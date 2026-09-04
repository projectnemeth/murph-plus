// MurphCore/TemplateSpec.swift
import Foundation

/// A value-type snapshot of a workout template's numbers.
///
/// This is what crosses to the Watch and what a `started` event carries, so a
/// session always knows what it was an attempt at — even if the underlying
/// `WorkoutTemplate` is later edited or deleted. `WorkoutTemplate` itself is a
/// SwiftData `@Model` and stays on the phone.
struct TemplateSpec: Codable, Equatable {
    var id: UUID
    var name: String
    var runDistanceMiles: Double
    var totalPullUps: Int
    var totalPushUps: Int
    var totalSquats: Int
    var rounds: Int

    /// Guards integer division: a stored 0 would be a hard crash rather than a
    /// recoverable error. Mirrors the same guard on `WorkoutTemplate`.
    var safeRounds: Int { max(rounds, 1) }

    var totalReps: Int { totalPullUps + totalPushUps + totalSquats }
    var pullUpsPerRound: Int { totalPullUps / safeRounds }
    var pushUpsPerRound: Int { totalPushUps / safeRounds }
    var squatsPerRound: Int { totalSquats / safeRounds }
    var repsPerRound: Int { totalReps / safeRounds }
}
