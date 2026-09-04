// MurphPlusTests/NeverStartedSessionPurgerTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

final class NeverStartedSessionPurgerTests: XCTestCase {
    var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    private func makeTemplate() -> WorkoutTemplate {
        let template = WorkoutTemplate(name: "Test Template", rounds: 3)
        context.insert(template)
        return template
    }

    private func insertSession(status: SessionStatus, startedAt: Date?) -> MurphSession {
        let session = MurphSession(template: makeTemplate(), vestOn: false)
        session.status = status
        session.startedAt = startedAt
        if status != .inProgress { session.completedAt = .now }
        context.insert(session)
        return session
    }

    private func allSessions() throws -> [MurphSession] {
        try context.fetch(FetchDescriptor<MurphSession>())
    }

    func test_purgesNeverStartedInProgressSession() throws {
        _ = insertSession(status: .inProgress, startedAt: nil)

        NeverStartedSessionPurger.purge(context: context)

        XCTAssertTrue(try allSessions().isEmpty)
    }

    /// The case this type was widened for: abandoning before tapping Start used
    /// to leave an `.abandoned` row with no `startedAt`, which the old
    /// status-scoped predicate walked straight past — so it counted toward the
    /// Attempts tile forever.
    func test_purgesNeverStartedAbandonedSession() throws {
        _ = insertSession(status: .abandoned, startedAt: nil)

        NeverStartedSessionPurger.purge(context: context)

        XCTAssertTrue(try allSessions().isEmpty, "A never-started abandon is not an attempt")
    }

    func test_keepsAStartedInProgressSession() throws {
        _ = insertSession(status: .inProgress, startedAt: .now)

        NeverStartedSessionPurger.purge(context: context)

        XCTAssertEqual(try allSessions().count, 1)
    }

    func test_keepsAStartedAbandonedSession() throws {
        _ = insertSession(status: .abandoned, startedAt: Date.now.addingTimeInterval(-600))

        NeverStartedSessionPurger.purge(context: context)

        XCTAssertEqual(try allSessions().count, 1, "A real attempt that was given up is a record")
    }

    func test_keepsCompletedSessions() throws {
        _ = insertSession(status: .completed, startedAt: Date.now.addingTimeInterval(-3600))

        NeverStartedSessionPurger.purge(context: context)

        XCTAssertEqual(try allSessions().count, 1)
    }

    func test_purgesOnlyTheNeverStartedRowsInAMixedStore() throws {
        _ = insertSession(status: .inProgress, startedAt: nil)
        _ = insertSession(status: .abandoned, startedAt: nil)
        _ = insertSession(status: .completed, startedAt: Date.now.addingTimeInterval(-3600))
        _ = insertSession(status: .abandoned, startedAt: Date.now.addingTimeInterval(-600))

        NeverStartedSessionPurger.purge(context: context)

        let remaining = try allSessions()
        XCTAssertEqual(remaining.count, 2)
        XCTAssertTrue(remaining.allSatisfy { $0.startedAt != nil })
    }

    func test_isSafeOnAnEmptyStore() throws {
        NeverStartedSessionPurger.purge(context: context)

        XCTAssertTrue(try allSessions().isEmpty)
    }
}
