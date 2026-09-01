// MurphPlus/DesignSystem/Components/MurphToggle.swift
// Switch row. The vest toggle is its canonical use
// (components/forms/Toggle.jsx).
import SwiftUI

struct MurphToggle: View {
    let label: String
    var description: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: MurphSpacing.space1) {
                Text(label)
                    .murphType(.body)
                    .foregroundStyle(MurphColor.textPrimary)
                if let description {
                    Text(description)
                        .murphType(.bodySm)
                        .foregroundStyle(MurphColor.textMuted)
                }
            }
            Spacer(minLength: MurphSpacing.space3)
            Toggle("", isOn: $isOn.animation(MurphMotion.snap()))
                .labelsHidden()
                .tint(MurphColor.hazard500)
        }
        .padding(MurphSpacing.space4)
        .background(MurphColor.surfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: MurphShape.radiusMd)
                .strokeBorder(MurphColor.lineHairline, lineWidth: MurphShape.borderHair)
        )
        .clipShape(RoundedRectangle(cornerRadius: MurphShape.radiusMd))
    }
}
