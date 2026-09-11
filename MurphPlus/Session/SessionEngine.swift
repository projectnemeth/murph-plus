// MurphPlus/Session/SessionEngine.swift
import Foundation
import Observation
import SwiftData

/// The phone's adapter over `MurphCore`.
///
/// Every method asks `SessionStateMachine` for an event and then applies that
/// event to both the in-memory `SessionState` and the SwiftData model. The
/// state machine owns the rules; this type owns persistence. Its public API is
/// unchanged from the pre-extraction version, and `SessionEngineTests` passes
/// untouched — that is the proof the extraction preserved behavior.
///
/// `@MainActor` because `LocationProviding` and `RunDistanceMeasuring` are:
/// every call into them needs main-actor context, and this class is
/// `@Observable` and drives SwiftUI. Same reasoning as
/// `WatchSessionController`.
@MainActor
@Observable
final class SessionEngine {
    private(set) var session: MurphSession
    private(set) var state: SessionState
    private let context: ModelContext
    private let location: SessionLocation?

    /// A run already in flight when this engine was built began before the
    /// engine existed, so whatever is measured from here is only part of it.
    /// Cleared by the next `beginRun()`.
    private var runDistanceUntrustworthy = false

    /// Mirrors the measurement window so the reconcile can edge-trigger on it.
    /// `stopMeasuring`/`resumeRun` are idempotent in effect, but `beginRun`
    /// zeroes the total, so it must fire exactly once per run.
    private var isMeasuring = false

    init(session: MurphSession, context: ModelContext, location: SessionLocation? = nil) {
        self.session = session
        self.context = context
        self.location = location
        self.state = SessionEngine.rebuildState(from: session)
        reconcileLocation()
        // Set AFTER the reconcile above, because that reconcile may call
        // `beginRun()` for a run already in progress - and `beginRun` is
        // exactly what clears this flag.
        runDistanceUntrustworthy = SessionEngine.isRun(state.phase)
    }

    static func startNew(
        template: WorkoutTemplate, vestOn: Bool, vestWeightLbs: Int?,
        indoor: Bool = false, context: ModelContext, location: SessionLocation? = nil
    ) -> SessionEngine {
        let session = MurphSession(
            template: template, vestOn: vestOn, vestWeightLbs: vestWeightLbs, indoor: indoor
        )
        context.insert(session)
        try? context.save()
        return SessionEngine(session: session, context: context, location: location)
    }

    var isPaused: Bool { state.isPaused }

    var totalElapsed: TimeInterval {
        SessionDerivation.elapsed(state, now: .now)
    }

    // MARK: - Transitions

    func start() {
        guard let spec = session.template?.spec else { return }
        perform(SessionStateMachine.start(
            state, template: spec, vestOn: session.vestOn,
            vestWeightLbs: session.vestWeightLbs, indoor: session.indoor, now: .now
        ))
    }

    func finishRun() {
        // Read before the transition: `perform` closes the measurement window
        // as part of reconciling, and the value is needed for the event.
        let distance = runDistanceUntrustworthy ? nil : location?.runDistanceMeters
        perform(SessionStateMachine.finishRun(state, at: .now, distanceMeters: distance))
    }

    func completeRound() {
        perform(SessionStateMachine.completeRound(state, at: .now))
    }

    func undoLastRound() {
        perform(SessionStateMachine.undoLastRound(state, at: .now))
    }

    func pause() {
        perform(SessionStateMachine.pause(state, at: .now))
    }

    func resume() {
        perform(SessionStateMachine.resume(state, at: .now))
    }

    /// Abandoning a session that was never started discards it instead of
    /// recording it. Nothing was logged against it — no runs, no rounds, no
    /// elapsed time — so keeping it would add an "attempt" to the history that
    /// represents no attempt at all. This is the same rule
    /// `NeverStartedSessionPurger` applies to rows stranded by an app kill.
    ///
    /// A session that *did* start is always kept, however little it recorded:
    /// that is a real attempt, and the log is the record of it.
    func abandon() {
        // Abandoning while paused must not leave the pause open: `.abandoned`
        // never closes one itself, and `session.pausedSeconds` is only ever
        // incremented by `.resumed`. Without this, an open pause is silently
        // dropped from `totalElapsedSeconds` — the logged "Stopped at" time
        // would read too high by exactly the open pause's length. Route a
        // synthetic resume through the same `perform`/`applyToModel` path the
        // real resume takes, so `state.pausedIntervals`,
        // `session.pausedSeconds`, and `session.pausedIntervalsData` all stay
        // consistent — and so the event stream (a future Watch journal) never
        // records an unclosed `paused` followed by `abandoned`.
        if isPaused {
            perform(SessionStateMachine.resume(state, at: .now))
        }
        perform(SessionStateMachine.abandon(state, at: .now))
    }

