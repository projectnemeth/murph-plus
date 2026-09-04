// MurphPlusTests/WatchPhaseLabelTests.swift
import XCTest
@testable import MurphPlus

final class WatchPhaseLabelTests: XCTestCase {

    func test_eachPhaseHasItsOwnLabel() {
        XCTAssertEqual(WatchPhaseLabel.text(phase: .run1, isPaused: false), "Run 1")
        XCTAssertEqual(WatchPhaseLabel.text(phase: .rounds, isPaused: false), "Rounds")
        XCTAssertEqual(WatchPhaseLabel.text(phase: .run2, isPaused: false), "Run 2")
    }

    /// Paused outranks the phase. A user who paused and walked away needs to
    /// see *that* from any page — the phase is still true but is no longer the
    /// thing they got the watch out to check.
    func test_pausedOutranksThePhase() {
        XCTAssertEqual(WatchPhaseLabel.text(phase: .rounds, isPaused: true), "Paused")
        XCTAssertEqual(WatchPhaseLabel.text(phase: .run1, isPaused: true), "Paused")
    }

    /// Nothing to say before the session starts or after it ends, and the
    /// corner sits beside the system clock — a stale label there would be
    /// worse than blank space.
    func test_theCornerIsBlankOutsideALiveSession() {
        XCTAssertNil(WatchPhaseLabel.text(phase: .notStarted, isPaused: false))
        XCTAssertNil(WatchPhaseLabel.text(phase: .completed, isPaused: false))
    }

    /// Terminal beats paused: a completed session is not "Paused" just
    /// because the flag was never cleared.
    func test_aCompletedSessionIsBlankEvenIfPausedIsSet() {
        XCTAssertNil(WatchPhaseLabel.text(phase: .completed, isPaused: true))
    }
}
