// MurphPlus/DesignSystem/Components/HazardRule.swift
// Diagonal tape bar — the brand's one decorative motif. Use at most once per
// screen: under a screen title, or capping an empty state
// (components/core/HazardRule.jsx).
import SwiftUI

struct HazardRule: View {
    var height: CGFloat = 8
    var width: CGFloat? = 72

    var body: some View {
        canvas
    }

    @ViewBuilder
    private var canvas: some View {
        if let width {
            stripes.frame(width: width, height: height).clipped()
        } else {
            stripes.frame(height: height).frame(maxWidth: .infinity).clipped()
        }
    }

    private var stripes: some View {
        Canvas { context, size in
            let stripe: CGFloat = 8
            let period = stripe * 2
            let diagonalExtra = size.height
            var x: CGFloat = -diagonalExtra
            while x < size.width + diagonalExtra {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + diagonalExtra, y: 0))
                path.addLine(to: CGPoint(x: x + diagonalExtra + stripe, y: 0))
                path.addLine(to: CGPoint(x: x + stripe, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(MurphColor.hazard500))
                x += period
            }
        }
        .background(MurphColor.ink1000)
    }
}
