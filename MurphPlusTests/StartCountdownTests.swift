// MurphPlusTests/StartCountdownTests.swift
import XCTest
@testable import MurphPlus

@MainActor
final class StartCountdownTests: XCTestCase {
    /// A real suspension, just a very short one. Injecting a delay that does
    /// not actually suspend would make every test pass without exercising the
    /// property that matters — that cancellation propagates through the wait.
    private func fastSleep(_: Duration) async throws {
        try await Task.sleep(for: .milliseconds(2))
    }

    func test_start_countsDownAndThenRuns() async throws {
        let countdown = StartCountdown(seconds: 3, sleep: fastSleep)
        var ticks: [Int] = []
        countdown.onTick = { ticks.append($0) }

        let started = expectation(description: "workout started")
        countdown.start { started.fulfill() }
        await fulfillment(of: [started], timeout: 2)

        XCTAssertEqual(ticks, [3, 2, 1])
        XCTAssertNil(countdown.remaining)
        XCTAssertFalse(countdown.isRunning)
    }

    func test_start_publishesTheNumberOnScreen() async throws {
        let countdown = StartCountdown(seconds: 3, sleep: fastSleep)
        countdown.start {}
        // Synchronously after `start`, before the first suspension: the view
        // must have something to draw the instant Start is tapped, not one
        // second later.
        XCTAssertEqual(countdown.remaining, 3)
        XCTAssertTrue(countdown.isRunning)
        countdown.cancel()
    }

    /// The property the whole design rests on: a cancelled count leaves no
    /// journal, no HealthKit session and no navigation behind, because the
    /// caller does all of that inside `go`.
    func test_cancel_neverRunsTheWorkout() async throws {
        var ran = false
        let countdown = StartCountdown(seconds: 3) { _ in
            try await Task.sleep(for: .milliseconds(50))
        }
        countdown.start { ran = true }
        countdown.cancel()

        XCTAssertNil(countdown.remaining)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(ran)
    }

    /// A double tap on Start must produce one workout, not two.
    func test_start_twice_runsTheWorkoutOnce() async throws {
        var runs = 0
        let countdown = StartCountdown(seconds: 2, sleep: fastSleep)

        let done = expectation(description: "started")
        done.expectedFulfillmentCount = 1
        done.assertForOverFulfill = true
        countdown.start { runs += 1; done.fulfill() }
        countdown.start { runs += 1; done.fulfill() }
        await fulfillment(of: [done], timeout: 2)

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(runs, 1)
    }

    /// A zero-length countdown is a legitimate configuration — it must start
    /// the workout immediately rather than silently do nothing.
    func test_zeroSeconds_startsImmediately() async throws {
        let countdown = StartCountdown(seconds: 0, sleep: fastSleep)
        let started = expectation(description: "workout started")
        countdown.start { started.fulfill() }
        await fulfillment(of: [started], timeout: 1)
        XCTAssertNil(countdown.remaining)
    }

    func test_cancel_withNothingRunning_isHarmless() {
        let countdown = StartCountdown(seconds: 3, sleep: fastSleep)
        countdown.cancel()
        XCTAssertNil(countdown.remaining)
    }
}
