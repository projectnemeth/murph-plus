// MurphPlus/Views/History/SessionDetailValue.swift
import Foundation

/// Builds the trailing value strings for the session detail split rows.
///
/// Separated from the view because the interesting part is which fields are
/// absent, not how they are laid out: heart rate and distance exist only on
/// Watch-collected sessions, so every v1 and every phone-owned session renders
/// the bare duration. That is the common path, and it is what the tests pin.
enum SessionDetailValue {
    private static let metresPerMile = 1609.34

    static func run(duration: String, distanceMeters: Double?, avgHeartRate: Int?) -> String {
        var parts = [duration]
        if let distanceMeters {
            parts.append(String(format: "%.2f mi", distanceMeters / metresPerMile))
        }
        if let avgHeartRate {
            parts.append("\(avgHeartRate) bpm")
        }
        return parts.joined(separator: " · ")
    }

    static func round(duration: String, avgHeartRate: Int?) -> String {
        guard let avgHeartRate else { return duration }
        return "\(duration) · \(avgHeartRate) bpm"
    }
}
