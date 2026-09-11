// MurphPlusTests/SessionEngineLocationTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

/// The phone's counterpart to the location arc asserted in
/// `WatchSessionControllerTests`. The contract is a *sequence of calls* across
/// a whole workout, so it is asserted against a recording double.
@MainActor
final class SessionEngineLocationTests: XCTestCase {
    var context: ModelContext!
    var location: FakeLocationController!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self,
            configurations: config
        )
        context = ModelContext(container)
        location = FakeLocationController()
    }

    private func makeTemplate(rounds: Int) -> WorkoutTemplate {
        let template = WorkoutTemplate(name: "Test Template", rounds: rounds)
        context.insert(template)
        return template
    }

    private func makeEngine(rounds: Int, indoor: Bool = false) -> SessionEngine {
        SessionEngine.startNew(
            template: makeTemplate(rounds: rounds), vestOn: false, vestWeightLbs: nil,
            indoor: indoor, context: context, location: location
        )
    }

    func test_startingRun1_warmsReceiverAndBeginsMeasuring() {
        let engine = makeEngine(rounds: 3)
        engine.start()

        XCTAssertEqual(location.transitions.last, .start)
        XCTAssertTrue(location.calls.contains(.beginRun))
    }

    func test_pause_stopsMeasuringButLeavesReceiverRunning() {
        let engine = makeEngine(rounds: 3)
        engine.start()
        engine.pause()

        XCTAssertEqual(location.calls.last, .stopMeasuring)
        // Pause is invisible to LocationPolicy on purpose: reacquiring a fix
        // on resume costs more than a short pause saves.
        XCTAssertEqual(location.transitions.last, .start)
    }

    func test_resume_resumesMeasuring() {
        let engine = makeEngine(rounds: 3)
        engine.start()
        engine.pause()
        engine.resume()

        XCTAssertEqual(location.calls.last, .resumeRun)
    }

    func test_finishRun1_capturesDistanceIntoTheSplitAndStopsMeasuring() {
        let engine = makeEngine(rounds: 3)
        engine.start()
        location.runDistanceMeters = 1609.34
        engine.finishRun()

        XCTAssertEqual(engine.session.runSplits.first?.distanceMeters ?? 0, 1609.34, accuracy: 0.01)
        XCTAssertTrue(location.calls.contains(.stopMeasuring))
    }

    func test_midRounds_receiverIsOff() {
        let engine = makeEngine(rounds: 20)
        engine.start()
        engine.finishRun()

        XCTAssertEqual(location.transitions.last, .stop)
    }

    func test_penultimateRound_warmsReceiverButDoesNotMeasure() {
        let engine = makeEngine(rounds: 3)
        engine.start()
        engine.finishRun()
        let callsBefore = location.calls.count
        engine.completeRound()
        engine.completeRound() // 2 of 3 done: remaining == 1, pre-warm begins

        XCTAssertEqual(location.transitions.last, .start)
        XCTAssertFalse(
            location.calls.dropFirst(callsBefore).contains(.beginRun),
            "the pre-warm started measuring - steps around the pull-up bar will land in run 2"
        )
    }

    func test_run2_beginsMeasuringAfresh() {
        let engine = makeEngine(rounds: 2)
        engine.start()
        engine.finishRun()
        engine.completeRound()
        engine.completeRound() // -> .run2

        XCTAssertEqual(engine.session.phase, .run2)
        XCTAssertEqual(location.calls.last, .beginRun)
    }

    func test_completion_stopsTheReceiver() {
        let engine = makeEngine(rounds: 1)
        engine.start()
        engine.finishRun()
        engine.completeRound()
        engine.finishRun()

        XCTAssertEqual(engine.session.phase, .completed)
        XCTAssertEqual(location.transitions.last, .stop)
    }

    func test_abandon_stopsTheReceiver() {
        let engine = makeEngine(rounds: 3)
        engine.start()
        engine.abandon()

        XCTAssertEqual(location.transitions.last, .stop)
    }

    func test_indoorSession_neverStartsTheReceiver() {
        let engine = makeEngine(rounds: 3, indoor: true)
        engine.start()
        engine.finishRun()
        engine.completeRound()

        XCTAssertFalse(location.calls.contains(.start))
    }

    /// A run already in flight at construction began before this engine
    /// existed, so its partial total is unrecoverable. An honest gap beats an
    /// undercount with no visible signal.
    func test_resumingMidRun_reportsNilDistanceForThatRunOnly() {
        let first = makeEngine(rounds: 2)
        first.start()

        // Relaunch: a second engine over the same persisted session.
        let resumed = SessionEngine(session: first.session, context: context, location: location)
        location.runDistanceMeters = 900
        resumed.finishRun()

        XCTAssertNil(resumed.session.runSplits.first?.distanceMeters)

        // Run 2 measures normally.
        resumed.completeRound()
        resumed.completeRound()
        location.runDistanceMeters = 1600
        resumed.finishRun()

        let run2 = resumed.session.runSplits.first { $0.runIndex == 2 }
        XCTAssertEqual(run2?.distanceMeters ?? 0, 1600, accuracy: 0.01)
    }
}