    // MARK: - Applying events

    /// A rejected transition is silently ignored, matching the pre-extraction
    /// engine's `guard … else { return }` posture: these are impossible-button
    /// guards, not user-facing errors.
    private func perform(_ result: Result<SessionEvent, SessionTransitionError>) {
        guard case let .success(event) = result else { return }
        let before = state
        state.apply(event)

        // Deciding whether to *persist* an abandonment is a persistence
        // concern, not a rules concern, so the state machine emits `.abandoned`
        // unconditionally and the adapter decides here. A session abandoned
        // before Start was ever tapped is discarded, not recorded — see
        // `abandon()`'s doc comment. This must happen before `applyToModel`
        // touches `session` any further: once deleted, it must not be mutated
        // or saved again.
        if case .abandoned = event, session.startedAt == nil {
            // Reconcile before returning, or a discarded session leaves the
            // receiver powered until the app dies.
            reconcileLocation()
            context.delete(session)
            save()
            return
        }

        applyToModel(event, before: before)
        save()

        // Pause and resume are not phase changes, so the window has to be
        // moved explicitly. The receiver is deliberately untouched: pauses are
        // typically short, and reacquiring a fix costs more than one saves.
        switch event {
        case .paused:
            location?.stopMeasuring()
        case .resumed:
            if SessionEngine.isRun(state.phase) { location?.resumeRun() }
        default:
            break
        }

        reconcileLocation()
    }

    private func applyToModel(_ event: SessionEvent, before: SessionState) {
        switch event {
        case let .started(at, _, _, _, _):
            session.startedAt = at
            session.phase = .run1
            session.currentPhaseStartedAt = at

        case let .runFinished(index, _, _):
            // `state` already computed the split net of pause; mirror it.
            // Guarded on the split's own index (not just its presence) so a
            // stale `runSplits.last` — e.g. run 1's split, still sitting there
            // because this `.runFinished` produced no new split — can never
            // be persisted a second time under `index`'s identity.
            if let split = state.runSplits.last, split.index == index {
                let model = RunSplit(
                    runIndex: split.index,
                    startTime: split.startTime,
                    durationSeconds: split.durationSeconds,
                    session: session
                )
                model.distanceMeters = split.distanceMeters
                context.insert(model)
                session.runSplits.append(model)
            }
            if index == 1 {
                // Persist the true rounds-phase start rather than relying on
                // run1.startTime + run1.durationSeconds: that derivation is
                // net of pause and would land earlier than the real boundary
                // once a pause occurs during run 1, silently absorbing that
                // pause into round 1's duration. Kept outside the `if let`
                // above so the boundary is still recorded even in the
                // (should-not-happen) case the split itself wasn't produced.
                session.roundsStartedAt = state.roundsStartedAt
            }
            session.phase = state.phase
            session.currentPhaseStartedAt = state.currentPhaseStartedAt
            if state.phase == .completed {
                session.status = .completed
                session.completedAt = state.completedAt
            }

        case let .roundCompleted(number, at):
            let boundary = before.roundTimestamps.last ?? before.roundsStartedAt ?? at
            let log = RoundLog(roundNumber: number, completedAt: at, session: session)
            log.pausedSecondsInRound = before.pausedSeconds(between: boundary, and: at)
            context.insert(log)
            session.roundLogs.append(log)
            session.completedRounds = number
            session.phase = state.phase
            session.currentPhaseStartedAt = state.currentPhaseStartedAt

        case .roundUndone:
            if let last = session.roundLogs.max(by: { $0.roundNumber < $1.roundNumber }) {
                session.roundLogs.removeAll { $0.roundNumber == last.roundNumber }
                context.delete(last)
            }
            session.completedRounds = state.completedRounds
            session.phase = state.phase
            session.currentPhaseStartedAt = state.currentPhaseStartedAt

        case let .paused(at):
            session.pausedAt = at

        case let .resumed(at):
            if let start = session.pausedAt {
                session.pausedSeconds += at.timeIntervalSince(start)
                session.pausedAt = nil
            }
            // Persist the exact intervals, not just their sum: `state` (already
            // updated by `apply` above) is the source of truth, and this is
            // what lets a relaunch net out a pause taken during the run or
            // round still in progress and not yet logged.
            session.pausedIntervalsData = try? JSONEncoder().encode(state.pausedIntervals)

        case .heartRate:
            break // Stage 2 concern; the phone collects none.

        case let .abandoned(at):
            session.status = .abandoned
            session.completedAt = at
            session.currentPhaseStartedAt = nil
        }
    }

