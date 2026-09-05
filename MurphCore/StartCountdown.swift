// MurphCore/StartCountdown.swift
import Foundation
import Observation

/// The 3·2·1 before a session starts, as the built-in Workout app does it.
///
/// In MurphCore, and deliberately free of WatchKit, for the same reason
/// `WatchSessionController` is: the watch target has no test bundle, so
/// anything with real logic has to be reachable from the iOS one. Haptics are
/// therefore a closure the caller supplies (`onTick`), not a call this type
/// makes.
///
/// The contract that matters: `go` runs **only** when the count reaches zero
/// uninterrupted. Cancelling — a tap, or the view going away — must leave no
/// session behind, which is why the caller does all of its starting work
/// inside `go` rather than before the count.
@MainActor
@Observable
final class StartCountdown {
    /// The number on screen, or `nil` when no count is running. Drives both
    /// the display and `isRunning`, so there is one source of truth for "is
    /// the user mid-countdown".
    private(set) var remaining: Int?

    /// Called once per tick with the number just shown — the haptic seam.
    /// Not called for the final zero; use the completion of `go` for that.
    var onTick: ((Int) -> Void)?

    private let seconds: Int
    private let sleep: (Duration) async throws -> Void
    private var task: Task<Void, Never>?

    var isRunning: Bool { remaining != nil }

    /// - Parameter sleep: injected so tests do not wait three real seconds.
    ///   It stays a *throwing* async call rather than a plain delay because
    ///   cancellation propagates through it — that is what stops a cancelled
    ///   count from ever reaching `go`.
    init(
        seconds: Int = 3,
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.seconds = seconds
        self.sleep = sleep
    }

    /// Starts counting, then runs `go`.
    ///
    /// A count already in flight is cancelled first, so a double tap starts
    /// one workout rather than two.
    func start(then go: @escaping () async -> Void) {
        cancel()

        // A zero-second countdown is a legitimate configuration (a settings
        // toggle would produce one), and it must start the workout rather than
        // silently do nothing.
        guard seconds > 0 else {
            task = Task { await go() }
            return
        }

        remaining = seconds
        task = Task { [weak self] in
            guard let self else { return }
            var value = self.seconds
            while value > 0 {
                self.remaining = value
                self.onTick?(value)
                do {
                    try await self.sleep(.seconds(1))
                } catch {
                    // Cancelled mid-tick. `cancel()` has already cleared
                    // `remaining`; the workout never starts.
                    return
                }
                guard !Task.isCancelled else { return }
                value -= 1
            }
            self.remaining = nil
            await go()
        }
    }

    /// Abandons the count. Safe to call when nothing is running.
    func cancel() {
        task?.cancel()
        task = nil
        remaining = nil
    }
}
