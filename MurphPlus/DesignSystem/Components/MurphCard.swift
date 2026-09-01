// MurphPlus/DesignSystem/Components/MurphCard.swift
// The base panel. Flat ink surface, hairline border, 8px radius — never a
// soft drop shadow (components/core/Card.jsx).
import SwiftUI

enum MurphCardTone {
    case `default`
    case accent // one hazard panel per screen at most
}

struct MurphCard<Content: View>: View {
    var tone: MurphCardTone = .default
    var padded: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padded ? MurphSpacing.space4 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .foregroundStyle(foreground)
            .overlay(
                RoundedRectangle(cornerRadius: MurphShape.radiusMd)
                    .strokeBorder(tone == .accent ? .clear : MurphColor.lineHairline, lineWidth: MurphShape.borderHair)
            )
            .clipShape(RoundedRectangle(cornerRadius: MurphShape.radiusMd))
    }

    private var background: Color {
        tone == .accent ? MurphColor.hazard500 : MurphColor.surfaceCard
    }
    private var foreground: Color {
        tone == .accent ? MurphColor.textOnAccent : MurphColor.textPrimary
    }
}
