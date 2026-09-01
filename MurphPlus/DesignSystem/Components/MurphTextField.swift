// MurphPlus/DesignSystem/Components/MurphTextField.swift
// Text / numeric entry. Vest weight, template name
// (components/forms/TextField.jsx). Pass `invalid` with `hint` for
// validation copy — the hint turns blood red.
import SwiftUI

struct MurphTextField: View {
    var label: String? = nil
    @Binding var text: String
    var placeholder: String = ""
    var suffix: String? = nil
    var keyboardType: UIKeyboardType = .default
    var invalid: Bool = false
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.space2) {
            if let label {
                Text(label)
                    .murphType(.micro)
                    .foregroundStyle(MurphColor.textMuted)
            }
            HStack(spacing: MurphSpacing.space2) {
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(MurphColor.textMuted))
                    .murphType(.body)
                    .foregroundStyle(MurphColor.textPrimary)
                    .keyboardType(keyboardType)
                    .textCase(nil)
                if let suffix {
                    Text(suffix)
                        .murphType(.bodySm)
                        .foregroundStyle(MurphColor.textMuted)
                }
            }
            .padding(.horizontal, MurphSpacing.space3)
            .frame(height: MurphSpacing.tapMin)
            .background(MurphColor.surfaceRaised)
            .overlay(
                RoundedRectangle(cornerRadius: MurphShape.radiusSm)
                    .strokeBorder(invalid ? MurphColor.blood500 : MurphColor.lineHairline, lineWidth: MurphShape.borderHair)
            )
            .clipShape(RoundedRectangle(cornerRadius: MurphShape.radiusSm))

            if let hint {
                Text(hint)
                    .murphType(.bodySm)
                    .foregroundStyle(invalid ? MurphColor.blood500 : MurphColor.textMuted)
            }
        }
    }
}
