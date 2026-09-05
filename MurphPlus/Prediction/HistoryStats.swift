// MurphPlus/Prediction/HistoryStats.swift
import Foundation

/// The numbers above the session list.
///
/// Every one of them is **scoped to a single template and vest state**, never
/// computed across the whole history. A global minimum made a mini-Murph the
/// personal best for a full one — so the record for the workout you actually
/// do became unreachable the moment a shorter template was logged, and the
/// trend compared times from two different workouts.
///
/// The scoping rule is `PersonalBestCheck`'s, not a second one invented here:
/// a record belongs to a (template, vest) pair, because a vested Murph is a
/// materially harder workout and beating an unvested time says nothing about
/// it. `PhoneSyncCoordinator` already builds the Watch's records this way; this
/// was the last place still taking a bare `min()`.
enum HistoryStats {
    /// What makes two sessions comparable.
    ///
    /// `templateID` is optional because a session's template can be deleted
    /// (`WorkoutTemplate` nullifies rather than cascades, so the history
    /// survives the template). Those sessions group together rather than
    /// vanishing — they are still attempts, and grouping them is the least
    /// wrong of the options available once the definition of the workout is
    /// gone.
    struct Scope: Hashable {
        let templateID: UUID?
        let vestOn: Bool
    }

    struct Summary {
        let personalBestSeconds: Double?
        let mostRecentSeconds: Double?
        let trendSeconds: Double?
        /// Attempts **within the scope**, completed or abandoned. A count that
        /// spanned every template would sit beside two numbers that don't,
        /// which is how the global best went unnoticed for as long as it did.
        let attempts: Int
        /// Human-readable scope, e.g. "Full Murph · vest". `nil` when there is
        /// nothing to describe. The view shows it under the best: a record
        /// that doesn't say what it is a record *of* is what this whole fix is
        /// about.
        let scopeLabel: String?
    }

    static func scope(of session: MurphSession) -> Scope {
        Scope(templateID: session.template?.id, vestOn: session.vestOn)
    }

    /// - Parameter sessions: every past session — completed *and* abandoned.
    ///   The completed filter lives here rather than at the call site so the
    ///   attempt count and the times cannot drift apart.
    ///
    /// The scope is taken from the **most recent completed session**: that is
    /// the workout the user is currently doing, so it is the record they came
    /// to see. With no completed session there is nothing to scope to and
    /// every field is empty.
    static func summarize(sessions: [MurphSession]) -> Summary {
        let completed = sessions
            .filter { $0.status == .completed && $0.totalElapsedSeconds != nil }
            .sorted { $0.date < $1.date }

        guard let latest = completed.last else {
            return Summary(
                personalBestSeconds: nil, mostRecentSeconds: nil, trendSeconds: nil,
                attempts: sessions.count, scopeLabel: nil
            )
        }

        let scope = scope(of: latest)
        let inScope = completed.filter { self.scope(of: $0) == scope }
        let times = inScope.compactMap(\.totalElapsedSeconds)

        return Summary(
            personalBestSeconds: times.min(),
            mostRecentSeconds: times.last,
            // Against the previous attempt at *this* workout, which is the only
            // comparison that means anything.
            trendSeconds: times.count >= 2 ? times[times.count - 1] - times[times.count - 2] : nil,
            attempts: sessions.filter { self.scope(of: $0) == scope }.count,
            scopeLabel: label(for: latest)
        )
    }

    /// The sessions to badge as a record — the fastest in each scope.
    ///
    /// Returned as a set rather than a single time so the badge is a property
    /// of the session, not of its duration: comparing a row's elapsed against
    /// one global best badged every session that merely *tied* it, including
    /// ones run with a different template.
    ///
    /// A scope with a single attempt gets no badge. There was no record to
    /// beat, and calling a debut a record is the same overclaim
    /// `PersonalBestCheck` already refuses to make on the Watch.
    static func personalBestIDs(sessions: [MurphSession]) -> Set<UUID> {
        var best: [Scope: (id: UUID, seconds: Double)] = [:]
        var counts: [Scope: Int] = [:]

        for session in sessions
        where session.status == .completed && session.totalElapsedSeconds != nil {
            let scope = scope(of: session)
            let seconds = session.totalElapsedSeconds!
            counts[scope, default: 0] += 1
            // Strictly-less, so a tie leaves the earlier session holding the
            // badge — the record was set the first time it was run.
            if let existing = best[scope], existing.seconds <= seconds { continue }
            best[scope] = (session.id, seconds)
        }

        return Set(best.filter { counts[$0.key, default: 0] > 1 }.values.map(\.id))
    }

    private static func label(for session: MurphSession) -> String {
        let name = session.template?.name ?? "Murph"
        return session.vestOn ? "\(name) · vest" : name
    }
}
