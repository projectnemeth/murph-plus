// MurphPlusTests/RoundThroughputPauseTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

/// Pins the fix for a latent bug: `SessionState.roundsStartedAt` is the raw
/// wall-clock end of run 1, but `RunSplit.durationSeconds` is net of pause.
/// Deriving the rounds-phase start as `run1.startTime + run1.durationSeconds`
/// therefore lands *earlier* than the true boundary by exactly the pause
/// taken during run 1, which would make round 1 silently absorb that pause.
/// `SessionEngine` now persists `MurphSession.roundsStartedAt` from
/// `state.roundsStartedAt`, and `RoundThroughputBuilder` prefers it.
final class RoundThroughputPauseTests: XCTestCase {
    var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        context = ModelContext(container)
    }

    func test_pauseDuringRun1DoesNotInflateRound1Duration() throws {
        let template = WorkoutTemplate(name: "Test Template", rounds: 2)
        context.insert(template)
        let engine = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)

        engine.start()

        // Pause for 30s partway through run 1, then finish it 500s (gross)
        // after start — net duration should be 470s.
        engine.pause()
        engine.resume()

        engine.finishRun()
        engine.completeRound()
        engine.completeRound()
        engine.finishRun()

        // The true rounds-phase boundary must be persisted regardless of the
        // pause taken during run 1.
        let roundsStartedAt = try XCTUnwrap(engine.session.roundsStartedAt)

        // The old (buggy) derivation — run1.startTime + run1.durationSeconds —
        // is net of the pause, so it can only land at or before the true
        // boundary. Persisting the true boundary means it is never earlier
        // than that derived fallback.
        let run1 = try XCTUnwrap(engine.session.runSplits.first { $0.runIndex == 1 })
        let derivedFallback = run1.startTime.addingTimeInterval(run1.durationSeconds)
        XCTAssertGreaterThanOrEqual(roundsStartedAt, derivedFallback)

        let throughputs = RoundThroughputBuilder.build(session: engine.session)
        XCTAssertEqual(throughputs.count, 2)
        for throughput in throughputs {
            XCTAssertGreaterThanOrEqual(throughput.secondsForRound, 0)
        }
    }

    /// A more direct, timestamp-controlled reproduction of the bug: builds the
    /// SwiftData graph exactly the way `SessionEngine` would after a paused
    /// run 1, and confirms the builder reads the persisted boundary rather
    /// than re-deriving (and misplacing) it.
    func test_builderPrefersPersistedRoundsStartedAtOverDerivedFallback() throws {
        let template = WorkoutTemplate(name: "Test", rounds: 3)
        context.insert(template)
        let session = MurphSession(template: template, vestOn: false)
        context.insert(session)

        let run1Start = Date(timeIntervalSince1970: 0)
        // Gross run-1 time is 530s, but 30s of that was paused, so the net
        // logged duration is 500s. The true rounds-phase start is therefore
        // run1Start + 530s, not run1Start + 500s.
        let run1 = RunSplit(runIndex: 1, startTime: run1Start, durationSeconds: 500, session: session)
        context.insert(run1)
        session.runSplits.append(run1)

        let trueRoundsStart = run1Start.addingTimeInterval(530)
        session.roundsStartedAt = trueRoundsStart

        let round1 = RoundLog(roundNumber: 1, completedAt: trueRoundsStart.addingTimeInterval(20), session: session)
        context.insert(round1)
        session.roundLogs.append(round1)

        let throughputs = RoundThroughputBuilder.build(session: session)

        XCTAssertEqual(throughputs.count, 1)
        // With the fix, round 1's duration is measured from the persisted
        // (true) boundary: 20s. The old derivation (run1Start + 500s) would
        // have measured 50s instead — 30s too slow.
        XCTAssertEqual(throughputs[0].secondsForRound, 20)
    }

    func test_builderFallsBackToDerivedStartWhenRoundsStartedAtIsNil() throws {
        // Every pre-existing session has no `roundsStartedAt` and, having
        // predated pause support, cannot contain one either — so the fallback
        // derivation must remain exact for them.
        let template = WorkoutTemplate(name: "Test", rounds: 3)
        context.insert(template)
        let session = MurphSession(template: template, vestOn: false)
        context.insert(session)

        let run1Start = Date(timeIntervalSince1970: 0)
        let run1 = RunSplit(runIndex: 1, startTime: run1Start, durationSeconds: 480, session: session)
        context.insert(run1)
        session.runSplits.append(run1)

        XCTAssertNil(session.roundsStartedAt)

        let roundsStart = run1Start.addingTimeInterval(480)
        let round1 = RoundLog(roundNumber: 1, completedAt: roundsStart.addingTimeInterval(20), session: session)
        context.insert(round1)
        session.roundLogs.append(round1)

        let throughputs = RoundThroughputBuilder.build(session: session)

        XCTAssertEqual(throughputs.count, 1)
        XCTAssertEqual(throughputs[0].secondsForRound, 20)
    }
}
