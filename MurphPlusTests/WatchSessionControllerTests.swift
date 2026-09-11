// MurphPlusTests/WatchSessionControllerTests.swift
import XCTest
@testable import MurphPlus

/// A `WorkoutControlling` that records what it was asked to do.
///
/// This is the whole point of the protocol: `WatchSessionController`'s
/// contract with HealthKit is a *sequence of calls* — segment the run, pause,
/// finish — and only a recording double can assert on it. The real controller
/// needs a watch on a wrist.
@MainActor
final class FakeWorkoutController: WorkoutControlling {
    enum Call: Equatable {
        case requestAuthorization
        case start(indoor: Bool)
        case recover(indoor: Bool)
        case beginRun(resetDistanceBaseline: Bool)
        case beginRounds
        case pause
        case resume
        case finish
    }

    private(set) var calls: [Call] = []
    /// What `recover(indoor:)` reports: `true` for the relaunch path that
    /// reattaches to a live session, `false` for the fresh-start fallback.
    var recoverSucceeds = true

    var currentHeartRate: Int?
    var currentRunDistanceMeters: Double?
    var onHeartRate: ((Int) -> Void)?

    func requestAuthorization() async { calls.append(.requestAuthorization) }
    func start(indoor: Bool) async { calls.append(.start(indoor: indoor)) }

    func recover(indoor: Bool) async -> Bool {
        calls.append(.recover(indoor: indoor))
        return recoverSucceeds
    }

    func beginRunActivity(resetDistanceBaseline: Bool) {
        calls.append(.beginRun(resetDistanceBaseline: resetDistanceBaseline))
    }

    func beginRoundsActivity() { calls.append(.beginRounds) }
    func pause() { calls.append(.pause) }
    func resume() { calls.append(.resume) }
    func finish() async { calls.append(.finish) }
}

/// A `LocationProviding` that records what it was asked to do.
///
/// Same reasoning as `FakeWorkoutController`: the contract under test is a
/// *sequence of calls* — warm for the run, stop for the rounds, warm again
/// before run 2 — and only a recording double can assert on it.
@MainActor
final class FakeLocationController: LocationProviding, RunDistanceMeasuring {
    enum Call: Equatable {
        case requestAuthorization
        case start
        case stop
        case beginRun
        case resumeRun
        case stopMeasuring
    }

    private(set) var calls: [Call] = []
    var fixState: GPSFixState = .off

    /// Settable so a test can stage the distance the engine should capture.
    var runDistanceMeters: Double?

    /// Only the receiver transitions, with repeats collapsed. `startUpdating`
    /// is idempotent by contract and is called after every event, so the raw
    /// list is mostly noise; this is the shape a test actually cares about.
    ///
    /// Measurement calls are filtered out too: they are a separate concern on
    /// a separate clock, asserted directly against `calls` by the phone tests.
    var transitions: [Call] {
        calls.filter { $0 == .start || $0 == .stop }.reduce(into: []) { out, call in
            if out.last != call { out.append(call) }
        }
    }

    /// Only the measurement-window calls, so an assertion about measuring is
    /// not perturbed by the idempotent receiver calls `reconcileLocation`
    /// issues after every event. The counterpart of `transitions`.
    var measurements: [Call] {
        calls.filter { $0 == .beginRun || $0 == .resumeRun || $0 == .stopMeasuring }
    }

    func requestAuthorization() async { calls.append(.requestAuthorization) }
    func startUpdating() { calls.append(.start) }
    func stopUpdating() { calls.append(.stop) }

    // Recording only. `beginRun` deliberately does NOT zero
    // `runDistanceMeters`: a double that mimics the real controller's reset
    // would let a later test assert `runDistanceMeters == 0` and pass because
    // the FAKE reset itself, not because the code under test asked it to.
    // `calls` is the only evidence of what was invoked; the distance is
    // whatever a test explicitly arranges.
    func beginRun() { calls.append(.beginRun) }
    func resumeRun() { calls.append(.resumeRun) }
    func stopMeasuring() { calls.append(.stopMeasuring) }
}

@MainActor
final class WatchSessionControllerTests: XCTestCase {

