// MurphPlusTests/SyncPayloadTests.swift
import XCTest
@testable import MurphPlus

final class SyncPayloadTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    private let spec = TemplateSpec(
        id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
        totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 3
    )

    private func payload(seq: Int, events: [SessionEvent] = []) -> SyncPayload {
        SyncPayload(sessionID: UUID(), checkpointSeq: seq, origin: .watch, events: events)
    }

    func test_payloadRoundTripsThroughJSON() throws {
        let original = SyncPayload(
            sessionID: UUID(), checkpointSeq: 7, origin: .watch,
            events: [
                .started(at: t(0), template: spec, vestOn: true, vestWeightLbs: 20, indoor: false),
                .heartRate(bpm: 150, at: t(5)),
                .roundCompleted(number: 1, at: t(60)),
            ]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncPayload.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func test_higherSequenceIsApplied() {
        XCTAssertTrue(SessionMerge.shouldApply(incoming: payload(seq: 5), storedSeq: 4))
    }

    func test_duplicateDeliveryIsIgnored() {
        // transferUserInfo can deliver the same payload more than once.
        XCTAssertFalse(SessionMerge.shouldApply(incoming: payload(seq: 5), storedSeq: 5))
    }

    func test_outOfOrderDeliveryIsIgnored() {
        // A queued earlier checkpoint arriving after a later one must not
        // rewind the session to fewer rounds.
        XCTAssertFalse(SessionMerge.shouldApply(incoming: payload(seq: 3), storedSeq: 9))
    }

    func test_firstCheckpointAppliesAgainstAnUnknownSession() {
        XCTAssertTrue(SessionMerge.shouldApply(incoming: payload(seq: 1), storedSeq: 0))
    }

    func test_strippingHeartRateKeepsEverythingElseInOrder() {
        let full = SyncPayload(
            sessionID: UUID(), checkpointSeq: 2, origin: .watch,
            events: [
                .started(at: t(0), template: spec, vestOn: false, vestWeightLbs: nil, indoor: false),
                .heartRate(bpm: 140, at: t(5)),
                .runFinished(index: 1, at: t(100), distanceMeters: 1609.34),
                .heartRate(bpm: 160, at: t(105)),
                .roundCompleted(number: 1, at: t(160)),
            ]
        )

        let stripped = full.strippingHeartRate()

        XCTAssertEqual(stripped.events.count, 3)
        XCTAssertFalse(stripped.events.contains { $0.isHeartRate })
        XCTAssertEqual(stripped.checkpointSeq, 2)
        XCTAssertEqual(stripped.sessionID, full.sessionID)
        // Replaying the stripped journal must still produce the same session shape.
        XCTAssertEqual(SessionState.replay(stripped.events).completedRounds, 1)
        XCTAssertEqual(SessionState.replay(stripped.events).phase, .rounds)
    }

    func test_syncContextRoundTrips() throws {
        let context = SyncContext(
            templates: [spec],
            personalBests: [PersonalBest(templateID: spec.id, vestOn: true, seconds: 3120)]
        )

        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(SyncContext.self, from: data)

        XCTAssertEqual(decoded, context)
    }
}
