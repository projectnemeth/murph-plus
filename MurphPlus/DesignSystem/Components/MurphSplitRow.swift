// MurphPlus/DesignSystem/Components/MurphSplitRow.swift
// Split breakdown row in session detail / live session. Bars are relative
// within one session only (components/data/SplitRow.jsx).
import SwiftUI

enum MurphSplitRowTone {
    case `default`, accent
}

struct MurphSplitRow: View {
    let label: String
    let value: String
    var fraction: Double? = nil
    var tone: MurphSplitRowTone = .default

    var body: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.space1) {
            HStack {
                Text(label)
                    .murphType(.bodySm)
                    .foregroundStyle(MurphColor.textSecondary)
                Spacer()
                Text(value)
                    .murphType(.metric(17))
                    .foregroundStyle(MurphColor.textPrimary)
            }
            if let fraction {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(MurphColor.ink700)
                        Rectangle()
                            .fill(tone == .accent ? MurphColor.hazard500 : MurphColor.bone300)
                            .frame(width: geo.size.width * max(0, min(1, fraction)))
                    }
                }
                .frame(height: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
        .padding(.vertical, MurphSpacing.space2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MurphColor.lineHairline).frame(height: MurphShape.borderHair)
        }
    }
}
