// MurphPlus/DesignSystem/Components/MurphButton.swift
// Pill action button in the Murph+ voice — uppercase mono label, hazard fill,
// hard offset shadow that collapses on press (components/core/Button.jsx).
import SwiftUI

enum MurphButtonVariant {
    case primary   // hazard, one per screen
    case secondary // bone outline
    case ghost     // bare, for tertiary rows
    case danger    // blood outline — Abandon, Delete
    case inverse   // bone fill on a hazard panel

    var background: Color {
        switch self {
        case .primary: MurphColor.hazard500
        case .secondary, .ghost, .danger: .clear
        case .inverse: MurphColor.bone100
        }
    }
    var foreground: Color {
        switch self {
        case .primary: MurphColor.textOnAccent
        case .secondary: MurphColor.textPrimary
        case .ghost: MurphColor.textSecondary
        case .danger: MurphColor.blood500
        case .inverse: MurphColor.textInverse
        }
    }
    var border: Color {
        switch self {
        case .primary: MurphColor.hazard500
        case .secondary: MurphColor.bone100
        case .ghost: .clear
        case .danger: MurphColor.blood500
        case .inverse: MurphColor.bone100
        }
    }
    var stampColor: Color? {
        switch self {
        case .primary: MurphColor.ink1000
        case .inverse: MurphColor.hazard600
        case .secondary, .ghost, .danger: nil
        }
    }
}

enum MurphButtonSize {
    case sm, md, lg

    var height: CGFloat {
        switch self {
        case .sm: 36
        case .md: MurphSpacing.tapMin
        case .lg: MurphSpacing.tapPrimary
        }
    }
    var horizontalPadding: CGFloat {
        switch self {
        case .sm: MurphSpacing.space4
        case .md: MurphSpacing.space6
        case .lg: MurphSpacing.space8
        }
    }
    var fontSize: CGFloat {
        switch self {
        case .sm: 10
        case .md: 11
        case .lg: 13
        }
    }
}

struct MurphButtonStyle: ButtonStyle {
    var variant: MurphButtonVariant = .primary
    var size: MurphButtonSize = .md
    var full: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        MurphButtonBody(configuration: configuration, variant: variant, size: size, full: full)
    }

    private struct MurphButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let variant: MurphButtonVariant
        let size: MurphButtonSize
        let full: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let pressed = configuration.isPressed && isEnabled
            let typeStyle = MurphTypeStyle(
                font: MurphFontFamily.mono(size.fontSize, weight: MurphFontWeight.extraBold),
                tracking: 0.08 * size.fontSize,
                uppercase: true
            )

            configuration.label
                .murphType(typeStyle)
                .lineLimit(1)
                .padding(.horizontal, size.horizontalPadding)
                .frame(height: size.height)
                .frame(maxWidth: full ? .infinity : nil)
                .foregroundStyle(variant.foreground)
                .background(variant.background)
                .overlay(
                    Capsule().strokeBorder(variant.border, lineWidth: MurphShape.borderStrong)
                )
                .clipShape(Capsule())
                .background(alignment: .center) {
                    if let stampColor, isEnabled {
                        Capsule()
                            .fill(stampColor)
                            .offset(x: MurphShape.stampOffset.width, y: MurphShape.stampOffset.height)
                    }
                }
                .opacity(isEnabled ? 1 : 0.35)
                .scaleEffect(pressed ? MurphMotion.pressScale : 1)
                .offset(x: pressed ? MurphShape.stampOffset.width : 0, y: pressed ? MurphShape.stampOffset.height : 0)
                .animation(MurphMotion.snap(), value: pressed)
        }

        private var stampColor: Color? { variant.stampColor }
    }
}

struct MurphButton: View {
    var variant: MurphButtonVariant = .primary
    var size: MurphButtonSize = .md
    var full: Bool = false
    var icon: Image? = nil
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MurphSpacing.space2) {
                icon
                Text(title)
            }
        }
        .buttonStyle(MurphButtonStyle(variant: variant, size: size, full: full))
    }
}
