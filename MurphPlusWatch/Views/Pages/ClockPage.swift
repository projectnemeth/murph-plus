// MurphPlusWatch/Views/Pages/ClockPage.swift
import SwiftUI

/// Slot 3 — same content, roles swapped: elapsed time is the hero and the
/// round count moves into the strip. Carries the advancing button too.
struct ClockPage: View {
    @Bindable var controller: WatchSessionController
    let elapsedText: String

    var body: some View {
        VStack(spacing: 0) {
            WatchStatusStrip(
                leading: .init(label: "Round",
                               value: "\(controller.state.completedRounds)/\(controller.state.template?.rounds ?? 0)"),
                trailing: .init(label: "BPM",
                                value: controller.heartRate.map(String.init) ?? "—",
                                tone: MurphColor.lime500)
            )

            Spacer(minLength: 0)
            VStack(spacing: 4) {
                Text(controller.isPaused ? "Paused" : "Elapsed")
                    .murphType(.micro)
                    .foregroundStyle(controller.isPaused ? MurphColor.dust500 : MurphColor.textMuted)
                Text(elapsedText)
                    .murphType(.clock(36))
                    .foregroundStyle(MurphColor.textPrimary)
            }
            Spacer(minLength: 0)

            if controller.isPaused {
                WatchPrimaryButton(title: "Resume") { controller.resume() }
                    .padding(.horizontal, MurphSpacing.space2)
            } else {
                WatchPrimaryButton(title: controller.state.phase == .rounds ? "Round Done" : "End Run") {
                    controller.advance()
                }
                .padding(.horizontal, MurphSpacing.space2)
            }
        }
        .background(MurphColor.surfacePage)
    }
}
