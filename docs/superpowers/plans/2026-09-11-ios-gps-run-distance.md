# iOS GPS Run Distance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give phone-owned sessions a real GPS-measured run distance, on the same terms the watch got — accurate during the runs, off during the rounds.

**Architecture:** A pure `RunDistanceAccumulator` in `MurphCore` turns filtered location samples into metres; a `PhoneLocationController` wraps `CLLocationManager` and feeds it; `SessionEngine` reconciles the receiver against the existing `LocationPolicy` at transitions it already owns, and captures the distance into `.runFinished`. The watch is not touched.

**Tech Stack:** Swift 5, SwiftUI, SwiftData, CoreLocation, XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-11-ios-gps-run-distance-design.md`

## Global Constraints

- **`MurphCore` imports Foundation and nothing else.** No CoreLocation, no HealthKit, no SwiftUI. It compiles into both targets and the iOS bundle is the only test bundle in the project.
- **`LocationPolicy` is not modified.** Its single-round defect is inherited deliberately (spec, "Scope"). `LocationPolicyTests` must pass unedited.
- **`SessionEngineTests` must pass unedited.** Every new `SessionEngine` dependency is defaulted for this reason.
- **The watch is not modified.** `WatchLocationController`, `WatchSessionController`, `WorkoutSessionController` and every watch view stay as they are.
- **`UIBackgroundModes: [location]` and `allowsBackgroundLocationUpdates = true` ship in ONE commit** (Task 4). Split apart, the first launch after the property lands is a fatal `NSInternalInconsistencyException`.
- **Re-run `xcodegen generate` after adding any new source file**, before building. New files are invisible to the build otherwise.
- Test command (substitute the task's suite):

  ```bash
  xcodebuild test -project MurphPlus.xcodeproj -scheme MurphPlus \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:MurphPlusTests/SUITE 2>&1 | tail -25
  ```

---

### Task 1: `LocationSample` and `RunDistanceAccumulator`

The numeric core, and the only part of this change that has to be right. Pure, no hardware.

**Files:**
- Create: `MurphCore/LocationSample.swift`
- Create: `MurphCore/RunDistanceAccumulator.swift`
- Test: `MurphPlusTests/RunDistanceAccumulatorTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `struct LocationSample` (`latitude`, `longitude`, `horizontalAccuracy`, `speed`, `timestamp`); `struct RunDistanceAccumulator` with `var totalMeters: Double { get }`, `mutating func reset()`, `mutating func resetAnchor()`, `@discardableResult mutating func add(_ sample: LocationSample, now: Date) -> Double`, and static constants `maxAccuracyMeters`, `maxSampleAgeSeconds`, `maxSpeedMetersPerSecond`, `minimumDeltaMeters`.

- [ ] **Step 1: Create `MurphCore/LocationSample.swift`**

```swift
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
```

- [ ] **Step 2: Write the failing tests**

Create `MurphPlusTests/RunDistanceAccumulatorTests.swift`:

```swift
// MurphPlusTests/RunDistanceAccumulatorTests.swift
import XCTest
@testable import MurphPlus

/// The only numerically load-bearing type in the GPS feature, so it is tested
/// against traces rather than single calls: the bugs that matter here are
/// about how a *sequence* of samples accumulates, not about one delta.
final class RunDistanceAccumulatorTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    /// ~0.000009 degrees of latitude is ~1 metre. Walking due north keeps the
    /// longitude term out of the arithmetic, so expected values stay legible.
    private func sample(
        northMetres: Double, at second: TimeInterval,
        accuracy: Double = 5, speed: Double = 3
    ) -> LocationSample {
        LocationSample(
            latitude: 51.5 + (northMetres / 111_320.0),
            longitude: -0.12,
            horizontalAccuracy: accuracy,
            speed: speed,
            timestamp: base.addingTimeInterval(second)
        )
    }

    /// Feeds a trace, treating each sample as arriving exactly on time.
    private func feed(_ samples: [LocationSample], into acc: inout RunDistanceAccumulator) {
        for s in samples { acc.add(s, now: s.timestamp) }
    }

    func test_straightLineTrace_sumsToKnownLength() {
        var acc = RunDistanceAccumulator()
        // 10 samples, 20 m apart, 5 s apart: 4 m/s, 180 m of travel after the
        // first sample is consumed as the anchor.
        let trace = (0..<10).map { sample(northMetres: Double($0) * 20, at: Double($0) * 5) }
        feed(trace, into: &acc)

        XCTAssertEqual(acc.totalMeters, 180, accuracy: 2)
    }

    func test_stationaryJitter_accumulatesNothing() {
        var acc = RunDistanceAccumulator()
        // Jitter of ±2 m with 5 m accuracy: every delta is under the floor.
        let trace: [LocationSample] = (0..<20).map {
            sample(northMetres: $0 % 2 == 0 ? 0 : 2, at: Double($0) * 2, speed: 0)
        }
        feed(trace, into: &acc)

        XCTAssertEqual(acc.totalMeters, 0, accuracy: 0.001)
    }

    func test_cachedFirstFix_producesNoPhantomJump() {
        var acc = RunDistanceAccumulator()
        // The classic CoreLocation opener: a fix 10 minutes old, 2 km away.
        let stale = LocationSample(
            latitude: 51.52, longitude: -0.12, horizontalAccuracy: 5,
            speed: -1, timestamp: base.addingTimeInterval(-600)
        )
        acc.add(stale, now: base)
        feed([sample(northMetres: 0, at: 0), sample(northMetres: 20, at: 5)], into: &acc)

        XCTAssertEqual(acc.totalMeters, 20, accuracy: 2)
    }

    func test_invalidAccuracy_isRejected() {
        var acc = RunDistanceAccumulator()
        feed([sample(northMetres: 0, at: 0)], into: &acc)
        acc.add(sample(northMetres: 500, at: 5, accuracy: -1), now: base.addingTimeInterval(5))

        XCTAssertEqual(acc.totalMeters, 0, accuracy: 0.001)
    }

    func test_poorAccuracy_isRejected() {
        var acc = RunDistanceAccumulator()
        feed([sample(northMetres: 0, at: 0)], into: &acc)
        acc.add(sample(northMetres: 100, at: 5, accuracy: 75), now: base.addingTimeInterval(5))

        XCTAssertEqual(acc.totalMeters, 0, accuracy: 0.001)
    }

    func test_impossibleSpeed_isRejected() {
        var acc = RunDistanceAccumulator()
        feed([sample(northMetres: 0, at: 0)], into: &acc)
        // 5 km in 5 s. Reported speed is left plausible so the IMPLIED-speed
        // rule is the one under test.
        acc.add(sample(northMetres: 5000, at: 5, speed: 4), now: base.addingTimeInterval(5))

        XCTAssertEqual(acc.totalMeters, 0, accuracy: 0.001)
    }

    func test_outOfOrderSample_isRejected() {
        var acc = RunDistanceAccumulator()
        feed([sample(northMetres: 0, at: 10), sample(northMetres: 40, at: 15)], into: &acc)
        let before = acc.totalMeters
        // Same wall clock, earlier timestamp than the anchor.
        acc.add(sample(northMetres: 80, at: 12), now: base.addingTimeInterval(15))

        XCTAssertEqual(acc.totalMeters, before, accuracy: 0.001)
    }

    /// THE REGRESSION THAT MATTERS. A rejected sample must not become the new
    /// anchor. If it does, slow movement is permanently invisible: every
    /// individual delta falls under the floor, is dropped, and the anchor
    /// chases the walker at exactly the speed that guarantees nothing counts.
    func test_rejectedSampleDoesNotMoveAnchor_soSlowMovementStillAccumulates() {
        var acc = RunDistanceAccumulator()
        // 1 m every 2 s for 60 s. Each step is under the 3 m floor, so every
        // sample after the anchor is individually rejected — but the distance
        // from the ANCHOR crosses the floor every few samples.
        let trace = (0..<30).map { sample(northMetres: Double($0), at: Double($0) * 2, speed: 0.5) }
        feed(trace, into: &acc)

        XCTAssertGreaterThan(acc.totalMeters, 20, "slow movement accumulated nothing — the anchor is being moved on rejection")
        XCTAssertLessThan(acc.totalMeters, 35)
    }

    func test_reset_clearsTotalAndAnchor() {
        var acc = RunDistanceAccumulator()
        feed([sample(northMetres: 0, at: 0), sample(northMetres: 40, at: 5)], into: &acc)
        XCTAssertGreaterThan(acc.totalMeters, 0)

        acc.reset()
        XCTAssertEqual(acc.totalMeters, 0, accuracy: 0.001)

        // Anchor cleared too: the next sample is consumed as a new anchor and
        // adds nothing, rather than measuring back to the pre-reset position.
        acc.add(sample(northMetres: 100, at: 10), now: base.addingTimeInterval(10))
        XCTAssertEqual(acc.totalMeters, 0, accuracy: 0.001)
    }

    func test_resetAnchor_keepsTotalButDropsTheGap() {
        var acc = RunDistanceAccumulator()
        feed([sample(northMetres: 0, at: 0), sample(northMetres: 40, at: 5)], into: &acc)
        let banked = acc.totalMeters

        // The pause: the user walks 200 m to a water fountain and back.
        acc.resetAnchor()
        acc.add(sample(northMetres: 240, at: 300), now: base.addingTimeInterval(300))

        XCTAssertEqual(acc.totalMeters, banked, accuracy: 0.001, "the walk during the pause landed in the run")
    }

    func test_haversine_matchesKnownDistance() {
        // London (51.5007, -0.1246) to Paris (48.8584, 2.2945): ~343 km.
        let london = LocationSample(latitude: 51.5007, longitude: -0.1246, horizontalAccuracy: 5, speed: 0, timestamp: Date())
        let paris = LocationSample(latitude: 48.8584, longitude: 2.2945, horizontalAccuracy: 5, speed: 0, timestamp: Date())

        XCTAssertEqual(RunDistanceAccumulator.distance(from: london, to: paris), 343_000, accuracy: 3_000)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

```bash
cd /Users/nemeth/Documents/Claude/Projects/murph-plus && xcodegen generate && \
xcodebuild test -project MurphPlus.xcodeproj -scheme MurphPlus \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MurphPlusTests/RunDistanceAccumulatorTests 2>&1 | tail -25
```

Expected: FAIL — `cannot find 'RunDistanceAccumulator' in scope`.

- [ ] **Step 4: Create `MurphCore/RunDistanceAccumulator.swift`**

```swift
// MurphCore/RunDistanceAccumulator.swift
import Foundation

