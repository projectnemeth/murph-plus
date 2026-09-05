// MurphPlusTests/HistoryStatsTests.swift
import XCTest
@testable import MurphPlus

final class HistoryStatsTests: XCTestCase {
    private func session(
        template: WorkoutTemplate,
        daysAgo: Int,
        elapsedSeconds: Double?,
        vestOn: Bool = false,
        status: SessionStatus = .completed
    ) -> MurphSession {
        let session = MurphSession(template: template, vestOn: vestOn)
        let start = Date.now.addingTimeInterval(Double(-daysAgo) * 86400)
        // `summarize` sorts on `session.date`, so the fixture must set it —
        // setting only startedAt/completedAt leaves every fixture at the same
        // default date and makes the ordering assertions meaningless.
        session.date = start
        session.startedAt = start
        if let elapsedSeconds { session.completedAt = start.addingTimeInterval(elapsedSeconds) }
        session.status = status
        return session
    }

    private func full() -> WorkoutTemplate { WorkoutTemplate(name: "Full Murph") }
    private func mini() -> WorkoutTemplate {
        WorkoutTemplate(name: "Mini Murph", totalPullUps: 50, totalPushUps: 100, totalSquats: 150)
    }

    // MARK: - Scoping

    /// The bug this whole type was rewritten for: a shorter template is always
    /// faster, so a global minimum makes the real record unreachable.
    func test_summarize_ignoresOtherTemplates() {
        let full = full()
        let sessions = [
            session(template: full, daysAgo: 10, elapsedSeconds: 3600),
            session(template: mini(), daysAgo: 5, elapsedSeconds: 1200),
            session(template: full, daysAgo: 1, elapsedSeconds: 3400)
        ]
        let summary = HistoryStats.summarize(sessions: sessions)
        XCTAssertEqual(summary.personalBestSeconds, 3400)
        XCTAssertEqual(summary.scopeLabel, "Full Murph")
    }

    /// Vest is part of the identity, never a tiebreak — the same rule
    /// `PersonalBestCheck` applies on the Watch.
    func test_summarize_ignoresTheOtherVestState() {
        let full = full()
        let sessions = [
            session(template: full, daysAgo: 10, elapsedSeconds: 2400, vestOn: false),
            session(template: full, daysAgo: 1, elapsedSeconds: 3600, vestOn: true)
        ]
        let summary = HistoryStats.summarize(sessions: sessions)
        XCTAssertEqual(summary.personalBestSeconds, 3600)
        XCTAssertEqual(summary.scopeLabel, "Full Murph · vest")
    }

    func test_summarize_scopesToTheMostRecentCompletedSession() {
        let sessions = [
            session(template: full(), daysAgo: 1, elapsedSeconds: 3600),
            session(template: mini(), daysAgo: 10, elapsedSeconds: 1200)
        ]
        XCTAssertEqual(HistoryStats.summarize(sessions: sessions).scopeLabel, "Full Murph")
    }

    // MARK: - The three numbers

    func test_summarize_withNoSessions_returnsNils() {
        let summary = HistoryStats.summarize(sessions: [])
        XCTAssertNil(summary.personalBestSeconds)
        XCTAssertNil(summary.mostRecentSeconds)
        XCTAssertNil(summary.trendSeconds)
        XCTAssertNil(summary.scopeLabel)
        XCTAssertEqual(summary.attempts, 0)
    }

    /// An abandoned session is an attempt but never a time, so it must not be
    /// able to set — or hide — a record.
    func test_summarize_withOnlyAbandonedSessions_hasNoTimes() {
        let sessions = [session(template: full(), daysAgo: 1, elapsedSeconds: nil, status: .abandoned)]
        let summary = HistoryStats.summarize(sessions: sessions)
        XCTAssertNil(summary.personalBestSeconds)
        XCTAssertEqual(summary.attempts, 1)
    }

    func test_summarize_findsPersonalBestWithinTheScope() {
        let full = full()
        let sessions = [
            session(template: full, daysAgo: 10, elapsedSeconds: 3000),
            session(template: full, daysAgo: 5, elapsedSeconds: 2700),
            session(template: full, daysAgo: 1, elapsedSeconds: 2900)
        ]
        XCTAssertEqual(HistoryStats.summarize(sessions: sessions).personalBestSeconds, 2700)
    }

