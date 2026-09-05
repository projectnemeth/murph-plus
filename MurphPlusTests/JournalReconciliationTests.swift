// MurphPlusTests/JournalReconciliationTests.swift
import XCTest
@testable import MurphPlus

/// `WatchSessionController.reconcileJournals` — the resend-and-retain pass.
///
/// Covers roadmap §1 (a finished workout that never reached the phone) and §7
/// (journals accumulating forever), which turned out to be the same feature
/// seen from two ends.
@MainActor
final class JournalReconciliationTests: XCTestCase {
    private var directory: URL!
    private var transport: FakeSessionTransport!
    private var controller: WatchSessionController!

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    private var spec: TemplateSpec {
        TemplateSpec(
            id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
            totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 2
        )
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("journal-reconcile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        transport = FakeSessionTransport()
        controller = WatchSessionController(
            workout: FakeWorkoutController(),
            journalDirectory: directory,
            transport: transport
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A workout written to disk and finished, exactly as one left behind by a
    /// session the phone never received.
    @discardableResult
    private func finishedJournal(
        startedAt: TimeInterval = 0, heartRates: Int = 0
    ) throws -> SessionJournal {
        let journal = try SessionJournal(sessionID: UUID(), directory: directory)
        try journal.append(
            .started(at: t(startedAt), template: spec, vestOn: false, vestWeightLbs: nil, indoor: false)
        )
        for i in 0..<heartRates {
            try journal.append(.heartRate(bpm: 140 + i, at: t(startedAt + 10 + Double(i))))
        }
        try journal.append(.runFinished(index: 1, at: t(startedAt + 500), distanceMeters: 1609))
        try journal.append(.roundCompleted(number: 1, at: t(startedAt + 560)))
        try journal.append(.roundCompleted(number: 2, at: t(startedAt + 620)))
        try journal.append(.runFinished(index: 2, at: t(startedAt + 1100), distanceMeters: 1609))
        return journal
    }

    @discardableResult
    private func unfinishedJournal(startedAt: TimeInterval = 0) throws -> SessionJournal {
        let journal = try SessionJournal(sessionID: UUID(), directory: directory)
        try journal.append(
            .started(at: t(startedAt), template: spec, vestOn: false, vestWeightLbs: nil, indoor: false)
        )
        try journal.append(.runFinished(index: 1, at: t(startedAt + 500), distanceMeters: 1609))
        return journal
    }

    private func journalsOnDisk() throws -> Set<UUID> {
        Set(try SessionJournal.all(in: directory).map(\.sessionID))
    }

    // MARK: - Resending

    /// The §1 case: the workout exists on the Watch and never reached the
    /// phone, and nothing before this would ever have tried again.
    func test_resendsAFinishedJournalThePhoneHasNotAcknowledged() throws {
        let stranded = try finishedJournal()

        controller.reconcileJournals(acknowledged: [])

        XCTAssertEqual(transport.checkpoints.map(\.sessionID), [stranded.sessionID])
        XCTAssertEqual(transport.checkpoints.first?.origin, .watch)
    }

    func test_doesNotResendAnAcknowledgedJournal() throws {
        let delivered = try finishedJournal()
        controller.reconcileJournals(acknowledged: [delivered.sessionID])
        XCTAssertTrue(transport.checkpoints.isEmpty)
    }

    /// The resent checkpoint has to outrank whatever the phone already stored
    /// for this session, or `SessionMerge` drops it and a session stuck
    /// part-way through stays stuck. Heart-rate events never produced a
    /// checkpoint, so they must not be counted.
    func test_theResentSequenceMatchesWhatTheTerminalCheckpointCarried() throws {
        try finishedJournal(heartRates: 12)

        controller.reconcileJournals(acknowledged: [])

        // started + 2 runFinished + 2 roundCompleted = 5 checkpoint-bearing events.
        XCTAssertEqual(transport.checkpoints.first?.checkpointSeq, 5)
    }

    /// An unfinished journal belongs to the launch prompt: resending it would
    /// ship a session whose fate the user has not decided.
    func test_neverResendsAnUnfinishedJournal() throws {
        try unfinishedJournal()
        controller.reconcileJournals(acknowledged: [])
        XCTAssertTrue(transport.checkpoints.isEmpty)
    }

    /// The live session checkpoints as it goes and is still being appended to.
    func test_neverTouchesTheSessionThisControllerIsRunning() async throws {
        await controller.startSession(template: spec, vestOn: false, vestWeightLbs: nil, indoor: false)
        let live = try XCTUnwrap(controller.journal).sessionID
        transport.reset()

        // Even if the phone somehow acknowledged it, it must survive.
        controller.reconcileJournals(acknowledged: [live])

        XCTAssertTrue(transport.checkpoints.isEmpty)
        XCTAssertTrue(try journalsOnDisk().contains(live))
    }

    func test_resendsOldestFirstAndCapsTheBatch() throws {
        // One more than the limit, so the cap is what decides, not the count.
        let all = try (0...WatchSessionController.resendBatchLimit).map {
            try finishedJournal(startedAt: Double($0) * 10_000)
        }

        controller.reconcileJournals(acknowledged: [])

        XCTAssertEqual(transport.checkpoints.count, WatchSessionController.resendBatchLimit)
        XCTAssertEqual(
            transport.checkpoints.map(\.sessionID),
            all.prefix(WatchSessionController.resendBatchLimit).map(\.sessionID),
            "Oldest first — the longest-stuck workout is the most at risk"
        )
    }

    // MARK: - Retention

    /// §7: journals accumulated forever because nothing could say when one was
    /// safe to remove. An acknowledgement can.
    func test_deletesAJournalThePhoneHasAcknowledged() throws {
        let delivered = try finishedJournal()
        controller.reconcileJournals(acknowledged: [delivered.sessionID])
        XCTAssertFalse(try journalsOnDisk().contains(delivered.sessionID))
    }

    func test_keepsAJournalThePhoneHasNotAcknowledged() throws {
        let stranded = try finishedJournal()
        controller.reconcileJournals(acknowledged: [])
        XCTAssertTrue(try journalsOnDisk().contains(stranded.sessionID))
    }

    /// The dangerous direction: an unfinished journal that somehow appears in
    /// the acknowledgement list must not be deleted out from under the resume
    /// prompt... except that it *should* be, because the phone only
    /// acknowledges terminal sessions — so if it names this one, that session
    /// is finished as far as the system of record is concerned and the Watch's
    /// copy is the stale one.
    func test_deletesAnAcknowledgedJournalEvenIfTheWatchThinksItUnfinished() throws {
        let stale = try unfinishedJournal()
        controller.reconcileJournals(acknowledged: [stale.sessionID])
        XCTAssertFalse(try journalsOnDisk().contains(stale.sessionID))
    }

    func test_leavesEverythingAloneWhenThereIsNothingToDo() throws {
        controller.reconcileJournals(acknowledged: [])
        XCTAssertTrue(transport.checkpoints.isEmpty)
        XCTAssertTrue(try journalsOnDisk().isEmpty)
    }

    // MARK: - Mixed

    func test_deletesTheAcknowledgedAndResendsTheRestInOnePass() throws {
        let delivered = try finishedJournal(startedAt: 0)
        let stranded = try finishedJournal(startedAt: 10_000)

        controller.reconcileJournals(acknowledged: [delivered.sessionID])

        XCTAssertEqual(transport.checkpoints.map(\.sessionID), [stranded.sessionID])
        XCTAssertEqual(try journalsOnDisk(), [stranded.sessionID])
    }
}
