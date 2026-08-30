import XCTest
import SwiftData
@testable import MurphPlus

final class DefaultTemplatesTests: XCTestCase {
    func test_seedIfNeeded_insertsTwoStarterTemplatesWhenEmpty() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)

        try DefaultTemplates.seedIfNeeded(context: context)

        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        XCTAssertEqual(templates.count, 2)
        XCTAssertTrue(templates.contains { $0.rounds == 1 })
        XCTAssertTrue(templates.contains { $0.rounds == 20 })
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
