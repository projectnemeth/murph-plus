// MurphPlusTests/WatchSyncEmissionTests.swift
import XCTest
@testable import MurphPlus

/// Records what the controller pushed onto each of the three channels.
@MainActor
final class FakeSessionTransport: SessionTransport {
    var isReachable = true
    private(set) var liveEvents: [(UUID, SessionEvent)] = []
    private(set) var checkpoints: [SyncPayload] = []
    private(set) var contexts: [SyncContext] = []

    var onLiveEvent: ((UUID, SessionEvent) -> Void)?
    var onCheckpoint: ((SyncPayload) -> Void)?
    var onContext: ((SyncContext) -> Void)?

    func sendLive(_ event: SessionEvent, sessionID: UUID) {
        liveEvents.append((sessionID, event))
    }
    func transferCheckpoint(_ payload: SyncPayload) { checkpoints.append(payload) }
    func updateContext(_ context: SyncContext) { contexts.append(context) }
}

@MainActor
final class WatchSyncEmissionTests: XCTestCase {
    private var directory: URL!
    private var transport: FakeSessionTransport!
    private var workout: FakeWorkoutController!
    private var controller: WatchSessionController!

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private var spec: TemplateSpec {
        TemplateSpec(
            id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
            totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 20
        )
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-sync-emission-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        transport = FakeSessionTransport()
        workout = FakeWorkoutController()
        controller = WatchSessionController(
            workout: workout,
            journalDirectory: directory,
            transport: transport
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func start() async {
        await controller.startSession(template: spec, vestOn: false, vestWeightLbs: nil, indoor: false)
    }

    func test_startingASessionEmitsALiveEventAndACheckpoint() async throws {
        await start()

        XCTAssertEqual(transport.liveEvents.count, 1)
        XCTAssertEqual(transport.checkpoints.count, 1)
        XCTAssertEqual(transport.checkpoints.first?.origin, .watch)
    }

    /// Task 1's merge rule is strictly-greater, so a first checkpoint of 0
    /// against an unseen session would be dropped and the session would never
    /// land on the phone.
    func test_theFirstCheckpointSequenceIsOneNotZero() async throws {
        await start()

        XCTAssertEqual(transport.checkpoints.first?.checkpointSeq, 1)
    }

    func test_eachNonHeartRateEventAdvancesTheSequence() async throws {
        await start()
        controller.advance()   // finishes run 1
        controller.advance()   // logs round 1

        XCTAssertEqual(transport.checkpoints.map(\.checkpointSeq), [1, 2, 3])
    }

    /// ~700 heart-rate events per session; checkpointing each would swamp the
    /// transfer queue. They still mirror live.
    func test_heartRateMirrorsLiveButDoesNotCheckpoint() async throws {
        await start()
        let checkpointsAfterStart = transport.checkpoints.count
        let liveAfterStart = transport.liveEvents.count

        workout.onHeartRate?(142)

        XCTAssertEqual(transport.checkpoints.count, checkpointsAfterStart, "No checkpoint for heart rate")
        XCTAssertEqual(transport.liveEvents.count, liveAfterStart + 1, "But it still mirrors")
    }

    /// Fix round 1, Important: a checkpoint sent after a failed append would
    /// carry `journal.events` *without* the event that failed to append — a
    /// payload identical to the previous checkpoint, burning a sequence
    /// number for nothing, and one that would throw off
    /// `resumeExistingSession`'s replay-derived count (Task 1's fix), which
    /// assumes every non-heart-rate event still in the journal produced
    /// exactly one checkpoint. So a failed append must not checkpoint at
    /// all, even though the live mirror and `state` are unaffected by the
    /// durability gap.
    func test_aFailedAppendDoesNotCheckpointButStateAndLiveMirrorStillAdvance() async throws {
        await start()
        controller.advance()   // finishes run 1

        let checkpointsBefore = transport.checkpoints.count
        let lastSeqBefore = try XCTUnwrap(transport.checkpoints.last).checkpointSeq
        let liveBefore = transport.liveEvents.count

        // Delete the journal file out from under the live session so the
        // next append throws.
        let url = try XCTUnwrap(controller.journal).url
        try FileManager.default.removeItem(at: url)

        controller.advance()   // logs round 1; the append fails

        XCTAssertTrue(controller.journalWriteFailed)
        XCTAssertEqual(controller.state.completedRounds, 1, "The tap still counts even though the write failed")
        XCTAssertEqual(transport.liveEvents.count, liveBefore + 1, "The live mirror is unaffected by durability")

        XCTAssertEqual(transport.checkpoints.count, checkpointsBefore, "A failed append must not checkpoint")
        XCTAssertEqual(transport.checkpoints.last?.checkpointSeq, lastSeqBefore)

        // The property `resumeExistingSession` depends on: the sequence still
        // matches exactly how many non-heart-rate events actually survived to
        // the journal, because the failed one was never appended to it.
        let survivingCount = try XCTUnwrap(controller.journal).events.filter { !$0.isHeartRate }.count
        XCTAssertEqual(transport.checkpoints.last?.checkpointSeq, survivingCount)
    }

    func test_theCheckpointCarriesTheWholeJournalNotADelta() async throws {
        await start()
        controller.advance()

        let last = try XCTUnwrap(transport.checkpoints.last)
        XCTAssertEqual(last.events.count, 2, "started + runFinished, not just the newest")
    }

    func test_everyChannelUsesTheJournalsSessionID() async throws {
        await start()
        let journalID = try XCTUnwrap(controller.journal?.sessionID)

        XCTAssertEqual(transport.liveEvents.first?.0, journalID)
        XCTAssertEqual(transport.checkpoints.first?.sessionID, journalID)
    }

    /// A relaunch mid-session rebuilds the controller, but the phone still holds
    /// the checkpoint sequence from before the crash. Restarting the count at 1
    /// makes every post-resume checkpoint fail the strictly-greater merge rule,
    /// so the second half of the workout — and the event that marks it complete —
    /// never lands.
    ///
    /// The pre-crash journal deliberately carries heart-rate events too. They
    /// are checkpointed by nobody, so `checkpointSequence(for:)` must filter
    /// them out before counting; without them in the journal that filter is
    /// verified only by inspection, and it is load-bearing — an unfiltered
    /// count would leap the sequence far ahead of what the phone was ever sent.
    func test_resumingContinuesTheCheckpointSequenceRatherThanRestartingIt() async throws {
        await start()
        workout.onHeartRate?(138)                  // journalled, never checkpointed
        controller.advance()                       // finishes run 1
        workout.onHeartRate?(151)
        workout.onHeartRate?(154)
        controller.advance()                       // logs round 1
        let beforeCrash = try XCTUnwrap(transport.checkpoints.last).checkpointSeq
        XCTAssertEqual(beforeCrash, 3)
        XCTAssertEqual(
            try XCTUnwrap(controller.journal).events.count, 6,
            "Three heart-rate events really are in the journal the resume replays"
        )

        // A relaunch: brand-new controller and transport over the same journal.
        let resumedTransport = FakeSessionTransport()
        let resumed = WatchSessionController(
            workout: FakeWorkoutController(),
            journalDirectory: directory,
            transport: resumedTransport
        )
        let didResume = try await resumed.resumeExistingSession()
        XCTAssertTrue(didResume, "The journal on disk must be resumable")

        resumed.advance()                          // logs round 2

        let afterResume = try XCTUnwrap(resumedTransport.checkpoints.last).checkpointSeq
        XCTAssertGreaterThan(
            afterResume, beforeCrash,
            "A post-resume checkpoint must outrank the last one the phone stored"
        )
    }

    /// The app holds exactly ONE long-lived controller (`MurphPlusWatchApp`
    /// keeps it in `@State`), so a second workout in the same launch runs on
    /// the very object that ran the first. Every other relaunch test here
    /// builds a fresh controller and so cannot see this.
    ///
    /// If `checkpointSeq` survived `finishAndReset()`, session B would emit
    /// sequence numbers continuing A's, while a post-crash resume derives them
    /// from B's own journal — a number far below what the phone stored. Every
    /// remaining checkpoint, the terminal one included, would then fail
    /// `SessionMerge`'s strictly-greater test, leaving B `.inProgress` on the
    /// phone forever and so filtered out of history entirely.
    func test_aSecondSessionInTheSameLaunchStartsAFreshSequenceSpace() async throws {
        // Session A, on the shared controller, run far enough to climb.
        await start()
        controller.advance()                       // finishes run 1
        controller.advance()                       // logs round 1
        controller.advance()                       // logs round 2
        controller.abandon()
        controller.finishAndReset()

        // Session B, on that SAME controller — the app's real object lifetime.
        await start()
        controller.advance()                       // finishes run 1
        let sessionB = try XCTUnwrap(controller.journal?.sessionID)
        let lastSeqB = try XCTUnwrap(transport.checkpoints.last).checkpointSeq

        // A relaunch mid-B: brand-new controller over the same directory.
        let resumedTransport = FakeSessionTransport()
        let resumed = WatchSessionController(
            workout: FakeWorkoutController(),
            journalDirectory: directory,
            transport: resumedTransport
        )
        let didResume = try await resumed.resumeExistingSession()
        XCTAssertTrue(didResume, "B's journal must be the resumable one")
        XCTAssertEqual(resumed.journal?.sessionID, sessionB, "A was abandoned, so B is what resumes")

        resumed.advance()                          // logs round 1

        let afterResume = try XCTUnwrap(resumedTransport.checkpoints.last).checkpointSeq
        XCTAssertGreaterThan(
            afterResume, lastSeqB,
            "A post-resume checkpoint must outrank the last one the phone stored for B"
        )
    }

    /// Discarding a recovered session must tell the phone. The phone already
    /// holds checkpoints for it, so without a final checkpoint it keeps the
    /// session `.inProgress` forever — hidden from history and (before the
    /// reaper) unreachable.
    func test_abandoningARecoveredSessionSendsAFinalCheckpoint() async throws {
        await start()
        controller.advance()
        let sessionID = try XCTUnwrap(controller.journal?.sessionID)

        let relaunchTransport = FakeSessionTransport()
        let relaunched = WatchSessionController(
            workout: FakeWorkoutController(),
            journalDirectory: directory,
            transport: relaunchTransport
        )
        relaunched.abandonResumableSession()

        let final = try XCTUnwrap(relaunchTransport.checkpoints.last)
        XCTAssertEqual(final.sessionID, sessionID)
        XCTAssertTrue(
            SessionState.replay(final.events).isTerminal,
            "The phone must be told the session ended"
        )
    }

    /// The transport is optional: the 13 Stage 2 tests construct the
    /// controller without one, and nothing may crash when it is absent.
    func test_aControllerWithNoTransportStillRunsTheSession() async throws {
        let solo = WatchSessionController(
            workout: FakeWorkoutController(), journalDirectory: directory
        )

        await solo.startSession(template: spec, vestOn: false, vestWeightLbs: nil, indoor: false)
        solo.advance()
        solo.advance()

        XCTAssertEqual(solo.state.completedRounds, 1)
    }
}
