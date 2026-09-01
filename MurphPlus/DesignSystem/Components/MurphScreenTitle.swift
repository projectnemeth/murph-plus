// MurphPlus/DesignSystem/Components/MurphScreenTitle.swift
// Big display heading capped with a hazard rule, used at the top of the two
// tab-root screens (ui_kits/murph-plus-ios/AppShell.jsx ScreenTitle).
import SwiftUI

struct MurphScreenTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.space3) {
            Text(title)
                .murphType(.display2())
                .foregroundStyle(MurphColor.textPrimary)
            HazardRule(height: 8, width: 72)
            if let subtitle {
                Text(subtitle)
                    .murphType(.bodySm)
                    .foregroundStyle(MurphColor.textMuted)
            }
        }
        .padding(.horizontal, MurphSpacing.gutterScreen)
        .padding(.bottom, MurphSpacing.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Ink page background that fills the safe area, matching the app's
/// dark-only surface.
struct MurphScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(MurphColor.surfacePage.ignoresSafeArea())
    }
}

extension View {
    func murphScreenBackground() -> some View {
        modifier(MurphScreenBackground())
    }
}
