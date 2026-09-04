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

@MainActor
final class WatchSessionControllerTests: XCTestCase {

    private var directory: URL!
    private var fake: FakeWorkoutController!
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
        controller = WatchSessionController(workout: fake, journalDirectory: directory)
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
}
