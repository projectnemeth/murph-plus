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
        switch phase {
        case .completed: return nil
        case .notStarted: return "Not started"
        case .run1: return "Run 1"
        case .rounds: return "\(roundsCompleted)/\(totalRounds) rounds"
        case .run2: return "Run 2"
        }
    }
}
