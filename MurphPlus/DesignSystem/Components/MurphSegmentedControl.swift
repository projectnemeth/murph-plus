// MurphPlus/DesignSystem/Components/MurphSegmentedControl.swift
// Pill segmented switch; active segment is bone-on-ink. Two or three
// segments only (components/forms/SegmentedControl.jsx).
import SwiftUI

struct MurphSegmentedControl: View {
    let options: [String]
    @Binding var selection: String
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(MurphMotion.snap()) { selection = option }
                } label: {
                    Text(option)
                        .murphType(.tag)
                        .foregroundStyle(selected ? MurphColor.textInverse : MurphColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(MurphColor.bone100)
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(MurphColor.surfaceRaised)
        .clipShape(Capsule())
    }
}
