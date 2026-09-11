# Watch GPS Run Distance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the GPS receiver during the two runs and keep it off through the rounds, so run distance stops being an accelerometer guess.

**Architecture:** A new `LocationProviding` seam in `MurphCore`, kept separate from `WorkoutControlling` because the receiver must warm while the user is still on the setup screen — before any `HKWorkoutSession` exists. A pure `LocationPolicy` answers "should GPS be on, given where the session is", so `WatchSessionController` reconciles against it at transitions it already owns, and relaunch recovery needs no special path. Distance itself still comes from HealthKit; Core Location only powers the receiver.

**Tech Stack:** Swift 5, SwiftUI, CoreLocation, HealthKit, XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-11-watch-gps-distance-design.md`

## Global Constraints

- **`MurphCore` imports Foundation (and `Observation`) only.** No CoreLocation, no HealthKit, no SwiftUI. `WatchSessionController` compiles into the phone target so the iOS test bundle can reach it (`project.yml:19`); anything it touches must follow it there.
- **The watch target has no test bundle.** Every test in this plan lives in `MurphPlusTests` and runs on the iOS simulator.
- **`UIBackgroundModes: [location]` and `allowsBackgroundLocationUpdates = true` must land in the same commit.** The property without the plist key is a documented fatal error that terminates the app on launch.
- **`WKBackgroundModes` has no `location` value.** Valid values are `workout-processing`, `self-care`, `mindfulness`, `physical-therapy`, `alarm`, `underwater-depth`. Do not add `location` there.
- **Accuracy threshold:** `20` metres horizontal. One named constant.
- **Gate bound:** `30` seconds. One named constant.
- **Authorization:** When In Use only. `NSLocationWhenInUseUsageDescription` already exists at `project.yml:64`. Do not request Always.
- **Run `xcodegen generate` after adding any new source file**, before building.
- **Test command:** `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
- **Watch build command:** `xcodebuild build -scheme MurphPlusWatch -destination 'generic/platform=watchOS' -project MurphPlus.xcodeproj`

---

## File Structure

| File | Responsibility |
|---|---|
| `MurphCore/LocationProviding.swift` (new) | `GPSFixState` enum + `LocationProviding` protocol. The seam. |
| `MurphCore/LocationPolicy.swift` (new) | One pure function: should the receiver be running for this `SessionState`. |
| `MurphCore/LocationFixGate.swift` (new) | The bounded wait for a fix at countdown zero. Injected sleep. |
| `MurphPlusWatch/Session/WatchLocationController.swift` (new) | The only type that touches `CLLocationManager`. No unit tests. |
| `MurphPlusWatch/Views/WatchAcquiringGPSView.swift` (new) | Full-screen "Acquiring GPS" overlay with Start anyway. |
| `MurphPlusWatch/Session/WatchSessionController.swift` (modify) | Holds the provider, reconciles it at existing transitions. |
| `MurphPlusWatch/Views/WatchSetupView.swift` (modify) | Setup-screen warm-up, Outdoor/Indoor toggle, hosts the gate. |
| `project.yml` (modify) | `UIBackgroundModes: [location]` on the watch target. |
| `MurphPlusTests/LocationPolicyTests.swift` (new) | The pure rule, table-driven. |
| `MurphPlusTests/LocationFixGateTests.swift` (new) | Gate behaviour with injected sleep. |
| `MurphPlusTests/WatchSessionControllerTests.swift` (modify) | `FakeLocationController` + lifecycle assertions. |

---

### Task 1: The seam and the policy

**Files:**
- Create: `MurphCore/LocationProviding.swift`
- Create: `MurphCore/LocationPolicy.swift`
- Test: `MurphPlusTests/LocationPolicyTests.swift`

**Interfaces:**
- Consumes: `SessionState`, `SessionPhase`, `TemplateSpec` (all existing in `MurphCore`).
- Produces: `GPSFixState` (`.off`/`.denied`/`.acquiring`/`.fixed`), `LocationProviding` (`fixState`, `requestAuthorization()`, `startUpdating()`, `stopUpdating()`), `LocationPolicy.shouldWarm(for:) -> Bool`.

- [ ] **Step 1: Write the failing tests**

Create `MurphPlusTests/LocationPolicyTests.swift`:

