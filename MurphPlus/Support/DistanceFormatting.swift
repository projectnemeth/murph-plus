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
