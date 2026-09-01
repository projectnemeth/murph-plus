// MurphPlus/DesignSystem/Foundations/MurphColor.swift
// Color tokens from the Murph+ Design System (tokens/colors.css).
import SwiftUI

extension Color {
    init(murphHex hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum MurphColor {
    // MARK: - Base: ink & bone
    static let ink1000 = Color(murphHex: 0x08080A)
    static let ink900 = Color(murphHex: 0x0E0E11)
    static let ink800 = Color(murphHex: 0x16161A)
    static let ink700 = Color(murphHex: 0x1F1F25)
    static let ink600 = Color(murphHex: 0x2C2C34)
    static let ink500 = Color(murphHex: 0x3D3D47)
    static let ash400 = Color(murphHex: 0x585863)
    static let ash300 = Color(murphHex: 0x7A7A86)
    static let ash200 = Color(murphHex: 0xA6A6B0)
    static let bone100 = Color(murphHex: 0xF5F2EA)
    static let bone200 = Color(murphHex: 0xE7E2D6)
    static let bone300 = Color(murphHex: 0xD4CEBE)

    // MARK: - Brand accents
    static let hazard500 = Color(murphHex: 0xFF5A1F)
    static let hazard600 = Color(murphHex: 0xE04512)
    static let hazard400 = Color(murphHex: 0xFF7B4D)
    static let hazard100 = Color(murphHex: 0xFFE3D6)
    static let lime500 = Color(murphHex: 0xC6F135)
    static let lime600 = Color(murphHex: 0xA9D419)
    static let lime100 = Color(murphHex: 0xEEFBC4)
    static let dust500 = Color(murphHex: 0xF2C14E)
    static let dust600 = Color(murphHex: 0xD8A32C)
    static let blood500 = Color(murphHex: 0xE0343C)
    static let blood600 = Color(murphHex: 0xBE212A)

    // MARK: - Semantic: surfaces
    static let surfacePage = ink1000
    static let surfaceCard = ink900
    static let surfaceRaised = ink800
    static let surfaceSunken = Color(murphHex: 0x050506)
    static let surfaceInverse = bone100
    static let surfaceAccent = hazard500

    // MARK: - Semantic: text
    static let textPrimary = bone100
    static let textSecondary = ash200
    static let textMuted = ash300
    static let textAccent = hazard500
    static let textOnAccent = ink1000
    static let textInverse = ink1000

    // MARK: - Semantic: lines
    static let lineHairline = ink700
    static let lineStrong = ink600
    static let lineAccent = hazard500
    static let lineInverse = ink1000

    // MARK: - Semantic: status
    static let statusComplete = lime500
    static let statusAbandoned = dust500
    static let statusLive = hazard500
    static let statusDanger = blood500
    static let statusPR = lime500

    // MARK: - Focus
    static let focusRing = hazard500
}
