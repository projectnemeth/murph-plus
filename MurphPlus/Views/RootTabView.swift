// MurphPlus/Views/RootTabView.swift
import SwiftUI
import SwiftData

private struct LiveSessionWrapper: Identifiable {
    let engine: SessionEngine
    var id: ObjectIdentifier { ObjectIdentifier(engine) }
}

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @State private var liveEngine: SessionEngine?
    @State private var resumableSession: MurphSession?

    var body: some View {
        TabView {
            StartView { template, vestOn, vestWeight in
                liveEngine = SessionEngine.startNew(template: template, vestOn: vestOn, vestWeightLbs: vestWeight, context: context)
            }
            .tabItem { Label("Start", systemImage: "play.circle") }

            HistoryView()
                .tabItem { Label("History", systemImage: "list.bullet") }
        }
        .fullScreenCover(item: Binding(
            get: { liveEngine.map { LiveSessionWrapper(engine: $0) } },
            set: { liveEngine = $0?.engine }
        )) { wrapper in
            LiveSessionView(engine: wrapper.engine) {
                liveEngine = nil
            }
        }
        .sheet(item: $resumableSession) { session in
            ResumeSessionPrompt(
                session: session,
                onResume: {
                    liveEngine = SessionEngine(session: session, context: context)
                    resumableSession = nil
                },
                onAbandon: {
                    session.status = .abandoned
                    session.completedAt = .now
                    try? context.save()
                    resumableSession = nil
                }
            )
        }
        .task {
            resumableSession = ResumableSessionFinder.findInProgress(context: context)
        }
    }
}
