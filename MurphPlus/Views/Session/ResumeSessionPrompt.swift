// MurphPlus/Views/Session/ResumeSessionPrompt.swift
import SwiftUI

struct ResumeSessionPrompt: View {
    let session: MurphSession
    let onResume: () -> Void
    let onAbandon: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.space4) {
            Rectangle()
                .fill(MurphColor.hazard500)
                .frame(height: MurphShape.borderStrong)

            VStack(alignment: .leading, spacing: MurphSpacing.space4) {
                Text("Unfinished Murph")
                    .murphType(.title())
                    .foregroundStyle(MurphColor.textPrimary)
                Text("You have an unfinished Murph from \(session.date.formatted(date: .abbreviated, time: .shortened)).")
                    .murphType(.body)
                    .foregroundStyle(MurphColor.textSecondary)

                VStack(spacing: MurphSpacing.space3) {
                    MurphButton(variant: .danger, full: true, title: "Abandon", action: onAbandon)
                    MurphButton(variant: .inverse, full: true, title: "Resume", action: onResume)
                }
                .padding(.top, MurphSpacing.space2)
            }
            .padding(.horizontal, MurphSpacing.gutterScreen)
            .padding(.bottom, MurphSpacing.space6)
        }
        .padding(.top, 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MurphColor.surfaceCard.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }
}
