// MurphPlusWatch/Views/Pages/ControlsPage.swift
import SwiftUI

/// Slot 1 — pause/resume, undo, abandon. Destructive and corrective actions
/// live here rather than beside the button tapped twenty times while exhausted.
///
/// Undo is **disabled rather than absent** when unavailable, so the page does
/// not reshuffle mid-workout.
struct ControlsPage: View {
    @Bindable var controller: WatchSessionController
    let elapsedText: String
    @Binding var showAbandonConfirm: Bool

    var body: some View {
        VStack(spacing: 0) {
            WatchStatusStrip(
                leading: .init(label: "Elapsed", value: elapsedText, tone: MurphColor.hazard500),
                trailing: .init(label: "Round",
                                value: "\(controller.state.completedRounds)/\(controller.state.template?.rounds ?? 0)")
            )

            Spacer(minLength: 0)

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
