// MurphCore/LocationPolicy.swift
import Foundation

/// Whether the GPS receiver should be running, given where the session is.
///
/// A pure function of `SessionState` and nothing else, which buys two things.
/// Relaunch recovery needs no separate path — replay the journal, ask this,
/// obey the answer — and the rule can be tested exhaustively without a watch.
///
/// Note what it does *not* consider: pause. A pause mid-run leaves the
/// receiver on deliberately. Pauses are typically short, and re-acquiring a
/// fix on resume costs more than the battery a short pause saves.
enum LocationPolicy {
    /// Runs need GPS. The rounds do not, until run 2 is one round away — that
    /// pre-warm is what buys run 2 a fix, since run 2 begins with the clock
    /// running and cannot be gated the way run 1 is.
    static func shouldWarm(for state: SessionState) -> Bool {
        guard !state.indoor else { return false }

        switch state.phase {
        case .run1, .run2:
            return true

        case .rounds:
            // No template means the question cannot be answered; off is the
            // safe answer, and this state is unreachable in a real session.
            guard let template = state.template else { return false }
            // "Remaining <= 1" rather than "completed == total - 1" so that a
            // single-round template warms from the moment rounds begin — with
            // no special case — and so no miscount past the total can switch
            // the receiver back off mid-workout.
            return template.safeRounds - state.completedRounds <= 1

        case .notStarted, .completed:
            return false
        }
    }
}
