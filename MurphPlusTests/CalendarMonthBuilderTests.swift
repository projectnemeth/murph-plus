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
    }
}
