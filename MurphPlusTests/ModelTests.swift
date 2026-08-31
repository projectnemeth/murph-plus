// MurphPlusTests/ModelTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

final class ModelTests: XCTestCase {
    var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        context = ModelContext(container)
    }

    func test_workoutTemplate_defaultsToFullMurphNumbers() {
        let template = WorkoutTemplate(name: "Test")
        XCTAssertEqual(template.totalPullUps, 100)
        XCTAssertEqual(template.totalPushUps, 200)
        XCTAssertEqual(template.totalSquats, 300)
        XCTAssertEqual(template.totalReps, 600)
        XCTAssertEqual(template.rounds, 1)
    }

    func test_workoutTemplate_repsPerRoundDividesEvenly() {
        let template = WorkoutTemplate(name: "Cindy-Style", rounds: 20)
        XCTAssertEqual(template.pullUpsPerRound, 5)
        XCTAssertEqual(template.pushUpsPerRound, 10)
        XCTAssertEqual(template.squatsPerRound, 15)
        XCTAssertEqual(template.repsPerRound, 30)
    }

    func test_murphSession_vestOffClearsWeight() {
        let template = WorkoutTemplate(name: "Test")
        let session = MurphSession(template: template, vestOn: false, vestWeightLbs: 20)
        XCTAssertNil(session.vestWeightLbs)
    }

    func test_murphSession_vestOnDefaultsToTwentyPounds() {
        let template = WorkoutTemplate(name: "Test")
        let session = MurphSession(template: template, vestOn: true, vestWeightLbs: nil)
        XCTAssertEqual(session.vestWeightLbs, 20)
    }

    func test_murphSession_totalElapsedSecondsNilUntilCompleted() {
        let template = WorkoutTemplate(name: "Test")
        let session = MurphSession(template: template, vestOn: false)
        XCTAssertNil(session.totalElapsedSeconds)
    }

    func test_murphSession_totalElapsedSecondsComputedFromTimestamps() {
        let template = WorkoutTemplate(name: "Test")
        let session = MurphSession(template: template, vestOn: false)
        let start = Date(timeIntervalSince1970: 1000)
        session.startedAt = start
        session.completedAt = start.addingTimeInterval(2520)
        XCTAssertEqual(session.totalElapsedSeconds, 2520)
    }

    func test_runSplitAndRoundLog_persistWithSessionRelationship() throws {
        let template = WorkoutTemplate(name: "Test", rounds: 2)
        context.insert(template)
        let session = MurphSession(template: template, vestOn: false)
        context.insert(session)

        let split = RunSplit(runIndex: 1, startTime: .now, durationSeconds: 480, session: session)
        context.insert(split)
        session.runSplits.append(split)

        let round = RoundLog(roundNumber: 1, completedAt: .now, session: session)
        context.insert(round)
        session.roundLogs.append(round)

        try context.save()

        XCTAssertEqual(session.runSplits.count, 1)
        XCTAssertEqual(session.roundLogs.count, 1)
    }

    func test_deletingSession_cascadesToSplitsAndRoundLogs() throws {
        let template = WorkoutTemplate(name: "Test", rounds: 2)
        context.insert(template)
        let session = MurphSession(template: template, vestOn: false)
        context.insert(session)
        let split = RunSplit(runIndex: 1, startTime: .now, durationSeconds: 480, session: session)
        context.insert(split)
        let round = RoundLog(roundNumber: 1, completedAt: .now, session: session)
        context.insert(round)
        try context.save()

        context.delete(session)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<RunSplit>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<RoundLog>()).isEmpty)
    }
}
