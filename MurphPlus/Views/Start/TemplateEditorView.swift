// MurphPlus/Views/Start/TemplateEditorView.swift
import SwiftUI
import SwiftData

struct TemplateEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var runDistanceMiles = 1.0
    @State private var totalPullUps = 100
    @State private var totalPushUps = 200
    @State private var totalSquats = 300
    @State private var rounds = 1

    // Reps are partitioned by integer division (totals / rounds), so a rounds
    // count larger than an exercise's total yields ZERO reps of that exercise
    // per round — e.g. 5 pull-ups across 50 rounds gives pullUpsPerRound == 0,
    // a round that asks for no pull-ups at all. Guarding here keeps that
    // template from being created in the first place.
    private var roundsFitEveryExercise: Bool {
        totalPullUps >= rounds && totalPushUps >= rounds && totalSquats >= rounds
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && runDistanceMiles > 0
            && totalPullUps > 0 && totalPushUps > 0 && totalSquats > 0
            && rounds > 0
            && roundsFitEveryExercise
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MurphSpacing.gapSection) {
                    VStack(alignment: .leading, spacing: MurphSpacing.gapStack) {
                        MurphSectionHeader("Name")
                        MurphTextField(text: $name, placeholder: "e.g. Half Murph")
                    }

                    VStack(alignment: .leading, spacing: MurphSpacing.gapStack) {
                        MurphSectionHeader("Runs")
                        MurphStepper(
                            label: "Distance each",
                            value: $runDistanceMiles,
                            display: String(format: "%.2f mi", runDistanceMiles),
                            step: 0.25, minValue: 0.25, maxValue: 5
                        )
                    }

                    VStack(alignment: .leading, spacing: MurphSpacing.gapStack) {
                        MurphSectionHeader("Total reps")
                        MurphStepper(label: "Pull-ups", intValue: $totalPullUps, step: 5, min: 1, max: 1000)
                        MurphStepper(label: "Push-ups", intValue: $totalPushUps, step: 5, min: 1, max: 1000)
                        MurphStepper(label: "Squats", intValue: $totalSquats, step: 5, min: 1, max: 1000)
                    }

                    VStack(alignment: .leading, spacing: MurphSpacing.gapStack) {
                        MurphSectionHeader("Partitioning")
                        MurphStepper(
                            label: rounds == 1 ? "Straight sets" : "Rounds",
                            intValue: $rounds, min: 1, max: 50
                        )
                        if !roundsFitEveryExercise {
                            // A disabled Save with no explanation is a dead end —
                            // say which way the numbers conflict.
                            MurphBanner(tone: .error, text: "Too many rounds to divide these reps: each exercise needs at least one rep per round. Lower the rounds or raise the reps.")
                        } else {
                            MurphCard {
                                MurphFlowLayout(maxWidth: MurphFlowWidth.card) {
                                    MurphBadge(title: "\(totalPullUps + totalPushUps + totalSquats) reps")
                                    if rounds > 1 {
                                        MurphBadge(title: "\(totalPullUps / rounds) / \(totalPushUps / rounds) / \(totalSquats / rounds) per round")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, MurphSpacing.gutterScreen)
                .padding(.top, MurphSpacing.space2)
                .padding(.bottom, MurphSpacing.space8)
            }
            .murphScreenBackground()
            .murphNavBar(title: "New template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    MurphButton(variant: .ghost, size: .sm, title: "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    MurphButton(variant: .primary, size: .sm, title: "Save") {
                        let template = WorkoutTemplate(
                            name: name,
                            runDistanceMiles: runDistanceMiles,
                            totalPullUps: totalPullUps,
                            totalPushUps: totalPushUps,
                            totalSquats: totalSquats,
                            rounds: rounds
                        )
                        context.insert(template)
                        try? context.save()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
