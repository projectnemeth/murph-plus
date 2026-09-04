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

    /// All four seeded starter templates present at once. A future edit that
    /// loosened or mistyped the name check in `corrections` should be caught
    /// here even though it would leave the two-test, two-template suite green.
    func test_onlyHalfAndMiniAreCorrected_bothFullMurphTemplatesUntouched() throws {
        context.insert(WorkoutTemplate(
            name: "Full Murph (Straight Sets)",
            runDistanceMiles: 1.0,
            totalPullUps: 100, totalPushUps: 200, totalSquats: 300,
            rounds: 1
        ))
        context.insert(WorkoutTemplate(
            name: "Full Murph (Cindy-Style, 20 Rounds)",
            runDistanceMiles: 1.0,
            totalPullUps: 100, totalPushUps: 200, totalSquats: 300,
            rounds: 20
        ))
        insertShippedHalfMurph()
        context.insert(WorkoutTemplate(
            name: "Mini Murph",
            runDistanceMiles: 0.25,
            totalPullUps: 25, totalPushUps: 50, totalSquats: 75,
            rounds: 1
        ))

        try DefaultTemplateMigration.runIfNeeded(context: context, defaults: defaults)

        let straightSets = try XCTUnwrap(fetchTemplate(named: "Full Murph (Straight Sets)"))
        let cindyStyle = try XCTUnwrap(fetchTemplate(named: "Full Murph (Cindy-Style, 20 Rounds)"))
        let half = try XCTUnwrap(fetchTemplate(named: "Half Murph"))
        let mini = try XCTUnwrap(fetchTemplate(named: "Mini Murph"))

        XCTAssertEqual(straightSets.rounds, 1, "Full Murph straight sets must not be swept up by the Half/Mini correction")
        XCTAssertEqual(cindyStyle.rounds, 20, "Full Murph Cindy-style must not be touched")
        XCTAssertEqual(half.rounds, 10)
        XCTAssertEqual(mini.rounds, 5)
    }

    /// The spec's stated fresh-install case: seeding directly produces the
    /// corrected values, and running the migration afterward is a no-op.
    func test_freshInstall_seedsCorrectedValuesDirectly_migrationIsNoOp() throws {
        try DefaultTemplates.seedIfNeeded(context: context)

        try DefaultTemplateMigration.runIfNeeded(context: context, defaults: defaults)

        let half = try XCTUnwrap(fetchTemplate(named: "Half Murph"))
        let mini = try XCTUnwrap(fetchTemplate(named: "Mini Murph"))
        XCTAssertEqual(half.rounds, 10)
        XCTAssertEqual(mini.rounds, 5)
    }

    func test_leavesUserEditedMiniMurphAlone() throws {
        // Same name, but the user changed the pull-up count. Not ours to touch.
        context.insert(WorkoutTemplate(
            name: "Mini Murph",
            runDistanceMiles: 0.25,
            totalPullUps: 30, totalPushUps: 50, totalSquats: 75,
            rounds: 1
        ))

        try DefaultTemplateMigration.runIfNeeded(context: context, defaults: defaults)

        let mini = try XCTUnwrap(fetchTemplate(named: "Mini Murph"))
        XCTAssertEqual(mini.rounds, 1, "An edited template must not be corrected")
    }

    func test_leavesTemplateEditedOnlyInDistanceAlone() throws {
        // Reps are untouched, but the run distance was edited. Still not a
        // byte-for-byte match with the shipped default, so leave it alone.
        context.insert(WorkoutTemplate(
            name: "Half Murph",
            runDistanceMiles: 0.6,
            totalPullUps: 50, totalPushUps: 100, totalSquats: 150,
            rounds: 1
        ))

        try DefaultTemplateMigration.runIfNeeded(context: context, defaults: defaults)

        let half = try XCTUnwrap(fetchTemplate(named: "Half Murph"))
        XCTAssertEqual(half.rounds, 1, "A template edited only in run distance must not be corrected")
    }
}
