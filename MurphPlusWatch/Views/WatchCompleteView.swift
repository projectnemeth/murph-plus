// MurphPlusWatch/Views/WatchCompleteView.swift
import SwiftUI

/// PLACEHOLDER — Task 9 replaces this with the real completion screen.
///
/// `WatchLiveView` navigates here once `controller.isFinished` becomes true,
/// so this stub exists only to keep Tasks 7/8 buildable; it is not meant to be
/// reviewed or polished as a real screen.
struct WatchCompleteView: View {
    @Bindable var controller: WatchSessionController

    var body: some View {
        Text("Session Complete")
            .murphType(.title(18))
            .foregroundStyle(MurphColor.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MurphColor.surfacePage)
    }
}
