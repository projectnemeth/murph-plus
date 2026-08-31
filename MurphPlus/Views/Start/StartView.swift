// MurphPlus/Views/Start/StartView.swift
import SwiftUI
import SwiftData

struct StartView: View {
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]
    @State private var selectedTemplate: WorkoutTemplate?
    @State private var vestOn = false
    @State private var vestWeightText = ""
    @State private var showTemplateEditor = false

    let onBegin: (WorkoutTemplate, Bool, Int?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    Picker("Template", selection: $selectedTemplate) {
                        ForEach(templates) { template in
                            Text(template.name).tag(Optional(template))
                        }
                    }
                    Button("New Template…") {
                        showTemplateEditor = true
                    }
                }

                Section("Vest") {
                    Toggle("Wearing a weighted vest", isOn: $vestOn)
                    if vestOn {
                        TextField("Weight (lbs, default 20)", text: $vestWeightText)
                            .keyboardType(.numberPad)
                    }
                }

                Section {
                    Button("Begin") {
                        guard let template = selectedTemplate else { return }
                        let weight = vestOn ? Int(vestWeightText) : nil
                        onBegin(template, vestOn, weight)
                    }
                    .disabled(selectedTemplate == nil)
                }
            }
            .navigationTitle("Start Murph")
            .onAppear {
                if selectedTemplate == nil {
                    selectedTemplate = templates.first
                }
            }
            .sheet(isPresented: $showTemplateEditor) {
                TemplateEditorView()
            }
        }
    }
}

#Preview {
    StartView { _, _, _ in }
        .modelContainer(for: [WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self], inMemory: true)
}
