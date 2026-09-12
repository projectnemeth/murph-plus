// MurphPlus/Views/Session/MirroredSessionView.swift
import SwiftUI
import SwiftData

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
/// ever saying the workout had finished. The cached copy is the fallback the
/// completion state draws from; it upgrades to the phone's own saved
/// `MurphSession`, with its personal-best line and full recap, the moment
/// `SessionImporter` writes it (see `completedSession` below).
struct MirroredSessionView: View {
    let mirror: LiveMirrorStore

    @Environment(\.dismiss) private var dismiss
    /// The phone's own history, sourced the same way `HistoryView` /
    /// `HistoryStats` already do — a completed workout's recap and its
    /// personal-best comparison both read this, never the mirror.
    @Query(sort: \MurphSession.date, order: .reverse) private var allSessions: [MurphSession]

    @State private var lastState: SessionState?
    /// `mirror.sessionID` as of the last *live* update — captured eagerly
    /// alongside `lastState`, never read lazily off `mirror` at render time.
    /// `LiveMirrorStore.clear()` nils `sessionID` in the same synchronous turn
    /// as the terminal event, before this view's `onChange` ever runs, so by
    /// the time `didFinish` flips true `mirror.sessionID` is already gone.
    /// This is the one place that id survives, which is what makes looking up
    /// the saved session possible at all.
    @State private var lastSessionID: UUID?
    @State private var didFinish = false
    /// The elapsed time frozen at the moment the workout ended.
    ///
    /// Needed because the state this view caches never carries `completedAt`.
    /// `LiveMirrorStore.receive` applies the terminal event and calls `clear()`
    /// in the same synchronous turn, and `markFinished` clears without ever
    /// exposing the terminal state — so SwiftUI is never handed a state that
    /// says the workout is over. `SessionDerivation.elapsed` then falls back to
    /// `now`, and the once-a-second `TimelineView` walked a finished Murph past
    /// 51:12 into 51:13, 51:14, for as long as the screen stayed open.
    @State private var finishedElapsed: TimeInterval?
    /// The instant `finishedElapsed` (and the fallback segment ladder's `now`)
    /// were frozen at. A second capture of the same `now`, rather than reusing
    /// `.now` at render time, for the identical reason `finishedElapsed`
    /// exists: the cached `lastState` this view falls back to while waiting
    /// for the saved session is not itself terminal (its `currentPhaseStartedAt`
    /// is still set), so `MirrorSegment.of` would otherwise keep advancing
    /// the in-progress row's clock on every later re-render — the same bug
    /// shape, just in the segment ladder instead of the hero clock.
    @State private var finishedAt: Date?

