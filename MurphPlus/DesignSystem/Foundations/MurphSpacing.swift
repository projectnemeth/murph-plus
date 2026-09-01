// MurphPlus/DesignSystem/Foundations/MurphSpacing.swift
// Spacing tokens from the Murph+ Design System (tokens/spacing.css).
import CoreGraphics

enum MurphSpacing {
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 20
    static let space6: CGFloat = 24
    static let space8: CGFloat = 32
    static let space10: CGFloat = 40
    static let space12: CGFloat = 48
    static let space16: CGFloat = 64

    /// Phone edge margin.
    static let gutterScreen: CGFloat = 20
    /// Gap between stacked cards.
    static let gapStack: CGFloat = 12
    /// Gap between screen sections.
    static let gapSection: CGFloat = 28
    /// Minimum hit target.
    static let tapMin: CGFloat = 44
    /// Full-width primary action height.
    static let tapPrimary: CGFloat = 56
}
