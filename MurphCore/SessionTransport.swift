// MurphCore/SessionTransport.swift
import Foundation

/// The three sync channels, abstracted so the coordinators can be tested
/// against a fake. `WatchConnectivity` itself is verified by hand — it cannot
/// be meaningfully unit tested.
///
/// Deliberately send-only. It carried `onLiveEvent`, `onCheckpoint` and
/// `onContext` receive hooks that nothing in the app ever assigned — each side
/// receives through its own `WCSessionDelegate` instead — so they were three
/// pieces of API a reader had to trace to nowhere, and one of them was being
/// *called* from a closure that could never be set.
protocol SessionTransport: AnyObject {
    var isReachable: Bool { get }

    /// Fire-and-forget live mirror. Dropped silently when unreachable.
    func sendLive(_ event: SessionEvent, sessionID: UUID)

    /// Queued, guaranteed, survives termination and reboot.
    func transferCheckpoint(_ payload: SyncPayload)

    /// Latest-value-wins reference data.
    func updateContext(_ context: SyncContext)
}
