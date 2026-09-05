// MurphPlusWatch/Sync/WatchSyncCoordinator.swift
import Foundation
import Observation
import WatchConnectivity

/// The Watch's concrete `SessionTransport`.
///
/// Talks to `WCSession` directly rather than through another seam: the
/// protocol exists so `WatchSessionController` can be exercised against a
/// fake, and this class is the part that by definition cannot be — it is
/// verified by the Task 7 hardware matrix instead.
@Observable
@MainActor
final class WatchSyncCoordinator: NSObject, SessionTransport {
    /// Latest template list and personal bests pushed down by the phone.
    private(set) var context: SyncContext?

    var onLiveEvent: ((UUID, SessionEvent) -> Void)?
    var onCheckpoint: ((SyncPayload) -> Void)?
    var onContext: ((SyncContext) -> Void)?

    var isReachable: Bool {
        WCSession.isSupported() && WCSession.default.isReachable
    }

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        decodeStoredContext()
    }

    /// Fire-and-forget. Dropped silently when the phone is unreachable — the
    /// phone's mirror simply goes stale and says so, which is the honest
    /// outcome. Nothing about the workout depends on this landing.
    func sendLive(_ event: SessionEvent, sessionID: UUID) {
        guard isReachable, let data = try? JSONEncoder().encode(event) else { return }
        WCSession.default.sendMessage(
            [SyncKey.liveEvent: data, SyncKey.liveSessionID: sessionID.uuidString],
            replyHandler: nil,
            errorHandler: nil
        )
    }

    /// Queued and guaranteed: survives app termination, and reboot of either
    /// device. This is the channel the session's durability rests on.
    ///
    /// `activationState` is part of the guard, matching `PhoneSyncCoordinator`.
    /// `activate()` is called in `init` but completes asynchronously through the
    /// delegate, so a user who launches the Watch app and taps Start inside that
    /// window — ordinary on a cold launch — would otherwise reach
    /// `transferUserInfo` on a session that is still `.notActivated`. Apple's
    /// contract is to activate and wait; the documented behaviour is an
    /// exception, and the benign reading still silently loses the session's
    /// *first* checkpoint.
    ///
    /// **Every exit from this method now says so.** It had three silent ones,
    /// and that `activationState` guard was the prime suspect for a finished
    /// workout that never reached the phone across a reboot: if the Watch's
    /// session was not activated during the phone-off window, every checkpoint
    /// was dropped without a word. A guard that discards the session's most
    /// important checkpoint in silence is the same failure class the rest of
    /// this file exists to abolish — reintroduced, by a fix for something else,
    /// and invisible until a hardware test went looking.
    func transferCheckpoint(_ payload: SyncPayload) {
        let sessionID = payload.sessionID
        let seq = payload.checkpointSeq

        guard WCSession.isSupported() else {
            SyncLog.checkpointDropped(
                sessionID: sessionID, seq: seq, reason: "WCSession is not supported"
            )
            return
        }

        let state = WCSession.default.activationState
        guard state == .activated else {
            SyncLog.checkpointDropped(
                sessionID: sessionID, seq: seq,
                reason: "WCSession is \(Self.name(of: state)), not activated"
            )
            return
        }

        guard let data = try? JSONEncoder().encode(payload) else {
            SyncLog.checkpointDropped(
                sessionID: sessionID, seq: seq,
                reason: "payload could not be encoded (\(payload.events.count) events)"
            )
            return
        }

        let reachable = WCSession.default.isReachable

        guard data.count < SyncPayload.userInfoByteLimit else {
            // Same guarantee, no ceiling. The oversize case is the *final*
            // checkpoint of a long workout — the one that marks it complete —
            // so dropping it would lose the whole session on the phone.
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("checkpoint-\(payload.sessionID)-\(payload.checkpointSeq).json")
            do {
                try data.write(to: url)
            } catch {
                SyncLog.checkpointDropped(
                    sessionID: sessionID, seq: seq,
                    reason: "could not be staged for file transfer — \(error.localizedDescription)"
                )
                return
            }
            WCSession.default.transferFile(url, metadata: nil)
            SyncLog.checkpointSent(
                sessionID: sessionID, seq: seq, bytes: data.count,
                carrier: .file, reachable: reachable
            )
            return
        }

        WCSession.default.transferUserInfo([SyncKey.payload: data])
        SyncLog.checkpointSent(
            sessionID: sessionID, seq: seq, bytes: data.count,
            carrier: .userInfo, reachable: reachable
        )
    }

    /// `WCSessionActivationState` has no useful description, and the raw value
    /// alone sends the reader to the headers mid-diagnosis.
    private static func name(of state: WCSessionActivationState) -> String {
        switch state {
        case .notActivated: "not activated"
        case .inactive: "inactive"
        case .activated: "activated"
        @unknown default: "unknown (\(state.rawValue))"
        }
    }

    /// Watch → phone context is never sent; the reference data flows the other
    /// way. Present only to satisfy the shared transport protocol.
    func updateContext(_ context: SyncContext) {}

    private func decodeStoredContext() {
        guard
            WCSession.isSupported(),
            let data = WCSession.default.receivedApplicationContext[SyncKey.context] as? Data
        else { return }
        context = try? JSONDecoder().decode(SyncContext.self, from: data)
    }
}

extension WatchSyncCoordinator: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in self.decodeStoredContext() }
    }

    nonisolated func session(
        _ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext[SyncKey.context] as? Data else { return }
        Task { @MainActor in
            guard let decoded = try? JSONDecoder().decode(SyncContext.self, from: data) else { return }
            self.context = decoded
            self.onContext?(decoded)
        }
    }

    /// Was silent before: an oversize or rejected transfer simply vanished,
    /// and the payload most likely to be oversize is the one that completes
    /// the session.
    ///
    /// Success is logged too, and it is not redundant with `checkpointSent`:
    /// that one records the hand-off to the queue, this one records the queue
    /// actually draining. A workout whose checkpoints are all "sent" and none
    /// "delivered" is a different bug from one where nothing was sent at all.
    nonisolated func session(
        _ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?
    ) {
        if let error {
            SyncLog.failure("userInfo transfer failed — \(error.localizedDescription)")
        } else {
            SyncLog.note("userInfo transfer delivered")
        }
    }

    /// WatchConnectivity takes its own copy of the file when the transfer is
    /// handed off; ours is scratch space that must be cleaned up here, whether
    /// or not the transfer succeeded, or it accumulates one file per oversize
    /// checkpoint.
    nonisolated func session(
        _ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?
    ) {
        if let error {
            SyncLog.failure("file transfer failed — \(error.localizedDescription)")
        } else {
            SyncLog.note("file transfer delivered")
        }
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }
}
