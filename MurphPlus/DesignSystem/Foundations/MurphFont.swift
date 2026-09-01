// MurphPlus/DesignSystem/Foundations/MurphFont.swift
// Typography tokens from the Murph+ Design System (tokens/typography.css,
// tokens/fonts.css). Three families, each with one job:
//   - Archivo Black (display): screen titles, empty-state headlines, round numerals.
//   - DM Sans (body): prose and control labels.
//   - Martian Mono (mono): every number, plus micro labels and button text.
//
// DM Sans and Martian Mono ship from Google Fonts as single variable TTFs
// (axes: DM Sans "wght"+"opsz", Martian Mono "wght"). SwiftUI's Font.custom
// only ever addresses a font's default named instance, so intermediate
// weights are reached with a UIFontDescriptor variation dictionary instead.
import SwiftUI
import UIKit

private enum VariableAxis {
    // Four-byte OpenType axis tags packed big-endian, as CoreText expects them.
    static let weight: UInt32 = 0x77676874 // 'wght'
    static let opticalSize: UInt32 = 0x6F70737A // 'opsz'
}

private let variationAttributeKey = UIFontDescriptor.AttributeName(rawValue: "NSCTFontVariationAttribute")

private extension UIFont {
    static func murphVariable(base postscriptName: String, size: CGFloat, variations: [UInt32: CGFloat]) -> UIFont {
        guard let base = UIFont(name: postscriptName, size: size) else {
            return .systemFont(ofSize: size)
        }
        let descriptor = base.fontDescriptor.addingAttributes([
            variationAttributeKey: variations
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}

enum MurphFontWeight {
    static let regular: CGFloat = 400
    static let medium: CGFloat = 500
    static let semiBold: CGFloat = 600
    static let bold: CGFloat = 700
    static let extraBold: CGFloat = 800
}

/// The three type families, addressed by weight (DM Sans / Martian Mono are
/// variable fonts bundled as a single file each; Archivo Black is a single
/// static weight, matching the source design system).
enum MurphFontFamily {
    static func display(_ size: CGFloat) -> Font {
        .custom("Archivo Black", size: size)
    }

    static func body(_ size: CGFloat, weight: CGFloat = MurphFontWeight.regular) -> Font {
        Font(UIFont.murphVariable(
            base: "DMSans-9ptRegular",
            size: size,
            variations: [
                VariableAxis.weight: weight,
                VariableAxis.opticalSize: min(max(size, 9), 40),
            ]
        ))
    }

    static func mono(_ size: CGFloat, weight: CGFloat = MurphFontWeight.regular) -> Font {
        Font(UIFont.murphVariable(
            base: "MartianMono-SemiExpandedRegular",
            size: size,
            variations: [VariableAxis.weight: weight]
        ))
    }
}

/// One named style per `--type-*` token. Each carries its own tracking
/// (converted from CSS em to points) and whether it renders uppercase.
struct MurphTypeStyle {
    let font: Font
    let tracking: CGFloat
    let uppercase: Bool

    static func display1(_ size: CGFloat = 64) -> MurphTypeStyle {
        MurphTypeStyle(font: MurphFontFamily.display(size), tracking: -0.02 * size, uppercase: true)
    }
    static func display2(_ size: CGFloat = 44) -> MurphTypeStyle {
        MurphTypeStyle(font: MurphFontFamily.display(size), tracking: -0.02 * size, uppercase: true)
    }
    static func display3(_ size: CGFloat = 30) -> MurphTypeStyle {
        MurphTypeStyle(font: MurphFontFamily.display(size), tracking: -0.02 * size, uppercase: true)
    }
    static func title(_ size: CGFloat = 22) -> MurphTypeStyle {
        MurphTypeStyle(font: MurphFontFamily.display(size), tracking: -0.02 * size, uppercase: true)
    }

    static let bodyLg = MurphTypeStyle(font: MurphFontFamily.body(17), tracking: 0, uppercase: false)
    static let body = MurphTypeStyle(font: MurphFontFamily.body(15), tracking: 0, uppercase: false)
    static let bodySm = MurphTypeStyle(font: MurphFontFamily.body(13), tracking: 0, uppercase: false)
    static let label = MurphTypeStyle(font: MurphFontFamily.body(14, weight: MurphFontWeight.semiBold), tracking: 0, uppercase: false)

    static func clock(_ size: CGFloat = 56) -> MurphTypeStyle {
        MurphTypeStyle(font: MurphFontFamily.mono(size, weight: MurphFontWeight.extraBold), tracking: -0.04 * size, uppercase: false)
    }
    static func metric(_ size: CGFloat = 22) -> MurphTypeStyle {
        MurphTypeStyle(font: MurphFontFamily.mono(size, weight: MurphFontWeight.semiBold), tracking: 0, uppercase: false)
    }
    static let micro = MurphTypeStyle(font: MurphFontFamily.mono(10, weight: MurphFontWeight.semiBold), tracking: 0.14 * 10, uppercase: true)
    static let tag = MurphTypeStyle(font: MurphFontFamily.mono(11, weight: MurphFontWeight.extraBold), tracking: 0.08 * 11, uppercase: true)
}

private struct MurphTextStyleModifier: ViewModifier {
    let style: MurphTypeStyle
    func body(content: Content) -> some View {
        content
            .font(style.font)
            .tracking(style.tracking)
            .textCase(style.uppercase ? .uppercase : nil)
    }
}

extension View {
    func murphType(_ style: MurphTypeStyle) -> some View {
        modifier(MurphTextStyleModifier(style: style))
    }
}
