// MurphPlusWatch/Views/WatchSetupView.swift
import SwiftUI
import WatchKit

/// Template list, then two segmented controls, then Start.
///
/// Vest and location are **segmented controls, not toggles**, and both states
/// are always visible. Vest is load-bearing data rather than a preference — the
/// prediction refuses to mix vest and non-vest sessions, so a wrong flag
/// silently disqualifies the session as source data. A lone toggle reads as a
/// settled state; showing the road not taken makes it read as a live choice.
struct WatchSetupView: View {
    @Bindable var controller: WatchSessionController
    var sync: WatchSyncCoordinator
    @Environment(\.scenePhase) private var scenePhase

    /// Prefers what the phone has synced down, falling back to the starters.
    /// The fallback matters on a Watch that has never connected: the user can
    /// still do a Full Murph rather than staring at an empty list.
    private var templates: [TemplateSpec] {
        let synced = sync.context?.templates ?? []
        return synced.isEmpty ? Self.starterTemplates : synced
    }

    /// `templates` can change under the user: the phone's list replaces the
    /// starters the moment context arrives. A `selected` that is no longer in
    /// the list highlights no row while still being what Start launches, so
    /// drop it and fall back to the first of whatever is current.
    private var effectiveSelection: TemplateSpec? {
        guard let selected, templates.contains(where: { $0.id == selected.id }) else {
            return templates.first
        }
        return selected
    }

    private var acknowledgedSessionIDs: Set<UUID> {
        Set(sync.context?.acknowledgedSessionIDs ?? [])
    }

    private var acknowledgementHorizon: Date? { sync.context?.acknowledgementHorizon }

    /// "No workout owns the receiver right now" — the guard for the
    /// scene-phase handler below.
    ///
    /// `.notStarted` is the phase this view is even on screen for before
    /// Start is tapped; `isFinished` is the completed/abandoned phase after
    /// one ends. Every other phase (`.run1`, `.run2`, `.rounds`) is a live
    /// session, and none of them satisfy this — which is what keeps the
    /// scene-phase handler from ever touching the receiver mid-workout, even
    /// though this view is still technically part of the hierarchy while
    /// `WatchLiveView` is pushed on top of it.
    private var noLiveSession: Bool {
        controller.state.phase == .notStarted || controller.isFinished
    }

