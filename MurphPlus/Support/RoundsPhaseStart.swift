// MurphPlus/Support/RoundsPhaseStart.swift
import Foundation

/// Where the rounds phase began for a saved `MurphSession` — the true
/// boundary before round 1.
///
/// Shared by `RoundThroughputBuilder` (the History screen's fatigue
/// prediction) and `SessionRecap` (the completed recap's round splits) so the
/// two screens can never independently drift on where the same session's
/// round 1 actually starts.
enum RoundsPhaseStart {
    /// Prefer the persisted rounds-phase start: it is the true wall-clock
    /// boundary. The run1-derived fallback is net of pause and would land
    /// earlier than the true boundary once a pause occurs during run 1 —
    /// exact for every pre-existing session, since none of them can contain
    /// a pause.
    static func of(_ session: MurphSession) -> Date? {
        if let roundsStartedAt = session.roundsStartedAt { return roundsStartedAt }
        guard let run1 = session.runSplits.first(where: { $0.runIndex == 1 }) else { return nil }
        return run1.startTime.addingTimeInterval(run1.durationSeconds)
    }
}
