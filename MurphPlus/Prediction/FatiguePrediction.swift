// MurphPlus/Prediction/FatiguePrediction.swift
import Foundation

struct RoundThroughput {
    let cumulativeRepsAfter: Int
    let secondsForRound: Int
    let repsInRound: Int

    var secondsPerRep: Double { Double(secondsForRound) / Double(repsInRound) }
}

enum FatiguePrediction {

    struct LinearFit {
        let intercept: Double
        let slope: Double
    }

    struct RunPace {
        let run1SecondsPerMile: Double
        let run2SecondsPerMile: Double
    }

    struct PredictionResult {
        let predictedRun1Seconds: Double
        let predictedWorkSeconds: Double
        let predictedRun2Seconds: Double
        let usedFatigueCurve: Bool

        var totalSeconds: Double { predictedRun1Seconds + predictedWorkSeconds + predictedRun2Seconds }
    }

    /// Least-squares fit of seconds/rep vs. cumulative reps completed, sampled at
    /// each round's midpoint (a round's rate is best attributed to its middle,
    /// not its start or end).
    static func fitFatigueCurve(rounds: [RoundThroughput]) -> LinearFit? {
        guard rounds.count >= 3 else { return nil }

        let points = rounds.map { round -> (x: Double, y: Double) in
            let midpoint = Double(round.cumulativeRepsAfter) - Double(round.repsInRound) / 2.0
            return (x: midpoint, y: round.secondsPerRep)
        }

        let n = Double(points.count)
        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }
        let sumXY = points.reduce(0) { $0 + $1.x * $1.y }
        let sumXX = points.reduce(0) { $0 + $1.x * $1.x }

        let denominator = n * sumXX - sumX * sumX
        guard denominator != 0 else { return nil }

        let slope = (n * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / n

        return LinearFit(intercept: intercept, slope: slope)
    }

    /// Integrates the fitted seconds/rep line from 0 to targetReps.
    static func predictWorkTime(targetReps: Int, fit: LinearFit) -> Double {
        let reps = Double(targetReps)
        return fit.intercept * reps + fit.slope * reps * reps / 2.0
    }

    static func predictWorkTimeFlatRate(targetReps: Int, sourceWorkSeconds: Double, sourceTotalReps: Int) -> Double? {
        guard sourceTotalReps > 0 else { return nil }
        let rate = sourceWorkSeconds / Double(sourceTotalReps)
        return rate * Double(targetReps)
    }

    static func predictRunTime(targetDistanceMiles: Double, secondsPerMile: Double) -> Double {
        targetDistanceMiles * secondsPerMile
    }

    static func predict(
        targetRunDistanceMiles: Double,
        targetTotalReps: Int,
        sourceRoundThroughputs: [RoundThroughput],
        sourceWorkSeconds: Double,
        sourceTotalReps: Int,
        pace: RunPace
    ) -> PredictionResult? {
        let predictedRun1 = predictRunTime(targetDistanceMiles: targetRunDistanceMiles, secondsPerMile: pace.run1SecondsPerMile)
        let predictedRun2 = predictRunTime(targetDistanceMiles: targetRunDistanceMiles, secondsPerMile: pace.run2SecondsPerMile)

        if let fit = fitFatigueCurve(rounds: sourceRoundThroughputs) {
            let work = predictWorkTime(targetReps: targetTotalReps, fit: fit)
            return PredictionResult(predictedRun1Seconds: predictedRun1, predictedWorkSeconds: work, predictedRun2Seconds: predictedRun2, usedFatigueCurve: true)
        } else if let flat = predictWorkTimeFlatRate(targetReps: targetTotalReps, sourceWorkSeconds: sourceWorkSeconds, sourceTotalReps: sourceTotalReps) {
            return PredictionResult(predictedRun1Seconds: predictedRun1, predictedWorkSeconds: flat, predictedRun2Seconds: predictedRun2, usedFatigueCurve: false)
        } else {
            return nil
        }
    }
}
