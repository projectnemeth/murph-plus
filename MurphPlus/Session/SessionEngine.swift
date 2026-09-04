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
@Observable
final class SessionEngine {
    private(set) var session: MurphSession
    private(set) var state: SessionState
    private let context: ModelContext

    init(session: MurphSession, context: ModelContext) {
        self.session = session
        self.context = context
        self.state = SessionEngine.rebuildState(from: session)
    }

    static func startNew(template: WorkoutTemplate, vestOn: Bool, vestWeightLbs: Int?, context: ModelContext) -> SessionEngine {
        let session = MurphSession(template: template, vestOn: vestOn, vestWeightLbs: vestWeightLbs)
        context.insert(session)
        try? context.save()
        return SessionEngine(session: session, context: context)
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
        perform(SessionStateMachine.finishRun(state, at: .now, distanceMeters: nil))
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
            context.delete(session)
            save()
            return
        }

        applyToModel(event, before: before)
        save()
    }

    private func applyToModel(_ event: SessionEvent, before: SessionState) {
        switch event {
        case let .started(at, _, _, _, _):
            session.startedAt = at
            session.phase = .run1
            session.currentPhaseStartedAt = at

        case .runFinished:
            // `state` already computed the split net of pause; mirror it.
            if let split = state.runSplits.last {
                let model = RunSplit(
                    runIndex: split.index,
                    startTime: split.startTime,
                    durationSeconds: split.durationSeconds,
                    session: session
                )
                context.insert(model)
                session.runSplits.append(model)
                if split.index == 1 {
                    // Persist the true rounds-phase start rather than relying on
                    // run1.startTime + run1.durationSeconds: that derivation is
                    // net of pause and would land earlier than the real
                    // boundary once a pause occurs during run 1, silently
                    // absorbing that pause into round 1's duration.
                    session.roundsStartedAt = state.roundsStartedAt
                }
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
    /// `pausedIntervals` is deliberately left empty: every already-logged round
    /// and split carries its own net correction, so only pauses taken from now
    /// on need tracking. `pausedSeconds` carries the running total for elapsed.
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

    private func save() {
        try? context.save()
    }
}