    func test_summarize_mostRecentIsLatestByDate() {
        let full = full()
        let sessions = [
            session(template: full, daysAgo: 10, elapsedSeconds: 3000),
            session(template: full, daysAgo: 1, elapsedSeconds: 2900)
        ]
        XCTAssertEqual(HistoryStats.summarize(sessions: sessions).mostRecentSeconds, 2900)
    }

    func test_summarize_trendComparesLastTwoInScope() {
        let full = full()
        let sessions = [
            session(template: full, daysAgo: 10, elapsedSeconds: 3000),
            session(template: full, daysAgo: 1, elapsedSeconds: 2900)
        ]
        XCTAssertEqual(HistoryStats.summarize(sessions: sessions).trendSeconds, -100)
    }

    /// Without scoping, the trend would read "20 minutes faster than last time"
    /// because last time was a different, shorter workout.
    func test_summarize_trendSkipsOtherTemplates() {
        let full = full()
        let sessions = [
            session(template: full, daysAgo: 20, elapsedSeconds: 3000),
            session(template: mini(), daysAgo: 10, elapsedSeconds: 1200),
            session(template: full, daysAgo: 1, elapsedSeconds: 2900)
        ]
        XCTAssertEqual(HistoryStats.summarize(sessions: sessions).trendSeconds, -100)
    }

    func test_summarize_attemptsCountsOnlyTheScope_completedAndAbandoned() {
        let full = full()
        let sessions = [
            session(template: full, daysAgo: 20, elapsedSeconds: 3000),
            session(template: full, daysAgo: 15, elapsedSeconds: nil, status: .abandoned),
            session(template: mini(), daysAgo: 10, elapsedSeconds: 1200),
            session(template: full, daysAgo: 1, elapsedSeconds: 2900)
        ]
        XCTAssertEqual(HistoryStats.summarize(sessions: sessions).attempts, 3)
    }

    // MARK: - Row badges

    func test_personalBestIDs_badgesTheBestOfEachTemplate() {
        let full = full()
        let mini = mini()
        let fullBest = session(template: full, daysAgo: 5, elapsedSeconds: 2700)
        let miniBest = session(template: mini, daysAgo: 3, elapsedSeconds: 1100)
        let sessions = [
            session(template: full, daysAgo: 10, elapsedSeconds: 3000),
            fullBest,
            session(template: mini, daysAgo: 8, elapsedSeconds: 1200),
            miniBest
        ]
        XCTAssertEqual(
            HistoryStats.personalBestIDs(sessions: sessions), [fullBest.id, miniBest.id]
        )
    }

    /// The old test was `elapsed == globalBest`, which badged every row that
    /// happened to share the winning time — including one run with a different
    /// template.
    func test_personalBestIDs_aTieLeavesTheBadgeWithTheFirstToSetIt() {
        let full = full()
        let first = session(template: full, daysAgo: 10, elapsedSeconds: 2700)
        let tie = session(template: full, daysAgo: 1, elapsedSeconds: 2700)
        XCTAssertEqual(HistoryStats.personalBestIDs(sessions: [first, tie]), [first.id])
    }

    /// A debut is not a record — the same refusal `PersonalBestCheck` makes.
    func test_personalBestIDs_doesNotBadgeASingleAttempt() {
        let sessions = [session(template: full(), daysAgo: 1, elapsedSeconds: 2700)]
        XCTAssertTrue(HistoryStats.personalBestIDs(sessions: sessions).isEmpty)
    }

    func test_personalBestIDs_ignoresAbandonedSessions() {
        let full = full()
        let best = session(template: full, daysAgo: 1, elapsedSeconds: 2700)
        let sessions = [
            session(template: full, daysAgo: 10, elapsedSeconds: 3000),
            best,
            session(template: full, daysAgo: 5, elapsedSeconds: nil, status: .abandoned)
        ]
        XCTAssertEqual(HistoryStats.personalBestIDs(sessions: sessions), [best.id])
    }

    func test_personalBestIDs_separatesVestedFromUnvested() {
        let full = full()
        let unvestedBest = session(template: full, daysAgo: 5, elapsedSeconds: 2700)
        let vestedBest = session(template: full, daysAgo: 2, elapsedSeconds: 3300, vestOn: true)
        let sessions = [
            session(template: full, daysAgo: 10, elapsedSeconds: 3000),
            unvestedBest,
            session(template: full, daysAgo: 8, elapsedSeconds: 3600, vestOn: true),
            vestedBest
        ]
        XCTAssertEqual(
            HistoryStats.personalBestIDs(sessions: sessions), [unvestedBest.id, vestedBest.id]
        )
    }
}
