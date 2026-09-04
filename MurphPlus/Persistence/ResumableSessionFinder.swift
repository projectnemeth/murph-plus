// MurphPlus/Persistence/ResumableSessionFinder.swift
import Foundation
import SwiftData

enum ResumableSessionFinder {
    static func findInProgress(context: ModelContext) -> MurphSession? {
        // Captured in a local so the predicate tracks the enum rather than a
        // hardcoded string that would silently stop matching if a case is renamed.
        let inProgressRaw = SessionStatus.inProgress.rawValue
        // Both captured in locals so the predicate tracks the enums rather
        // than hardcoded strings that would silently stop matching on rename.
        let phoneRaw = SessionOrigin.phone.rawValue
        let descriptor = FetchDescriptor<MurphSession>(
            predicate: #Predicate { $0.statusRaw == inProgressRaw && $0.originRaw == phoneRaw },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        // Two exclusions, for different reasons:
        //
        // `originRaw == phone` keeps a Watch-owned session out. Its journal
        // lives on the Watch, which is the session's single writer; the phone
        // resuming it would fork one session across two writers, which is the
        // one conflict this design refuses to resolve. When a Watch dies
        // mid-session the phone's answer is abandon, never resume.
        //
        // `startedAt != nil` excludes sessions that were created at the setup
        // screen but never started — prompting to "resume" one of those would
        // be confusing, since there is nothing to resume.
        return (try? context.fetch(descriptor))?.first { $0.startedAt != nil }
    }
}
