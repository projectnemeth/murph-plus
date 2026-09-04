// MurphCore/WorkoutControlling.swift
import Foundation

/// The HealthKit side of a live session, expressed without HealthKit.
///
/// `WatchSessionController` owns the journal and the state machine; everything
/// it needs from `HKWorkoutSession`/`HKLiveWorkoutBuilder` is exactly the
/// surface below. Keeping that surface a protocol does two things: it lets the
/// controller be exercised from the iOS test bundle (the watch target has no
/// test bundle of its own), and it keeps HealthKit out of `MurphCore`, which
/// imports Foundation and nothing else.
///
/// Every member here is optional to the app functioning. A conforming type
/// whose authorization was denied — or that has no session at all — must
/// no-op rather than fail, so a complete workout is still possible with no
/// heart rate and no distance.
@MainActor
protocol WorkoutControlling: AnyObject {
    /// Most recent sample, for live display only. `nil` until one arrives.
    var currentHeartRate: Int? { get }
    /// Distance covered during the *current run*, not the whole workout.
    /// `nil` outside a run.
    var currentRunDistanceMeters: Double? { get }
    /// Throttled sample callback; the caller journals each one.
    var onHeartRate: ((Int) -> Void)? { get set }

    func requestAuthorization() async

    func start(indoor: Bool) async

    /// Reattaches to a session watchOS kept alive across an app relaunch.
    /// Returns `false` if there was nothing to recover.
    func recover(indoor: Bool) async -> Bool

    /// Marks the current segment as a run.
    ///
    /// - Parameter resetDistanceBaseline: `true` when a run is genuinely
    ///   beginning, so the distance already banked by earlier segments is
    ///   subtracted out. `false` when re-issuing the segment for a run that
    ///   was *already* under way — relaunch recovery — where the builder still
    ///   holds the distance covered before the relaunch and re-snapshotting
    ///   would zero it away mid-run.
    func beginRunActivity(resetDistanceBaseline: Bool)

    /// Marks the current segment as the calisthenics rounds.
    func beginRoundsActivity()

    func pause()
    func resume()
    func finish() async
}
