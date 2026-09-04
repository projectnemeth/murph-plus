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
    /// `durationSeconds` is net of pause, so a run containing a long pause
    /// computes an end slightly earlier than wall-clock. Samples are not
    /// collected while paused (the `HKWorkoutSession` is itself paused), so no
    /// real sample falls in the discarded tail.
    static func runSummaries(events: [SessionEvent], state: SessionState) -> [Int: HeartRateSummary] {
        var result: [Int: HeartRateSummary] = [:]
        for split in state.runSplits {
            let end = split.startTime.addingTimeInterval(split.durationSeconds)
            if let summary = summary(events: events, from: split.startTime, to: end) {
                result[split.index] = summary
            }
        }
        return result
    }
}
