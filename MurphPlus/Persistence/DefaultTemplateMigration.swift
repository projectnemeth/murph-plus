// MurphPlus/Persistence/DefaultTemplateMigration.swift
import Foundation
import SwiftData

/// One-time correction for the Half/Mini Murph starter templates, which
/// shipped as straight sets (`rounds: 1`) but are Cindy-style in practice.
///
/// This exists because `DefaultTemplates.seedIfNeeded` returns early on a
/// non-empty store: changing the seed constants alone fixes nothing on any
/// install that has already run once, including every TestFlight build.
///
/// A template is corrected only if it still matches the shipped default in
/// every field. Any difference means the user edited it, and an edited
/// template is left completely alone.
enum DefaultTemplateMigration {
    static let flagKey = "didCorrectDefaultTemplateRounds"

    struct Correction {
        let name: String
        let runDistanceMiles: Double
        let totalPullUps: Int
        let totalPushUps: Int
        let totalSquats: Int
        let correctedRounds: Int
    }

    /// Both templates' rep totals divide exactly into Cindy 5/10/15 sets.
    static let corrections: [Correction] = [
        Correction(name: "Half Murph", runDistanceMiles: 0.5,
                   totalPullUps: 50, totalPushUps: 100, totalSquats: 150,
                   correctedRounds: 10),
        Correction(name: "Mini Murph", runDistanceMiles: 0.25,
                   totalPullUps: 25, totalPushUps: 50, totalSquats: 75,
                   correctedRounds: 5),
    ]

    static func runIfNeeded(context: ModelContext, defaults: UserDefaults = .standard) throws {
        guard !defaults.bool(forKey: flagKey) else { return }

        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        for correction in corrections {
            for template in templates where matchesAsShipped(template, correction) {
                template.rounds = correction.correctedRounds
            }
        }
        try context.save()

        // Set the flag unconditionally, including when nothing matched — a
        // fresh install seeds the corrected values directly and must never
        // re-enter this path on a later launch.
        defaults.set(true, forKey: flagKey)
    }

    private static func matchesAsShipped(_ template: WorkoutTemplate, _ correction: Correction) -> Bool {
        template.name == correction.name
            && template.rounds == 1
            && template.runDistanceMiles == correction.runDistanceMiles
            && template.totalPullUps == correction.totalPullUps
            && template.totalPushUps == correction.totalPushUps
            && template.totalSquats == correction.totalSquats
    }
}
