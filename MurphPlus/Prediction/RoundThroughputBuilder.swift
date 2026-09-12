// MurphPlus/Prediction/RoundThroughputBuilder.swift
import Foundation

enum RoundThroughputBuilder {
    static func build(session: MurphSession) -> [RoundThroughput] {
        guard let template = session.template,
              session.runSplits.contains(where: { $0.runIndex == 1 }),
              let roundsPhaseStart = RoundsPhaseStart.of(session) else { return [] }

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
