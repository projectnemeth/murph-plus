// MurphPlus/DesignSystem/Components/MurphSelectField.swift
// Template picker. Opens a panel of 44px rows; the selected row reads as
// chosen (components/forms/SelectField.jsx). Built on SwiftUI's native
// Menu so VoiceOver and Dynamic Type behave correctly; only the closed-field
// chrome is custom-styled to match the design system's field look.
import SwiftUI

struct MurphSelectOption: Identifiable, Hashable {
    let id: String
    let label: String
}

struct MurphSelectField: View {
    var label: String? = nil
    var placeholder: String = "Choose"
    let options: [MurphSelectOption]
    @Binding var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.space2) {
            if let label {
                Text(label)
                    .murphType(.micro)
                    .foregroundStyle(MurphColor.textMuted)
            }
            Menu {
                ForEach(options) { option in
                    Button {
                        selection = option.id
                    } label: {
                        if option.id == selection {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                HStack {
                    Text(currentLabel)
                        .murphType(.body)
                        .foregroundStyle(selection == nil ? MurphColor.textMuted : MurphColor.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MurphColor.textMuted)
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
            .menuOrder(.fixed)
        }
    }

    private var currentLabel: String {
        options.first { $0.id == selection }?.label ?? placeholder
    }
}
