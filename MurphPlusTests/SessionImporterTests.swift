// MurphPlusTests/SessionImporterTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

/// `@MainActor` so the container's `mainContext` can be reached — see
/// `setUpWithError`.
@MainActor
final class SessionImporterTests: XCTestCase {

    var context: ModelContext!
    /// Held, not local: `mainContext` is owned by the container, so a container
    /// that goes out of scope at the end of `setUpWithError` takes the context
    /// with it and every test crashes on a dangling reference. The old
    /// `ModelContext(container)` retained it for us and hid this.
    private var container: ModelContainer!
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self,
            configurations: config
        )
        // `container.mainContext`, matching what ships. `PhoneSyncCoordinator`
        // deliberately imports into the main context so received sessions reach
        // the `@Query`-backed History screen without a cross-context merge; a
        // test against a freshly constructed `ModelContext` was exercising a
        // flavour of `apply` that no longer runs in the app — including the
        // autosave behaviour, which differs between the two.
        context = container.mainContext
    }

    private func spec(rounds: Int = 3, id: UUID = UUID()) -> TemplateSpec {
        TemplateSpec(id: id, name: "Full Murph", runDistanceMiles: 1.0,
                     totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: rounds)
    }

    private func events(_ spec: TemplateSpec, rounds: Int, finished: Bool) -> [SessionEvent] {
        var out: [SessionEvent] = [
            .started(at: t(0), template: spec, vestOn: true, vestWeightLbs: 20, indoor: false),
            .runFinished(index: 1, at: t(500), distanceMeters: 1609.34),
        ]
        for i in 1...rounds {
            out.append(.heartRate(bpm: 150 + i, at: t(500 + Double(i) * 60 - 10)))
            out.append(.roundCompleted(number: i, at: t(500 + Double(i) * 60)))
        }
        if finished {
            out.append(.runFinished(index: 2, at: t(2000), distanceMeters: 1609.34))
        }
        return out
    }

    private func payload(_ spec: TemplateSpec, seq: Int, rounds: Int, finished: Bool,
                         id: UUID = UUID()) -> SyncPayload {
        SyncPayload(sessionID: id, checkpointSeq: seq, origin: .watch,
                    events: events(spec, rounds: rounds, finished: finished))
    }

    private func allSessions() throws -> [MurphSession] {
        try context.fetch(FetchDescriptor<MurphSession>())
    }

    func test_createsASessionFromATerminalPayload() throws {
        let s = spec()
        let session = try XCTUnwrap(
            SessionImporter.apply(payload(s, seq: 4, rounds: 3, finished: true), context: context)
        )

        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.completedRounds, 3)
        XCTAssertEqual(session.runSplits.count, 2)
        XCTAssertEqual(session.roundLogs.count, 3)
        XCTAssertEqual(session.origin, .watch)
        XCTAssertTrue(session.vestOn)
        XCTAssertEqual(session.vestWeightLbs, 20)
    }

    func test_duplicateDeliveryDoesNotCreateASecondSession() throws {
        let s = spec()
        let p = payload(s, seq: 4, rounds: 3, finished: true)

        _ = try SessionImporter.apply(p, context: context)
        let second = try SessionImporter.apply(p, context: context)

        XCTAssertNil(second, "A stale or duplicate checkpoint is ignored")
        XCTAssertEqual(try allSessions().count, 1)
    }

    func test_aLaterCheckpointReplacesTheEarlierOne() throws {
        let s = spec()
        let id = UUID()

        _ = try SessionImporter.apply(payload(s, seq: 2, rounds: 1, finished: false, id: id), context: context)
        _ = try SessionImporter.apply(payload(s, seq: 5, rounds: 3, finished: true, id: id), context: context)

        let sessions = try allSessions()
        XCTAssertEqual(sessions.count, 1, "Same session ID must not duplicate")
        XCTAssertEqual(sessions[0].completedRounds, 3)
        XCTAssertEqual(sessions[0].roundLogs.count, 3, "Round logs are replaced wholesale, not appended")
        XCTAssertEqual(sessions[0].status, .completed)
    }

    func test_anEarlierCheckpointArrivingLateIsIgnored() throws {
        let s = spec()
        let id = UUID()

        _ = try SessionImporter.apply(payload(s, seq: 5, rounds: 3, finished: true, id: id), context: context)
        let late = try SessionImporter.apply(payload(s, seq: 2, rounds: 1, finished: false, id: id), context: context)

        XCTAssertNil(late)
        XCTAssertEqual(try allSessions()[0].completedRounds, 3, "Must not rewind to fewer rounds")
    }

    func test_linksToAnExistingTemplateByID() throws {
        let template = WorkoutTemplate(name: "Full Murph", rounds: 3)
        context.insert(template)
        try context.save()

        let session = try XCTUnwrap(
            SessionImporter.apply(payload(template.spec, seq: 1, rounds: 3, finished: true), context: context)
        )

        XCTAssertEqual(session.template?.id, template.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutTemplate>()).count, 1)
    }

    func test_reconstructsATemplateWhenTheIDIsUnknown() throws {
        // The template was deleted on the phone after the workout started.
        // History must never lose what the workout actually was.
        let s = spec()

        let session = try XCTUnwrap(
            SessionImporter.apply(payload(s, seq: 1, rounds: 3, finished: true), context: context)
        )

        let template = try XCTUnwrap(session.template)
        XCTAssertEqual(template.id, s.id)
        XCTAssertEqual(template.rounds, 3)
        XCTAssertEqual(template.totalPullUps, 100)
    }

    func test_storesHeartRateSummariesOnRoundsAndRuns() throws {
        let s = spec()
        let session = try XCTUnwrap(
            SessionImporter.apply(payload(s, seq: 1, rounds: 3, finished: true), context: context)
        )

        let firstRound = try XCTUnwrap(session.roundLogs.first { $0.roundNumber == 1 })
        XCTAssertEqual(firstRound.avgHeartRate, 151)
        XCTAssertEqual(firstRound.maxHeartRate, 151)
    }

    func test_storesRunDistance() throws {
        let s = spec()
        let session = try XCTUnwrap(
            SessionImporter.apply(payload(s, seq: 1, rounds: 3, finished: true), context: context)
        )

        let run1 = try XCTUnwrap(session.runSplits.first { $0.runIndex == 1 })
        XCTAssertEqual(try XCTUnwrap(run1.distanceMeters), 1609.34, accuracy: 0.01)
    }

    func test_storedJournalHasNoHeartRateEvents() throws {
        let s = spec()
        let session = try XCTUnwrap(
            SessionImporter.apply(payload(s, seq: 1, rounds: 3, finished: true), context: context)
        )

        let data = try XCTUnwrap(session.journalData)
        let stored = try JSONDecoder().decode([SessionEvent].self, from: data)
        XCTAssertFalse(stored.contains { $0.isHeartRate })
        XCTAssertEqual(SessionState.replay(stored).completedRounds, 3)
    }

    func test_anUnfinishedPayloadLandsAsInProgress() throws {
        let s = spec()
        let session = try XCTUnwrap(
            SessionImporter.apply(payload(s, seq: 2, rounds: 1, finished: false), context: context)
        )

        XCTAssertEqual(session.status, .inProgress)
        XCTAssertEqual(session.completedRounds, 1)
    }

    func test_twoDifferentSessionIDsBothSurvive() throws {
        // The simultaneous-start race: two sessions, both kept, never merged.
        let s = spec()
        _ = try SessionImporter.apply(payload(s, seq: 1, rounds: 3, finished: true), context: context)
        _ = try SessionImporter.apply(payload(s, seq: 1, rounds: 3, finished: true), context: context)

        XCTAssertEqual(try allSessions().count, 2)
    }

    /// The Watch's built-in starters carry ids the phone has never seen when no
    /// context has synced yet. Rebuilding one must not add a second copy of a
    /// template the phone already has under a different id — that copy shows up
    /// in the Start picker, once per Watch relaunch.
    func test_doesNotDuplicateATemplateThePhoneAlreadyHasByShape() throws {
        let existing = WorkoutTemplate(name: "Half Murph", runDistanceMiles: 0.5,
                                       totalPullUps: 50, totalPushUps: 100,
                                       totalSquats: 150, rounds: 10)
        context.insert(existing)
        try context.save()

        let unknownID = TemplateSpec(id: UUID(), name: "Half Murph", runDistanceMiles: 0.5,
                                     totalPullUps: 50, totalPushUps: 100,
                                     totalSquats: 150, rounds: 10)
        try SessionImporter.apply(payload(unknownID, seq: 1, rounds: 10, finished: true), context: context)

        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        XCTAssertEqual(templates.count, 1, "Matched the existing template by shape")
    }

    /// But a genuinely different workout must still be reconstructed.
    func test_stillRebuildsATemplateWhoseShapeIsNew() throws {
        let existing = WorkoutTemplate(name: "Half Murph", runDistanceMiles: 0.5,
                                       totalPullUps: 50, totalPushUps: 100,
                                       totalSquats: 150, rounds: 10)
        context.insert(existing)
        try context.save()

        let different = TemplateSpec(id: UUID(), name: "Quarter Murph", runDistanceMiles: 0.25,
                                     totalPullUps: 25, totalPushUps: 50,
                                     totalSquats: 75, rounds: 5)
        try SessionImporter.apply(payload(different, seq: 1, rounds: 5, finished: true), context: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutTemplate>()).count, 2)
    }
}
