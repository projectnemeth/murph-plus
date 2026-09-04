// MurphPlus/DesignSystem/Foundations/MurphFlowLayout.swift
// Wrapping row layout for badge groups (CSS `flexWrap: wrap` in the source
// design system) — an HStack alone truncates when badges don't all fit.
import SwiftUI
#if os(watchOS)
import WatchKit
#endif

private struct FlowLayoutEngine: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            // Include the spacing this item would need *before* it when
            // deciding whether it still fits — comparing against just
            // `size.width` under-counts by one gap and lets a row's true
            // content run past `maxWidth` without wrapping.
            let neededWidth = size.width + (rowWidth > 0 ? spacing : 0)
            if rowWidth + neededWidth > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + (rowWidth > 0 ? spacing : 0)
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: proposal.width ?? totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let needsGap = x > bounds.minX
            let neededWidth = size.width + (needsGap ? spacing : 0)
            if x - bounds.minX + neededWidth > maxWidth, needsGap {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            } else if needsGap {
                x += spacing
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A `VStack` sizes a custom `Layout` child using its unconstrained ideal
/// size (a single un-wrapped row, measured with a nil-width proposal) to
/// decide how much vertical space to reserve for it, then places it at the
/// real, narrower final width — where it wraps into more rows than were
/// reserved, so the next sibling overlaps it. An explicit fixed `.frame`
/// width sidesteps that ideal-vs-final ambiguity entirely: both of the
/// layout's own passes are then always given the same concrete number.
/// `maxWidth` should be the caller's known available content width (screen
/// width minus whatever gutters/padding wrap this flow).
enum MurphFlowWidth {
    /// Available width for badges laid directly under the screen gutter.
    /// `UIScreen` is unavailable on watchOS (it's marked `API_UNAVAILABLE`
    /// even though the header is importable), so the watch side reads the
    /// same measurement through `WKInterfaceDevice` instead. This property
    /// is only ever consumed by the phone-sized badge components under
    /// `DesignSystem/Components`, which the watch target does not build —
    /// but the declaration still has to type-check there since this file
    /// lives in the shared `Foundations` sources.
    static var screen: CGFloat {
        #if os(watchOS)
        WKInterfaceDevice.current().screenBounds.width - 2 * MurphSpacing.gutterScreen
        #else
        UIScreen.main.bounds.width - 2 * MurphSpacing.gutterScreen
        #endif
    }
    /// Available width for badges inside a `MurphCard` under the screen gutter.
    static var card: CGFloat { screen - 2 * MurphSpacing.space4 }
}

struct MurphFlowLayout<Content: View>: View {
    var maxWidth: CGFloat = MurphFlowWidth.screen
    var spacing: CGFloat = MurphSpacing.space2
    @ViewBuilder var content: Content

    var body: some View {
        FlowLayoutEngine(spacing: spacing) { content }
            .frame(width: maxWidth, alignment: .topLeading)
    }
}
