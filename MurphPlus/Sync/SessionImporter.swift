// MurphPlus/Sync/SessionImporter.swift
import Foundation
import SwiftData

/// Applies a received checkpoint to the phone's system of record.
///
/// A checkpoint carries the whole journal, so application is a wholesale
/// replace rather than a merge: the session's splits and round logs are rebuilt
/// from the replayed state every time. Combined with the "only a strictly
/// higher sequence applies" rule, that makes duplicate and out-of-order
/// delivery harmless without any conflict resolution.
enum SessionImporter {

    /// Returns the session, or `nil` if the payload was ignored as stale.
    @discardableResult
    static func apply(_ payload: SyncPayload, context: ModelContext) throws -> MurphSession? {
        let sessionID = payload.sessionID
        let descriptor = FetchDescriptor<MurphSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        let existing = try context.fetch(descriptor).first

        if let existing, !SessionMerge.shouldApply(incoming: payload, storedSeq: existing.lastCheckpointSeq) {
            return nil
        }

        let state = SessionState.replay(payload.events)
        guard let spec = state.template, let startedAt = state.startedAt else { return nil }

        let template = try resolveTemplate(spec, context: context)
        let session = existing ?? {
            let new = MurphSession(template: template, vestOn: state.vestOn, vestWeightLbs: state.vestWeightLbs)
            new.id = sessionID
            context.insert(new)
            return new
        }()

        session.template = template
        session.origin = payload.origin
        session.date = startedAt
        session.startedAt = startedAt
        session.vestOn = state.vestOn
        session.vestWeightLbs = state.vestWeightLbs
        session.indoor = state.indoor
        session.phase = state.phase
        session.status = state.status
        session.completedAt = state.completedAt
        session.completedRounds = state.completedRounds
        session.currentPhaseStartedAt = state.currentPhaseStartedAt
        session.pausedSeconds = totalPaused(state)
        // Stage 1 persists the true rounds-phase start and `RoundThroughputBuilder`
        // PREFERS it. Leaving it nil would send the builder to its fallback,
        // `run1.startTime + run1.durationSeconds` — which is net of pause, so round 1
        // would absorb any pause taken during run 1 and read as slower than it was,
        // bending the fatigue curve. Every imported session must carry it.
        session.roundsStartedAt = state.roundsStartedAt
        session.pausedIntervalsData = try? JSONEncoder().encode(state.pausedIntervals)
        session.lastCheckpointSeq = payload.checkpointSeq
        session.journalData = try? JSONEncoder().encode(payload.strippingHeartRate().events)

        rebuildSplits(on: session, state: state, events: payload.events, context: context)
        rebuildRounds(on: session, state: state, events: payload.events, context: context)

        try context.save()
        return session
    }

    // MARK: - Pieces

    private static func totalPaused(_ state: SessionState) -> Double {
        guard let startedAt = state.startedAt else { return 0 }
        let end = state.completedAt ?? Date.now
        return state.pausedSeconds(between: startedAt, and: end)
    }

    /// Three paths, in order. Links to the live template when the ID resolves;
    /// failing that, matches an existing template on shape, because the Watch's
    /// starter templates carry ids generated per process launch and an existing
    /// install's seeded templates carry ids from before sync existed; and only
    /// when neither hits does it reconstruct from the snapshot, so a deleted
    /// template never costs history the record of what the workout actually was.
    private static func resolveTemplate(_ spec: TemplateSpec, context: ModelContext) throws -> WorkoutTemplate {
        let specID = spec.id
        let descriptor = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate { $0.id == specID }
        )
        if let found = try context.fetch(descriptor).first { return found }

        // Fall back to matching on shape. The Watch's starter templates carry
        // ids generated per process launch, and an existing install's seeded
        // templates carry ids from before sync existed — in both cases the id
        // misses but the workout is the one the user already has. Without this
        // the picker gains a duplicate for every Watch relaunch.
        let allTemplates = (try? context.fetch(FetchDescriptor<WorkoutTemplate>())) ?? []
        if let match = allTemplates.first(where: {
            $0.name == spec.name
                && $0.rounds == spec.rounds
                && $0.runDistanceMiles == spec.runDistanceMiles
                && $0.totalPullUps == spec.totalPullUps
                && $0.totalPushUps == spec.totalPushUps
                && $0.totalSquats == spec.totalSquats
        }) {
            return match
        }

        let rebuilt = WorkoutTemplate(
            name: spec.name,
            runDistanceMiles: spec.runDistanceMiles,
            totalPullUps: spec.totalPullUps,
            totalPushUps: spec.totalPushUps,
            totalSquats: spec.totalSquats,
            rounds: spec.rounds
        )
        rebuilt.id = spec.id
        context.insert(rebuilt)
        return rebuilt
    }

    private static func rebuildSplits(
        on session: MurphSession, state: SessionState,
        events: [SessionEvent], context: ModelContext
    ) {
        for old in session.runSplits { context.delete(old) }
        session.runSplits.removeAll()

        let summaries = HeartRateAggregator.runSummaries(events: events, state: state)
        for split in state.runSplits {
            let model = RunSplit(
                runIndex: split.index,
                startTime: split.startTime,
                durationSeconds: split.durationSeconds,
                session: session
            )
            model.distanceMeters = split.distanceMeters
            model.avgHeartRate = summaries[split.index]?.average
            model.maxHeartRate = summaries[split.index]?.maximum
            context.insert(model)
            session.runSplits.append(model)
        }
    }

    private static func rebuildRounds(
        on session: MurphSession, state: SessionState,
        events: [SessionEvent], context: ModelContext
    ) {
        for old in session.roundLogs { context.delete(old) }
        session.roundLogs.removeAll()

        let summaries = HeartRateAggregator.roundSummaries(events: events, state: state)
        let durations = SessionDerivation.roundDurations(state)
        var boundary = state.roundsStartedAt

        for (index, timestamp) in state.roundTimestamps.enumerated() {
            let log = RoundLog(roundNumber: index + 1, completedAt: timestamp, session: session)
            if let start = boundary {
                // Wall-clock minus the net duration is exactly the paused time
                // inside this round — stored so the fatigue fit stays honest.
                let gross = timestamp.timeIntervalSince(start)
                log.pausedSecondsInRound = max(0, gross - durations[index])
            }
            log.avgHeartRate = summaries[index]?.average
            log.maxHeartRate = summaries[index]?.maximum
            context.insert(log)
            session.roundLogs.append(log)
            boundary = timestamp
        }
    }
}
