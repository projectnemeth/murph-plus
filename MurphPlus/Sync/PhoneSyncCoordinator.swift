// MurphPlus/Sync/PhoneSyncCoordinator.swift
import Foundation
import Observation
import SwiftData
import WatchConnectivity

/// The phone's side of the link: receives the Watch's live events and durable
/// checkpoints, and pushes reference data back down.
@Observable
@MainActor
final class PhoneSyncCoordinator: NSObject {
    let mirror = LiveMirrorStore()
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Latest-value-wins reference data for the Watch: the current template
    /// list plus personal bests, so the Watch can offer the right workouts and
    /// its completion screen can badge a PB without asking the phone.
    func pushContext() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }

        let context = ModelContext(container)
        guard
            let templates = try? context.fetch(FetchDescriptor<WorkoutTemplate>()),
            let sessions = try? context.fetch(FetchDescriptor<MurphSession>())
        else { return }

        // A best is per template *and* per vest state: the prediction refuses
        // to mix them, so a vested time is not a best for an unvested attempt.
        var bests: [String: PersonalBest] = [:]
        for session in sessions where session.status == .completed {
            guard
                let templateID = session.template?.id,
                let seconds = session.totalElapsedSeconds
            else { continue }
            let key = "\(templateID)-\(session.vestOn)"
            if let existing = bests[key], existing.seconds <= seconds { continue }
            bests[key] = PersonalBest(templateID: templateID, vestOn: session.vestOn, seconds: seconds)
        }

        let acknowledged = Self.acknowledgements(from: sessions)
        let payload = SyncContext(
            templates: templates.map(\.spec),
            personalBests: Array(bests.values),
            acknowledgedSessionIDs: acknowledged.ids,
            acknowledgementHorizon: acknowledged.horizon
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? WCSession.default.updateApplicationContext([SyncKey.context: data])
    }

    /// The sessions the Watch may stop holding a journal for.
    ///
    /// Terminal ones only. A session the phone holds mid-way is one whose final
    /// checkpoint never landed, and acknowledging it would invite the Watch to
    /// delete the only remaining copy of a workout that will otherwise sit
    /// `.inProgress` forever.
    ///
    /// Watch-origin only, since those are the only journals that exist, and
    /// capped at the most recent 100 so the application context cannot grow
    /// without bound across years of workouts.
    ///
    /// The cap comes with a horizon, because on its own it is a trap: a journal
    /// the phone already holds but which has fallen outside the window can
    /// never be named, so the Watch resends it, the phone ignores it as a stale
    /// sequence — without changing its acknowledgement set — and the same
    /// journal is re-transferred on every pass forever. Returning the oldest
    /// acknowledged date alongside the ids lets the Watch tell "not yet
    /// acknowledged" from "beyond anything that will ever be acknowledged".
    ///
    /// `nil` horizon means the list was not capped and so covers everything.
    static let acknowledgementLimit = 100

    static func acknowledgements(
        from sessions: [MurphSession]
    ) -> (ids: [UUID], horizon: Date?) {
        let terminal = sessions
            .filter { $0.origin == .watch && $0.status != .inProgress }
            .sorted { $0.date > $1.date }
        let named = terminal.prefix(acknowledgementLimit)
        return (
            named.map(\.id),
            terminal.count > acknowledgementLimit ? named.last?.date : nil
        )
    }

    /// The durable path, and the only one that may create a `MurphSession`.
    ///
    /// Every outcome is logged, not just the failures. The Watch says what it
    /// sent; this says what arrived and what became of it, and the pair is what
    /// makes "never sent" distinguishable from "sent but never delivered" —
    /// the question a lost workout could not previously be asked.
    private func ingest(_ data: Data) {
        // Both failure paths below are logged rather than swallowed. A decode
        // failure is realistic — the user updates the Watch app but not the
        // phone app and `SessionEvent` gains a case — and it drops every
        // checkpoint of every session with no signal at all.
        guard let payload = try? JSONDecoder().decode(SyncPayload.self, from: data) else {
            SyncLog.failure("checkpoint could not be decoded (\(data.count)B) — dropped")
            return
        }

        // `mainContext`, not a fresh `ModelContext`: `ingest` is already on the
        // main actor, and this is the context the rest of the app uses. A
        // separate one would leave imported sessions depending on cross-context
        // merge to reach the `@Query`-backed History screen.
        let landed: MurphSession?
        do {
            landed = try SessionImporter.apply(payload, context: container.mainContext)
        } catch {
            SyncLog.failure(
                "checkpoint \(payload.checkpointSeq) could not be imported — \(error.localizedDescription)"
            )
            return
        }

        let state = SessionState.replay(payload.events)

        // `landed` is nil only when the payload changed nothing: a stale or
        // duplicate sequence, or a journal that replays without a template.
        // Which of the two matters — one is normal traffic, the other means a
        // session can never land — so the log distinguishes them.
        guard landed != nil else {
            SyncLog.checkpointIgnored(
                sessionID: payload.sessionID, seq: payload.checkpointSeq,
                reason: state.template == nil || state.startedAt == nil
                    ? "journal replays without a template or a start time"
                    : "sequence is not newer than the one already stored"
            )
            return
        }

        SyncLog.checkpointApplied(
            sessionID: payload.sessionID, seq: payload.checkpointSeq, terminal: state.isTerminal
        )

        guard state.isTerminal else { return }

        // The session has landed in history, so stop mirroring it — otherwise
        // the phone shows the finished workout twice, once live and once real.
        //
        // Gated on the import actually having produced a session, because
        // `markFinished` is irreversible: it records the id in `finished`,
        // which blocks any later re-mirroring. Running it on a failed import
        // would lose the terminal checkpoint *and* wipe the mirror — the only
        // remaining on-screen trace of that workout. Skipping it on a stale
        // terminal checkpoint is safe: a higher sequence is already stored, and
        // that one was terminal too, so the id was marked when it arrived.
        mirror.markFinished(sessionID: payload.sessionID)

        // A landed session may have set a new record, and the Watch badges its
        // completion screen from this context. Without the push, the next
        // Watch workout is judged against a record it has already been beaten by.
        //
        // Only a terminal checkpoint can move a personal best, and `pushContext`
        // fetches every `MurphSession` and every `WorkoutTemplate` on the main
        // actor — so the other ~24 checkpoints of a workout would each buy a
        // full history scan for a result that cannot have changed.
        pushContext()
    }
}

