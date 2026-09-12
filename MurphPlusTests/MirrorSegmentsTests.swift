// MurphPlusTests/MirrorSegmentsTests.swift
import XCTest
@testable import MurphPlus

final class MirrorSegmentsTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    private func spec(rounds: Int) -> TemplateSpec {
        TemplateSpec(
            id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
            totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: rounds
        )
    }

    private func started(rounds: Int, indoor: Bool = false) -> SessionEvent {
        .started(at: t(0), template: spec(rounds: rounds), vestOn: false, vestWeightLbs: nil, indoor: indoor)
    }

    // MARK: - Not started

    /// A session with no events at all must still hand back three rows — a
    /// missing row (or a crash reading empty `runSplits`) would make the
    /// ladder appear or jump the moment the workout starts.
    func test_notStartedSessionShowsThreeAheadRowsWithoutCrashing() {
        let segments = MirrorSegment.of(SessionState(), now: t(0))

        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments.map(\.label), ["Run 1", "Rounds", "Run 2"])
        for segment in segments {
            XCTAssertEqual(segment.state, .ahead)
            XCTAssertEqual(segment.value, "\u{2014}")
            XCTAssertNil(segment.detail)
            XCTAssertEqual(segment.fraction, 0)
        }
    }

    // MARK: - Mid run 1

    /// Run 1's live value must come from `currentPhaseStartedAt`, not from a
    /// split (there isn't one yet) — a regression here would show "—" for a
    /// run that is actually in progress.
    func test_midRun1ShowsRun1CurrentAndTheOthersAhead() {
        let state = SessionState.replay([started(rounds: 20)])
        let segments = MirrorSegment.of(state, now: t(522))

        XCTAssertEqual(segments[0].state, .current)
        XCTAssertEqual(segments[0].value, "8:42")
        XCTAssertEqual(segments[0].fraction, 1, accuracy: 0.0001)

        XCTAssertEqual(segments[1].state, .ahead)
        XCTAssertEqual(segments[1].value, "\u{2014}")
        XCTAssertEqual(segments[2].state, .ahead)
        XCTAssertEqual(segments[2].value, "\u{2014}")
    }

    // MARK: - Mid rounds, run 1 logged

    /// Exercises the brief's own worked example: "12 of 20 · 2:02 avg" while
    /// rounds are still in progress, with run 1 already showing as done.
    func test_midRoundsWithRun1LoggedShowsTheBriefsWorkedExample() {
        var events: [SessionEvent] = [
            started(rounds: 20),
            .runFinished(index: 1, at: t(500), distanceMeters: 1609.34),
        ]
        // 12 rounds, 122s (2:02) apart, so the average is a round number.
        for round in 1...12 {
            events.append(.roundCompleted(number: round, at: t(500 + 122 * Double(round))))
        }
        let state = SessionState.replay(events)
        // 50s into round 13.
        let now = t(500 + 122 * 12 + 50)
        let segments = MirrorSegment.of(state, now: now)

        XCTAssertEqual(segments[0].state, .done)
        XCTAssertEqual(segments[0].value, "8:20")
        XCTAssertEqual(segments[0].detail, "1.00 mi")

        XCTAssertEqual(segments[1].state, .current)
        XCTAssertEqual(segments[1].value, "25:14")
        XCTAssertEqual(segments[1].detail, "12 of 20 · 2:02 avg")

        XCTAssertEqual(segments[2].state, .ahead)
    }

    // MARK: - Mid run 2, both prior segments logged

    /// Once run 2 is under way, run 1 and rounds must both read as `.done`
    /// with real values — neither should regress back to "ahead" just
    /// because the workout has moved past them.
    func test_midRun2ShowsBothPriorSegmentsDone() {
        let events: [SessionEvent] = [
            started(rounds: 2),
            .runFinished(index: 1, at: t(500), distanceMeters: 1609.34),
            .roundCompleted(number: 1, at: t(600)),
            .roundCompleted(number: 2, at: t(700)),
        ]
        let state = SessionState.replay(events)
        let now = t(745)
        let segments = MirrorSegment.of(state, now: now)

        XCTAssertEqual(segments[0].state, .done)
        XCTAssertEqual(segments[0].value, "8:20")
        XCTAssertEqual(segments[0].detail, "1.00 mi")

        XCTAssertEqual(segments[1].state, .done)
        XCTAssertEqual(segments[1].value, "3:20")
        XCTAssertEqual(segments[1].detail, "2 rounds · 1:40 avg")

        XCTAssertEqual(segments[2].state, .current)
        XCTAssertEqual(segments[2].value, "0:45")
        XCTAssertNil(segments[2].detail)
    }

    // MARK: - Indoor run

    /// A logged run with no distance (indoor, or no fix) must show no
    /// distance detail at all — "0.00 mi" would misreport an unmeasured run
    /// as a measured, empty one.
    func test_indoorRunOmitsDistanceDetailRatherThanShowingZero() {
        let state = SessionState.replay([
            started(rounds: 20, indoor: true),
            .runFinished(index: 1, at: t(300), distanceMeters: nil),
        ])
        let segments = MirrorSegment.of(state, now: t(310))

        XCTAssertEqual(segments[0].state, .done)
        XCTAssertNil(segments[0].detail)
    }

    // MARK: - Paused session

    /// The in-progress segment's value must exclude a paused stretch — a
    /// regression here would let a pause inflate the live run-2 clock.
    func test_pausedSessionExcludesThePauseFromTheCurrentSegmentValue() {
        let state = SessionState.replay([
            started(rounds: 2),
            .runFinished(index: 1, at: t(300), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(400)),
            .roundCompleted(number: 2, at: t(500)),
            .paused(at: t(520)),
            .resumed(at: t(560)),
        ])
        let now = t(600)
        let segments = MirrorSegment.of(state, now: now)

        // 100s of wall clock since run 2 started, 40s of it paused.
        XCTAssertEqual(segments[2].state, .current)
        XCTAssertEqual(segments[2].value, "1:00")
    }

    // MARK: - Zero rounds complete

    /// Zero completed rounds must omit the average entirely — printing
    /// "0:00 avg" would read as a broken timer, not as "no data yet".
    func test_zeroRoundsCompleteOmitsTheAverageFromDetail() {
        let state = SessionState.replay([
            started(rounds: 20),
            .runFinished(index: 1, at: t(100), distanceMeters: nil),
        ])
        let segments = MirrorSegment.of(state, now: t(150))

        XCTAssertEqual(segments[1].state, .current)
        XCTAssertEqual(segments[1].detail, "0 of 20")
    }

    // MARK: - Fractions

    /// The three bars must never overshoot a whole progress bar's worth of
    /// width, even allowing for floating-point rounding across the phase
    /// boundaries.
    func test_fractionsSumToAtMostOne() {
        let state = SessionState.replay([
            started(rounds: 2),
            .runFinished(index: 1, at: t(500), distanceMeters: 1609.34),
            .roundCompleted(number: 1, at: t(600)),
            .roundCompleted(number: 2, at: t(700)),
        ])
        let segments = MirrorSegment.of(state, now: t(745))

        let total = segments.reduce(0) { $0 + $1.fraction }
        XCTAssertLessThanOrEqual(total, 1.0001)
        for segment in segments {
            XCTAssertGreaterThanOrEqual(segment.fraction, 0)
        }
    }
}
