// MurphPlusTests/SessionRecapTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

final class SessionRecapTests: XCTestCase {
    // MARK: - Fixtures

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self,
            configurations: config
        )
        return ModelContext(container)
    }

    /// Builds a fully completed session: run 1, N rounds (each duration exact,
    /// no pause), run 2, wired together the way `SessionEngine` leaves a real
    /// session — `roundsStartedAt` set, `completedAt` at the very end.
    @discardableResult
    private func makeSession(
        context: ModelContext,
        template: WorkoutTemplate,
        vestOn: Bool = false,
        run1Duration: Double,
        run2Duration: Double,
        run1Distance: Double? = nil,
        run2Distance: Double? = nil,
        run1MaxHR: Int? = nil,
        run2MaxHR: Int? = nil,
        roundDurations: [Double],
        roundMaxHRs: [Int?] = [],
        status: SessionStatus = .completed
    ) -> MurphSession {
        let session = MurphSession(template: template, vestOn: vestOn)
        context.insert(session)

        let start = Date(timeIntervalSince1970: 0)
        let run1 = RunSplit(runIndex: 1, startTime: start, durationSeconds: run1Duration, session: session)
        run1.distanceMeters = run1Distance
        run1.maxHeartRate = run1MaxHR
        context.insert(run1)
        session.runSplits.append(run1)

        let roundsStart = start.addingTimeInterval(run1Duration)
        session.roundsStartedAt = roundsStart

        var cursor = roundsStart
        for (index, duration) in roundDurations.enumerated() {
            cursor = cursor.addingTimeInterval(duration)
            let log = RoundLog(roundNumber: index + 1, completedAt: cursor, session: session)
            if roundMaxHRs.indices.contains(index) { log.maxHeartRate = roundMaxHRs[index] }
            context.insert(log)
            session.roundLogs.append(log)
        }
        session.completedRounds = roundDurations.count

        let run2Start = cursor
        let run2 = RunSplit(runIndex: 2, startTime: run2Start, durationSeconds: run2Duration, session: session)
        run2.distanceMeters = run2Distance
        run2.maxHeartRate = run2MaxHR
        context.insert(run2)
        session.runSplits.append(run2)

        session.startedAt = start
        session.completedAt = run2Start.addingTimeInterval(run2Duration)
        session.status = status

        return session
    }

    /// A minimal prior attempt for personal-best comparisons: only the fields
    /// `PersonalBestCheck`'s scoping rule and the elapsed-time comparison
    /// actually read. Mirrors `HistoryStatsTests`'s bare-fixture style since no
    /// relationship data is needed for this comparison.
    private func priorSession(
        context: ModelContext,
        template: WorkoutTemplate,
        vestOn: Bool,
        elapsedSeconds: Double,
        status: SessionStatus = .completed
    ) -> MurphSession {
        let session = MurphSession(template: template, vestOn: vestOn)
        context.insert(session)
        let start = Date(timeIntervalSince1970: 0)
        session.startedAt = start
        session.completedAt = start.addingTimeInterval(elapsedSeconds)
        session.status = status
        return session
    }

    private func template(rounds: Int = 20) -> WorkoutTemplate {
        WorkoutTemplate(name: "Full Murph", rounds: rounds)
    }

    // MARK: - Segments and total

    /// The centrepiece happy path: three real segments whose fractions sum to
    /// 1, a total that matches their sum, and correctly derived round splits.
    func test_make_normalCompletedSession_computesSegmentsTotalAndRoundSplits() throws {
        let context = try makeContext()
        let tmpl = template()
        let session = makeSession(
            context: context, template: tmpl,
            run1Duration: 300, run2Duration: 280,
            run1Distance: 1609.34, run2Distance: 1609.34,
            roundDurations: [100, 120]
        )

        let recap = SessionRecap.make(session: session, priorSessions: [])

        XCTAssertEqual(recap.total, "13:20")
        XCTAssertEqual(recap.segments.count, 3)
        XCTAssertEqual(recap.segments[0].label, "Run 1")
        XCTAssertEqual(recap.segments[0].value, "5:00")
        XCTAssertEqual(recap.segments[1].label, "Rounds")
        XCTAssertEqual(recap.segments[1].value, "3:40")
        XCTAssertEqual(recap.segments[2].label, "Run 2")
        XCTAssertEqual(recap.segments[2].value, "4:40")

        XCTAssertEqual(recap.segments[0].fraction, 300.0 / 800.0, accuracy: 0.0001)
        XCTAssertEqual(recap.segments[1].fraction, 220.0 / 800.0, accuracy: 0.0001)
        XCTAssertEqual(recap.segments[2].fraction, 280.0 / 800.0, accuracy: 0.0001)

        XCTAssertEqual(recap.roundSplits, [100, 120])
    }

    /// The first round's duration is measured from `roundsStartedAt`, not from
    /// round zero or from run 1's own start — using the wrong anchor would
    /// silently fold run 1's time into round 1's split.
    func test_roundSplits_firstRoundMeasuredFromRoundsStartedAt() throws {
        let context = try makeContext()
        let tmpl = template(rounds: 3)
        let session = makeSession(
            context: context, template: tmpl,
            run1Duration: 400, run2Duration: 400,
            roundDurations: [45, 60, 50]
        )

        let recap = SessionRecap.make(session: session, priorSessions: [])

        XCTAssertEqual(recap.roundSplits, [45, 60, 50])
        XCTAssertEqual(recap.fastestRoundSeconds, 45)
        XCTAssertEqual(recap.slowestRoundSeconds, 60)
        XCTAssertEqual(recap.averageRoundSeconds ?? -1, 155.0 / 3.0, accuracy: 0.0001)
    }

    /// A zero-round session (or one with no `roundsStartedAt`) must not divide
    /// by zero — a NaN average reaching a SwiftUI frame is a crash-class bug.
    func test_roundSplits_withNoRounds_doesNotDivideByZero() throws {
        let context = try makeContext()
        let tmpl = template(rounds: 0)
        let session = makeSession(
            context: context, template: tmpl,
            run1Duration: 300, run2Duration: 300,
            roundDurations: []
        )

        let recap = SessionRecap.make(session: session, priorSessions: [])

        XCTAssertEqual(recap.roundSplits, [])
        XCTAssertNil(recap.fastestRoundSeconds)
        XCTAssertNil(recap.slowestRoundSeconds)
        XCTAssertNil(recap.averageRoundSeconds)
        XCTAssertFalse(recap.segments[1].fraction.isNaN)
        XCTAssertFalse(recap.segments[1].fraction.isInfinite)
    }

    // MARK: - Peak heart rate

    /// No heart-rate sample was ever recorded anywhere — the view must render
    /// nothing, not a false "0 bpm".
    func test_peakHeartRate_withNoSamplesAnywhere_isNilNotZero() throws {
        let context = try makeContext()
        let tmpl = template(rounds: 2)
        let session = makeSession(
            context: context, template: tmpl,
            run1Duration: 300, run2Duration: 300,
            roundDurations: [60, 60]
        )

        let recap = SessionRecap.make(session: session, priorSessions: [])

        XCTAssertNil(recap.peakHeartRate)
    }

    /// The peak is the max across both run splits and round logs, not just
    /// one or the other.
    func test_peakHeartRate_isTheMaxAcrossRunsAndRounds() throws {
        let context = try makeContext()
        let tmpl = template(rounds: 2)
        let session = makeSession(
            context: context, template: tmpl,
            run1Duration: 300, run2Duration: 300,
            run1MaxHR: 150, run2MaxHR: 170,
            roundDurations: [60, 60],
            roundMaxHRs: [165, 158]
        )

        let recap = SessionRecap.make(session: session, priorSessions: [])

        XCTAssertEqual(recap.peakHeartRate, 170)
    }

    // MARK: - Negative split

    /// Run 2 beating run 1 is the only case that prints a negative-split line.
    func test_negativeSplit_whenRun2BeatsRun1_printsTheLine() throws {
        let context = try makeContext()
        let tmpl = template(rounds: 1)
        let session = makeSession(
            context: context, template: tmpl,
            run1Duration: 300, run2Duration: 270,
            roundDurations: [60]
        )

        let recap = SessionRecap.make(session: session, priorSessions: [])

        XCTAssertEqual(recap.negativeSplit, "\u{2193} 0:30 negative split")
    }

    /// A positive split (run 2 slower than run 1) must not be rendered as a
    /// failure line — it is simply absent.
    func test_negativeSplit_withAPositiveSplit_isNil() throws {
        let context = try makeContext()
        let tmpl = template(rounds: 1)
        let session = makeSession(
            context: context, template: tmpl,
            run1Duration: 250, run2Duration: 300,
            roundDurations: [60]
        )

        let recap = SessionRecap.make(session: session, priorSessions: [])

        XCTAssertNil(recap.negativeSplit)
    }

    // MARK: - Personal best delta

    /// A first attempt has nothing to beat — badging one would claim a record
    /// that does not exist.
    func test_personalBestDelta_withNoPriorAttempt_isNil() throws {
        let context = try makeContext()
        let tmpl = template(rounds: 1)
        let session = makeSession(
            context: context, template: tmpl,
            run1Duration: 300, run2Duration: 300,
            roundDurations: [60]
        )

        let recap = SessionRecap.make(session: session, priorSessions: [])

        XCTAssertNil(recap.personalBestDelta)
    }

    /// Beating the prior best produces the improvement badge, painted lime by
    /// the view.
    func test_personalBestDelta_whenFasterThanBest_isAnImprovement() throws {
        let context = try makeContext()
        let tmpl = template(rounds: 1)
        let session = makeSession(
            context: context, template: tmpl,
            run1Duration: 300, run2Duration: 300,
            roundDurations: [60]
        )
        // Total elapsed for `session` is 660s (11:00).
        let prior = priorSession(context: context, template: tmpl, vestOn: false, elapsedSeconds: 794)

        let recap = SessionRecap.make(session: session, priorSessions: [prior])

        XCTAssertEqual(recap.personalBestDelta, SessionRecap.PersonalBestDelta(
            text: "\u{2193} 2:14 faster than your best", isImprovement: true
        ))
    }

    /// Losing to the prior best must still read as plain fact, not a scold —
    /// the text carries no arrow and `isImprovement` is false so the view
    /// paints it muted rather than red.
    func test_personalBestDelta_whenSlowerThanBest_isStatedPlainly() throws {
        let context = try makeContext()
        let tmpl = template(rounds: 1)
        let session = makeSession(
            context: context, template: tmpl,
            run1Duration: 300, run2Duration: 300,
            roundDurations: [60]
        )
        // Total elapsed for `session` is 660s (11:00).
        let prior = priorSession(context: context, template: tmpl, vestOn: false, elapsedSeconds: 588)

        let recap = SessionRecap.make(session: session, priorSessions: [prior])

        XCTAssertEqual(recap.personalBestDelta, SessionRecap.PersonalBestDelta(
            text: "1:12 off your best", isImprovement: false
        ))
    }

    /// Vest state is part of the identity, never a tiebreak — a vested Murph
    /// is a materially harder workout, so an unvested record says nothing
    /// about it. The only prior attempt wears the opposite vest state, so
    /// there is nothing to compare against.
    func test_personalBestDelta_whenOnlyPriorAttemptHasADifferentVestState_isNil() throws {
        let context = try makeContext()
        let tmpl = template(rounds: 1)
        let session = makeSession(
            context: context, template: tmpl, vestOn: true,
            run1Duration: 300, run2Duration: 300,
            roundDurations: [60]
        )
        let prior = priorSession(context: context, template: tmpl, vestOn: false, elapsedSeconds: 500)

        let recap = SessionRecap.make(session: session, priorSessions: [prior])

        XCTAssertNil(recap.personalBestDelta)
    }

    /// This session is already in history by the time this runs. If the
    /// injected list (as it would from a real history query) still contains
    /// this session's own row, it must be excluded — otherwise the session is
    /// compared against itself and the delta collapses to a bogus zero
    /// instead of staying nil.
    func test_personalBestDelta_excludesThisSessionsOwnIdFromTheComparison() throws {
        let context = try makeContext()
        let tmpl = template(rounds: 1)
        let session = makeSession(
            context: context, template: tmpl,
            run1Duration: 300, run2Duration: 300,
            roundDurations: [60]
        )

        let recap = SessionRecap.make(session: session, priorSessions: [session])

        XCTAssertNil(recap.personalBestDelta)
    }
}