```swift
// MurphPlusTests/LocationPolicyTests.swift
import XCTest
@testable import MurphPlus

/// `SessionState` is normally only reachable through `replay`, but the policy
/// is a pure function *of* a state — building states by replay would be
/// testing the replay, not the rule. Authored directly on purpose.
final class LocationPolicyTests: XCTestCase {

    private func spec(rounds: Int) -> TemplateSpec {
        TemplateSpec(
            id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
            totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: rounds
        )
    }

    private func state(
        phase: SessionPhase, rounds: Int = 20,
        completed: Int = 0, indoor: Bool = false
    ) -> SessionState {
        var s = SessionState()
        s.template = spec(rounds: rounds)
        s.phase = phase
        s.completedRounds = completed
        s.indoor = indoor
        return s
    }

    func test_runsAlwaysWarm() {
        XCTAssertTrue(LocationPolicy.shouldWarm(for: state(phase: .run1)))
        XCTAssertTrue(LocationPolicy.shouldWarm(for: state(phase: .run2)))
    }

    func test_indoorNeverWarms() {
        XCTAssertFalse(LocationPolicy.shouldWarm(for: state(phase: .run1, indoor: true)))
        XCTAssertFalse(LocationPolicy.shouldWarm(for: state(phase: .run2, indoor: true)))
        XCTAssertFalse(
            LocationPolicy.shouldWarm(
                for: state(phase: .rounds, rounds: 20, completed: 19, indoor: true)
            )
        )
    }

    func test_roundsDoNotWarmUntilOneRemains() {
        XCTAssertFalse(LocationPolicy.shouldWarm(for: state(phase: .rounds, completed: 0)))
        XCTAssertFalse(LocationPolicy.shouldWarm(for: state(phase: .rounds, completed: 3)))
        XCTAssertFalse(LocationPolicy.shouldWarm(for: state(phase: .rounds, completed: 18)))
    }

    /// The pre-warm: one round of head start before run 2.
    func test_roundsWarmAtOneRemaining() {
        XCTAssertTrue(LocationPolicy.shouldWarm(for: state(phase: .rounds, completed: 19)))
    }

    /// Stated as "remaining <= 1" rather than "== 1" so a miscount past the
    /// total cannot switch the receiver back off mid-workout.
    func test_roundsWarmPastTheTotal() {
        XCTAssertTrue(LocationPolicy.shouldWarm(for: state(phase: .rounds, completed: 25)))
    }

    /// Falls out of the rule with no special case: at rounds-start the
    /// condition is already true, so the receiver simply never powers down.
    func test_singleRoundTemplateWarmsFromTheStartOfRounds() {
        XCTAssertTrue(
            LocationPolicy.shouldWarm(for: state(phase: .rounds, rounds: 1, completed: 0))
        )
    }

    func test_terminalAndUnstartedPhasesNeverWarm() {
        XCTAssertFalse(LocationPolicy.shouldWarm(for: state(phase: .notStarted)))
        XCTAssertFalse(LocationPolicy.shouldWarm(for: state(phase: .completed)))
    }

    /// A rounds phase with no template cannot answer the question; the safe
    /// answer is off, not a crash.
    func test_roundsWithoutATemplateDoNotWarm() {
        var s = SessionState()
        s.phase = .rounds
        XCTAssertFalse(LocationPolicy.shouldWarm(for: s))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/LocationPolicyTests
```

Expected: compile failure — `cannot find 'LocationPolicy' in scope`.

- [ ] **Step 3: Create the seam**

Create `MurphCore/LocationProviding.swift`:

```swift
// MurphCore/LocationProviding.swift
import Foundation

/// How usable the GPS fix currently is.
///
/// `.denied` is deliberately separate from `.off`: it is the one state where
/// waiting for a fix is waiting for something that will never arrive, and the
/// start gate branches on exactly that.
enum GPSFixState: Equatable {
    /// Not updating — indoor, mid-rounds, or never started.
    case off
    /// Refused or restricted. A fix will never come.
    case denied
    /// Updating, but no sample yet at usable accuracy.
    case acquiring
    /// A sample at or better than the accuracy threshold has arrived.
    case fixed
}

/// The GPS side of a session, expressed without CoreLocation.
///
/// Separate from `WorkoutControlling` rather than folded into it because the
/// two have different lifetimes: this one starts warming on the *setup*
/// screen, when there is no `HKWorkoutSession` to wrap and every method on
/// `WorkoutControlling` is contractually a no-op. Keeping it a protocol also
/// keeps CoreLocation out of `MurphCore` and lets the whole lifecycle be
/// exercised from the iOS test bundle — the watch target has none of its own.
///
/// Both `startUpdating` and `stopUpdating` MUST be idempotent. That is what
/// lets callers assert the desired state unconditionally instead of tracking
/// whether they already asked, which is what keeps `LocationPolicy` a pure
/// function rather than a second state machine.
@MainActor
protocol LocationProviding: AnyObject {
    var fixState: GPSFixState { get }

    /// Asks for When In Use. Returns once the request has been made — the
    /// answer arrives later via `fixState`, because CoreLocation reports
    /// authorization through a delegate callback, not a return value.
    func requestAuthorization() async

    func startUpdating()
    func stopUpdating()
}
```

- [ ] **Step 4: Create the policy**

Create `MurphCore/LocationPolicy.swift`:

```swift
// MurphCore/LocationPolicy.swift
import Foundation

/// Whether the GPS receiver should be running, given where the session is.
///
/// A pure function of `SessionState` and nothing else, which buys two things.
/// Relaunch recovery needs no separate path — replay the journal, ask this,
/// obey the answer — and the rule can be tested exhaustively without a watch.
///
/// Note what it does *not* consider: pause. A pause mid-run leaves the
/// receiver on deliberately. Pauses are typically short, and re-acquiring a
/// fix on resume costs more than the battery a short pause saves.
enum LocationPolicy {
    /// Runs need GPS. The rounds do not, until run 2 is one round away — that
    /// pre-warm is what buys run 2 a fix, since run 2 begins with the clock
    /// running and cannot be gated the way run 1 is.
    static func shouldWarm(for state: SessionState) -> Bool {
        guard !state.indoor else { return false }
        // An abandoned session keeps its phase: `SessionState.apply` leaves it
        // deliberately, because phase is the record of how far the attempt got
        // and the history screens show it. So a Murph abandoned mid-run still
        // reads `.run1` forever, and a phase-only rule would leave the receiver
        // running until the app died.
        guard !state.isTerminal else { return false }

        switch state.phase {
        case .run1, .run2:
            return true

        case .rounds:
            // No template means the question cannot be answered; off is the
            // safe answer, and this state is unreachable in a real session.
            guard let template = state.template else { return false }
            // "Remaining <= 1" rather than "completed == total - 1" so that a
            // single-round template warms from the moment rounds begin — with
            // no special case — and so no miscount past the total can switch
            // the receiver back off mid-workout.
            return template.safeRounds - state.completedRounds <= 1

        case .notStarted, .completed:
            return false
        }
    }
}
```

- [ ] **Step 5: Regenerate the project and run the tests**

```bash
xcodegen generate
xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/LocationPolicyTests
```

Expected: PASS, 8 tests.

- [ ] **Step 6: Commit**

```bash
git add MurphCore/LocationProviding.swift MurphCore/LocationPolicy.swift \
        MurphPlusTests/LocationPolicyTests.swift MurphPlus.xcodeproj
git commit -m "feat: add the LocationProviding seam and the warm-up policy"
```

---

