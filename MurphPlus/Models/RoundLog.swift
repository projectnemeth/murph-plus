// MurphPlus/Models/RoundLog.swift
import Foundation
import SwiftData

@Model
final class RoundLog {
    var roundNumber: Int = 0
    var completedAt: Date = Date.distantPast
    var session: MurphSession?

    init(roundNumber: Int, completedAt: Date, session: MurphSession? = nil) {
        self.roundNumber = roundNumber
        self.completedAt = completedAt
        self.session = session
    }
}
