// MurphPlusWatch/Views/WatchLiveView.swift
import SwiftUI

/// Four fixed slots, **hard stops at both ends** — a plain paged `TabView` with
/// the system indicator. No wrap-around: `TabView` does not support it, faking
/// it needs clone pages and programmatic selection snapping, and the built-in
/// Workout app does not wrap either.
///
/// `selection` is deliberately never reset when the phase changes: finish run 1
/// while reading the clock page and you stay on the clock page. The workout
/// changed underneath you; your position did not.
struct WatchLiveView: View {
    @Bindable var controller: WatchSessionController

    @State private var selection = 1          // Count page is the landing page
    @State private var showAbandonConfirm = false
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 60 : 1)) { _ in
            TabView(selection: $selection) {
                ControlsPage(
                    controller: controller,
                    elapsedText: elapsedText,
                    showAbandonConfirm: $showAbandonConfirm
                )
                .tag(0)

                PrimaryPage(controller: controller, elapsedText: elapsedText)
                    .tag(1)

                ClockPage(controller: controller, elapsedText: elapsedText)
                    .tag(2)

                NowPlayingPage()
                    .tag(3)
            }
            .tabViewStyle(.verticalPage)
        }
        .navigationBarBackButtonHidden(true)
        .confirmationDialog(
            "Abandon this session?",
            isPresented: $showAbandonConfirm,
            titleVisibility: .visible
        ) {
            Button("Abandon", role: .destructive) { controller.abandon() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Your progress so far is kept.")
        }
        .navigationDestination(isPresented: .constant(controller.isFinished)) {
            WatchCompleteView(controller: controller)
        }
    }

    /// In the dimmed always-on state the clock renders at minute resolution,
    /// matching the once-a-minute update budget the system expects.
    private var elapsedText: String {
        let total = Int(controller.elapsed)
        if isLuminanceReduced {
            return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