### Task 2: The start gate

**Files:**
- Create: `MurphCore/LocationFixGate.swift`
- Test: `MurphPlusTests/LocationFixGateTests.swift`

**Interfaces:**
- Consumes: `GPSFixState` from Task 1.
- Produces: `LocationFixGate(timeout:pollInterval:sleep:)`, `.isWaiting: Bool`, `func wait(fixState: @escaping () -> GPSFixState) async`, `func skip()`, `static let defaultTimeout: TimeInterval`.

The gate takes a **closure returning `GPSFixState`**, not a `LocationProviding`. It needs one value, polled; a closure keeps it independent of the provider and trivial to drive from a test.

- [ ] **Step 1: Write the failing tests**

Create `MurphPlusTests/LocationFixGateTests.swift`:

```swift
// MurphPlusTests/LocationFixGateTests.swift
import XCTest
@testable import MurphPlus

@MainActor
final class LocationFixGateTests: XCTestCase {
    /// A real suspension, just a very short one — same reasoning as
    /// `StartCountdownTests`: a delay that does not actually suspend would let
    /// every test pass without exercising the polling at all.
    private func fastSleep(_: Duration) async throws {
        try await Task.sleep(for: .milliseconds(1))
    }

    private func gate(timeout: TimeInterval = 1, poll: TimeInterval = 0.1) -> LocationFixGate {
        LocationFixGate(timeout: timeout, pollInterval: poll, sleep: fastSleep)
    }

    func test_aFixReturnsImmediatelyWithoutWaiting() async {
        let g = gate()
        await g.wait { .fixed }
        XCTAssertFalse(g.isWaiting)
    }

    /// The case that matters most: waiting for a fix that will never come is
    /// pure delay in front of a workout.
    func test_deniedReturnsImmediately() async {
        let g = gate()
        await g.wait { .denied }
        XCTAssertFalse(g.isWaiting)
    }

    func test_offReturnsImmediately() async {
        let g = gate()
        await g.wait { .off }
        XCTAssertFalse(g.isWaiting)
    }

    func test_acquiringHoldsUntilAFixArrives() async {
        let g = gate(timeout: 10, poll: 0.1)
        var polls = 0
        await g.wait {
            polls += 1
            return polls < 4 ? .acquiring : .fixed
        }
        XCTAssertGreaterThanOrEqual(polls, 4)
        XCTAssertFalse(g.isWaiting)
    }

    /// Start anyway. Available from the first frame, not after a delay.
    ///
    /// `poll: 0.001` puts `maxPolls` at 100_000 — roughly 100 seconds at the
    /// 1 ms injected sleep, far outside the fulfillment window below. That is
    /// deliberate: with a bound the loop could reach on its own, this test
    /// would pass just as happily if `skip()` did nothing at all, which is
    /// exactly the regression it exists to catch.
    func test_skipEndsTheWaitEarly() async {
        let g = gate(timeout: 100, poll: 0.001)
        var polls = 0
        let done = expectation(description: "gate returned")
        Task {
            await g.wait {
                polls += 1
                return .acquiring
            }
            done.fulfill()
        }
        // Let the wait get going, then release it.
        try? await Task.sleep(for: .milliseconds(20))
        g.skip()
        await fulfillment(of: [done], timeout: 2)
        XCTAssertFalse(g.isWaiting)
        // Nowhere near the 100_000 bound: the wait ended because it was
        // skipped, not because it ran out.
        XCTAssertLessThan(polls, 1_000)
    }

    /// The bound is the whole reason this is safe: the standing contract is
    /// that no sensor may block the workout.
    func test_givesUpAtTheTimeout() async {
        let g = gate(timeout: 0.5, poll: 0.1)   // 5 polls
        var polls = 0
        await g.wait {
            polls += 1
            return .acquiring
        }
        // Six, not five: one read before deciding to wait at all, then one
        // per poll. A gate that did not read first would suspend even on a
        // fix it already had.
        XCTAssertEqual(polls, 6)
        XCTAssertFalse(g.isWaiting)
    }

    func test_isWaitingIsTrueWhileHolding() async {
        let g = gate(timeout: 100, poll: 0.1)
        let done = expectation(description: "gate returned")
        Task {
            await g.wait { .acquiring }
            done.fulfill()
        }
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(g.isWaiting)
        g.skip()
        await fulfillment(of: [done], timeout: 2)
    }

    /// A second workout in the same launch must not inherit the first one's
    /// skip.
    func test_skipDoesNotLeakIntoTheNextWait() async {
        let g = gate(timeout: 0.5, poll: 0.1)
        g.skip()
        var polls = 0
        await g.wait {
            polls += 1
            return .acquiring
        }
        XCTAssertEqual(polls, 6)   // the guard read, then five polls
    }

    func test_defaultTimeoutIsThirtySeconds() {
        XCTAssertEqual(LocationFixGate.defaultTimeout, 30)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/LocationFixGateTests
```

Expected: compile failure — `cannot find 'LocationFixGate' in scope`.

- [ ] **Step 3: Implement the gate**

Create `MurphCore/LocationFixGate.swift`:

```swift
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
```

- [ ] **Step 4: Regenerate and run the tests**

