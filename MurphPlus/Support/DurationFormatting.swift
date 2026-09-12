// MurphPlus/Support/DurationFormatting.swift
import Foundation

/// e.g. "8:42" — what the eye reads: a live clock, a split, a recap value.
func formatDuration(_ seconds: Double) -> String {
    let total = Int(max(0, seconds))
    return String(format: "%d:%02d", total / 60, total % 60)
}

/// Turns a `formatDuration` string ("8:42") into VoiceOver's spoken form
/// ("8 minutes 42 seconds") — what the ear hears, not what the eye reads.
/// Deliberately kept separate from `formatDuration` rather than folded into
/// one function: a visual caller has no use for the spoken form, and
/// collapsing the two would leave VoiceOver reading the visual form
/// digit-by-digit as "eight colon four two" instead of a real duration.
/// There was no existing spoken-duration precedent elsewhere in the app when
/// this was added — `MurphSegmentLadder` and `MurphTimelineSpine` are the
/// first screens to put a duration inside an accessibility label.
enum MirrorSpokenDuration {
    /// `nil` for anything that isn't exactly "M:SS" — in particular the
    /// live ladder's own "\u{2014}" placeholder for a segment that hasn't
    /// started, which must be omitted from a sentence entirely, never
    /// spoken as "em dash".
    static func phrase(from value: String) -> String? {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let minutes = Int(parts[0]), minutes >= 0,
              let seconds = Int(parts[1]), seconds >= 0
        else { return nil }

        func unit(_ count: Int, _ name: String) -> String {
            "\(count) \(name)\(count == 1 ? "" : "s")"
        }

        if minutes == 0 { return unit(seconds, "second") }
        if seconds == 0 { return unit(minutes, "minute") }
        return "\(unit(minutes, "minute")) \(unit(seconds, "second"))"
    }
}
