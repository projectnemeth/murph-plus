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

    @Environment(PhoneSyncCoordinator.self) private var sync

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MurphScreenTitle(title: "Murph+")

                    VStack(alignment: .leading, spacing: MurphSpacing.gapSection) {
                        workoutSection
                        vestSection

                        // `isStale` is time-derived, so `@Observable` alone
                        // will not re-render when it flips; the timer forces
                        // a re-evaluation once a second.
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            if sync.mirror.isMirroring {
                                // Never offer Start while the Watch owns a
                                // session. Two live sessions is the one conflict
                                // this design refuses to resolve, so the guard is
                                // to make it unreachable rather than to merge it
                                // afterwards.
                                NavigationLink {
                                    MirroredSessionView(mirror: sync.mirror)
                                } label: {
                                    MurphBanner(
                                        tone: .info,
                                        text: "Session running on Apple Watch · Tap to follow along"
                                    )
                                }
                            } else {
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
                        }
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
                        // Per-round counts are shown only for a partitioned
                        // template. On straight sets they equal the totals, so
                        // repeating them would be noise.
                        HStack(spacing: MurphSpacing.space3) {
                            repStat(
                                label: "Pull-ups",
                                value: template.totalPullUps,
                                perRound: template.rounds > 1 ? template.pullUpsPerRound : nil
                            )
                            repStat(
                                label: "Push-ups",
                                value: template.totalPushUps,
                                perRound: template.rounds > 1 ? template.pushUpsPerRound : nil
                            )
                            repStat(
                                label: "Squats",
                                value: template.totalSquats,
                                perRound: template.rounds > 1 ? template.squatsPerRound : nil
                            )
                        }
                    }
                }
            }
        }
    }

    /// `value` is the workout total; `perRound` is what a single round costs,
    /// or nil for straight sets. Showing both means the reader never has to
    /// divide 25 by 5 rounds to find out this is a 5/10/15 set.
    private func repStat(label: String, value: Int, perRound: Int?) -> some View {
        VStack(alignment: .leading, spacing: MurphSpacing.space1 + 2) {
            Text(label)
                .murphType(.micro)
                .foregroundStyle(MurphColor.textMuted)
            Text("\(value)")
                .murphType(.metric())
                .foregroundStyle(MurphColor.textPrimary)
            if let perRound {
                Text("\(perRound) / round")
                    .murphType(.micro)
                    .foregroundStyle(MurphColor.textAccent)
            }
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
