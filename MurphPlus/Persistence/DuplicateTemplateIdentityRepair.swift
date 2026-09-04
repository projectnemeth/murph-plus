// MurphPlus/Persistence/DuplicateTemplateIdentityRepair.swift
import Foundation
import SwiftData

/// Gives every `WorkoutTemplate` a genuinely unique `id`.
///
/// `WorkoutTemplate.id` was added as `= UUID()`. For a template created through
/// `init` that default is evaluated per instance and is correctly unique. But
/// when the property was added to a model that already had rows, SwiftData's
/// lightweight migration evaluated the default expression **once** and stamped
/// every backfilled row with the same value. Observed on a real upgraded
/// install: four starter templates, one distinct id between them.
///
/// That is latent today, because nothing looks a template up by id. It stops
/// being latent when the Watch arrives: a session records the id of the
/// template it was an attempt at, and the phone matches on it. Four templates
/// sharing an id makes that match arbitrary.
///
/// Self-healing rather than flag-gated: it only acts on ids that are actually
/// duplicated, so a second run finds nothing to do. That also means it repairs
/// any future backfill of the same shape without needing a new flag.
enum DuplicateTemplateIdentityRepair {
    static func repair(context: ModelContext) {
        guard let templates = try? context.fetch(FetchDescriptor<WorkoutTemplate>()) else { return }

        var seen: Set<UUID> = []
        var reassigned = false

        for template in templates {
            // The first holder of an id keeps it; every later collision gets a
            // fresh one. Keeping one row stable means a store that is already
            // correct is never churned.
            if seen.contains(template.id) {
                template.id = UUID()
                reassigned = true
            }
            seen.insert(template.id)
        }

        guard reassigned else { return }
        try? context.save()
    }
}
