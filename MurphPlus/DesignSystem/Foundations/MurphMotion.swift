// MurphPlus/DesignSystem/Foundations/MurphMotion.swift
// Motion tokens from the Murph+ Design System (tokens/motion.css). Fast and
// mechanical — no bounce, no spring overshoot, no fades longer than 220ms.
import SwiftUI

enum MurphMotion {
    static let easeSnap = Animation.timingCurve(0.2, 0.9, 0.25, 1.0, duration: durBase)
    static let easeOut = Animation.timingCurve(0.16, 1.0, 0.3, 1.0, duration: durBase)
    static let easeInOut = Animation.timingCurve(0.65, 0, 0.35, 1.0, duration: durBase)

    static let durInstant: Double = 0.08
    static let durFast: Double = 0.14
    static let durBase: Double = 0.22
    static let durSlow: Double = 0.42

    /// Press-down scale for buttons and tappable rows.
    static let pressScale: CGFloat = 0.97

    /// Live-clock hazard dot pulse — a hard blink (steps(2,end)), not a fade.
    static let tickPulse: Double = 1.0

    static func snap(_ duration: Double = durInstant) -> Animation {
        .timingCurve(0.2, 0.9, 0.25, 1.0, duration: duration)
    }
}

/// A hard on/off blink, matching CSS `steps(2,end)` — never a smooth fade.
struct HazardPulseDot: View {
    var size: CGFloat = 6
    var color: Color = MurphColor.hazard500

    var body: some View {
        TimelineView(.periodic(from: .now, by: MurphMotion.tickPulse / 2)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / (MurphMotion.tickPulse / 2))
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .opacity(tick.isMultiple(of: 2) ? 1 : 0.35)
        }
    }
}
