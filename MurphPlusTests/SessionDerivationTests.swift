// MurphPlusTests/SessionDerivationTests.swift
import XCTest
@testable import MurphPlus

final class SessionDerivationTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    private let spec = TemplateSpec(
        id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
        totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 3
    )

    private var startedEvent: SessionEvent {
        .started(at: t(0), template: spec, vestOn: false, vestWeightLbs: nil, indoor: false)
    }

    // MARK: - Elapsed

    func test_elapsedOnARunningSessionCountsToNow() {
        let state = SessionState.replay([startedEvent])

        XCTAssertEqual(SessionDerivation.elapsed(state, now: t(300)), 300, accuracy: 0.001)
    }

    func test_elapsedExcludesPausedTime() {
        let state = SessionState.replay([
            startedEvent,
            .paused(at: t(100)),
            .resumed(at: t(400)),
        ])

        // 500s of wall clock, 300s paused.
        XCTAssertEqual(SessionDerivation.elapsed(state, now: t(500)), 200, accuracy: 0.001)
    }

    func test_elapsedStopsCountingWhilePaused() {
        let state = SessionState.replay([startedEvent, .paused(at: t(100))])

        XCTAssertEqual(SessionDerivation.elapsed(state, now: t(400)), 100, accuracy: 0.001)
        XCTAssertEqual(SessionDerivation.elapsed(state, now: t(900)), 100, accuracy: 0.001)
    }

    func test_elapsedOnACompletedSessionIgnoresNow() {
        let state = SessionState.replay([
            startedEvent,
            .runFinished(index: 1, at: t(100), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(200)),
            .roundCompleted(number: 2, at: t(300)),
            .roundCompleted(number: 3, at: t(400)),
            .runFinished(index: 2, at: t(500), distanceMeters: nil),
        ])

        XCTAssertEqual(SessionDerivation.elapsed(state, now: t(99_999)), 500, accuracy: 0.001)
    }

    func test_elapsedIsZeroBeforeStarting() {
        XCTAssertEqual(SessionDerivation.elapsed(SessionState(), now: t(500)), 0, accuracy: 0.001)
    }

    // MARK: - Round durations

    func test_roundDurationsMeasureFromTheRoundsPhaseStart() {
        let state = SessionState.replay([
            startedEvent,
            .runFinished(index: 1, at: t(500), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(560)),
            .roundCompleted(number: 2, at: t(650)),
            .roundCompleted(number: 3, at: t(700)),
        ])

        let durations = SessionDerivation.roundDurations(state)

        XCTAssertEqual(durations.count, 3)
        XCTAssertEqual(durations[0], 60, accuracy: 0.001)
        XCTAssertEqual(durations[1], 90, accuracy: 0.001)
        XCTAssertEqual(durations[2], 50, accuracy: 0.001)
    }

    /// THE test this whole task exists for. A pause inside round 2 must be
    /// charged to round 2 and to no other round — otherwise the fatigue fit
    /// reads a ten-minute round and predicts nonsense.
    func test_pauseInsideARoundIsSubtractedFromThatRoundOnly() {
        let state = SessionState.replay([
            startedEvent,
            .runFinished(index: 1, at: t(500), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(560)),
            .paused(at: t(580)),
            .resumed(at: t(1180)),          // a ten-minute interruption
            .roundCompleted(number: 2, at: t(1240)),
            .roundCompleted(number: 3, at: t(1300)),
        ])

        let durations = SessionDerivation.roundDurations(state)

        XCTAssertEqual(durations[0], 60, accuracy: 0.001, "Round 1 predates the pause")
        XCTAssertEqual(durations[1], 80, accuracy: 0.001, "680s of wall time minus 600s paused")
        XCTAssertEqual(durations[2], 60, accuracy: 0.001, "Round 3 postdates the pause")
    }

    func test_pauseSpanningARoundBoundaryIsSplitAcrossBothRounds() {
        let state = SessionState.replay([
            startedEvent,
            .runFinished(index: 1, at: t(500), distanceMeters: nil),
            .paused(at: t(520)),
            .roundCompleted(number: 1, at: t(560)),   // logged during the pause window
            .resumed(at: t(600)),
            .roundCompleted(number: 2, at: t(660)),
        ])

        let durations = SessionDerivation.roundDurations(state)

        // Round 1: 60s wall, 40s of it paused. Round 2: 100s wall, 40s paused.
        XCTAssertEqual(durations[0], 20, accuracy: 0.001)
        XCTAssertEqual(durations[1], 60, accuracy: 0.001)
    }

    func test_noRoundsYieldsNoDurations() {
        let state = SessionState.replay([
            startedEvent,
            .runFinished(index: 1, at: t(500), distanceMeters: nil),
        ])

        XCTAssertTrue(SessionDerivation.roundDurations(state).isEmpty)
    }

    func test_undoneRoundIsNotCounted() {
        let state = SessionState.replay([
            startedEvent,
            .runFinished(index: 1, at: t(500), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(560)),
            .roundCompleted(number: 2, at: t(620)),
            .roundUndone(number: 2, at: t(625)),
        ])

        XCTAssertEqual(SessionDerivation.roundDurations(state).count, 1)
    }
}
