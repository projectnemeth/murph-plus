// MurphCore/HeartRateAggregation.swift
import Foundation

struct HeartRateSummary: Codable, Equatable {
    var average: Int
    var maximum: Int
}

/// Per-segment heart rate, derived by bucketing journaled samples between the
/// round and run boundaries.
///
/// Deliberately derived rather than accumulated in running state: a crash
/// cannot corrupt a partial average, and the aggregation can be changed later
/// without re-recording anything.
enum HeartRateAggregator {

    /// `nil` when the window holds no samples — an absent summary, never a zero.
    /// Denied HealthKit authorization produces exactly this case.
    static func summary(events: [SessionEvent], from start: Date, to end: Date) -> HeartRateSummary? {
        var readings: [Int] = []
        for event in events {
            guard case let .heartRate(bpm, at) = event else { continue }
            guard at >= start, at <= end else { continue }
            readings.append(bpm)
        }
        guard !readings.isEmpty else { return nil }
        return HeartRateSummary(
            average: readings.reduce(0, +) / readings.count,
            maximum: readings.max() ?? 0
        )
    }

    /// One entry per completed round, in order, aligned with
    /// `SessionDerivation.roundDurations`.
    static func roundSummaries(events: [SessionEvent], state: SessionState) -> [HeartRateSummary?] {
        guard let roundsStartedAt = state.roundsStartedAt else { return [] }
        var result: [HeartRateSummary?] = []
        var boundary = roundsStartedAt
        for timestamp in state.roundTimestamps {
            result.append(summary(events: events, from: boundary, to: timestamp))
            boundary = timestamp
        }
        return result
    }

    /// Keyed by run index (1 or 2).
    ///
    /// The window is wall-clock: from the run's start to the `runFinished`
    /// event that ended it. `RunSplitState.durationSeconds` deliberately is
    /// *not* used to compute the end, because it is net of pause — a five
    /// minute pause during run 1 would pull the window's end five minutes
    /// early and silently drop every sample from the run's final five
    /// minutes, which is the hardest stretch of it.
    ///
    /// A paused stretch inside the window contributes nothing on its own:
    /// samples are never journaled while paused (`WatchSessionController`
    /// guards on `state.isPaused`), so the window needs no pause handling
    /// beyond reaching the true end.
    static func runSummaries(events: [SessionEvent], state: SessionState) -> [Int: HeartRateSummary] {
        var endByIndex: [Int: Date] = [:]
        for event in events {
            guard case let .runFinished(index, at, _) = event else { continue }
            endByIndex[index] = at
        }

        var result: [Int: HeartRateSummary] = [:]
        for split in state.runSplits {
            // The net-duration end is only a fallback for a state assembled
            // without the events that produced it; it can only ever be early,
            // never late, so it cannot pull in a sample from the next segment.
            let end = endByIndex[split.index]
                ?? split.startTime.addingTimeInterval(split.durationSeconds)
            if let summary = summary(events: events, from: split.startTime, to: end) {
                result[split.index] = summary
            }
        }
        return result
    }
}
