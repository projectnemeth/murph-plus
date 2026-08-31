// MurphPlus/Views/Session/ResumeSessionPrompt.swift
import SwiftUI

struct ResumeSessionPrompt: View {
    let session: MurphSession
    let onResume: () -> Void
    let onAbandon: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("You have an unfinished Murph from \(session.date.formatted(date: .abbreviated, time: .shortened))")
                .multilineTextAlignment(.center)
            HStack {
                Button("Abandon", role: .destructive, action: onAbandon)
                Button("Resume", action: onResume)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
