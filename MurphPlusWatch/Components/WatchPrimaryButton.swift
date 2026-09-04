// MurphPlusWatch/Components/WatchPrimaryButton.swift
import SwiftUI

/// The advancing action. Appears on **both** metric pages, so logging a round
/// never requires swiping first — paging changes what you read, never what you
/// can do.
struct WatchPrimaryButton: View {
    let title: String
    var disabled: Bool = false
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
    }
}