    private var directory: URL!
    private var fake: FakeWorkoutController!
    private var gps: FakeLocationController!
    private var controller: WatchSessionController!

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    private func spec(rounds: Int) -> TemplateSpec {
        TemplateSpec(
            id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
            totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: rounds
        )
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-controller-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fake = FakeWorkoutController()
        gps = FakeLocationController()
        controller = WatchSessionController(
            workout: fake, journalDirectory: directory, location: gps
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Event names, so an assertion reads as the journal's shape rather than
    /// a wall of associated values.
    private func names(_ events: [SessionEvent]) -> [String] {
        events.map { event in
            switch event {
            case .started: "started"
            case .runFinished: "runFinished"
            case .roundCompleted: "roundCompleted"
            case .roundUndone: "roundUndone"
            case .paused: "paused"
            case .resumed: "resumed"
            case .heartRate: "heartRate"
            case .abandoned: "abandoned"
            }
        }
    }

    // MARK: - Abandon

    func test_abandoningWhilePausedClosesThePauseFirstAndReplaysIdentically() async throws {
        await controller.startSession(
            template: spec(rounds: 3), vestOn: true, vestWeightLbs: 20, indoor: false
        )
        controller.pause()
        XCTAssertTrue(controller.isPaused)

        controller.abandon()

        let events = try XCTUnwrap(controller.journal).events
        XCTAssertEqual(names(events), ["started", "paused", "resumed", "abandoned"])
        // The journal is the sync payload: replaying it must land exactly
        // where the live session did, with the pause closed rather than open.
        XCTAssertEqual(SessionState.replay(events), controller.state)
        XCTAssertFalse(SessionState.replay(events).isPaused)
        XCTAssertEqual(controller.state.status, .abandoned)
    }

    func test_abandoningANeverStartedSessionDeletesTheJournalAndAppendsNothing() throws {
        // The window inside `startSession` between opening the journal and the
        // `started` event: a session that exists on disk but never began.
        controller.openJournal()
        let journal = try XCTUnwrap(controller.journal)
        let url = journal.url
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        controller.abandon()

        XCTAssertNil(controller.journal)
        XCTAssertEqual(names(journal.events), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(try SessionJournal.resumable(in: directory))
    }

    /// Important 7: the launch prompt's abandon path must leave nothing
    /// resumable behind.
    func test_abandonResumableSessionTerminatesTheJournal() async throws {
        let journal = try SessionJournal(sessionID: UUID(), directory: directory)
        try journal.append(.started(
            at: t(0), template: spec(rounds: 3), vestOn: false,
            vestWeightLbs: nil, indoor: false
        ))
        try journal.append(.paused(at: t(60)))
        XCTAssertTrue(controller.hasResumableSession())

        controller.abandonResumableSession()

        XCTAssertNil(try SessionJournal.resumable(in: directory))
        XCTAssertFalse(controller.hasResumableSession())
        let replayed = try SessionJournal(sessionID: journal.sessionID, directory: directory)
        XCTAssertEqual(names(replayed.events), ["started", "paused", "resumed", "abandoned"])
        XCTAssertTrue(replayed.state.isTerminal)
    }

    // MARK: - Undo

    func test_undoAcrossTheRunTwoBoundaryReissuesTheRoundsActivity() async {
        await controller.startSession(
            template: spec(rounds: 1), vestOn: false, vestWeightLbs: nil, indoor: true
        )
        controller.advance()            // run 1 done -> rounds
        controller.advance()            // the only round -> run 2
        XCTAssertEqual(controller.state.phase, .run2)
        XCTAssertEqual(fake.calls.last, .beginRun(resetDistanceBaseline: true))

        controller.undoLastRound()

        XCTAssertEqual(controller.state.phase, .rounds)
        // The segment must follow the phase back: leaving `.running` in place
        // would file the calisthenics as a run and wreck the calorie model.
        XCTAssertEqual(fake.calls.last, .beginRounds)
    }

    // MARK: - Resume

    /// Important 3.
    func test_resumingAPausedSessionPausesHealthKit() async throws {
        let journal = try SessionJournal(sessionID: UUID(), directory: directory)
        try journal.append(.started(
            at: t(0), template: spec(rounds: 3), vestOn: false,
            vestWeightLbs: nil, indoor: false
        ))
        try journal.append(.paused(at: t(120)))

        let resumed = try await controller.resumeExistingSession()

        XCTAssertTrue(resumed)
        XCTAssertTrue(controller.isPaused)
        // Without this the state machine believes it is paused while
        // HealthKit keeps accruing time and calories.
        XCTAssertEqual(fake.calls.last, .pause)
    }

    func test_resumingAnUnpausedSessionDoesNotPauseHealthKit() async throws {
        let journal = try SessionJournal(sessionID: UUID(), directory: directory)
        try journal.append(.started(
            at: t(0), template: spec(rounds: 3), vestOn: false,
            vestWeightLbs: nil, indoor: false
        ))

        _ = try await controller.resumeExistingSession()

        XCTAssertFalse(fake.calls.contains(.pause))
    }

    /// Important 6.
    func test_resumingMidRunKeepsTheDistanceAlreadyCovered() async throws {
        let journal = try SessionJournal(sessionID: UUID(), directory: directory)
        try journal.append(.started(
            at: t(0), template: spec(rounds: 3), vestOn: false,
            vestWeightLbs: nil, indoor: false
        ))
        fake.recoverSucceeds = true

        _ = try await controller.resumeExistingSession()

        // The recovered builder already holds the miles run before the
        // relaunch; re-snapshotting the baseline would subtract them away.
        XCTAssertTrue(fake.calls.contains(.beginRun(resetDistanceBaseline: false)))
        XCTAssertFalse(fake.calls.contains(.beginRun(resetDistanceBaseline: true)))
    }

    func test_resumingMidRunAfterAFailedRecoveryDoesSnapshotTheBaseline() async throws {
        let journal = try SessionJournal(sessionID: UUID(), directory: directory)
        try journal.append(.started(
            at: t(0), template: spec(rounds: 3), vestOn: false,
            vestWeightLbs: nil, indoor: false
        ))
        fake.recoverSucceeds = false

        _ = try await controller.resumeExistingSession()

        // A fresh builder has recorded nothing, so the baseline is honest.
        XCTAssertTrue(fake.calls.contains(.start(indoor: false)))
        XCTAssertTrue(fake.calls.contains(.beginRun(resetDistanceBaseline: true)))
    }

    func test_resumingInTheRoundsPhaseIssuesTheRoundsActivity() async throws {
        let journal = try SessionJournal(sessionID: UUID(), directory: directory)
        try journal.append(.started(
            at: t(0), template: spec(rounds: 3), vestOn: false,
            vestWeightLbs: nil, indoor: false
        ))
        try journal.append(.runFinished(index: 1, at: t(500), distanceMeters: 1609))

        _ = try await controller.resumeExistingSession()

        XCTAssertEqual(controller.state.phase, .rounds)
        XCTAssertEqual(fake.calls.last, .beginRounds)
    }

    // MARK: - Durability

    /// Important 5: a journal that cannot be created is the same durability
    /// failure as an append that throws, and must raise the same flag —
    /// otherwise an entire workout is recorded to nothing behind a green
    /// "Complete".
    func test_aJournalThatCannotBeCreatedFlagsTheWriteFailure() async throws {
        // A *file* where the journal directory should be, so `createDirectory`
        // cannot succeed.
        let blocker = directory.appendingPathComponent("blocked")
        try Data().write(to: blocker)
        let unwritable = blocker.appendingPathComponent("sessions", isDirectory: true)
        let doomed = WatchSessionController(workout: fake, journalDirectory: unwritable)

        await doomed.startSession(
            template: spec(rounds: 3), vestOn: false, vestWeightLbs: nil, indoor: false
        )

        XCTAssertNil(doomed.journal)
        XCTAssertTrue(doomed.journalWriteFailed)
        // The workout itself still runs: durability is optional to it.
        XCTAssertEqual(doomed.state.phase, .run1)
    }

    func test_aWorkingJournalLeavesTheWriteFailureFlagClear() async {
        await controller.startSession(
            template: spec(rounds: 3), vestOn: false, vestWeightLbs: nil, indoor: false
        )
        controller.advance()

        XCTAssertNotNil(controller.journal)
        XCTAssertFalse(controller.journalWriteFailed)
    }

    // MARK: - GPS lifecycle

    /// Walks a whole outdoor workout and asserts the receiver's on/off shape.
    /// This is the plan's headline behaviour in one test.
    func test_gpsRunsForTheRunsAndStopsForTheRounds() async throws {
        await controller.startSession(
            template: spec(rounds: 3), vestOn: false, vestWeightLbs: nil, indoor: false
        )
        XCTAssertEqual(gps.transitions, [.start])          // run 1

        controller.advance()                                // run 1 ends, rounds begin
        XCTAssertEqual(gps.transitions, [.start, .stop])

        controller.advance()                                // round 1 of 3 — still off
        XCTAssertEqual(gps.transitions, [.start, .stop])

        controller.advance()                                // round 2 of 3 — one remains
        XCTAssertEqual(gps.transitions, [.start, .stop, .start])

        controller.advance()                                // round 3 — run 2 begins
        XCTAssertEqual(gps.transitions, [.start, .stop, .start])

        controller.advance()                                // run 2 ends, complete
        XCTAssertEqual(gps.transitions, [.start, .stop, .start, .stop])
    }

    func test_indoorSessionNeverStartsTheReceiver() async throws {
        await controller.startSession(
            template: spec(rounds: 3), vestOn: false, vestWeightLbs: nil, indoor: true
        )
        controller.advance()
        controller.advance()
        controller.advance()
        controller.advance()
        controller.advance()

        XCTAssertFalse(gps.calls.contains(.start))
    }

    /// A pause mid-run leaves the receiver on: re-acquiring on resume costs
    /// more than the battery a short pause saves.
    func test_pauseLeavesTheReceiverRunning() async throws {
        await controller.startSession(
            template: spec(rounds: 3), vestOn: false, vestWeightLbs: nil, indoor: false
        )
        controller.pause()
        controller.resume()

        XCTAssertEqual(gps.transitions, [.start])
    }

    func test_abandoningStopsTheReceiver() async throws {
        await controller.startSession(
            template: spec(rounds: 3), vestOn: false, vestWeightLbs: nil, indoor: false
        )
        controller.abandon()

        XCTAssertEqual(gps.transitions.last, .stop)
    }

    func test_finishAndResetStopsTheReceiver() async throws {
        await controller.startSession(
            template: spec(rounds: 3), vestOn: false, vestWeightLbs: nil, indoor: false
        )
        controller.finishAndReset()

        XCTAssertEqual(gps.transitions.last, .stop)
    }

    /// Recovery needs no special path — replay the journal, ask the policy.
    func test_resumingMidRunRestartsTheReceiver() async throws {
        await controller.startSession(
            template: spec(rounds: 3), vestOn: false, vestWeightLbs: nil, indoor: false
        )

        let fresh = FakeLocationController()
        let revived = WatchSessionController(
            workout: FakeWorkoutController(), journalDirectory: directory, location: fresh
        )
        let resumed = try await revived.resumeExistingSession()

        XCTAssertTrue(resumed)
        XCTAssertEqual(fresh.transitions, [.start])
    }

    func test_resumingMidRoundsDoesNotStartTheReceiver() async throws {
        await controller.startSession(
            template: spec(rounds: 20), vestOn: false, vestWeightLbs: nil, indoor: false
        )
        controller.advance()   // into the rounds, 20 to go

        let fresh = FakeLocationController()
        let revived = WatchSessionController(
            workout: FakeWorkoutController(), journalDirectory: directory, location: fresh
        )
        let resumed = try await revived.resumeExistingSession()

        XCTAssertTrue(resumed)
        XCTAssertFalse(fresh.calls.contains(.start))
    }

    /// Relaunching one round from run 2 must come back already warming.
    func test_resumingAtThePenultimateRoundRestartsTheReceiver() async throws {
        await controller.startSession(
            template: spec(rounds: 3), vestOn: false, vestWeightLbs: nil, indoor: false
        )
        controller.advance()   // rounds begin
        controller.advance()   // round 1
        controller.advance()   // round 2 — one remains

        let fresh = FakeLocationController()
        let revived = WatchSessionController(
            workout: FakeWorkoutController(), journalDirectory: directory, location: fresh
        )
        let resumed = try await revived.resumeExistingSession()

        XCTAssertTrue(resumed)
        XCTAssertEqual(fresh.transitions, [.start])
    }

    func test_requestAuthorizationAsksBothSensors() async throws {
        await controller.requestAuthorization()

        XCTAssertTrue(fake.calls.contains(.requestAuthorization))
        XCTAssertTrue(gps.calls.contains(.requestAuthorization))
    }

    /// The setup-screen warm-up sits outside the policy on purpose: the policy
    /// answers "where is the session", and on the setup screen there is none.
    func test_setupWarmupStartsAndStopsDirectly() {
        controller.warmLocationForSetup(true)
        XCTAssertEqual(gps.transitions, [.start])

        controller.warmLocationForSetup(false)
        XCTAssertEqual(gps.transitions, [.start, .stop])
    }

    func test_gpsFixStateIsOffWithNoProvider() {
        let bare = WatchSessionController(workout: FakeWorkoutController(), journalDirectory: directory)
        XCTAssertEqual(bare.gpsFixState, .off)
    }
}
