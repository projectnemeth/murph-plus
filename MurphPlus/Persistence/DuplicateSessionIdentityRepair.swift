// MurphPlus/Persistence/DuplicateSessionIdentityRepair.swift
import Foundation
import SwiftData

/// Gives every `MurphSession` a genuinely unique `id`.
///
/// `MurphSession.id` was added as `= UUID()`. For a session created through
/// `init` that default is evaluated per instance and is correctly unique. But
/// when the property was added to a model that already had rows, SwiftData's
/// lightweight migration evaluated the default expression **once** and
/// stamped every backfilled row with the same value — this was observed on a
/// real upgraded install for `WorkoutTemplate.id` in an earlier stage (see
/// `DuplicateTemplateIdentityRepair`), and the same migration shape applies
/// here.
///
/// The stakes are higher for sessions: `MurphSession.id` is the dedup key for
/// the entire sync protocol. `SessionImporter` fetches by it, so if every
/// pre-existing session shares one id, the first checkpoint to arrive from
/// the Watch matches an arbitrary old workout and overwrites it — destroying
/// a logged record the app promises is uneditable.
///
/// Self-healing rather than flag-gated: it only acts on ids that are actually
/// duplicated, so a second run finds nothing to do, an already-correct store
/// is never churned, and any future backfill of the same shape is repaired
/// without needing a new flag. Must run before any importer can execute.
enum DuplicateSessionIdentityRepair {
    static func repair(context: ModelContext) {
        guard let sessions = try? context.fetch(FetchDescriptor<MurphSession>()) else { return }

        var seen: Set<UUID> = []
        var reassigned = false

        for session in sessions {
            // The first holder of an id keeps it; every later collision gets a
            // fresh one. Keeping one row stable means a store that is already
            // correct is never churned.
            if seen.contains(session.id) {
                session.id = UUID()
                reassigned = true
            }
            seen.insert(session.id)
        }

        guard reassigned else { return }
        try? context.save()
    }
}