```bash
xcodegen generate
xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/LocationFixGateTests
```

Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add MurphCore/LocationFixGate.swift MurphPlusTests/LocationFixGateTests.swift MurphPlus.xcodeproj
git commit -m "feat: add the bounded GPS fix gate"
```

---

### Task 3: Wire the provider into the session controller

**Files:**
- Modify: `MurphPlusWatch/Session/WatchSessionController.swift`
- Test: `MurphPlusTests/WatchSessionControllerTests.swift`

**Interfaces:**
- Consumes: `LocationProviding`, `GPSFixState`, `LocationPolicy.shouldWarm(for:)` from Task 1.
- Produces: `WatchSessionController.init(workout:journalDirectory:healthKitStartTimeout:transport:location:)`, `var gpsFixState: GPSFixState`, `func warmLocationForSetup(_ on: Bool)`.

The dependency is **optional and defaulted `nil`**, matching the existing `transport` parameter exactly — a session must run identically with no provider at all, which is what keeps every existing test compiling untouched.

- [ ] **Step 1: Write the failing tests**

Add to `MurphPlusTests/WatchSessionControllerTests.swift`. First, the fake — place it directly after the closing brace of `FakeWorkoutController` (currently line 49):

```swift
/// A `LocationProviding` that records what it was asked to do.
///
/// Same reasoning as `FakeWorkoutController`: the contract under test is a
/// *sequence of calls* — warm for the run, stop for the rounds, warm again
/// before run 2 — and only a recording double can assert on it.
@MainActor
final class FakeLocationController: LocationProviding {
    enum Call: Equatable {
        case requestAuthorization
        case start
        case stop
    }

    private(set) var calls: [Call] = []
    var fixState: GPSFixState = .off

    /// Only the transitions, with repeats collapsed. `startUpdating` is
    /// idempotent by contract and is called after every event, so the raw
    /// list is mostly noise; this is the shape a test actually cares about.
    var transitions: [Call] {
        calls.filter { $0 != .requestAuthorization }.reduce(into: []) { out, call in
            if out.last != call { out.append(call) }
        }
    }

    func requestAuthorization() async { calls.append(.requestAuthorization) }
    func startUpdating() { calls.append(.start) }
    func stopUpdating() { calls.append(.stop) }
}
```

Then add a second controller fixture and the tests. Add `private var gps: FakeLocationController!` beside the existing `fake` property, and extend `setUpWithError` to build it:

```swift
        fake = FakeWorkoutController()
        gps = FakeLocationController()
        controller = WatchSessionController(
            workout: fake, journalDirectory: directory, location: gps
        )
```

Now the tests, in a new `// MARK: - GPS lifecycle` section at the end of the class:

```swift
    // MARK: - GPS lifecycle

    /// Walks a whole outdoor workout and asserts the receiver's on/off shape.
    /// This is the plan's headline behaviour in one test.
    func test_gpsRunsForTheRunsAndStopsForTheRounds() async throws {
        await controller.startSession(
            template: spec(rounds: 3), vestOn: false, vestWeightLbs: nil, indoor: false
        )
        XCTAssertEqual(gps.transitions, [.start])          // run 1

        controller.advance()                                // run 1 ends, rounds begin
        XCTAssertEqual(gps.transitions, [.start, .stop])

        controller.advance()                                // round 1 of 3 — still off
        XCTAssertEqual(gps.transitions, [.start, .stop])

        controller.advance()                                // round 2 of 3 — one remains
        XCTAssertEqual(gps.transitions, [.start, .stop, .start])

        controller.advance()                                // round 3 — run 2 begins
        XCTAssertEqual(gps.transitions, [.start, .stop, .start])

        controller.advance()                                // run 2 ends, complete
        XCTAssertEqual(gps.transitions, [.start, .stop, .start, .stop])
    }

    func test_indoorSessionNeverStartsTheReceiver() async throws {
        await controller.startSession(
            template: spec(rounds: 3), vestOn: false, vestWeightLbs: nil, indoor: true
        )
        controller.advance()
        controller.advance()
        controller.advance()
        controller.advance()
        controller.advance()

        XCTAssertFalse(gps.calls.contains(.start))
    }

    /// A pause mid-run leaves the receiver on: re-acquiring on resume costs
    /// more than the battery a short pause saves.
    func test_pauseLeavesTheReceiverRunning() async throws {
        await controller.startSession(
            template: spec(rounds: 3), vestOn: false, vestWeightLbs: nil, indoor: false
        )
        controller.pause()
        controller.resume()

        XCTAssertEqual(gps.transitions, [.start])
    }

    func test_abandoningStopsTheReceiver() async throws {
        await controller.startSession(
            template: spec(rounds: 3), vestOn: false, vestWeightLbs: nil, indoor: false
        )
        controller.abandon()

        XCTAssertEqual(gps.transitions.last, .stop)
    }

    func test_finishAndResetStopsTheReceiver() async throws {
        await controller.startSession(
            template: spec(rounds: 3), vestOn: false, vestWeightLbs: nil, indoor: false
        )
        controller.finishAndReset()

        XCTAssertEqual(gps.transitions.last, .stop)
    }

    /// Recovery needs no special path — replay the journal, ask the policy.
    func test_resumingMidRunRestartsTheReceiver() async throws {
        await controller.startSession(
            template: spec(rounds: 3), vestOn: false, vestWeightLbs: nil, indoor: false
        )

        let fresh = FakeLocationController()
        let revived = WatchSessionController(
            workout: FakeWorkoutController(), journalDirectory: directory, location: fresh
        )
        let resumed = try await revived.resumeExistingSession()

        XCTAssertTrue(resumed)
        XCTAssertEqual(fresh.transitions, [.start])
    }

    func test_resumingMidRoundsDoesNotStartTheReceiver() async throws {
        await controller.startSession(
            template: spec(rounds: 20), vestOn: false, vestWeightLbs: nil, indoor: false
        )
        controller.advance()   // into the rounds, 20 to go

        let fresh = FakeLocationController()
        let revived = WatchSessionController(
            workout: FakeWorkoutController(), journalDirectory: directory, location: fresh
        )
        let resumed = try await revived.resumeExistingSession()

        XCTAssertTrue(resumed)
        XCTAssertFalse(fresh.calls.contains(.start))
    }

    /// Relaunching one round from run 2 must come back already warming.
    func test_resumingAtThePenultimateRoundRestartsTheReceiver() async throws {
        await controller.startSession(
            template: spec(rounds: 3), vestOn: false, vestWeightLbs: nil, indoor: false
        )
        controller.advance()   // rounds begin
        controller.advance()   // round 1
        controller.advance()   // round 2 — one remains

        let fresh = FakeLocationController()
        let revived = WatchSessionController(
            workout: FakeWorkoutController(), journalDirectory: directory, location: fresh
        )
        let resumed = try await revived.resumeExistingSession()

        XCTAssertTrue(resumed)
        XCTAssertEqual(fresh.transitions, [.start])
    }

    func test_requestAuthorizationAsksBothSensors() async throws {
        await controller.requestAuthorization()

        XCTAssertTrue(fake.calls.contains(.requestAuthorization))
        XCTAssertTrue(gps.calls.contains(.requestAuthorization))
    }

    /// The setup-screen warm-up sits outside the policy on purpose: the policy
    /// answers "where is the session", and on the setup screen there is none.
    func test_setupWarmupStartsAndStopsDirectly() {
        controller.warmLocationForSetup(true)
        XCTAssertEqual(gps.transitions, [.start])

        controller.warmLocationForSetup(false)
        XCTAssertEqual(gps.transitions, [.start, .stop])
    }

    func test_gpsFixStateIsOffWithNoProvider() {
        let bare = WatchSessionController(workout: FakeWorkoutController(), journalDirectory: directory)
        XCTAssertEqual(bare.gpsFixState, .off)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/WatchSessionControllerTests
```

