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

    /// The one formula for "how long did this stretch actually take": the
    /// wall-clock gap between two points, minus whatever of it was paused.
    /// `elapsed` and `roundDurations` below are both just this applied to a
    /// different pair of boundaries, and any other net-of-pause duration
    /// anywhere in the app should be too — two copies of this three-line
    /// idiom agree with each other right up until one of them drifts, and
    /// that disagreement has no visible symptom until a prediction or a
    /// displayed time is quietly wrong.
    static func netDuration(_ state: SessionState, from start: Date, to end: Date) -> TimeInterval {
        let gross = end.timeIntervalSince(start)
        let paused = state.pausedSeconds(between: start, and: end)
        return max(0, gross - paused)
    }

    static func elapsed(_ state: SessionState, now: Date) -> TimeInterval {
        guard let startedAt = state.startedAt else { return 0 }
        let end = state.completedAt ?? now
        return netDuration(state, from: startedAt, to: end)
    }

    /// One duration per completed round, in order. Round *n* is measured from
    /// the previous round's completion — or from the start of the rounds phase,
    /// for round 1 — with any overlapping paused time removed.
    static func roundDurations(_ state: SessionState) -> [TimeInterval] {
        guard let roundsStartedAt = state.roundsStartedAt else { return [] }

        var durations: [TimeInterval] = []
        var boundary = roundsStartedAt
        for timestamp in state.roundTimestamps {
            durations.append(netDuration(state, from: boundary, to: timestamp))
            boundary = timestamp
        }
        return durations
    }
}
