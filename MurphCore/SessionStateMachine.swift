// MurphCore/SessionStateMachine.swift
import Foundation

enum SessionTransitionError: Error, Equatable {
    case sessionIsTerminal
    case wrongPhase
    case sessionIsPaused
    case alreadyPaused
    case notPaused
    case nothingToUndo
    case noTemplate
}

/// The transition rules for a live session.
///
/// Every function is pure: it takes the current state and *returns an event*,
/// never mutating anything. Callers apply the returned event — to a
/// `SessionState`, to SwiftData, to a journal file — which is what lets the
/// phone and the Watch share one set of rules while persisting differently.
enum SessionStateMachine {

    private static func guardActive(_ state: SessionState) -> SessionTransitionError? {
        // Status, not phase. `abandon` changes only `status`, leaving `phase`
        // wherever it stopped — a phase-only guard would let a later transition
        // silently flip an abandoned session back to completed.
        state.isTerminal ? .sessionIsTerminal : nil
    }

    static func start(
        _ state: SessionState, template: TemplateSpec, vestOn: Bool,
        vestWeightLbs: Int?, indoor: Bool, now: Date
    ) -> Result<SessionEvent, SessionTransitionError> {
        if let error = guardActive(state) { return .failure(error) }
        guard state.phase == .notStarted else { return .failure(.wrongPhase) }
        return .success(.started(
            at: now, template: template, vestOn: vestOn,
            vestWeightLbs: vestWeightLbs, indoor: indoor
        ))
    }

    static func finishRun(
        _ state: SessionState, at now: Date, distanceMeters: Double?
    ) -> Result<SessionEvent, SessionTransitionError> {
        if let error = guardActive(state) { return .failure(error) }
        guard !state.isPaused else { return .failure(.sessionIsPaused) }
        guard state.phase == .run1 || state.phase == .run2 else { return .failure(.wrongPhase) }
        // A run split can only be timed from a phase start. Without this, a
        // `run2` with no `currentPhaseStartedAt` (reached via a state
        // `apply` that advances phase unconditionally) would still emit
        // `.runFinished`, and the adapter would fabricate a duplicate split
        // and a false completion.
        guard state.currentPhaseStartedAt != nil else { return .failure(.wrongPhase) }
        let index = state.phase == .run1 ? 1 : 2
        return .success(.runFinished(index: index, at: now, distanceMeters: distanceMeters))
    }

    static func completeRound(
        _ state: SessionState, at now: Date
    ) -> Result<SessionEvent, SessionTransitionError> {
        if let error = guardActive(state) { return .failure(error) }
        guard !state.isPaused else { return .failure(.sessionIsPaused) }
        guard state.phase == .rounds else { return .failure(.wrongPhase) }
        guard state.template != nil else { return .failure(.noTemplate) }
        return .success(.roundCompleted(number: state.completedRounds + 1, at: now))
    }

    /// Permitted only while a round is still the most recent meaningful event —
    /// which allows correcting a mis-tap, including one that just advanced the
    /// session into run 2, without letting history be unwound further back.
    /// Deliberately not guarded on `isPaused`: correcting a mis-tap is not a
    /// workout transition, and blocking it would strand a wrong round count
    /// until the user resumes.
    static func undoLastRound(
        _ state: SessionState, at now: Date
    ) -> Result<SessionEvent, SessionTransitionError> {
        if let error = guardActive(state) { return .failure(error) }
        guard let number = state.undoableRoundNumber else { return .failure(.nothingToUndo) }
        return .success(.roundUndone(number: number, at: now))
    }

    static func pause(
        _ state: SessionState, at now: Date
    ) -> Result<SessionEvent, SessionTransitionError> {
        if let error = guardActive(state) { return .failure(error) }
        guard state.phase != .notStarted else { return .failure(.wrongPhase) }
        guard !state.isPaused else { return .failure(.alreadyPaused) }
        return .success(.paused(at: now))
    }

    static func resume(
        _ state: SessionState, at now: Date
    ) -> Result<SessionEvent, SessionTransitionError> {
        if let error = guardActive(state) { return .failure(error) }
        guard state.isPaused else { return .failure(.notPaused) }
        return .success(.resumed(at: now))
    }

    static func abandon(
        _ state: SessionState, at now: Date
    ) -> Result<SessionEvent, SessionTransitionError> {
        if let error = guardActive(state) { return .failure(error) }
        return .success(.abandoned(at: now))
    }
}
