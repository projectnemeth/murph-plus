// MurphPlus/Session/SessionEngine.swift
import Foundation
import Observation
import SwiftData

@Observable
final class SessionEngine {
    private(set) var session: MurphSession
    private let context: ModelContext

    init(session: MurphSession, context: ModelContext) {
        self.session = session
        self.context = context
    }

    static func startNew(template: WorkoutTemplate, vestOn: Bool, vestWeightLbs: Int?, context: ModelContext) -> SessionEngine {
        let session = MurphSession(template: template, vestOn: vestOn, vestWeightLbs: vestWeightLbs)
        context.insert(session)
        try? context.save()
        return SessionEngine(session: session, context: context)
    }

    /// A completed or abandoned session is terminal: no further transition may
    /// mutate it. Guarding on phase alone is not enough, because `abandon()`
    /// changes only `status` — leaving `phase` wherever it was, which would let
    /// `completeRound()`/`finishRun()` run afterwards and silently flip an
    /// abandoned session back to `.completed`, destroying the record.
    private var isTerminal: Bool {
        session.status == .completed || session.status == .abandoned
    }

    func start() {
        guard !isTerminal else { return }
        guard session.phase == .notStarted else { return }
        let now = Date.now
        session.startedAt = now
        session.phase = .run1
        session.currentPhaseStartedAt = now
        save()
    }

    func finishRun() {
        guard !isTerminal else { return }
        guard session.phase == .run1 || session.phase == .run2,
              let start = session.currentPhaseStartedAt else { return }

        let runIndex = session.phase == .run1 ? 1 : 2
        let now = Date.now
        let split = RunSplit(runIndex: runIndex, startTime: start, durationSeconds: now.timeIntervalSince(start), session: session)
        context.insert(split)
        session.runSplits.append(split)

        if session.phase == .run1 {
            session.phase = .rounds
            session.currentPhaseStartedAt = now
        } else {
            session.phase = .completed
            session.status = .completed
            session.completedAt = now
            session.currentPhaseStartedAt = nil
        }
        save()
    }

    func completeRound() {
        guard !isTerminal else { return }
        guard session.phase == .rounds, let template = session.template else { return }

        let nextRoundNumber = session.completedRounds + 1
        let log = RoundLog(roundNumber: nextRoundNumber, completedAt: .now, session: session)
        context.insert(log)
        session.roundLogs.append(log)
        session.completedRounds = nextRoundNumber

        if session.completedRounds >= template.rounds {
            session.phase = .run2
            session.currentPhaseStartedAt = .now
        }
        save()
    }

    func abandon() {
        guard !isTerminal else { return }
        session.status = .abandoned
        session.completedAt = .now
        session.currentPhaseStartedAt = nil
        save()
    }

    var totalElapsed: TimeInterval {
        guard let startedAt = session.startedAt else { return 0 }
        let end = session.completedAt ?? .now
        return end.timeIntervalSince(startedAt)
    }

    private func save() {
        try? context.save()
    }
}
