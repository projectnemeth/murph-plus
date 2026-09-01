// MurphPlus/DesignSystem/Components/MurphEmptyState.swift
// Empty history, empty calendar month (components/feedback/EmptyState.jsx).
// Empty states name the absence and the way out, in display type.
import SwiftUI

struct MurphEmptyState<Action: View>: View {
    let title: String
    let body_: String
    @ViewBuilder var action: Action

    init(title: String, body: String, @ViewBuilder action: () -> Action = { EmptyView() }) {
        self.title = title
        self.body_ = body
        self.action = action()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.space3) {
            HazardRule(height: 6, width: 48)
            Text(title)
                .murphType(.display3())
                .foregroundStyle(MurphColor.textPrimary)
            Text(body_)
                .murphType(.body)
                .foregroundStyle(MurphColor.textMuted)
            action
                .padding(.top, MurphSpacing.space2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, MurphSpacing.space8)
    }
}
