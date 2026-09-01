// MurphPlus/Views/Start/StartView.swift
import SwiftUI
import SwiftData

struct StartView: View {
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]
    @State private var selectedTemplate: WorkoutTemplate?
    @State private var vestOn = false
    @State private var vestWeightText = ""
    @State private var showTemplateEditor = false

    let onBegin: (WorkoutTemplate, Bool, Int?) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MurphScreenTitle(title: "Start Murph")

                    VStack(alignment: .leading, spacing: MurphSpacing.gapSection) {
                        workoutSection
                        vestSection

                        MurphButton(
                            variant: .primary,
                            size: .lg,
                            full: true,
                            icon: Image(systemName: "play.fill"),
                            title: "Begin"
                        ) {
                            guard let selectedTemplate else { return }
                            let weight = vestOn ? Int(vestWeightText) : nil
                            onBegin(selectedTemplate, vestOn, weight)
                        }
                        .disabled(selectedTemplate == nil)
                    }
                    .padding(.horizontal, MurphSpacing.gutterScreen)
                    .padding(.bottom, MurphSpacing.space8)
                }
            }
            .murphScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if selectedTemplate == nil {
                    selectedTemplate = templates.first
                }
            }
            .sheet(isPresented: $showTemplateEditor) {
                TemplateEditorView()
            }
        }
    }

    private var workoutSection: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.gapStack) {
            MurphSectionHeader("Workout") {
                MurphButton(variant: .ghost, size: .sm, title: "New template") {
                    showTemplateEditor = true
                }
            }

            MurphSelectField(
                placeholder: "Choose a template",
                options: templates.indices.map { MurphSelectOption(id: String($0), label: templates[$0].name) },
                selection: Binding(
                    get: { selectedTemplate.flatMap { templates.firstIndex(of: $0) }.map(String.init) },
                    set: { idString in
                        guard let idString, let index = Int(idString), templates.indices.contains(index) else { return }
                        selectedTemplate = templates[index]
                    }
                )
            )

            if let template = selectedTemplate {
                MurphCard {
                    VStack(alignment: .leading, spacing: MurphSpacing.space5) {
                        MurphFlowLayout(maxWidth: MurphFlowWidth.card) {
                            MurphBadge(title: template.rounds == 1 ? "Straight sets" : "\(template.rounds) rounds")
                            MurphBadge(title: "\(template.totalReps) reps")
                            MurphBadge(title: "\(template.runDistanceMiles.formatted(.number.precision(.fractionLength(2)))) mi \u{00d7} 2")
                        }
                        HStack(spacing: MurphSpacing.space3) {
                            repStat(label: "Pull-ups", value: template.totalPullUps)
                            repStat(label: "Push-ups", value: template.totalPushUps)
                            repStat(label: "Squats", value: template.totalSquats)
                        }
                    }
                }
            }
        }
    }

    private func repStat(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: MurphSpacing.space1 + 2) {
            Text(label)
                .murphType(.micro)
                .foregroundStyle(MurphColor.textMuted)
            Text("\(value)")
                .murphType(.metric())
                .foregroundStyle(MurphColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var vestSection: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.gapStack) {
            MurphSectionHeader("Vest")
            MurphToggle(label: "Wearing a weighted vest", description: "Defaults to 20 lbs if left blank", isOn: $vestOn)
            if vestOn {
                MurphTextField(text: $vestWeightText, placeholder: "20", suffix: "lbs", keyboardType: .numberPad)
            }
        }
    }
}

#Preview {
    StartView { _, _, _ in }
        .modelContainer(for: [WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self], inMemory: true)
}
