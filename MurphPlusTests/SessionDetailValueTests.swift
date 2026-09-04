// MurphPlusTests/SessionDetailValueTests.swift
import XCTest
@testable import MurphPlus

final class SessionDetailValueTests: XCTestCase {

    // MARK: - Runs

    /// Every v1 session and every phone-owned session has no heart rate and no
    /// distance, so the bare duration is the common path, not the exception.
    func test_aRunWithNeitherDistanceNorHeartRateIsJustItsDuration() {
        let value = SessionDetailValue.run(duration: "8:12", distanceMeters: nil, avgHeartRate: nil)

        XCTAssertEqual(value, "8:12")
    }

    func test_aRunWithDistanceShowsItInMiles() {
        let value = SessionDetailValue.run(duration: "8:12", distanceMeters: 1609.34, avgHeartRate: nil)

        XCTAssertEqual(value, "8:12 · 1.00 mi")
    }

    func test_aRunWithHeartRateShowsBpm() {
        let value = SessionDetailValue.run(duration: "8:12", distanceMeters: nil, avgHeartRate: 148)

        XCTAssertEqual(value, "8:12 · 148 bpm")
    }

    func test_aRunWithBothShowsDistanceThenHeartRate() {
        let value = SessionDetailValue.run(duration: "8:12", distanceMeters: 1609.34, avgHeartRate: 148)

        XCTAssertEqual(value, "8:12 · 1.00 mi · 148 bpm")
    }

    /// An indoor run records no distance but still records heart rate, so the
    /// separator must not be left dangling where distance would have been.
    func test_anIndoorRunSkipsDistanceCleanly() {
        let value = SessionDetailValue.run(duration: "9:30", distanceMeters: nil, avgHeartRate: 155)

        XCTAssertFalse(value.contains("mi"))
        XCTAssertEqual(value, "9:30 · 155 bpm")
    }

    func test_aZeroDistanceIsStillReported() {
        let value = SessionDetailValue.run(duration: "0:05", distanceMeters: 0, avgHeartRate: nil)

        XCTAssertEqual(value, "0:05 · 0.00 mi", "Zero is a measurement, not a missing value")
    }

    // MARK: - Rounds

    func test_aRoundWithoutHeartRateIsJustItsDuration() {
        XCTAssertEqual(SessionDetailValue.round(duration: "42s", avgHeartRate: nil), "42s")
    }

    func test_aRoundWithHeartRateShowsBpm() {
        XCTAssertEqual(SessionDetailValue.round(duration: "42s", avgHeartRate: 161), "42s · 161 bpm")
    }
}
