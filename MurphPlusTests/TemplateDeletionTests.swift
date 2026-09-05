// MurphPlusTests/TemplateDeletionTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

final class TemplateDeletionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    private func template(name: String = "Full Murph") -> WorkoutTemplate {
        let template = WorkoutTemplate(name: name)
        context.insert(template)
        return template
    }

    @discardableResult
    private func session(
        for template: WorkoutTemplate, status: SessionStatus
    ) -> MurphSession {
        let session = MurphSession(template: template, vestOn: false)
        session.status = status
        context.insert(session)
        return session
    }

    // MARK: - The delete itself

    func test_delete_removesTheTemplate() throws {
        let template = template()
        try TemplateDeletion.delete(template, context: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutTemplate>()).isEmpty)
    }

    /// The whole reason the relationship nullifies rather than cascades:
    /// tidying the template list must not erase months of logged times.
    func test_delete_keepsTheSessionsThatUsedIt() throws {
        let template = template()
        session(for: template, status: .completed)
        session(for: template, status: .abandoned)

        try TemplateDeletion.delete(template, context: context)

        let sessions = try context.fetch(FetchDescriptor<MurphSession>())
        XCTAssertEqual(sessions.count, 2)
        XCTAssertTrue(sessions.allSatisfy { $0.template == nil })
    }

    func test_delete_leavesOtherTemplatesAlone() throws {
        let doomed = template(name: "Doomed")
        let kept = template(name: "Kept")
        session(for: kept, status: .completed)

        try TemplateDeletion.delete(doomed, context: context)

        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        XCTAssertEqual(templates.map(\.name), ["Kept"])
        XCTAssertEqual(kept.sessions.count, 1)
    }

    // MARK: - The live-session guard

    /// Deleting mid-workout would hand the live screen a nil template, and
    /// `template?.rounds ?? 0` turns a 20-round Murph into a 0-round one while
    /// the user is running it.
    func test_delete_refusesWhileASessionIsInProgress() throws {
        let template = template()
        session(for: template, status: .inProgress)

        XCTAssertEqual(TemplateDeletion.blocker(for: template), .sessionInProgress)
        XCTAssertThrowsError(try TemplateDeletion.delete(template, context: context)) { error in
            XCTAssertEqual(error as? TemplateDeletion.Failure, .sessionInProgress)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutTemplate>()).count, 1)
    }

    func test_blocker_isNilWithOnlyFinishedSessions() {
        let template = template()
        session(for: template, status: .completed)
        session(for: template, status: .abandoned)
        XCTAssertNil(TemplateDeletion.blocker(for: template))
    }

    /// An in-progress session against a *different* template must not block
    /// this one — the phone can be mid-workout and still tidy its list.
    func test_blocker_ignoresOtherTemplatesLiveSessions() {
        let live = template(name: "Live")
        let idle = template(name: "Idle")
        session(for: live, status: .inProgress)
        XCTAssertNil(TemplateDeletion.blocker(for: idle))
    }

    // MARK: - What the confirmation says

    func test_affectedSessionCount_countsPastSessionsOnly() {
        let template = template()
        session(for: template, status: .completed)
        session(for: template, status: .abandoned)
        session(for: template, status: .inProgress)
        XCTAssertEqual(TemplateDeletion.affectedSessionCount(for: template), 2)
    }

    func test_affectedSessionCount_isZeroForAnUnusedTemplate() {
        XCTAssertEqual(TemplateDeletion.affectedSessionCount(for: template()), 0)
    }
}
