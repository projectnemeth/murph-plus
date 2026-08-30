// MurphPlus/Models/WorkoutTemplate.swift
import SwiftData

@Model
final class WorkoutTemplate {
    var name: String = ""
    var runDistanceMiles: Double = 1.0
    var totalPullUps: Int = 100
    var totalPushUps: Int = 200
    var totalSquats: Int = 300
    var rounds: Int = 1

    init(
        name: String,
        runDistanceMiles: Double = 1.0,
        totalPullUps: Int = 100,
        totalPushUps: Int = 200,
        totalSquats: Int = 300,
        rounds: Int = 1
    ) {
        self.name = name
        self.runDistanceMiles = runDistanceMiles
        self.totalPullUps = totalPullUps
        self.totalPushUps = totalPushUps
        self.totalSquats = totalSquats
        self.rounds = rounds
    }

    // `max(rounds, 1)` guards against integer division by zero, which would be a
    // hard crash rather than a recoverable error if a stored value ever hits 0.
    private var safeRounds: Int { max(rounds, 1) }

    var totalReps: Int { totalPullUps + totalPushUps + totalSquats }
    var pullUpsPerRound: Int { totalPullUps / safeRounds }
    var pushUpsPerRound: Int { totalPushUps / safeRounds }
    var squatsPerRound: Int { totalSquats / safeRounds }
    var repsPerRound: Int { totalReps / safeRounds }
}
