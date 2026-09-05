// MurphPlusWatch/Views/Pages/ControlsPage.swift
import SwiftUI

/// Slot 1 — pause/resume, undo, abandon. Destructive and corrective actions
/// live here rather than beside the button tapped twenty times while exhausted.
///
/// Undo is **disabled rather than absent** when unavailable, so the page does
/// not reshuffle mid-workout.
///
/// **No status strip.** The other three pages carry the numbers; this page is
/// controls only. The strip here bought nothing — elapsed and the round count
/// are one swipe away on either metric page — while costing the collision with
/// the system clock that made the whole band unreadable at 46mm.
///
/// A `ScrollView` rather than a bare `VStack`, for two reasons: three buttons
/// plus the time indicator's clearance do not fit a 40mm screen, and a scroll
/// view is handed the system's top safe-area inset automatically, so the first
/// button clears the clock without a hard-coded constant. The built-in Workout
/// app's own controls page scrolls inside its paged tab view the same way.
struct ControlsPage: View {
    @Bindable var controller: WatchSessionController
    @Binding var showAbandonConfirm: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: MurphSpacing.space2) {
                Button(controller.isPaused ? "Resume" : "Pause") {
                    controller.isPaused ? controller.resume() : controller.pause()
                }
                .buttonStyle(.bordered)
                .tint(MurphColor.lime500)

                Button("Undo last round") { controller.undoLastRound() }
                    .buttonStyle(.bordered)
                    .disabled(!controller.canUndo)

                Button("Abandon", role: .destructive) { showAbandonConfirm = true }
                    .buttonStyle(.bordered)
            }
            .murphType(.micro)
            .padding(.horizontal, MurphSpacing.space2)
            .padding(.bottom, MurphSpacing.space2)
        }
        .background(MurphColor.surfacePage)
    }
}
