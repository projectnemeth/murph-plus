// MurphPlusTests/DistanceFormattingTests.swift
import XCTest
@testable import MurphPlus

final class DistanceFormattingTests: XCTestCase {

    /// A known metres value with an unambiguous miles conversion, so a typo
    /// in the shared constant (or a stray extra rounding step) fails an
    /// exact number rather than a fuzzy comparison.
    func test_milesValueConvertsAKnownDistance() {
        XCTAssertEqual(milesValue(1609.34), 1.0, accuracy: 0.0001)
        XCTAssertEqual(milesValue(804.67), 0.5, accuracy: 0.0001)
    }

    /// Characterisation test: pins `formatMiles`'s exact output so moving the
    /// conversion into `MurphCore` cannot silently change what the phone's
    /// live readout and history row render.
    func test_formatMilesMatchesItsPreMoveOutput() {
        XCTAssertEqual(formatMiles(1158.7), "0.72 mi")
    }

    /// Characterisation test: `formatMilesValue` is `formatMiles` without the
    /// unit suffix — the form the watch's distance readout needs, since it
    /// supplies its own "Distance" label alongside the number.
    func test_formatMilesValueMatchesItsPreMoveOutput() {
        XCTAssertEqual(formatMilesValue(1158.7), "0.72")
    }

    /// The actual regression this change fixes: before this move,
    /// `PrimaryPage` (watch) inlined its own `1609.34` instead of sharing the
    /// phone's conversion in `DistanceFormatting.swift`, so the phone's live
    /// readout and the watch's distance readout could round the same run
    /// differently and disagree. `formatMiles` is what the phone renders
    /// (`SessionDetailValue`, `LiveSessionView`); `formatMilesValue` is what
    /// the watch's `PrimaryPage.distanceText` now renders. Stripping the
    /// phone's " mi" suffix and comparing proves both now derive the
    /// identical value from the same metres.
    func test_phoneAndWatchDeriveTheSameMilesFromTheSameMetres() {
        let meters = 1158.7
        let phoneRendered = formatMiles(meters).replacingOccurrences(of: " mi", with: "")
        let watchRendered = formatMilesValue(meters)
        XCTAssertEqual(phoneRendered, watchRendered)
    }
}
