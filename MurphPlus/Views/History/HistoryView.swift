// MurphPlus/Views/History/HistoryView.swift
import SwiftUI
import SwiftData

struct HistoryView: View {
    enum Mode: String, CaseIterable {
        case list = "List"
        case calendar = "Calendar"
    }

    // History shows PAST sessions: completed and abandoned only. An .inProgress
    // row can outlive its workout — if the app is killed between "Begin" and
    // "Start Run 1", the session has startedAt == nil, so ResumableSessionFinder
    // deliberately refuses to offer it for resume, and it would otherwise linger
    // in the store forever, rendering here as a stray row showing "—".
    @Query(sort: \MurphSession.date, order: .reverse) private var allSessions: [MurphSession]

    @State private var mode: Mode = .list
    @State private var displayedMonth: Date = .now
    @State private var selectedSession: MurphSession?

    private let calendar = Calendar.current

    private var sessions: [MurphSession] {
        allSessions.filter { $0.status != .inProgress }
    }

    private var summary: HistoryStats.Summary {
        HistoryStats.summarize(completedSessions: sessions.filter { $0.status == .completed })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MurphScreenTitle(title: "History")

                    VStack(alignment: .leading, spacing: MurphSpacing.gapSection) {
                        MurphSegmentedControl(options: Mode.allCases.map(\.rawValue), selection: Binding(
                            get: { mode.rawValue },
                            set: { mode = Mode(rawValue: $0) ?? .list }
                        ))

                        if sessions.isEmpty {
                            MurphEmptyState(title: "No Murphs yet", body: "Start your first session from the Start tab.")
                        } else if mode == .list {
                            listContent
                        } else {
                            calendarContent
                        }
                    }
                    .padding(.horizontal, MurphSpacing.gutterScreen)
                    .padding(.bottom, MurphSpacing.space8)
                }
            }
            .murphScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedSession) { session in
                SessionDetailView(session: session)
            }
        }
    }

    // MARK: - List

    private var listContent: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.gapSection) {
            MurphCard {
                HStack(alignment: .top, spacing: MurphSpacing.space4) {
                    MurphStatTile(label: "Personal best", value: summary.personalBestSeconds.map(formatDuration) ?? "\u{2014}")
                    MurphStatTile(
                        label: "Most recent",
                        value: summary.mostRecentSeconds.map(formatDuration) ?? "\u{2014}",
                        delta: summary.trendSeconds.map { trend in
                            "\(trend <= 0 ? "\u{2193}" : "\u{2191}")\(formatDuration(abs(trend))) vs last"
                        }
                    )
                    MurphStatTile(label: "Attempts", value: "\(sessions.count)", alignTrailing: true)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                MurphSectionHeader("Sessions")
                MurphCard(padded: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(sessions.enumerated()), id: \.element.persistentModelID) { index, session in
                            MurphSessionRow(
                                templateName: session.template?.name ?? "Murph",
                                dateLabel: session.date.formatted(date: .abbreviated, time: .omitted),
                                time: session.totalElapsedSeconds.map(formatDuration),
                                vestLabel: session.vestOn ? "\(session.vestWeightLbs ?? 20) lb vest" : nil,
                                isCompleted: session.status == .completed,
                                progressLabel: SessionProgressDescriber.shortDescription(
                                    phase: session.phase,
                                    roundsCompleted: session.completedRounds,
                                    totalRounds: session.template?.rounds ?? 0
                                ),
                                isPR: session.status == .completed && session.totalElapsedSeconds == summary.personalBestSeconds,
                                showBottomDivider: index != sessions.count - 1,
                                action: { selectedSession = session }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Calendar

    private var days: [CalendarDay] {
        CalendarMonthBuilder.build(month: displayedMonth, sessions: sessions, calendar: calendar)
    }

    private var calendarContent: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.space5) {
            HStack {
                MurphIconButton(label: "Previous month", systemImage: "chevron.left") { shiftMonth(by: -1) }
                Spacer()
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .murphType(.title())
                    .foregroundStyle(MurphColor.textPrimary)
                Spacer()
                MurphIconButton(label: "Next month", systemImage: "chevron.right") { shiftMonth(by: 1) }
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { d in
                    Text(d)
                        .murphType(.micro)
                        .foregroundStyle(MurphColor.ash400)
                        .frame(maxWidth: .infinity)
                }
                ForEach(days) { day in
                    MurphCalendarCell(
                        day: calendar.component(.day, from: day.date),
                        isToday: calendar.isDateInToday(day.date),
                        isInCurrentMonth: day.isInCurrentMonth,
                        status: day.session.map { $0.status == .completed ? .completed : .abandoned },
                        action: day.session.map { session in { selectedSession = session } }
                    )
                }
            }

            HStack(spacing: MurphSpacing.space5) {
                legend(color: MurphColor.statusComplete, ring: false, label: "Completed")
                legend(color: MurphColor.statusAbandoned, ring: true, label: "Abandoned")
            }
        }
    }

    private func legend(color: Color, ring: Bool, label: String) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(ring ? .clear : color)
                .overlay(Circle().strokeBorder(ring ? color : .clear, lineWidth: 1.5))
                .frame(width: 7, height: 7)
            Text(label)
                .murphType(.micro)
                .foregroundStyle(MurphColor.textMuted)
        }
    }

    private func shiftMonth(by value: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) ?? displayedMonth
    }
}
