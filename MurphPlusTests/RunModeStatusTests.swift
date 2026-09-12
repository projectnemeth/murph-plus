// MurphPlusTests/RunModeStatusTests.swift
import XCTest
@testable import MurphPlus

final class RunModeStatusTests: XCTestCase {

    /// Indoor must ignore `fixState` entirely — the receiver is stopped on
    /// that path, so a leaked `.acquiring` or `.denied` would tell the runner
    /// to go fix something that was never being measured in the first place.
    /// Asserting all four cases explicitly means a future change that lets
    /// `fixState` leak through the indoor branch fails right here, not on a
    /// screen months later.
    func test_indoorIsTheNeutralTreadmillCaptionForEveryFixState() {
        let expected = RunModeStatus(
            text: "Treadmill or track \u{00b7} the run distance isn\u{2019}t measured",
            tone: .neutral
        )
        XCTAssertEqual(RunModeStatus.of(indoor: true, fixState: .off), expected)
        XCTAssertEqual(RunModeStatus.of(indoor: true, fixState: .denied), expected)
        XCTAssertEqual(RunModeStatus.of(indoor: true, fixState: .acquiring), expected)
        XCTAssertEqual(RunModeStatus.of(indoor: true, fixState: .fixed), expected)
    }

    /// The one state where the run is actually measurable — the caption
    /// should say so plainly, and read as good news (`.ready`).
    func test_outdoorFixedIsReady() {
        let status = RunModeStatus.of(indoor: false, fixState: .fixed)
        XCTAssertEqual(status.text, "GPS ready \u{00b7} the run distance is measured")
        XCTAssertEqual(status.tone, .ready)
    }

    /// `.acquiring` and `.off` are both mid-warm-up, not failures, and both
    /// read as `.pending` — the runner shouldn't see a warning colour for a
    /// fix that just hasn't arrived yet.
    func test_acquiringAndOffAreBothPending() {
        XCTAssertEqual(RunModeStatus.of(indoor: false, fixState: .acquiring).tone, .pending)
        XCTAssertEqual(RunModeStatus.of(indoor: false, fixState: .off).tone, .pending)
        XCTAssertEqual(RunModeStatus.of(indoor: false, fixState: .acquiring).text, "Acquiring GPS\u{2026}")
        XCTAssertEqual(RunModeStatus.of(indoor: false, fixState: .off).text, "Starting GPS\u{2026}")
    }

    /// `.denied` is the one state where waiting is pointless — a fix will
    /// never come — so it gets its own tone rather than sharing `.pending`.
    func test_deniedIsUnavailable() {
        let status = RunModeStatus.of(indoor: false, fixState: .denied)
        XCTAssertEqual(status.text, "Location access is off \u{00b7} the run distance isn\u{2019}t measured")
        XCTAssertEqual(status.tone, .unavailable)
    }

    /// `.denied` and indoor both say "the distance isn't measured," but for
    /// different reasons — one is a problem worth fixing, the other a choice
    /// that needs no fixing at all. That distinction is the entire reason a
    /// fourth tone exists, so assert the tones differ rather than just that
    /// each text matches its own table row.
    func test_deniedAndIndoorShareNoMeasurementButNotTone() {
        let denied = RunModeStatus.of(indoor: false, fixState: .denied)
        let indoor = RunModeStatus.of(indoor: true, fixState: .off)
        XCTAssertNotEqual(denied.tone, indoor.tone)
    }
}
