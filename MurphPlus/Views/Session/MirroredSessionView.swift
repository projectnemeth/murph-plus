// MurphPlus/Views/Session/MirroredSessionView.swift
import SwiftUI

/// Read-only reflection of a session owned by the Apple Watch.
///
/// A distinct view rather than a second mode on `LiveSessionView`: it shares
/// the design language but shares no interaction at all. Single-writer means
/// the phone may display and never act, and a screen that looks like the
/// controllable one but ignores every tap is worse than one that plainly is
/// not it.
///
/// It keeps its own copy of the last state it was shown. `LiveMirrorStore`
/// clears itself the moment the workout ends — the phone's own history is the
/// record from then on, and a lingering mirror would draw the session twice —
/// which left this screen blank and then yanked away mid-glance, with nothing
/// ever saying the workout had finished. The cached copy is what the completion
/// state is drawn from.
struct MirroredSessionView: View {
    let mirror: LiveMirrorStore

    @Environment(\.dismiss) private var dismiss
    @State private var lastState: SessionState?
    @State private var didFinish = false

    var body: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.gapSection) {
            if didFinish {
                MurphBanner(
                    tone: .info,
                    text: "Workout complete on Apple Watch \u{00b7} Saved to History"
                )
            } else {
                // The staleness line is deliberate. The live channel fails
                // silently by design, so a frozen clock with no explanation would
                // read as a stalled workout rather than a dropped link.
                MurphBanner(
                    tone: mirror.isStale ? .warn : .info,
                    text: mirror.isStale
                        ? "Controlled by Apple Watch \u{00b7} Disconnected, showing last known state"
                        : "Controlled by Apple Watch \u{00b7} Live"
                )
            }

            if let state = lastState {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    MurphClock(
                        label: "Elapsed",
                        seconds: SessionDerivation.elapsed(state, now: .now),
                        size: .lg,
                        running: !didFinish && !state.isPaused && !mirror.isStale,
                        tone: didFinish ? .accent : .default
                    )
                }

                MurphFlowLayout {
                    MurphBadge(
                        tone: didFinish ? .complete : .live,
                        dot: !didFinish,
                        title: didFinish ? "Complete" : phaseLabel(state.phase)
                    )
                    if state.isPaused, !didFinish {
                        MurphBadge(tone: .abandoned, title: "Paused")
                    }
                    if let bpm = state.latestHeartRate, !didFinish {
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

            if didFinish {
                // Dismissed by the user, not by the store. Leaving on a
                // completion the reader has actually seen is the whole point of
                // this state existing.
                MurphButton(variant: .primary, full: true, title: "Done") { dismiss() }
            }
        }
        .padding(MurphSpacing.gutterScreen)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .murphScreenBackground()
        .murphNavBar(title: didFinish ? "Workout complete" : "Live session")
        .onAppear { lastState = mirror.state }
        // `lastUpdate` is the honest signal for both halves: it moves on every
        // live event, and `LiveMirrorStore.clear()` nils it — which happens only
        // when the session ends. A dropped link leaves it set (that is
        // staleness, a different thing), so this cannot mistake one for the
        // other.
        .onChange(of: mirror.lastUpdate) { _, update in
            if update != nil {
                lastState = mirror.state
            } else if lastState != nil {
                didFinish = true
            }
        }
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
