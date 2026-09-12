// MurphPlus/Support/DistanceFormatting.swift
import Foundation

private let metresPerMile: Double = 1609.34

/// e.g. `"0.72 mi"`.
///
/// Hoisted out of `SessionDetailValue`, which held the conversion privately,
/// so the live readout and the history row cannot round differently and
/// disagree about the same run.
func formatMiles(_ meters: Double) -> String {
    String(format: "%.2f mi", meters / metresPerMile)
}

/// The same figure as `formatMiles`, without the " mi" suffix.
///
/// The run-hero numeral renders its unit separately, at a different size and
/// weight, from the value it labels — so the value must come back bare. It
/// still routes through `metresPerMile` here rather than a second constant,
/// for the same reason `formatMiles` does: one conversion, so the live
/// readout and the hero cannot round the same run differently.
func formatMilesValue(_ meters: Double) -> String {
    String(format: "%.2f", meters / metresPerMile)
}
