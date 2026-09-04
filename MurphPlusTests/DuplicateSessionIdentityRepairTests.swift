// MurphPlusTests/DuplicateSessionIdentityRepairTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

final class DuplicateSessionIdentityRepairTests: XCTestCase {
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
    private func insert(on date: Date, id: UUID, completedRounds: Int = 0) -> MurphSession {
        let session = MurphSession(date: date, template: nil, vestOn: false)
        session.id = id
        session.completedRounds = completedRounds
        context.insert(session)
        return session
    }

    private func sessions() throws -> [MurphSession] {
        try context.fetch(FetchDescriptor<MurphSession>())
    }

    private func day(_ n: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(n) * 86_400)
    }

    /// The state a lightweight migration leaves behind: the `= UUID()` default
    /// evaluated once, stamping every backfilled row with the same value. Here
    /// that id is the sync dedup key, so leaving it shared lets the first
    /// checkpoint from the Watch overwrite an arbitrary logged workout.
    func test_repairsRowsThatAllSharedOneBackfilledID() throws {
        let shared = UUID()
        insert(on: day(1), id: shared)
        insert(on: day(2), id: shared)
        insert(on: day(3), id: shared)
        insert(on: day(4), id: shared)

        DuplicateSessionIdentityRepair.repair(context: context)

        let ids = try sessions().map(\.id)
        XCTAssertEqual(ids.count, 4)
        XCTAssertEqual(Set(ids).count, 4, "Every session must end up uniquely identified")
    }

    func test_repairChangesNothingButTheIDs() throws {
        let shared = UUID()
        insert(on: day(1), id: shared, completedRounds: 12)
        insert(on: day(2), id: shared, completedRounds: 20)

        DuplicateSessionIdentityRepair.repair(context: context)

        let first = try XCTUnwrap(sessions().first { $0.date == day(1) })
        XCTAssertEqual(first.completedRounds, 12)
        XCTAssertEqual(first.origin, .phone)
        XCTAssertEqual(first.lastCheckpointSeq, 0)
    }

    func test_isANoOpWhenEveryIDIsAlreadyDistinct() throws {
        let a = UUID(), b = UUID()
        insert(on: day(1), id: a)
        insert(on: day(2), id: b)

        DuplicateSessionIdentityRepair.repair(context: context)

        let byDate = Dictionary(uniqueKeysWithValues: try sessions().map { ($0.date, $0.id) })
        XCTAssertEqual(byDate[day(1)], a, "An already-unique id must not be churned")
        XCTAssertEqual(byDate[day(2)], b)
    }

    /// Self-healing rather than flag-gated: running it twice must be safe,
    /// because after the first pass there are no duplicates left to act on.
    func test_isIdempotent() throws {
        let shared = UUID()
        insert(on: day(1), id: shared)
        insert(on: day(2), id: shared)

        DuplicateSessionIdentityRepair.repair(context: context)
        let afterFirst = Dictionary(uniqueKeysWithValues: try sessions().map { ($0.date, $0.id) })

        DuplicateSessionIdentityRepair.repair(context: context)
        let afterSecond = Dictionary(uniqueKeysWithValues: try sessions().map { ($0.date, $0.id) })

        XCTAssertEqual(afterFirst, afterSecond, "A second pass must not reassign anything")
    }

    func test_repairsOnlyTheDuplicatedGroup() throws {
        let shared = UUID(), unique = UUID()
        insert(on: day(1), id: shared)
        insert(on: day(2), id: shared)
        insert(on: day(3), id: unique)

        DuplicateSessionIdentityRepair.repair(context: context)

        let byDate = Dictionary(uniqueKeysWithValues: try sessions().map { ($0.date, $0.id) })
        XCTAssertEqual(byDate[day(3)], unique, "Untouched by another row's collision")
        XCTAssertEqual(Set(byDate.values).count, 3)
    }

    func test_isSafeOnAnEmptyStore() throws {
        DuplicateSessionIdentityRepair.repair(context: context)

        XCTAssertTrue(try sessions().isEmpty)
    }
}
