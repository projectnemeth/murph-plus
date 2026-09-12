// MurphPlus/DesignSystem/Components/MurphSegmentLadder.swift
// The live mirror's three-row ladder — Run 1, Rounds, Run 2 — each showing
// its value, an optional detail, and its own share-of-elapsed bar, tinted by
// where that row sits relative to the runner right now.
import SwiftUI

/// Turns a `formatDuration` string ("8:42") into VoiceOver's spoken form
/// ("8 minutes 42 seconds"), so a duration is never read digit-by-digit as
/// "eight colon four two". There is no existing spoken-duration precedent
/// elsewhere in this app to follow — this is the first place a formatted
/// duration reaches an accessibility label — so this helper is new, not
/// copied. Not `private`: `MurphTimelineSpine` needs the same conversion for
/// its own segment rows and its round-pace chart's summary, and duplicating
/// it there would risk the two components quietly disagreeing about how a
/// duration is spoken.
enum MirrorSpokenDuration {
    /// `nil` for anything that isn't exactly "M:SS" — in particular the
    /// ladder's own "\u{2014}" placeholder for a segment that hasn't started,
    /// which must be omitted from the sentence entirely, never spoken as
    /// "em dash".
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

struct MurphSegmentLadder: View {
    let segments: [MirrorSegment]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                MurphSegmentLadderRow(segment: segment)
            }
        }
    }
}

/// Not `MurphSplitRow`: that component is label + value + one optional bar,
/// used by five other screens, and shouldn't grow a third detail line and a
/// per-state tone just for this one caller. This row instead copies
/// `MurphSplitRow`'s exact metrics — `.bodySm`/`textSecondary` label,
/// `.metric(17)` value, a 4pt bar over an `ink700` track, the same `2`pt
/// corner radius — so the two read as one family.
private struct MurphSegmentLadderRow: View {
    let segment: MirrorSegment

    var body: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.space1) {
            HStack {
                Text(segment.label)
                    .murphType(.bodySm)
                    .foregroundStyle(tone)
                Spacer()
                Text(segment.value)
                    .murphType(.metric(17))
                    .foregroundStyle(tone)
            }
            if let detail = segment.detail {
                Text(detail)
                    .murphType(.bodySm)
                    .foregroundStyle(tone)
            }
            // GeometryReader here is pinned to a 4pt height right after —
            // the same shape of bug `MurphBanner` had (b1c1172): an
            // unconstrained `Rectangle` axis is greedy, so both the reader
            // and the fill inside it need an explicit frame rather than
            // relying on the VStack around them to bound it.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(MurphColor.ink700)
                    Rectangle()
                        .fill(barTone)
                        .frame(width: geo.size.width * segment.fraction)
                }
            }
            .frame(height: 4)
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .padding(.vertical, MurphSpacing.space2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MurphColor.lineHairline).frame(height: MurphShape.borderHair)
        }
        // One sentence per row, not four fragments — a done row must read
        // "Run 1, 8 minutes 42 seconds, 1.02 miles, done", not the label,
        // the value, the detail and the bar's fraction as four separate
        // VoiceOver stops.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Text tone: muted for a finished row, hazard for the one happening
    /// now, dimmest (`ash400`) for a row not yet reached — the whole row
    /// carries the tone, not just its value, so the state reads at a glance
    /// without needing to parse the numbers.
    private var tone: Color {
        switch segment.state {
        case .done: MurphColor.textSecondary
        case .current: MurphColor.hazard500
        case .ahead: MurphColor.ash400
        }
    }

    /// The bar's fill echoes the row's tone, except `.done`: its text is
    /// `textSecondary` but its bar reuses `MurphSplitRow`'s own muted fill
    /// (`bone300`) rather than a second gray, so a finished row's bar still
    /// reads as "the same kind of bar" as every other split bar in the app.
    private var barTone: Color {
        switch segment.state {
        case .done: MurphColor.bone300
        case .current: MurphColor.hazard500
        case .ahead: MurphColor.ash400
        }
    }

    private var stateWord: String {
        switch segment.state {
        case .done: "done"
        case .current: "in progress"
        case .ahead: "not started"
        }
    }

    private var accessibilityLabel: String {
        var parts = [segment.label]
        if let spoken = MirrorSpokenDuration.phrase(from: segment.value) {
            parts.append(spoken)
        }
        if let detail = segment.detail {
            parts.append(detail)
        }
        parts.append(stateWord)
        return parts.joined(separator: ", ")
    }
}
