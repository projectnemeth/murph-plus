// MurphPlus/MurphPlusApp.swift
import SwiftUI
import SwiftData

@main
struct MurphPlusApp: App {
    let container: ModelContainer
    @State private var sync: PhoneSyncCoordinator

    init() {
        do {
            container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self)
        } catch {
            // Container creation fails on schema problems (a non-defaulted
            // property under CloudKit, a bad migration). Surface the reason
            // rather than crashing opaquely on `try!`.
            fatalError("Failed to create ModelContainer: \(error)")
        }
        try? DefaultTemplates.seedIfNeeded(context: container.mainContext)
        try? DefaultTemplateMigration.runIfNeeded(context: container.mainContext)
        // Runs after seeding so a fresh install's templates are present, and
        // unconditionally because it is self-healing — it acts only on ids that
        // are genuinely duplicated.
        DuplicateTemplateIdentityRepair.repair(context: container.mainContext)
        // Must run before any importer can execute: `SessionImporter` fetches
        // a session by id, and a store with duplicated session ids would let
        // the first arriving checkpoint overwrite an arbitrary old workout.
        DuplicateSessionIdentityRepair.repair(context: container.mainContext)
        // Built last: it activates `WCSession` immediately and its first act
        // on activation is to push context read from this container, so every
        // seed, migration and repair above must already have run.
        _sync = State(initialValue: PhoneSyncCoordinator(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(sync)
        }
        .modelContainer(container)
    }
}
