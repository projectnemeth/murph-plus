// MurphPlusWatch/MurphPlusWatchApp.swift
import SwiftUI

@main
struct MurphPlusWatchApp: App {
    @State private var controller = WatchSessionController()

    var body: some Scene {
        WindowGroup {
            WatchSetupView(controller: controller)
        }
    }
}