    @State private var selected: TemplateSpec?
    @AppStorage("watchVestOn") private var vestOn = false
    @AppStorage("watchVestWeight") private var vestWeight = 20
    @AppStorage("watchIndoor") private var indoor = false
    @State private var gate = LocationFixGate()
    @State private var showLive = false
    @State private var showResumePrompt = false
    /// Owned here rather than by the countdown view so cancelling can tear the
    /// count down without the view that draws it having to exist.
    @State private var countdown = StartCountdown()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MurphSpacing.space3) {
                    // The display face, not `.navigationTitle`. A watchOS
                    // navigation title is drawn by the system in SF and takes
                    // no font modifier, so it read as a different app from the
                    // phone. The phone uses no navigation titles at all — see
                    // `MurphScreenTitle` — so an in-content heading is also
                    // the house pattern. `.title` rather than the phone's
                    // `.display2` purely for scale: 44pt does not fit a watch.
                    Text("Murph+")
                        .murphType(.title())
                        .foregroundStyle(MurphColor.textPrimary)

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
                        onLeft: { indoor = false; controller.warmLocationForSetup(true) },
                        onRight: { indoor = true; controller.warmLocationForSetup(false) }
                    )

                    Button("Start") {
                        guard let spec = effectiveSelection else { return }
                        // Repeats the `.task` warm-up rather than trusting it:
                        // the receiver is started only from `.task`, and
                        // whether SwiftUI re-runs `.task` when this view
                        // reappears after a `NavigationStack` pop (session 2
                        // of the same launch) is not something this test
                        // bundle can pin down. The same gap swallows the
                        // deny-then-grant-in-Settings path, since
                        // `reflectAuthorization` clears `.denied` to `.off`
                        // without restarting updates. One idempotent call here
                        // makes the warm state deterministic regardless — a
                        // future reader should not delete this as a duplicate
                        // of the `.task` one.
                        controller.warmLocationForSetup(!indoor)
                        // Everything that creates state lives inside the
                        // closure: a cancelled count must leave no journal, no
                        // HealthKit session and no navigation behind.
                        countdown.start {
                            // Returns at once unless GPS is still acquiring,
                            // which after the warm-up above is the rare case.
                            // Bounded and skippable: no sensor blocks a
                            // workout.
                            await gate.wait { controller.gpsFixState }
                            await controller.startSession(
                                template: spec, vestOn: vestOn,
                                vestWeightLbs: vestOn ? vestWeight : nil, indoor: indoor
                            )
                            WKInterfaceDevice.current().play(.start)
                            showLive = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MurphColor.hazard500)
                }
                .padding(.horizontal, MurphSpacing.space2)
            }
            .background(MurphColor.surfacePage)
            .navigationDestination(isPresented: $showLive) {
                WatchLiveView(controller: controller, sync: sync, onDone: { showLive = false })
            }
        }
        // Covers the whole setup screen rather than presenting a sheet: a sheet
        // is dismissible by swipe, and swiping a countdown away would leave the
        // count running behind it with no way back to Cancel.
        .overlay {
            if let value = countdown.remaining {
                WatchCountdownView(value: value) { countdown.cancel() }
            } else if gate.isWaiting {
                WatchAcquiringGPSView { gate.skip() }
            }
        }
        .sheet(isPresented: $showResumePrompt) {
            resumePrompt
        }
        .onDisappear {
            // Pushing WatchLiveView fires this too, and there the session owns
            // the receiver from `startSession` onward — stopping it here would
            // kill GPS in the first seconds of run 1. Only stop when we are
            // genuinely leaving setup without a workout.
            if !showLive { controller.warmLocationForSetup(false) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // `.onDisappear` fires when this view leaves the hierarchy, not
            // when the app itself backgrounds — and with
            // `allowsBackgroundLocationUpdates = true`, dropping the wrist
            // with Outdoor selected is exactly what keeps this app alive in
            // the background with a running receiver and no workout to
            // justify it. `noLiveSession` is why this can never fight
            // `reconcileLocation()` for control of the receiver during a run.
            guard noLiveSession else { return }
            controller.warmLocationForSetup(newPhase == .active && !indoor)
        }
        .task {
            // Set here, not at construction: `StartCountdown` lives in
            // MurphCore and is deliberately WatchKit-free so the iOS test
            // bundle can reach it. The haptic is the watch's business.
            countdown.onTick = { _ in WKInterfaceDevice.current().play(.click) }
            await controller.requestAuthorization()
            // Warm from the moment the screen appears, so the receiver has
            // been running for tens of seconds by the time Start is tapped.
            // This is what makes the gate below almost never visible.
            controller.warmLocationForSetup(!indoor)
            // Reconcile *first*, then ask what is resumable.
            //
            // Reconciliation can delete the very journal the prompt would
            // offer: an unfinished journal whose session the phone already
            // holds terminally — the ordinary outcome of the phone's stuck-
            // session reaper abandoning it — is acknowledged, and being
            // acknowledged is exactly what makes it safe to remove. Asking
            // first would offer Resume for a journal about to disappear, and
            // the user would tap it to no effect at all: `resumeExistingSession`
            // returns false and nothing on screen changes.
            controller.reconcileJournals(
                acknowledged: acknowledgedSessionIDs, horizon: acknowledgementHorizon
            )

            // The spec offers resume *or* abandon here. Auto-resuming would
            // not just be unfaithful: it is the only escape from a journal
            // that cannot be made terminal (an unwritable volume), which
            // otherwise drops the user into the same phantom workout on every
            // launch with no way out.
            showResumePrompt = controller.hasResumableSession()
        }
        // The phone's acknowledgement list arrives asynchronously, and usually
        // *after* launch — a phone that was off during the workout sends it
        // when it comes back. Reconciling only on appear would leave the
        // stranded workout waiting for the next launch.
        .onChange(of: acknowledgedSessionIDs) { _, acknowledged in
            controller.reconcileJournals(acknowledged: acknowledged, horizon: acknowledgementHorizon)
            // The prompt may have been offering a journal that pass just
            // removed. Re-asking closes it rather than leaving a dead button
            // on screen.
            if showResumePrompt, !controller.hasResumableSession() {
                showResumePrompt = false
            }
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
                        } else {
                            // Reachable, and it used to be completely silent:
                            // the journal can be gone by the time this runs
                            // (reconciliation removed it because the phone
                            // holds that session terminally), and the button
                            // then did nothing with nothing said anywhere.
                            SyncLog.note(
                                "resume found no journal — it was reconciled away, or could not be read"
                            )
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
        let isSelected = effectiveSelection?.id == template.id
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
        TemplateSpec(id: UUID(uuidString: "7F3A1C90-0001-4000-A000-000000000001")!, name: "Full Murph (Straight Sets)", runDistanceMiles: 1.0,
                     totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 1),
        TemplateSpec(id: UUID(uuidString: "7F3A1C90-0002-4000-A000-000000000002")!, name: "Full Murph (Cindy-Style, 20 Rounds)", runDistanceMiles: 1.0,
                     totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 20),
        TemplateSpec(id: UUID(uuidString: "7F3A1C90-0003-4000-A000-000000000003")!, name: "Half Murph", runDistanceMiles: 0.5,
                     totalPullUps: 50, totalPushUps: 100, totalSquats: 150, rounds: 10),
        TemplateSpec(id: UUID(uuidString: "7F3A1C90-0004-4000-A000-000000000004")!, name: "Mini Murph", runDistanceMiles: 0.25,
                     totalPullUps: 25, totalPushUps: 50, totalSquats: 75, rounds: 5),
    ]
}
