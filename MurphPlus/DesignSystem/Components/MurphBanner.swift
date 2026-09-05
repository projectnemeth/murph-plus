// MurphPlus/DesignSystem/Components/MurphBanner.swift
// Inline note sitting next to the thing it explains — validation errors,
// prediction caveats (components/feedback/Banner.jsx).
import SwiftUI

enum MurphBannerTone {
    case error, warn, info

    var accent: Color {
        switch self {
        case .error: MurphColor.blood500
        case .warn: MurphColor.dust500
        case .info: MurphColor.ash300
        }
    }
}

struct MurphBanner: View {
    var tone: MurphBannerTone = .info
    let text: String
    /// A trailing chevron, for a banner that is really a control.
    ///
    /// The live-mirror banner was already inside a `NavigationLink` and read as
    /// flat text — it said "Tap to follow along" and testers did not tap it.
    /// The words were never the problem; nothing about the shape said it could
    /// be pressed.
    var navigates: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: MurphSpacing.space3) {
            Rectangle().fill(tone.accent).frame(width: 3)
            Text(text)
                .murphType(.bodySm)
                .foregroundStyle(MurphColor.textSecondary)
            if navigates {
                Spacer(minLength: MurphSpacing.space2)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MurphColor.textMuted)
            }
        }
        .padding(.vertical, MurphSpacing.space2)
        .padding(.trailing, MurphSpacing.space3)
        .background(MurphColor.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: MurphShape.radiusSm))
    }
}