Expected: compile failure — no `location:` parameter on the initializer.

- [ ] **Step 3: Add the dependency**

In `MurphPlusWatch/Session/WatchSessionController.swift`, add the stored property immediately after the `transport` property (currently line 30):

```swift
    /// Injected and optional for the same reasons `transport` is: the phone-
    /// side test bundle supplies a fake, and a session must run identically
    /// with none at all — an indoor workout, or a build where the receiver was
    /// never wired up.
    private let location: (any LocationProviding)?
```

Extend the designated initializer:

```swift
    init(
        workout: any WorkoutControlling,
        journalDirectory: URL,
        healthKitStartTimeout: TimeInterval = 10,
        transport: (any SessionTransport)? = nil,
        location: (any LocationProviding)? = nil
    ) {
        self.workout = workout
        self.journalDirectory = journalDirectory
        self.healthKitStartTimeout = healthKitStartTimeout
        self.transport = transport
        self.location = location
    }
```

And the watchOS convenience initializer, so the real app gets a real receiver:

```swift
    convenience init(sync: WatchSyncCoordinator) {
        self.init(
            workout: WorkoutSessionController(),
            journalDirectory: Self.defaultJournalDirectory,
            transport: sync,
            location: WatchLocationController()
        )
    }
```

> `WatchLocationController` does not exist until Task 4. Leave this line
> commented out with `// location: WatchLocationController()` for now and
> uncomment it in Task 4 Step 5; the rest of this task compiles and tests
> without it.

- [ ] **Step 4: Add the reconcile method and the view-facing accessors**

Add beside the existing `heartRate` / `runDistanceMeters` accessors (currently around line 73):

```swift
    var gpsFixState: GPSFixState { location?.fixState ?? .off }
```

Add a new `// MARK: - Location` section just before `// MARK: - Transitions`:

```swift
    // MARK: - Location

    /// Brings the receiver in line with where the session now is.
    ///
    /// Safe to call after any transition, and called after every one, because
    /// `LocationProviding` is idempotent by contract. That is what keeps the
    /// decision a pure function in `LocationPolicy` instead of a second state
    /// machine living in here.
    ///
    /// Deliberately NOT called from `pause()`/`resume()`: the policy does not
    /// consider pause, and a paused run keeps its receiver.
    private func reconcileLocation() {
        guard let location else { return }
        if LocationPolicy.shouldWarm(for: state) {
            location.startUpdating()
        } else {
            location.stopUpdating()
        }
    }

    /// The setup screen's warm-up, before any session exists.
    ///
    /// Outside `LocationPolicy` on purpose: the policy answers "where is the
    /// session", and here there is not one yet — `state.phase` is
    /// `.notStarted`, for which the policy correctly says off. Warming early
    /// is what makes the start gate almost never visible.
    func warmLocationForSetup(_ on: Bool) {
        on ? location?.startUpdating() : location?.stopUpdating()
    }
```

- [ ] **Step 5: Call it at every transition**

Five edits, each adding one line.

In `requestAuthorization()`, add the second sensor:

```swift
    func requestAuthorization() async {
        await workout.requestAuthorization()
        await location?.requestAuthorization()
    }
```

In `startSession(template:vestOn:vestWeightLbs:indoor:)`, as the last line of the method, after `workout.beginRunActivity(resetDistanceBaseline: true)`:

```swift
        reconcileLocation()
```

In `resumeExistingSession()`, immediately before the closing `return true`:

```swift
        reconcileLocation()
        return true
```

In `advance()`, as the last line of the method, after the `switch` closes:

```swift
        reconcileLocation()
```

In `abandon()`, as the last line of the method:

```swift
        reconcileLocation()
```

In `finishAndReset()`, as the last line:

```swift
    func finishAndReset() {
        journal = nil
        state = SessionState()
        journalWriteFailed = false
        reconcileLocation()
    }
```

- [ ] **Step 6: Run the full test suite**

```bash
xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj
```

Expected: PASS. The 11 new tests pass, and every pre-existing test still passes untouched — `location` defaults to `nil`, so the fixtures that do not pass one behave exactly as before.

- [ ] **Step 7: Commit**

```bash
git add MurphPlusWatch/Session/WatchSessionController.swift MurphPlusTests/WatchSessionControllerTests.swift
git commit -m "feat: drive the GPS receiver from the session's transitions"
```

---

### Task 4: The CoreLocation wrapper and the background modes

