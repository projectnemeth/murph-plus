// MurphPlusTests/SessionEnginePauseRelaunchTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

/// Pins two relaunch bugs found in review of the pause-persistence design:
///
/// - `rebuildState(from:)` used to leave `state.pausedIntervals` empty, so
///   `totalElapsed` (which reads `state.pausedIntervals` via
///   `SessionDerivation`) would jump forward after a relaunch by every second
///   previously paused — the live clock was wrong, even though the eventually
///   *logged* time was not.
/// - Worse, a pause taken during a run or round that had not yet been logged
///   at relaunch time was lost entirely: `before.pausedSeconds(between:and:)`
///   (used when the round finally completes, or when the run finally ends)
///   would see an empty interval list and subtract nothing, silently writing
///   a *gross* (too-slow) `RunSplit.durationSeconds` or
///   `RoundLog.pausedSecondsInRound` — the exact fatigue-curve skew Ruling 3
///   was raised to prevent, arriving by a different door.
///
/// The fix persists the actual `[PausedInterval]` (JSON-encoded, in
/// `MurphSession.pausedIntervalsData`) rather than just their running sum, and
/// `rebuildState(from:)` decodes them back. Each test here rebuilds a second
/// `SessionEngine` over the same persisted `MurphSession` — exactly what a
/// relaunch does — to prove both symptoms are gone.
final class SessionEnginePauseRelaunchTests: XCTestCase {
    var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        context = ModelContext(container)
    }

    /// Important 1: the live elapsed clock must not jump forward across a
    /// relaunch by the amount previously paused.
    func test_relaunchDoesNotInflateTheLiveElapsedClock() throws {
        let template = WorkoutTemplate(name: "Test", rounds: 1)
        context.insert(template)
        let engine1 = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)

        engine1.start()
        engine1.pause()
        Thread.sleep(forTimeInterval: 0.3)
        engine1.resume()

        let elapsedBeforeRelaunch = engine1.totalElapsed

        // Simulate an app relaunch: a fresh engine rebuilt from the same
        // persisted session — exactly what `rebuildState(from:)` is for.
        let engine2 = SessionEngine(session: engine1.session, context: context)
        let elapsedAfterRelaunch = engine2.totalElapsed

        // Without the fix, `pausedIntervals` would rebuild empty, so
        // `elapsedAfterRelaunch` would read ~0.3s *higher* than
        // `elapsedBeforeRelaunch`. A tight tolerance (well under the 0.3s
        // pause) still allows for the negligible real time the test itself
        // takes between the two reads.
        XCTAssertEqual(elapsedAfterRelaunch, elapsedBeforeRelaunch, accuracy: 0.15)
    }

    /// Important 2 (run case): a pause taken during run 1, before relaunch,
    /// must still be subtracted from the eventual `RunSplit.durationSeconds`
    /// even though run 1 had not been logged yet when the relaunch happened.
    func test_relaunchDuringRun1PreservesThePauseInTheUnloggedSplit() throws {
        let template = WorkoutTemplate(name: "Test", rounds: 1)
        context.insert(template)
        let engine1 = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)

        engine1.start()
        let t0 = try XCTUnwrap(engine1.session.startedAt)

        engine1.pause()
        Thread.sleep(forTimeInterval: 0.3)
        engine1.resume()

        // Relaunch mid-run-1: run 1 has not been logged yet.
        let engine2 = SessionEngine(session: engine1.session, context: context)
        XCTAssertTrue(engine2.session.runSplits.isEmpty, "run 1 must not be logged yet at the moment of relaunch")

        let beforeFinish = Date()
        engine2.finishRun()

        let run1 = try XCTUnwrap(engine2.session.runSplits.first { $0.runIndex == 1 })

        // `beforeFinish` is a lower bound on the true gross elapsed time (the
        // real `at` used inside `finishRun()` can only be later), so this
        // understates the true paused amount subtracted — but if the fix
        // works, it still clears a comfortable margin below the full ~0.3s.
        let grossElapsedAtLeast = beforeFinish.timeIntervalSince(t0)
        let pauseAccountedFor = grossElapsedAtLeast - run1.durationSeconds
        XCTAssertGreaterThan(pauseAccountedFor, 0.15, "the pause taken before relaunch must still be subtracted from run 1's duration")
    }

    /// Important 2 (round case): a pause taken during round 1, before
    /// relaunch, must still be recorded in `RoundLog.pausedSecondsInRound`
    /// even though round 1 had not been logged yet when the relaunch
    /// happened.
    func test_relaunchDuringARoundPreservesThePauseInTheUnloggedRound() throws {
        let template = WorkoutTemplate(name: "Test", rounds: 2)
        context.insert(template)
        let engine1 = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)

        engine1.start()
        engine1.finishRun() // -> rounds phase; roundsStartedAt persisted.

        engine1.pause()
        Thread.sleep(forTimeInterval: 0.3)
        engine1.resume()

        // Relaunch mid-round-1: round 1 has not been logged yet.
        let engine2 = SessionEngine(session: engine1.session, context: context)
        XCTAssertTrue(engine2.session.roundLogs.isEmpty, "round 1 must not be logged yet at the moment of relaunch")

        engine2.completeRound()

        let round1 = try XCTUnwrap(engine2.session.roundLogs.first { $0.roundNumber == 1 })
        XCTAssertGreaterThan(round1.pausedSecondsInRound, 0.15, "the pause taken before relaunch must still be attributed to round 1")
    }

    /// A relaunch that happens *while paused* must keep working exactly as it
    /// already did — `pausedAt` restoration is unrelated to this fix and must
    /// not regress.
    func test_relaunchWhilePausedStillReportsPaused() throws {
        let template = WorkoutTemplate(name: "Test", rounds: 1)
        context.insert(template)
        let engine1 = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)

        engine1.start()
        engine1.pause()

        let engine2 = SessionEngine(session: engine1.session, context: context)
        XCTAssertTrue(engine2.isPaused)
    }
}
