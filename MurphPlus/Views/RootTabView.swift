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
                    // Delegate to the engine rather than mutating the session
                    // inline: SessionEngine.abandon() also clears
                    // currentPhaseStartedAt, and a second hand-rolled copy of
                    // "abandon a session" would silently drift from it.
                    SessionEngine(session: session, context: context).abandon()
                    resumableSession = nil
                }
            )
            // Resume-or-abandon must be an explicit choice. A swipe-dismiss
            // would leave the session .inProgress — and since History and
            // Calendar both filter .inProgress out, it would become invisible
            // with no route back: `.task` runs once per launch, `onBegin`
            // creates a new session unconditionally, and findInProgress returns
            // only the newest row. The workout would survive in the store but be
            // permanently unreachable, which is indistinguishable from data loss.
            .interactiveDismissDisabled()
        }
        .task {
            resumableSession = ResumableSessionFinder.findInProgress(context: context)
        }
    }
}
