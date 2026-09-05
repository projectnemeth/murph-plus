// MurphPlusWatch/Views/WatchCountdownView.swift
import SwiftUI

/// The 3·2·1 that stands between Start and a running clock.
///
/// Full-bleed and opaque on purpose: it is the only thing on screen, so a
/// mistaken Start is cancelled by the one control here rather than by finding
/// Abandon three swipes into a workout that has already begun.
struct WatchCountdownView: View {
    let value: Int
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: MurphSpacing.space3) {
            Spacer(minLength: 0)

            Text("\(value)")
                .murphType(.clock(64))
                .foregroundStyle(MurphColor.hazard500)
                // Digits swap in place rather than crossfading — at one per
                // second a fade is still on screen when the next one starts.
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy(duration: 0.2), value: value)

            Spacer(minLength: 0)

            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
                .murphType(.micro)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, MurphSpacing.space2)
        .padding(.bottom, MurphSpacing.space2)
        .background(MurphColor.surfacePage)
    }
}
