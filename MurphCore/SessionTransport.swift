// MurphCore/SessionTransport.swift
import Foundation

/// The three sync channels, abstracted so the coordinators can be tested
/// against a fake. `WatchConnectivity` itself is verified by hand — it cannot
/// be meaningfully unit tested.
protocol SessionTransport: AnyObject {
    var isReachable: Bool { get }

    /// Fire-and-forget live mirror. Dropped silently when unreachable.
    func sendLive(_ event: SessionEvent, sessionID: UUID)

    /// Queued, guaranteed, survives termination and reboot.
    func transferCheckpoint(_ payload: SyncPayload)

    /// Latest-value-wins reference data.
    func updateContext(_ context: SyncContext)

    var onLiveEvent: ((UUID, SessionEvent) -> Void)? { get set }
    var onCheckpoint: ((SyncPayload) -> Void)? { get set }
    var onContext: ((SyncContext) -> Void)? { get set }
}