/// Turns a stream of GPS samples into a distance, in metres.
///
/// Pure: no hardware, no I/O, no clock of its own. `now` is a parameter for
/// the same reason it is on `SessionStateMachine.start` and
/// `SessionDerivation.elapsed` — it keeps the type testable and the sample-age
/// rule exercisable without waiting.
///
/// The phone needs this and the watch does not, because there is no
/// `HKLiveWorkoutBuilder` on iOS: `distanceWalkingRunning` on an iPhone is the
/// pedometer stride estimate with no location in it, which is the mechanism
/// that read 0.46 miles on a 0.72 mile route. There is no fusion to defer to
/// here, so distance is derived.
struct RunDistanceAccumulator {
    /// Same VALUE as the watch's gate threshold, deliberately a separate
    /// constant: the gate asks "is the receiver warm yet", this asks "is this
    /// delta trustworthy". They will want tuning independently.
    static let maxAccuracyMeters: Double = 20
    /// `startUpdatingLocation` hands back a cached fix first, sometimes
    /// minutes old and hundreds of metres away. Unfiltered that single sample
    /// is a phantom half-kilometre at the start of every run.
    static let maxSampleAgeSeconds: TimeInterval = 5
    /// Roughly world-record sprint pace, so it catches teleports and nothing
    /// a runner can actually do.
    static let maxSpeedMetersPerSecond: Double = 12
    /// The floor below which a delta is assumed to be noise rather than
    /// movement. Applied as `max(accuracy, this)`, so it only binds when the
    /// fix is better than the floor.
    static let minimumDeltaMeters: Double = 3

    private static let earthRadiusMeters: Double = 6_371_008.8

    private(set) var totalMeters: Double = 0
    private var anchor: LocationSample?

    /// A new run: clear the total and the anchor.
    mutating func reset() {
        totalMeters = 0
        anchor = nil
    }

    /// Resuming after a pause: keep the total, drop the anchor.
    ///
    /// Dropping the anchor is the load-bearing half. If it survived the pause,
    /// the first sample after resume would measure its delta from where the
    /// user stood when they paused — so a walk to the water fountain lands in
    /// the run as one lump. A pause should be a genuine gap, consistent with
    /// the run's duration, which is net of pause everywhere else in this app.
    mutating func resetAnchor() {
        anchor = nil
    }

    /// - Returns: the running total after considering `sample`, accepted or not.
    @discardableResult
    mutating func add(_ sample: LocationSample, now: Date) -> Double {
        // The sign of `horizontalAccuracy` is the validity flag, so this must
        // come before the threshold comparison.
        guard sample.horizontalAccuracy >= 0,
              sample.horizontalAccuracy <= Self.maxAccuracyMeters
        else { return totalMeters }

        guard now.timeIntervalSince(sample.timestamp) <= Self.maxSampleAgeSeconds else {
            return totalMeters
        }

        // A negative reported speed means unavailable, not slow.
        guard sample.speed < 0 || sample.speed <= Self.maxSpeedMetersPerSecond else {
            return totalMeters
        }

        guard let anchor else {
            self.anchor = sample
            return totalMeters
        }

        let interval = sample.timestamp.timeIntervalSince(anchor.timestamp)
        guard interval > 0 else { return totalMeters }

        let delta = Self.distance(from: anchor, to: sample)
        guard delta / interval <= Self.maxSpeedMetersPerSecond else { return totalMeters }

        // The movement has to exceed its own uncertainty.
        guard delta > max(sample.horizontalAccuracy, Self.minimumDeltaMeters) else {
            // NOTE: the anchor is deliberately NOT updated here. Keeping the
            // last ACCEPTED point is what lets slow movement accumulate across
            // several samples. Move the anchor on rejection and every delta
            // falls under the floor forever: a fast run reads roughly right
            // and a slow one reads zero.
            return totalMeters
        }

        totalMeters += delta
        self.anchor = sample
        return totalMeters
    }

