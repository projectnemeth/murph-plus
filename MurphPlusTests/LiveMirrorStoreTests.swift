// MurphPlusTests/LiveMirrorStoreTests.swift
import XCTest
@testable import MurphPlus

@MainActor
final class LiveMirrorStoreTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    private var spec: TemplateSpec {
        TemplateSpec(
            id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
            totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 20
        )
    }

    private func started(_ at: Date) -> SessionEvent {
        .started(at: at, template: spec, vestOn: false, vestWeightLbs: nil, indoor: false)
    }

    func test_theFirstEventBeginsMirroringThatSession() {
        let store = LiveMirrorStore()
        let id = UUID()

        store.receive(sessionID: id, event: started(t(0)))

        XCTAssertEqual(store.sessionID, id)
        XCTAssertEqual(store.state?.phase, .run1)
        XCTAssertTrue(store.isMirroring)
    }

    func test_laterEventsAccumulateOntoTheSameSession() {
        let store = LiveMirrorStore()
        let id = UUID()

        store.receive(sessionID: id, event: started(t(0)))
        store.receive(sessionID: id, event: .runFinished(index: 1, at: t(600), distanceMeters: 1609))
        store.receive(sessionID: id, event: .roundCompleted(number: 1, at: t(700)))

        XCTAssertEqual(store.state?.phase, .rounds)
        XCTAssertEqual(store.state?.completedRounds, 1)
    }

    /// A second watch session must not inherit the first one's rounds.
    func test_aDifferentSessionIDStartsAFreshMirror() {
        let store = LiveMirrorStore()
        let first = UUID()
        store.receive(sessionID: first, event: started(t(0)))
        store.receive(sessionID: first, event: .runFinished(index: 1, at: t(600), distanceMeters: nil))
        store.receive(sessionID: first, event: .roundCompleted(number: 1, at: t(700)))

        let second = UUID()
        store.receive(sessionID: second, event: started(t(1000)))

        XCTAssertEqual(store.sessionID, second)
        XCTAssertEqual(store.state?.completedRounds, 0, "The new session must not inherit rounds")
        XCTAssertEqual(store.state?.phase, .run1)
    }

    /// The mirror is for a session in flight. Once it ends, the phone's own
    /// history is the record — a lingering mirror would double-render it.
    func test_aTerminalEventClearsTheMirror() {
        let store = LiveMirrorStore()
        let id = UUID()
        store.receive(sessionID: id, event: started(t(0)))

        store.receive(sessionID: id, event: .abandoned(at: t(60)))

        XCTAssertNil(store.state)
        XCTAssertNil(store.sessionID)
        XCTAssertFalse(store.isMirroring)
    }

    func test_anUntouchedMirrorIsStale() {
        XCTAssertTrue(LiveMirrorStore().isStale, "Never having heard from the Watch is stale")
    }

    func test_aJustUpdatedMirrorIsNotStale() {
        let store = LiveMirrorStore()
        store.receive(sessionID: UUID(), event: started(t(0)))

        XCTAssertFalse(store.isStale)
    }

    /// A watch whose battery dies sends no terminal event — it simply stops.
    /// If the mirror never expires, `StartView` hides Begin forever and the
    /// phone can never start a workout again.
    func test_aMirrorThatHasGoneStaleIsNoLongerMirroring() {
        let store = LiveMirrorStore(staleAfter: 0.05)
        store.receive(sessionID: UUID(), event: started(t(0)))
        XCTAssertTrue(store.isMirroring)

        Thread.sleep(forTimeInterval: 0.1)

        XCTAssertTrue(store.isStale)
        XCTAssertFalse(store.isMirroring, "A dead link must release the Start screen")
    }

    /// Heart rate keeps arriving after the workout ends: the handler guards
    /// only on `isPaused`, and HealthKit's `finish()` is awaited asynchronously.
    /// Without a guard the first straggler re-opens the mirror as an empty
    /// session and the phone shows a live 00:00 clock for a finished workout.
    func test_anEventArrivingAfterTheSessionEndedDoesNotReopenTheMirror() {
        let store = LiveMirrorStore()
        let id = UUID()
        store.receive(sessionID: id, event: started(t(0)))
        store.receive(sessionID: id, event: .abandoned(at: t(60)))
        XCTAssertFalse(store.isMirroring)

        store.receive(sessionID: id, event: .heartRate(bpm: 140, at: t(61)))

        XCTAssertNil(store.state, "A finished session must stay finished")
        XCTAssertFalse(store.isMirroring)
    }

    /// But a genuinely new workout must still be able to start mirroring.
    func test_aNewSessionAfterAFinishedOneStillMirrors() {
        let store = LiveMirrorStore()
        let first = UUID()
        store.receive(sessionID: first, event: started(t(0)))
        store.receive(sessionID: first, event: .abandoned(at: t(60)))

        let second = UUID()
        store.receive(sessionID: second, event: started(t(100)))

        XCTAssertTrue(store.isMirroring)
        XCTAssertEqual(store.sessionID, second)
    }

    /// `PhoneSyncCoordinator.ingest` also ends a session — via the durable
    /// checkpoint channel, which is guaranteed, unlike the fire-and-forget
    /// live channel whose own terminal event may have been dropped. That path
    /// must record the id as finished too, or a heart-rate straggler on the
    /// same id reopens the mirror through this second door.
    func test_aSessionEndedByMarkFinishedCannotBeReopenedByALaterEvent() {
        let store = LiveMirrorStore()
        let id = UUID()
        store.receive(sessionID: id, event: started(t(0)))

        store.markFinished(sessionID: id)

        XCTAssertNil(store.state)
        XCTAssertFalse(store.isMirroring)

        store.receive(sessionID: id, event: .heartRate(bpm: 140, at: t(61)))

        XCTAssertNil(store.state, "A session ended via markFinished must stay finished")
        XCTAssertFalse(store.isMirroring)
    }

    /// A genuinely new session id must still be able to start mirroring after
    /// a prior one was ended via `markFinished`.
    func test_aNewSessionAfterMarkFinishedStillMirrors() {
        let store = LiveMirrorStore()
        let first = UUID()
        store.receive(sessionID: first, event: started(t(0)))
        store.markFinished(sessionID: first)

        let second = UUID()
        store.receive(sessionID: second, event: started(t(100)))

        XCTAssertTrue(store.isMirroring)
        XCTAssertEqual(store.sessionID, second)
    }

    /// A queued, guaranteed checkpoint can land long after the fact: the watch
    /// finishes session A while the phone is unreachable, the user starts B,
    /// the phone begins mirroring B live, and only then does A's terminal
    /// checkpoint arrive. `markFinished(sessionID: A)` must not wipe B's
    /// in-flight mirror — B was never the session being marked finished.
    func test_markFinishedForAStaleSessionDoesNotClearADifferentSessionCurrentlyMirroring() {
        let store = LiveMirrorStore()
        let a = UUID()
        let b = UUID()
        store.receive(sessionID: b, event: started(t(0)))
        store.receive(sessionID: b, event: .roundCompleted(number: 1, at: t(100)))

        store.markFinished(sessionID: a)

        XCTAssertEqual(store.sessionID, b, "B's mirror must survive a stale checkpoint about A")
        XCTAssertEqual(store.state?.completedRounds, 1, "B's accumulated rounds must not be wiped")
        XCTAssertTrue(store.isMirroring)
    }

    /// Even though the stale checkpoint about A must not clear B's mirror, A's
    /// id must still be recorded as finished — otherwise a later straggling
    /// event for A would start mirroring A from empty.
    func test_markFinishedForAStaleSessionStillRecordsItAsFinished() {
        let store = LiveMirrorStore()
        let a = UUID()
        let b = UUID()
        store.receive(sessionID: b, event: started(t(0)))

        store.markFinished(sessionID: a)
        store.receive(sessionID: a, event: .heartRate(bpm: 140, at: t(61)))

        XCTAssertEqual(store.sessionID, b, "A stray event for the already-finished A must not reopen A's mirror or disturb B's")
        XCTAssertTrue(store.isMirroring)
    }

    /// The existing behaviour must survive: marking the session that is
    /// actually being mirrored finished still clears it — every field of it.
    /// (`clear()` itself is private; `markFinished` is the only door to it, so
    /// this is where the full reset is asserted.)
    func test_markFinishedForTheCurrentlyMirroredSessionStillClearsIt() {
        let store = LiveMirrorStore()
        let id = UUID()
        store.receive(sessionID: id, event: started(t(0)))

        store.markFinished(sessionID: id)

        XCTAssertNil(store.state)
        XCTAssertNil(store.sessionID)
        XCTAssertNil(store.lastUpdate)
        XCTAssertTrue(store.isStale)
        XCTAssertFalse(store.isMirroring)
    }
}
