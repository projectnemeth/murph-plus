// MurphPlus/Sync/LiveMirrorStore.swift
import Foundation
import Observation

/// What the phone shows while a workout is happening on the Watch.
///
/// In-memory only. Nothing here is ever persisted — a `MurphSession` is created
/// solely by a durable checkpoint through `SessionImporter`, so a dropped link
/// can never leave a half-written session in history. The two paths are kept
/// deliberately separate: this one is allowed to be lossy, that one is not.
@Observable
@MainActor
final class LiveMirrorStore {
    private(set) var sessionID: UUID?
    private(set) var state: SessionState?
    private(set) var lastUpdate: Date?

    /// Sessions already seen to completion. Heart rate keeps arriving for a
    /// short while after the terminal event, and without this the first
    /// straggler would be read as a brand-new workout.
    private var finished: Set<UUID> = []

    /// How long a gap makes the mirror untrustworthy. Live events arrive on
    /// every round tap and every 5-second heart-rate sample, so ten seconds of
    /// silence means the link is down rather than the user being still.
    private let staleAfter: TimeInterval

    init(staleAfter: TimeInterval = 10) {
        self.staleAfter = staleAfter
    }

    /// A frozen clock with no explanation is worse than an honest one: the
    /// view says "not connected" rather than showing a stopped timer as live.
    var isStale: Bool {
        guard let lastUpdate else { return true }
        return Date.now.timeIntervalSince(lastUpdate) > staleAfter
    }

    /// Deliberately consults `isStale`. A watch that runs out of battery sends
    /// no terminal event, it just stops; without the staleness test the mirror
    /// would claim a session is live forever and `StartView` would never give
    /// the Begin button back.
    var isMirroring: Bool {
        guard let state, !state.isTerminal else { return false }
        return !isStale
    }

    func receive(sessionID: UUID, event: SessionEvent) {
        guard !finished.contains(sessionID) else { return }

        // A different id means a different workout — never accumulate the new
        // session's events onto the old one's rounds.
        if self.sessionID != sessionID {
            self.sessionID = sessionID
            self.state = SessionState()
        }
        state?.apply(event)
        lastUpdate = .now

        // Once the session ends, the phone's own history is the record. A
        // lingering mirror would render it a second time alongside it.
        if state?.isTerminal == true {
            finished.insert(sessionID)
            clear()
        }
    }

    func clear() {
        sessionID = nil
        state = nil
        lastUpdate = nil
    }

    /// The durable checkpoint channel also ends a session — via
    /// `PhoneSyncCoordinator.ingest`, when an imported payload replays as
    /// terminal. That channel is guaranteed, unlike the fire-and-forget live
    /// channel whose own terminal event may never arrive. A session's end
    /// must be recorded once no matter which channel observed it, or a
    /// straggling event on the same id (heart rate keeps arriving after
    /// `finish()`) would take the "different session" branch in `receive`
    /// and reopen the mirror on a finished workout.
    func markFinished(sessionID: UUID) {
        finished.insert(sessionID)
        clear()
    }
}
