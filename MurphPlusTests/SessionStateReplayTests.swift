// MurphPlusTests/SessionStateReplayTests.swift
import XCTest
@testable import MurphPlus

final class SessionStateReplayTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    private let spec = TemplateSpec(
        id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
        totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 3
    )

    private func started() -> SessionEvent {
        .started(at: t(0), template: spec, vestOn: true, vestWeightLbs: 20, indoor: false)
    }

    func test_startedBeginsRun1() {
        let state = SessionState.replay([started()])

        XCTAssertEqual(state.phase, .run1)
        XCTAssertEqual(state.startedAt, t(0))
        XCTAssertEqual(state.currentPhaseStartedAt, t(0))
        XCTAssertEqual(state.vestOn, true)
        XCTAssertEqual(state.vestWeightLbs, 20)
        XCTAssertEqual(state.template, spec)
    }

    func test_finishingRun1BeginsRoundsAndRecordsSplit() {
        let state = SessionState.replay([
            started(),
            .runFinished(index: 1, at: t(500), distanceMeters: 1609.34),
        ])

        XCTAssertEqual(state.phase, .rounds)
        XCTAssertEqual(state.roundsStartedAt, t(500))
        XCTAssertEqual(state.runSplits.count, 1)
        XCTAssertEqual(state.runSplits[0].index, 1)
        XCTAssertEqual(state.runSplits[0].durationSeconds, 500, accuracy: 0.001)
        XCTAssertEqual(state.runSplits[0].distanceMeters, 1609.34)
    }

    func test_lastRoundBeginsRun2() {
        let state = SessionState.replay([
            started(),
            .runFinished(index: 1, at: t(500), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(560)),
            .roundCompleted(number: 2, at: t(620)),
            .roundCompleted(number: 3, at: t(680)),
        ])

        XCTAssertEqual(state.phase, .run2)
        XCTAssertEqual(state.completedRounds, 3)
        XCTAssertEqual(state.roundTimestamps, [t(560), t(620), t(680)])
        XCTAssertEqual(state.currentPhaseStartedAt, t(680))
    }

    func test_finishingRun2CompletesTheSession() {
        let state = SessionState.replay([
            started(),
            .runFinished(index: 1, at: t(500), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(560)),
            .roundCompleted(number: 2, at: t(620)),
            .roundCompleted(number: 3, at: t(680)),
            .runFinished(index: 2, at: t(1200), distanceMeters: nil),
        ])

        XCTAssertEqual(state.phase, .completed)
        XCTAssertEqual(state.status, .completed)
        XCTAssertEqual(state.completedAt, t(1200))
        XCTAssertTrue(state.isTerminal)
    }

    func test_undoRevertsTheRun2Transition() {
        // Mis-tapping the final round advances into run 2; undo must put the
        // session back into the rounds phase and discard that run-2 start.
        let state = SessionState.replay([
            started(),
            .runFinished(index: 1, at: t(500), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(560)),
            .roundCompleted(number: 2, at: t(620)),
            .roundCompleted(number: 3, at: t(680)),
            .roundUndone(number: 3, at: t(690)),
        ])

        XCTAssertEqual(state.phase, .rounds)
        XCTAssertEqual(state.completedRounds, 2)
        XCTAssertEqual(state.roundTimestamps, [t(560), t(620)])
    }

    func test_undoableRoundNumberTracksOnlyTheMostRecentRound() {
        var state = SessionState.replay([
            started(),
            .runFinished(index: 1, at: t(500), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(560)),
        ])
        XCTAssertEqual(state.undoableRoundNumber, 1)

        // Heart rate must NOT clear undoability — it arrives every 5 seconds and
        // would otherwise make undo almost never available.
        state.apply(.heartRate(bpm: 150, at: t(562)))
        XCTAssertEqual(state.undoableRoundNumber, 1)

        state.apply(.paused(at: t(565)))
        XCTAssertNil(state.undoableRoundNumber, "Any non-heart-rate event ends the undo window")
    }

    func test_pauseAndResumeRecordAnInterval() {
        let state = SessionState.replay([
            started(),
            .paused(at: t(100)),
            .resumed(at: t(400)),
        ])

        XCTAssertFalse(state.isPaused)
        XCTAssertEqual(state.pausedIntervals.count, 1)
        XCTAssertEqual(state.pausedSeconds(between: t(0), and: t(500)), 300, accuracy: 0.001)
    }

    func test_anOpenPauseCountsUpToTheQueriedMoment() {
        let state = SessionState.replay([started(), .paused(at: t(100))])

        XCTAssertTrue(state.isPaused)
        XCTAssertEqual(state.pausedSeconds(between: t(0), and: t(250)), 150, accuracy: 0.001)
    }

    func test_pausedSecondsClipsToTheQueriedWindow() {
        let state = SessionState.replay([
            started(),
            .paused(at: t(100)),
            .resumed(at: t(400)),
        ])

        // Only the overlap counts, not the whole interval.
        XCTAssertEqual(state.pausedSeconds(between: t(200), and: t(300)), 100, accuracy: 0.001)
        XCTAssertEqual(state.pausedSeconds(between: t(500), and: t(600)), 0, accuracy: 0.001)
    }

    func test_runSplitDurationExcludesPauseTakenDuringTheRun() {
        let state = SessionState.replay([
            started(),
            .paused(at: t(100)),
            .resumed(at: t(400)),
            .runFinished(index: 1, at: t(800), distanceMeters: nil),
        ])

        // 800s of wall time, 300s of it paused.
        XCTAssertEqual(state.runSplits[0].durationSeconds, 500, accuracy: 0.001)
    }

    func test_abandonKeepsThePhaseItStoppedIn() {
        let state = SessionState.replay([
            started(),
            .runFinished(index: 1, at: t(500), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(560)),
            .abandoned(at: t(600)),
        ])

        XCTAssertEqual(state.status, .abandoned)
        XCTAssertEqual(state.phase, .rounds, "Phase records where the attempt stopped")
        XCTAssertEqual(state.completedRounds, 1)
        XCTAssertTrue(state.isTerminal)
    }

    func test_heartRateUpdatesLatestOnly() {
        let state = SessionState.replay([
            started(),
            .heartRate(bpm: 120, at: t(10)),
            .heartRate(bpm: 155, at: t(20)),
        ])

        XCTAssertEqual(state.latestHeartRate, 155)
    }
}
