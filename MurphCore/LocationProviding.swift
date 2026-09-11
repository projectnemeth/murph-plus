// MurphCore/LocationProviding.swift
import Foundation

/// How usable the GPS fix currently is.
///
/// `.denied` is deliberately separate from `.off`: it is the one state where
/// waiting for a fix is waiting for something that will never arrive, and the
/// start gate branches on exactly that.
enum GPSFixState: Equatable {
    /// Not updating — indoor, mid-rounds, or never started.
    case off
    /// Refused or restricted. A fix will never come.
    case denied
    /// Updating, but no sample yet at usable accuracy.
    case acquiring
    /// A sample at or better than the accuracy threshold has arrived.
    case fixed
}

/// The GPS side of a session, expressed without CoreLocation.
///
/// Separate from `WorkoutControlling` rather than folded into it because the
/// two have different lifetimes: this one starts warming on the *setup*
/// screen, when there is no `HKWorkoutSession` to wrap and every method on
/// `WorkoutControlling` is contractually a no-op. Keeping it a protocol also
/// keeps CoreLocation out of `MurphCore` and lets the whole lifecycle be
/// exercised from the iOS test bundle — the watch target has none of its own.
///
/// Both `startUpdating` and `stopUpdating` MUST be idempotent. That is what
/// lets callers assert the desired state unconditionally instead of tracking
/// whether they already asked, which is what keeps `LocationPolicy` a pure
/// function rather than a second state machine.
@MainActor
protocol LocationProviding: AnyObject {
    var fixState: GPSFixState { get }

    /// Asks for When In Use. Returns once the request has been made — the
    /// answer arrives later via `fixState`, because CoreLocation reports
    /// authorization through a delegate callback, not a return value.
    func requestAuthorization() async

    func startUpdating()
    func stopUpdating()
}
