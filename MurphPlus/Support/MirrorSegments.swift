// MurphPlus/Support/MirrorSegments.swift
import Foundation

/// Where one row of the live segment ladder sits relative to the runner's
/// progress — `.done` and `.ahead` both render without a live value, but they
/// are opposite ends of the ladder and must not be styled the same.
enum MirrorSegmentState: Equatable {
    case done
    case current
    case ahead
}

/// One row of the phone's live "segment ladder" — Run 1, Rounds, or Run 2 —
/// mirroring a Watch-controlled workout: its time, an optional detail line,
/// and its share of total elapsed for the row's progress bar.
///
/// Lives in `MurphPlus/Support`, not `MurphCore`: `formatDuration` and
/// `formatMiles` live here too, and `project.yml` excludes this folder from
/// the watchOS target's sources. A `MurphCore` placement would pull those
/// formatters into the watch build and break it.
struct MirrorSegment: Equatable {
    let label: String
    let value: String
    let detail: String?
    let fraction: Double
    let state: MirrorSegmentState

    /// The separator this app already uses to join several facts into one
    /// caption (`"5 pull-ups · 10 push-ups · 15 squats"`), reused so a detail
    /// with two facts — a count and an average — reads the same way.
    private static let detailSeparator = " · "

    /// Shown for a value that has no meaning yet, because its segment hasn't
    /// started.
    private static let unstartedValue = "\u{2014}"

    /// Derives the three ladder rows from a session's state.
    ///
    /// Always returns exactly three segments, in order, whatever the phase —
    /// a row that appeared or disappeared mid-workout would make the screen
    /// jump under the runner's eyes.
    static func of(_ session: SessionState, now: Date) -> [MirrorSegment] {
        let totalElapsed = SessionDerivation.elapsed(session, now: now)

        return [
            runSegment(index: 1, label: "Run 1", currentPhase: .run1, session: session, now: now, totalElapsed: totalElapsed),
            roundsSegment(session: session, now: now, totalElapsed: totalElapsed),
            runSegment(index: 2, label: "Run 2", currentPhase: .run2, session: session, now: now, totalElapsed: totalElapsed),
        ]
    }

    // MARK: - Run 1 / Run 2

    private static func runSegment(
        index: Int,
        label: String,
        currentPhase: SessionPhase,
        session: SessionState,
        now: Date,
        totalElapsed: TimeInterval
    ) -> MirrorSegment {
        // A logged split is authoritative and always means "done" — it is
        // only ever appended once the run actually finishes.
        if let split = session.runSplits.first(where: { $0.index == index }) {
            // Indoor runs (and any run logged with no fix) carry no distance.
            // Printing "0.00 mi" would read as a measured, empty run instead
            // of an unmeasured one, so the detail must be nil, not a zero.
            let detail = split.distanceMeters.map(formatMiles)
            return MirrorSegment(
                label: label,
                value: formatDuration(split.durationSeconds),
                detail: detail,
                fraction: fraction(split.durationSeconds, of: totalElapsed),
                state: .done
            )
        }

        guard session.phase == currentPhase else {
            return MirrorSegment(label: label, value: unstartedValue, detail: nil, fraction: 0, state: .ahead)
        }

        guard let elapsed = elapsedSincePhaseStart(session, now: now) else {
            // `currentPhaseStartedAt` is only ever nil here if the session was
            // abandoned mid-run — there is then no live clock to read, so fall
            // back to the same unstarted look rather than crash or guess.
            return MirrorSegment(label: label, value: unstartedValue, detail: nil, fraction: 0, state: .current)
        }
        return MirrorSegment(
            label: label,
            value: formatDuration(elapsed),
            detail: nil,
            fraction: fraction(elapsed, of: totalElapsed),
            state: .current
        )
    }

    // MARK: - Rounds

    private static func roundsSegment(session: SessionState, now: Date, totalElapsed: TimeInterval) -> MirrorSegment {
        let label = "Rounds"
        let totalRounds = session.template?.rounds ?? 0
        let allRoundsDone = totalRounds > 0 && session.completedRounds >= totalRounds
        let countLabel = allRoundsDone ? "\(totalRounds) rounds" : "\(session.completedRounds) of \(totalRounds)"

        if allRoundsDone {
            // The rounds phase's own duration isn't stored as a split; its
            // end is the timestamp of the round that reached the template's
            // total. That timestamp is used — rather than
            // `currentPhaseStartedAt`, which run2 clears back to nil once it
            // finishes — because it also survives an abandon mid-run-2,
            // which nils `currentPhaseStartedAt` but never touches
            // `roundTimestamps`.
            guard let roundsStartedAt = session.roundsStartedAt, let end = session.roundTimestamps.last else {
                return MirrorSegment(label: label, value: unstartedValue, detail: nil, fraction: 0, state: .ahead)
            }
            let duration = SessionDerivation.netDuration(session, from: roundsStartedAt, to: end)
            return MirrorSegment(
                label: label,
                value: formatDuration(duration),
                detail: roundsDetail(countLabel: countLabel, session: session),
                fraction: fraction(duration, of: totalElapsed),
                state: .done
            )
        }

        guard session.phase == .rounds else {
            return MirrorSegment(label: label, value: unstartedValue, detail: nil, fraction: 0, state: .ahead)
        }

        guard let elapsed = elapsedSincePhaseStart(session, now: now) else {
            return MirrorSegment(label: label, value: unstartedValue, detail: roundsDetail(countLabel: countLabel, session: session), fraction: 0, state: .current)
        }
        return MirrorSegment(
            label: label,
            value: formatDuration(elapsed),
            detail: roundsDetail(countLabel: countLabel, session: session),
            fraction: fraction(elapsed, of: totalElapsed),
            state: .current
        )
    }

    /// "12 of 20" / "20 rounds", with the average round time appended once at
    /// least one round is in — never with zero rounds, where a "0:00 avg"
    /// would read as a broken timer rather than as "no data yet".
    private static func roundsDetail(countLabel: String, session: SessionState) -> String {
        guard session.completedRounds > 0 else { return countLabel }
        let durations = SessionDerivation.roundDurations(session)
        guard !durations.isEmpty else { return countLabel }
        let average = durations.reduce(0, +) / Double(durations.count)
        return "\(countLabel)\(detailSeparator)\(formatDuration(average)) avg"
    }

    // MARK: - Shared helpers

    /// The in-progress segment's elapsed-so-far, net of pauses. `nil` only
    /// when `currentPhaseStartedAt` itself is nil, which happens after an
    /// abandon — there is then no start point left to measure from.
    ///
    /// Routed through `SessionDerivation.netDuration` — the same net-of-pause
    /// formula `elapsed` and `roundDurations` use — rather than a private
    /// copy, so this file and `SessionDerivation` cannot quietly disagree
    /// about what "net of pause" means.
    private static func elapsedSincePhaseStart(_ session: SessionState, now: Date) -> TimeInterval? {
        guard let phaseStart = session.currentPhaseStartedAt else { return nil }
        return SessionDerivation.netDuration(session, from: phaseStart, to: now)
    }

    /// Guards the division: a zero or negative denominator (no elapsed time
    /// yet) must yield 0, never NaN or infinity reaching a view.
    private static func fraction(_ duration: TimeInterval, of totalElapsed: TimeInterval) -> Double {
        guard totalElapsed > 0 else { return 0 }
        return max(0, min(1, duration / totalElapsed))
    }
}
