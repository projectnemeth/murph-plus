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

    var body: some View {
        HStack(alignment: .top, spacing: MurphSpacing.space3) {
            Rectangle().fill(tone.accent).frame(width: 3)
            Text(text)
                .murphType(.bodySm)
                .foregroundStyle(MurphColor.textSecondary)
        }
        .padding(.vertical, MurphSpacing.space2)
        .padding(.trailing, MurphSpacing.space3)
        .background(MurphColor.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: MurphShape.radiusSm))
    }
}
