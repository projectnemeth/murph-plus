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
        VStack(alignment: .leading, spacing: MurphSpacing.gapSection) {
            banner

            if didFinish {
                completedBody
            } else if let state = lastState {
                liveBody(state)
            }

            if didFinish {
                // Dismissed by the user, not by the store. Leaving on a
                // completion the reader has actually seen is the whole point of
                // this state existing.
                MurphButton(variant: .primary, full: true, title: "Done") { dismiss() }
            }
        }
        .padding(MurphSpacing.gutterScreen)
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
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            MurphClock(
                label: "Elapsed",
                seconds: SessionDerivation.elapsed(state, now: .now),
                size: .lg,
                running: !state.isPaused && !mirror.isStale
            )
        }

        MurphFlowLayout {
            MurphBadge(tone: .live, dot: true, title: phaseLabel(state.phase))
            if state.isPaused {
                MurphBadge(tone: .abandoned, title: "Paused")
            }
            if let bpm = state.latestHeartRate {
                MurphBadge(title: "\(bpm) bpm")
            }
        }

        MurphSegmentLadder(segments: MirrorSegment.of(state, now: .now))

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
    /// could clear it. `nil` only in the race: the terminal live event has
    /// already arrived (`didFinish`), but `SessionImporter`'s durable
    /// checkpoint has not landed yet, so nothing with this id exists in
    /// `allSessions` for the moment. `completedBody` falls back to the cached
    /// mirror state in exactly that gap and upgrades automatically once this
    /// query re-fetches with the saved row in it.
    private var completedSession: MurphSession? {
        guard didFinish, let lastSessionID else { return nil }
        return allSessions.first { $0.id == lastSessionID }
    }

    @ViewBuilder
    private var completedBody: some View {
        if let session = completedSession {
            let recap = SessionRecap.make(session: session, priorSessions: allSessions)
            // Grouped into one accessibility element so the total and the PR
            // line read as one sentence rather than two disconnected stops.
            VStack(alignment: .leading, spacing: MurphSpacing.space1) {
                totalClock(seconds: session.totalElapsedSeconds ?? 0)
                // The element the user asked for. Lime for an improvement,
                // muted (never red) for a slower time — a completed Murph is
                // not a failure. Nil renders nothing at all: no row, no
                // placeholder, for a first-ever attempt with no best to beat.
                if let delta = recap.personalBestDelta {
                    Text(delta.text)
                        .murphType(.bodyLg)
                        .foregroundStyle(delta.isImprovement ? MurphColor.lime500 : MurphColor.textMuted)
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
            MurphSegmentLadder(segments: MirrorSegment.of(state, now: finishedAt ?? .now))
        }
    }

    private func totalClock(seconds: Double) -> some View {
        MurphClock(label: "Total", seconds: seconds, size: .lg, running: false, tone: .accent)
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
