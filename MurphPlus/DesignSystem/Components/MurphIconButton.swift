// MurphPlus/DesignSystem/Components/MurphIconButton.swift
// Icon-only tap target for chrome: month arrows, close, back
// (components/core/IconButton.jsx).
import SwiftUI

enum MurphIconButtonVariant {
    case ghost    // default
    case outline  // needs to read as a control on a dark card
    case solid    // a floating primary only
}

struct MurphIconButton: View {
    var variant: MurphIconButtonVariant = .ghost
    var label: String
    var systemImage: String
    var size: CGFloat = 20
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .frame(width: MurphSpacing.tapMin, height: MurphSpacing.tapMin)
                .foregroundStyle(foreground)
                .background(background)
                .overlay(
                    Circle().strokeBorder(border, lineWidth: variant == .outline ? MurphShape.borderHair : 0)
                )
                .clipShape(Circle())
        }
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(label)
    }

    private var foreground: Color {
        variant == .solid ? MurphColor.textOnAccent : MurphColor.textPrimary
    }
    private var background: Color {
        variant == .solid ? MurphColor.hazard500 : .clear
    }
    private var border: Color {
        variant == .outline ? MurphColor.lineHairline : .clear
    }
}
