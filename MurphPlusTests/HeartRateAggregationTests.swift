// MurphPlusTests/HeartRateAggregationTests.swift
import XCTest
@testable import MurphPlus

final class HeartRateAggregationTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    private let spec = TemplateSpec(
        id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
        totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 2
    )

    func test_summaryAveragesAndMaximisesInsideTheWindow() {
        let events: [SessionEvent] = [
            .heartRate(bpm: 100, at: t(10)),
            .heartRate(bpm: 140, at: t(20)),
            .heartRate(bpm: 120, at: t(30)),
        ]

        let summary = HeartRateAggregator.summary(events: events, from: t(0), to: t(60))

        XCTAssertEqual(summary?.average, 120)
        XCTAssertEqual(summary?.maximum, 140)
    }

    func test_summaryExcludesSamplesOutsideTheWindow() {
        let events: [SessionEvent] = [
            .heartRate(bpm: 90, at: t(5)),
            .heartRate(bpm: 150, at: t(25)),
            .heartRate(bpm: 200, at: t(95)),
        ]

        let summary = HeartRateAggregator.summary(events: events, from: t(10), to: t(60))

        XCTAssertEqual(summary?.average, 150)
        XCTAssertEqual(summary?.maximum, 150)
    }

    func test_summaryIsNilWithNoSamples() {
        // A denied HealthKit permission produces exactly this, and it must be
        // an absent summary rather than a zero.
        XCTAssertNil(HeartRateAggregator.summary(events: [], from: t(0), to: t(60)))
    }

    func test_summaryIgnoresNonHeartRateEvents() {
        let events: [SessionEvent] = [
            .roundCompleted(number: 1, at: t(20)),
            .heartRate(bpm: 130, at: t(30)),
        ]

        XCTAssertEqual(HeartRateAggregator.summary(events: events, from: t(0), to: t(60))?.average, 130)
    }

    func test_roundSummariesBucketBetweenRoundBoundaries() {
        let events: [SessionEvent] = [
            .started(at: t(0), template: spec, vestOn: false, vestWeightLbs: nil, indoor: false),
            .runFinished(index: 1, at: t(100), distanceMeters: nil),
            .heartRate(bpm: 140, at: t(120)),
            .heartRate(bpm: 160, at: t(140)),
            .roundCompleted(number: 1, at: t(200)),
            .heartRate(bpm: 170, at: t(220)),
            .heartRate(bpm: 190, at: t(240)),
            .roundCompleted(number: 2, at: t(300)),
        ]
        let state = SessionState.replay(events)

        let summaries = HeartRateAggregator.roundSummaries(events: events, state: state)

        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries[0]?.average, 150)
        XCTAssertEqual(summaries[0]?.maximum, 160)
        XCTAssertEqual(summaries[1]?.average, 180)
        XCTAssertEqual(summaries[1]?.maximum, 190)
    }

    func test_runSummariesAreKeyedByRunIndex() {
        let events: [SessionEvent] = [
            .started(at: t(0), template: spec, vestOn: false, vestWeightLbs: nil, indoor: false),
            .heartRate(bpm: 150, at: t(50)),
            .runFinished(index: 1, at: t(100), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(200)),
            .roundCompleted(number: 2, at: t(300)),
            .heartRate(bpm: 180, at: t(350)),
            .runFinished(index: 2, at: t(400), distanceMeters: nil),
        ]
        let state = SessionState.replay(events)

        let summaries = HeartRateAggregator.runSummaries(events: events, state: state)

        XCTAssertEqual(summaries[1]?.average, 150)
        XCTAssertEqual(summaries[2]?.average, 180)
    }

    /// A run's window is wall-clock, not net of pause. `durationSeconds` is
    /// net, so ending the window at `startTime + durationSeconds` would cut
    /// the paused span off the *end* of the run and drop every sample from
    /// its final stretch — the hardest part of it.
    func test_runSummariesIncludeSamplesAfterAPauseInsideTheRun() {
        let events: [SessionEvent] = [
            .started(at: t(0), template: spec, vestOn: false, vestWeightLbs: nil, indoor: false),
            .heartRate(bpm: 120, at: t(60)),
            .paused(at: t(100)),
            .resumed(at: t(400)),          // a five minute pause
            .heartRate(bpm: 180, at: t(500)),
            .runFinished(index: 1, at: t(600), distanceMeters: nil),
        ]
        let state = SessionState.replay(events)
        // Net duration is 300s, so the naive window would end at t(300) and
        // silently exclude the 180 bpm sample taken at t(500).
        XCTAssertEqual(state.runSplits.first?.durationSeconds, 300)

        let summaries = HeartRateAggregator.runSummaries(events: events, state: state)

        XCTAssertEqual(summaries[1]?.average, 150)
        XCTAssertEqual(summaries[1]?.maximum, 180)
    }

    /// The widened window must still stop at the run's own end — a sample from
    /// the rounds that follow may not be pulled into the run's average.
    func test_runSummariesStopAtTheRunsEnd() {
        let events: [SessionEvent] = [
            .started(at: t(0), template: spec, vestOn: false, vestWeightLbs: nil, indoor: false),
            .heartRate(bpm: 140, at: t(50)),
            .runFinished(index: 1, at: t(100), distanceMeters: nil),
            .heartRate(bpm: 200, at: t(150)),
            .roundCompleted(number: 1, at: t(200)),
        ]
        let state = SessionState.replay(events)

        let summaries = HeartRateAggregator.runSummaries(events: events, state: state)

        XCTAssertEqual(summaries[1]?.average, 140)
        XCTAssertEqual(summaries[1]?.maximum, 140)
    }
}
