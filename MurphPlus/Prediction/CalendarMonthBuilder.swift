// MurphPlus/Prediction/CalendarMonthBuilder.swift
import Foundation

struct CalendarDay: Identifiable {
    let id = UUID()
    let date: Date
    let isInCurrentMonth: Bool
    let session: MurphSession?
}

enum CalendarMonthBuilder {
    static func build(month: Date, sessions: [MurphSession], calendar: Calendar = .current) -> [CalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let firstWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else { return [] }

        let sessionsByDay = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.date) }

        var days: [CalendarDay] = []
        var current = firstWeekInterval.start

        while current < monthInterval.end || days.count % 7 != 0 {
            let dayStart = calendar.startOfDay(for: current)
            let isInCurrentMonth = calendar.isDate(current, equalTo: month, toGranularity: .month)
            let session = sessionsByDay[dayStart]?.first
            days.append(CalendarDay(date: dayStart, isInCurrentMonth: isInCurrentMonth, session: session))
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }

        return days
    }
}
