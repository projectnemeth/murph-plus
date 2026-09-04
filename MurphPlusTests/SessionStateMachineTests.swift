// MurphPlusTests/SessionStateMachineTests.swift
import XCTest
@testable import MurphPlus

final class SessionStateMachineTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    private let spec = TemplateSpec(
        id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
        totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 3
    )

    /// Replays a scripted history so each test starts from a real state.
    private func state(_ events: [SessionEvent]) -> SessionState {
        SessionState.replay(events)
    }

    private var startedEvent: SessionEvent {
        .started(at: t(0), template: spec, vestOn: false, vestWeightLbs: nil, indoor: false)
    }

    private var inRounds: [SessionEvent] {
        [startedEvent, .runFinished(index: 1, at: t(500), distanceMeters: nil)]
    }

    private func expectFailure(
        _ result: Result<SessionEvent, SessionTransitionError>,
        _ expected: SessionTransitionError,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        switch result {
        case .success(let event):
            XCTFail("Expected \(expected), got event \(event)", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error, expected, file: file, line: line)
        }
    }

    // MARK: - Start

    func test_startFromNotStartedProducesStartedEvent() throws {
        let result = SessionStateMachine.start(
            SessionState(), template: spec, vestOn: true, vestWeightLbs: 20,
            indoor: false, now: t(0)
        )

        let event = try result.get()
        XCTAssertEqual(event, .started(at: t(0), template: spec, vestOn: true, vestWeightLbs: 20, indoor: false))
    }

    func test_startTwiceIsRejected() {
        let result = SessionStateMachine.start(
            state([startedEvent]), template: spec, vestOn: false, vestWeightLbs: nil,
            indoor: false, now: t(10)
        )

        expectFailure(result, .wrongPhase)
    }

    // MARK: - Terminal guard

    func test_everyTransitionIsRejectedOnAnAbandonedSession() {
        // Abandon changes only `status`, leaving `phase` where it stopped — so a
        // phase-only guard would let a later transition be flipped back to
        // completed, destroying the record.
        let abandoned = state(inRounds + [.abandoned(at: t(600))])

        expectFailure(SessionStateMachine.completeRound(abandoned, at: t(700)), .sessionIsTerminal)
        expectFailure(SessionStateMachine.finishRun(abandoned, at: t(700), distanceMeters: nil), .sessionIsTerminal)
        expectFailure(SessionStateMachine.pause(abandoned, at: t(700)), .sessionIsTerminal)
        expectFailure(SessionStateMachine.abandon(abandoned, at: t(700)), .sessionIsTerminal)
        expectFailure(SessionStateMachine.undoLastRound(abandoned, at: t(700)), .sessionIsTerminal)
    }

    // MARK: - Rounds

    func test_completeRoundNumbersTheNextRound() throws {
        let s = state(inRounds + [.roundCompleted(number: 1, at: t(560))])

        let event = try SessionStateMachine.completeRound(s, at: t(620)).get()

        XCTAssertEqual(event, .roundCompleted(number: 2, at: t(620)))
    }

    func test_completeRoundIsRejectedDuringARun() {
        expectFailure(
            SessionStateMachine.completeRound(state([startedEvent]), at: t(100)),
            .wrongPhase
        )
    }

    func test_completeRoundIsRejectedWhilePaused() {
        let paused = state(inRounds + [.paused(at: t(520))])

        expectFailure(SessionStateMachine.completeRound(paused, at: t(560)), .sessionIsPaused)
    }

    func test_finishRunIsRejectedWhilePaused() {
        let paused = state([startedEvent, .paused(at: t(100))])

        expectFailure(SessionStateMachine.finishRun(paused, at: t(200), distanceMeters: nil), .sessionIsPaused)
    }

    // MARK: - Undo

    func test_undoIsAvailableImmediatelyAfterARound() throws {
        let s = state(inRounds + [.roundCompleted(number: 1, at: t(560))])

        let event = try SessionStateMachine.undoLastRound(s, at: t(570)).get()

        XCTAssertEqual(event, .roundUndone(number: 1, at: t(570)))
    }

    func test_undoSurvivesInterveningHeartRate() throws {
        let s = state(inRounds + [
            .roundCompleted(number: 1, at: t(560)),
            .heartRate(bpm: 150, at: t(565)),
        ])

        let event = try SessionStateMachine.undoLastRound(s, at: t(570)).get()

        XCTAssertEqual(event, .roundUndone(number: 1, at: t(570)))
    }

    func test_undoIsRejectedWhenNoRoundWasJustLogged() {
        expectFailure(
            SessionStateMachine.undoLastRound(state(inRounds), at: t(560)),
            .nothingToUndo
        )
    }

    func test_undoIsRejectedTwiceInARow() {
        let s = state(inRounds + [
            .roundCompleted(number: 1, at: t(560)),
            .roundUndone(number: 1, at: t(570)),
        ])

        expectFailure(SessionStateMachine.undoLastRound(s, at: t(580)), .nothingToUndo)
    }

    func test_undoIsAllowedAcrossTheRun2Boundary() throws {
        let s = state(inRounds + [
            .roundCompleted(number: 1, at: t(560)),
            .roundCompleted(number: 2, at: t(620)),
            .roundCompleted(number: 3, at: t(680)),
        ])
        XCTAssertEqual(s.phase, .run2)

        let event = try SessionStateMachine.undoLastRound(s, at: t(690)).get()

        XCTAssertEqual(event, .roundUndone(number: 3, at: t(690)))
    }

    // MARK: - Pause

    func test_pauseAndResume() throws {
        let s = state(inRounds)

        let pausedEvent = try SessionStateMachine.pause(s, at: t(520)).get()
        XCTAssertEqual(pausedEvent, .paused(at: t(520)))

        var paused = s
        paused.apply(pausedEvent)
        let resumedEvent = try SessionStateMachine.resume(paused, at: t(700)).get()
        XCTAssertEqual(resumedEvent, .resumed(at: t(700)))
    }

    func test_pauseTwiceIsRejected() {
        let paused = state(inRounds + [.paused(at: t(520))])

        expectFailure(SessionStateMachine.pause(paused, at: t(530)), .alreadyPaused)
    }

    func test_resumeWithoutPauseIsRejected() {
        expectFailure(SessionStateMachine.resume(state(inRounds), at: t(530)), .notPaused)
    }

    func test_pauseBeforeStartingIsRejected() {
        expectFailure(SessionStateMachine.pause(SessionState(), at: t(0)), .wrongPhase)
    }
}
