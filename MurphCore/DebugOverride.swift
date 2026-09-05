// MurphCore/DebugOverride.swift
import Foundation

/// Launch-argument overrides for the two constants the hardware matrix cannot
/// otherwise reach.
///
/// Three tests in that matrix — 10, 11 and 12 — are not runnable as shipped:
/// one needs a six-hour threshold to be a minute, the others need a 60,000-byte
/// ceiling to be small enough that an ordinary workout crosses it. The
/// instruction was "make the edit, run the check, revert before committing",
/// which puts a production constant one forgotten `git checkout` away from
/// shipping wrong — on a value whose failure mode is a silently dropped
/// checkpoint.
///
/// Reads through `UserDefaults`, so `-MurphUserInfoByteLimit 2000` in a scheme's
/// launch arguments is all it takes: Apple's argument domain picks those up
/// automatically, and nothing has to be edited or put back.
///
/// `#if DEBUG`, so a release build cannot be talked into a different limit by
/// anything at all.
enum DebugOverride {
    static func int(_ key: String) -> Int? {
        #if DEBUG
        // `object(forKey:)` rather than `integer(forKey:)`: the latter returns
        // 0 for a key that is not set, which is indistinguishable from a
        // deliberate 0 and would silently become the value in use.
        return UserDefaults.standard.object(forKey: key) as? Int
        #else
        return nil
        #endif
    }

    static func seconds(_ key: String) -> TimeInterval? {
        #if DEBUG
        guard let value = UserDefaults.standard.object(forKey: key) else { return nil }
        if let seconds = value as? TimeInterval { return seconds }
        if let seconds = value as? Int { return TimeInterval(seconds) }
        // Launch arguments arrive as strings when the value is not a plist
        // number, which is exactly how they arrive from a scheme.
        if let text = value as? String { return TimeInterval(text) }
        return nil
        #else
        return nil
        #endif
    }
}
