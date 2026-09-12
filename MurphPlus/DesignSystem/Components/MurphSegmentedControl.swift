// MurphPlus/DesignSystem/Components/MurphSegmentedControl.swift
// Pill segmented switch; active segment is bone-on-ink. Two or three
// segments only (components/forms/SegmentedControl.jsx).
import SwiftUI

/// One segment of a `MurphSegmentedControl`.
///
/// `systemImage` is optional and defaults to `nil` so existing call sites
/// that only ever had a string (via the `options:` initializer below) don't
/// have to know this type exists at all.
struct MurphSegment: Equatable {
    let label: String
    var systemImage: String? = nil
}

struct MurphSegmentedControl: View {
    let segments: [MurphSegment]
    @Binding var selection: String
    @Namespace private var namespace

    /// Text-only, for callers that have nothing to illustrate. Kept around
    /// so `HistoryView` — the one existing caller — compiles unchanged: it
    /// passes `options: [String]` and never needs to know `MurphSegment`
    /// exists.
    init(options: [String], selection: Binding<String>) {
        self.segments = options.map { MurphSegment(label: $0) }
        self._selection = selection
    }

    init(segments: [MurphSegment], selection: Binding<String>) {
        self.segments = segments
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments, id: \.label) { segment in
                let selected = segment.label == selection
                Button {
                    withAnimation(MurphMotion.snap()) { selection = segment.label }
                } label: {
                    HStack(spacing: MurphSpacing.space2) {
                        if let systemImage = segment.systemImage {
                            // An SF Symbol carries no Murph type style of its
                            // own, so it's sized by hand rather than through
                            // `.murphType(...)`: 12pt bold is what optically
                            // matches the 11pt `.tag` mono label it sits next
                            // to — a plain 11pt symbol reads visibly lighter
                            // than bold mono text beside it.
                            Image(systemName: systemImage)
                                .font(.system(size: 12, weight: .bold))
                                // Decorative alongside the label: the label
                                // text is already the accessible text for
                                // this segment, so the symbol's own implicit
                                // a11y name (e.g. "figure walking") would only
                                // double up what's announced, not add to it.
                                .accessibilityHidden(true)
                        }
                        Text(segment.label)
                            .murphType(.tag)
                    }
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
                // Selection is drawn as a bone capsule sliding behind the
                // label — invisible to VoiceOver, which only ever hears
                // "button". The trait is the only thing that actually tells
                // an assistive-tech user which segment is active.
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(MurphColor.surfaceRaised)
        .clipShape(Capsule())
    }
}
