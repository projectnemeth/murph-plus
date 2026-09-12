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
    ///     nothing.
    ///   - distanceMeters: The current distance, or `nil` before a figure
    ///     exists at all.
    ///   - targetMiles: The template's run distance, or `nil` for a free run
    ///     with nothing to divide against.
    ///   - elapsedSeconds: The run clock, used whenever the hero falls back
    ///     to elapsed time.
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

        guard distanceIsTrustworthy, let distanceMeters else {
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
            let targetText = targetMiles.formatted(.number.precision(.fractionLength(2)))
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
