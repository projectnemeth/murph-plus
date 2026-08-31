// MurphPlus/Views/Start/TemplateEditorView.swift
import SwiftUI
import SwiftData

struct TemplateEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var runDistanceMiles = 1.0
    @State private var totalPullUps = 100
    @State private var totalPushUps = 200
    @State private var totalSquats = 300
    @State private var rounds = 1

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && runDistanceMiles > 0
            && totalPullUps > 0 && totalPushUps > 0 && totalSquats > 0
            && rounds > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Half Murph", text: $name)
                }

                Section("Runs") {
                    Stepper(value: $runDistanceMiles, in: 0.25...5, step: 0.25) {
                        Text("\(runDistanceMiles, specifier: "%.2f") mi each")
                    }
                }

                Section("Total Reps") {
                    Stepper(value: $totalPullUps, in: 1...1000, step: 5) {
                        Text("Pull-ups: \(totalPullUps)")
                    }
                    Stepper(value: $totalPushUps, in: 1...1000, step: 5) {
                        Text("Push-ups: \(totalPushUps)")
                    }
                    Stepper(value: $totalSquats, in: 1...1000, step: 5) {
                        Text("Squats: \(totalSquats)")
                    }
                }

                Section("Partitioning") {
                    Stepper(value: $rounds, in: 1...50) {
                        Text(rounds == 1 ? "Straight sets" : "\(rounds) rounds")
                    }
                }
            }
            .navigationTitle("New Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let template = WorkoutTemplate(
                            name: name,
                            runDistanceMiles: runDistanceMiles,
                            totalPullUps: totalPullUps,
                            totalPushUps: totalPushUps,
                            totalSquats: totalSquats,
                            rounds: rounds
                        )
                        context.insert(template)
                        try? context.save()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
