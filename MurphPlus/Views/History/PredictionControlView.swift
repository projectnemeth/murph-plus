// MurphPlus/Views/History/PredictionControlView.swift
import SwiftUI
import SwiftData

struct PredictionControlView: View {
    let session: MurphSession
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]
    @State private var targetTemplate: WorkoutTemplate?

    private var sourceRoundThroughputs: [RoundThroughput] {
        RoundThroughputBuilder.build(session: session)
    }

    private var pace: FatiguePrediction.RunPace? {
        guard
            let run1 = session.runSplits.first(where: { $0.runIndex == 1 }),
            let run2 = session.runSplits.first(where: { $0.runIndex == 2 }),
            let template = session.template,
            template.runDistanceMiles > 0
        else { return nil }
        return FatiguePrediction.RunPace(
            run1SecondsPerMile: run1.durationSeconds / template.runDistanceMiles,
            run2SecondsPerMile: run2.durationSeconds / template.runDistanceMiles
        )
    }

    private var sourceWorkSeconds: Double {
        sourceRoundThroughputs.reduce(0) { $0 + Double($1.secondsForRound) }
    }

    private var sourceTotalReps: Int {
        session.template?.totalReps ?? 0
    }

    private var result: FatiguePrediction.PredictionResult? {
        guard let target = targetTemplate, let pace else { return nil }
        return FatiguePrediction.predict(
            targetRunDistanceMiles: target.runDistanceMiles,
            targetTotalReps: target.totalReps,
            sourceRoundThroughputs: sourceRoundThroughputs,
            sourceWorkSeconds: sourceWorkSeconds,
            sourceTotalReps: sourceTotalReps,
            pace: pace
        )
    }

    var body: some View {
        // Per the spec, the control is absent — not merely disabled — until this
        // session has the run data a prediction is derived from. An abandoned or
        // partial session simply shows no prediction UI at all.
        if pace != nil {
            predictionSection
        }
    }

    @ViewBuilder
    private var predictionSection: some View {
        Section("Predict Another Distance") {
            Picker("Target", selection: $targetTemplate) {
                Text("Choose a template").tag(WorkoutTemplate?.none)
                ForEach(templates) { template in
                    Text(template.name).tag(Optional(template))
                }
            }

            if let result {
                LabeledContent("Predicted Time", value: formatDuration(result.totalSeconds))
                Text(result.usedFatigueCurve
                     ? "Based on this session's fatigue curve."
                     : "Based on this session's flat average pace (not enough rounds for a fatigue curve).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Assumes the same vest status as this session: \(session.vestOn ? "\(session.vestWeightLbs ?? 20) lbs" : "no vest").")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
