// MurphPlus/Support/DurationFormatting.swift
import Foundation

func formatDuration(_ seconds: Double) -> String {
    let total = Int(max(0, seconds))
    return String(format: "%d:%02d", total / 60, total % 60)
}
