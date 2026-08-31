// MurphPlusTests/HistoryStatsTests.swift
import XCTest
@testable import MurphPlus

final class HistoryStatsTests: XCTestCase {
    private func completedSession(daysAgo: Int, elapsedSeconds: Double) -> MurphSession {
        let template = WorkoutTemplate(name: "Test")
        let session = MurphSession(template: template, vestOn: false)
        let start = Date.now.addingTimeInterval(Double(-daysAgo) * 86400)
        // `summarize` sorts on `session.date`, so the fixture must set it —
        // setting only startedAt/completedAt leaves every fixture at the same
        // default date and makes the ordering assertions meaningless.
        session.date = start
        session.startedAt = start
        session.completedAt = start.addingTimeInterval(elapsedSeconds)
        session.status = .completed
        return session
    }

    func test_summarize_withNoSessions_returnsNils() {
        let summary = HistoryStats.summarize(completedSessions: [])
        XCTAssertNil(summary.personalBestSeconds)
        XCTAssertNil(summary.mostRecentSeconds)
        XCTAssertNil(summary.trendSeconds)
    }

    func test_summarize_findsPersonalBestAcrossSessions() {
        let sessions = [
            completedSession(daysAgo: 10, elapsedSeconds: 3000),
            completedSession(daysAgo: 5, elapsedSeconds: 2700),
            completedSession(daysAgo: 1, elapsedSeconds: 2900)
        ]
        let summary = HistoryStats.summarize(completedSessions: sessions)
        XCTAssertEqual(summary.personalBestSeconds, 2700)
    }

    func test_summarize_mostRecentIsLatestByDate() {
        let sessions = [
            completedSession(daysAgo: 10, elapsedSeconds: 3000),
            completedSession(daysAgo: 1, elapsedSeconds: 2900)
        ]
        let summary = HistoryStats.summarize(completedSessions: sessions)
        XCTAssertEqual(summary.mostRecentSeconds, 2900)
    }

    func test_summarize_trendComparesLastTwoSessions() {
        let sessions = [
            completedSession(daysAgo: 10, elapsedSeconds: 3000),
            completedSession(daysAgo: 1, elapsedSeconds: 2900)
        ]
        let summary = HistoryStats.summarize(completedSessions: sessions)
        XCTAssertEqual(summary.trendSeconds, -100)
    }
}
