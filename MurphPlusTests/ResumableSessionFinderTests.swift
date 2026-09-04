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
    /// Stage 3: a Watch-owned session must never be offered for resume on the
    /// phone. Its journal lives on the Watch, which is the single writer — the
    /// phone resuming it would fork the session between two writers, which is
    /// the one conflict this design refuses to resolve. The spec's answer to a
    /// dead Watch is abandon, never resume.
    func test_findInProgress_ignoresASessionOwnedByTheWatch() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)

        let template = WorkoutTemplate(name: "Test")
        context.insert(template)
        let fromWatch = MurphSession(template: template, vestOn: false)
        fromWatch.startedAt = .now
        fromWatch.origin = .watch
        context.insert(fromWatch)
        try context.save()

        XCTAssertNil(ResumableSessionFinder.findInProgress(context: context))
    }

    func test_findInProgress_stillReturnsAPhoneOwnedSession() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)

        let template = WorkoutTemplate(name: "Test")
        context.insert(template)
        let fromWatch = MurphSession(template: template, vestOn: false)
        fromWatch.startedAt = .now
        fromWatch.origin = .watch
        context.insert(fromWatch)
        let onPhone = MurphSession(template: template, vestOn: false)
        onPhone.startedAt = .now
        context.insert(onPhone)
        try context.save()

        let found = ResumableSessionFinder.findInProgress(context: context)

        XCTAssertEqual(found?.persistentModelID, onPhone.persistentModelID,
                       "The Watch session must be skipped, not merely outranked")
    }
}
