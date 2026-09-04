// MurphCore/SessionState.swift
import Foundation

/// One paused stretch, excluded from every duration that spans it.
struct PausedInterval: Codable, Equatable {
    var start: Date
    var end: Date
}

/// A completed run, with its duration already net of any pause taken during it.
struct RunSplitState: Codable, Equatable {
    var index: Int
    var startTime: Date
    var durationSeconds: Double
    var distanceMeters: Double?
}

/// The state of a live session, produced entirely by folding an event array.
///
/// Nothing here is authored directly — `replay` and `apply` are the only ways
/// in, which is what makes crash recovery free: replay the journal and you are
/// exactly where you were.
struct SessionState: Equatable {
    var template: TemplateSpec?
    var vestOn: Bool = false
    var vestWeightLbs: Int?
    var indoor: Bool = false

    var phase: SessionPhase = .notStarted
    var status: SessionStatus = .inProgress

    var startedAt: Date?
    /// When the *current* phase began — used to time runs.
    var currentPhaseStartedAt: Date?
    /// When the rounds phase began; the boundary before round 1. Kept
    /// separately from `currentPhaseStartedAt` so undoing out of run 2 can
    /// restore the rounds phase without losing the round-timing origin.
    var roundsStartedAt: Date?
    var completedAt: Date?

    var completedRounds: Int = 0
    var roundTimestamps: [Date] = []
    var runSplits: [RunSplitState] = []

    var pausedAt: Date?
    var pausedIntervals: [PausedInterval] = []

    var latestHeartRate: Int?

    /// The round that may still be undone, or `nil` if undo is not available.
    /// Set by `roundCompleted` and cleared by any other non-heart-rate event —
    /// heart rate arrives every 5 seconds and must not close the undo window.
    var undoableRoundNumber: Int?

    var isPaused: Bool { pausedAt != nil }
    var isTerminal: Bool { status == .completed || status == .abandoned }

    static func replay(_ events: [SessionEvent]) -> SessionState {
        var state = SessionState()
        for event in events { state.apply(event) }
        return state
    }

    /// Total paused time overlapping the window, including an in-progress pause
    /// which counts up to `end`.
    func pausedSeconds(between start: Date, and end: Date) -> TimeInterval {
        var intervals = pausedIntervals
        if let pausedAt {
            intervals.append(PausedInterval(start: pausedAt, end: end))
        }
        return intervals.reduce(0) { total, interval in
            let overlapStart = max(interval.start, start)
            let overlapEnd = min(interval.end, end)
            return total + max(0, overlapEnd.timeIntervalSince(overlapStart))
        }
    }

    mutating func apply(_ event: SessionEvent) {
        if Self.closesUndoWindow(event) {
            undoableRoundNumber = nil
        }

        switch event {
        case let .started(at, template, vestOn, vestWeightLbs, indoor):
            self.template = template
            self.vestOn = vestOn
            self.vestWeightLbs = vestWeightLbs
            self.indoor = indoor
            startedAt = at
            phase = .run1
            currentPhaseStartedAt = at

        case let .runFinished(index, at, distanceMeters):
            if let phaseStart = currentPhaseStartedAt {
                let gross = at.timeIntervalSince(phaseStart)
                let paused = pausedSeconds(between: phaseStart, and: at)
                runSplits.append(RunSplitState(
                    index: index,
                    startTime: phaseStart,
                    durationSeconds: gross - paused,
                    distanceMeters: distanceMeters
                ))
            }
            if index == 1 {
                phase = .rounds
                currentPhaseStartedAt = at
                roundsStartedAt = at
            } else {
                phase = .completed
                status = .completed
                completedAt = at
                currentPhaseStartedAt = nil
            }

        case let .roundCompleted(number, at):
            roundTimestamps.append(at)
            completedRounds = number
            undoableRoundNumber = number
            if let template, completedRounds >= template.rounds {
                phase = .run2
                currentPhaseStartedAt = at
            }

        case .roundUndone:
            if !roundTimestamps.isEmpty { roundTimestamps.removeLast() }
            completedRounds = max(0, completedRounds - 1)
            if phase == .run2 {
                phase = .rounds
                currentPhaseStartedAt = roundsStartedAt
            }

        case let .paused(at):
            if pausedAt == nil { pausedAt = at }

        case let .resumed(at):
            if let start = pausedAt {
                pausedIntervals.append(PausedInterval(start: start, end: at))
                pausedAt = nil
            }

        case let .heartRate(bpm, _):
            latestHeartRate = bpm

        case let .abandoned(at):
            status = .abandoned
            completedAt = at
            currentPhaseStartedAt = nil
            // `phase` is deliberately left where it was: it is the record of
            // how far the attempt got, which the history screens display.
        }
    }

    /// Whether `event` should end the undo window. Heart rate never does (it
    /// arrives every 5 seconds and would make undo almost never available); a
    /// completed round leaves the window open here — `apply`'s switch sets it
    /// to the new round number right after — and every other event closes it.
    private static func closesUndoWindow(_ event: SessionEvent) -> Bool {
        if event.isHeartRate { return false }
        if case .roundCompleted = event { return false }
        return true
    }
}
