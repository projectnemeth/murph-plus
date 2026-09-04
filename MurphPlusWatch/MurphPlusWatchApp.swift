// MurphPlusWatch/MurphPlusWatchApp.swift
import SwiftUI

@main
struct MurphPlusWatchApp: App {
    var body: some Scene {
        WindowGroup {
            // Replaced in Task 6 by the real setup screen. This exists so the
            // target builds and the design-system foundations are proven to
            // compile for watchOS before any UI is written on top of them.
            Text("MURPH+")
                .murphType(.title(18))
                .foregroundStyle(MurphColor.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MurphColor.surfacePage)
        }
    }
}
