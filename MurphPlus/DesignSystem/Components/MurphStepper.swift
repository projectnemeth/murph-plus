// MurphPlus/DesignSystem/Components/MurphStepper.swift
// Numeric stepper for rep totals, run distance and round count
// (components/forms/Stepper.jsx). Stepper keys use minus/plus glyphs in
// mono type, not icon files, matching the SwiftUI Stepper it recreates.
import SwiftUI

struct MurphStepper: View {
    let label: String
    @Binding var value: Double
    var display: String? = nil
    var step: Double = 1
    var minValue: Double = 0
    var maxValue: Double = .infinity

    var body: some View {
        HStack(spacing: MurphSpacing.space3) {
            Text(label)
                .murphType(.body)
                .foregroundStyle(MurphColor.textPrimary)
                .lineLimit(1)
            Spacer(minLength: MurphSpacing.space2)
            key("\u{2212}") { adjust(by: -step) } // − (minus sign, not hyphen)
                .disabled(value <= minValue)
            Text(display ?? String(Int(value)))
                .murphType(.metric(16))
                .foregroundStyle(MurphColor.textPrimary)
                .frame(minWidth: 64)
                .multilineTextAlignment(.center)
            key("+") { adjust(by: step) }
                .disabled(value >= maxValue)
        }
        .padding(.horizontal, MurphSpacing.space3)
        .frame(height: MurphSpacing.tapMin)
        .background(MurphColor.surfaceRaised)
        .overlay(
            RoundedRectangle(cornerRadius: MurphShape.radiusSm)
                .strokeBorder(MurphColor.lineHairline, lineWidth: MurphShape.borderHair)
        )
        .clipShape(RoundedRectangle(cornerRadius: MurphShape.radiusSm))
    }

    private func adjust(by delta: Double) {
        withAnimation(MurphMotion.snap()) {
            value = min(max(value + delta, minValue), maxValue)
        }
    }

    private func key(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .murphType(.metric(16))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(MurphColor.textPrimary)
    }
}

extension MurphStepper {
    init(label: String, intValue: Binding<Int>, display: String? = nil, step: Int = 1, min minValue: Int = 0, max maxValue: Int = .max) {
        self.init(
            label: label,
            value: Binding(
                get: { Double(intValue.wrappedValue) },
                set: { intValue.wrappedValue = Int($0) }
            ),
            display: display,
            step: Double(step),
            minValue: Double(minValue),
            maxValue: Double(maxValue)
        )
    }
}