**Files:**
- Create: `MurphPlusWatch/Session/WatchLocationController.swift`
- Modify: `project.yml:76-89` (the watch target's `info.properties`)
- Modify: `MurphPlusWatch/Session/WatchSessionController.swift` (uncomment the convenience init line from Task 3)

**Interfaces:**
- Consumes: `LocationProviding`, `GPSFixState` from Task 1.
- Produces: `WatchLocationController()`, conforming to `LocationProviding`. `static let usableAccuracyMeters: CLLocationAccuracy`.

**No unit tests.** It is a hardware wrapper, exactly as `WorkoutSessionController` is today. Its correctness is established by the device checks in Task 6.

> **The two edits in this task must land in one commit.** `allowsBackgroundLocationUpdates = true` without `UIBackgroundModes: [location]` in the built plist is a documented fatal error that terminates the app at launch.

- [ ] **Step 1: Add the background mode to the watch target**

In `project.yml`, under `targets.MurphPlusWatch.info.properties`, add `UIBackgroundModes` beside the existing `WKBackgroundModes`:

```yaml
    info:
      path: MurphPlusWatch/Info.plist
      properties:
        # Without `workout-processing` watchOS suspends the app the moment the
        # wrist drops. The `HKWorkoutSession` survives system-side, but
        # `HKLiveWorkoutBuilderDelegate` stops firing, so no heart-rate event
        # reaches the journal for the rest of the workout and the live view
        # freezes. This is a plist key only — no portal capability required.
        WKBackgroundModes:
          - workout-processing
        # A *different* key doing a *different* job, and both are required.
        # `WKBackgroundModes` has no `location` value at all — its full set is
        # workout-processing, self-care, mindfulness, physical-therapy, alarm,
        # underwater-depth — and `workout-processing` covers only the workout
        # session. Location on watchOS goes through `UIBackgroundModes`, which
        # is available here (watchOS 4.0+).
        #
        # This is not optional hardening: setting
        # `CLLocationManager.allowsBackgroundLocationUpdates = true` while this
        # key is missing is documented as "a fatal error that terminates the
        # app" — NSInternalInconsistencyException, "Invalid parameter not
        # satisfying: !stayUp || CLClientIsBackgroundable(...)". And leaving
        # that property false is not a safe middle: updates then "may or may
        # not continue in the background", which is the silent undercount this
        # whole feature exists to remove.
        UIBackgroundModes:
          - location
        UIAppFonts:
          - ArchivoBlack-Regular.ttf
          - DMSans-Variable.ttf
          - MartianMono-Variable.ttf
```

- [ ] **Step 2: Write the wrapper**

Create `MurphPlusWatch/Session/WatchLocationController.swift`:

```swift
// MurphPlusWatch/Session/WatchLocationController.swift
import CoreLocation
import Foundation
import Observation

/// Wraps `CLLocationManager`.
///
/// Its only job is to keep the GPS receiver powered while a run is in
/// progress. It never computes distance: that still comes from HealthKit's
/// `distanceWalkingRunning`, which fuses GPS with the accelerometer and beats
/// either alone — notably under tree cover, where raw GPS would not.
///
/// Isolated to the main actor for the same reason `WorkoutSessionController`
/// is: `CLLocationManagerDelegate` callbacks arrive off the main actor, so the
/// delegate methods below are `nonisolated` and hop back before touching any
/// stored property. All mutation stays single-threaded.
///
/// Like every sensor in this app, it is optional to the app functioning: a
/// denial yields a complete workout with an estimated distance, never a
/// blocked one.
@MainActor
@Observable
final class WatchLocationController: NSObject, LocationProviding {
    /// A fix this good or better counts as usable. Apple Watch typically
    /// reaches 5-10 m outdoors; 20 m is loose enough not to stall the start
    /// gate and tight enough to exclude a fix that is still settling.
    static let usableAccuracyMeters: CLLocationAccuracy = 20

    private let manager = CLLocationManager()
    private(set) var fixState: GPSFixState = .off
    private var isUpdating = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        // No `pausesLocationUpdatesAutomatically` here: it is
        // API_UNAVAILABLE(watchos). Core Location's auto-pause-when-stationary
        // behaviour, which would be poison in a workout that includes standing
        // still at a pull-up bar, appears not to exist on this platform — there
        // is nothing to switch off.
        // Requires `UIBackgroundModes: [location]` in the built Info.plist.
        // Without it this line is a fatal error that terminates the app, which
        // is why the plist key and this property ship in one commit.
        manager.allowsBackgroundLocationUpdates = true
    }

    func requestAuthorization() async {
        // When In Use is sufficient: `allowsBackgroundLocationUpdates`
        // extends its reach into the background, so Always would be a second
        // prompt for nothing.
        //
        // Not actually asynchronous — CoreLocation answers through
        // `locationManagerDidChangeAuthorization`, not a return value. The
        // signature matches `LocationProviding`, whose other conformer
        // (HealthKit's) genuinely does await.
        guard manager.authorizationStatus == .notDetermined else {
            reflectAuthorization(manager.authorizationStatus)
            return
        }
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        guard !isUpdating else { return }

        switch manager.authorizationStatus {
        case .denied, .restricted:
            // Nothing to wait for. The gate reads this and starts at once.
            fixState = .denied
            return
        default:
            break
        }

        isUpdating = true
        fixState = .acquiring
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        guard isUpdating else { return }
        isUpdating = false
        manager.stopUpdatingLocation()
        fixState = .off
    }

    private func reflectAuthorization(_ status: CLAuthorizationStatus) {
        switch status {
        case .denied, .restricted:
            if isUpdating {
                isUpdating = false
                manager.stopUpdatingLocation()
            }
            fixState = .denied
        default:
            // Newly granted while the setup screen is warming: pick up where
            // `startUpdating` left off rather than waiting for another tap.
            if fixState == .denied { fixState = .off }
        }
    }
}

extension WatchLocationController: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        // A negative `horizontalAccuracy` means the fix is invalid, not
        // precise — the sign is the validity flag, so this check must come
        // before the threshold comparison.
        guard let latest = locations.last,
              latest.horizontalAccuracy >= 0,
              latest.horizontalAccuracy <= Self.usableAccuracyMeters
        else { return }

        Task { @MainActor in
            guard self.isUpdating else { return }
            self.fixState = .fixed
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.reflectAuthorization(status)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didFailWithError error: Error
    ) {
        guard (error as? CLError)?.code == .denied else { return }
        Task { @MainActor in
            self.reflectAuthorization(.denied)
        }
    }
}
```

- [ ] **Step 3: Wire it into the app's own construction**

In `MurphPlusWatch/Session/WatchSessionController.swift`, uncomment the line left in Task 3:

```swift
    convenience init(sync: WatchSyncCoordinator) {
        self.init(
            workout: WorkoutSessionController(),
            journalDirectory: Self.defaultJournalDirectory,
            transport: sync,
            location: WatchLocationController()
        )
    }
```

- [ ] **Step 4: Regenerate and build both targets**

```bash
xcodegen generate
xcodebuild build -scheme MurphPlusWatch -destination 'generic/platform=watchOS' -project MurphPlus.xcodeproj
xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj
```

Expected: both succeed, all tests still pass.

- [ ] **Step 5: Verify the plist key survived the build**

This check exists because an Apple engineer confirmed a case where **the build system stripped this exact key** from the built plist while it was correctly set in source. Reading `project.yml` is not proof.

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -name 'MurphPlusWatch.app' -path '*Debug-watchos*' -print -quit)
plutil -p "$APP/Info.plist" | grep -A3 -E 'UIBackgroundModes|WKBackgroundModes'
```

Expected: `UIBackgroundModes` containing `"location"` **and** `WKBackgroundModes` containing `"workout-processing"`. If `UIBackgroundModes` is absent, stop — the app will crash on launch. Do not proceed to Task 5.

- [ ] **Step 6: Commit**

```bash
git add MurphPlusWatch/Session/WatchLocationController.swift \
        MurphPlusWatch/Session/WatchSessionController.swift \
        project.yml MurphPlus.xcodeproj
