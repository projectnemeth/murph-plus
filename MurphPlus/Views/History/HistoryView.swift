// MurphPlus/Views/History/HistoryView.swift
import SwiftUI

struct HistoryView: View {
    enum Mode: String, CaseIterable {
        case list = "List"
        case calendar = "Calendar"
    }

    @State private var mode: Mode = .list
    @State private var selectedSession: MurphSession?

    var body: some View {
        NavigationStack {
            VStack {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch mode {
                case .list:
                    HistoryListView(onSelect: { selectedSession = $0 })
                case .calendar:
                    CalendarView(onSelect: { selectedSession = $0 })
                }
            }
            .navigationTitle("History")
            .navigationDestination(item: $selectedSession) { session in
                SessionDetailView(session: session)
            }
        }
    }
}
