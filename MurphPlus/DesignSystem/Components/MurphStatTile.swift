// MurphPlus/DesignSystem/Components/MurphStatTile.swift
// Stat readout for the history header and session summary
// (components/data/StatTile.jsx). Trend colour follows the arrow: down
// (faster) is lime, up is blood. Never colour a bare value.
import SwiftUI

struct MurphStatTile: View {
    let label: String
    let value: String
    var delta: String? = nil
    var caption: String? = nil
    var alignTrailing: Bool = false

    var body: some View {
        VStack(alignment: alignTrailing ? .trailing : .leading, spacing: MurphSpacing.space1) {
            Text(label)
                .murphType(.micro)
                .foregroundStyle(MurphColor.textMuted)
            Text(value)
                .murphType(.metric())
                .foregroundStyle(MurphColor.textPrimary)
            if let delta {
                Text(delta)
                    .murphType(.bodySm)
                    .foregroundStyle(delta.hasPrefix("\u{2193}") ? MurphColor.lime500 : MurphColor.blood500)
            } else if let caption {
                Text(caption)
                    .murphType(.bodySm)
                    .foregroundStyle(MurphColor.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignTrailing ? .trailing : .leading)
    }
}