    var body: some View {
        // Matches `LiveSessionView`'s own shape: scrolling content as one
        // sibling, the primary action pinned below it as a second, rather
        // than one `VStack` sized to its content with the button riding
        // wherever that content happens to end. Without this split the Done
        // button sat under a half-empty screen for every completed render.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: MurphSpacing.gapSection) {
                    banner

                    if didFinish {
                        completedBody
                    } else if let state = lastState {
                        liveBody(state)
                    }
                }
                .padding(MurphSpacing.gutterScreen)
            }

            if didFinish {
                // A second sibling, not folded into the scrolling content —
                // present only for the completed state, so the live state
                // (which has no action here at all) never grows an empty
                // footer or a stray hairline underneath it.
                VStack(spacing: MurphSpacing.space3) {
                    // Dismissed by the user, not by the store. Leaving on a
                    // completion the reader has actually seen is the whole
                    // point of this state existing.
                    MurphButton(variant: .primary, full: true, title: "Done") { dismiss() }
                }
                .padding(.init(top: MurphSpacing.space4, leading: MurphSpacing.gutterScreen, bottom: MurphSpacing.space8, trailing: MurphSpacing.gutterScreen))
                .overlay(alignment: .top) {
                    Rectangle().fill(MurphColor.lineHairline).frame(height: MurphShape.borderHair)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .murphScreenBackground()
        .murphNavBar(title: didFinish ? "Workout complete" : "Live session")
        .onAppear {
            lastState = mirror.state
            lastSessionID = mirror.sessionID
        }
        // `lastUpdate` is the honest signal for both halves: it moves on every
        // live event, and `LiveMirrorStore.clear()` nils it — which happens only
        // when the session ends. A dropped link leaves it set (that is
        // staleness, a different thing), so this cannot mistake one for the
        // other.
        .onChange(of: mirror.lastUpdate) { _, update in
            if update != nil {
                lastState = mirror.state
                lastSessionID = mirror.sessionID
                // A live event after a finish can only belong to a *new*
                // session: `LiveMirrorStore` records the finished id and
                // refuses its stragglers. This screen does not pop itself, so
                // without the reset a second workout started on the Watch would
                // be drawn live under a "Workout complete" title, with a
                // Complete badge and a Done button.
                didFinish = false
                finishedElapsed = nil
                finishedAt = nil
            } else if let ended = lastState {
                let frozenNow = Date.now
                didFinish = true
                finishedAt = frozenNow
                finishedElapsed = SessionDerivation.elapsed(ended, now: frozenNow)
            }
        }
    }

    // MARK: - Banner

    @ViewBuilder
    private var banner: some View {
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
    }

    // MARK: - Live

    @ViewBuilder
    private func liveBody(_ state: SessionState) -> some View {
        // The clock and the segment ladder both read "now", and both must
        // read the SAME one: `MirrorSegment.of` used to be computed outside
        // `TimelineView`, so its in-progress row only advanced when a live
        // event re-evaluated `body` — every ~5s on a heart-rate sample, or
        // never if heart-rate stopped arriving — while the hero clock beside
        // it, inside `TimelineView`, ticked every second. The two visibly
        // disagreed. Grouping both under the same `TimelineView` closure,
        // reading its own `context.date`, is what keeps them in lockstep.
        // The badges are along for the ride only for ordering — cheap to
        // re-evaluate every second, and `@Query` is not touched by any of
        // this, so this costs nothing extra per tick.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: MurphSpacing.gapSection) {
                MurphClock(
                    label: "Elapsed",
                    seconds: SessionDerivation.elapsed(state, now: context.date),
                    size: .lg,
                    running: !state.isPaused && !mirror.isStale
                )

                MurphFlowLayout {
                    MurphBadge(tone: .live, dot: true, title: phaseLabel(state.phase))
                    if state.isPaused {
                        MurphBadge(tone: .abandoned, title: "Paused")
                    }
                    if let bpm = state.latestHeartRate {
                        MurphBadge(title: "\(bpm) bpm")
                    }
                }

                MurphSegmentLadder(segments: MirrorSegment.of(state, now: context.date))
            }
        }

        if state.phase == .rounds, let template = state.template {
            MurphRoundCounter(
                current: state.completedRounds + 1,
                total: template.rounds,
                repsLabel: "\(template.pullUpsPerRound) pull-ups \u{00b7} \(template.pushUpsPerRound) push-ups \u{00b7} \(template.squatsPerRound) squats"
            )
        }
    }

    // MARK: - Completed

    /// The saved session, looked up by the id captured before the mirror
    /// could clear it, AND required to have actually finished importing.
    ///
    /// `completedAt != nil` is load-bearing, not decorative:
    /// `SessionImporter.apply` upserts a row for this same id on every
    /// checkpoint *during* the workout, long before it ends, so by the time
    /// the terminal live event lands a row already exists — with
    /// `status == .inProgress` and `completedAt == nil`. Matching on id
    /// alone resolved to that mid-workout row: `totalElapsedSeconds` is nil
    /// for it, `SessionRecap.make` fell back to a 0-second total, and 0
    /// beats any real prior best, so the screen painted a fabricated
    /// personal best on top of a workout that had not even finished. This
    /// guard is what makes the race fallback below reachable at all — nil
    /// only in the true race: the terminal live event has already arrived
    /// (`didFinish`), but no row with `completedAt` set exists yet for this
    /// id. `completedBody` falls back to the cached mirror state in exactly
    /// that gap and upgrades automatically once this query re-fetches with
    /// the finished row in it.
    private var completedSession: MurphSession? {
        guard didFinish, let lastSessionID else { return nil }
        return allSessions.first { $0.id == lastSessionID && $0.completedAt != nil }
    }

    @ViewBuilder
    private var completedBody: some View {
        if let session = completedSession {
            let recap = SessionRecap.make(session: session, priorSessions: allSessions)
            // Grouped into one accessibility element so the total and the PR
            // line read as one sentence rather than two disconnected stops.
            VStack(alignment: .leading, spacing: MurphSpacing.space1) {
                // `recap.totalSeconds`, not `session.totalElapsedSeconds`
                // again: the same number `recap.total` was formatted from,
                // read once rather than re-derived a second time here.
                totalClock(seconds: recap.totalSeconds)
                // The element the user asked for. Lime for an improvement,
                // muted (never red) for a slower time — a completed Murph is
                // not a failure. Nil renders nothing at all: no row, no
                // placeholder, for a first-ever attempt with no best to beat,
                // and — since `SessionRecap` now guards on the session
                // itself being `.completed` — for an abandoned attempt too.
                if let delta = recap.personalBestDelta {
                    Text(delta.text)
                        .murphType(.bodyLg)
                        .foregroundStyle(delta.isImprovement ? MurphColor.lime500 : MurphColor.textMuted)
                }
                // Peak heart rate is the headline reason this screen reads
                // the saved session instead of the mirror at all — the live
                // `SessionState` only ever keeps `latestHeartRate`, never a
                // peak (see this type's own top-of-file comment) — so it (and
                // the average round pace already summarized per-row in the
                // spine below) is surfaced explicitly here rather than only
                // being true in the data. Each fact is independent and each
                // is omitted on its own when nil, never a placeholder.
                if let stats = statsLine(recap) {
                    Text(stats)
                        .murphType(.bodySm)
                        .foregroundStyle(MurphColor.textMuted)
                }
                // Same "↓" convention as an improving personal best — a
                // negative split is a good thing, never rendered as muted
                // fine print or, worse, as a scold; nil (a positive split)
                // renders nothing.
                if let negativeSplit = recap.negativeSplit {
                    Text(negativeSplit)
                        .murphType(.bodySm)
                        .foregroundStyle(MurphColor.lime500)
                }
            }
            .accessibilityElement(children: .combine)

            MurphTimelineSpine(recap: recap)
        } else if let state = lastState {
            // The race: the terminal event has arrived but the durable
            // checkpoint has not, so there is no saved session to build a
            // recap from yet. Falls back to the cached mirror state — frozen
            // at `finishedAt`, exactly as `finishedElapsed` is — rather than
            // show nothing or a spinner where a finished workout belongs.
            totalClock(seconds: finishedElapsed ?? SessionDerivation.elapsed(state, now: finishedAt ?? .now))
            MurphSegmentLadder(segments: frozenSegments(for: state))
        }
    }

    private func totalClock(seconds: Double) -> some View {
        MurphClock(label: "Total", seconds: seconds, size: .lg, running: false, tone: .accent)
    }

    /// "N bpm peak · M:SS avg round", either half dropped when its fact is
    /// nil, the whole line dropped when both are — never a lone " · " and
    /// never a placeholder for a fact this session doesn't have.
    private func statsLine(_ recap: SessionRecap) -> String? {
        var parts: [String] = []
        if let peak = recap.peakHeartRate { parts.append("\(peak) bpm peak") }
        if let avg = recap.averageRoundSeconds { parts.append("\(formatDuration(avg)) avg round") }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00b7} ")
    }

    /// The race-fallback ladder, not the live one: `state` is one event
    /// behind the true terminal state (see `finishedAt`'s comment), so
    /// whichever row was in progress when the mirror was last observed still
    /// carries `.current` from `MirrorSegment.of`. Left alone, that row would
    /// render in the live hazard tone — under a "Workout complete" title and
    /// a Done button — telling the user a finished workout is still running.
    /// Every row is over by the time this screen shows at all, so any
    /// `.current` row is remapped to `.done` here, local to this one
    /// fallback branch; `MirrorSegment`/`MirrorSegmentState` stay untouched,
    /// since the live ladder above still needs a genuine `.current` row.
    private func frozenSegments(for state: SessionState) -> [MirrorSegment] {
        MirrorSegment.of(state, now: finishedAt ?? .now).map { segment in
            guard segment.state == .current else { return segment }
            return MirrorSegment(
                label: segment.label,
                value: segment.value,
                detail: segment.detail,
                fraction: segment.fraction,
                state: .done
            )
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
