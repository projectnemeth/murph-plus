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

    func test_clearingResetsEverything() {
        let store = LiveMirrorStore()
        store.receive(sessionID: UUID(), event: started(t(0)))

        store.clear()

        XCTAssertNil(store.sessionID)
        XCTAssertNil(store.state)
        XCTAssertNil(store.lastUpdate)
        XCTAssertTrue(store.isStale)
    }
}
