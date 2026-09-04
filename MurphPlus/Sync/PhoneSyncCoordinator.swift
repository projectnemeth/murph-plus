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

        let payload = SyncContext(
            templates: templates.map(\.spec),
            personalBests: Array(bests.values)
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? WCSession.default.updateApplicationContext([SyncKey.context: data])
    }

    /// The durable path, and the only one that may create a `MurphSession`.
    private func ingest(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(SyncPayload.self, from: data) else { return }
        let context = ModelContext(container)
        try? SessionImporter.apply(payload, context: context)

        // The session has landed in history, so stop mirroring it — otherwise
        // the phone shows the finished workout twice, once live and once real.
        if SessionState.replay(payload.events).isTerminal {
            mirror.markFinished(sessionID: payload.sessionID)
        }

        // A landed session may have set a new record, and the Watch badges its
        // completion screen from this context. Without the push, the next
        // Watch workout is judged against a record it has already been beaten by.
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
        guard let data = userInfo[SyncKey.payload] as? Data else { return }
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
