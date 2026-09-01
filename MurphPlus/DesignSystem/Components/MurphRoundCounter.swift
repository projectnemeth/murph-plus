// MurphPlus/DesignSystem/Components/MurphRoundCounter.swift
// Where you are in a Cindy-style Murph. Zero-padded display numeral, ticks
// below (components/data/RoundCounter.jsx). Ticks: lime = done, hazard =
// current, ink = ahead.
import SwiftUI

struct MurphRoundCounter: View {
    let current: Int
    let total: Int
    let repsLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.space4) {
            VStack(alignment: .leading, spacing: MurphSpacing.space1) {
                Text("Round \(String(format: "%02d", current)) of \(String(format: "%02d", total))")
                    .murphType(.micro)
                    .foregroundStyle(MurphColor.textMuted)
                Text(String(format: "%02d", current))
                    .murphType(.display1(72))
                    .foregroundStyle(MurphColor.textPrimary)
                Text(repsLabel)
                    .murphType(.bodySm)
                    .foregroundStyle(MurphColor.textSecondary)
            }

            HStack(spacing: 3) {
                ForEach(1...max(total, 1), id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(tickColor(for: index))
                        .frame(height: 4)
                }
            }
        }
    }

    private func tickColor(for index: Int) -> Color {
        if index < current { MurphColor.lime500 }
        else if index == current { MurphColor.hazard500 }
        else { MurphColor.ink700 }
    }
}