extension PhoneSyncCoordinator: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in self.pushContext() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Reactivate so the link survives the user switching paired watches.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    /// Durable handoff. This is the only path that creates a `MurphSession`.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[SyncKey.payload] as? Data else {
            SyncLog.failure("userInfo arrived with no payload under the expected key")
            return
        }
        SyncLog.checkpointArrived(bytes: data.count, carrier: .userInfo)
        Task { @MainActor in self.ingest(data) }
    }

    /// The large-payload counterpart of `didReceiveUserInfo`. A `WCSessionFile`'s
    /// URL is only valid until this method returns — the system deletes it right
    /// after — so the read must happen synchronously here, before hopping to
    /// the main actor.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let data = try? Data(contentsOf: file.fileURL) else {
            SyncLog.failure("a transferred checkpoint file could not be read before the system reclaimed it")
            return
        }
        SyncLog.checkpointArrived(bytes: data.count, carrier: .file)
        Task { @MainActor in self.ingest(data) }
    }

    /// Live mirror. Rendered and forgotten — never persisted.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard
            let eventData = message[SyncKey.liveEvent] as? Data,
            let idString = message[SyncKey.liveSessionID] as? String,
            let sessionID = UUID(uuidString: idString),
            let event = try? JSONDecoder().decode(SessionEvent.self, from: eventData)
        else { return }

        Task { @MainActor in
            self.mirror.receive(sessionID: sessionID, event: event)
        }
    }
}
