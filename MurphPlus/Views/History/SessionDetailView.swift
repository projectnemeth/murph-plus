// MurphPlus/Views/History/SessionDetailView.swift
import SwiftUI
import SwiftData

struct SessionDetailView: View {
    @Bindable var session: MurphSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]

    @State private var showDeleteConfirm = false
    @State private var targetTemplate: WorkoutTemplate?

    private var roundThroughputs: [RoundThroughput] {
        RoundThroughputBuilder.build(session: session)
    }

    private var run1: RunSplit? { session.runSplits.first { $0.runIndex == 1 } }
    private var run2: RunSplit? { session.runSplits.first { $0.runIndex == 2 } }

    // MARK: - Prediction (moved from PredictionControlView)

    private var pace: FatiguePrediction.RunPace? {
        guard
            let run1, let run2,
            let template = session.template,
            template.runDistanceMiles > 0
        else { return nil }
        return FatiguePrediction.RunPace(
            run1SecondsPerMile: run1.durationSeconds / template.runDistanceMiles,
            run2SecondsPerMile: run2.durationSeconds / template.runDistanceMiles
        )
    }

    private var sourceWorkSeconds: Double {
        roundThroughputs.reduce(0) { $0 + Double($1.secondsForRound) }
    }

    private var sourceTotalReps: Int {
        session.template?.totalReps ?? 0
    }

    // Per the spec, the control is absent — not merely disabled — until this
    // session has the run data a prediction is derived from.
    private var predictable: Bool { pace != nil }

    private var predictionResult: FatiguePrediction.PredictionResult? {
        guard let targetTemplate, let pace else { return nil }
        return FatiguePrediction.predict(
            targetRunDistanceMiles: targetTemplate.runDistanceMiles,
            targetTotalReps: targetTemplate.totalReps,
            sourceRoundThroughputs: roundThroughputs,
            sourceWorkSeconds: sourceWorkSeconds,
            sourceTotalReps: sourceTotalReps,
            pace: pace
        )
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MurphSpacing.gapSection) {
                    header
                    summaryCard
                    progressLine
                    if run1 != nil || run2 != nil { splitsSection }
                    if !roundThroughputs.isEmpty { roundsSection }
                    notesSection
                    if predictable { predictionSection }

                    MurphButton(variant: .danger, full: true, icon: Image(systemName: "trash"), title: "Delete session") {
                        showDeleteConfirm = true
                    }
                }
                .padding(.horizontal, MurphSpacing.gutterScreen)
                .padding(.top, MurphSpacing.space2)
                .padding(.bottom, MurphSpacing.space8)
            }
            .murphScreenBackground()
            .murphNavBar(title: session.date.formatted(date: .abbreviated, time: .omitted))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MurphIconButton(label: "Back", systemImage: "arrow.left") { dismiss() }
                }
            }

            if showDeleteConfirm {
                MurphDialog(
                    title: "Delete this session?",
                    body: "Logged times can't be edited, and this can't be undone.",
                    onDismiss: { showDeleteConfirm = false }
                ) {
                    MurphButton(variant: .danger, full: true, title: "Delete") {
                        showDeleteConfirm = false
                        // Dismiss before deleting: this view is @Bindable on `session` and the
                        // parent still holds it in navigationDestination(item:), so deleting
                        // first can leave a body evaluation reading a deleted model.
                        dismiss()
                        context.delete(session)
                        do {
                            try context.save()
                        } catch {
                            // A destructive action must not silently report success.
                            assertionFailure("Failed to delete session: \(error)")
                        }
                    }
                    MurphButton(variant: .secondary, full: true, title: "Cancel") {
                        showDeleteConfirm = false
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.space3) {
            Text(session.template?.name ?? "Murph")
                .murphType(.display3())
                .foregroundStyle(MurphColor.textPrimary)
            MurphFlowLayout {
                MurphBadge(
                    tone: session.status == .completed ? .complete : .abandoned,
                    dot: true,
                    title: session.status == .completed ? "Completed" : "Abandoned"
                )
                if session.vestOn {
                    MurphBadge(tone: .vest, title: "\(session.vestWeightLbs ?? 20) lb vest")
                } else {
                    MurphBadge(title: "No vest")
                }
            }
        }
    }

    private var summaryCard: some View {
        MurphCard {
            HStack(alignment: .bottom) {
                if session.status == .completed {
                    MurphClock(label: "Total time", seconds: session.totalElapsedSeconds ?? 0, size: .md)
                } else if let elapsed = session.totalElapsedSeconds {
                    MurphClock(label: "Stopped at", seconds: elapsed, size: .md)
                } else {
                    // Abandoning before Start leaves startedAt nil, so there is no
                    // real duration to show. An em-dash beats inventing a zero —
                    // the progress line already says "Stopped before starting".
                    MurphStatTile(label: "Stopped at", value: "\u{2014}", caption: "Never started")
                }
                Spacer()
                MurphStatTile(label: "Reps", value: "\(session.template?.totalReps ?? 0)", alignTrailing: true)
            }
        }
    }

    @ViewBuilder
    private var progressLine: some View {
        if let text = SessionProgressDescriber.describe(
            phase: session.phase,
            roundsCompleted: session.completedRounds,
            totalRounds: session.template?.rounds ?? 0,
            repsPerRound: session.template?.repsPerRound ?? 0
        ) {
            Text(text)
                .murphType(.bodySm)
                .foregroundStyle(MurphColor.textMuted)
        }
    }

    private var splitsSection: some View {
        let maxDuration = max(run1?.durationSeconds ?? 0, run2?.durationSeconds ?? 0, 1)
        return VStack(alignment: .leading, spacing: 0) {
            MurphSectionHeader("Splits")
            if let run1 {
                MurphSplitRow(label: "Run 1", value: formatDuration(run1.durationSeconds), fraction: run1.durationSeconds / maxDuration, tone: .accent)
            }
            if let run2 {
                MurphSplitRow(label: "Run 2", value: formatDuration(run2.durationSeconds), fraction: run2.durationSeconds / maxDuration, tone: .accent)
            }
        }
    }

    private var roundsSection: some View {
        let maxSplit = Double(roundThroughputs.map(\.secondsForRound).max() ?? 1)
        return VStack(alignment: .leading, spacing: 0) {
            MurphSectionHeader("Rounds")
            ForEach(Array(roundThroughputs.enumerated()), id: \.offset) { index, round in
                MurphSplitRow(
                    label: "Round \(String(format: "%02d", index + 1))",
                    value: "\(round.secondsForRound)s",
                    fraction: Double(round.secondsForRound) / maxSplit
                )
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.gapStack) {
            MurphSectionHeader("Notes")
            TextEditor(text: Binding(get: { session.notes ?? "" }, set: { session.notes = $0 }))
                .murphType(.body)
                .foregroundStyle(MurphColor.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(MurphSpacing.space3)
                .background(MurphColor.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: MurphShape.radiusSm)
                        .strokeBorder(MurphColor.lineHairline, lineWidth: MurphShape.borderHair)
                )
                .clipShape(RoundedRectangle(cornerRadius: MurphShape.radiusSm))
        }
    }

    private var predictionSection: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.gapStack) {
            MurphSectionHeader("Predict another distance")
            MurphSelectField(
                placeholder: "Choose a template",
                options: templates.indices.map { MurphSelectOption(id: String($0), label: templates[$0].name) },
                selection: Binding(
                    get: { targetTemplate.flatMap { templates.firstIndex(of: $0) }.map(String.init) },
                    set: { idString in
                        guard let idString, let index = Int(idString), templates.indices.contains(index) else { return }
                        targetTemplate = templates[index]
                    }
                )
            )

            if let result = predictionResult {
                MurphCard(tone: .accent) {
                    VStack(alignment: .leading, spacing: MurphSpacing.space1 + 2) {
                        Text("Predicted time")
                            .murphType(.tag)
                        Text(formatDuration(result.totalSeconds))
                            .murphType(.clock(40))
                    }
                }
                MurphBanner(
                    tone: roundThroughputs.count >= 3 ? .info : .warn,
                    text: roundThroughputs.count >= 3
                        ? "Based on this session's fatigue curve."
                        : "Based on this session's flat average pace (not enough rounds for a fatigue curve)."
                )
                MurphBanner(
                    tone: .info,
                    text: "Assumes the same vest status as this session: \(session.vestOn ? "\(session.vestWeightLbs ?? 20) lbs" : "no vest")."
                )
            }
        }
    }
}
