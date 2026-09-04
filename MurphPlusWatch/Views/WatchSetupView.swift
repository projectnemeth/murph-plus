// MurphPlusWatch/Views/WatchSetupView.swift
import SwiftUI

/// Template list, then two segmented controls, then Start.
///
/// Vest and location are **segmented controls, not toggles**, and both states
/// are always visible. Vest is load-bearing data rather than a preference — the
/// prediction refuses to mix vest and non-vest sessions, so a wrong flag
/// silently disqualifies the session as source data. A lone toggle reads as a
/// settled state; showing the road not taken makes it read as a live choice.
struct WatchSetupView: View {
    @Bindable var controller: WatchSessionController

    @State private var templates: [TemplateSpec] = WatchSetupView.starterTemplates
    @State private var selected: TemplateSpec?
    @AppStorage("watchVestOn") private var vestOn = false
    @AppStorage("watchVestWeight") private var vestWeight = 20
    @AppStorage("watchIndoor") private var indoor = false
    @State private var showLive = false
    @State private var showResumePrompt = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MurphSpacing.space3) {
                    ForEach(templates, id: \.id) { template in
                        templateRow(template)
                    }

                    segmented(
                        left: "Vest", right: "No vest",
                        leftSelected: vestOn,
                        onLeft: { vestOn = true }, onRight: { vestOn = false }
                    )

                    if vestOn {
                        weightChip
                    }

                    segmented(
                        left: "Outdoor", right: "Indoor",
                        leftSelected: !indoor,
                        onLeft: { indoor = false }, onRight: { indoor = true }
                    )

                    Button("Start") {
                        guard let spec = selected ?? templates.first else { return }
                        Task {
                            await controller.startSession(
                                template: spec, vestOn: vestOn,
                                vestWeightLbs: vestOn ? vestWeight : nil, indoor: indoor
                            )
                            showLive = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MurphColor.hazard500)
                }
                .padding(.horizontal, MurphSpacing.space2)
            }
            .background(MurphColor.surfacePage)
            .navigationTitle("Murph+")
            .navigationDestination(isPresented: $showLive) {
                WatchLiveView(controller: controller, onDone: { showLive = false })
            }
        }
        .sheet(isPresented: $showResumePrompt) {
            resumePrompt
        }
        .task {
            await controller.requestAuthorization()
            // The spec offers resume *or* abandon here. Auto-resuming would
            // not just be unfaithful: it is the only escape from a journal
            // that cannot be made terminal (an unwritable volume), which
            // otherwise drops the user into the same phantom workout on every
            // launch with no way out.
            showResumePrompt = controller.hasResumableSession()
        }
    }

    /// Resume or abandon, with no dismiss-by-swipe: leaving the choice
    /// unmade is what the auto-resume bug effectively did.
    private var resumePrompt: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MurphSpacing.space3) {
                Text("Workout in progress")
                    .murphType(.bodySm)
                    .foregroundStyle(MurphColor.textPrimary)
                Text("Pick up where you left off, or discard it.")
                    .murphType(.micro)
                    .foregroundStyle(MurphColor.textMuted)

                Button("Resume") {
                    showResumePrompt = false
                    Task {
                        if (try? await controller.resumeExistingSession()) == true {
                            showLive = true
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(MurphColor.hazard500)

                Button("Discard") {
                    controller.abandonResumableSession()
                    showResumePrompt = false
                }
                .buttonStyle(.bordered)
                .tint(MurphColor.dust500)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MurphSpacing.space2)
        }
        .background(MurphColor.surfacePage)
        .interactiveDismissDisabled()
    }

    private func templateRow(_ template: TemplateSpec) -> some View {
        let isSelected = (selected ?? templates.first)?.id == template.id
        return Button {
            selected = template
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .murphType(.bodySm)
                    .foregroundStyle(MurphColor.textPrimary)
                Text(template.rounds == 1
                     ? "Straight sets"
                     : "\(template.rounds) rounds · \(template.pullUpsPerRound)/\(template.pushUpsPerRound)/\(template.squatsPerRound)")
                    .murphType(.micro)
                    .foregroundStyle(MurphColor.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MurphSpacing.space2)
            .background(isSelected ? MurphColor.hazard500.opacity(0.18) : MurphColor.surfaceRaised)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? MurphColor.hazard500 : MurphColor.lineHairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func segmented(
        left: String, right: String, leftSelected: Bool,
        onLeft: @escaping () -> Void, onRight: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 0) {
            segmentButton(left, selected: leftSelected, action: onLeft)
            segmentButton(right, selected: !leftSelected, action: onRight)
        }
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(MurphColor.lineStrong))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    private func segmentButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .murphType(.micro)
                .foregroundStyle(selected ? MurphColor.textOnAccent : MurphColor.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, MurphSpacing.space2)
                .background(selected ? MurphColor.hazard500 : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var weightChip: some View {
        HStack {
            Text("\(vestWeight) lb")
                .murphType(.metric(15))
                .foregroundStyle(MurphColor.textPrimary)
            Spacer()
            Text("crown")
                .murphType(.micro)
                .foregroundStyle(MurphColor.textMuted)
        }
        .padding(MurphSpacing.space2)
        .background(MurphColor.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .focusable()
        .digitalCrownRotation(
            .init(get: { Double(vestWeight) }, set: { vestWeight = Int($0) }),
            from: 5, through: 60, by: 5, sensitivity: .low
        )
    }

    /// Mirrors `DefaultTemplates` on the phone. Replaced by the synced list in
    /// Stage 3; kept here so this screen is fully exercisable before sync exists.
    static let starterTemplates: [TemplateSpec] = [
        TemplateSpec(id: UUID(), name: "Full Murph (Straight Sets)", runDistanceMiles: 1.0,
                     totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 1),
        TemplateSpec(id: UUID(), name: "Full Murph (Cindy-Style, 20 Rounds)", runDistanceMiles: 1.0,
                     totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 20),
        TemplateSpec(id: UUID(), name: "Half Murph", runDistanceMiles: 0.5,
                     totalPullUps: 50, totalPushUps: 100, totalSquats: 150, rounds: 10),
        TemplateSpec(id: UUID(), name: "Mini Murph", runDistanceMiles: 0.25,
                     totalPullUps: 25, totalPushUps: 50, totalSquats: 75, rounds: 5),
    ]
}
