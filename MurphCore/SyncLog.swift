// MurphCore/SyncLog.swift
import Foundation
import os

/// One place for everything the Watch↔phone link says about itself.
///
/// The link logged **only failures**, which is exactly the wrong half. When a
/// checkpoint simply never arrives there is nothing in Console at all, so
/// "never sent" and "sent but not delivered" are indistinguishable — and those
/// two have opposite fixes. The hardware matrix hit that wall on test 09 (a
/// finished workout lost across a phone reboot) and could not go further by
/// reading code.
///
/// So successes are logged too, on both sides, with the facts needed to pair a
/// send with its arrival: session, sequence number, carrier and size. This is
/// meant to stay in the shipping app. The feature's whole failure surface is
/// silent by construction — a queued transfer that never lands raises nothing —
/// and one line per checkpoint is roughly 25 lines per workout.
///
/// `os.Logger` rather than `NSLog` so Console can filter on the subsystem and
/// category instead of a string match. Every interpolation is explicitly
/// `.public`: the default redacts dynamic values to `<private>`, which would
/// leave the log saying a checkpoint moved without saying which one.
enum SyncLog {
    private static let log = Logger(subsystem: "com.projectnemeth.MurphPlus", category: "sync")

    /// Which WatchConnectivity channel carried a checkpoint. Both are queued
    /// and guaranteed; they differ only in size ceiling, so knowing which one
    /// ran is the difference between "the file path is broken" and "the file
    /// path was never taken".
    enum Carrier: String {
        case userInfo
        case file
    }

    // MARK: - Watch side

    /// - Parameter reachable: whether the phone was reachable *at the moment of
    ///   handoff*. Both carriers queue, so an unreachable phone is not a
    ///   failure — but it is the difference between a checkpoint that should
    ///   have landed immediately and one that was always going to wait, which
    ///   is the first question asked of any missing session.
    static func checkpointSent(
        sessionID: UUID, seq: Int, bytes: Int, carrier: Carrier, reachable: Bool
    ) {
        log.notice("""
            sent checkpoint \(seq, privacy: .public) \
            session \(sessionID.uuidString, privacy: .public) \
            \(bytes, privacy: .public)B via \(carrier.rawValue, privacy: .public) \
            reachable=\(reachable, privacy: .public)
            """)
    }

    /// The counterpart that did not exist, and the one that matters most: a
    /// checkpoint the Watch decided not to send. Every early return in
    /// `transferCheckpoint` goes through here, `reason` naming which.
    static func checkpointDropped(sessionID: UUID, seq: Int, reason: String) {
        log.error("""
            DROPPED checkpoint \(seq, privacy: .public) \
            session \(sessionID.uuidString, privacy: .public) — \(reason, privacy: .public)
            """)
    }

    // MARK: - Phone side

    static func checkpointArrived(bytes: Int, carrier: Carrier) {
        log.notice("""
            received \(bytes, privacy: .public)B \
            via \(carrier.rawValue, privacy: .public)
            """)
    }

    /// Logged separately from arrival because they are different failures:
    /// arriving and being rejected by the merge rule is a sequencing problem,
    /// while never arriving is a delivery one.
    static func checkpointApplied(sessionID: UUID, seq: Int, terminal: Bool) {
        log.notice("""
            applied checkpoint \(seq, privacy: .public) \
            session \(sessionID.uuidString, privacy: .public) \
            terminal=\(terminal, privacy: .public)
            """)
    }

    static func checkpointIgnored(sessionID: UUID, seq: Int, reason: String) {
        log.notice("""
            ignored checkpoint \(seq, privacy: .public) \
            session \(sessionID.uuidString, privacy: .public) — \(reason, privacy: .public)
            """)
    }

    // MARK: - Both

    static func failure(_ message: String) {
        log.error("\(message, privacy: .public)")
    }

    static func note(_ message: String) {
        log.notice("\(message, privacy: .public)")
    }
}
