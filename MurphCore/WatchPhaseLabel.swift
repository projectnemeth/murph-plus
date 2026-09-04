// MurphCore/WatchPhaseLabel.swift
import Foundation

/// The short label shown in the status band's top-left corner, beside the
/// system clock.
///
/// That corner is the one place on the live pages that carries *where you are*
/// rather than a number, so the heroes below it can drop the phase from their
/// own labels and just name the figure they show.
enum WatchPhaseLabel {
    /// - Returns: `nil` when there is nothing worth saying, which renders as
    ///   blank space rather than a placeholder. The corner sits beside the
    ///   system clock, where a stale or filler label reads worse than nothing.
    static func text(phase: SessionPhase, isPaused: Bool) -> String? {
        switch phase {
        // Terminal first: a finished session is not "Paused" merely because
        // the flag was never cleared on the way out.
        case .notStarted, .completed:
            return nil
        case .run1, .rounds, .run2:
            // Paused outranks the phase. A user who paused and walked away
            // needs to see that from whichever page they happen to be on.
            guard !isPaused else { return "Paused" }
            switch phase {
            case .run1: return "Run 1"
            case .rounds: return "Rounds"
            case .run2: return "Run 2"
            default: return nil
            }
        }
    }
}
