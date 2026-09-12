// MurphPlus/DesignSystem/Components/MurphBanner.swift
// Inline note sitting next to the thing it explains — validation errors,
// prediction caveats (components/feedback/Banner.jsx).
import SwiftUI

enum MurphBannerTone {
    case error, warn, info

    var accent: Color {
        switch self {
        case .error: MurphColor.blood500
        case .warn: MurphColor.dust500
        case .info: MurphColor.ash300
        }
    }
}

struct MurphBanner: View {
    var tone: MurphBannerTone = .info
    let text: String
    /// A trailing chevron, for a banner that is really a control.
    ///
    /// The live-mirror banner was already inside a `NavigationLink` and read as
    /// flat text — it said "Tap to follow along" and testers did not tap it.
    /// The words were never the problem; nothing about the shape said it could
    /// be pressed.
    var navigates: Bool = false

    /// Width of the accent rule. Kept as a single literal (out of scope to
    /// tokenize) but named once so the leading inset below and the rule it
    /// makes room for can't drift apart.
    private let ruleWidth: CGFloat = 3

    var body: some View {
        // The rule used to sit here as a `Rectangle().frame(width: 3)`
        // sibling in the HStack. A `Rectangle` (like `Color` or any other
        // `Shape`) has no intrinsic size on either axis — constraining only
        // its width left the height greedy, so it happily grew to fill
        // whatever the tallest enclosing container offered. Every other call
        // site sits in a scroll view, which bounds that height and hid the
        // bug; the mirror screen's `.frame(maxHeight: .infinity)` VStack does
        // not, so the rule swallowed the whole screen behind one line of
        // text. Nothing in this HStack is a shape or a color now — `Text`
        // and `Image` both have real intrinsic sizes — so the row's height
        // is driven purely by its content no matter what height its
        // container offers.
        HStack(alignment: .top, spacing: MurphSpacing.space3) {
            Text(text)
                .murphType(.bodySm)
                .foregroundStyle(MurphColor.textSecondary)
            if navigates {
                Spacer(minLength: MurphSpacing.space2)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MurphColor.textMuted)
            }
        }
        .padding(.leading, ruleWidth + MurphSpacing.space3)
        .padding(.vertical, MurphSpacing.space2)
        .padding(.trailing, MurphSpacing.space3)
        // The rule itself is painted as a background of the row above,
        // after that row (text + padding) has already resolved to its
        // natural size. A background is proposed exactly its host's own
        // size, never the container's — so this `Rectangle` fills precisely
        // that resolved height instead of the space offered further up the
        // hierarchy, spanning the banner's full height including the
        // vertical padding without being able to inflate that height
        // itself. `alignment: .leading` pins it flush to the left edge
        // (the leading padding above starts past it), matching the
        // full-bleed look this replaces.
        .background(alignment: .leading) {
            Rectangle().fill(tone.accent).frame(width: ruleWidth)
        }
        .background(MurphColor.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: MurphShape.radiusSm))
    }
}
