// MurphPlus/Views/Start/StartView.swift
import SwiftUI
import SwiftData

struct StartView: View {
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]
    @State private var selectedTemplate: WorkoutTemplate?
    @State private var vestOn = false
    @State private var vestWeightText = ""
    @State private var showTemplateEditor = false
    @State private var showDeleteTemplateConfirm = false
    @State private var showMirror = false
    @State private var indoor = false
    /// Reused verbatim from the watch. The phone is its second caller and adds
    /// nothing to it.
    @State private var gate = LocationFixGate()
    @State private var pendingSetup: SessionSetup?

    let location: PhoneLocationController
    /// Whether a session engine currently exists.
    ///
    /// Once one does, IT owns the receiver: `SessionEngine.reconcileLocation`
    /// asserts the correct state at every transition, and this screen must not
    /// countermand it. Load-bearing on the resume path — a session resumed
    /// mid-run has its receiver switched on by `SessionEngine.init`, and this
    /// view may disappear immediately afterwards as the cover presents over
    /// it. Stopping unconditionally there would kill the receiver for the rest
    /// of that run, with nothing to restart it until the next transition, by
    /// which point `finishRun` has already read the distance.
    ///
    /// Also guards against a second, narrower case: presenting the acquiring
    /// overlay (`fullScreenCover`) over this screen can itself fire
    /// `.onDisappear`. At gate time no engine exists yet, so this alone would
    /// read `false` and let the guard fall through to `stopUpdating()` — which
    /// would kill the very receiver the gate is polling and strand every
    /// outdoor session at the 30-second timeout. Hence the second condition,
    /// `!gate.isWaiting`, below: this screen must not stop the receiver while
    /// anything is still waiting on it.
    let sessionIsLive: Bool
    let onBegin: (SessionSetup) -> Void

    @Environment(PhoneSyncCoordinator.self) private var sync
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        MurphScreenTitle(title: "Murph+")

                        VStack(alignment: .leading, spacing: MurphSpacing.gapSection) {
                            workoutSection
                            locationSection
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
                                    //
                                    // A button into `navigationDestination`, not
                                    // a `NavigationLink`. A link's label
                                    // disappears the moment the Watch's session
                                    // ends, which pops the mirror out from under
                                    // a user still reading it — the completion
                                    // state `MirroredSessionView` now draws
                                    // would never be seen. Ending the
                                    // presentation is the user's to do.
                                    Button {
                                        showMirror = true
                                    } label: {
                                        MurphBanner(
                                            tone: .info,
                                            text: "Session running on Apple Watch · Tap to follow along",
                                            navigates: true
                                        )
                                    }
                                    .buttonStyle(.plain)
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
                                        let setup = SessionSetup(
                                            template: selectedTemplate, vestOn: vestOn,
                                            vestWeightLbs: weight, indoor: indoor
                                        )
                                        pendingSetup = setup
                                        Task {
                                            // Returns immediately for every
                                            // state except `.acquiring`: Indoor
                                            // is `.off`, a refusal is `.denied`
                                            // and waiting for a fix that will
                                            // never come is pure delay, and the
                                            // ordinary case is already `.fixed`.
                                            await gate.wait { location.fixState }
                                            guard let staged = pendingSetup else { return }
                                            pendingSetup = nil
                                            onBegin(staged)
                                        }
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
                .task {
                    await location.requestAuthorization()
                    reconcileWarmUp()
                }
                .onChange(of: indoor) { _, _ in reconcileWarmUp() }
                .onDisappear {
                    guard !sessionIsLive, !gate.isWaiting else { return }
                    location.stopUpdating()
                }
                .sheet(isPresented: $showTemplateEditor) {
                    TemplateEditorView()
                }
                .navigationDestination(isPresented: $showMirror) {
                    MirroredSessionView(mirror: sync.mirror)
                }
                .fullScreenCover(isPresented: Binding(
                    get: { gate.isWaiting },
                    // `set` also fires with `false` on NATURAL completion —
                    // `isWaiting` flips false on its own, and SwiftUI drives
                    // this setter — so `skip()` runs on an already-finished
                    // gate too. That's safe only because `LocationFixGate
                    // .wait()` resets `skipped` as its first synchronous
                    // statement, so this stray call can't leak into the next
                    // wait. If that reset ever moves into `skip()` itself,
                    // this call site regresses silently.
                    set: { if !$0 { gate.skip() } }
                )) {
                    acquiringOverlay
                }

                if showDeleteTemplateConfirm, let template = selectedTemplate {
                    deleteDialog(for: template)
                }
            }
        }
    }

    /// Says what survives, not just what goes. Sessions outlive their template
    /// by design (`.nullify`, so a tidy-up cannot erase logged times), but they
    /// lose its name — and a user who finds that out afterwards has no way back.
    private func deleteDialog(for template: WorkoutTemplate) -> some View {
        let affected = TemplateDeletion.affectedSessionCount(for: template)
        return MurphDialog(
            title: "Delete \u{201c}\(template.name)\u{201d}?",
            body: affected == 0
                ? "No sessions have used this template. This can\u{2019}t be undone."
                : "\(affected) session\(affected == 1 ? "" : "s") used this template. "
                    + "They\u{2019}re kept, but will lose its name. This can\u{2019}t be undone.",
            onDismiss: { showDeleteTemplateConfirm = false }
        ) {
            MurphButton(variant: .danger, full: true, title: "Delete") {
                showDeleteTemplateConfirm = false
                deleteSelectedTemplate(template)
            }
            MurphButton(variant: .secondary, full: true, title: "Cancel") {
                showDeleteTemplateConfirm = false
            }
        }
    }

    private func deleteSelectedTemplate(_ template: WorkoutTemplate) {
        // Move the selection off the template *before* deleting it: this view
        // holds it in `@State` and reads `template.name` while rendering, so
        // deleting first can leave a body evaluation on a deleted model.
        selectedTemplate = templates.first { $0 != template }
        do {
            try TemplateDeletion.delete(template, context: context)
            // The Watch's template list is this list. Without the push it keeps
            // offering a template the phone no longer has.
            sync.pushContext()
        } catch {
            // Safe because `TemplateDeletion.delete` rolls the context back on a
            // failed save: the template really is still there, rather than
            // deleted-but-unsaved, so pointing the selection at it again cannot
            // strand a body evaluation on a deleted model.
            selectedTemplate = template
            assertionFailure("Failed to delete template: \(error)")
        }
    }

    private var workoutSection: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.gapStack) {
            MurphSectionHeader("Workout") {
                MurphButton(variant: .ghost, size: .sm, title: "New template") {
                    showTemplateEditor = true
                }
            }

            if templates.isEmpty {
                // Reachable now that templates can be deleted. Without this the
                // screen is a placeholder select field above a disabled Begin,
                // with nothing saying what to do about it.
                MurphEmptyState(
                    title: "No templates",
                    body: "Create one to start a workout. Tap New template above."
                )
            } else {
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
            }

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

                if let blocker = TemplateDeletion.blocker(for: template) {
                    // Named rather than merely disabled: a greyed-out delete
                    // with no explanation reads as a bug, not a rule.
                    MurphBanner(tone: .info, text: message(for: blocker))
                } else {
                    MurphButton(
                        variant: .danger,
                        size: .sm,
                        icon: Image(systemName: "trash"),
                        title: "Delete template"
                    ) {
                        showDeleteTemplateConfirm = true
                    }
                }
            }
        }
    }

    private func message(for blocker: TemplateDeletion.Failure) -> String {
        switch blocker {
        case .sessionInProgress:
            "A session is running against this template. Finish or abandon it before deleting."
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

    /// The receiver warms from the moment this screen appears, which is what
    /// makes the start gate almost never visible: by the time a template is
    /// chosen and the vest is set, a fix has usually landed.
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.gapStack) {
            MurphSectionHeader("Location")
            MurphToggle(
                label: "Indoor",
                description: "Treadmill or track. Skips GPS, so the run distance isn\u{2019}t measured.",
                isOn: $indoor
            )
        }
    }

    /// A `fullScreenCover`, not a sheet, and dismissal is disabled: the same
    /// reasoning already written at `RootTabView.swift:54-61`. A swipe here
    /// would resolve the gate without a decision and leave a half-started
    /// session behind it.
    private var acquiringOverlay: some View {
        VStack(spacing: MurphSpacing.space6) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(MurphColor.hazard500)
            VStack(spacing: MurphSpacing.space2) {
                Text("Acquiring GPS")
                    .murphType(.title())
                    .foregroundStyle(MurphColor.textPrimary)
                Text("Waiting for a usable fix so the run distance is measured.")
                    .murphType(.bodySm)
                    .foregroundStyle(MurphColor.textMuted)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            // Available from the first frame. The standing contract is that no
            // sensor may block the workout (`WorkoutControlling`), and the
            // 30-second timeout is only the backstop for someone who is not
            // looking at the screen.
            MurphButton(variant: .secondary, size: .lg, full: true, title: "Start anyway") {
                gate.skip()
            }
        }
        .padding(MurphSpacing.gutterScreen)
        .murphScreenBackground()
        .interactiveDismissDisabled()
    }

    /// Asserted unconditionally rather than tracked, because `startUpdating`
    /// and `stopUpdating` are idempotent by contract.
    ///
    /// Guarded on `!gate.isWaiting` too: presenting the acquiring overlay as a
    /// `fullScreenCover` over this screen can itself trigger a reconcile, and
    /// at gate time no session exists yet, so `sessionIsLive` alone would let
    /// `indoor` (still false, most likely) call `stopUpdating()` on the very
    /// receiver the gate is polling — stalling every outdoor start until the
    /// 30-second timeout. See the note on `sessionIsLive` for the matching
    /// case in `.onDisappear`.
    private func reconcileWarmUp() {
        guard !sessionIsLive, !gate.isWaiting else { return }
        if indoor { location.stopUpdating() } else { location.startUpdating() }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return StartView(location: PhoneLocationController(), sessionIsLive: false) { _ in }
        .modelContainer(container)
        .environment(PhoneSyncCoordinator(container: container))
}
