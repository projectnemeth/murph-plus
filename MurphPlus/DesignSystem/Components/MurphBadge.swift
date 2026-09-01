// MurphPlus/DesignSystem/Components/MurphBadge.swift
// Status and metadata tag — mono, uppercase, 22px tall
// (components/core/Badge.jsx). Tones map to real session states.
import SwiftUI

enum MurphBadgeTone {
    case live      // the active session
    case complete
    case abandoned
    case pr        // filled lime, only for a personal best
    case vest
    case neutral

    var textColor: Color {
        switch self {
        case .live: MurphColor.hazard500
        case .complete: MurphColor.lime500
        case .abandoned: MurphColor.dust500
        case .pr: MurphColor.textInverse
        case .vest, .neutral: MurphColor.textSecondary
        }
    }
    var fill: Color? {
        self == .pr ? MurphColor.lime500 : nil
    }
    var dotColor: Color? {
        switch self {
        case .live: MurphColor.hazard500
        case .complete: MurphColor.lime500
        case .abandoned: MurphColor.dust500
        case .pr, .vest, .neutral: nil
        }
    }
}

struct MurphBadge: View {
    var tone: MurphBadgeTone = .neutral
    var dot: Bool = false
    let title: String

    var body: some View {
        HStack(spacing: MurphSpacing.space1 + 2) {
            if dot, tone == .live {
                HazardPulseDot(size: 6, color: MurphColor.hazard500)
            } else if dot, let dotColor = tone.dotColor {
                Circle().fill(dotColor).frame(width: 6, height: 6)
            }
            Text(title)
        }
        .murphType(.tag)
        .foregroundStyle(tone.textColor)
        .padding(.horizontal, MurphSpacing.space2 + 2)
        .frame(height: 22)
        .background(tone.fill ?? .clear)
        .overlay(
            Capsule().strokeBorder(tone.fill == nil ? MurphColor.lineHairline : .clear, lineWidth: MurphShape.borderHair)
        )
        .clipShape(Capsule())
    }
}
