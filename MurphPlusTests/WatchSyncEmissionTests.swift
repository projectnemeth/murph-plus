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
    func test_resumingContinuesTheCheckpointSequenceRatherThanRestartingIt() async throws {
        await start()
        controller.advance()                       // finishes run 1
        controller.advance()                       // logs round 1
        let beforeCrash = try XCTUnwrap(transport.checkpoints.last).checkpointSeq
        XCTAssertEqual(beforeCrash, 3)

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
