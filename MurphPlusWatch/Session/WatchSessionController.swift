// MurphPlusWatch/Session/WatchSessionController.swift
import Foundation
import Observation

/// The Watch's session owner: journal in, state machine deciding, HealthKit
/// alongside. Every mutation follows the same three beats — ask the state
/// machine for an event, append it to the journal, mirror the HealthKit side.
///
/// `@MainActor` because `WorkoutSessionController` is: every call into it
/// needs main-actor context, and this class is `@Observable` and drives
/// SwiftUI besides, so the isolation is correct for both reasons at once.
@MainActor
@Observable
final class WatchSessionController {
    private(set) var state = SessionState()
    private(set) var journal: SessionJournal?
    private let workout = WorkoutSessionController()

    private static var journalDirectory: URL {
        URL.documentsDirectory.appendingPathComponent("sessions", isDirectory: true)
    }

    var heartRate: Int? { workout.currentHeartRate }
    var runDistanceMeters: Double? { workout.currentRunDistanceMeters }
    var isPaused: Bool { state.isPaused }
    var isFinished: Bool { state.isTerminal }
    var canUndo: Bool { state.undoableRoundNumber != nil }

    var elapsed: TimeInterval { SessionDerivation.elapsed(state, now: .now) }

    // MARK: - Lifecycle

    func requestAuthorization() async {
        await workout.requestAuthorization()
    }

    /// Returns true if an unfinished journal was found and restored.
    func resumeExistingSession() throws -> Bool {
        guard let found = try SessionJournal.resumable(in: Self.journalDirectory) else {
            return false
        }
        journal = found
        state = found.state
        return true
    }

    func startSession(template: TemplateSpec, vestOn: Bool, vestWeightLbs: Int?, indoor: Bool) async {
        let journal = try? SessionJournal(sessionID: UUID(), directory: Self.journalDirectory)
        self.journal = journal

        await workout.start(indoor: indoor)
        workout.onHeartRate = { [weak self] bpm in
            // Ruling 3: a hardware spike to confirm whether
            // `HKWorkoutSession.pause()` actually suspends heart-rate delivery
            // was skipped — don't trust it to. Dropping samples taken while
            // paused keeps a stopped-still spike from being bucketed into the
            // surrounding round and dragging its average down.
            guard let self, !self.state.isPaused else { return }
            self.record(.heartRate(bpm: bpm, at: .now))
        }

        perform(SessionStateMachine.start(
            state, template: template, vestOn: vestOn,
            vestWeightLbs: vestWeightLbs, indoor: indoor, now: .now
        ))
        workout.beginRunActivity()
    }

    // MARK: - Transitions

    /// The slot-2 primary action: end the current run, or log a round.
    func advance() {
        switch state.phase {
        case .run1, .run2:
            let distance = workout.currentRunDistanceMeters
            let wasRun1 = state.phase == .run1
            perform(SessionStateMachine.finishRun(state, at: .now, distanceMeters: distance))
            if state.phase == .completed {
                Task { await workout.finish() }
            } else if wasRun1 {
                workout.beginRoundsActivity()
            }
        case .rounds:
            let before = state.phase
            perform(SessionStateMachine.completeRound(state, at: .now))
            // The round that reaches the template total begins run 2.
            if before == .rounds, state.phase == .run2 {
                workout.beginRunActivity()
            }
        case .notStarted, .completed:
            break
        }
    }

    func pause() {
        perform(SessionStateMachine.pause(state, at: .now))
        workout.pause()
    }

    func resume() {
        perform(SessionStateMachine.resume(state, at: .now))
        workout.resume()
    }

    func undoLastRound() {
        let wasRun2 = state.phase == .run2
        perform(SessionStateMachine.undoLastRound(state, at: .now))
        // Undoing the round that advanced into run 2 puts us back in the rounds.
        if wasRun2, state.phase == .rounds {
            workout.beginRoundsActivity()
        }
    }

    /// Ruling 2: closes an open pause before abandoning, through the normal
    /// `.resumed` path, so the journal never carries an unclosed `paused`
    /// followed by `abandoned` — ambiguous to replay, and in a later stage
    /// this journal ships to the phone as the sync payload.
    ///
    /// Ruling 1: a session abandoned before Start was ever tapped is
    /// discarded, not recorded. Nothing was logged against it, so keeping it
    /// would add an attempt representing no attempt: delete the journal
    /// outright and clear the in-memory session, with no `.abandoned` event.
    func abandon() {
        if state.isPaused {
            perform(SessionStateMachine.resume(state, at: .now))
        }

        if state.startedAt == nil {
            try? journal?.delete()
            journal = nil
            state = SessionState()
        } else {
            perform(SessionStateMachine.abandon(state, at: .now))
        }

        Task { await workout.finish() }
    }

    // MARK: - Applying

    private func perform(_ result: Result<SessionEvent, SessionTransitionError>) {
        guard case let .success(event) = result else { return }
        record(event)
    }

    private func record(_ event: SessionEvent) {
        try? journal?.append(event)
        state.apply(event)
    }
}
