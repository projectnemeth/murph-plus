// MurphPlusTests/SessionJournalTests.swift
import XCTest
@testable import MurphPlus

final class SessionJournalTests: XCTestCase {

    private var directory: URL!
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    private let spec = TemplateSpec(
        id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
        totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 3
    )

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("journal-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var startedEvent: SessionEvent {
        .started(at: t(0), template: spec, vestOn: false, vestWeightLbs: nil, indoor: false)
    }

    func test_appendedEventsSurviveReopening() throws {
        let id = UUID()
        let journal = try SessionJournal(sessionID: id, directory: directory)
        try journal.append(startedEvent)
        try journal.append(.runFinished(index: 1, at: t(500), distanceMeters: 1609.34))

        // A fresh instance simulates a crash and relaunch.
        let reopened = try SessionJournal(sessionID: id, directory: directory)

        XCTAssertEqual(reopened.events.count, 2)
        XCTAssertEqual(reopened.state.phase, .rounds)
        XCTAssertEqual(reopened.state.runSplits.first?.distanceMeters, 1609.34)
    }

    func test_stateIsRebuiltByReplay() throws {
        let journal = try SessionJournal(sessionID: UUID(), directory: directory)
        try journal.append(startedEvent)
        try journal.append(.runFinished(index: 1, at: t(500), distanceMeters: nil))
        try journal.append(.roundCompleted(number: 1, at: t(560)))

        XCTAssertEqual(journal.state.completedRounds, 1)
        XCTAssertEqual(journal.state.phase, .rounds)
    }

    func test_resumableFindsAnUnfinishedSession() throws {
        let journal = try SessionJournal(sessionID: UUID(), directory: directory)
        try journal.append(startedEvent)
        try journal.append(.roundCompleted(number: 1, at: t(560)))

        let found = try XCTUnwrap(SessionJournal.resumable(in: directory))

        XCTAssertEqual(found.sessionID, journal.sessionID)
    }

    func test_resumableIgnoresACompletedSession() throws {
        let journal = try SessionJournal(sessionID: UUID(), directory: directory)
        try journal.append(startedEvent)
        try journal.append(.runFinished(index: 1, at: t(100), distanceMeters: nil))
        try journal.append(.roundCompleted(number: 1, at: t(200)))
        try journal.append(.roundCompleted(number: 2, at: t(300)))
        try journal.append(.roundCompleted(number: 3, at: t(400)))
        try journal.append(.runFinished(index: 2, at: t(500), distanceMeters: nil))

        XCTAssertNil(try SessionJournal.resumable(in: directory))
    }

    func test_resumableIgnoresAnAbandonedSession() throws {
        let journal = try SessionJournal(sessionID: UUID(), directory: directory)
        try journal.append(startedEvent)
        try journal.append(.abandoned(at: t(100)))

        XCTAssertNil(try SessionJournal.resumable(in: directory))
    }

    func test_deleteRemovesTheFile() throws {
        let id = UUID()
        let journal = try SessionJournal(sessionID: id, directory: directory)
        try journal.append(startedEvent)

        try journal.delete()

        XCTAssertTrue(try SessionJournal.all(in: directory).isEmpty)
    }

    func test_aHighVolumeOfHeartRateEventsReplaysCorrectly() throws {
        // A long Murph journals ~700 heart-rate events; replay must stay correct
        // and the file must stay well-formed with that many lines.
        let journal = try SessionJournal(sessionID: UUID(), directory: directory)
        try journal.append(startedEvent)
        for i in 0..<700 {
            try journal.append(.heartRate(bpm: 140 + (i % 20), at: t(Double(i) * 5)))
        }

        let reopened = try SessionJournal(sessionID: journal.sessionID, directory: directory)

        XCTAssertEqual(reopened.events.count, 701)
        XCTAssertEqual(reopened.state.latestHeartRate, 140 + (699 % 20))
    }

    func test_anEmptyDirectoryHasNothingToResume() throws {
        XCTAssertNil(try SessionJournal.resumable(in: directory))
        XCTAssertTrue(try SessionJournal.all(in: directory).isEmpty)
    }
}
