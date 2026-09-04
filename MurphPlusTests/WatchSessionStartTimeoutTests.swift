// MurphPlusTests/WatchSessionStartTimeoutTests.swift
import XCTest
@testable import MurphPlus

/// A `WorkoutControlling` whose `start(indoor:)` never returns.
///
/// This is not a hypothetical. Shipped without the HealthKit entitlement, the
/// real controller behaved exactly this way: `HKWorkoutSession.init` *succeeded*
/// (so the defensive catch never fired), then HealthKit's task server failed to
/// start and `builder.beginCollection(at:)` never called back — leaving
/// `startSession` suspended forever and the app pinned to the setup screen.
@MainActor
final class HangingWorkoutController: WorkoutControlling {
    private(set) var startWasCalled = false

    var currentHeartRate: Int?
    var currentRunDistanceMeters: Double?
    var onHeartRate: ((Int) -> Void)?

    func requestAuthorization() async {}

    func start(indoor: Bool) async {
        startWasCalled = true
        // Suspend forever, the way an un-called HealthKit completion handler does.
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
    }

    func recover(indoor: Bool) async -> Bool { false }
    func beginRunActivity(resetDistanceBaseline: Bool) {}
    func beginRoundsActivity() {}
    func pause() {}
    func resume() {}
    func finish() async {}
}

@MainActor
final class WatchSessionStartTimeoutTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-start-timeout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var spec: TemplateSpec {
        TemplateSpec(
            id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
            totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 20
        )
    }

    /// Bounds the test itself so a regression fails in seconds instead of
    /// hanging the whole suite.
    private func withDeadline(
        _ seconds: Double, _ work: @escaping @MainActor () async -> Void
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in await work(); return true }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return false
            }
            let finishedFirst = await group.next() ?? false
            group.cancelAll()
            return finishedFirst
        }
    }

    func test_aHealthKitStartThatNeverReturnsStillStartsTheWorkout() async throws {
        let hanging = HangingWorkoutController()
        let controller = WatchSessionController(
            workout: hanging,
            journalDirectory: directory,
            healthKitStartTimeout: 0.05
        )

        let returned = await withDeadline(3) {
            await controller.startSession(
                template: self.spec, vestOn: false, vestWeightLbs: nil, indoor: false
            )
        }

        XCTAssertTrue(returned, "startSession must return even when HealthKit never does")
        XCTAssertTrue(hanging.startWasCalled, "HealthKit must still have been attempted")
        XCTAssertEqual(
            controller.state.phase, .run1,
            "The workout must be under way regardless of HealthKit"
        )
    }

    /// The timeout must not steal time from the normal path.
    func test_aPromptHealthKitStartIsNotDelayedByTheTimeout() async throws {
        let fake = FakeWorkoutController()
        let controller = WatchSessionController(
            workout: fake,
            journalDirectory: directory,
            healthKitStartTimeout: 30
        )

        let returned = await withDeadline(3) {
            await controller.startSession(
                template: self.spec, vestOn: false, vestWeightLbs: nil, indoor: false
            )
        }

        XCTAssertTrue(returned, "A prompt start must not wait on the timeout")
        XCTAssertEqual(controller.state.phase, .run1)
    }
}
