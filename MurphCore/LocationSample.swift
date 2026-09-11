// MurphCore/LocationSample.swift
import Foundation

/// One GPS reading, expressed without CoreLocation.
///
/// Foundation-only for the reason `LocationProviding` is: `MurphCore` compiles
/// into both targets, and the iOS bundle is the only test bundle in the
/// project. Feeding `RunDistanceAccumulator` plain values rather than
/// `CLLocation` is what lets the one numerically load-bearing type in this
/// feature be tested against recorded traces, with no hardware and no
/// simulator location fixtures.
struct LocationSample: Equatable {
    var latitude: Double
    var longitude: Double
    /// Metres. A NEGATIVE value means the fix is invalid, not precise — the
    /// sign is the validity flag.
    var horizontalAccuracy: Double
    /// Metres per second. Negative means unavailable.
    var speed: Double
    var timestamp: Date
}