    /// Haversine on a sphere, rather than `CLLocation.distance(from:)`, because
    /// the entire point of `LocationSample` is that `MurphCore` never imports
    /// CoreLocation.
    static func distance(from a: LocationSample, to b: LocationSample) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusMeters * asin(min(1, sqrt(h)))
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd /Users/nemeth/Documents/Claude/Projects/murph-plus && xcodegen generate && \
xcodebuild test -project MurphPlus.xcodeproj -scheme MurphPlus \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MurphPlusTests/RunDistanceAccumulatorTests 2>&1 | tail -25
```

Expected: PASS, 11 tests.

- [ ] **Step 6: Commit**

```bash
git add MurphCore/LocationSample.swift MurphCore/RunDistanceAccumulator.swift \
        MurphPlusTests/RunDistanceAccumulatorTests.swift MurphPlus.xcodeproj
git commit -m "feat: add pure run-distance accumulator

The phone has no HKLiveWorkoutBuilder to fuse GPS with the accelerometer,
so unlike the watch it must derive distance itself. Five rejection rules,
each a named constant: invalid accuracy, poor accuracy, stale sample,
impossible speed, and a noise floor scaled to the fix's own uncertainty.

A rejected sample deliberately does not become the new anchor. Moving it
would make slow movement permanently invisible - every delta under the
floor, dropped forever - so a fast run would read roughly right and a slow
one would read zero."
```

---

### Task 2: `RunDistanceMeasuring` and the test double

**Files:**
- Create: `MurphCore/RunDistanceMeasuring.swift`
- Modify: `MurphPlusTests/WatchSessionControllerTests.swift:50-78` (extend the existing `FakeLocationController`)

**Interfaces:**
- Consumes: `GPSFixState` and `LocationProviding` from `MurphCore/LocationProviding.swift`.
- Produces: `protocol RunDistanceMeasuring` with `var runDistanceMeters: Double? { get }`, `func beginRun()`, `func resumeRun()`, `func stopMeasuring()`; `typealias SessionLocation = LocationProviding & RunDistanceMeasuring`. `FakeLocationController` gains `Call.beginRun`, `.resumeRun`, `.stopMeasuring` and a settable `runDistanceMeters`.

- [ ] **Step 1: Create `MurphCore/RunDistanceMeasuring.swift`**

```swift
// MurphCore/RunDistanceMeasuring.swift
import Foundation

/// Measuring a run's distance, expressed without CoreLocation.
///
/// A second seam rather than an extension of `LocationProviding`, so
/// `WatchLocationController` does not grow a property it can never
/// meaningfully answer: the watch reads distance from HealthKit and its
/// location manager only powers the receiver.
///
/// **Receiver-on is not the same as measuring**, and keeping them apart is the
/// whole reason this protocol exists. `LocationPolicy` powers the receiver
/// during the pre-warm at rounds-remaining <= 1, which is *before* run 2
/// begins. Tying the measurement window to receiver power would put every step
/// taken around the pull-up bar during that pre-warm into run 2's distance.
@MainActor
protocol RunDistanceMeasuring: AnyObject {
    /// Metres measured in the current run. `nil` before any run has begun.
    var runDistanceMeters: Double? { get }

    /// A new run: clear the total and the anchor, start measuring.
    func beginRun()

    /// Resuming after a pause: keep the total, drop the anchor, start
    /// measuring. Dropping the anchor is what keeps the walk taken during the
    /// pause out of the run.
    func resumeRun()

    /// Stop measuring. `runDistanceMeters` stays readable, because the caller
    /// reads it when writing the `.runFinished` event.
    func stopMeasuring()
}

/// What `SessionEngine` needs from the phone's location stack: the lifecycle
/// (shared with the watch) and the measurement (phone-only).
typealias SessionLocation = LocationProviding & RunDistanceMeasuring
```

- [ ] **Step 2: Extend `FakeLocationController`**

In `MurphPlusTests/WatchSessionControllerTests.swift`, replace the existing `FakeLocationController` declaration (currently `final class FakeLocationController: LocationProviding`, around line 57) so it also conforms to `RunDistanceMeasuring`. Add the three cases to `Call`, and leave `transitions` untouched — the watch's existing assertions filter on `.requestAuthorization` and depend on this shape.

```swift
@MainActor
final class FakeLocationController: LocationProviding, RunDistanceMeasuring {
    enum Call: Equatable {
        case requestAuthorization
        case start
        case stop
        case beginRun
        case resumeRun
        case stopMeasuring
    }

    private(set) var calls: [Call] = []
    var fixState: GPSFixState = .off

    /// Settable so a test can stage the distance the engine should capture.
    var runDistanceMeters: Double?

    /// Only the receiver transitions, with repeats collapsed. `startUpdating`
    /// is idempotent by contract and is called after every event, so the raw
    /// list is mostly noise; this is the shape a test actually cares about.
    ///
    /// Measurement calls are filtered out too: they are a separate concern on
    /// a separate clock, asserted directly against `calls` by the phone tests.
    var transitions: [Call] {
        calls.filter { $0 == .start || $0 == .stop }.reduce(into: []) { out, call in
            if out.last != call { out.append(call) }
        }
    }

    func requestAuthorization() async { calls.append(.requestAuthorization) }
    func startUpdating() { calls.append(.start) }
    func stopUpdating() { calls.append(.stop) }

