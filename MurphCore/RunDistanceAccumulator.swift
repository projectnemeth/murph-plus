// MurphCore/RunDistanceAccumulator.swift
import Foundation

/// Turns a stream of GPS samples into a distance, in metres.
///
/// Pure: no hardware, no I/O, no clock of its own. `now` is a parameter for
/// the same reason it is on `SessionStateMachine.start` and
/// `SessionDerivation.elapsed` — it keeps the type testable and the sample-age
/// rule exercisable without waiting.
///
/// The phone needs this and the watch does not, because there is no
/// `HKLiveWorkoutBuilder` on iOS: `distanceWalkingRunning` on an iPhone is the
/// pedometer stride estimate with no location in it, which is the mechanism
/// that read 0.46 miles on a 0.72 mile route. There is no fusion to defer to
/// here, so distance is derived.
struct RunDistanceAccumulator {
    /// Same VALUE as the watch's gate threshold, deliberately a separate
    /// constant: the gate asks "is the receiver warm yet", this asks "is this
    /// delta trustworthy". They will want tuning independently.
    static let maxAccuracyMeters: Double = 20
    /// `startUpdatingLocation` hands back a cached fix first, sometimes
    /// minutes old and hundreds of metres away. Unfiltered that single sample
    /// is a phantom half-kilometre at the start of every run.
    static let maxSampleAgeSeconds: TimeInterval = 5
    /// Roughly world-record sprint pace, so it catches teleports and nothing
    /// a runner can actually do.
    static let maxSpeedMetersPerSecond: Double = 12
    /// The floor below which a delta is assumed to be noise rather than
    /// movement. Applied as `max(accuracy, this)`, so it only binds when the
    /// fix is better than the floor.
    static let minimumDeltaMeters: Double = 3

    private static let earthRadiusMeters: Double = 6_371_008.8

    private(set) var totalMeters: Double = 0
    private var anchor: LocationSample?

    /// Whether any sample has passed the quality filters yet.
    ///
    /// Distinguishes "measuring, nothing moved yet" (0 m, honest) from "nothing
    /// usable has arrived at all" (no number, also honest). A caller that
    /// reported 0 for the second case would be publishing a measurement it
    /// never made — the exact failure this whole feature exists to remove.
    var hasAcceptedSample: Bool { anchor != nil }

    /// A new run: clear the total and the anchor.
    mutating func reset() {
        totalMeters = 0
        anchor = nil
    }

    /// Resuming after a pause: keep the total, drop the anchor.
    ///
    /// Dropping the anchor is the load-bearing half. If it survived the pause,
    /// the first sample after resume would measure its delta from where the
    /// user stood when they paused — so a walk to the water fountain lands in
    /// the run as one lump. A pause should be a genuine gap, consistent with
    /// the run's duration, which is net of pause everywhere else in this app.
    mutating func resetAnchor() {
        anchor = nil
    }

    /// - Returns: the running total after considering `sample`, accepted or not.
    @discardableResult
    mutating func add(_ sample: LocationSample, now: Date) -> Double {
        // The sign of `horizontalAccuracy` is the validity flag, so this must
        // come before the threshold comparison.
        guard sample.horizontalAccuracy >= 0,
              sample.horizontalAccuracy <= Self.maxAccuracyMeters
        else { return totalMeters }

        guard now.timeIntervalSince(sample.timestamp) <= Self.maxSampleAgeSeconds else {
            return totalMeters
        }

        // A negative reported speed means unavailable, not slow.
        guard sample.speed < 0 || sample.speed <= Self.maxSpeedMetersPerSecond else {
            return totalMeters
        }

        guard let anchor else {
            self.anchor = sample
            return totalMeters
        }

        let interval = sample.timestamp.timeIntervalSince(anchor.timestamp)
        guard interval > 0 else { return totalMeters }

        let delta = Self.distance(from: anchor, to: sample)
        guard delta / interval <= Self.maxSpeedMetersPerSecond else { return totalMeters }

        // The movement has to exceed its own uncertainty.
        guard delta > max(sample.horizontalAccuracy, Self.minimumDeltaMeters) else {
            // NOTE: the anchor is deliberately NOT updated here. Keeping the
            // last ACCEPTED point is what lets slow movement accumulate across
            // several samples. Move the anchor on rejection and every delta
            // falls under the floor forever: a fast run reads roughly right
            // and a slow one reads zero.
            return totalMeters
        }

        totalMeters += delta
        self.anchor = sample
        return totalMeters
    }

    /// Haversine on a sphere, rather than `CLLocation.distance(from:)`, because
    /// the entire point of `LocationSample` is that `MurphCore` never imports
    /// CoreLocation.
    static func distance(from a: LocationSample, to b: LocationSample) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusMeters * asin(min(1, sqrt(h)))
    }
}
