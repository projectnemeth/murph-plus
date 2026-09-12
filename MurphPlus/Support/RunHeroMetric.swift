// MurphPlus/Support/RunHeroMetric.swift
import Foundation

/// Which figure the hero slot is currently the giant numeral for.
///
/// Kept alongside `RunHeroMetric` rather than folded into it as a `Bool`
/// because a future third hero (pace, say) would otherwise force every
/// call site to reinterpret what `true`/`false` meant.
enum RunHeroKind: Equatable {
    case distance
    case elapsed
}

/// What the hero slot on the live-run screen shows, and the caption and
/// progress bar underneath it.
///
/// A pure mapping from the session state that decides it — same reason
/// `RunModeStatus` lives here rather than in a view: this is a small decision
/// table with a rank between its inputs, and this file is where the repo
/// puts logic it wants tested without a simulator. Lives in `MurphPlus`
/// rather than `MurphCore` because its distance formatting calls
/// `formatMilesValue` (`DistanceFormatting.swift`), which is not part of the
/// watch target's sources — see `project.yml`.
struct RunHeroMetric: Equatable {
    let kind: RunHeroKind
    let label: String
    let value: String
    let caption: String?
    let progress: Double?
    let accessibilityText: String

    /// - Parameters:
    ///   - indoor: Whether the runner picked the indoor path at setup.
    ///     Outranks every other input, exactly as in `RunModeStatus`: on the
    ///     indoor path distance is never measured, so nothing else here is
    ///     worth consulting.
    ///   - distanceIsTrustworthy: Whether the current distance reading is
    ///     fit to show as a giant confident numeral. A jumpy or stale
    ///     reading rendered huge would mislead a runner more than showing
    ///     nothing. This is not the same fact as `distanceMeters == nil` —
    ///     see below.
    ///   - distanceMeters: The current distance, or `nil` before a figure
    ///     exists at all.
    ///   - targetMiles: The template's run distance, or `nil` for a free run
    ///     with nothing to divide against.
    ///   - elapsedSeconds: The run clock, used whenever the hero falls back
    ///     to elapsed time.
    ///
    /// `!distanceIsTrustworthy` and `distanceMeters == nil` both fall back to
    /// the elapsed hero, but they are not the same state, and the fallback
    /// caption must say which one is true. `distanceMeters == nil` means the
    /// receiver genuinely has not produced a figure yet — GPS is warming, and
    /// "Waiting for GPS…" is a promise that will be kept shortly.
    /// `!distanceIsTrustworthy` means something else entirely:
    /// `SessionEngine` sets `runDistanceUntrustworthy = isRun(state.phase)` at
    /// init (`SessionEngine.swift:45`) — that is, whenever the app relaunches
    /// into a session that was already mid-run — and clears it only inside
    /// `beginRun()`, when a *new* run leg starts (`SessionEngine.swift:360`).
    /// So on a resumed leg the flag cannot clear before that leg ends: GPS is
    /// perfectly healthy, but this leg's distance is unrecoverable for its
    /// entire remaining length. Telling the runner "Waiting for GPS…" there
    /// promises a fix that is never coming. `!distanceIsTrustworthy` is
    /// checked first because it is the more specific truth and can coincide
    /// with `distanceMeters == nil`.
    static func of(
        indoor: Bool,
        distanceIsTrustworthy: Bool,
        distanceMeters: Double?,
        targetMiles: Double?,
        elapsedSeconds: Double
    ) -> RunHeroMetric {
        let elapsedValue = formatDuration(elapsedSeconds)

        guard !indoor else {
            return RunHeroMetric(
                kind: .elapsed,
                label: "Elapsed",
                value: elapsedValue,
                caption: "Indoor \u{00b7} distance not measured",
                progress: nil,
                accessibilityText: "Elapsed \(elapsedValue). Indoor, distance not measured."
            )
        }

        guard distanceIsTrustworthy else {
            return RunHeroMetric(
                kind: .elapsed,
                label: "Elapsed",
                value: elapsedValue,
                caption: "Distance not recorded for this run",
                progress: nil,
                accessibilityText: "Elapsed \(elapsedValue). Distance not recorded for this run."
            )
        }

        guard let distanceMeters else {
            return RunHeroMetric(
                kind: .elapsed,
                label: "Elapsed",
                value: elapsedValue,
                caption: "Waiting for GPS\u{2026}",
                progress: nil,
                accessibilityText: "Elapsed \(elapsedValue). Waiting for GPS."
            )
        }

        let value = formatMilesValue(distanceMeters)
        // Reread from the rounded string rather than dividing meters by a
        // second, separately-maintained conversion constant: this way the
        // progress bar and the numeral above it always agree, because they
        // come from the same figure.
        let miles = Double(value) ?? 0

        // A zero or negative target isn't "no progress" — it's not a target
        // at all. Dividing by it anyway would either crash or draw a bar for
        // a distance that was never asked for.
        if let targetMiles, targetMiles > 0 {
            // Same "%.2f" route as the numeral above (`formatMilesValue`),
            // not `.formatted(...)`: the two numbers sit directly adjacent at
            // 96pt, and `.formatted` is locale-aware (comma decimals) while
            // "%.2f" is not, so a comma-decimal locale would otherwise show
            // two adjacent numbers with disagreeing separators.
            let targetText = String(format: "%.2f", targetMiles)
            let progress = min(1.0, max(0.0, miles / targetMiles))
            return RunHeroMetric(
                kind: .distance,
                label: "Distance",
                value: value,
                caption: "MI OF \(targetText)",
                progress: progress,
                accessibilityText: "Distance \(value) of \(targetText) miles"
            )
        }

        return RunHeroMetric(
            kind: .distance,
            label: "Distance",
            value: value,
            caption: "MI",
            progress: nil,
            accessibilityText: "Distance \(value) miles"
        )
    }
}
