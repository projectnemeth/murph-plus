// MurphPlusWatch/Components/WatchPrimaryButton.swift
import SwiftUI

/// The advancing action. Appears on **both** metric pages, so logging a round
/// never requires swiping first — paging changes what you read, never what you
/// can do.
struct WatchPrimaryButton: View {
    let title: String
    var disabled: Bool = false
    /// Whether this instance claims Double Tap.
    ///
    /// Off by default, and decided by `WatchLiveView` rather than here: this
    /// button is built four times over — twice per metric page, for the paused
    /// and running cases — and the paged `TabView` constructs every page at
    /// once, so a modifier applied unconditionally inside this type would
    /// declare the primary action several times and leave SwiftUI to pick.
    /// Only the view that knows which page is showing can answer this.
    var isPrimaryGesture: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .murphType(.tag)
                .foregroundStyle(MurphColor.textOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, MurphSpacing.space3)
                .background(disabled ? MurphColor.ash400 : MurphColor.hazard500)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .modifier(PrimaryHandGesture(isEnabled: isPrimaryGesture))
    }
}

/// `handGestureShortcut` is watchOS 11+, and the app's floor is watchOS 10 —
/// deliberately, so that every watch back to a Series 4 can still run a Murph.
/// Below 11 the button is untouched and works by touch, which is also what
/// happens on any watch older than a Series 9 whatever its OS, since Double Tap
/// is hardware-limited.
///
/// Toggled with `isEnabled:` rather than by branching on whether to apply the
/// modifier at all: the shortcut moves between pages on every swipe, and an
/// `if` there would change the button's view identity mid-session.
private struct PrimaryHandGesture: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if #available(watchOS 11.0, *) {
            content.handGestureShortcut(.primaryAction, isEnabled: isEnabled)
        } else {
            content
        }
    }
}
