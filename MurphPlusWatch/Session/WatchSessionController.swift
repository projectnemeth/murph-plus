// MurphPlusWatch/Session/WatchSessionController.swift
import Foundation
import Observation

/// The Watch's session owner: journal in, state machine deciding, HealthKit
/// alongside. Every mutation follows the same three beats — ask the state
/// machine for an event, append it to the journal, mirror the HealthKit side.
///
/// `@MainActor` because `WorkoutControlling` is: every call into it needs
/// main-actor context, and this class is `@Observable` and drives SwiftUI
/// besides, so the isolation is correct for both reasons at once.
///
/// HealthKit is reached only through `WorkoutControlling`, never directly, so
/// this type imports nothing beyond Foundation and Observation. That is what
/// lets it be compiled into the phone target and exercised from the iOS test
/// bundle — the watch target has no test bundle of its own.
@MainActor
@Observable
final class WatchSessionController {
    private(set) var state = SessionState()
    private(set) var journal: SessionJournal?
    private let workout: any WorkoutControlling
    private let journalDirectory: URL

    nonisolated static var defaultJournalDirectory: URL {
        URL.documentsDirectory.appendingPathComponent("sessions", isDirectory: true)
    }

    init(workout: any WorkoutControlling, journalDirectory: URL) {
        self.workout = workout
        self.journalDirectory = journalDirectory
    }

    #if os(watchOS)
    /// The app's own construction: the concrete HealthKit controller and the
    /// real documents directory. Kept behind `#if` because
    /// `WorkoutSessionController` wraps `HKWorkoutSession`, which is
    /// watchOS-only — off the watch, injection is the only way in, which is
    /// exactly what the tests want.
    convenience init() {
        self.init(
            workout: WorkoutSessionController(),
            journalDirectory: Self.defaultJournalDirectory
        )
    }
    #endif

    var heartRate: Int? { workout.currentHeartRate }
    var runDistanceMeters: Double? { workout.currentRunDistanceMeters }
    var isPaused: Bool { state.isPaused }
    var isFinished: Bool { state.isTerminal }
    var canUndo: Bool { state.undoableRoundNumber != nil }

    /// Set when this session's on-disk record is not guaranteed — either the
    /// journal could not be created at all, or an append threw. In both cases
    /// the workout itself proceeds: the event still applied to `state` (see
    /// `record(_:)`), and a missing journal makes every append a silent no-op.
    /// The flag is what stops that from hiding behind a green "Complete", and
    /// is what the completion screen warns from.
    private(set) var journalWriteFailed = false

    var elapsed: TimeInterval { SessionDerivation.elapsed(state, now: .now) }

    // MARK: - Lifecycle

    func requestAuthorization() async {
        await workout.requestAuthorization()
    }

    /// Whether an unfinished journal is waiting on disk.
    ///
    /// Deliberately non-committal: the launch screen asks the user to resume
    /// or abandon, per the design spec, and neither path may be taken on the
    /// user's behalf. Auto-resuming would also remove the only escape from a
    /// journal that can never be made terminal.
    func hasResumableSession() -> Bool {
        ((try? SessionJournal.resumable(in: journalDirectory)) ?? nil) != nil
    }

    /// Returns true if an unfinished journal was found and restored.
    ///
    /// Restoring the journal is not enough on its own: a relaunch means
    /// `workout` is a brand-new controller with no session, no builder, and no
    /// heart-rate handler, even though the workout is still live on the
    /// Watch's side. Reattach HealthKit the same way `startSession` does, then
    /// issue whatever activity segment matches the phase the journal replayed
    /// into — otherwise a resumed session quietly stops recording heart rate
    /// for the rest of the workout.
    func resumeExistingSession() async throws -> Bool {
        guard let found = try SessionJournal.resumable(in: journalDirectory) else {
            return false
        }
        journal = found
        state = found.state

        // Prefer reattaching to the still-live session watchOS kept running;
        // fall back to a fresh one if there is nothing to recover (or
        // recovery fails) — a second `HKWorkout` in Fitness is a much
        // smaller loss than an hour of unrecorded heart rate.
        let recovered = await workout.recover(indoor: state.indoor)
        if !recovered {
            await workout.start(indoor: state.indoor)
        }
        attachHeartRateHandler()

        switch state.phase {
        case .run1, .run2:
            // Reset the distance baseline only on the fresh-start path, where
            // the new builder has recorded nothing. On the recover path the
            // builder still holds the miles run before the relaunch, and
            // re-snapshotting would subtract them away — the athlete would see
            // "0.00 · 1.00 to go" half a mile in, and the eventual split would
            // record a distance short by everything before the crash.
            workout.beginRunActivity(resetDistanceBaseline: !recovered)
        case .rounds:
            workout.beginRoundsActivity()
        case .notStarted, .completed:
            break
        }

        // The replayed state may carry an open pause. HealthKit knows nothing
        // about it — a recovered session was never paused by this process, and
        // a fresh one has only just started — so without this the state
        // machine believes it is paused while `HKWorkoutSession` keeps
        // accruing time and calories, and the user's later Resume would call
        // `resume()` on a session that was never paused.
        if state.isPaused {
            workout.pause()
        }

        return true
    }

