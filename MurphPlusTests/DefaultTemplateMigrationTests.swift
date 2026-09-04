// MurphPlusTests/DefaultTemplateMigrationTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

final class DefaultTemplateMigrationTests: XCTestCase {
    var context: ModelContext!
    var defaults: UserDefaults!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self,
            configurations: config
        )
        context = ModelContext(container)

        // A throwaway suite per test run, so the migration flag never leaks
        // between tests or into the developer's real defaults.
        let suiteName = "DefaultTemplateMigrationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    /// The Half Murph exactly as v1 shipped it: straight sets.
    private func insertShippedHalfMurph() {
        context.insert(WorkoutTemplate(
            name: "Half Murph",
            runDistanceMiles: 0.5,
            totalPullUps: 50, totalPushUps: 100, totalSquats: 150,
            rounds: 1
        ))
    }

    private func fetchTemplate(named name: String) throws -> WorkoutTemplate? {
        try context.fetch(FetchDescriptor<WorkoutTemplate>()).first { $0.name == name }
    }

    func test_correctsUntouchedHalfMurphToTenRounds() throws {
        insertShippedHalfMurph()

        try DefaultTemplateMigration.runIfNeeded(context: context, defaults: defaults)

        let half = try XCTUnwrap(fetchTemplate(named: "Half Murph"))
        XCTAssertEqual(half.rounds, 10)
        XCTAssertEqual(half.pullUpsPerRound, 5)
        XCTAssertEqual(half.pushUpsPerRound, 10)
        XCTAssertEqual(half.squatsPerRound, 15)
    }

    func test_correctsUntouchedMiniMurphToFiveRounds() throws {
        context.insert(WorkoutTemplate(
            name: "Mini Murph",
            runDistanceMiles: 0.25,
            totalPullUps: 25, totalPushUps: 50, totalSquats: 75,
            rounds: 1
        ))

        try DefaultTemplateMigration.runIfNeeded(context: context, defaults: defaults)

        let mini = try XCTUnwrap(fetchTemplate(named: "Mini Murph"))
        XCTAssertEqual(mini.rounds, 5)
        XCTAssertEqual(mini.pullUpsPerRound, 5)
        XCTAssertEqual(mini.pushUpsPerRound, 10)
        XCTAssertEqual(mini.squatsPerRound, 15)
    }

    func test_leavesNameRepsAndDistanceUntouched() throws {
        insertShippedHalfMurph()

        try DefaultTemplateMigration.runIfNeeded(context: context, defaults: defaults)

        let half = try XCTUnwrap(fetchTemplate(named: "Half Murph"))
        XCTAssertEqual(half.name, "Half Murph")
        XCTAssertEqual(half.runDistanceMiles, 0.5)
        XCTAssertEqual(half.totalPullUps, 50)
        XCTAssertEqual(half.totalPushUps, 100)
        XCTAssertEqual(half.totalSquats, 150)
    }

    func test_leavesUserEditedTemplateAlone() throws {
        // Same name, but the user changed the pull-up count. Not ours to touch.
        context.insert(WorkoutTemplate(
            name: "Half Murph",
            runDistanceMiles: 0.5,
            totalPullUps: 60, totalPushUps: 100, totalSquats: 150,
            rounds: 1
        ))

        try DefaultTemplateMigration.runIfNeeded(context: context, defaults: defaults)

        let half = try XCTUnwrap(fetchTemplate(named: "Half Murph"))
        XCTAssertEqual(half.rounds, 1, "An edited template must not be corrected")
    }

    func test_leavesAlreadyPartitionedTemplateAlone() throws {
        // The user already fixed it themselves, to a different value.
        context.insert(WorkoutTemplate(
            name: "Half Murph",
            runDistanceMiles: 0.5,
            totalPullUps: 50, totalPushUps: 100, totalSquats: 150,
            rounds: 25
        ))

        try DefaultTemplateMigration.runIfNeeded(context: context, defaults: defaults)

        let half = try XCTUnwrap(fetchTemplate(named: "Half Murph"))
        XCTAssertEqual(half.rounds, 25)
    }

    func test_doesNotRunASecondTime() throws {
        insertShippedHalfMurph()
        try DefaultTemplateMigration.runIfNeeded(context: context, defaults: defaults)

        // Simulate the user deliberately setting it back to straight sets.
        let half = try XCTUnwrap(fetchTemplate(named: "Half Murph"))
        half.rounds = 1
        try context.save()

        try DefaultTemplateMigration.runIfNeeded(context: context, defaults: defaults)

        XCTAssertEqual(half.rounds, 1, "Migration must be one-shot, not re-applied every launch")
    }

    func test_setsFlagEvenWhenNothingMatched() throws {
        try DefaultTemplateMigration.runIfNeeded(context: context, defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: DefaultTemplateMigration.flagKey))
    }
}
