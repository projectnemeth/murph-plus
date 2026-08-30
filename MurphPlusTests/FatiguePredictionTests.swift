// MurphPlusTests/FatiguePredictionTests.swift
import XCTest
@testable import MurphPlus

final class FatiguePredictionTests: XCTestCase {

    func test_fitFatigueCurve_returnsNilWithFewerThanThreeRounds() {
        let rounds = [
            RoundThroughput(cumulativeRepsAfter: 10, secondsForRound: 20, repsInRound: 10),
            RoundThroughput(cumulativeRepsAfter: 20, secondsForRound: 22, repsInRound: 10)
        ]
        XCTAssertNil(FatiguePrediction.fitFatigueCurve(rounds: rounds))
    }

    // Fixture note: intercept 1.0 / slope 0.02 at 10 reps/round is chosen
    // deliberately so every round's duration lands on a whole second
    // (11, 13, 15, 17, 19, 21). Rounding to Int would otherwise bias the fit —
    // a 0.01 slope yields x.5-second rounds and shifts the recovered intercept
    // by exactly 0.05, which is enough to fail a tolerance-based assertion.
    func test_fitFatigueCurve_recoversKnownLinearRelationship() {
        let repsPerRound = 10
        var rounds: [RoundThroughput] = []
        var cumulative = 0
        for _ in 0..<6 {
            cumulative += repsPerRound
            let midpoint = Double(cumulative) - Double(repsPerRound) / 2.0
            let secPerRep = 1.0 + 0.02 * midpoint
            let secondsForRound = Int((secPerRep * Double(repsPerRound)).rounded())
            rounds.append(RoundThroughput(cumulativeRepsAfter: cumulative, secondsForRound: secondsForRound, repsInRound: repsPerRound))
        }

        let fit = FatiguePrediction.fitFatigueCurve(rounds: rounds)
        XCTAssertNotNil(fit)
        XCTAssertEqual(fit!.intercept, 1.0, accuracy: 0.0001)
        XCTAssertEqual(fit!.slope, 0.02, accuracy: 0.0001)
    }

    func test_predictWorkTime_withZeroSlope_matchesFlatMultiplication() {
        let fit = FatiguePrediction.LinearFit(intercept: 2.0, slope: 0.0)
        let predicted = FatiguePrediction.predictWorkTime(targetReps: 300, fit: fit)
        XCTAssertEqual(predicted, 600.0, accuracy: 0.001)
    }

    func test_predictWorkTimeFlatRate_scalesProportionally() {
        let predicted = FatiguePrediction.predictWorkTimeFlatRate(targetReps: 600, sourceWorkSeconds: 300, sourceTotalReps: 300)
        XCTAssertEqual(predicted!, 600.0, accuracy: 0.001)
    }

    func test_predict_usesFatigueCurveWhenEnoughRounds() {
        let repsPerRound = 15
        var rounds: [RoundThroughput] = []
        var cumulative = 0
        for _ in 0..<5 {
            cumulative += repsPerRound
            rounds.append(RoundThroughput(cumulativeRepsAfter: cumulative, secondsForRound: 20, repsInRound: repsPerRound))
        }
        let pace = FatiguePrediction.RunPace(run1SecondsPerMile: 480, run2SecondsPerMile: 540)

        let result = FatiguePrediction.predict(
            targetRunDistanceMiles: 1.0,
            targetTotalReps: 600,
            sourceRoundThroughputs: rounds,
            sourceWorkSeconds: 100,
            sourceTotalReps: 75,
            pace: pace
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.usedFatigueCurve)
        XCTAssertEqual(result!.predictedRun1Seconds, 480, accuracy: 0.001)
        XCTAssertEqual(result!.predictedRun2Seconds, 540, accuracy: 0.001)
    }

    func test_predict_fallsBackToFlatRateWithOneRound() {
        let rounds = [RoundThroughput(cumulativeRepsAfter: 600, secondsForRound: 500, repsInRound: 600)]
        let pace = FatiguePrediction.RunPace(run1SecondsPerMile: 480, run2SecondsPerMile: 540)

        let result = FatiguePrediction.predict(
            targetRunDistanceMiles: 1.0,
            targetTotalReps: 300,
            sourceRoundThroughputs: rounds,
            sourceWorkSeconds: 500,
            sourceTotalReps: 600,
            pace: pace
        )

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.usedFatigueCurve)
        XCTAssertEqual(result!.predictedWorkSeconds, 250.0, accuracy: 0.001)
    }
}
