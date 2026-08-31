// MurphPlus/Views/Session/LiveSessionView.swift
import SwiftUI

struct LiveSessionView: View {
    let engine: SessionEngine
    let onFinished: () -> Void

    @State private var showAbandonConfirm = false

    var body: some View {
        VStack(spacing: 24) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(elapsedTimeText)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
            }

            phaseContent

            Button("Abandon", role: .destructive) {
                showAbandonConfirm = true
            }
        }
        .padding()
        .confirmationDialog("Abandon this session?", isPresented: $showAbandonConfirm) {
            Button("Abandon", role: .destructive) {
                engine.abandon()
                onFinished()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch engine.session.phase {
        case .notStarted:
            Button("Start Run 1") { engine.start() }
                .buttonStyle(.borderedProminent)
        case .run1:
            Button("Finish Run 1") { engine.finishRun() }
                .buttonStyle(.borderedProminent)
        case .rounds:
            VStack {
                Text("Round \(engine.session.completedRounds + 1) of \(engine.session.template?.rounds ?? 1)")
                    .font(.title2)
                Button("Round Done") { engine.completeRound() }
                    .buttonStyle(.borderedProminent)
            }
        case .run2:
            Button("Finish Run 2") {
                engine.finishRun()
                onFinished()
            }
            .buttonStyle(.borderedProminent)
        case .completed:
            Text("Done!")
                .font(.title)
        }
    }

    private var elapsedTimeText: String {
        let seconds = Int(engine.totalElapsed)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
