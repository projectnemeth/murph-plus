// MurphPlus/Views/History/SessionDetailView.swift
import SwiftUI
import SwiftData

struct SessionDetailView: View {
    @Bindable var session: MurphSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    private var roundThroughputs: [RoundThroughput] {
        RoundThroughputBuilder.build(session: session)
    }

    var body: some View {
        Form {
            Section("Summary") {
                LabeledContent("Template", value: session.template?.name ?? "—")
                LabeledContent("Total Time", value: session.totalElapsedSeconds.map(formatDuration) ?? "—")
                LabeledContent("Vest", value: session.vestOn ? "\(session.vestWeightLbs ?? 20) lbs" : "None")
                LabeledContent("Status", value: session.status == .completed ? "Completed" : "Abandoned")
            }

            if let run1 = session.runSplits.first(where: { $0.runIndex == 1 }) {
                Section("Run 1") {
                    Text(formatDuration(run1.durationSeconds))
                }
            }

            if !roundThroughputs.isEmpty {
                Section("Rounds") {
                    ForEach(Array(roundThroughputs.enumerated()), id: \.offset) { index, round in
                        LabeledContent("Round \(index + 1)", value: "\(round.secondsForRound)s")
                    }
                }
            }

            if let run2 = session.runSplits.first(where: { $0.runIndex == 2 }) {
                Section("Run 2") {
                    Text(formatDuration(run2.durationSeconds))
                }
            }

            Section("Notes") {
                TextEditor(text: Binding(
                    get: { session.notes ?? "" },
                    set: { session.notes = $0 }
                ))
                .frame(minHeight: 80)
            }

            PredictionControlView(session: session)

            Section {
                Button("Delete Session", role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        }
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
        .confirmationDialog("Delete this session?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                context.delete(session)
                try? context.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
