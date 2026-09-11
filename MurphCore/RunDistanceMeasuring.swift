// MurphCore/RunDistanceMeasuring.swift
import Foundation

/// Measuring a run's distance, expressed without CoreLocation.
///
/// A second seam rather than an extension of `LocationProviding`, so
/// `WatchLocationController` does not grow a property it can never
/// meaningfully answer: the watch reads distance from HealthKit and its
/// location manager only powers the receiver.
///
/// **Receiver-on is not the same as measuring**, and keeping them apart is the
/// whole reason this protocol exists. `LocationPolicy` powers the receiver
/// during the pre-warm at rounds-remaining <= 1, which is *before* run 2
/// begins. Tying the measurement window to receiver power would put every step
/// taken around the pull-up bar during that pre-warm into run 2's distance.
@MainActor
protocol RunDistanceMeasuring: AnyObject {
    /// Metres measured in the current run. `nil` before any run has begun.
    var runDistanceMeters: Double? { get }

    /// A new run: clear the total and the anchor, start measuring.
    func beginRun()

    /// Resuming after a pause: keep the total, drop the anchor, start
    /// measuring. Dropping the anchor is what keeps the walk taken during the
    /// pause out of the run.
    func resumeRun()

    /// Stop measuring. `runDistanceMeters` stays readable, because the caller
    /// reads it when writing the `.runFinished` event.
    func stopMeasuring()
}

/// What `SessionEngine` needs from the phone's location stack: the lifecycle
/// (shared with the watch) and the measurement (phone-only).
typealias SessionLocation = LocationProviding & RunDistanceMeasuring