    func startSession(template: TemplateSpec, vestOn: Bool, vestWeightLbs: Int?, indoor: Bool) async {
        openJournal()

        await workout.start(indoor: indoor)
        attachHeartRateHandler()

        perform(SessionStateMachine.start(
            state, template: template, vestOn: vestOn,
            vestWeightLbs: vestWeightLbs, indoor: indoor, now: .now
        ))
        workout.beginRunActivity(resetDistanceBaseline: true)
    }

    /// Opens the on-disk journal for a new session.
    ///
    /// Split out from `startSession` because the failure has to be handled,
    /// not swallowed: with `journal` nil every later `try journal?.append(...)`
    /// is a no-op that throws nothing, so without this an entire workout would
    /// be recorded to nothing behind a green "Complete".
    func openJournal() {
        do {
            journal = try SessionJournal(sessionID: UUID(), directory: journalDirectory)
        } catch {
            journal = nil
            journalWriteFailed = true
        }
    }

    /// Ruling 3: a hardware spike to confirm whether `HKWorkoutSession.pause()`
    /// actually suspends heart-rate delivery was skipped — don't trust it to.
    /// Dropping samples taken while paused keeps a stopped-still spike from
    /// being bucketed into the surrounding round and dragging its average
    /// down. Shared by `startSession` and `resumeExistingSession`, which both
    /// need to (re)attach this handler to a freshly (re)created `workout`.
    private func attachHeartRateHandler() {
        workout.onHeartRate = { [weak self] bpm in
            guard let self, !self.state.isPaused else { return }
            self.record(.heartRate(bpm: bpm, at: .now))
        }
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
                workout.beginRunActivity(resetDistanceBaseline: true)
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

    /// Abandons the unfinished journal offered by the launch prompt, without
    /// ever loading it into this controller.
    ///
    /// The terminal `.abandoned` event is what stops the journal being offered
    /// again — but if the volume is unwritable that append fails, and a
    /// journal that can never be made terminal would hand the user the same
    /// prompt on every single launch with no way out. So when the writes do
    /// not stick, the file is deleted outright: losing the record of an
    /// abandoned attempt is a far smaller loss than a permanently wedged app.
    func abandonResumableSession() {
        guard let found = (try? SessionJournal.resumable(in: journalDirectory)) ?? nil else {
            return
        }

        var replayed = found.state
        var wrote = true

        // Same Ruling 2 shape as `abandon()`: close an open pause first, so the
        // journal never ends on an unclosed `paused`.
        if replayed.isPaused,
           case let .success(event) = SessionStateMachine.resume(replayed, at: .now) {
            do {
                try found.append(event)
                replayed.apply(event)
            } catch {
                wrote = false
            }
        }

        if wrote, case let .success(event) = SessionStateMachine.abandon(replayed, at: .now) {
            do { try found.append(event) } catch { wrote = false }
        }

        if !wrote || !found.state.isTerminal {
            try? found.delete()
        }
    }

    /// Returns the controller to a clean slate once the completion screen has
    /// been shown, so `WatchSetupView` can start a brand-new session right
    /// away. Deliberately does **not** delete the on-disk journal — it holds
    /// a completed (or abandoned) workout that a later stage syncs to the
    /// phone; only the in-memory handle is dropped here. `workout` itself is
    /// not touched: by the time this is called the workout session has
    /// already been finished (see `advance()` and `abandon()`), so there is
    /// nothing left on that side to reset.
    func finishAndReset() {
        journal = nil
        state = SessionState()
        journalWriteFailed = false
    }

    // MARK: - Applying

    private func perform(_ result: Result<SessionEvent, SessionTransitionError>) {
        guard case let .success(event) = result else { return }
        record(event)
    }

    private func record(_ event: SessionEvent) {
        // The user really did do this — a round tap, a pause, a run finish —
        // so `state` applies the event regardless of whether the journal
        // write succeeds. Refusing to count it in memory over a durability
        // gap would be a worse failure than the gap itself. But the failure
        // must not vanish silently: this journal is a later stage's sync
        // payload, so a swallowed append is permanent, invisible data loss.
        // Surface it instead via `journalWriteFailed`, which the completion
        // screen shows to the user.
        do {
            try journal?.append(event)
        } catch {
            journalWriteFailed = true
        }
        state.apply(event)
    }
}
