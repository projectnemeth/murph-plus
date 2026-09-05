// MurphPlusWatch/Components/WatchStatusStrip.swift
import SwiftUI

/// The two-cell banded row at the top of the two metric pages. Each page's
/// strip carries the metrics its hero does not, so no number is ever shown
/// twice on one page.
///
/// It carries **no clearance for the system clock and no corner label** any
/// more. Both were wrong:
///
/// - The clearance (24pt of top padding inside the band) was added on the
///   belief that a paged `TabView` gives its pages no usable top safe area. It
///   does: a screenshot from the layout harness puts the band's top edge at the
///   safe-area inset already, so the 24pt stacked on top of a gap that was
///   doing its job, and pushed every number a row further down the screen.
/// - The corner label sat *inside* that padding, which put it below the clock
///   rather than level with it, and gave it a flat leading inset that the
///   round display could clip. The phase now lives in `topBarLeading` on the
///   `TabView` in `WatchLiveView` — the system slot that is level with the time
///   by construction and inset for the corner by the system.
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
