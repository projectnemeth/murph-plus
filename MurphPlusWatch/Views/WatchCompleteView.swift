// MurphPlusWatch/Views/WatchCompleteView.swift
import SwiftUI

/// Total, average heart rate, and the three splits at a glance.
///
/// The PB badge is deliberately absent until Stage 3: the Watch holds no
/// history to compare against, and a badge that cannot be trusted is worse
/// than no badge.
struct WatchCompleteView: View {
    @Bindable var controller: WatchSessionController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: MurphSpacing.space3) {
                Text(controller.state.status == .abandoned ? "Stopped" : "Complete")
                    .murphType(.micro)
                    .foregroundStyle(controller.state.status == .abandoned
                                     ? MurphColor.dust500 : MurphColor.lime500)

                // The workout happened and this summary is real; what's
                // uncertain is only whether every event reached disk (and,
                // in a later stage, the phone). Say so plainly, but don't
                // alarm — nothing here is wrong, just possibly incomplete.
                if controller.journalWriteFailed {
                    Text("Some data may not have saved.")
                        .murphType(.micro)
                        .foregroundStyle(MurphColor.dust500)
                        .multilineTextAlignment(.center)
                }

                Text(totalText)
                    .murphType(.clock(34))
                    .foregroundStyle(MurphColor.textPrimary)

                if let average = averageHeartRate {
                    Text("Avg \(average) bpm")
                        .murphType(.micro)
                        .foregroundStyle(MurphColor.textSecondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(controller.state.runSplits, id: \.index) { split in
                        row("Run \(split.index)", formatted(split.durationSeconds))
                    }
                    row("Rounds", "\(controller.state.completedRounds) of \(controller.state.template?.rounds ?? 0)")
                }

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(MurphColor.lime500)
            }
            .padding(.horizontal, MurphSpacing.space2)
        }
        .background(MurphColor.surfacePage)
        .navigationBarBackButtonHidden(true)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).murphType(.micro).foregroundStyle(MurphColor.textMuted)
            Spacer()
            Text(value).murphType(.metric(14)).foregroundStyle(MurphColor.textPrimary)
        }
    }

    private var totalText: String {
        formatted(SessionDerivation.elapsed(controller.state, now: .now))
    }

    private var averageHeartRate: Int? {
        guard
            let events = controller.journal?.events,
            let start = controller.state.startedAt,
            let end = controller.state.completedAt
        else { return nil }
        return HeartRateAggregator.summary(events: events, from: start, to: end)?.average
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
