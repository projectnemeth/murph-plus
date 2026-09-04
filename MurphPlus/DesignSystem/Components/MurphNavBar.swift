// MurphPlus/DesignSystem/Components/MurphNavBar.swift
// Micro-caps navigation bar chrome for sheets / pushed / full-screen-cover
// screens (ui_kits/murph-plus-ios/AppShell.jsx NavBar). Tab-root screens use
// MurphScreenTitle in-body instead and hide this bar entirely.
import SwiftUI

private struct MurphNavBarModifier: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            // Every screen using this bar supplies its own leading dismiss
            // control, so the system chevron is a duplicate. On a pushed screen
            // it rendered right next to our own back arrow — two back buttons,
            // one bar. A no-op for the sheet and full-screen-cover users, which
            // never get a system back button in the first place.
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(MurphColor.surfacePage, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .murphType(.micro)
                        .foregroundStyle(MurphColor.textMuted)
                }
            }
    }
}

extension View {
    func murphNavBar(title: String) -> some View {
        modifier(MurphNavBarModifier(title: title))
    }
}
