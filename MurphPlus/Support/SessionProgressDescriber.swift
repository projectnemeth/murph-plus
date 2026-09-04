// MurphPlus/Support/SessionProgressDescriber.swift
import Foundation

/// "How far did this attempt get" copy for an abandoned session.
///
/// Abandoning retains every logged `RoundLog` and `RunSplit` and leaves
/// `completedRounds` intact, so a stopped attempt is already a complete
/// partial record — it was simply never displayed as one. This turns that
/// stored progress into the strings the history row and detail screen show.
///
/// Both functions return `nil` for a completed session, which is described
/// by its finishing time rather than by how far it got.
enum SessionProgressDescriber {

    /// Long form, for the session detail screen.
    static func describe(
        phase: SessionPhase,
        roundsCompleted: Int,
        totalRounds: Int,
        repsPerRound: Int
    ) -> String? {
        // A session whose template has gone missing (nullified, e.g. once
        // CloudKit sync can race a session ahead of its template) has no
        // round structure left to describe. Inventing "of 0" is worse than
        // saying nothing, so bail before the switch touches totalRounds.
        guard totalRounds > 0 else { return nil }

        switch phase {
        case .completed:
            return nil
        case .notStarted:
            return "Stopped before starting"
        case .run1:
            // Rounds hadn't begun; "0 of 20" would be noise, not information.
            return "Stopped during run 1"
        case .rounds:
            let reps = roundsCompleted * repsPerRound
            let totalReps = totalRounds * repsPerRound
            return "Stopped during rounds · \(roundsCompleted) of \(totalRounds) · \(reps) of \(totalReps) reps"
        case .run2:
            return "Stopped during run 2 · all \(totalRounds) rounds complete"
        }
    }

    /// Short form, for the history list row.
    static func shortDescription(
        phase: SessionPhase,
        roundsCompleted: Int,
        totalRounds: Int
    ) -> String? {
        // See describe(...) above: with no template there's no round
        // structure to summarize, so don't fabricate one.
        guard totalRounds > 0 else { return nil }

        switch phase {
        case .completed: return nil
        case .notStarted: return "Not started"
        case .run1: return "Quit in run 1"
        case .rounds: return "\(roundsCompleted)/\(totalRounds) rounds"
        case .run2: return "Quit in run 2"
        }
    }
}
