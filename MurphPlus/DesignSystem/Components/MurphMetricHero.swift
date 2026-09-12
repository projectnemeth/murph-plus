// MurphPlus/DesignSystem/Components/MurphMetricHero.swift
// The live-run hero slot: whichever figure `RunHeroMetric` decided is worth
// reading mid-stride, drawn as large as the screen allows. This view only
// draws what it's handed — the distance-vs-elapsed call, the caption, and
// the progress fraction all live in `RunHeroMetric` so they can be tested
// without a simulator.
//
// `running` is a separate parameter rather than a field on `RunHeroMetric`
// for the same reason `MurphClock` takes its own flag: whether the clock is
// currently live is view state, not part of the number-and-caption decision,
// and folding it in would force every non-visual call site (and Task 1's
// tests) to fake a UI concern they don't have.
import SwiftUI

struct MurphMetricHero: View {
    let metric: RunHeroMetric
    var running: Bool = false
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.space2) {
            HStack(spacing: MurphSpacing.space1 + 2) {
                if running {
                    HazardPulseDot(size: 6)
                }
                Text(metric.label)
                    .murphType(.micro)
                    .foregroundStyle(MurphColor.textMuted)
                Spacer()
                if let note {
                    Text(note)
                        .murphType(.micro)
                        .foregroundStyle(MurphColor.textMuted)
                }
            }

            // 96pt is the largest the design calls for and the common
            // 4-glyph reading ("0.12") clears it on the narrowest supported
            // iPhone without touching minimumScaleFactor — this is here only
            // for the rare 6-glyph duration ("125:30") that would otherwise
            // clip or wrap.
            Text(metric.value)
                .murphType(.clock(96))
                .foregroundStyle(MurphColor.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            if let caption = metric.caption {
                Text(caption)
                    .murphType(.micro)
                    .foregroundStyle(MurphColor.textMuted)
            }

            if let progress = metric.progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: MurphShape.radiusSm)
                            .fill(MurphColor.ink700)
                        RoundedRectangle(cornerRadius: MurphShape.radiusSm)
                            .fill(MurphColor.hazard500)
                            .frame(width: geometry.size.width * progress)
                            .animation(MurphMotion.easeOut, value: progress)
                    }
                }
                .frame(height: 8)
            }
        }
        // One sentence, not four fragments: VoiceOver would otherwise read
        // the label, the numeral, the caption and the bar's percentage as
        // four separate stops.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.accessibilityText)
    }
}
