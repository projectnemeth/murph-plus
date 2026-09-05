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
            let url = Self.stagingDirectory
                .appendingPathComponent("checkpoint-\(payload.sessionID)-\(payload.checkpointSeq).json")
            do {
                try FileManager.default.createDirectory(
                    at: Self.stagingDirectory, withIntermediateDirectories: true
                )
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

    /// Oversize checkpoints are staged here rather than loose in `tmp`.
    ///
    /// A directory of our own is what makes the cleanup safe to write at all:
    /// the sweep below deletes files it did not create only if it cannot tell
    /// them apart, and `didFinish` can check that the URL it is handed is
    /// really ours before removing it. Prefix-matching filenames in the shared
    /// temporary directory could not offer either guarantee.
    static let stagingDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("checkpoint-staging", isDirectory: true)

    /// Removes staged files that no transfer is waiting on.
    ///
    /// A staged file is deleted when its transfer finishes — but if the Watch
    /// app is killed mid-transfer that callback never comes, and the file stays
    /// on disk for the life of the install. Each is a whole journal, so they
    /// are not small.
    ///
    /// Runs after activation, because `outstandingFileTransfers` is what makes
    /// it safe: a queued transfer that has not been delivered yet still needs
    /// its file, and this is the difference between cleaning up and losing the
    /// checkpoint that completes a workout.
    private func sweepStagedCheckpoints() {
        let manager = FileManager.default
        guard
            let staged = try? manager.contentsOfDirectory(
                at: Self.stagingDirectory, includingPropertiesForKeys: nil
            )
        else { return }

        let pending = Set(
            WCSession.default.outstandingFileTransfers.map(\.file.fileURL.standardizedFileURL)
        )
        var removed = 0
        for url in staged where !pending.contains(url.standardizedFileURL) {
            if (try? manager.removeItem(at: url)) != nil { removed += 1 }
        }
        if removed > 0 {
            SyncLog.note("swept \(removed) staged checkpoint file(s) left by an interrupted transfer")
        }
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
        Task { @MainActor in
            self.decodeStoredContext()
            self.sweepStagedCheckpoints()
        }
    }

    nonisolated func session(
        _ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext[SyncKey.context] as? Data else { return }
        Task { @MainActor in
            guard let decoded = try? JSONDecoder().decode(SyncContext.self, from: data) else { return }
            self.context = decoded
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

        // Only ever our own staging directory. Whether `fileTransfer.file.fileURL`
        // is the URL we handed over or a system-owned copy is not documented,
        // and deleting something belonging to WatchConnectivity would fail
        // silently in exactly the place this app can least afford silence.
        let url = fileTransfer.file.fileURL.standardizedFileURL
        guard url.path.hasPrefix(Self.stagingDirectory.standardizedFileURL.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
