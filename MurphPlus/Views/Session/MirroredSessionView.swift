// MurphPlus/Views/Session/MirroredSessionView.swift
import SwiftUI

/// Read-only reflection of a session owned by the Apple Watch.
///
/// A distinct view rather than a second mode on `LiveSessionView`: it shares
/// the design language but shares no interaction at all. Single-writer means
/// the phone may display and never act, and a screen that looks like the
/// controllable one but ignores every tap is worse than one that plainly is
/// not it.
struct MirroredSessionView: View {
    let mirror: LiveMirrorStore

    var body: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.gapSection) {
            // The staleness line is deliberate. The live channel fails
            // silently by design, so a frozen clock with no explanation would
            // read as a stalled workout rather than a dropped link.
            MurphBanner(
                tone: mirror.isStale ? .warn : .info,
                text: mirror.isStale
                    ? "Controlled by Apple Watch · Disconnected, showing last known state"
                    : "Controlled by Apple Watch · Live"
            )

            if let state = mirror.state {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    MurphClock(
                        label: "Elapsed",
                        seconds: SessionDerivation.elapsed(state, now: .now),
                        size: .lg,
                        running: !state.isPaused && !mirror.isStale
                    )
                }

                MurphFlowLayout {
                    MurphBadge(tone: .live, dot: true, title: phaseLabel(state.phase))
                    if state.isPaused {
                        MurphBadge(tone: .abandoned, title: "Paused")
                    }
                    if let bpm = state.latestHeartRate {
                        MurphBadge(title: "\(bpm) bpm")
                    }
                }

                if let template = state.template {
                    MurphSplitRow(
                        label: "Rounds",
                        value: "\(state.completedRounds) of \(template.rounds)",
                        tone: .accent
                    )
                }
            }
        }
        .padding(MurphSpacing.gutterScreen)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .murphScreenBackground()
        .murphNavBar(title: "Live session")
    }

    private func phaseLabel(_ phase: SessionPhase) -> String {
        switch phase {
        case .notStarted: "Starting"
        case .run1: "Run 1"
        case .rounds: "Rounds"
        case .run2: "Run 2"
        case .completed: "Complete"
        }
    }
}
