// MurphPlus/Models/RoundLog.swift
import Foundation
import SwiftData

@Model
final class RoundLog {
    var roundNumber: Int = 0
    var completedAt: Date = Date.distantPast
    var session: MurphSession?
    /// Paused time falling inside this round's interval, already excluded from
    /// the round's effective duration. Stored rather than derived so a relaunch
    /// mid-session cannot lose the correction.
    var pausedSecondsInRound: Double = 0
    var avgHeartRate: Int?
    var maxHeartRate: Int?

    init(roundNumber: Int, completedAt: Date, session: MurphSession? = nil) {
        self.roundNumber = roundNumber
        self.completedAt = completedAt
        self.session = session
    }
}
