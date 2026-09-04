// MurphCore/SessionEvent.swift
import Foundation

/// The single currency of a live session.
///
/// Everything downstream is derived from an ordered array of these: the
/// session's state, its elapsed time, its round durations, the Watch's on-disk
/// journal, and the sync payload. Phase transitions are *implicit* — `started`
/// begins run 1, `runFinished(1)` begins the rounds, the round reaching the
/// template's total begins run 2, `runFinished(2)` completes the session — so
/// there are no separate transition events to keep consistent.
///
/// Timestamps always come from the device that owns the session, and are never
/// restamped on receipt. Every duration is therefore a difference between two
/// readings of the same clock, which is why clock skew between watch and phone
/// cannot distort a split.
enum SessionEvent: Codable, Equatable {
    case started(at: Date, template: TemplateSpec, vestOn: Bool, vestWeightLbs: Int?, indoor: Bool)
    case runFinished(index: Int, at: Date, distanceMeters: Double?)
    case roundCompleted(number: Int, at: Date)
    case roundUndone(number: Int, at: Date)
    case paused(at: Date)
    case resumed(at: Date)
    case heartRate(bpm: Int, at: Date)
    case abandoned(at: Date)

    var timestamp: Date {
        switch self {
        case let .started(at, _, _, _, _): at
        case let .runFinished(_, at, _): at
        case let .roundCompleted(_, at): at
        case let .roundUndone(_, at): at
        case let .paused(at): at
        case let .resumed(at): at
        case let .heartRate(_, at): at
        case let .abandoned(at): at
        }
    }

    /// Heart rate is journaled every 5 seconds and is the only high-frequency
    /// event. Stage 3 checkpoints on every event that is *not* one of these.
    var isHeartRate: Bool {
        if case .heartRate = self { return true }
        return false
    }
}
