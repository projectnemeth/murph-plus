// MurphPlusTests/CalendarMonthBuilderTests.swift
import XCTest
@testable import MurphPlus

final class CalendarMonthBuilderTests: XCTestCase {
    func test_build_returnsCompleteWeeksCoveringTheMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let month = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!

        let days = CalendarMonthBuilder.build(month: month, sessions: [], calendar: calendar)

        XCTAssertEqual(days.count % 7, 0)
        XCTAssertTrue(days.contains { calendar.isDate($0.date, equalTo: month, toGranularity: .month) })
    }

    func test_build_attachesSessionToMatchingDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let month = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let sessionDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!

        let template = WorkoutTemplate(name: "Test")
        let session = MurphSession(template: template, vestOn: false)
        session.date = sessionDate

        let days = CalendarMonthBuilder.build(month: month, sessions: [session], calendar: calendar)

        let matchingDay = days.first { calendar.isDate($0.date, inSameDayAs: sessionDate) }
        XCTAssertNotNil(matchingDay?.session)

        // Asserting only the above would pass against an implementation that
        // stamped the session onto EVERY cell — verified: replacing the
        // per-day dictionary lookup with `sessions.first` still passed. These
        // two assertions are what make the test non-vacuous.
        XCTAssertEqual(days.filter { $0.session != nil }.count, 1)
        let otherDays = days.filter { !calendar.isDate($0.date, inSameDayAs: sessionDate) }
        XCTAssertTrue(otherDays.allSatisfy { $0.session == nil })
    }

    func test_build_groupsSameDaySessionsOntoOneCell() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let month = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 6))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 20))!

        let template = WorkoutTemplate(name: "Test")
        let first = MurphSession(template: template, vestOn: false)
        first.date = morning
        let second = MurphSession(template: template, vestOn: false)
        second.date = evening

        let days = CalendarMonthBuilder.build(month: month, sessions: [first, second], calendar: calendar)

        // Grouping is by startOfDay, so two sessions on the same calendar day
        // occupy one cell rather than spilling onto a neighbouring date.
        XCTAssertEqual(days.filter { $0.session != nil }.count, 1)
        let matchingDay = days.first { calendar.isDate($0.date, inSameDayAs: morning) }
        XCTAssertNotNil(matchingDay?.session)
    }

    // Abandoning a Murph and completing a retry the same day is a normal flow.
    // Which one the cell shows must be deterministic, not whatever the fetch
    // happened to return first — the completed one wins.
    func test_build_prefersCompletedSessionOverAbandonedOnSameDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let month = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 6))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 17))!

        let template = WorkoutTemplate(name: "Test")
        let abandoned = MurphSession(template: template, vestOn: false)
        abandoned.date = morning
        abandoned.status = .abandoned
        let completed = MurphSession(template: template, vestOn: false)
        completed.date = evening
        completed.status = .completed

        // Passed abandoned-first so a naive `.first` would pick the wrong one.
        let days = CalendarMonthBuilder.build(month: month, sessions: [abandoned, completed], calendar: calendar)

        let cell = days.first { calendar.isDate($0.date, inSameDayAs: morning) }
        XCTAssertEqual(cell?.session?.status, .completed)
    }

    func test_build_marksLeadingDaysAsOutsideCurrentMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // 1 Aug 2026 is a Saturday, so the grid carries six leading days from July.
        let month = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!

        let days = CalendarMonthBuilder.build(month: month, sessions: [], calendar: calendar)

        XCTAssertFalse(days.first!.isInCurrentMonth)
        XCTAssertTrue(days.contains { $0.isInCurrentMonth })
        // Every cell flagged in-month must actually fall in that month.
        XCTAssertTrue(days.filter(\.isInCurrentMonth).allSatisfy {
            calendar.isDate($0.date, equalTo: month, toGranularity: .month)
        })
    }

    // February 2026 begins on a Sunday and has 28 days, so it tiles exactly four
    // complete weeks with no leading or trailing cells — the boundary case where
    // the "start of the containing week" logic must contribute nothing.
    func test_build_handlesMonthStartingExactlyOnFirstWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let month = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!

        let days = CalendarMonthBuilder.build(month: month, sessions: [], calendar: calendar)

        XCTAssertEqual(days.count, 28)
        XCTAssertTrue(days.allSatisfy(\.isInCurrentMonth))
    }
}
