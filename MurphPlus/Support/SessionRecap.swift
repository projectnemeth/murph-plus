// MurphPlus/Support/SessionRecap.swift
import Foundation

/// Everything the completed-workout recap screen draws, derived once from the
/// phone's own saved `MurphSession` rather than the live Watch mirror.
///
/// `LiveMirrorStore`'s own doc comment says it is allowed to be lossy, while
/// the durable checkpoint path through `SessionImporter` is not — and it is
/// that path which leaves this session's `RoundLog.maxHeartRate` /
/// `RunSplit.maxHeartRate` (peak heart rate; the live `SessionState` only ever
/// keeps `latestHeartRate`) and each round's authoritative `completedAt` in
/// place once the workout is over. For a finished workout the saved session
/// is the record, so this type reads it directly instead of the mirror.
///
/// Lives in `MurphPlus/Support`, not `MurphCore`: `MurphCore` is compiled into
/// the watchOS target, which must never see a SwiftData model.
struct SessionRecap: Equatable {
    /// One row of the completed timeline spine — Run 1, Rounds, or Run 2.
    struct Segment: Equatable {
        let label: String
        /// The formatted, real (not projected) duration.
        let value: String
        let detail: String?
        /// This segment's share of `total`, for the spine's row heights.
        let fraction: Double
    }

    /// The headline PR comparison.
    ///
    /// `isImprovement` alone decides colour and glyph in the view: an
    /// improvement is painted lime with a "↓" arrow, while a slower time is
    /// stated in plain, muted text — never red. A completed Murph is not a
    /// failure, so the slower case must not read as one.
    struct PersonalBestDelta: Equatable {
        let text: String
        let isImprovement: Bool
    }

    let total: String
    /// Always exactly three, in order: Run 1, Rounds, Run 2.
    let segments: [Segment]
    /// Seconds per round, from consecutive `RoundLog.completedAt`, the first
    /// measured from the rounds phase's start (see `RoundsPhaseStart`).
    let roundSplits: [Double]
    let fastestRoundSeconds: Double?
    let slowestRoundSeconds: Double?
    let averageRoundSeconds: Double?
    /// Nil when no heart-rate sample was ever recorded, so the view never
    /// renders a false "0 bpm".
    let peakHeartRate: Int?
    /// e.g. "↓ 0:30 negative split" when run 2 beat run 1. Nil otherwise — a
    /// positive split is never rendered as a failure line.
    let negativeSplit: String?
    let personalBestDelta: PersonalBestDelta?

    /// The separator this app already uses to join several facts into one
    /// caption, reused here so the rounds detail reads the same way as the
    /// live mirror's (`MirrorSegments`).
    private static let detailSeparator = " · "

    /// Derives the full recap from a saved, completed session.
    ///
    /// - Parameter priorSessions: every other candidate session to compare
    ///   against for the personal-best delta (typically the phone's whole
    ///   history, completed and abandoned alike — this method does its own
    ///   filtering). Injected rather than queried from SwiftData internally,
    ///   which is what keeps this type testable without a store and matches
    ///   `PersonalBestCheck`. This session's own id is excluded even if
    ///   present in the list, since by the time a recap is drawn the session
    ///   is already part of its own history.
    static func make(session: MurphSession, priorSessions: [MurphSession]) -> SessionRecap {
        let totalSeconds = session.totalElapsedSeconds ?? 0
        let run1 = session.runSplits.first(where: { $0.runIndex == 1 })
        let run2 = session.runSplits.first(where: { $0.runIndex == 2 })

        let roundSplits = self.roundSplits(session: session)
        let roundsDuration = roundSplits.reduce(0, +)

        let segments = [
            runSegment(label: "Run 1", split: run1, totalSeconds: totalSeconds),
            roundsSegment(session: session, roundsDuration: roundsDuration, averageRoundSeconds: average(roundSplits), totalSeconds: totalSeconds),
            runSegment(label: "Run 2", split: run2, totalSeconds: totalSeconds),
        ]

        return SessionRecap(
            total: formatDuration(totalSeconds),
            segments: segments,
            roundSplits: roundSplits,
            fastestRoundSeconds: roundSplits.min(),
            slowestRoundSeconds: roundSplits.max(),
            averageRoundSeconds: average(roundSplits),
            peakHeartRate: peakHeartRate(session: session),
            negativeSplit: negativeSplit(run1: run1, run2: run2),
            personalBestDelta: personalBestDelta(session: session, totalSeconds: totalSeconds, priorSessions: priorSessions)
        )
    }

    // MARK: - Run segments

