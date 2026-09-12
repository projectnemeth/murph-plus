// MurphPlusTests/RunHeroMetricTests.swift
import XCTest
@testable import MurphPlus

final class RunHeroMetricTests: XCTestCase {

    /// Indoor must outrank every other input, exactly as `RunModeStatus` does
    /// for its own caption — a leaked distance figure or progress bar on the
    /// indoor path would report on a receiver that was never running.
    func test_indoorBeatsEveryCombinationOfOtherInputs() {
        let combinations: [(distanceIsTrustworthy: Bool, distanceMeters: Double?, targetMiles: Double?)] = [
            (true, 1_609.34, 1.0),
            (true, nil, 1.0),
            (false, 1_609.34, 1.0),
            (false, nil, nil),
            (true, 0, nil),
        ]
        for combination in combinations {
            let metric = RunHeroMetric.of(
                indoor: true,
                distanceIsTrustworthy: combination.distanceIsTrustworthy,
                distanceMeters: combination.distanceMeters,
                targetMiles: combination.targetMiles,
                elapsedSeconds: 66
            )
            XCTAssertEqual(metric.kind, .elapsed)
            XCTAssertEqual(metric.label, "Elapsed")
            XCTAssertEqual(metric.value, "1:06")
            XCTAssertEqual(metric.caption, "Indoor \u{00b7} distance not measured")
            XCTAssertNil(metric.progress)
            XCTAssertEqual(metric.accessibilityText, "Elapsed 1:06. Indoor, distance not measured.")
        }
    }

    /// An untrustworthy fix must fall back to the elapsed hero even though a
    /// distance figure exists — a jumpy reading rendered as a giant confident
    /// numeral would be worse than no numeral at all. Its caption must NOT
    /// claim to be waiting for GPS: this is the regression a resumed mid-run
    /// session hits. `SessionEngine` marks a session untrustworthy at launch
    /// whenever it relaunches mid-run (`runDistanceUntrustworthy =
    /// isRun(state.phase)` at init) and only clears the flag inside
    /// `beginRun()`, at the START of the NEXT run leg — so for the rest of
    /// THIS leg, GPS is perfectly healthy and simply has nothing to recover.
    /// "Waiting for GPS…" here would promise a fix that is never coming for
    /// the whole mile.
    func test_untrustworthyDistanceFallsBackToElapsedWithoutClaimingGPSIsPending() {
        let metric = RunHeroMetric.of(
            indoor: false,
            distanceIsTrustworthy: false,
            distanceMeters: 1_609.34,
            targetMiles: 1.0,
            elapsedSeconds: 66
        )
        XCTAssertEqual(metric.kind, .elapsed)
        XCTAssertEqual(metric.value, "1:06")
        XCTAssertEqual(metric.caption, "Distance not recorded for this run")
        XCTAssertNil(metric.progress)
        XCTAssertEqual(metric.accessibilityText, "Elapsed 1:06. Distance not recorded for this run.")
    }

    /// An untrustworthy fix outranks `distanceMeters == nil`: even when no
    /// figure exists yet, an untrustworthy session must still get the "not
    /// recorded" caption, not "Waiting for GPS…" — the two conditions can
    /// coincide (nothing has ever been measured on this leg) and the more
    /// specific truth must win.
    func test_untrustworthyBeatsNilMeters() {
        let metric = RunHeroMetric.of(
            indoor: false,
            distanceIsTrustworthy: false,
            distanceMeters: nil,
            targetMiles: 1.0,
            elapsedSeconds: 66
        )
        XCTAssertEqual(metric.kind, .elapsed)
        XCTAssertEqual(metric.caption, "Distance not recorded for this run")
        XCTAssertNil(metric.progress)
    }

