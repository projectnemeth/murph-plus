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
    /// Short label for the band's top-left, level with the system clock.
    ///
    /// watchOS reserves only the *right* of that row for its time indicator,
    /// so the left of the clearance is free. `nil` renders nothing.
    var corner: String? = nil
    /// Amber for paused, matching the treatment the clock page already gives
    /// that state — a paused workout is the one thing the corner says that the
    /// user needs to catch without reading it.
    var cornerTone: Color = MurphColor.bone200

    /// Room above the labels for watchOS's system time.
    ///
    /// The time indicator is drawn *over* app content in the top-right rather
    /// than inset out of it, and the safe area a full-bleed `TabView` page
    /// gets is not deep enough to clear it — so the trailing cell's label
    /// collided with the clock. Applied inside the band so the raised surface
    /// still runs to the top edge; moving the whole band down instead would
    /// leave the clock floating on the page background and break the banded
    /// header the three pages share.
    ///
    /// It *replaces* the cells' top padding rather than stacking on it (see
    /// `cell`). Added on top, the band grew to ~40% of the screen and left the
    /// pages below with no slack at all, which is what collapsed their
    /// `Spacer`s and jammed every element against the next.
    private static let timeIndicatorClearance: CGFloat = MurphSpacing.space6

    var body: some View {
        HStack(spacing: 0) {
            cell(leading)
            Rectangle().fill(MurphColor.lineHairline).frame(width: 1)
            cell(trailing)
        }
        .padding(.top, Self.timeIndicatorClearance)
        .overlay(alignment: .topLeading) {
            if let corner {
                // Deliberately not `.micro` in `textMuted`: that is exactly
                // the treatment the two column labels below it use, so the
                // phase read as a third one stacked above "Elapsed". `.tag`
                // in bone gives it the weight of a status chip instead.
                Text(corner)
                    .murphType(.tag)
                    .foregroundStyle(cornerTone)
                    .padding(.leading, MurphSpacing.space2)
                    .frame(height: Self.timeIndicatorClearance, alignment: .center)
            }
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
        // Top padding comes from `timeIndicatorClearance` on the band itself.
        .padding(.bottom, MurphSpacing.space2)
    }
}
