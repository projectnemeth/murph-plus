// MurphPlus/DesignSystem/Components/MurphClock.swift
// One continuous elapsed clock, as the app models it — never a per-phase
// countdown (components/data/Clock.jsx). `sm` is the inline size for split
// rows; `lg` is the live-session hero.
import SwiftUI

enum MurphClockSize {
    case sm, md, lg

    var fontSize: CGFloat {
        switch self {
        case .sm: 22
        case .md: 40
        case .lg: 56
        }
    }
}

enum MurphClockTone {
    case `default`, accent
}

struct MurphClock: View {
    var label: String? = nil
    let seconds: Double
    var size: MurphClockSize = .lg
    var running: Bool = false
    var tone: MurphClockTone = .default

    var body: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.space1) {
            if let label {
                HStack(spacing: MurphSpacing.space1 + 2) {
                    if running {
                        HazardPulseDot(size: 6)
                    }
                    Text(label)
                        .murphType(.micro)
                        .foregroundStyle(MurphColor.textMuted)
                }
            }
            Text(formatDuration(seconds))
                .murphType(.clock(size.fontSize))
                .foregroundStyle(tone == .accent ? MurphColor.hazard500 : MurphColor.textPrimary)
                .monospacedDigit()
        }
    }
}
