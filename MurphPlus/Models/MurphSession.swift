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
    /// When the rounds phase began — the true boundary before round 1.
    /// Persisted rather than derived from run 1's split, because that
    /// derivation is net of pause and would land earlier than the real
    /// boundary once a pause occurs during run 1, silently absorbing that
    /// pause into round 1's duration. Nil for sessions that have not yet
    /// finished run 1, and for sessions logged before this field existed.
    var roundsStartedAt: Date?
    var completedAt: Date?
    var completedRounds: Int = 0
    /// Written by the Watch in a later stage; stays `false` for phone sessions.
    var indoor: Bool = false
    var pausedSeconds: Double = 0
    var pausedAt: Date?

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
        return max(0, completedAt.timeIntervalSince(startedAt) - pausedSeconds)
    }
}
