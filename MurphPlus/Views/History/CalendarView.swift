// MurphPlus/Views/History/CalendarView.swift
import SwiftUI
import SwiftData

struct CalendarView: View {
    @Query private var allSessions: [MurphSession]
    @State private var displayedMonth: Date = .now
    let onSelect: (MurphSession) -> Void

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    // Same rule as HistoryListView: the calendar shows PAST sessions only. An
    // .inProgress row can outlive its workout (app killed between "Begin" and
    // "Start Run 1" leaves startedAt == nil, which the resume finder
    // deliberately ignores, so nothing cleans it up). Left unfiltered it would
    // render as an invisible marker on a day that is nonetheless tappable —
    // opening a detail screen from a cell that looks empty.
    private var sessions: [MurphSession] {
        allSessions.filter { $0.status != .inProgress }
    }

    private var days: [CalendarDay] {
        CalendarMonthBuilder.build(month: displayedMonth, sessions: sessions, calendar: calendar)
    }

    var body: some View {
        VStack {
            HStack {
                Button { shiftMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button { shiftMonth(by: 1) } label: { Image(systemName: "chevron.right") }
            }
            .padding(.horizontal)

            LazyVGrid(columns: columns) {
                ForEach(days) { day in
                    dayCell(day)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
    }

    private func dayCell(_ day: CalendarDay) -> some View {
        Button {
            if let session = day.session {
                onSelect(session)
            }
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: day.date))")
                    .foregroundStyle(day.isInCurrentMonth ? .primary : .secondary)
                marker(for: day.session)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .disabled(day.session == nil)
    }

    @ViewBuilder
    private func marker(for session: MurphSession?) -> some View {
        switch session?.status {
        case .completed:
            Circle().fill(Color.green).frame(width: 6, height: 6)
        case .abandoned:
            Circle().strokeBorder(Color.orange).frame(width: 6, height: 6)
        default:
            Circle().fill(Color.clear).frame(width: 6, height: 6)
        }
    }

    private func shiftMonth(by value: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) ?? displayedMonth
    }
}
