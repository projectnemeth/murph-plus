import XCTest
import SwiftData
@testable import MurphPlus

final class StuckWatchSessionReaperTests: XCTestCase {
    private var context: ModelContext!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    @discardableResult
    private func session(origin: SessionOrigin, startedHoursAgo: Double,
                         status: SessionStatus = .inProgress) -> MurphSession {
        let s = MurphSession(date: now, template: nil, vestOn: false)
        s.origin = origin
        s.status = status
        s.startedAt = now.addingTimeInterval(-startedHoursAgo * 3600)
        context.insert(s)
        return s
    }

    /// A Murph takes an hour or two, never twelve. A watch session still
    /// in progress long past any plausible workout is a dead watch.
    func test_findsAWatchSessionStuckWellPastAnyPlausibleWorkout() throws {
        session(origin: .watch, startedHoursAgo: 12)

        let stuck = StuckWatchSessionReaper.stuckSessions(context: context, olderThan: 6 * 3600, now: now)

        XCTAssertEqual(stuck.count, 1)
    }

    func test_leavesAWatchSessionThatCouldStillBeRunning() throws {
        session(origin: .watch, startedHoursAgo: 1)

        XCTAssertTrue(StuckWatchSessionReaper.stuckSessions(context: context, olderThan: 6 * 3600, now: now).isEmpty)
    }

    /// Phone sessions have their own resume prompt; this must not touch them.
    func test_ignoresPhoneOwnedSessions() throws {
        session(origin: .phone, startedHoursAgo: 12)

        XCTAssertTrue(StuckWatchSessionReaper.stuckSessions(context: context, olderThan: 6 * 3600, now: now).isEmpty)
    }

    func test_ignoresSessionsThatAlreadyEnded() throws {
        session(origin: .watch, startedHoursAgo: 12, status: .completed)

        XCTAssertTrue(StuckWatchSessionReaper.stuckSessions(context: context, olderThan: 6 * 3600, now: now).isEmpty)
    }

    /// Abandon, never delete: the rounds the user actually did are real and
    /// belong in history.
    func test_abandoningKeepsTheSessionAndItsProgress() throws {
        let stuck = session(origin: .watch, startedHoursAgo: 12)
        stuck.completedRounds = 8

        StuckWatchSessionReaper.abandon(stuck, context: context)

        XCTAssertEqual(stuck.status, .abandoned)
        XCTAssertEqual(stuck.completedRounds, 8, "The work done is not erased")
        XCTAssertNotNil(stuck.completedAt)
    }
}
