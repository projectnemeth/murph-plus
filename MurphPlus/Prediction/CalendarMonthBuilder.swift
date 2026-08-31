// MurphPlus/Prediction/CalendarMonthBuilder.swift
import Foundation

struct CalendarDay: Identifiable {
    // Identity must be stable across body evaluations: `days` is computed, so a
    // fresh UUID per build would make ForEach tear down and rebuild all 42 cells
    // on every render. `date` is already startOfDay-normalised and unique per cell.
    var id: Date { date }
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

        // A day can hold more than one session — abandoning a Murph and
        // completing a retry the same day is a normal flow, and one the app
        // explicitly supports by keeping abandoned sessions visible. Picking
        // `.first` off an unsorted fetch would make the winner arbitrary and
        // liable to flip between launches, so the tie-break is explicit:
        // a completed session outranks an abandoned one (you did finish it
        // that day), and among equals the most recent wins.
        func preferredSession(_ candidates: [MurphSession]) -> MurphSession? {
            candidates.sorted { lhs, rhs in
                if (lhs.status == .completed) != (rhs.status == .completed) {
                    return lhs.status == .completed
                }
                return lhs.date > rhs.date
            }.first
        }

        var days: [CalendarDay] = []
        var current = firstWeekInterval.start

        while current < monthInterval.end || days.count % 7 != 0 {
            let dayStart = calendar.startOfDay(for: current)
            let isInCurrentMonth = calendar.isDate(current, equalTo: month, toGranularity: .month)
            let session = preferredSession(sessionsByDay[dayStart] ?? [])
            days.append(CalendarDay(date: dayStart, isInCurrentMonth: isInCurrentMonth, session: session))
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }

        return days
    }
}
