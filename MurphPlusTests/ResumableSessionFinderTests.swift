// MurphPlusTests/ResumableSessionFinderTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

final class ResumableSessionFinderTests: XCTestCase {
    func test_findInProgress_returnsSessionWithInProgressStatus() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)

        let template = WorkoutTemplate(name: "Test")
        context.insert(template)
        let completed = MurphSession(template: template, vestOn: false)
        completed.status = .completed
        context.insert(completed)
        let inProgress = MurphSession(template: template, vestOn: false)
        inProgress.startedAt = .now
        context.insert(inProgress)
        try context.save()

        let found = ResumableSessionFinder.findInProgress(context: context)

        XCTAssertEqual(found?.persistentModelID, inProgress.persistentModelID)
    }

    func test_findInProgress_ignoresSessionThatWasNeverStarted() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)

        let template = WorkoutTemplate(name: "Test")
        context.insert(template)
        let neverStarted = MurphSession(template: template, vestOn: false)
        context.insert(neverStarted)
        try context.save()

        XCTAssertNil(ResumableSessionFinder.findInProgress(context: context))
    }

    func test_findInProgress_returnsNilWhenNoneInProgress() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)

        let template = WorkoutTemplate(name: "Test")
        context.insert(template)
        let completed = MurphSession(template: template, vestOn: false)
        completed.status = .completed
        context.insert(completed)
        try context.save()

        XCTAssertNil(ResumableSessionFinder.findInProgress(context: context))
    }
}