    func beginRun() {
        calls.append(.beginRun)
        runDistanceMeters = 0
    }
    func resumeRun() { calls.append(.resumeRun) }
    func stopMeasuring() { calls.append(.stopMeasuring) }
}
```

- [ ] **Step 3: Run the watch suite to verify nothing regressed**

```bash
cd /Users/nemeth/Documents/Claude/Projects/murph-plus && xcodegen generate && \
xcodebuild test -project MurphPlus.xcodeproj -scheme MurphPlus \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MurphPlusTests/WatchSessionControllerTests 2>&1 | tail -25
```

Expected: PASS, same count as before the change. `transitions` was rewritten from an exclusion filter to an inclusion filter; if any watch assertion fails, that rewrite is the first suspect.

- [ ] **Step 4: Commit**

```bash
git add MurphCore/RunDistanceMeasuring.swift MurphPlusTests/WatchSessionControllerTests.swift MurphPlus.xcodeproj
git commit -m "feat: add RunDistanceMeasuring seam

Separate from LocationProviding so the watch's controller does not grow a
distance property it cannot answer - it reads distance from HealthKit and
uses CoreLocation only to power the receiver.

The begin/resume/stop triple exists because receiver-on is not the same as
measuring: LocationPolicy warms the receiver during the pre-warm before run
2, and tying the measurement window to receiver power would put the walk
around the pull-up bar into run 2's distance."
```

---

### Task 3: `SessionEngine` reconciliation and distance capture

**Files:**
- Modify: `MurphPlus/Models/MurphSession.swift:50-55` (add `indoor` to `init`)
- Modify: `MurphPlus/Session/SessionEngine.swift` (init, `startNew`, `perform`, `finishRun`)
- Test: `MurphPlusTests/SessionEngineLocationTests.swift`

**Interfaces:**
- Consumes: `SessionLocation`, `FakeLocationController` (Task 2); `LocationPolicy.shouldWarm(for:)` (existing, unmodified).
- Produces: `SessionEngine.init(session:context:location:)` with `location: SessionLocation? = nil`; `SessionEngine.startNew(template:vestOn:vestWeightLbs:indoor:context:location:)` with `indoor: Bool = false` and `location: SessionLocation? = nil`; `MurphSession.init(date:template:vestOn:vestWeightLbs:indoor:)` with `indoor: Bool = false`.

- [ ] **Step 1: Add `indoor` to `MurphSession.init`**

In `MurphPlus/Models/MurphSession.swift`, change the initializer to accept it. Defaulted, so no existing caller changes.

```swift
    init(
        date: Date = .now,
        template: WorkoutTemplate?,
        vestOn: Bool,
        vestWeightLbs: Int? = nil,
        indoor: Bool = false
    ) {
        self.date = date
        self.template = template
        self.vestOn = vestOn
        self.vestWeightLbs = vestOn ? (vestWeightLbs ?? 20) : nil
        self.indoor = indoor
        self.statusRaw = SessionStatus.inProgress.rawValue
        self.phaseRaw = SessionPhase.notStarted.rawValue
        self.completedRounds = 0
    }
```

- [ ] **Step 2: Write the failing tests**

Create `MurphPlusTests/SessionEngineLocationTests.swift`:

```swift
// MurphPlusTests/SessionEngineLocationTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

/// The phone's counterpart to the location arc asserted in
/// `WatchSessionControllerTests`. The contract is a *sequence of calls* across
/// a whole workout, so it is asserted against a recording double.
@MainActor
final class SessionEngineLocationTests: XCTestCase {
    var context: ModelContext!
    var location: FakeLocationController!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self,
            configurations: config
        )
        context = ModelContext(container)
        location = FakeLocationController()
    }

    private func makeTemplate(rounds: Int) -> WorkoutTemplate {
        let template = WorkoutTemplate(name: "Test Template", rounds: rounds)
        context.insert(template)
        return template
    }

    private func makeEngine(rounds: Int, indoor: Bool = false) -> SessionEngine {
        SessionEngine.startNew(
            template: makeTemplate(rounds: rounds), vestOn: false, vestWeightLbs: nil,
            indoor: indoor, context: context, location: location
        )
    }

    func test_startingRun1_warmsReceiverAndBeginsMeasuring() {
        let engine = makeEngine(rounds: 3)
        engine.start()

        XCTAssertEqual(location.transitions.last, .start)
        XCTAssertTrue(location.calls.contains(.beginRun))
    }

    func test_pause_stopsMeasuringButLeavesReceiverRunning() {
        let engine = makeEngine(rounds: 3)
        engine.start()
        engine.pause()

        XCTAssertEqual(location.calls.last, .stopMeasuring)
        // Pause is invisible to LocationPolicy on purpose: reacquiring a fix
        // on resume costs more than a short pause saves.
        XCTAssertEqual(location.transitions.last, .start)
    }

    func test_resume_resumesMeasuring() {
        let engine = makeEngine(rounds: 3)
        engine.start()
        engine.pause()
        engine.resume()

        XCTAssertEqual(location.calls.last, .resumeRun)
    }

    func test_finishRun1_capturesDistanceIntoTheSplitAndStopsMeasuring() {
        let engine = makeEngine(rounds: 3)
        engine.start()
        location.runDistanceMeters = 1609.34
        engine.finishRun()

        XCTAssertEqual(engine.session.runSplits.first?.distanceMeters ?? 0, 1609.34, accuracy: 0.01)
        XCTAssertTrue(location.calls.contains(.stopMeasuring))
    }

    func test_midRounds_receiverIsOff() {
        let engine = makeEngine(rounds: 20)
        engine.start()
        engine.finishRun()

        XCTAssertEqual(location.transitions.last, .stop)
    }

    func test_penultimateRound_warmsReceiverButDoesNotMeasure() {
        let engine = makeEngine(rounds: 3)
        engine.start()
        engine.finishRun()
        let callsBefore = location.calls.count
        engine.completeRound()
        engine.completeRound() // 2 of 3 done: remaining == 1, pre-warm begins

        XCTAssertEqual(location.transitions.last, .start)
        XCTAssertFalse(
            location.calls.dropFirst(callsBefore).contains(.beginRun),
            "the pre-warm started measuring - steps around the pull-up bar will land in run 2"
        )
    }

    func test_run2_beginsMeasuringAfresh() {
        let engine = makeEngine(rounds: 2)
        engine.start()
        engine.finishRun()
        engine.completeRound()
        engine.completeRound() // -> .run2

        XCTAssertEqual(engine.session.phase, .run2)
        XCTAssertEqual(location.calls.last, .beginRun)
    }

    func test_completion_stopsTheReceiver() {
        let engine = makeEngine(rounds: 1)
        engine.start()
        engine.finishRun()
        engine.completeRound()
        engine.finishRun()

        XCTAssertEqual(engine.session.phase, .completed)
        XCTAssertEqual(location.transitions.last, .stop)
    }

    func test_abandon_stopsTheReceiver() {
        let engine = makeEngine(rounds: 3)
        engine.start()
        engine.abandon()

        XCTAssertEqual(location.transitions.last, .stop)
    }

    func test_indoorSession_neverStartsTheReceiver() {
        let engine = makeEngine(rounds: 3, indoor: true)
        engine.start()
        engine.finishRun()
        engine.completeRound()

        XCTAssertFalse(location.calls.contains(.start))
    }

    /// A run already in flight at construction began before this engine
    /// existed, so its partial total is unrecoverable. An honest gap beats an
    /// undercount with no visible signal.
    func test_resumingMidRun_reportsNilDistanceForThatRunOnly() {
        let first = makeEngine(rounds: 2)
        first.start()

        // Relaunch: a second engine over the same persisted session.
        let resumed = SessionEngine(session: first.session, context: context, location: location)
        location.runDistanceMeters = 900
        resumed.finishRun()

        XCTAssertNil(resumed.session.runSplits.first?.distanceMeters)

        // Run 2 measures normally.
        resumed.completeRound()
        resumed.completeRound()
        location.runDistanceMeters = 1600
        resumed.finishRun()

        let run2 = resumed.session.runSplits.first { $0.runIndex == 2 }
        XCTAssertEqual(run2?.distanceMeters ?? 0, 1600, accuracy: 0.01)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

```bash
cd /Users/nemeth/Documents/Claude/Projects/murph-plus && xcodegen generate && \
xcodebuild test -project MurphPlus.xcodeproj -scheme MurphPlus \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MurphPlusTests/SessionEngineLocationTests 2>&1 | tail -25
```

Expected: FAIL — `extra argument 'location' in call`.

- [ ] **Step 4: Wire `SessionEngine`**

In `MurphPlus/Session/SessionEngine.swift`, add the stored properties and change `init` (currently lines 17-21):

```swift
    private let location: SessionLocation?

    /// A run already in flight when this engine was built began before the
    /// engine existed, so whatever is measured from here is only part of it.
    /// Cleared by the next `beginRun()`.
    private var runDistanceUntrustworthy = false

    init(session: MurphSession, context: ModelContext, location: SessionLocation? = nil) {
        self.session = session
        self.context = context
        self.location = location
        self.state = SessionEngine.rebuildState(from: session)
        reconcileLocation(previousPhase: nil)
        // Set AFTER the reconcile above, because that reconcile may call
        // `beginRun()` for a run already in progress - and `beginRun` is
        // exactly what clears this flag.
        runDistanceUntrustworthy = SessionEngine.isRun(state.phase)
    }
```

Change `startNew` (currently lines 23-29) to carry `indoor` and `location`:

```swift
    static func startNew(
        template: WorkoutTemplate, vestOn: Bool, vestWeightLbs: Int?,
        indoor: Bool = false, context: ModelContext, location: SessionLocation? = nil
    ) -> SessionEngine {
        let session = MurphSession(
            template: template, vestOn: vestOn, vestWeightLbs: vestWeightLbs, indoor: indoor
        )
        context.insert(session)
        try? context.save()
        return SessionEngine(session: session, context: context, location: location)
    }
```

Change `finishRun` (currently line 48-50) to capture the distance:

```swift
    func finishRun() {
        // Read before the transition: `perform` closes the measurement window
        // as part of reconciling, and the value is needed for the event.
        let distance = runDistanceUntrustworthy ? nil : location?.runDistanceMeters
        perform(SessionStateMachine.finishRun(state, at: .now, distanceMeters: distance))
    }
```

Add the reconcile helpers at the end of the type, above `save()`:

```swift
    private static func isRun(_ phase: SessionPhase) -> Bool {
        phase == .run1 || phase == .run2
    }

    /// Asserts the desired receiver state unconditionally rather than tracking
    /// what was already asked — `startUpdating`/`stopUpdating` are idempotent
    /// by contract, which is what lets `LocationPolicy` stay a pure function
    /// rather than a second state machine.
    ///
    /// Mirrors `WatchSessionController`: the transition points are ones this
    /// type already owns, so there are no new events and no state-machine
    /// change.
    private func reconcileLocation(previousPhase: SessionPhase?) {
        guard let location else { return }

        if LocationPolicy.shouldWarm(for: state) {
            location.startUpdating()
        } else {
            location.stopUpdating()
        }

        // The measurement window follows PHASE, not receiver power. The two
        // overlap but are not the same interval: the pre-warm at
        // rounds-remaining <= 1 powers the receiver while measuring stays off.
        let wasRun = previousPhase.map(SessionEngine.isRun) ?? false
        let isRun = SessionEngine.isRun(state.phase)
        if isRun && !wasRun {
            location.beginRun()
            runDistanceUntrustworthy = false
        } else if wasRun && !isRun {
            location.stopMeasuring()
        }
    }
```

Finally, extend `perform` (currently lines 95-119). Add the reconcile before the never-started early return, and the pause/resume handling plus reconcile at the end:

```swift
    private func perform(_ result: Result<SessionEvent, SessionTransitionError>) {
        guard case let .success(event) = result else { return }
        let before = state
        state.apply(event)

        if case .abandoned = event, session.startedAt == nil {
            // Reconcile before returning, or a discarded session leaves the
            // receiver powered until the app dies.
            reconcileLocation(previousPhase: before.phase)
            context.delete(session)
            save()
            return
        }

        applyToModel(event, before: before)
        save()

        // Pause and resume are not phase changes, so the window has to be
        // moved explicitly. The receiver is deliberately untouched: pauses are
        // typically short, and reacquiring a fix costs more than one saves.
        switch event {
        case .paused:
            location?.stopMeasuring()
        case .resumed:
            if SessionEngine.isRun(state.phase) { location?.resumeRun() }
        default:
            break
        }

        reconcileLocation(previousPhase: before.phase)
    }
```

- [ ] **Step 5: Run the new tests to verify they pass**

```bash
cd /Users/nemeth/Documents/Claude/Projects/murph-plus && xcodegen generate && \
xcodebuild test -project MurphPlus.xcodeproj -scheme MurphPlus \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MurphPlusTests/SessionEngineLocationTests 2>&1 | tail -25
```

Expected: PASS, 11 tests.

- [ ] **Step 6: Run the pre-existing suites to verify nothing regressed**

```bash
cd /Users/nemeth/Documents/Claude/Projects/murph-plus && \
xcodebuild test -project MurphPlus.xcodeproj -scheme MurphPlus \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MurphPlusTests/SessionEngineTests \
  -only-testing:MurphPlusTests/LocationPolicyTests 2>&1 | tail -25
```

Expected: PASS, both suites, **with no edits to either file**. If `SessionEngineTests` needed changing, the dependency was not defaulted correctly.

- [ ] **Step 7: Commit**

```bash
git add MurphPlus/Session/SessionEngine.swift MurphPlus/Models/MurphSession.swift \
        MurphPlusTests/SessionEngineLocationTests.swift MurphPlus.xcodeproj
git commit -m "feat: reconcile GPS and capture run distance in SessionEngine

Mirrors WatchSessionController: the receiver is asserted against
LocationPolicy at transitions the engine already owns, so no new events, no
state-machine change, no journal change. finishRun stops passing nil.

The measurement window follows phase rather than receiver power, because
the two are not the same interval - the pre-warm before run 2 powers the
receiver while measuring stays off.

A run already in flight when the engine is built reports nil rather than a
partial: an honest gap beats an undercount with no visible signal, which is
the failure this feature exists to remove."
```

---

### Task 4: `PhoneLocationController` and background modes

Hardware. No unit tests, exactly as `WatchLocationController` has none. **The `project.yml` keys and `allowsBackgroundLocationUpdates` must land in the same commit.**

**Files:**
- Create: `MurphPlus/Session/PhoneLocationController.swift`
- Modify: `project.yml:24-37` (iOS target `settings.base` and `info.properties`)

**Interfaces:**
- Consumes: `LocationSample`, `RunDistanceAccumulator` (Task 1); `LocationProviding`, `RunDistanceMeasuring`, `GPSFixState` (Task 2 and existing).
- Produces: `final class PhoneLocationController: NSObject, LocationProviding, RunDistanceMeasuring`, `init()` takes no arguments.

- [ ] **Step 1: Add the Info.plist keys to `project.yml`**

In the `MurphPlus` target only (**not** the watch target), add the usage-description key to `settings.base`, after `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`:

```yaml
        INFOPLIST_KEY_NSLocationWhenInUseUsageDescription: "Murph+ uses location during the two runs to measure distance and pace. Choose Indoor at setup to skip this."
```

And add `UIBackgroundModes` to the existing `info.properties` block, alongside `UIAppFonts`:

```yaml
    info:
      path: MurphPlus/Info.plist
      properties:
        # Setting `CLLocationManager.allowsBackgroundLocationUpdates = true`
        # while this key is missing is documented as "a fatal error that
        # terminates the app" - NSInternalInconsistencyException, "Invalid
        # parameter not satisfying: !stayUp || CLClientIsBackgroundable(...)".
        # It ships in the same commit as that property for exactly that reason.
        #
        # Leaving the property false is not a safe middle: updates then "may or
        # may not continue in the background", which is the silent undercount
        # this feature exists to remove. A pocketed phone with a locked screen
        # is the normal case for a run.
        UIBackgroundModes:
          - location
        UIAppFonts:
          - ArchivoBlack-Regular.ttf
          - DMSans-Variable.ttf
          - MartianMono-Variable.ttf
```

- [ ] **Step 2: Create `MurphPlus/Session/PhoneLocationController.swift`**

```swift
// MurphPlus/Session/PhoneLocationController.swift
import CoreLocation
import Foundation
import Observation

/// Wraps `CLLocationManager` for the phone.
///
/// The sibling of `WatchLocationController`, with one difference that matters:
/// the watch's manager only powers the receiver and reads distance from
/// HealthKit's fused `distanceWalkingRunning`. There is no
/// `HKLiveWorkoutBuilder` on iOS, and `distanceWalkingRunning` on an iPhone is
/// the pedometer stride estimate with no location in it - so this controller
/// derives distance itself, through `RunDistanceAccumulator`.
///
/// Isolated to the main actor because `CLLocationManagerDelegate` callbacks
/// arrive off it: the delegate methods are `nonisolated` and hop back before
/// touching any stored property. All mutation stays single-threaded.
///
/// Like every sensor in this app, it is optional to the app functioning: a
/// denial yields a complete workout with no distance, never a blocked one.
@MainActor
@Observable
final class PhoneLocationController: NSObject, LocationProviding, RunDistanceMeasuring {
    /// A fix this good or better counts as usable for the START GATE. The
    /// accumulator applies its own, separately tunable threshold to decide
    /// whether a delta is trustworthy.
    ///
    /// `nonisolated` because the delegate reads it off the main actor: an
    /// immutable Sendable value, so the isolation would buy nothing and cost a
    /// Swift 6 error.
    nonisolated static let usableAccuracyMeters: CLLocationAccuracy = 20

    private let manager = CLLocationManager()
    private(set) var fixState: GPSFixState = .off
    private(set) var runDistanceMeters: Double?

    private var accumulator = RunDistanceAccumulator()
    private var isUpdating = false
    private var isMeasuring = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        // Unlike watchOS, where this property does not exist, iOS really will
        // stop delivering updates when it decides the user has stopped moving.
        // Mid-Murph that is a silent undercount, and it is the likeliest way
        // this feature fails quietly on a phone after working on a watch.
        manager.pausesLocationUpdatesAutomatically = false
        // Requires `UIBackgroundModes: [location]` in the built Info.plist.
        // Without it this line is a fatal error that terminates the app, which
        // is why the plist key and this property ship in one commit.
        manager.allowsBackgroundLocationUpdates = true
    }

    // MARK: - LocationProviding

    func requestAuthorization() async {
        // When In Use is sufficient: `allowsBackgroundLocationUpdates` extends
        // its reach into the background, so Always would be a second prompt
        // for nothing.
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

    // MARK: - RunDistanceMeasuring

    func beginRun() {
        accumulator.reset()
        runDistanceMeters = 0
        isMeasuring = true
    }

    func resumeRun() {
        // Anchor only. Keeping the total but dropping the anchor is what keeps
        // the walk taken during the pause out of the run.
        accumulator.resetAnchor()
        isMeasuring = true
    }

    func stopMeasuring() {
        isMeasuring = false
    }

    // MARK: - Private

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

    fileprivate func ingest(_ locations: [CLLocation], now: Date) {
        guard isUpdating else { return }

        for location in locations {
            let sample = LocationSample(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracy: location.horizontalAccuracy,
                speed: location.speed,
                timestamp: location.timestamp
            )

            // The gate's threshold, applied independently of the
            // accumulator's: a negative accuracy means invalid, not precise,
            // so the sign test must come first.
            if sample.horizontalAccuracy >= 0,
               sample.horizontalAccuracy <= Self.usableAccuracyMeters {
                fixState = .fixed
            }

            if isMeasuring {
                runDistanceMeters = accumulator.add(sample, now: now)
            }
        }
    }
}

extension PhoneLocationController: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        let now = Date()
        Task { @MainActor in self.ingest(locations, now: now) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.reflectAuthorization(status) }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didFailWithError error: Error
    ) {
        guard (error as? CLError)?.code == .denied else { return }
        Task { @MainActor in self.reflectAuthorization(.denied) }
    }
}
```

- [ ] **Step 3: Build and verify the plist key reached the BUILT product**

```bash
cd /Users/nemeth/Documents/Claude/Projects/murph-plus && xcodegen generate && \
xcodebuild build -project MurphPlus.xcodeproj -scheme MurphPlus \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/murph-dd 2>&1 | tail -5 && \
plutil -p /tmp/murph-dd/Build/Products/Debug-iphonesimulator/MurphPlus.app/Info.plist \
  | grep -A3 "UIBackgroundModes\|NSLocationWhenInUse"
```

Expected: build succeeds; output shows `UIBackgroundModes => [ 0 => "location" ]` and the `NSLocationWhenInUseUsageDescription` string. **Checking `project.yml` is not sufficient** — the build system has been observed stripping this key, which is why this step reads the built product.

- [ ] **Step 4: Run the full test suite to verify nothing regressed**

```bash
cd /Users/nemeth/Documents/Claude/Projects/murph-plus && \
xcodebuild test -project MurphPlus.xcodeproj -scheme MurphPlus \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -25
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MurphPlus/Session/PhoneLocationController.swift project.yml MurphPlus.xcodeproj
git commit -m "feat: add PhoneLocationController with background location

The plist key and allowsBackgroundLocationUpdates ship together on purpose:
the property without the key is a documented fatal error that terminates
the app on launch, so splitting them would make the first run after the
property lands a crash.

pausesLocationUpdatesAutomatically = false is the one line the watch could
not have - the property is API_UNAVAILABLE(watchos). On iOS the behaviour
is real, and a receiver that stops when it thinks you have stopped moving
is a silent undercount in the middle of a run."
```

---

### Task 5: Indoor/Outdoor at setup, and receiver warm-up

**Files:**
- Create: `MurphPlus/Session/SessionSetup.swift`
- Modify: `MurphPlus/Views/Start/StartView.swift` (the `onBegin` property, `vestSection`, the `.task`/`.onDisappear` modifiers, `#Preview`)
- Modify: `MurphPlus/Views/RootTabView.swift:16-19` (own the controller, take `SessionSetup`)

**Interfaces:**
- Consumes: `PhoneLocationController` (Task 4); `SessionEngine.startNew(…indoor:context:location:)` (Task 3).
- Produces: `struct SessionSetup { let template: WorkoutTemplate; let vestOn: Bool; let vestWeightLbs: Int?; let indoor: Bool }`; `StartView.onBegin` becomes `(SessionSetup) -> Void`; `StartView.init` gains `location: PhoneLocationController`.

- [ ] **Step 1: Create `MurphPlus/Session/SessionSetup.swift`**

```swift
// MurphPlus/Session/SessionSetup.swift
import Foundation

/// What the user chose on the setup screen, handed to `RootTabView` as one
/// value.
///
/// A struct rather than a fourth closure parameter because `indoor` and
/// `vestOn` are both `Bool`: as positional arguments they would sit adjacent
/// and unlabelled at the call site, where transposing them silently produces a
/// vested indoor session that never powers the receiver.
struct SessionSetup {
    let template: WorkoutTemplate
    let vestOn: Bool
    let vestWeightLbs: Int?
    let indoor: Bool
}
```

- [ ] **Step 2: Add the toggle and warm-up to `StartView`**

Change the stored properties (near line 11) — add the indoor state and the injected controller:

```swift
    @State private var indoor = false

    let location: PhoneLocationController
    let onBegin: (SessionSetup) -> Void
```

Change the Begin action inside the `TimelineView` (currently lines 66-70) to build the value:

```swift
                                    ) {
                                        guard let selectedTemplate else { return }
                                        let weight = vestOn ? Int(vestWeightText) : nil
                                        onBegin(SessionSetup(
                                            template: selectedTemplate, vestOn: vestOn,
                                            vestWeightLbs: weight, indoor: indoor
                                        ))
                                    }
```

Add a location section to the body, between `workoutSection` and `vestSection` (line 27):

```swift
                            workoutSection
                            locationSection
                            vestSection
```

Add the section itself beside `vestSection` (near line 249):

```swift
    /// The receiver warms from the moment this screen appears, which is what
    /// makes the start gate almost never visible: by the time a template is
    /// chosen and the vest is set, a fix has usually landed.
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.gapStack) {
            MurphSectionHeader("Location")
            MurphToggle(
                label: "Indoor",
                description: "Treadmill or track. Skips GPS, so the run distance isn\u{2019}t measured.",
                isOn: $indoor
            )
        }
    }
```

Add the lifecycle modifiers beside the existing `.onAppear` (line 82):

```swift
                .task {
                    await location.requestAuthorization()
                    reconcileWarmUp()
                }
                .onChange(of: indoor) { _, _ in reconcileWarmUp() }
                .onDisappear { location.stopUpdating() }
```

And the helper, beside `locationSection`:

```swift
    /// Asserted unconditionally rather than tracked, because `startUpdating`
    /// and `stopUpdating` are idempotent by contract.
    private func reconcileWarmUp() {
        if indoor { location.stopUpdating() } else { location.startUpdating() }
    }
```

Update `#Preview` (line 265):

```swift
    return StartView(location: PhoneLocationController()) { _ in }
```

- [ ] **Step 3: Own the controller in `RootTabView`**

Add the stored property beside the existing `@State` declarations (line 12):

```swift
    /// One long-lived instance: the receiver warms on the setup screen and
    /// must still be the same object once the session begins.
    @State private var location = PhoneLocationController()
```

Change the `StartView` call (lines 17-19):

```swift
            StartView(location: location) { setup in
                liveEngine = SessionEngine.startNew(
                    template: setup.template, vestOn: setup.vestOn,
                    vestWeightLbs: setup.vestWeightLbs, indoor: setup.indoor,
                    context: context, location: location
                )
            }
```

And the resume path (line 42) — this is where `LocationPolicy`'s purity pays off: replay, ask the policy, obey the answer, with no separate recovery branch:

```swift
                    liveEngine = SessionEngine(session: session, context: context, location: location)
```

- [ ] **Step 4: Build and run the full suite**

```bash
cd /Users/nemeth/Documents/Claude/Projects/murph-plus && xcodegen generate && \
xcodebuild test -project MurphPlus.xcodeproj -scheme MurphPlus \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -25
```

Expected: PASS. `SessionEngineTests` still calls `startNew` without `indoor:` or `location:` and must still compile — both are defaulted.

- [ ] **Step 5: Commit**

```bash
git add MurphPlus/Session/SessionSetup.swift MurphPlus/Views/Start/StartView.swift \
        MurphPlus/Views/RootTabView.swift MurphPlus.xcodeproj
git commit -m "feat: ask Indoor or Outdoor at setup and warm the receiver

MurphSession.indoor has existed since the watch work but nothing on the
phone ever set it, so every phone session has been silently outdoor with
nobody asked. The toggle finally sets it.

Warming from the moment the setup screen appears is what makes the start
gate almost never visible: choosing a template and setting the vest takes
longer than an iPhone needs for a fix.

onBegin takes a SessionSetup rather than a fourth parameter, so indoor and
vestOn are not two adjacent unlabelled Bools at the call site."
```

---

### Task 6: The start gate

**Files:**
- Modify: `MurphPlus/Views/Start/StartView.swift` (the Begin action, a `fullScreenCover`)

**Interfaces:**
- Consumes: `LocationFixGate` (`MurphCore/LocationFixGate.swift`, existing and unmodified — `init(timeout:pollInterval:sleep:)`, `var isWaiting: Bool`, `func wait(fixState:) async`, `func skip()`); `PhoneLocationController.fixState` (Task 4).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Hold the gate in `StartView`**

Add beside the other `@State` properties:

```swift
    /// Reused verbatim from the watch. The phone is its second caller and adds
    /// nothing to it.
    @State private var gate = LocationFixGate()
    @State private var pendingSetup: SessionSetup?
```

- [ ] **Step 2: Route Begin through the gate**

Replace the Begin action written in Task 5 so it stages the setup and waits, rather than calling `onBegin` directly:

```swift
                                    ) {
                                        guard let selectedTemplate else { return }
                                        let weight = vestOn ? Int(vestWeightText) : nil
                                        let setup = SessionSetup(
                                            template: selectedTemplate, vestOn: vestOn,
                                            vestWeightLbs: weight, indoor: indoor
                                        )
                                        pendingSetup = setup
                                        Task {
                                            // Returns immediately for every
                                            // state except `.acquiring`: Indoor
                                            // is `.off`, a refusal is `.denied`
                                            // and waiting for a fix that will
                                            // never come is pure delay, and the
                                            // ordinary case is already `.fixed`.
                                            await gate.wait { location.fixState }
                                            guard let staged = pendingSetup else { return }
                                            pendingSetup = nil
                                            onBegin(staged)
                                        }
                                    }
```

- [ ] **Step 3: Present the acquiring overlay**

Add beside the existing `.navigationDestination` (line 87):

```swift
                .fullScreenCover(isPresented: Binding(
                    get: { gate.isWaiting },
                    set: { if !$0 { gate.skip() } }
                )) {
                    acquiringOverlay
                }
```

And the overlay itself, beside `locationSection`:

```swift
    /// A `fullScreenCover`, not a sheet, and dismissal is disabled: the same
    /// reasoning already written at `RootTabView.swift:54-61`. A swipe here
    /// would resolve the gate without a decision and leave a half-started
    /// session behind it.
    private var acquiringOverlay: some View {
        VStack(spacing: MurphSpacing.space6) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(MurphColor.hazard500)
            VStack(spacing: MurphSpacing.space2) {
                Text("Acquiring GPS")
                    .murphType(.title())
                    .foregroundStyle(MurphColor.textPrimary)
                Text("Waiting for a usable fix so the run distance is measured.")
                    .murphType(.bodySm)
                    .foregroundStyle(MurphColor.textMuted)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            // Available from the first frame. The standing contract is that no
            // sensor may block the workout (`WorkoutControlling`), and the
            // 30-second timeout is only the backstop for someone who is not
            // looking at the screen.
            MurphButton(variant: .secondary, size: .lg, full: true, title: "Start anyway") {
                gate.skip()
            }
        }
        .padding(MurphSpacing.gutterScreen)
        .murphScreenBackground()
        .interactiveDismissDisabled()
    }
```

- [ ] **Step 4: Verify the gate suite still passes and the app builds**

```bash
cd /Users/nemeth/Documents/Claude/Projects/murph-plus && xcodegen generate && \
xcodebuild test -project MurphPlus.xcodeproj -scheme MurphPlus \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MurphPlusTests/LocationFixGateTests 2>&1 | tail -25
```

Expected: PASS, **with no edits to `LocationFixGate` or its tests**. The phone adds a caller, not a change.

- [ ] **Step 5: Commit**

```bash
git add MurphPlus/Views/Start/StartView.swift MurphPlus.xcodeproj
git commit -m "feat: gate Begin on a usable GPS fix

LocationFixGate is reused verbatim - the phone is its second caller and
adds nothing to it. Indoor, denied and fixed all pass through instantly;
only acquiring holds, with Start anyway from the first frame and the same
30-second bound.

fullScreenCover with dismissal disabled, for the reason already written on
the resume prompt: a swipe would resolve the gate without a decision and
leave a half-started session behind it."
```

---

### Task 7: Live distance during the runs

**Files:**
- Create: `MurphPlus/Support/DistanceFormatting.swift`
- Modify: `MurphPlus/Views/History/SessionDetailValue.swift:11,16` (use the shared helper)
- Modify: `MurphPlus/Views/Session/LiveSessionView.swift` (a readout under the clock; distance on the logged rows)

**Interfaces:**
- Consumes: `PhoneLocationController.runDistanceMeters` (Task 4); `SessionPhase` (existing).
- Produces: global `func formatMiles(_ meters: Double) -> String` in `MurphPlus/Support/DistanceFormatting.swift`.

- [ ] **Step 1: Create `MurphPlus/Support/DistanceFormatting.swift`**

A free function beside `DurationFormatting.swift`, matching its shape exactly —
that file declares a global `formatDuration(_:)` rather than a namespacing enum,
and this is its sibling.

```swift
// MurphPlus/Support/DistanceFormatting.swift
import Foundation

private let metresPerMile: Double = 1609.34

/// e.g. `"0.72 mi"`.
///
/// Hoisted out of `SessionDetailValue`, which held the conversion privately,
/// so the live readout and the history row cannot round differently and
/// disagree about the same run.
func formatMiles(_ meters: Double) -> String {
    String(format: "%.2f mi", meters / metresPerMile)
}
```

- [ ] **Step 2: Point `SessionDetailValue` at it**

In `MurphPlus/Views/History/SessionDetailValue.swift`, delete the private constant on line 11 and change the formatting on line 16 to use the shared one:

```swift
        if let distanceMeters {
            parts.append(formatMiles(distanceMeters))
        }
```

- [ ] **Step 3: Add the live readout to `LiveSessionView`**

Add the injected controller beside the existing stored properties (near line 21):

```swift
    let location: PhoneLocationController
```

Add a distance line under the elapsed clock, inside the `TimelineView` block (currently lines 120-129), after `MurphClock`:

```swift
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(alignment: .leading, spacing: MurphSpacing.space2) {
                    MurphClock(
                        label: "Elapsed",
                        seconds: engine.totalElapsed,
                        size: .lg,
                        running: phase != .notStarted && phase != .completed && !engine.isPaused,
                        tone: phase == .completed ? .accent : .default
                    )
                    // Runs only. During the rounds the receiver is off by
                    // policy, so there is nothing to show and a frozen number
                    // would read as a stall.
                    if phase == .run1 || phase == .run2 {
                        Text(liveDistanceText)
                            .murphType(.bodySm)
                            .foregroundStyle(MurphColor.textMuted)
                    }
                }
            }
```

And the helper, as a private computed property on `LiveSessionView` beside
`copy` and `neverStarted` (note `formatDuration` is NOT a member of this view —
it is a global in `MurphPlus/Support/DurationFormatting.swift`):

```swift
    /// An em dash rather than "0.00 mi" while the fix is still settling: a
    /// zero that is really "not measured yet" reads as a broken sensor.
    private var liveDistanceText: String {
        guard !session.indoor else { return "Indoor \u{00b7} distance not measured" }
        guard let meters = location.runDistanceMeters else { return "Distance \u{2014}" }
        guard let target = session.template?.runDistanceMiles else {
            return "Distance \(formatMiles(meters))"
        }
        let targetText = target.formatted(.number.precision(.fractionLength(2)))
        return "Distance \(formatMiles(meters)) of \(targetText) mi"
    }
```

Show the distance on the logged rows too (currently line 140):

```swift
                            ForEach(session.runSplits.sorted { $0.runIndex < $1.runIndex }, id: \.persistentModelID) { split in
                                MurphSplitRow(
                                    label: "Run \(split.runIndex)",
                                    value: split.distanceMeters.map {
                                        "\(formatDuration(split.durationSeconds)) \u{00b7} \(formatMiles($0))"
                                    } ?? formatDuration(split.durationSeconds),
                                    tone: .accent
                                )
                            }
```

- [ ] **Step 4: Pass the controller in from `RootTabView`**

In `MurphPlus/Views/RootTabView.swift`, update the `fullScreenCover` content (line 36):

```swift
            LiveSessionView(engine: wrapper.engine, location: location) {
                liveEngine = nil
            }
```

`LiveSessionView` has no `#Preview`, so there is no other call site to update.
`RootTabView` is the only place it is constructed.

- [ ] **Step 5: Build and run the full suite**

```bash
cd /Users/nemeth/Documents/Claude/Projects/murph-plus && xcodegen generate && \
xcodebuild test -project MurphPlus.xcodeproj -scheme MurphPlus \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -25
```

Expected: PASS, every suite.

- [ ] **Step 6: Commit**

```bash
git add MurphPlus/Support/DistanceFormatting.swift MurphPlus/Views/History/SessionDetailValue.swift \
        MurphPlus/Views/Session/LiveSessionView.swift MurphPlus/Views/RootTabView.swift MurphPlus.xcodeproj
git commit -m "feat: show run distance live and on the logged splits

Mirrors what the watch already shows on its primary page, including
progress toward the template's target.

The metres-to-miles conversion moves out of SessionDetailValue into a
formatMiles free function beside formatDuration, so the live readout and
the history row cannot round differently and disagree about the same run. History itself needed no change - it has always fed
split.distanceMeters to a formatter that handles it, and the phone simply
stops handing it nil."
```

---

### Task 8: On-device acceptance

Not a code task. The unit tests prove the rules; only a real route proves the number. **This is the acceptance test for the whole feature.**

**Files:** none.

- [ ] **Step 1: Verify the built plist one more time on a device build**

```bash
cd /Users/nemeth/Documents/Claude/Projects/murph-plus && xcodegen generate && \
xcodebuild build -project MurphPlus.xcodeproj -scheme MurphPlus \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/murph-device 2>&1 | tail -5 && \
plutil -p /tmp/murph-device/Build/Products/Debug-iphoneos/MurphPlus.app/Info.plist \
  | grep -A3 "UIBackgroundModes\|NSLocationWhenInUse"
```

Expected: `UIBackgroundModes` contains `location`. Reading `project.yml` is not a substitute — the build system has been observed stripping this key from the built plist, and the symptom is a launch crash rather than a missing feature.

- [ ] **Step 2: Install on a real iPhone and confirm the permission prompt**

Open the Start tab. The location prompt must appear — iOS has never asked before, so if no prompt appears, either the usage-description key is missing or `requestAuthorization` is not reached from `.task`.

- [ ] **Step 3: Run the known route**

Choose an outdoor template, tap Begin, put the phone in a pocket with the screen locked, and run the known **0.70–0.75 mile** route.

- [ ] **Step 4: Check the result**

Open the session in History. Run 1's distance must read **in the 0.70–0.75 mile band**. Anything near 0.46 means the accumulator is not receiving samples; a wildly high number means the noise or speed filters are too loose.

- [ ] **Step 5: Record the findings in the spec**

Append a short "Measured" section to `docs/superpowers/specs/2026-09-11-ios-gps-run-distance-design.md` recording the figure, the weather/sky view, and whether any of the three open tuning questions (accuracy threshold, noise floor, long-gap drift) now have answers. Commit it.

```bash
git add docs/superpowers/specs/2026-09-11-ios-gps-run-distance-design.md
git commit -m "docs: record measured iOS GPS distance against the known route"
```
