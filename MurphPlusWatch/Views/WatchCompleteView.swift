// MurphPlusWatch/Views/WatchCompleteView.swift
import SwiftUI

/// Total, average heart rate, and the three splits at a glance.
///
/// The PB badge arrived with Stage 3 and not before: until the phone pushed
/// its records down, the Watch held no history to compare against, and a badge
/// that cannot be trusted is worse than no badge.
struct WatchCompleteView: View {
    @Bindable var controller: WatchSessionController
    var sync: WatchSyncCoordinator
    /// Runs after the controller has been reset. Owned by `WatchLiveView`,
    /// which was handed it from `WatchSetupView` — Done needs to land all
    /// the way back on Setup with a clean controller, not just pop this one
    /// screen, so this is a passthrough rather than `@Environment(\.dismiss)`.
    let onDone: () -> Void

    /// The records as they stood when this screen appeared.
    ///
    /// Frozen on purpose. `sync.context` is `@Observable` and the phone pushes
    /// a fresh context after every terminal checkpoint it imports — including
    /// the one this very screen is reporting. Recomputed live, the newly
    /// imported session *is* the record it is being compared against, and
    /// `PersonalBestCheck`'s strict `<` turns `X < X` into false: the badge
    /// would appear and then vanish a couple of seconds later, on exactly the
    /// run that earned it, while the user is still looking at it. The snapshot
    /// is also the question actually worth asking — "did this beat the record
    /// as of when I finished".
    @State private var bestsAtAppear: [PersonalBest] = []

    /// Compared only against a record for the *same* vest setting — see
    /// `PersonalBestCheck`. An abandoned session is never a best regardless of
    /// its clock, because it did not finish the work.
    private var isPersonalBest: Bool {
        guard controller.state.status == .completed else { return false }
        return PersonalBestCheck.isPersonalBest(
            elapsed: SessionDerivation.elapsed(controller.state, now: .now),
            templateID: controller.state.template?.id,
            vestOn: controller.state.vestOn,
            among: bestsAtAppear
        )
    }

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

                if isPersonalBest {
                    Text("Personal best")
                        .murphType(.micro)
                        .foregroundStyle(MurphColor.ink1000)
                        .padding(.horizontal, MurphSpacing.space2)
                        .padding(.vertical, 3)
                        .background(MurphColor.lime500)
                        .clipShape(Capsule())
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

                Button("Done") {
                    controller.finishAndReset()
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .tint(MurphColor.lime500)
            }
            .padding(.horizontal, MurphSpacing.space2)
        }
        .background(MurphColor.surfacePage)
        .navigationBarBackButtonHidden(true)
        .onAppear { bestsAtAppear = sync.context?.personalBests ?? [] }
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
