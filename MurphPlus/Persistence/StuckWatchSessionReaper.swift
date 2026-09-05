// MurphPlus/Persistence/StuckWatchSessionReaper.swift
import Foundation
import SwiftData

/// Finds Watch-owned sessions the phone can no longer reach, and closes them.
///
/// A Watch session is imported `.inProgress` and only its owner can finish it.
/// If that Watch dies, is force-quit, or never comes back into range, nothing
/// ever moves the session on: `ResumableSessionFinder` excludes it by origin
/// (the phone must not become a second writer), `HistoryView` shows only past
/// sessions, and `NeverStartedSessionPurger` only takes rows that never
/// started. The row is real, holds real rounds, and is invisible — which is
/// indistinguishable from data loss.
///
/// Abandon rather than delete: the rounds the user actually did happened, and
/// `.abandoned` is a status history already renders.
enum StuckWatchSessionReaper {
    /// A Murph takes one to two hours. Six is generous enough that a genuinely
    /// long session is never swept, and short enough that a dead Watch surfaces
    /// the same day.
    static var defaultThreshold: TimeInterval {
        // Overridable in DEBUG so hardware test 10 can run in a minute rather
        // than six hours, without this file being edited and put back.
        DebugOverride.seconds("MurphStuckSessionThreshold") ?? shippedThreshold
    }

    static let shippedThreshold: TimeInterval = 6 * 3600

    static func stuckSessions(
        context: ModelContext,
        olderThan threshold: TimeInterval = defaultThreshold,
        now: Date = .now
    ) -> [MurphSession] {
        let inProgressRaw = SessionStatus.inProgress.rawValue
        let watchRaw = SessionOrigin.watch.rawValue
        let descriptor = FetchDescriptor<MurphSession>(
            predicate: #Predicate { $0.statusRaw == inProgressRaw && $0.originRaw == watchRaw }
        )
        guard let candidates = try? context.fetch(descriptor) else { return [] }
        return candidates.filter { session in
            guard let startedAt = session.startedAt else { return false }
            return now.timeIntervalSince(startedAt) > threshold
        }
    }

    static func abandon(_ session: MurphSession, context: ModelContext) {
        session.status = .abandoned
        session.completedAt = session.completedAt ?? .now
        try? context.save()
    }
}
