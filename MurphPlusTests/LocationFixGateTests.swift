// MurphPlusTests/LocationFixGateTests.swift
import XCTest
@testable import MurphPlus

@MainActor
final class LocationFixGateTests: XCTestCase {
    /// A real suspension, just a very short one — same reasoning as
    /// `StartCountdownTests`: a delay that does not actually suspend would let
    /// every test pass without exercising the polling at all.
    private func fastSleep(_: Duration) async throws {
        try await Task.sleep(for: .milliseconds(1))
    }

    private func gate(timeout: TimeInterval = 1, poll: TimeInterval = 0.1) -> LocationFixGate {
        LocationFixGate(timeout: timeout, pollInterval: poll, sleep: fastSleep)
    }

    func test_aFixReturnsImmediatelyWithoutWaiting() async {
        let g = gate()
        await g.wait { .fixed }
        XCTAssertFalse(g.isWaiting)
    }

    /// The case that matters most: waiting for a fix that will never come is
    /// pure delay in front of a workout.
    func test_deniedReturnsImmediately() async {
        let g = gate()
        await g.wait { .denied }
        XCTAssertFalse(g.isWaiting)
    }

    func test_offReturnsImmediately() async {
        let g = gate()
        await g.wait { .off }
        XCTAssertFalse(g.isWaiting)
    }

    func test_acquiringHoldsUntilAFixArrives() async {
        let g = gate(timeout: 10, poll: 0.1)
        var polls = 0
        await g.wait {
            polls += 1
            return polls < 4 ? .acquiring : .fixed
        }
        XCTAssertGreaterThanOrEqual(polls, 4)
        XCTAssertFalse(g.isWaiting)
    }

    /// Start anyway. Available from the first frame, not after a delay.
    func test_skipEndsTheWaitEarly() async {
        let g = gate(timeout: 100, poll: 0.1)
        let done = expectation(description: "gate returned")
        Task {
            await g.wait { .acquiring }
            done.fulfill()
        }
        // Let the wait get going, then release it.
        try? await Task.sleep(for: .milliseconds(20))
        g.skip()
        await fulfillment(of: [done], timeout: 2)
        XCTAssertFalse(g.isWaiting)
    }

    /// The bound is the whole reason this is safe: the standing contract is
    /// that no sensor may block the workout.
    func test_givesUpAtTheTimeout() async {
        let g = gate(timeout: 0.5, poll: 0.1)   // 5 polls
        var polls = 0
        await g.wait {
            polls += 1
            return .acquiring
        }
        // Six, not five: one read before deciding to wait at all, then one
        // per poll. A gate that did not read first would suspend even on a
        // fix it already had.
        XCTAssertEqual(polls, 6)
        XCTAssertFalse(g.isWaiting)
    }

    func test_isWaitingIsTrueWhileHolding() async {
        let g = gate(timeout: 100, poll: 0.1)
        let done = expectation(description: "gate returned")
        Task {
            await g.wait { .acquiring }
            done.fulfill()
        }
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(g.isWaiting)
        g.skip()
        await fulfillment(of: [done], timeout: 2)
    }

    /// A second workout in the same launch must not inherit the first one's
    /// skip.
    func test_skipDoesNotLeakIntoTheNextWait() async {
        let g = gate(timeout: 0.5, poll: 0.1)
        g.skip()
        var polls = 0
        await g.wait {
            polls += 1
            return .acquiring
        }
        XCTAssertEqual(polls, 6)   // the guard read, then five polls
    }

    func test_defaultTimeoutIsThirtySeconds() {
        XCTAssertEqual(LocationFixGate.defaultTimeout, 30)
    }
}
