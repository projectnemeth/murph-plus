// MurphPlusTests/DebugOverrideTests.swift
import XCTest
@testable import MurphPlus

/// The launch-argument overrides that make hardware tests 10, 11 and 12
/// runnable without editing a production constant and having to remember to
/// put it back.
final class DebugOverrideTests: XCTestCase {
    private let intKey = "MurphTestOverrideInt"
    private let secondsKey = "MurphTestOverrideSeconds"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: intKey)
        UserDefaults.standard.removeObject(forKey: secondsKey)
        super.tearDown()
    }

    func test_absentKeyReadsAsNoOverride() {
        XCTAssertNil(DebugOverride.int(intKey))
        XCTAssertNil(DebugOverride.seconds(secondsKey))
    }

    /// The trap `object(forKey:)` avoids: `integer(forKey:)` returns 0 for an
    /// unset key, which is indistinguishable from a deliberate 0 — and a
    /// zero-byte `userInfoByteLimit` would send every checkpoint by file.
    func test_zeroIsAnOverride_notAnAbsence() {
        UserDefaults.standard.set(0, forKey: intKey)
        XCTAssertEqual(DebugOverride.int(intKey), 0)
    }

    func test_readsAnIntOverride() {
        UserDefaults.standard.set(2_000, forKey: intKey)
        XCTAssertEqual(DebugOverride.int(intKey), 2_000)
    }

    /// Launch arguments arrive as strings, which is how they come from a
    /// scheme — the whole point of the seam.
    func test_readsSecondsFromAString() {
        UserDefaults.standard.set("60", forKey: secondsKey)
        XCTAssertEqual(DebugOverride.seconds(secondsKey), 60)
    }

    func test_readsSecondsFromANumber() {
        UserDefaults.standard.set(90, forKey: secondsKey)
        XCTAssertEqual(DebugOverride.seconds(secondsKey), 90)
    }

    func test_ignoresAValueThatIsNotANumber() {
        UserDefaults.standard.set("soon", forKey: secondsKey)
        XCTAssertNil(DebugOverride.seconds(secondsKey))
    }

    /// With nothing set, the shipping values are what the app uses.
    func test_theShippedConstantsAreWhatIsInUse() {
        XCTAssertEqual(SyncPayload.userInfoByteLimit, SyncPayload.defaultUserInfoByteLimit)
        XCTAssertEqual(StuckWatchSessionReaper.defaultThreshold, StuckWatchSessionReaper.shippedThreshold)
    }
}
