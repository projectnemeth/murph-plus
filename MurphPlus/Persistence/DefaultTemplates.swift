import SwiftData

enum DefaultTemplates {
    static func seedIfNeeded(context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        guard existing.isEmpty else { return }

        let straightSets = WorkoutTemplate(name: "Full Murph (Straight Sets)", rounds: 1)
        let cindyStyle = WorkoutTemplate(name: "Full Murph (Cindy-Style, 20 Rounds)", rounds: 20)
        let halfMurph = WorkoutTemplate(
            name: "Half Murph",
            runDistanceMiles: 0.5,
            totalPullUps: 50,
            totalPushUps: 100,
            totalSquats: 150,
            rounds: 1
        )
        let miniMurph = WorkoutTemplate(
            name: "Mini Murph",
            runDistanceMiles: 0.25,
            totalPullUps: 25,
            totalPushUps: 50,
            totalSquats: 75,
            rounds: 1
        )
        context.insert(straightSets)
        context.insert(cindyStyle)
        context.insert(halfMurph)
        context.insert(miniMurph)
        try context.save()
    }
}
