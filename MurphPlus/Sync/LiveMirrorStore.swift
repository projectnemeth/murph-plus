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

    /// How long a gap makes the mirror untrustworthy. Live events arrive on
    /// every round tap and every 5-second heart-rate sample, so ten seconds of
    /// silence means the link is down rather than the user being still.
    private static let staleAfter: TimeInterval = 10

    /// A frozen clock with no explanation is worse than an honest one: the
    /// view says "not connected" rather than showing a stopped timer as live.
    var isStale: Bool {
        guard let lastUpdate else { return true }
        return Date.now.timeIntervalSince(lastUpdate) > Self.staleAfter
    }

    var isMirroring: Bool {
        guard let state else { return false }
        return !state.isTerminal
    }

    func receive(sessionID: UUID, event: SessionEvent) {
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
        if state?.isTerminal == true { clear() }
    }

    func clear() {
        sessionID = nil
        state = nil
        lastUpdate = nil
    }
}
