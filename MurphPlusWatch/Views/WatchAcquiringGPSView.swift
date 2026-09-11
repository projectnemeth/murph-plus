// MurphPlusWatch/Views/WatchAcquiringGPSView.swift
import SwiftUI

/// The hold between countdown zero and a running clock, shown only when GPS
/// is still acquiring.
///
/// Full-bleed and opaque for the same reason `WatchCountdownView` is: it takes
/// the same slot in the same overlay, and the one control on screen has to be
/// the way out. Start anyway is available from the first frame — the user who
/// does not care about the mile must never be made to wait for it.
struct WatchAcquiringGPSView: View {
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: MurphSpacing.space3) {
            Spacer(minLength: 0)

            Text("Acquiring GPS")
                .murphType(.micro)
                .foregroundStyle(MurphColor.hazard500)
                .multilineTextAlignment(.center)

            ProgressView()

            Spacer(minLength: 0)

            Button("Start anyway", action: onSkip)
                .buttonStyle(.bordered)
                .murphType(.micro)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, MurphSpacing.space2)
        .padding(.bottom, MurphSpacing.space2)
        .background(MurphColor.surfacePage)
    }
}
