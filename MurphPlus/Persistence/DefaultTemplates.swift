import SwiftData

enum DefaultTemplates {
    static func seedIfNeeded(context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        guard existing.isEmpty else { return }

        let straightSets = WorkoutTemplate(name: "Full Murph (Straight Sets)", rounds: 1)
        let cindyStyle = WorkoutTemplate(name: "Full Murph (Cindy-Style, 20 Rounds)", rounds: 20)
        context.insert(straightSets)
        context.insert(cindyStyle)
        try context.save()
    }
}
