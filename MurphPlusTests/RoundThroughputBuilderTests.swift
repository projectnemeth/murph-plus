// MurphPlusTests/RoundThroughputBuilderTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

final class RoundThroughputBuilderTests: XCTestCase {
    func test_build_computesPerRoundDurationsFromTimestamps() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)

        let template = WorkoutTemplate(name: "Test", rounds: 3)
        context.insert(template)
        let session = MurphSession(template: template, vestOn: false)
        context.insert(session)

        let run1Start = Date(timeIntervalSince1970: 0)
        let run1 = RunSplit(runIndex: 1, startTime: run1Start, durationSeconds: 480, session: session)
        context.insert(run1)
        session.runSplits.append(run1)

        let roundsStart = run1Start.addingTimeInterval(480)
        let round1 = RoundLog(roundNumber: 1, completedAt: roundsStart.addingTimeInterval(20), session: session)
        let round2 = RoundLog(roundNumber: 2, completedAt: roundsStart.addingTimeInterval(45), session: session)
        context.insert(round1)
        context.insert(round2)
        session.roundLogs.append(contentsOf: [round1, round2])

        let throughputs = RoundThroughputBuilder.build(session: session)

        XCTAssertEqual(throughputs.count, 2)
        XCTAssertEqual(throughputs[0].secondsForRound, 20)
        XCTAssertEqual(throughputs[1].secondsForRound, 25)
        XCTAssertEqual(throughputs[0].repsInRound, 200)

        // Round N must report N × repsPerRound cumulatively — this is the x-axis
        // of Task 11's fatigue regression, so an error here skews every prediction.
        XCTAssertEqual(throughputs[0].cumulativeRepsAfter, 200)
        XCTAssertEqual(throughputs[1].cumulativeRepsAfter, 400)
    }

    // The builder sorts roundLogs by roundNumber before walking them, because
    // SwiftData relationship arrays have no guaranteed order. Without the sort,
    // walking logs in insertion order yields wrong (and possibly negative)
    // durations. This test inserts them deliberately out of order so that
    // removing the sort fails loudly instead of silently corrupting predictions.
    func test_build_sortsRoundLogsBeforeComputingDurations() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)

        let template = WorkoutTemplate(name: "Test", rounds: 3)
        context.insert(template)
        let session = MurphSession(template: template, vestOn: false)
        context.insert(session)

        let run1Start = Date(timeIntervalSince1970: 0)
        let run1 = RunSplit(runIndex: 1, startTime: run1Start, durationSeconds: 480, session: session)
        context.insert(run1)
        session.runSplits.append(run1)

        let roundsStart = run1Start.addingTimeInterval(480)
        // Constructed newest-first (each initializer's `session:` argument links
        // the inverse relationship immediately, so construction order, not any
        // later manual array mutation, is what determines session.roundLogs order).
        let round2 = RoundLog(roundNumber: 2, completedAt: roundsStart.addingTimeInterval(45), session: session)
        let round1 = RoundLog(roundNumber: 1, completedAt: roundsStart.addingTimeInterval(20), session: session)
        context.insert(round2)
        context.insert(round1)

        let throughputs = RoundThroughputBuilder.build(session: session)

        XCTAssertEqual(throughputs.count, 2)
        XCTAssertEqual(throughputs[0].secondsForRound, 20)
        XCTAssertEqual(throughputs[1].secondsForRound, 25)
    }

    func test_build_returnsEmptyWhenRunOneMissing() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)

        let template = WorkoutTemplate(name: "Test", rounds: 3)
        context.insert(template)
        let session = MurphSession(template: template, vestOn: false)
        context.insert(session)

        let round1 = RoundLog(roundNumber: 1, completedAt: .now, session: session)
        context.insert(round1)
        session.roundLogs.append(round1)

        XCTAssertTrue(RoundThroughputBuilder.build(session: session).isEmpty)
    }

    func test_build_returnsEmptyWhenNoRoundsLogged() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)

        let template = WorkoutTemplate(name: "Test", rounds: 3)
        context.insert(template)
        let session = MurphSession(template: template, vestOn: false)
        context.insert(session)

        let run1 = RunSplit(runIndex: 1, startTime: Date(timeIntervalSince1970: 0), durationSeconds: 480, session: session)
        context.insert(run1)
        session.runSplits.append(run1)

        XCTAssertTrue(RoundThroughputBuilder.build(session: session).isEmpty)
    }
}
