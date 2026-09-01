// MurphPlus/Views/Session/LiveSessionView.swift
import SwiftUI
import UIKit

struct LiveSessionView: View {
    let engine: SessionEngine
    let onFinished: () -> Void

    @State private var showAbandonConfirm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(elapsedTimeText)
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                }

                phaseContent

                Spacer()
            }
            .padding()
            // Abandon lives in the toolbar, away from the primary action button,
            // so a mid-workout reach for "Round Done" can't land on it by mistake.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Abandon", role: .destructive) {
                        showAbandonConfirm = true
                    }
                }
            }
            .confirmationDialog("Abandon this session?", isPresented: $showAbandonConfirm) {
                Button("Abandon", role: .destructive) {
                    engine.abandon()
                    onFinished()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch engine.session.phase {
        case .notStarted:
            Button("Start Run 1") { engine.start() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .run1:
            Button("Finish Run 1") { engine.finishRun() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .rounds:
            VStack(spacing: 12) {
                Text("Round \(engine.session.completedRounds + 1) of \(engine.session.template?.rounds ?? 1)")
                    .font(.title2)
                if let template = engine.session.template {
                    Text(roundBreakdown(for: template))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button {
                    engine.completeRound()
                } label: {
                    // Frame goes on the label — a frame applied to the Button
                    // itself, after .buttonStyle, does not affect how wide
                    // .borderedProminent actually draws its background.
                    Text("Round Done")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .controlSize(.large)
                .padding(.top, 8)
            }
        case .run2:
            Button("Finish Run 2") {
                engine.finishRun()
                onFinished()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .completed:
            Text("Done!")
                .font(.title)
        }
    }

    private func roundBreakdown(for template: WorkoutTemplate) -> String {
        "\(template.pullUpsPerRound) pull-ups · \(template.pushUpsPerRound) push-ups · \(template.squatsPerRound) squats"
    }

    private var elapsedTimeText: String {
        let seconds = Int(engine.totalElapsed)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
