// MurphCore/SessionDerivation.swift
import Foundation

/// Durations derived from a session's state, all of them net of paused time.
///
/// Pause exists so an interruption does not skew a logged time. That is only
/// true if every duration that spans a pause excludes it — including per-round
/// durations, which feed the least-squares fatigue fit. A pause charged to a
/// round produces a plausible-looking but wrong prediction with no visible
/// symptom, which is the most expensive kind of bug this app can have.
enum SessionDerivation {

    static func elapsed(_ state: SessionState, now: Date) -> TimeInterval {
        guard let startedAt = state.startedAt else { return 0 }
        let end = state.completedAt ?? now
        let gross = end.timeIntervalSince(startedAt)
        return max(0, gross - state.pausedSeconds(between: startedAt, and: end))
    }

    /// One duration per completed round, in order. Round *n* is measured from
    /// the previous round's completion — or from the start of the rounds phase,
    /// for round 1 — with any overlapping paused time removed.
    static func roundDurations(_ state: SessionState) -> [TimeInterval] {
        guard let roundsStartedAt = state.roundsStartedAt else { return [] }

        var durations: [TimeInterval] = []
        var boundary = roundsStartedAt
        for timestamp in state.roundTimestamps {
            let gross = timestamp.timeIntervalSince(boundary)
            let paused = state.pausedSeconds(between: boundary, and: timestamp)
            durations.append(max(0, gross - paused))
            boundary = timestamp
        }
        return durations
    }
}
