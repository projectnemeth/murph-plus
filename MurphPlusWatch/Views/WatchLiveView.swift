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
    var sync: WatchSyncCoordinator
    /// Called when the completion screen's Done button is tapped. Owned by
    /// `WatchSetupView`, which pops all the way back to the setup screen —
    /// popping only this view would strand the user on a live view for a
    /// session that has already finished.
    let onDone: () -> Void
    /// Which slot to land on. Only ever non-default from the DEBUG layout
    /// harness, which cannot swipe a simulator and so opens each page directly.
    var initialPage = 1

    @State private var selection = 1          // Count page is the landing page
    @State private var showAbandonConfirm = false
    @State private var didApplyInitialPage = false
    // Real, writable presentation state. `controller.isFinished` never goes
    // back to false on its own (there is no reset path on the controller
    // short of `finishAndReset()`, which only runs after Done is tapped), so
    // this can't just track it directly with `.constant(_:)` — that binding
    // discards writes, which is exactly what made the completion screen's
    // Done button a dead end. `onChange` below is the one-way sync from
    // controller state into this real, poppable binding.
    @State private var showComplete = false
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 60 : 1)) { _ in
            TabView(selection: $selection) {
                ControlsPage(
                    controller: controller,
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
            // Once, not on every appearance: `selection` is deliberately
            // never reset while a session is live (see above), and `onAppear`
            // fires again whenever this view comes back into view.
            .onAppear {
                guard !didApplyInitialPage else { return }
                didApplyInitialPage = true
                selection = initialPage
            }
        }
        .navigationBarBackButtonHidden(true)
        // The phase, level with the system clock, on every page at once.
        //
        // `topBarLeading` is the system's own slot for this — the built-in
        // Workout app puts its elapsed time there — so it is level with the
        // time by construction and inset clear of the round display's
        // corner by the system. Both are things the old in-band corner
        // label had to guess at, and got wrong at 46mm.
        //
        // Declared here rather than per page so it does not blink out and
        // back during a page swipe, and so the controls page — which no
        // longer carries a status band at all — still says what phase the
        // workout is in.
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if let phase = WatchPhaseLabel.text(
                    phase: controller.state.phase, isPaused: controller.isPaused
                ) {
                    Text(phase)
                        .murphType(.tag)
                        // Amber for paused: a user who paused and walked
                        // away needs to catch that without reading it.
                        .foregroundStyle(
                            controller.isPaused ? MurphColor.dust500 : MurphColor.bone200
                        )
                }
            }
        }
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
        .onChange(of: controller.isFinished) { _, isFinished in
            if isFinished { showComplete = true }
        }
        .navigationDestination(isPresented: $showComplete) {
            WatchCompleteView(controller: controller, sync: sync, onDone: onDone)
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
