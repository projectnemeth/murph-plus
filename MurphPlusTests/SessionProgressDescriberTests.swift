// MurphPlusTests/SessionProgressDescriberTests.swift
import XCTest
@testable import MurphPlus

final class SessionProgressDescriberTests: XCTestCase {

    // MARK: - Long form (session detail)

    func test_describe_midRounds_namesRoundsAndReps() {
        let text = SessionProgressDescriber.describe(
            phase: .rounds, roundsCompleted: 15, totalRounds: 20, repsPerRound: 30
        )

        XCTAssertEqual(text, "Stopped during rounds · 15 of 20 · 450 of 600 reps")
    }

    func test_describe_duringRun1_omitsRoundsEntirely() {
        let text = SessionProgressDescriber.describe(
            phase: .run1, roundsCompleted: 0, totalRounds: 20, repsPerRound: 30
        )

        // "0 of 20 rounds" is noise when the user never reached the rounds.
        XCTAssertEqual(text, "Stopped during run 1")
    }

    func test_describe_duringRun2_notesAllRoundsDone() {
        let text = SessionProgressDescriber.describe(
            phase: .run2, roundsCompleted: 20, totalRounds: 20, repsPerRound: 30
        )

        XCTAssertEqual(text, "Stopped during run 2 · all 20 rounds complete")
    }

    func test_describe_beforeStarting() {
        let text = SessionProgressDescriber.describe(
            phase: .notStarted, roundsCompleted: 0, totalRounds: 20, repsPerRound: 30
        )

        XCTAssertEqual(text, "Stopped before starting")
    }

    func test_describe_completedSessionHasNoProgressLine() {
        let text = SessionProgressDescriber.describe(
            phase: .completed, roundsCompleted: 20, totalRounds: 20, repsPerRound: 30
        )

        XCTAssertNil(text, "A finished session is described by its time, not its progress")
    }

    func test_describe_straightSetsSessionStillReadsSensibly() {
        let text = SessionProgressDescriber.describe(
            phase: .rounds, roundsCompleted: 0, totalRounds: 1, repsPerRound: 600
        )

        XCTAssertEqual(text, "Stopped during rounds · 0 of 1 · 0 of 600 reps")
    }

    // MARK: - Short form (history row)

    func test_shortDescription_midRounds() {
        XCTAssertEqual(
            SessionProgressDescriber.shortDescription(phase: .rounds, roundsCompleted: 15, totalRounds: 20),
            "15/20 rounds"
        )
    }

    func test_shortDescription_duringRuns() {
        XCTAssertEqual(
            SessionProgressDescriber.shortDescription(phase: .run1, roundsCompleted: 0, totalRounds: 20),
            "Run 1"
        )
        XCTAssertEqual(
            SessionProgressDescriber.shortDescription(phase: .run2, roundsCompleted: 20, totalRounds: 20),
            "Run 2"
        )
    }

    func test_shortDescription_completedIsNil() {
        XCTAssertNil(
            SessionProgressDescriber.shortDescription(phase: .completed, roundsCompleted: 20, totalRounds: 20)
        )
    }
}
