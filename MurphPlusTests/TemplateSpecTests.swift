// MurphPlusTests/TemplateSpecTests.swift
import XCTest
@testable import MurphPlus

final class TemplateSpecTests: XCTestCase {

    private func fullMurph(rounds: Int) -> TemplateSpec {
        TemplateSpec(
            id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
            totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: rounds
        )
    }

    func test_derivedPerRoundValues() {
        let spec = fullMurph(rounds: 20)

        XCTAssertEqual(spec.totalReps, 600)
        XCTAssertEqual(spec.pullUpsPerRound, 5)
        XCTAssertEqual(spec.pushUpsPerRound, 10)
        XCTAssertEqual(spec.squatsPerRound, 15)
        XCTAssertEqual(spec.repsPerRound, 30)
    }

    func test_zeroRoundsDoesNotDivideByZero() {
        // A stored 0 would be a hard crash rather than a recoverable error,
        // mirroring the guard WorkoutTemplate already carries.
        let spec = fullMurph(rounds: 0)

        XCTAssertEqual(spec.safeRounds, 1)
        XCTAssertEqual(spec.repsPerRound, 600)
    }

    func test_roundTripsThroughJSON() throws {
        let spec = fullMurph(rounds: 20)

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(TemplateSpec.self, from: data)

        XCTAssertEqual(decoded, spec)
    }
}
