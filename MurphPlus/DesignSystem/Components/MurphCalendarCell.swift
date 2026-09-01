// MurphPlus/DesignSystem/Components/MurphCalendarCell.swift
// Calendar day cell. Filled lime dot = completed, hollow dust ring =
// abandoned, nothing = no attempt (components/data/CalendarCell.jsx). Empty
// days are non-interactive — the app never logs a session retroactively.
import SwiftUI

enum MurphCalendarCellStatus {
    case completed, abandoned
}

struct MurphCalendarCell: View {
    let day: Int
    var isToday: Bool = false
    var isInCurrentMonth: Bool = true
    var status: MurphCalendarCellStatus? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            VStack(spacing: 4) {
                Text("\(day)")
                    .murphType(.bodySm)
                    .foregroundStyle(isInCurrentMonth ? MurphColor.textPrimary : MurphColor.textMuted)
                marker
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(isToday ? MurphColor.ink800 : .clear)
            .clipShape(RoundedRectangle(cornerRadius: MurphShape.radiusSm))
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    @ViewBuilder
    private var marker: some View {
        switch status {
        case .completed:
            Circle().fill(MurphColor.statusComplete).frame(width: 6, height: 6)
        case .abandoned:
            Circle().strokeBorder(MurphColor.statusAbandoned, lineWidth: 1.5).frame(width: 6, height: 6)
        case nil:
            Circle().fill(.clear).frame(width: 6, height: 6)
        }
    }
}
