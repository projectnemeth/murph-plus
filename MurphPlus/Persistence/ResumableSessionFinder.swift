// MurphPlus/Persistence/ResumableSessionFinder.swift
import Foundation
import SwiftData

enum ResumableSessionFinder {
    static func findInProgress(context: ModelContext) -> MurphSession? {
        // Captured in a local so the predicate tracks the enum rather than a
        // hardcoded string that would silently stop matching if a case is renamed.
        let inProgressRaw = SessionStatus.inProgress.rawValue
        let descriptor = FetchDescriptor<MurphSession>(
            predicate: #Predicate { $0.statusRaw == inProgressRaw },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        // `startedAt != nil` excludes sessions that were created at the setup
        // screen but never started — prompting to "resume" one of those would
        // be confusing, since there is nothing to resume.
        return (try? context.fetch(descriptor))?.first { $0.startedAt != nil }
    }
}
