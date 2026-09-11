// MurphCore/LocationFixGate.swift
import Foundation
import Observation

/// The bounded wait between countdown zero and the workout starting, held
/// only while GPS is still acquiring.
///
/// In the ordinary case this is invisible: the receiver has been warming since
/// the setup screen appeared, so a fix has long since landed and `wait`
/// returns without suspending once.
///
/// Bounded on purpose. The standing contract is that no sensor may block the
/// workout (see `WorkoutControlling`), and an unbounded wait breaks it the
/// first time the user runs somewhere with a poor sky view. `skip()` is
/// available from the first frame; the timeout is the backstop for a user who
/// is not looking at the watch.
///
/// In `MurphCore` and free of CoreLocation for the same reason
/// `StartCountdown` is free of WatchKit: the watch target has no test bundle,
/// so anything with real logic has to be reachable from the iOS one. It takes
/// a closure rather than a `LocationProviding` because it needs exactly one
/// value, polled.
@MainActor
@Observable
final class LocationFixGate {
    static let defaultTimeout: TimeInterval = 30

    /// Drives the "Acquiring GPS" overlay. `false` whenever `wait` is not
    /// actively holding, including before it is ever called.
    private(set) var isWaiting = false

    private let timeout: TimeInterval
    private let pollInterval: TimeInterval
    private let sleep: (Duration) async throws -> Void
    private var skipped = false

    /// Polling rather than a continuation resumed by the delegate: the state
    /// being watched is already `@Observable` and changes on the main actor,
    /// and a bounded poll has no way to leak a continuation that is never
    /// resumed. At 200 ms the user cannot perceive the latency.
    ///
    /// - Parameter sleep: injected so tests do not wait thirty real seconds.
    init(
        timeout: TimeInterval = LocationFixGate.defaultTimeout,
        pollInterval: TimeInterval = 0.2,
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.timeout = timeout
        self.pollInterval = pollInterval
        self.sleep = sleep
    }

    /// Counted rather than measured against the wall clock, so an injected
    /// `sleep` that does not advance real time still exercises the bound.
    private var maxPolls: Int {
        guard pollInterval > 0 else { return 1 }
        return max(1, Int((timeout / pollInterval).rounded()))
    }

    /// Returns as soon as the fix is usable, the user skips, or the bound is
    /// reached — whichever comes first. Returns immediately for every state
    /// except `.acquiring`.
    func wait(fixState: @escaping () -> GPSFixState) async {
        // Cleared here, not in `skip()`: a skip from a previous workout must
        // not release the next one before it has waited at all.
        skipped = false
        guard fixState() == .acquiring else { return }

        isWaiting = true
        defer { isWaiting = false }

        var remaining = maxPolls
        while remaining > 0 {
            do {
                try await sleep(.seconds(pollInterval))
            } catch {
                // Swallowed deliberately: the caller (`StartCountdown`'s `go`,
                // after the count has already completed uninterrupted) simply
                // proceeds into `startSession` on any thrown `sleep`, cancellation
                // included. There is no live path to a cancelled wait today —
                // the acquiring overlay offers only "Start anyway", no Cancel —
                // but if one is ever added here, note that it means a
                // cancelled wait still starts the workout. Whoever adds that
                // button should decide that on purpose rather than inherit it.
                return
            }
            if skipped { return }
            if fixState() != .acquiring { return }
            remaining -= 1
        }
    }

    /// Start anyway.
    func skip() { skipped = true }
}