git commit -m "feat: power the GPS receiver, with the background mode it requires"
```

---

### Task 5: Setup-screen warm-up and the gate UI

**Files:**
- Create: `MurphPlusWatch/Views/WatchAcquiringGPSView.swift`
- Modify: `MurphPlusWatch/Views/WatchSetupView.swift`

**Interfaces:**
- Consumes: `LocationFixGate` (Task 2), `WatchSessionController.gpsFixState` and `.warmLocationForSetup(_:)` (Task 3).
- Produces: no new API — this is the top of the stack.

- [ ] **Step 1: Write the overlay**

Create `MurphPlusWatch/Views/WatchAcquiringGPSView.swift`. It mirrors `WatchCountdownView`'s shape deliberately — the two occupy the same slot, one after the other, and a change of layout between them would read as a glitch:

```swift
// MurphPlusWatch/Views/WatchAcquiringGPSView.swift
import SwiftUI

/// The hold between countdown zero and a running clock, shown only when GPS
/// is still acquiring.
///
/// Full-bleed and opaque for the same reason `WatchCountdownView` is: it takes
/// the same slot in the same overlay, and the one control on screen has to be
/// the way out. Start anyway is available from the first frame — the user who
/// does not care about the mile must never be made to wait for it.
struct WatchAcquiringGPSView: View {
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: MurphSpacing.space3) {
            Spacer(minLength: 0)

            Text("Acquiring GPS")
                .murphType(.micro)
                .foregroundStyle(MurphColor.hazard500)
                .multilineTextAlignment(.center)

            ProgressView()

            Spacer(minLength: 0)

            Button("Start anyway", action: onSkip)
                .buttonStyle(.bordered)
                .murphType(.micro)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, MurphSpacing.space2)
        .padding(.bottom, MurphSpacing.space2)
        .background(MurphColor.surfacePage)
    }
}
```

- [ ] **Step 2: Hold the gate in the setup view**

In `MurphPlusWatch/Views/WatchSetupView.swift`, add beside the existing `@AppStorage("watchIndoor") private var indoor = false` (line 44):

```swift
    @State private var gate = LocationFixGate()
```

- [ ] **Step 3: Warm the receiver from the setup screen**

Extend the `.task` block (around line 126) so authorization is followed by warm-up:

```swift
            await controller.requestAuthorization()
            // Warm from the moment the screen appears, so the receiver has
            // been running for tens of seconds by the time Start is tapped.
            // This is what makes the gate below almost never visible.
            controller.warmLocationForSetup(!indoor)
```

Make the Outdoor/Indoor control drive it:

```swift
                    segmented(
                        left: "Outdoor", right: "Indoor",
                        leftSelected: !indoor,
                        onLeft: { indoor = false; controller.warmLocationForSetup(true) },
                        onRight: { indoor = true; controller.warmLocationForSetup(false) }
                    )
```

And stop it if the user leaves setup without starting. Add after the existing `.sheet(isPresented: $showResumePrompt)` modifier:

```swift
        .onDisappear {
            // Pushing WatchLiveView fires this too, and there the session owns
            // the receiver from `startSession` onward — stopping it here would
            // kill GPS in the first seconds of run 1. Only stop when we are
            // genuinely leaving setup without a workout.
            if !showLive { controller.warmLocationForSetup(false) }
        }
```

- [ ] **Step 4: Gate the start**

Replace the body of the Start button's `countdown.start { ... }` closure:

```swift
                    Button("Start") {
                        guard let spec = effectiveSelection else { return }
                        // Everything that creates state lives inside the
                        // closure: a cancelled count must leave no journal, no
                        // HealthKit session and no navigation behind.
                        countdown.start {
                            // Returns at once unless GPS is still acquiring,
                            // which after the warm-up above is the rare case.
                            // Bounded and skippable: no sensor blocks a
                            // workout.
                            await gate.wait { controller.gpsFixState }
                            await controller.startSession(
                                template: spec, vestOn: vestOn,
                                vestWeightLbs: vestOn ? vestWeight : nil, indoor: indoor
                            )
                            WKInterfaceDevice.current().play(.start)
                            showLive = true
                        }
                    }
