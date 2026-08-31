// MurphPlus/Prediction/RoundThroughputBuilder.swift
import Foundation

enum RoundThroughputBuilder {
    static func build(session: MurphSession) -> [RoundThroughput] {
        guard let template = session.template,
              let run1 = session.runSplits.first(where: { $0.runIndex == 1 }) else { return [] }

        let roundsPhaseStart = run1.startTime.addingTimeInterval(run1.durationSeconds)
        let sortedLogs = session.roundLogs.sorted { $0.roundNumber < $1.roundNumber }
        let repsPerRound = template.repsPerRound

        var results: [RoundThroughput] = []
        var previousTimestamp = roundsPhaseStart

        for log in sortedLogs {
            let duration = Int(log.completedAt.timeIntervalSince(previousTimestamp).rounded())
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
