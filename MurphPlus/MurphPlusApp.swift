// MurphPlus/MurphPlusApp.swift
import SwiftUI
import SwiftData

@main
struct MurphPlusApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self)
        } catch {
            // Container creation fails on schema problems (a non-defaulted
            // property under CloudKit, a bad migration). Surface the reason
            // rather than crashing opaquely on `try!`.
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Text("Murph Plus")
        }
        .modelContainer(container)
    }
}