    /// Reconstructs core state from a persisted session, for resume-after-relaunch.
    ///
    /// `pausedIntervals` is restored from `pausedIntervalsData` rather than
    /// left empty: every already-logged round and split carries its own net
    /// correction, but the run or round still *in progress* at relaunch has
    /// not been logged yet, and without the real intervals a pause taken
    /// inside it would silently be written as zero once it finally is —
    /// exactly the fatigue-curve skew pause exists to prevent. Restoring the
    /// intervals also keeps the live elapsed-time clock (`totalElapsed`,
    /// which reads `state.pausedIntervals` via `SessionDerivation`) correct
    /// across the relaunch, rather than jumping forward by every second
    /// previously paused.
    private static func rebuildState(from session: MurphSession) -> SessionState {
        var state = SessionState()
        state.template = session.template?.spec
        state.vestOn = session.vestOn
        state.vestWeightLbs = session.vestWeightLbs
        state.indoor = session.indoor
        state.phase = session.phase
        state.status = session.status
        state.startedAt = session.startedAt
        state.currentPhaseStartedAt = session.currentPhaseStartedAt
        state.completedAt = session.completedAt
        state.completedRounds = session.completedRounds
        state.pausedAt = session.pausedAt
        if let data = session.pausedIntervalsData,
           let intervals = try? JSONDecoder().decode([PausedInterval].self, from: data) {
            state.pausedIntervals = intervals
        }
        state.roundTimestamps = session.roundLogs
            .sorted { $0.roundNumber < $1.roundNumber }
            .map(\.completedAt)
        state.runSplits = session.runSplits
            .sorted { $0.runIndex < $1.runIndex }
            .map { RunSplitState(index: $0.runIndex, startTime: $0.startTime,
                                 durationSeconds: $0.durationSeconds, distanceMeters: nil) }
        // Prefer the persisted rounds-phase start; fall back to deriving it
        // from run 1's split for sessions logged before that field existed.
        state.roundsStartedAt = session.roundsStartedAt
            ?? session.runSplits.first { $0.runIndex == 1 }
                .map { $0.startTime.addingTimeInterval($0.durationSeconds) }
        return state
    }

    private static func isRun(_ phase: SessionPhase) -> Bool {
        phase == .run1 || phase == .run2
    }

    /// Whether a run's distance should be accumulating right now.
    ///
    /// Deliberately not a phase-edge comparison. `SessionState.apply` preserves
    /// `phase` on `.abandoned`, so an abandoned run reads `.run1` forever and an
    /// edge trigger would never close the window; and `indoor` is invisible to
    /// phase entirely. Putting all three conditions in one predicate is what
    /// keeps those two cases from being separate special cases.
    private static func shouldMeasure(_ state: SessionState) -> Bool {
        guard !state.indoor, !state.isTerminal else { return false }
        return isRun(state.phase)
    }

    /// Asserts the desired receiver state unconditionally rather than tracking
    /// what was already asked — `startUpdating`/`stopUpdating` are idempotent
    /// by contract, which is what lets `LocationPolicy` stay a pure function
    /// rather than a second state machine.
    ///
    /// Mirrors `WatchSessionController`: the transition points are ones this
    /// type already owns, so there are no new events and no state-machine
    /// change.
    private func reconcileLocation() {
        guard let location else { return }

        if LocationPolicy.shouldWarm(for: state) {
            location.startUpdating()
        } else {
            location.stopUpdating()
        }

        // The measurement window follows a pure predicate, not receiver power
        // or a bare phase edge. The two overlap but are not the same interval:
        // the pre-warm at rounds-remaining <= 1 powers the receiver while
        // measuring stays off.
        let wantMeasuring = SessionEngine.shouldMeasure(state)
        if wantMeasuring && !isMeasuring {
            location.beginRun()
            runDistanceUntrustworthy = false
            isMeasuring = true
        } else if !wantMeasuring && isMeasuring {
            location.stopMeasuring()
            isMeasuring = false
        }
    }

    private func save() {
        try? context.save()
    }
}
