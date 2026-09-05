// MurphPlusWatch/MurphPlusWatchApp.swift
import SwiftUI

@main
struct MurphPlusWatchApp: App {
    /// One coordinator for the whole app: it claims `WCSession.default.delegate`,
    /// so a second would displace it and silently stop delivering context.
    @State private var sync: WatchSyncCoordinator
    @State private var controller: WatchSessionController

    init() {
        let sync = WatchSyncCoordinator()
        _sync = State(initialValue: sync)
        _controller = State(initialValue: WatchSessionController(sync: sync))
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // Layout harness: opens the live pages directly for screenshotting.
            // See `WatchLayoutHarness` — the simulator cannot be tapped, so
            // this is the only way to look at those pages from the CLI.
            if WatchLayoutHarness.isActive {
                WatchLayoutHarnessView()
            } else {
                WatchSetupView(controller: controller, sync: sync)
            }
            #else
            WatchSetupView(controller: controller, sync: sync)
            #endif
        }
    }
}
