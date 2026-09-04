// MurphPlusWatch/Components/WatchStatusStrip.swift
import SwiftUI

/// The two-cell banded row at the top of every page. Each page's strip carries
/// the metrics its hero does not, so no number is ever shown twice on one page.
struct WatchStatusStrip: View {
    struct Cell {
        let label: String
        let value: String
        var tone: Color = MurphColor.textPrimary
    }

    let leading: Cell
    let trailing: Cell

    var body: some View {
        HStack(spacing: 0) {
            cell(leading)
            Rectangle().fill(MurphColor.lineHairline).frame(width: 1)
            cell(trailing)
        }
        .background(MurphColor.surfaceRaised)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MurphColor.lineHairline).frame(height: 1)
        }
    }

    private func cell(_ cell: Cell) -> some View {
        VStack(spacing: 2) {
            Text(cell.label)
                .murphType(.micro)
                .foregroundStyle(MurphColor.textMuted)
            Text(cell.value)
                .murphType(.metric(16))
                .foregroundStyle(cell.tone)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MurphSpacing.space2)
    }
}