```

Extend the existing overlay so the hold takes the countdown's slot when the count is done:

```swift
        .overlay {
            if let value = countdown.remaining {
                WatchCountdownView(value: value) { countdown.cancel() }
            } else if gate.isWaiting {
                WatchAcquiringGPSView { gate.skip() }
            }
        }
```

- [ ] **Step 5: Regenerate, build, and run the full suite**

```bash
xcodegen generate
xcodebuild build -scheme MurphPlusWatch -destination 'generic/platform=watchOS' -project MurphPlus.xcodeproj
xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj
```

Expected: watch target builds, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add MurphPlusWatch/Views/WatchAcquiringGPSView.swift \
        MurphPlusWatch/Views/WatchSetupView.swift MurphPlus.xcodeproj
git commit -m "feat: warm GPS from setup and gate the start on a fix"
```

---

### Task 6: Device verification

**Files:** none. This task changes no code; it establishes whether the feature works.

Nothing in Tasks 1-5 can prove the feature works — the acceptance criterion is a distance measured outdoors on a known route. Run these in order and stop at the first failure.

- [ ] **Step 1: Confirm the built plist one more time**

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -name 'MurphPlusWatch.app' -path '*watchos*' -print -quit)
plutil -p "$APP/Info.plist" | grep -A3 -E 'UIBackgroundModes|WKBackgroundModes|NSLocation'
```

Expected: `UIBackgroundModes` → `location`; `WKBackgroundModes` → `workout-processing`; `NSLocationWhenInUseUsageDescription` present.

- [ ] **Step 2: Install on the watch and launch**

Expected: **a location permission prompt appears.** It never has before — this app has never asked. If no prompt appears, authorization is not being requested and nothing downstream can work.

Grant When In Use.

- [ ] **Step 3: Confirm the app does not crash on launch**

The `allowsBackgroundLocationUpdates` fatal error fires at `WatchLocationController.init`, which the app constructs at startup. A launch that survives to the setup screen clears it.

- [ ] **Step 4: Watch the gate behave**

On the setup screen with Outdoor selected, wait a few seconds, then tap Start. Expected: the 3·2·1 runs and the workout begins with **no** "Acquiring GPS" screen — the warm-up got there first.

Then force the other path: toggle to Indoor, back to Outdoor, and tap Start immediately. Expected: either a brief "Acquiring GPS" hold that clears on its own, or no hold at all. Tap **Start anyway** at least once to confirm it starts the workout immediately.

- [ ] **Step 5: Run the known route — the acceptance test**

Run the usual 0.70-0.75 mile route as run 1.

Expected: **the recorded distance reads in the 0.70-0.75 band.** Previously 0.46. If it still reads low, the feature has not worked and the remaining suspects are, in order: the plist key (Step 1), the permission grant (Step 2), and whether the watch dimming interrupted delivery.

- [ ] **Step 6: Confirm the rounds stop the receiver, and run 2 is ready**

Do at least three rounds, then run the same route as run 2.

Expected: run 2's distance also reads in the 0.70-0.75 band, without a slow opening — the pre-warm at the penultimate round did its job.

- [ ] **Step 7: Record the two open questions**

Both were flagged in the spec as unresolvable from documentation. Write the answers into the spec's "Open, to settle on hardware" section and commit:

1. **Did the watch dimming mid-run interrupt delivery?** Compare the two splits against their true distances; a mid-run drop shows as an under-read on the split where the wrist was down longer.
2. **Is 20 m the right threshold?** If the gate held noticeably on Step 4, it is too strict. If run 1 opened with a bad reading, it is too loose. Adjust `WatchLocationController.usableAccuracyMeters` and note the value that worked.

```bash
git add docs/superpowers/specs/2026-09-11-watch-gps-distance-design.md
git commit -m "docs: record the hardware answers to the GPS open questions"
```

---

## Self-Review

**Spec coverage.** `LocationProviding`/`GPSFixState` → Task 1. `LocationPolicy` and its rule, including the single-round and recovery consequences → Task 1. `LocationFixGate` → Task 2. `WatchSessionController` wiring at `startSession`/`advance`/`resumeExistingSession`/`finishAndReset` → Task 3 (plus `abandon()`, which the spec's lifecycle table implies through "Session completes / reset" and which is called out explicitly here). `WatchLocationController` with all four manager settings and the 20 m threshold → Task 4. Both background-mode keys, same commit, `plutil` verification → Task 4. Setup warm-up, Outdoor/Indoor toggle, gate overlay, Start anyway, run 2 never gating → Task 5. The full test list → Tasks 1, 2, 3. On-device verification and the two open questions → Task 6. No section of the spec is unimplemented.

**Out of scope, deliberately unchanged, and touched by no task:** `RunSplit`, `SyncPayload`, `SessionImporter`, `HKWorkoutRouteBuilder`, and anything on the phone.

**Type consistency.** `GPSFixState` cases `.off`/`.denied`/`.acquiring`/`.fixed` are spelled identically in Tasks 1-5. `shouldWarm(for:)` takes `SessionState` and returns `Bool` everywhere. `warmLocationForSetup(_:)` takes an unlabelled `Bool` in its definition (Task 3) and both call sites (Task 5). `gate.wait(fixState:)` takes `() -> GPSFixState` in its definition (Task 2), its tests (Task 2), and its call site (Task 5). `usableAccuracyMeters` is referenced only within Task 4 and in Task 6 Step 7.

**One ordering dependency, handled explicitly:** Task 3 Step 3 references `WatchLocationController`, which Task 4 creates. Task 3 leaves that single line commented and Task 4 Step 3 uncomments it, so every task builds and tests green on its own.
