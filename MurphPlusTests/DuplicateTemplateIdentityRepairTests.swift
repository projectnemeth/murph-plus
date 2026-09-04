// MurphPlusTests/DuplicateTemplateIdentityRepairTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

final class DuplicateTemplateIdentityRepairTests: XCTestCase {
    var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    @discardableResult
    private func insert(_ name: String, rounds: Int, id: UUID) -> WorkoutTemplate {
        let template = WorkoutTemplate(name: name, rounds: rounds)
        template.id = id
        context.insert(template)
        return template
    }

    private func templates() throws -> [WorkoutTemplate] {
        try context.fetch(FetchDescriptor<WorkoutTemplate>())
    }

    /// The exact state observed on a real upgraded install: SwiftData's
    /// lightweight migration evaluated the `= UUID()` default once and stamped
    /// every backfilled row with the same value.
    func test_repairsRowsThatAllSharedOneBackfilledID() throws {
        let shared = UUID()
        insert("Full Murph (Straight Sets)", rounds: 1, id: shared)
        insert("Full Murph (Cindy-Style, 20 Rounds)", rounds: 20, id: shared)
        insert("Half Murph", rounds: 10, id: shared)
        insert("Mini Murph", rounds: 5, id: shared)

        DuplicateTemplateIdentityRepair.repair(context: context)

        let ids = try templates().map(\.id)
        XCTAssertEqual(ids.count, 4)
        XCTAssertEqual(Set(ids).count, 4, "Every template must end up uniquely identified")
    }

    func test_repairChangesNothingButTheIDs() throws {
        let shared = UUID()
        insert("Half Murph", rounds: 10, id: shared)
        insert("Mini Murph", rounds: 5, id: shared)

        DuplicateTemplateIdentityRepair.repair(context: context)

        let half = try XCTUnwrap(templates().first { $0.name == "Half Murph" })
        XCTAssertEqual(half.rounds, 10)
        XCTAssertEqual(half.totalPullUps, 100)
        XCTAssertEqual(half.runDistanceMiles, 1.0)
    }

    func test_isANoOpWhenEveryIDIsAlreadyDistinct() throws {
        let a = UUID(), b = UUID()
        insert("Half Murph", rounds: 10, id: a)
        insert("Mini Murph", rounds: 5, id: b)

        DuplicateTemplateIdentityRepair.repair(context: context)

        let byName = Dictionary(uniqueKeysWithValues: try templates().map { ($0.name, $0.id) })
        XCTAssertEqual(byName["Half Murph"], a, "An already-unique id must not be churned")
        XCTAssertEqual(byName["Mini Murph"], b)
    }

    /// Self-healing rather than flag-gated: running it twice must be safe,
    /// because after the first pass there are no duplicates left to act on.
    func test_isIdempotent() throws {
        let shared = UUID()
        insert("Half Murph", rounds: 10, id: shared)
        insert("Mini Murph", rounds: 5, id: shared)

        DuplicateTemplateIdentityRepair.repair(context: context)
        let afterFirst = Dictionary(uniqueKeysWithValues: try templates().map { ($0.name, $0.id) })

        DuplicateTemplateIdentityRepair.repair(context: context)
        let afterSecond = Dictionary(uniqueKeysWithValues: try templates().map { ($0.name, $0.id) })

        XCTAssertEqual(afterFirst, afterSecond, "A second pass must not reassign anything")
    }

    func test_repairsOnlyTheDuplicatedGroup() throws {
        let shared = UUID(), unique = UUID()
        insert("Half Murph", rounds: 10, id: shared)
        insert("Mini Murph", rounds: 5, id: shared)
        insert("Full Murph (Straight Sets)", rounds: 1, id: unique)

        DuplicateTemplateIdentityRepair.repair(context: context)

        let byName = Dictionary(uniqueKeysWithValues: try templates().map { ($0.name, $0.id) })
        XCTAssertEqual(byName["Full Murph (Straight Sets)"], unique, "Untouched by another row's collision")
        XCTAssertEqual(Set(byName.values).count, 3)
    }

    func test_isSafeOnAnEmptyStore() throws {
        DuplicateTemplateIdentityRepair.repair(context: context)

        XCTAssertTrue(try templates().isEmpty)
    }
}
