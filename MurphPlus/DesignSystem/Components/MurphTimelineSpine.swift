// MurphPlus/DesignSystem/Components/MurphTimelineSpine.swift
// The completed recap's "timeline spine": a vertical bar down the left,
// split into Run 1 / Rounds / Run 2 sized by their real share of the total,
// with each segment's label/time/detail alongside it and a round-pace bar
// chart inside the rounds section. `recap.total`, the negative-split line
// and the personal-best delta are drawn by the caller above this component —
// this view only draws the spine itself.
import SwiftUI

struct MurphTimelineSpine: View {
    let recap: SessionRecap

    /// Matches `MurphBanner`'s `ruleWidth`: the spine is the same "accent
    /// rule beside content" shape, just split into proportional sections
    /// instead of painted as one flat color.
    private let barWidth: CGFloat = 6
    /// Gap between the bar's three sections, subtracted from the measured
    /// height before splitting it proportionally (see `sectionHeight`) so
    /// the gaps can never push the bar taller than the content beside it.
    private let sectionGap: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.space5) {
            ForEach(Array(recap.segments.enumerated()), id: \.offset) { index, segment in
                MurphTimelineSpineRow(
                    segment: segment,
                    roundSplits: index == 1 ? recap.roundSplits : [],
                    fastestRoundSeconds: recap.fastestRoundSeconds,
                    slowestRoundSeconds: recap.slowestRoundSeconds
                )
            }
        }
        .padding(.leading, barWidth + MurphSpacing.space3)
        // A background is proposed exactly this VStack's own resolved size,
        // never the container's greedy one (the same mechanism that fixed
        // `MurphBanner`'s rule in b1c1172) — so the `GeometryReader` below
        // reads a real, already-settled height instead of an unbounded one,
        // and the spine can never overflow or collapse past its own content.
        .background(alignment: .topLeading) {
            GeometryReader { geo in
                let usableHeight = max(0, geo.size.height - sectionGap * CGFloat(max(0, recap.segments.count - 1)))
                ZStack(alignment: .top) {
                    Rectangle().fill(MurphColor.ink700)
                    VStack(spacing: sectionGap) {
                        ForEach(Array(recap.segments.enumerated()), id: \.offset) { _, segment in
                            // Every section is the same muted tone: unlike the
                            // live ladder, a completed recap has no "current"
                            // or "ahead" row — the workout is over, so all
                            // three sections are equally "done".
                            Rectangle()
                                .fill(MurphColor.bone300)
                                .frame(height: max(0, usableHeight * segment.fraction))
                        }
                    }
                }
            }
            .frame(width: barWidth)
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

private struct MurphTimelineSpineRow: View {
    let segment: SessionRecap.Segment
    /// Non-empty only for the rounds row; empty everywhere else and for a
    /// legacy session with no per-round data.
    let roundSplits: [Double]
    let fastestRoundSeconds: Double?
    let slowestRoundSeconds: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.space2) {
            VStack(alignment: .leading, spacing: MurphSpacing.space1) {
                HStack {
                    Text(segment.label)
                        .murphType(.bodySm)
                        .foregroundStyle(MurphColor.textSecondary)
                    Spacer()
                    Text(segment.value)
                        .murphType(.metric(17))
                        .foregroundStyle(MurphColor.textPrimary)
                }
                if let detail = segment.detail {
                    Text(detail)
                        .murphType(.bodySm)
                        .foregroundStyle(MurphColor.textMuted)
                }
            }
            // Its own accessibility element and its own summary label — kept
            // out of the row's `.ignore` above it so a VoiceOver user gets
            // two stops for the rounds row (the sentence, then the chart's
            // summary) instead of the chart's facts being silently dropped
            // by the row's own `.ignore`.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)

            if !roundSplits.isEmpty {
                RoundPaceChart(
                    splits: roundSplits,
                    fastestSeconds: fastestRoundSeconds,
                    slowestSeconds: slowestRoundSeconds
                )
            }
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
        parts.append("done")
        return parts.joined(separator: ", ")
    }
}

/// The rounds section's pace bar chart: one bar per round, height scaled to
/// that round's share of the slowest round. Decorative detail layered on a
/// spoken summary, per the project's VoiceOver rule — twenty unlabelled bars
/// would be worse for a VoiceOver user than no chart at all, so the whole
/// chart is one element with one sentence, and the bars themselves carry no
/// individual accessibility.
private struct RoundPaceChart: View {
    let splits: [Double]
    let fastestSeconds: Double?
    let slowestSeconds: Double?

    /// Pinned so the `GeometryReader` inside has a determinate height on
    /// both axes rather than expanding into whatever unbounded space its
    /// container offers (the same bug class fixed in `MurphBanner`).
    private let chartHeight: CGFloat = MurphSpacing.space8

    var body: some View {
        GeometryReader { geo in
            let barWidth = max(1, (geo.size.width - MurphSpacing.space1 * CGFloat(max(0, splits.count - 1))) / CGFloat(splits.count))
            HStack(alignment: .bottom, spacing: MurphSpacing.space1) {
                ForEach(Array(splits.enumerated()), id: \.offset) { _, seconds in
                    RoundedRectangle(cornerRadius: MurphShape.radiusNone)
                        .fill(color(for: seconds))
                        .frame(width: barWidth, height: barHeight(for: seconds, containerHeight: geo.size.height))
                }
            }
        }
        .frame(height: chartHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Guards against an all-equal (or single-round) split list, where the
    /// slowest round would otherwise be a zero-height sliver.
    private func barHeight(for seconds: Double, containerHeight: CGFloat) -> CGFloat {
        guard let slowestSeconds, slowestSeconds > 0 else { return containerHeight }
        return max(2, containerHeight * CGFloat(seconds / slowestSeconds))
    }

    /// Highlighting exists to show spread. When the fastest and slowest
    /// round are exactly equal — every round tied, not just a one-round
    /// chart — there is no spread to point at, so neither extreme is
    /// highlighted and every bar renders neutral. (This equality check looks
    /// redundant next to the `==` checks below, since a tie makes both of
    /// those true for every bar too, but without it every bar would render
    /// lime "fastest" — telling the user all twenty rounds were
    /// simultaneously their fastest, which is not a fact about the session.)
    private func color(for seconds: Double) -> Color {
        guard let fastestSeconds, let slowestSeconds, fastestSeconds != slowestSeconds else {
            return MurphColor.bone300
        }
        if seconds == fastestSeconds { return MurphColor.lime500 }
        if seconds == slowestSeconds { return MurphColor.dust500 }
        return MurphColor.bone300
    }

    private var accessibilityLabel: String {
        var parts = ["\(splits.count) rounds"]
        if let fastestSeconds {
            let spoken = MirrorSpokenDuration.phrase(from: formatDuration(fastestSeconds)) ?? formatDuration(fastestSeconds)
            parts.append("fastest \(spoken)")
        }
        if let slowestSeconds {
            let spoken = MirrorSpokenDuration.phrase(from: formatDuration(slowestSeconds)) ?? formatDuration(slowestSeconds)
            parts.append("slowest \(spoken)")
        }
        return parts.joined(separator: ", ")
    }
}
