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
    func transferCheckpoint(_ payload: SyncPayload) {
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(payload) else { return }
        WCSession.default.transferUserInfo([SyncKey.payload: data])
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
}
