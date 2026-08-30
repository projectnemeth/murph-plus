// MurphPlus/Models/MurphSession.swift
import Foundation
import SwiftData

@Model
final class MurphSession {
    var date: Date = Date.distantPast
    var template: WorkoutTemplate?
    var vestOn: Bool = false
    var vestWeightLbs: Int?
    var statusRaw: String = SessionStatus.inProgress.rawValue
    var phaseRaw: String = SessionPhase.notStarted.rawValue
    var notes: String?
    var startedAt: Date?
    var currentPhaseStartedAt: Date?
    var completedAt: Date?
    var completedRounds: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \RunSplit.session)
    var runSplits: [RunSplit] = []

    @Relationship(deleteRule: .cascade, inverse: \RoundLog.session)
    var roundLogs: [RoundLog] = []

    init(
        date: Date = .now,
        template: WorkoutTemplate?,
        vestOn: Bool,
        vestWeightLbs: Int? = nil
    ) {
        self.date = date
        self.template = template
        self.vestOn = vestOn
        self.vestWeightLbs = vestOn ? (vestWeightLbs ?? 20) : nil
        self.statusRaw = SessionStatus.inProgress.rawValue
        self.phaseRaw = SessionPhase.notStarted.rawValue
        self.completedRounds = 0
    }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .inProgress }
        set { statusRaw = newValue.rawValue }
    }

    var phase: SessionPhase {
        get { SessionPhase(rawValue: phaseRaw) ?? .notStarted }
        set { phaseRaw = newValue.rawValue }
    }

    var totalElapsedSeconds: Double? {
        guard let startedAt, let completedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }
}
