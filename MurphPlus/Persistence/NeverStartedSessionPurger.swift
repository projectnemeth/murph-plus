// MurphPlus/Persistence/NeverStartedSessionPurger.swift
import Foundation
import SwiftData

/// Removes sessions that were created but never started.
///
/// `SessionEngine.startNew` persists a session the moment "Begin" is tapped,
/// before the user taps "Start Run 1". Two things can leave a row stranded in
/// that window: an app kill (status stays `.inProgress`), or the user
/// abandoning from the setup screen (status becomes `.abandoned`). Neither has
/// a `startedAt`, and nothing was ever recorded against either — so neither is
/// an attempt, and deleting loses nothing.
///
/// The predicate deliberately filters on `startedAt` rather than on status. An
/// earlier status-scoped version caught only the `.inProgress` case and walked
/// straight past a never-started abandon, which then counted toward the
/// Attempts tile forever.
enum NeverStartedSessionPurger {
    static func purge(context: ModelContext) {
        // `startedAt == nil` is not expressible in a #Predicate against an
        // optional Date on all supported OS versions, so the store is fetched
        // and filtered in memory. Session volume is low by design — this runs
        // once per launch over a handful of rows.
        guard let sessions = try? context.fetch(FetchDescriptor<MurphSession>()) else { return }
        var removed = false
        for session in sessions where session.startedAt == nil {
            context.delete(session)
            removed = true
        }
        guard removed else { return }
        try? context.save()
    }
}
