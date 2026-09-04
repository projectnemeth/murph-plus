// MurphPlusTests/SessionEngineTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

final class SessionEngineTests: XCTestCase {
    var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        context = ModelContext(container)
    }

    private func makeTemplate(rounds: Int) -> WorkoutTemplate {
        let template = WorkoutTemplate(name: "Test Template", rounds: rounds)
        context.insert(template)
        return template
    }

    func test_start_transitionsToRun1AndSetsTimestamps() {
        let template = makeTemplate(rounds: 3)
        let engine = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)

        engine.start()

        XCTAssertEqual(engine.session.phase, .run1)
        XCTAssertNotNil(engine.session.startedAt)
        XCTAssertNotNil(engine.session.currentPhaseStartedAt)
    }

    func test_finishRun_afterRun1_transitionsToRoundsAndRecordsSplit() {
        let template = makeTemplate(rounds: 3)
        let engine = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)
        engine.start()

        engine.finishRun()

        XCTAssertEqual(engine.session.phase, .rounds)
        XCTAssertEqual(engine.session.runSplits.count, 1)
        XCTAssertEqual(engine.session.runSplits.first?.runIndex, 1)
    }

    func test_completeRound_incrementsCountAndTransitionsToRun2OnLastRound() {
        let template = makeTemplate(rounds: 2)
        let engine = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)
        engine.start()
        engine.finishRun()

        engine.completeRound()
        XCTAssertEqual(engine.session.completedRounds, 1)
        XCTAssertEqual(engine.session.phase, .rounds)

        engine.completeRound()
        XCTAssertEqual(engine.session.completedRounds, 2)
        XCTAssertEqual(engine.session.phase, .run2)
    }

    func test_finishRun_afterRun2_completesSession() {
        let template = makeTemplate(rounds: 1)
        let engine = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)
        engine.start()
        engine.finishRun()
        engine.completeRound()

        engine.finishRun()

        XCTAssertEqual(engine.session.phase, .completed)
        XCTAssertEqual(engine.session.status, .completed)
        XCTAssertNotNil(engine.session.completedAt)
        XCTAssertEqual(engine.session.runSplits.count, 2)
    }

    func test_abandon_marksSessionAbandoned() {
        let template = makeTemplate(rounds: 2)
        let engine = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)
        engine.start()

        engine.abandon()

        XCTAssertEqual(engine.session.status, .abandoned)
        XCTAssertNotNil(engine.session.completedAt)
    }

    // An abandoned session is terminal. Without a status guard, `abandon()`
    // leaves `phase` untouched, so a phase-only guard would let completeRound()
    // and then finishRun() run afterwards and flip the session back to
    // .completed — silently erasing the user's abandonment.
    func test_abandonedSession_cannotBeResurrectedByFurtherTransitions() {
        let template = makeTemplate(rounds: 1)
        let engine = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)
        engine.start()
        engine.finishRun()
        engine.abandon()

        engine.completeRound()
        engine.finishRun()

        XCTAssertEqual(engine.session.status, .abandoned)
        XCTAssertEqual(engine.session.roundLogs.count, 0)
    }

    func test_completedSession_cannotBeAbandoned() {
        let template = makeTemplate(rounds: 1)
        let engine = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)
        engine.start()
        engine.finishRun()
        engine.completeRound()
        engine.finishRun()
        let completedAt = engine.session.completedAt

        engine.abandon()

        XCTAssertEqual(engine.session.status, .completed)
        XCTAssertEqual(engine.session.completedAt, completedAt)
    }

    private func allSessions() throws -> [MurphSession] {
        try context.fetch(FetchDescriptor<MurphSession>())
    }

    func test_abandon_beforeStarting_discardsTheSessionEntirely() throws {
        let template = makeTemplate(rounds: 3)
        let engine = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)
        XCTAssertEqual(try allSessions().count, 1)

        // Never tapped Start: nothing was recorded, so this is not an attempt.
        engine.abandon()

        XCTAssertTrue(try allSessions().isEmpty, "A never-started session must leave no record")
    }

    func test_abandon_afterStarting_keepsTheRecordWithItsLoggedData() throws {
        let template = makeTemplate(rounds: 3)
        let engine = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)
        engine.start()
        engine.finishRun()
        engine.completeRound()

        engine.abandon()

        let sessions = try allSessions()
        XCTAssertEqual(sessions.count, 1, "A started session stays in history even when abandoned")
        XCTAssertEqual(sessions[0].status, .abandoned)
        XCTAssertEqual(sessions[0].completedRounds, 1)
        XCTAssertEqual(sessions[0].runSplits.count, 1)
        XCTAssertNotNil(sessions[0].completedAt)
    }

    func test_invalidPhaseTransitionsAreIgnored() {
        let template = makeTemplate(rounds: 2)
        let engine = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)

        engine.completeRound()
        XCTAssertEqual(engine.session.completedRounds, 0)

        engine.start()
        engine.start()
        XCTAssertEqual(engine.session.phase, .run1)

        engine.completeRound()
        XCTAssertEqual(engine.session.completedRounds, 0)
    }
}
