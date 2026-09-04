// MurphPlusTests/SessionEventTests.swift
import XCTest
@testable import MurphPlus

final class SessionEventTests: XCTestCase {

    private let spec = TemplateSpec(
        id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
        totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 20
    )

    private var allEventKinds: [SessionEvent] {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        return [
            .started(at: t, template: spec, vestOn: true, vestWeightLbs: 20, indoor: false),
            .runFinished(index: 1, at: t, distanceMeters: 1609.34),
            .runFinished(index: 2, at: t, distanceMeters: nil),
            .roundCompleted(number: 7, at: t),
            .roundUndone(number: 7, at: t),
            .paused(at: t),
            .resumed(at: t),
            .heartRate(bpm: 142, at: t),
            .abandoned(at: t),
        ]
    }

    func test_everyEventRoundTripsThroughJSON() throws {
        // The journal format and the sync payload are the same encoding, so a
        // case that fails to round-trip is a case that silently loses a
        // workout in Stage 3.
        for event in allEventKinds {
            let data = try JSONEncoder().encode(event)
            let decoded = try JSONDecoder().decode(SessionEvent.self, from: data)
            XCTAssertEqual(decoded, event)
        }
    }

    func test_timestampIsReadableForEveryCase() {
        let t = Date(timeIntervalSince1970: 1_700_000_000)

        for event in allEventKinds {
            XCTAssertEqual(event.timestamp, t)
        }
    }

    func test_onlyHeartRateIsMarkedAsHeartRate() {
        let t = Date()

        XCTAssertTrue(SessionEvent.heartRate(bpm: 140, at: t).isHeartRate)
        XCTAssertFalse(SessionEvent.roundCompleted(number: 1, at: t).isHeartRate)
        XCTAssertFalse(SessionEvent.paused(at: t).isHeartRate)
    }
}
