// MurphPlusTests/LocationPolicyTests.swift
import XCTest
@testable import MurphPlus

/// `SessionState` is normally only reachable through `replay`, but the policy
/// is a pure function *of* a state — building states by replay would be
/// testing the replay, not the rule. Authored directly on purpose.
final class LocationPolicyTests: XCTestCase {

    private func spec(rounds: Int) -> TemplateSpec {
        TemplateSpec(
            id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
            totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: rounds
        )
    }

    private func state(
        phase: SessionPhase, rounds: Int = 20,
        completed: Int = 0, indoor: Bool = false
    ) -> SessionState {
        var s = SessionState()
        s.template = spec(rounds: rounds)
        s.phase = phase
        s.completedRounds = completed
        s.indoor = indoor
        return s
    }

    func test_runsAlwaysWarm() {
        XCTAssertTrue(LocationPolicy.shouldWarm(for: state(phase: .run1)))
        XCTAssertTrue(LocationPolicy.shouldWarm(for: state(phase: .run2)))
    }

    func test_indoorNeverWarms() {
        XCTAssertFalse(LocationPolicy.shouldWarm(for: state(phase: .run1, indoor: true)))
        XCTAssertFalse(LocationPolicy.shouldWarm(for: state(phase: .run2, indoor: true)))
        XCTAssertFalse(
            LocationPolicy.shouldWarm(
                for: state(phase: .rounds, rounds: 20, completed: 19, indoor: true)
            )
        )
    }

    func test_roundsDoNotWarmUntilOneRemains() {
        XCTAssertFalse(LocationPolicy.shouldWarm(for: state(phase: .rounds, completed: 0)))
        XCTAssertFalse(LocationPolicy.shouldWarm(for: state(phase: .rounds, completed: 3)))
        XCTAssertFalse(LocationPolicy.shouldWarm(for: state(phase: .rounds, completed: 18)))
    }

    /// The pre-warm: one round of head start before run 2.
    func test_roundsWarmAtOneRemaining() {
        XCTAssertTrue(LocationPolicy.shouldWarm(for: state(phase: .rounds, completed: 19)))
    }

    /// Stated as "remaining <= 1" rather than "== 1" so a miscount past the
    /// total cannot switch the receiver back off mid-workout.
    func test_roundsWarmPastTheTotal() {
        XCTAssertTrue(LocationPolicy.shouldWarm(for: state(phase: .rounds, completed: 25)))
    }

    /// Falls out of the rule with no special case: at rounds-start the
    /// condition is already true, so the receiver simply never powers down.
    func test_singleRoundTemplateWarmsFromTheStartOfRounds() {
        XCTAssertTrue(
            LocationPolicy.shouldWarm(for: state(phase: .rounds, rounds: 1, completed: 0))
        )
    }

    func test_terminalAndUnstartedPhasesNeverWarm() {
        XCTAssertFalse(LocationPolicy.shouldWarm(for: state(phase: .notStarted)))
        XCTAssertFalse(LocationPolicy.shouldWarm(for: state(phase: .completed)))
    }

    /// A rounds phase with no template cannot answer the question; the safe
    /// answer is off, not a crash.
    func test_roundsWithoutATemplateDoNotWarm() {
        var s = SessionState()
        s.phase = .rounds
        XCTAssertFalse(LocationPolicy.shouldWarm(for: s))
    }
}
