// MurphPlus/DesignSystem/Components/MurphSectionHeader.swift
// Labels a block of a screen. Mono micro caps, wide tracking, hairline rule
// (components/core/SectionHeader.jsx).
import SwiftUI

struct MurphSectionHeader<Action: View>: View {
    let title: String
    @ViewBuilder var action: Action

    init(_ title: String, @ViewBuilder action: () -> Action = { EmptyView() }) {
        self.title = title
        self.action = action()
    }

    var body: some View {
        HStack {
            Text(title)
                .murphType(.micro)
                .foregroundStyle(MurphColor.textMuted)
            Spacer()
            action
        }
        .padding(.bottom, MurphSpacing.space2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MurphColor.lineHairline)
                .frame(height: MurphShape.borderHair)
        }
    }
}
