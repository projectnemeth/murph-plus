// MurphPlus/Views/History/HistoryListView.swift
import SwiftUI
import SwiftData

struct HistoryListView: View {
    @Query(sort: \MurphSession.date, order: .reverse) private var allSessions: [MurphSession]
    let onSelect: (MurphSession) -> Void

    // History shows PAST sessions: completed and abandoned only. An .inProgress
    // row can outlive its workout — if the app is killed between "Begin" and
    // "Start Run 1", the session has startedAt == nil, so ResumableSessionFinder
    // deliberately refuses to offer it for resume, and it would otherwise linger
    // in the store forever, rendering here as a stray row showing "—".
    private var sessions: [MurphSession] {
        allSessions.filter { $0.status != .inProgress }
    }

    private var summary: HistoryStats.Summary {
        HistoryStats.summarize(completedSessions: sessions.filter { $0.status == .completed })
    }

    var body: some View {
        List {
            Section {
                statsRow(label: "Personal Best", seconds: summary.personalBestSeconds)
                statsRow(label: "Most Recent", seconds: summary.mostRecentSeconds)
                if let trend = summary.trendSeconds {
                    Text("Trend: \(trend <= 0 ? "↓" : "↑")\(formatDuration(abs(trend))) vs last")
                        .foregroundStyle(trend <= 0 ? .green : .red)
                }
            }

            Section("Sessions") {
                ForEach(sessions) { session in
                    Button {
                        onSelect(session)
                    } label: {
                        sessionRow(session)
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView("No Murphs Yet", systemImage: "figure.run", description: Text("Start your first session from the Start tab."))
            }
        }
    }

    private func statsRow(label: String, seconds: Double?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(seconds.map(formatDuration) ?? "—")
                .foregroundStyle(.secondary)
        }
    }

    private func sessionRow(_ session: MurphSession) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(session.template?.name ?? "Murph")
                Text(session.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if session.status == .abandoned {
                Text("Abandoned").foregroundStyle(.secondary)
            } else {
                Text(session.totalElapsedSeconds.map(formatDuration) ?? "—")
            }
        }
    }
}
