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
}
