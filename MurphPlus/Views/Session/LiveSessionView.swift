// MurphPlus/Views/Session/LiveSessionView.swift
import SwiftUI
import UIKit

private struct PhaseCopy {
    let label: String
    let action: String
    let icon: String
}

private let phaseCopy: [SessionPhase: PhaseCopy] = [
    .notStarted: PhaseCopy(label: "Not started", action: "Start run 1", icon: "play.fill"),
    .run1: PhaseCopy(label: "Run 1", action: "Finish run 1", icon: "figure.run"),
    .rounds: PhaseCopy(label: "Rounds", action: "Round done", icon: "arrow.triangle.2.circlepath"),
    .run2: PhaseCopy(label: "Run 2", action: "Finish run 2", icon: "flag.fill"),
    .completed: PhaseCopy(label: "Completed", action: "Done", icon: "checkmark"),
]

struct LiveSessionView: View {
    let engine: SessionEngine
    let onFinished: () -> Void

    @State private var showAbandonConfirm = false

    private var session: MurphSession { engine.session }
    private var phase: SessionPhase { session.phase }

    /// Begin was tapped but Start Run 1 never was — nothing is recorded, so
    /// leaving here discards rather than logs.
    private var neverStarted: Bool { session.startedAt == nil }
    private var copy: PhaseCopy { phaseCopy[phase] ?? phaseCopy[.notStarted]! }