    /// `distanceMeters == nil` must fall back to elapsed even when the fix is
    /// trustworthy — there is simply no figure yet to show, trustworthy or
    /// not, and this is the one case that could tempt formatting `nil` as 0.
    func test_nilMetersWithTrustworthyFixFallsBackToElapsed() {
        let metric = RunHeroMetric.of(
            indoor: false,
            distanceIsTrustworthy: true,
            distanceMeters: nil,
            targetMiles: 1.0,
            elapsedSeconds: 66
        )
        XCTAssertEqual(metric.kind, .elapsed)
        XCTAssertEqual(metric.caption, "Waiting for GPS\u{2026}")
        XCTAssertNil(metric.progress)
    }

    /// The normal case: a trustworthy fix with a distance and a target should
    /// produce the distance hero, with the miles figure unsuffixed (the unit
    /// renders separately) and the caption/progress derived from the target.
    func test_normalDistanceCaseProducesDistanceHero() {
        let metric = RunHeroMetric.of(
            indoor: false,
            distanceIsTrustworthy: true,
            distanceMeters: 193.12, // ~0.12 mi
            targetMiles: 0.25,
            elapsedSeconds: 66
        )
        XCTAssertEqual(metric.kind, .distance)
        XCTAssertEqual(metric.label, "Distance")
        XCTAssertEqual(metric.value, "0.12")
        XCTAssertEqual(metric.caption, "MI OF 0.25")
        XCTAssertEqual(metric.progress ?? -1, 0.12 / 0.25, accuracy: 0.0001)
        XCTAssertEqual(metric.accessibilityText, "Distance 0.12 of 0.25 miles")
    }

    /// `targetMiles == nil` must not crash and must not draw a bar — a runner
    /// who started a free run (no template) has nothing to divide against.
    func test_nilTargetProducesNoBarAndBareCaption() {
        let metric = RunHeroMetric.of(
            indoor: false,
            distanceIsTrustworthy: true,
            distanceMeters: 193.12,
            targetMiles: nil,
            elapsedSeconds: 66
        )
        XCTAssertEqual(metric.caption, "MI")
        XCTAssertNil(metric.progress)
        XCTAssertEqual(metric.accessibilityText, "Distance 0.12 miles")
    }

    /// A zero (or negative) target must not divide-by-zero and must not draw
    /// a bar — this is the regression a naive `miles / targetMiles` would hit
    /// the moment a target of 0 slipped through instead of being treated as
    /// "no target."
    func test_zeroTargetDoesNotDivideAndDrawsNoBar() {
        let zero = RunHeroMetric.of(
            indoor: false,
            distanceIsTrustworthy: true,
            distanceMeters: 193.12,
            targetMiles: 0,
            elapsedSeconds: 66
        )
        XCTAssertEqual(zero.caption, "MI")
        XCTAssertNil(zero.progress)

        let negative = RunHeroMetric.of(
            indoor: false,
            distanceIsTrustworthy: true,
            distanceMeters: 193.12,
            targetMiles: -1,
            elapsedSeconds: 66
        )
        XCTAssertEqual(negative.caption, "MI")
        XCTAssertNil(negative.progress)
    }

    /// Overshooting the target must clamp the bar at 1.0, never past it — an
    /// unclamped `miles / targetMiles` would push the bar off the end of its
    /// track once a runner ran past their target distance.
    func test_overshootClampsProgressToOne() {
        let metric = RunHeroMetric.of(
            indoor: false,
            distanceIsTrustworthy: true,
            distanceMeters: 3_218.68, // ~2.00 mi
            targetMiles: 1.0,
            elapsedSeconds: 66
        )
        XCTAssertEqual(metric.progress ?? -1, 1.0, accuracy: 0.0001)
    }

    /// A plain midpoint, asserted on its own, so the clamp logic above isn't
    /// the only thing exercising the progress computation — half of a target
    /// should read as exactly half, not clamped or rounded away.
    func test_progressAtAPlainMidpoint() {
        let metric = RunHeroMetric.of(
            indoor: false,
            distanceIsTrustworthy: true,
            distanceMeters: 804.67, // ~0.50 mi
            targetMiles: 1.0,
            elapsedSeconds: 66
        )
        XCTAssertEqual(metric.progress ?? -1, 0.5, accuracy: 0.0001)
    }
}
