// MurphPlus/Models/RunSplit.swift
import Foundation
import SwiftData

@Model
final class RunSplit {
    var runIndex: Int = 1
    var startTime: Date = Date.distantPast
    var durationSeconds: Double = 0
    var distanceMeters: Double?
    var avgHeartRate: Int?
    var maxHeartRate: Int?
    var session: MurphSession?

    init(runIndex: Int, startTime: Date, durationSeconds: Double, session: MurphSession? = nil) {
        self.runIndex = runIndex
        self.startTime = startTime
        self.durationSeconds = durationSeconds
        self.session = session
    }
}
