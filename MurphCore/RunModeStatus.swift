// MurphCore/RunModeStatus.swift
import Foundation

/// The colour a `RunModeStatus` caption reads in, chosen for what it tells the
/// runner about their *next* action rather than for its literal accuracy.
///
/// `.unavailable` and `.neutral` both land on "distance isn't measured", but
/// they are not the same fact: one is a problem worth fixing (grant location
/// access), the other is a choice that needs no fixing at all (you picked
/// indoor). Collapsing them to one tone would make the runner go looking for
/// a Settings toggle that was never the issue.
enum RunModeStatusTone: Equatable {
    /// A fix has landed — lime500.
    case ready
    /// Still warming, or the receiver hasn't been asked to start yet — dust500.
    case pending
    /// A fix will never come this session — blood500.
    case unavailable
    /// Indoor. Nothing is wrong; there is simply nothing to report — ash300.
    case neutral
}

/// The caption shown beneath the run-mode control, and the tone it reads in.
///
/// A pure mapping from the two things that caption depends on — same reason
/// `WatchPhaseLabel` lives in `MurphCore` rather than a view: this is real
/// logic (a small decision table with a rank between its inputs), and
/// `MurphCore` is where this repo puts logic it wants tested without a
/// simulator.
struct RunModeStatus: Equatable {
    let text: String
    let tone: RunModeStatusTone

    /// - Parameters:
    ///   - indoor: Whether the runner picked the indoor path at setup.
    ///   - fixState: The receiver's current state. Ignored when `indoor` is
    ///     true — see below.
    ///
    /// `indoor` outranks `fixState` deliberately: on the indoor path the
    /// receiver is stopped (`LocationPolicy` never warms it), so its state is
    /// `.off` as a *consequence* of the choice the runner already made, not a
    /// condition worth reporting on top of it. Reporting it anyway would read
    /// as "GPS is off" on a screen where GPS was never asked to be on.
    static func of(indoor: Bool, fixState: GPSFixState) -> RunModeStatus {
        guard !indoor else {
            return RunModeStatus(
                text: "Treadmill or track \u{00b7} the run distance isn\u{2019}t measured",
                tone: .neutral
            )
        }

        switch fixState {
        case .fixed:
            return RunModeStatus(
                text: "GPS ready \u{00b7} the run distance is measured",
                tone: .ready
            )
        case .acquiring:
            return RunModeStatus(text: "Acquiring GPS\u{2026}", tone: .pending)
        case .off:
            // Outdoor but not yet warming — e.g. the instant setup switches
            // from indoor to outdoor, before `LocationPolicy` has had a tick
            // to start the receiver. Read the same as "acquiring" rather than
            // as a problem: nothing has failed, the ask just hasn't landed.
            return RunModeStatus(text: "Starting GPS\u{2026}", tone: .pending)
        case .denied:
            return RunModeStatus(
                text: "Location access is off \u{00b7} the run distance isn\u{2019}t measured",
                tone: .unavailable
            )
        }
    }
}