    var body: some View {
        NavigationStack {
            ZStack {
                content
                if showAbandonConfirm {
                    MurphDialog(
                        title: neverStarted ? "Discard this session?" : "Abandon this session?",
                        body: neverStarted
                            ? "Nothing has been recorded yet, so it won't be logged as an attempt."
                            : "It stays in your history, flagged incomplete.",
                        onDismiss: { showAbandonConfirm = false }
                    ) {
                        MurphButton(variant: .danger, full: true, title: neverStarted ? "Discard" : "Abandon") {
                            showAbandonConfirm = false
                            // Dismiss BEFORE mutating: a never-started session is
                            // deleted by `abandon()`, and this view is bound to it,
                            // so deleting first can leave a body evaluation reading
                            // a deleted model. Same ordering as the delete path in
                            // SessionDetailView.
                            onFinished()
                            engine.abandon()
                        }
                        MurphButton(variant: .secondary, full: true, title: "Keep going") {
                            showAbandonConfirm = false
                        }
                    }
                }
            }
            .murphScreenBackground()
            .murphNavBar(title: "Live session")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // One slot, two phases. During a session it carries Abandon,
                    // which keeps the destructive action out of the thumb zone
                    // under "Round Done". At completion it becomes Close.
                    // Previously this held a Close button that was disabled —
                    // and so visibly inert — for the entire workout.
                    if phase == .completed {
                        MurphIconButton(label: "Close", systemImage: "xmark") {
                            onFinished()
                        }
                    } else {
                        // .sm renders 36pt tall, under MurphSpacing.tapMin (44pt).
                        // Keep the small visual (a .md danger button here would
                        // read as oversized chrome in a nav bar) but pad the tap
                        // target out to the minimum, since this is the only
                        // danger-variant control in the app below that minimum.
                        // "Cancel" before the clock starts, "Abandon" after: the
                        // pre-start action discards an empty session rather than
                        // logging an attempt, and calling that "Abandon" would
                        // look like the record went missing.
                        MurphButton(variant: .danger, size: .sm, title: neverStarted ? "Cancel" : "Abandon") {
                            showAbandonConfirm = true
                        }
                        .frame(minHeight: MurphSpacing.tapMin)
                    }
                }
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var content: some View {
        VStack(spacing: 0) {
            MurphFlowLayout {
                MurphBadge(tone: .live, dot: true, title: copy.label)
                if session.vestOn, let weight = session.vestWeightLbs {
                    MurphBadge(tone: .vest, title: "\(weight) lb vest")
                }
                if let template = session.template {
                    MurphBadge(title: template.rounds == 1 ? "Straight sets" : "\(template.rounds) rounds")
                }
                if engine.isPaused {
                    MurphBadge(tone: .abandoned, title: "Paused")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MurphSpacing.gutterScreen)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                MurphClock(
                    label: "Elapsed",
                    seconds: engine.totalElapsed,
                    size: .lg,
                    running: phase != .notStarted && phase != .completed && !engine.isPaused,
                    tone: phase == .completed ? .accent : .default
                )
            }
            .padding(.init(top: MurphSpacing.space6, leading: MurphSpacing.gutterScreen, bottom: MurphSpacing.space5, trailing: MurphSpacing.gutterScreen))
            .frame(maxWidth: .infinity, alignment: .leading)

            HazardRule(height: 8, width: nil)

            ScrollView {
                VStack(alignment: .leading, spacing: MurphSpacing.gapSection) {
                    phaseBody
                    if !session.runSplits.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            MurphSectionHeader("Logged")
                            ForEach(session.runSplits.sorted { $0.runIndex < $1.runIndex }, id: \.persistentModelID) { split in
                                MurphSplitRow(label: "Run \(split.runIndex)", value: formatDuration(split.durationSeconds), tone: .accent)
                            }
                        }
                    }
                    if phase == .completed {
                        Text("Logged to your history.")
                            .murphType(.body)
                            .foregroundStyle(MurphColor.textMuted)
                    }
                }
                .padding(MurphSpacing.gutterScreen)
            }

            VStack(spacing: MurphSpacing.space3) {
                MurphButton(variant: .primary, size: .lg, full: true, icon: Image(systemName: copy.icon), title: copy.action) {
                    advance()
                }
                .disabled(engine.isPaused)
                if phase != .notStarted && phase != .completed {
                    MurphButton(
                        variant: .secondary,
                        full: true,
                        icon: Image(systemName: engine.isPaused ? "play.fill" : "pause.fill"),
                        title: engine.isPaused ? "Resume" : "Pause"
                    ) {
                        if engine.isPaused { engine.resume() } else { engine.pause() }
                    }
                }
            }
            .padding(.init(top: MurphSpacing.space4, leading: MurphSpacing.gutterScreen, bottom: MurphSpacing.space8, trailing: MurphSpacing.gutterScreen))
            .overlay(alignment: .top) {
                Rectangle().fill(MurphColor.lineHairline).frame(height: MurphShape.borderHair)
            }
        }
    }

    @ViewBuilder
    private var phaseBody: some View {
        if phase == .rounds, let template = session.template {
            MurphRoundCounter(
                current: session.completedRounds + 1,
                total: template.rounds,
                repsLabel: "\(template.pullUpsPerRound) pull-ups \u{00b7} \(template.pushUpsPerRound) push-ups \u{00b7} \(template.squatsPerRound) squats"
            )
        } else if phase == .notStarted, let template = session.template {
            VStack(alignment: .leading, spacing: MurphSpacing.space2) {
                Text("\(template.runDistanceMiles.formatted(.number.precision(.fractionLength(2)))) mile run, \(template.totalPullUps) pull-ups, \(template.totalPushUps) push-ups, \(template.totalSquats) squats, \(template.runDistanceMiles.formatted(.number.precision(.fractionLength(2)))) mile run.")
                    .murphType(.bodyLg)
                    .foregroundStyle(MurphColor.textSecondary)

                // How the work is partitioned, stated rather than left as
                // division. Once the rounds begin MurphRoundCounter shows the
                // same breakdown under the round numeral; this is the view of
                // it before the clock starts.
                if template.rounds > 1 {
                    Text("\(template.rounds) rounds of \(template.pullUpsPerRound) pull-ups \u{00b7} \(template.pushUpsPerRound) push-ups \u{00b7} \(template.squatsPerRound) squats")
                        .murphType(.bodySm)
                        .foregroundStyle(MurphColor.textAccent)
                }
            }
        } else if phase == .run1 || phase == .run2, let template = session.template {
            HStack(spacing: MurphSpacing.space4) {
                Image(systemName: "figure.run")
                    .font(.system(size: 30))
                    .foregroundStyle(MurphColor.hazard500)
                Text("\(template.runDistanceMiles.formatted(.number.precision(.fractionLength(2)))) mile \(phase == .run1 ? "out" : "back")")
                    .murphType(.display3())
                    .foregroundStyle(MurphColor.textPrimary)
            }
        }
    }

    private func advance() {
        switch phase {
        case .notStarted:
            engine.start()
        case .run1:
            engine.finishRun()
        case .rounds:
            engine.completeRound()
        case .run2:
            engine.finishRun()
        case .completed:
            onFinished()
        }
    }
}
