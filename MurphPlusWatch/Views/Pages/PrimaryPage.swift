// MurphPlusWatch/Views/Pages/PrimaryPage.swift
import SwiftUI

/// Slot 2 — the only slot whose content changes with phase. It always holds
/// "the number that matters right now, plus the button that advances".
/// Distance during runs, round count during rounds, Resume while paused.
struct PrimaryPage: View {
    @Bindable var controller: WatchSessionController
    let elapsedText: String

    var body: some View {
        VStack(spacing: 0) {
            WatchStatusStrip(
                leading: .init(label: "Elapsed", value: elapsedText, tone: MurphColor.hazard500),
                trailing: .init(label: "BPM",
                                value: controller.heartRate.map(String.init) ?? "—",
                                tone: MurphColor.lime500),
                corner: WatchPhaseLabel.text(
                    phase: controller.state.phase, isPaused: controller.isPaused
                ),
                cornerTone: controller.isPaused ? MurphColor.dust500 : MurphColor.bone200
            )

            Spacer(minLength: MurphSpacing.space3)
            hero
            Spacer(minLength: MurphSpacing.space3)

            if controller.isPaused {
                WatchPrimaryButton(title: "Resume") { controller.resume() }
                    .padding(.horizontal, MurphSpacing.space2)
            } else {
                WatchPrimaryButton(title: advanceTitle) { controller.advance() }
                    .padding(.horizontal, MurphSpacing.space2)
            }
        }
        .background(MurphColor.surfacePage)
    }

    @ViewBuilder
    private var hero: some View {
        switch controller.state.phase {
        case .run1, .run2:
            VStack(spacing: 4) {
                Text("Distance")
                    .murphType(.micro)
                    .foregroundStyle(MurphColor.textMuted)
                Text(distanceText)
                    .murphType(.clock(38))
                    .foregroundStyle(MurphColor.textPrimary)
                Text(remainingText)
                    .murphType(.micro)
                    .foregroundStyle(MurphColor.textSecondary)
            }
        case .rounds:
            VStack(spacing: 4) {
                Text("Round")
                    .murphType(.micro)
                    .foregroundStyle(MurphColor.textMuted)
                Text("\(controller.state.completedRounds) / \(controller.state.template?.rounds ?? 0)")
                    .murphType(.clock(38))
                    .foregroundStyle(MurphColor.textPrimary)
                if let spec = controller.state.template {
                    Text("\(spec.pullUpsPerRound) pull·\(spec.pushUpsPerRound) push·\(spec.squatsPerRound) sqt")
                        .murphType(.microDense)
                        .lineLimit(1)
                        .foregroundStyle(MurphColor.textSecondary)
                }
            }
        case .notStarted, .completed:
            EmptyView()
        }
    }

    private var advanceTitle: String {
        switch controller.state.phase {
        case .run1, .run2: "End Run"
        case .rounds: "Round Done"
        case .notStarted, .completed: ""
        }
    }

    private var distanceText: String {
        guard let meters = controller.runDistanceMeters else { return "—" }
        return String(format: "%.2f", meters / 1609.34)
    }

    private var remainingText: String {
        guard
            let meters = controller.runDistanceMeters,
            let target = controller.state.template?.runDistanceMiles
        else { return "miles" }
        // Displayed, never acted on: GPS drift ending a run at 0.97 mi while
        // the user is still running is worse than a button.
        let remaining = max(0, target - meters / 1609.34)
        return String(format: "%.2f to go", remaining)
    }
}
