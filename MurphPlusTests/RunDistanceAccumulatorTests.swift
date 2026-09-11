// MurphPlusTests/RunDistanceAccumulatorTests.swift
import XCTest
@testable import MurphPlus

/// The only numerically load-bearing type in the GPS feature, so it is tested
/// against traces rather than single calls: the bugs that matter here are
/// about how a *sequence* of samples accumulates, not about one delta.
final class RunDistanceAccumulatorTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    /// ~0.000009 degrees of latitude is ~1 metre. Walking due north keeps the
    /// longitude term out of the arithmetic, so expected values stay legible.
    private func sample(
        northMetres: Double, at second: TimeInterval,
        accuracy: Double = 5, speed: Double = 3
    ) -> LocationSample {
        LocationSample(
            latitude: 51.5 + (northMetres / 111_320.0),
            longitude: -0.12,
            horizontalAccuracy: accuracy,
            speed: speed,
            timestamp: base.addingTimeInterval(second)
        )
    }

    /// Feeds a trace, treating each sample as arriving exactly on time.
    private func feed(_ samples: [LocationSample], into acc: inout RunDistanceAccumulator) {
        for s in samples { acc.add(s, now: s.timestamp) }
    }

    func test_straightLineTrace_sumsToKnownLength() {
        var acc = RunDistanceAccumulator()
        // 10 samples, 20 m apart, 5 s apart: 4 m/s, 180 m of travel after the
        // first sample is consumed as the anchor.
        let trace = (0..<10).map { sample(northMetres: Double($0) * 20, at: Double($0) * 5) }
        feed(trace, into: &acc)

        XCTAssertEqual(acc.totalMeters, 180, accuracy: 2)
    }

    func test_stationaryJitter_accumulatesNothing() {
        var acc = RunDistanceAccumulator()
        // Jitter of ±2 m with 5 m accuracy: every delta is under the floor.
        let trace: [LocationSample] = (0..<20).map {
            sample(northMetres: $0 % 2 == 0 ? 0 : 2, at: Double($0) * 2, speed: 0)
        }
        feed(trace, into: &acc)

        XCTAssertEqual(acc.totalMeters, 0, accuracy: 0.001)
    }

    func test_cachedFirstFix_producesNoPhantomJump() {
        var acc = RunDistanceAccumulator()
        // The classic CoreLocation opener: a fix 10 minutes old, 2 km away.
        let stale = LocationSample(
            latitude: 51.52, longitude: -0.12, horizontalAccuracy: 5,
            speed: -1, timestamp: base.addingTimeInterval(-600)
        )
        acc.add(stale, now: base)
        feed([sample(northMetres: 0, at: 0), sample(northMetres: 20, at: 5)], into: &acc)

        XCTAssertEqual(acc.totalMeters, 20, accuracy: 2)
    }

    func test_invalidAccuracy_isRejected() {
        var acc = RunDistanceAccumulator()
        feed([sample(northMetres: 0, at: 0)], into: &acc)
        acc.add(sample(northMetres: 500, at: 5, accuracy: -1), now: base.addingTimeInterval(5))

        XCTAssertEqual(acc.totalMeters, 0, accuracy: 0.001)
    }

    func test_poorAccuracy_isRejected() {
        var acc = RunDistanceAccumulator()
        feed([sample(northMetres: 0, at: 0)], into: &acc)
        acc.add(sample(northMetres: 100, at: 5, accuracy: 75), now: base.addingTimeInterval(5))

        XCTAssertEqual(acc.totalMeters, 0, accuracy: 0.001)
    }

    func test_impossibleSpeed_isRejected() {
        var acc = RunDistanceAccumulator()
        feed([sample(northMetres: 0, at: 0)], into: &acc)
        // 5 km in 5 s. Reported speed is left plausible so the IMPLIED-speed
        // rule is the one under test.
        acc.add(sample(northMetres: 5000, at: 5, speed: 4), now: base.addingTimeInterval(5))

        XCTAssertEqual(acc.totalMeters, 0, accuracy: 0.001)
    }

    func test_outOfOrderSample_isRejected() {
        var acc = RunDistanceAccumulator()
        feed([sample(northMetres: 0, at: 10), sample(northMetres: 40, at: 15)], into: &acc)
        let before = acc.totalMeters
        // Same wall clock, earlier timestamp than the anchor.
        acc.add(sample(northMetres: 80, at: 12), now: base.addingTimeInterval(15))

        XCTAssertEqual(acc.totalMeters, before, accuracy: 0.001)
    }

    /// THE REGRESSION THAT MATTERS. A rejected sample must not become the new
    /// anchor. If it does, slow movement is permanently invisible: every
    /// individual delta falls under the floor, is dropped, and the anchor
    /// chases the walker at exactly the speed that guarantees nothing counts.
    func test_rejectedSampleDoesNotMoveAnchor_soSlowMovementStillAccumulates() {
        var acc = RunDistanceAccumulator()
        // 1 m every 2 s for 60 s. Each step is under the 3 m floor, so every
        // sample after the anchor is individually rejected — but the distance
        // from the ANCHOR crosses the floor every few samples.
        let trace = (0..<30).map { sample(northMetres: Double($0), at: Double($0) * 2, speed: 0.5) }
        feed(trace, into: &acc)

        XCTAssertGreaterThan(acc.totalMeters, 20, "slow movement accumulated nothing — the anchor is being moved on rejection")
        XCTAssertLessThan(acc.totalMeters, 35)
    }

    func test_reset_clearsTotalAndAnchor() {
        var acc = RunDistanceAccumulator()
        feed([sample(northMetres: 0, at: 0), sample(northMetres: 40, at: 5)], into: &acc)
        XCTAssertGreaterThan(acc.totalMeters, 0)

        acc.reset()
        XCTAssertEqual(acc.totalMeters, 0, accuracy: 0.001)

        // Anchor cleared too: the next sample is consumed as a new anchor and
        // adds nothing, rather than measuring back to the pre-reset position.
        acc.add(sample(northMetres: 100, at: 10), now: base.addingTimeInterval(10))
        XCTAssertEqual(acc.totalMeters, 0, accuracy: 0.001)
    }

    func test_resetAnchor_keepsTotalButDropsTheGap() {
        var acc = RunDistanceAccumulator()
        feed([sample(northMetres: 0, at: 0), sample(northMetres: 40, at: 5)], into: &acc)
        let banked = acc.totalMeters

        // The pause: the user walks 200 m to a water fountain and back.
        acc.resetAnchor()
        acc.add(sample(northMetres: 240, at: 300), now: base.addingTimeInterval(300))

        XCTAssertEqual(acc.totalMeters, banked, accuracy: 0.001, "the walk during the pause landed in the run")
    }

    func test_haversine_matchesKnownDistance() {
        // London (51.5007, -0.1246) to Paris (48.8584, 2.2945): ~343 km.
        let london = LocationSample(latitude: 51.5007, longitude: -0.1246, horizontalAccuracy: 5, speed: 0, timestamp: Date())
        let paris = LocationSample(latitude: 48.8584, longitude: 2.2945, horizontalAccuracy: 5, speed: 0, timestamp: Date())

        XCTAssertEqual(RunDistanceAccumulator.distance(from: london, to: paris), 343_000, accuracy: 3_000)
    }
}