    private static func runSegment(label: String, split: RunSplit?, totalSeconds: Double) -> Segment {
        let duration = split?.durationSeconds ?? 0
        // Indoor runs (and any run logged with no fix) carry no distance.
        // Printing "0.00 mi" would read as a measured, empty run instead of an
        // unmeasured one, so the detail must be nil, not a zero.
        let detail = split?.distanceMeters.map(formatMiles)
        return Segment(label: label, value: formatDuration(duration), detail: detail, fraction: fraction(duration, of: totalSeconds))
    }

    // MARK: - Rounds segment

    private static func roundsSegment(
        session: MurphSession,
        roundsDuration: Double,
        averageRoundSeconds: Double?,
        totalSeconds: Double
    ) -> Segment {
        let countLabel = "\(session.completedRounds) rounds"
        let detail: String?
        if let averageRoundSeconds {
            detail = "\(countLabel)\(detailSeparator)\(formatDuration(averageRoundSeconds)) avg"
        } else {
            detail = nil
        }
        return Segment(
            label: "Rounds",
            value: formatDuration(roundsDuration),
            detail: detail,
            fraction: fraction(roundsDuration, of: totalSeconds)
        )
    }

    // MARK: - Round splits

    /// Seconds per round, net of any pause that fell inside it — the same
    /// reasoning `RoundThroughputBuilder` already applies, so an interruption
    /// mid-round cannot read here as a very slow round. The anchor for round 1
    /// comes from `RoundsPhaseStart`, shared with `RoundThroughputBuilder`, so
    /// a session missing `roundsStartedAt` still gets real splits here — the
    /// same way the History screen already falls back for it — instead of the
    /// two screens disagreeing about the same session.
    private static func roundSplits(session: MurphSession) -> [Double] {
        guard let roundsPhaseStart = RoundsPhaseStart.of(session) else { return [] }
        let sortedLogs = session.roundLogs.sorted { $0.roundNumber < $1.roundNumber }

        var splits: [Double] = []
        var previousTimestamp = roundsPhaseStart
        for log in sortedLogs {
            let raw = log.completedAt.timeIntervalSince(previousTimestamp) - log.pausedSecondsInRound
            splits.append(max(0, raw))
            previousTimestamp = log.completedAt
        }
        return splits
    }

    /// Guards the division: an empty round list must yield nil, never NaN.
    private static func average(_ roundSplits: [Double]) -> Double? {
        guard !roundSplits.isEmpty else { return nil }
        return roundSplits.reduce(0, +) / Double(roundSplits.count)
    }

    // MARK: - Peak heart rate

    private static func peakHeartRate(session: MurphSession) -> Int? {
        let samples = session.roundLogs.compactMap(\.maxHeartRate) + session.runSplits.compactMap(\.maxHeartRate)
        return samples.max()
    }

    // MARK: - Negative split

    private static func negativeSplit(run1: RunSplit?, run2: RunSplit?) -> String? {
        guard let run1Duration = run1?.durationSeconds, let run2Duration = run2?.durationSeconds else { return nil }
        guard run2Duration < run1Duration else { return nil }
        return "\u{2193} \(formatDuration(run1Duration - run2Duration)) negative split"
    }

    // MARK: - Personal best delta

    /// The fastest COMPLETED session with the same template and the same
    /// vest state, excluding this session's own id.
    ///
    /// Vest state is part of the identity, never a tiebreak: a vested Murph
    /// is a materially harder workout, so beating an unvested record says
    /// nothing about it. This is the same reasoning `PersonalBestCheck`
    /// already applies. With no prior matching session the delta is nil — a
    /// first attempt has nothing to beat, and badging one would claim a best
    /// that does not exist.
    private static func personalBestDelta(
        session: MurphSession,
        totalSeconds: Double,
        priorSessions: [MurphSession]
    ) -> PersonalBestDelta? {
        guard let templateID = session.template?.id else { return nil }

        let candidates = priorSessions.filter {
            $0.id != session.id
                && $0.status == .completed
                && $0.template?.id == templateID
                && $0.vestOn == session.vestOn
        }
        guard let bestSeconds = candidates.compactMap(\.totalElapsedSeconds).min() else { return nil }

        if totalSeconds < bestSeconds {
            let faster = bestSeconds - totalSeconds
            return PersonalBestDelta(text: "\u{2193} \(formatDuration(faster)) faster than your best", isImprovement: true)
        } else {
            let slower = totalSeconds - bestSeconds
            return PersonalBestDelta(text: "\(formatDuration(slower)) off your best", isImprovement: false)
        }
    }

    /// Guards the division: a zero or negative total (no elapsed time
    /// recorded) must yield 0, never NaN or infinity reaching a view.
    private static func fraction(_ duration: Double, of totalSeconds: Double) -> Double {
        guard totalSeconds > 0 else { return 0 }
        return max(0, min(1, duration / totalSeconds))
    }
}
