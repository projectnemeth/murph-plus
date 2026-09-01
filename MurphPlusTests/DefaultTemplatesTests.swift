import XCTest
import SwiftData
@testable import MurphPlus

final class DefaultTemplatesTests: XCTestCase {
    func test_seedIfNeeded_insertsFourStarterTemplatesWhenEmpty() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)

        try DefaultTemplates.seedIfNeeded(context: context)

        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        XCTAssertEqual(templates.count, 4)

        XCTAssertTrue(templates.contains {
            $0.rounds == 1 && $0.runDistanceMiles == 1.0 && $0.totalPullUps == 100 && $0.totalPushUps == 200 && $0.totalSquats == 300
        }, "Full Murph straight sets")
        XCTAssertTrue(templates.contains {
            $0.rounds == 20 && $0.runDistanceMiles == 1.0 && $0.totalPullUps == 100 && $0.totalPushUps == 200 && $0.totalSquats == 300
        }, "Full Murph Cindy-style")
        XCTAssertTrue(templates.contains {
            $0.rounds == 1 && $0.runDistanceMiles == 0.5 && $0.totalPullUps == 50 && $0.totalPushUps == 100 && $0.totalSquats == 150
        }, "Half Murph — 50% scale on reps and run distance")
        XCTAssertTrue(templates.contains {
            $0.rounds == 1 && $0.runDistanceMiles == 0.25 && $0.totalPullUps == 25 && $0.totalPushUps == 50 && $0.totalSquats == 75
        }, "Mini Murph — 25% scale on reps and run distance")
    }

    func test_seedIfNeeded_doesNothingWhenTemplatesExist() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)
        context.insert(WorkoutTemplate(name: "Custom"))
        try context.save()

        try DefaultTemplates.seedIfNeeded(context: context)

        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        XCTAssertEqual(templates.count, 1)
    }
}
