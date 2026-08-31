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
    }
}
