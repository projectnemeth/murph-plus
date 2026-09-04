// MurphPlus/Prediction/RoundThroughputBuilder.swift
import Foundation

enum RoundThroughputBuilder {
    static func build(session: MurphSession) -> [RoundThroughput] {
        guard let template = session.template,
              let run1 = session.runSplits.first(where: { $0.runIndex == 1 }) else { return [] }

        // Prefer the persisted rounds-phase start: it is the true wall-clock
        // boundary. The run1-derived fallback is net of pause and would land
        // earlier than the true boundary once a pause occurs during run 1 —
        // exact for every pre-existing session, since none of them can contain
        // a pause.
        let roundsPhaseStart = session.roundsStartedAt
            ?? run1.startTime.addingTimeInterval(run1.durationSeconds)
        let sortedLogs = session.roundLogs.sorted { $0.roundNumber < $1.roundNumber }
        let repsPerRound = template.repsPerRound

        var results: [RoundThroughput] = []
        var previousTimestamp = roundsPhaseStart

        for log in sortedLogs {
            // Net of pause: an interruption inside a round would otherwise read as
            // a very slow round and bend the fatigue curve.
            let duration = Int((log.completedAt.timeIntervalSince(previousTimestamp) - log.pausedSecondsInRound).rounded())
            results.append(RoundThroughput(
                cumulativeRepsAfter: log.roundNumber * repsPerRound,
                secondsForRound: duration,
                repsInRound: repsPerRound
            ))
            previousTimestamp = log.completedAt
        }

        return results
    }
}
