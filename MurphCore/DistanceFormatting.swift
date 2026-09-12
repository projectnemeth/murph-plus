// MurphCore/DistanceFormatting.swift
import Foundation

/// The one metres-to-miles conversion in the codebase.
///
/// Originally lived in `MurphPlus/Support` so the phone's live readout and
/// its history row couldn't round the same run differently. Moved into
/// `MurphCore` — the same reason `RunModeStatus` lives here — because the
/// watch needs this exact conversion too: `PrimaryPage`'s distance readout
/// used to carry its own inlined `1609.34`, so a runner's phone and watch
/// could disagree about the distance of the run they just did together.
/// `MurphCore` is pure Foundation with no UIKit/SwiftUI, and it is the one
/// source directory both the `MurphPlus` and `MurphPlusWatch` targets
/// compile (see `project.yml`), so it is the only place a shared constant
/// can live without one target losing sight of it.
private let metresPerMile: Double = 1609.34

/// GPS metres to runners' miles, as a `Double`. Every string formatter below
/// is defined in terms of this so there is exactly one division in the
/// codebase — a caller that needs to do arithmetic on the distance (the
/// watch's "miles remaining" readout) gets the same rounding-free value the
/// string formatters start from, rather than a second inlined conversion.
func milesValue(_ meters: Double) -> Double {
    meters / metresPerMile
}

/// e.g. `"0.72 mi"`.
///
/// Hoisted out of `SessionDetailValue`, which held the conversion privately,
/// so the live readout and the history row cannot round differently and
/// disagree about the same run.
func formatMiles(_ meters: Double) -> String {
    String(format: "%.2f mi", milesValue(meters))
}

/// e.g. `"0.72"` — `formatMiles` without the unit suffix, for a caller that
/// supplies its own "miles" label alongside the number rather than wanting
/// it repeated inline. Two callers today, on both devices: the watch's
/// distance readout, which prints a "Distance" caption above the number, and
/// the phone's run hero, which renders the unit separately at a different
/// size and weight from the value it labels.
func formatMilesValue(_ meters: Double) -> String {
    String(format: "%.2f", milesValue(meters))
}
