# Murph Plus Watch — Stage 1: MurphCore Extraction and Pause

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the live-session state machine into a pure-Swift `MurphCore` layer with no SwiftData dependency, rewire `SessionEngine` as a thin adapter over it, and ship **pause** on the phone.

**Architecture:** Event-sourced. A `SessionEvent` enum is the single currency; `SessionState` is produced by folding events; `SessionStateMachine` validates transitions and *returns* events rather than mutating anything. `SessionEngine` keeps its existing public API and its `ModelContext`, but each method now asks the state machine for an event and applies that event to SwiftData. **The existing `SessionEngineTests` must pass untouched** — that is the contract proving the extraction preserved behavior.

**Tech Stack:** Swift, SwiftUI, SwiftData, XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-03-murph-plus-watch-design.md`

**Ships working software on its own:** the phone app, with pause, on a tested pure core. No watchOS target is added in this stage.

## Global Constraints

- iOS 17.0 minimum. watchOS 10 is not yet relevant — no watch target in this stage.
- **`MurphCore` imports `Foundation` and nothing else.** No SwiftData, no SwiftUI, no HealthKit, no WatchConnectivity. This is the constraint that makes Stage 2 possible; a single `import SwiftData` in that directory defeats the entire design.
- Types in `MurphCore` need **no access modifiers** — the directory is compiled into each app target directly, not linked as a framework, so default internal access is correct. Do not write `public`.
- **Timestamps always come from the owning device**, and are never restamped on receipt. Every duration is a difference between two timestamps from the same clock.
- **Pause time falling inside a round's interval must be subtracted from that round's duration.** Round durations feed the least-squares fatigue fit; a naive pause silently poisons the prediction with no visible symptom. This is the highest-risk requirement in the plan.
- Re-run `xcodegen generate` after adding any new source file, before building.
- Test command: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`. Substitute an available simulator from `xcrun simctl list devicetypes` if needed.

---

## File Structure

```
MurphCore/                                  CREATE — pure Foundation, both targets
  SessionEnums.swift                        MOVE from MurphPlus/Models/ (unchanged content)
  TemplateSpec.swift                        CREATE — value snapshot of a template
  SessionEvent.swift                        CREATE — the Codable event enum
  SessionState.swift                        CREATE — folded state + replay
  SessionStateMachine.swift                 CREATE — transition rules, returns events
  SessionDerivation.swift                   CREATE — elapsed and round durations, pause-aware
MurphPlus/
  Models/
    MurphSession.swift                      MODIFY — pausedSeconds, pausedAt, net elapsed
    RoundLog.swift                          MODIFY — pausedSecondsInRound
    WorkoutTemplate.swift                   MODIFY — id + spec accessor
  Session/SessionEngine.swift               MODIFY — becomes an adapter over MurphCore
  Prediction/RoundThroughputBuilder.swift   MODIFY — subtract per-round pause
  Views/Session/LiveSessionView.swift       MODIFY — pause/resume control
project.yml                                 MODIFY — add MurphCore to sources
MurphPlusTests/
  TemplateSpecTests.swift                   CREATE
  SessionEventTests.swift                   CREATE
  SessionStateReplayTests.swift             CREATE
  SessionStateMachineTests.swift            CREATE
  SessionDerivationTests.swift              CREATE
  SessionEngineTests.swift                  UNCHANGED — the safety net
```

---

### Task 1: MurphCore scaffolding, TemplateSpec, SessionEvent

**Files:**
- Create: `MurphCore/TemplateSpec.swift`, `MurphCore/SessionEvent.swift`
- Move: `MurphPlus/Models/SessionEnums.swift` → `MurphCore/SessionEnums.swift`
- Modify: `project.yml`, `MurphPlus/Models/WorkoutTemplate.swift`
- Test: `MurphPlusTests/TemplateSpecTests.swift`, `MurphPlusTests/SessionEventTests.swift`

**Interfaces:**
- Produces, consumed by every later task:
  - `TemplateSpec` — `id: UUID`, `name: String`, `runDistanceMiles: Double`, `totalPullUps/PushUps/Squats: Int`, `rounds: Int`; derived `safeRounds`, `totalReps`, `pullUpsPerRound`, `pushUpsPerRound`, `squatsPerRound`, `repsPerRound`.
  - `SessionEvent` — cases below; `var timestamp: Date`; `var isHeartRate: Bool`.
  - `WorkoutTemplate.spec: TemplateSpec` and `WorkoutTemplate.id: UUID`.
- Consumes: `SessionPhase`, `SessionStatus` (moved, content unchanged).

> **Deviation from the spec, deliberate:** the spec writes `started(at:templateID:template:…)`. Since `TemplateSpec` carries its own `id`, the separate `templateID` parameter is redundant and is folded in. Same information, one field.

- [ ] **Step 1: Move the enums and wire up the directory**

```bash
mkdir -p MurphCore
git mv MurphPlus/Models/SessionEnums.swift MurphCore/SessionEnums.swift
```

Its content is already pure Swift with no imports — do not edit it.

In `project.yml`, add `MurphCore` to the `MurphPlus` target's sources:

```yaml
    sources:
      - MurphPlus
      - MurphCore
```

- [ ] **Step 2: Write the failing tests**

Create `MurphPlusTests/TemplateSpecTests.swift`:

```swift
// MurphPlusTests/TemplateSpecTests.swift
import XCTest
@testable import MurphPlus

final class TemplateSpecTests: XCTestCase {

    private func fullMurph(rounds: Int) -> TemplateSpec {
        TemplateSpec(
            id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
            totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: rounds
        )
    }

    func test_derivedPerRoundValues() {
        let spec = fullMurph(rounds: 20)

        XCTAssertEqual(spec.totalReps, 600)
        XCTAssertEqual(spec.pullUpsPerRound, 5)
        XCTAssertEqual(spec.pushUpsPerRound, 10)
        XCTAssertEqual(spec.squatsPerRound, 15)
        XCTAssertEqual(spec.repsPerRound, 30)
    }

    func test_zeroRoundsDoesNotDivideByZero() {
        // A stored 0 would be a hard crash rather than a recoverable error,
        // mirroring the guard WorkoutTemplate already carries.
        let spec = fullMurph(rounds: 0)

        XCTAssertEqual(spec.safeRounds, 1)
        XCTAssertEqual(spec.repsPerRound, 600)
    }

    func test_roundTripsThroughJSON() throws {
        let spec = fullMurph(rounds: 20)

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(TemplateSpec.self, from: data)

        XCTAssertEqual(decoded, spec)
    }
}
```

Create `MurphPlusTests/SessionEventTests.swift`:

```swift
// MurphPlusTests/SessionEventTests.swift
import XCTest
@testable import MurphPlus

final class SessionEventTests: XCTestCase {

    private let spec = TemplateSpec(
        id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
        totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 20
    )

    private var allEventKinds: [SessionEvent] {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        return [
            .started(at: t, template: spec, vestOn: true, vestWeightLbs: 20, indoor: false),
            .runFinished(index: 1, at: t, distanceMeters: 1609.34),
            .runFinished(index: 2, at: t, distanceMeters: nil),
            .roundCompleted(number: 7, at: t),
            .roundUndone(number: 7, at: t),
            .paused(at: t),
            .resumed(at: t),
            .heartRate(bpm: 142, at: t),
            .abandoned(at: t),
        ]
    }

    func test_everyEventRoundTripsThroughJSON() throws {
        // The journal format and the sync payload are the same encoding, so a
        // case that fails to round-trip is a case that silently loses a
        // workout in Stage 3.
        for event in allEventKinds {
            let data = try JSONEncoder().encode(event)
            let decoded = try JSONDecoder().decode(SessionEvent.self, from: data)
            XCTAssertEqual(decoded, event)
        }
    }

    func test_timestampIsReadableForEveryCase() {
        let t = Date(timeIntervalSince1970: 1_700_000_000)

        for event in allEventKinds {
            XCTAssertEqual(event.timestamp, t)
        }
    }

    func test_onlyHeartRateIsMarkedAsHeartRate() {
        let t = Date()

        XCTAssertTrue(SessionEvent.heartRate(bpm: 140, at: t).isHeartRate)
        XCTAssertFalse(SessionEvent.roundCompleted(number: 1, at: t).isHeartRate)
        XCTAssertFalse(SessionEvent.paused(at: t).isHeartRate)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/TemplateSpecTests`

Expected: compile failure — `cannot find 'TemplateSpec' in scope`.

- [ ] **Step 4: Write TemplateSpec**

Create `MurphCore/TemplateSpec.swift`:

```swift
// MurphCore/TemplateSpec.swift
import Foundation

/// A value-type snapshot of a workout template's numbers.
///
/// This is what crosses to the Watch and what a `started` event carries, so a
/// session always knows what it was an attempt at — even if the underlying
/// `WorkoutTemplate` is later edited or deleted. `WorkoutTemplate` itself is a
/// SwiftData `@Model` and stays on the phone.
struct TemplateSpec: Codable, Equatable {
    var id: UUID
    var name: String
    var runDistanceMiles: Double
    var totalPullUps: Int
    var totalPushUps: Int
    var totalSquats: Int
    var rounds: Int

    /// Guards integer division: a stored 0 would be a hard crash rather than a
    /// recoverable error. Mirrors the same guard on `WorkoutTemplate`.
    var safeRounds: Int { max(rounds, 1) }

    var totalReps: Int { totalPullUps + totalPushUps + totalSquats }
    var pullUpsPerRound: Int { totalPullUps / safeRounds }
    var pushUpsPerRound: Int { totalPushUps / safeRounds }
    var squatsPerRound: Int { totalSquats / safeRounds }
    var repsPerRound: Int { totalReps / safeRounds }
}
```

- [ ] **Step 5: Write SessionEvent**

Create `MurphCore/SessionEvent.swift`:

```swift
// MurphCore/SessionEvent.swift
import Foundation

/// The single currency of a live session.
///
/// Everything downstream is derived from an ordered array of these: the
/// session's state, its elapsed time, its round durations, the Watch's on-disk
/// journal, and the sync payload. Phase transitions are *implicit* — `started`
/// begins run 1, `runFinished(1)` begins the rounds, the round reaching the
/// template's total begins run 2, `runFinished(2)` completes the session — so
/// there are no separate transition events to keep consistent.
///
/// Timestamps always come from the device that owns the session, and are never
/// restamped on receipt. Every duration is therefore a difference between two
/// readings of the same clock, which is why clock skew between watch and phone
/// cannot distort a split.
enum SessionEvent: Codable, Equatable {
    case started(at: Date, template: TemplateSpec, vestOn: Bool, vestWeightLbs: Int?, indoor: Bool)
    case runFinished(index: Int, at: Date, distanceMeters: Double?)
    case roundCompleted(number: Int, at: Date)
    case roundUndone(number: Int, at: Date)
    case paused(at: Date)
    case resumed(at: Date)
    case heartRate(bpm: Int, at: Date)
    case abandoned(at: Date)

    var timestamp: Date {
        switch self {
        case let .started(at, _, _, _, _): at
        case let .runFinished(_, at, _): at
        case let .roundCompleted(_, at): at
        case let .roundUndone(_, at): at
        case let .paused(at): at
        case let .resumed(at): at
        case let .heartRate(_, at): at
        case let .abandoned(at): at
        }
    }

    /// Heart rate is journaled every 5 seconds and is the only high-frequency
    /// event. Stage 3 checkpoints on every event that is *not* one of these.
    var isHeartRate: Bool {
        if case .heartRate = self { return true }
        return false
    }
}
```

- [ ] **Step 6: Give WorkoutTemplate an id and a spec**

In `MurphPlus/Models/WorkoutTemplate.swift`, add the stored property (defaulted, so it stays CloudKit-legal and migrates lightly):

```swift
    var id: UUID = UUID()
```

and the accessor:

```swift
    /// The value-type snapshot that crosses to the Watch and is embedded in a
    /// session's `started` event.
    var spec: TemplateSpec {
        TemplateSpec(
            id: id,
            name: name,
            runDistanceMiles: runDistanceMiles,
            totalPullUps: totalPullUps,
            totalPushUps: totalPushUps,
            totalSquats: totalSquats,
            rounds: rounds
        )
    }
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`

Expected: `** TEST SUCCEEDED **`. The full suite must pass — the `SessionEnums.swift` move must not have broken any existing reference.

- [ ] **Step 8: Commit**

```bash
git add MurphCore project.yml MurphPlus/Models/WorkoutTemplate.swift \
        MurphPlusTests/TemplateSpecTests.swift MurphPlusTests/SessionEventTests.swift
git commit -m "feat: add MurphCore with TemplateSpec and SessionEvent

Pure-Foundation layer compiled into the app target directly, no
framework. SessionEnums moves here unchanged so both platforms share
the phase and status vocabulary."
```

---

### Task 2: SessionState and event replay

**Files:**
- Create: `MurphCore/SessionState.swift`
- Test: `MurphPlusTests/SessionStateReplayTests.swift`

**Interfaces:**
- Consumes: `SessionEvent`, `TemplateSpec`, `SessionPhase`, `SessionStatus`.
- Produces:
  - `SessionState` with `template`, `vestOn`, `vestWeightLbs`, `indoor`, `phase`, `status`, `startedAt`, `currentPhaseStartedAt`, `roundsStartedAt`, `completedAt`, `completedRounds`, `roundTimestamps: [Date]`, `runSplits: [RunSplitState]`, `pausedAt`, `pausedIntervals: [PausedInterval]`, `latestHeartRate: Int?`, `undoableRoundNumber: Int?`
  - computed `isPaused`, `isTerminal`
  - `SessionState.replay(_ events: [SessionEvent]) -> SessionState`
  - `mutating func apply(_ event: SessionEvent)`
  - `func pausedSeconds(between:and:) -> TimeInterval`
  - `RunSplitState { index, startTime, durationSeconds, distanceMeters }`
  - `PausedInterval { start, end }`

- [ ] **Step 1: Write the failing tests**

Create `MurphPlusTests/SessionStateReplayTests.swift`:

```swift
// MurphPlusTests/SessionStateReplayTests.swift
import XCTest
@testable import MurphPlus

final class SessionStateReplayTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    private let spec = TemplateSpec(
        id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
        totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 3
    )

    private func started() -> SessionEvent {
        .started(at: t(0), template: spec, vestOn: true, vestWeightLbs: 20, indoor: false)
    }

    func test_startedBeginsRun1() {
        let state = SessionState.replay([started()])

        XCTAssertEqual(state.phase, .run1)
        XCTAssertEqual(state.startedAt, t(0))
        XCTAssertEqual(state.currentPhaseStartedAt, t(0))
        XCTAssertEqual(state.vestOn, true)
        XCTAssertEqual(state.vestWeightLbs, 20)
        XCTAssertEqual(state.template, spec)
    }

    func test_finishingRun1BeginsRoundsAndRecordsSplit() {
        let state = SessionState.replay([
            started(),
            .runFinished(index: 1, at: t(500), distanceMeters: 1609.34),
        ])

        XCTAssertEqual(state.phase, .rounds)
        XCTAssertEqual(state.roundsStartedAt, t(500))
        XCTAssertEqual(state.runSplits.count, 1)
        XCTAssertEqual(state.runSplits[0].index, 1)
        XCTAssertEqual(state.runSplits[0].durationSeconds, 500, accuracy: 0.001)
        XCTAssertEqual(state.runSplits[0].distanceMeters, 1609.34)
    }

    func test_lastRoundBeginsRun2() {
        let state = SessionState.replay([
            started(),
            .runFinished(index: 1, at: t(500), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(560)),
            .roundCompleted(number: 2, at: t(620)),
            .roundCompleted(number: 3, at: t(680)),
        ])

        XCTAssertEqual(state.phase, .run2)
        XCTAssertEqual(state.completedRounds, 3)
        XCTAssertEqual(state.roundTimestamps, [t(560), t(620), t(680)])
        XCTAssertEqual(state.currentPhaseStartedAt, t(680))
    }

    func test_finishingRun2CompletesTheSession() {
        let state = SessionState.replay([
            started(),
            .runFinished(index: 1, at: t(500), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(560)),
            .roundCompleted(number: 2, at: t(620)),
            .roundCompleted(number: 3, at: t(680)),
            .runFinished(index: 2, at: t(1200), distanceMeters: nil),
        ])

        XCTAssertEqual(state.phase, .completed)
        XCTAssertEqual(state.status, .completed)
        XCTAssertEqual(state.completedAt, t(1200))
        XCTAssertTrue(state.isTerminal)
    }

    func test_undoRevertsTheRun2Transition() {
        // Mis-tapping the final round advances into run 2; undo must put the
        // session back into the rounds phase and discard that run-2 start.
        let state = SessionState.replay([
            started(),
            .runFinished(index: 1, at: t(500), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(560)),
            .roundCompleted(number: 2, at: t(620)),
            .roundCompleted(number: 3, at: t(680)),
            .roundUndone(number: 3, at: t(690)),
        ])

        XCTAssertEqual(state.phase, .rounds)
        XCTAssertEqual(state.completedRounds, 2)
        XCTAssertEqual(state.roundTimestamps, [t(560), t(620)])
    }

    func test_undoableRoundNumberTracksOnlyTheMostRecentRound() {
        var state = SessionState.replay([
            started(),
            .runFinished(index: 1, at: t(500), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(560)),
        ])
        XCTAssertEqual(state.undoableRoundNumber, 1)

        // Heart rate must NOT clear undoability — it arrives every 5 seconds and
        // would otherwise make undo almost never available.
        state.apply(.heartRate(bpm: 150, at: t(562)))
        XCTAssertEqual(state.undoableRoundNumber, 1)

        state.apply(.paused(at: t(565)))
        XCTAssertNil(state.undoableRoundNumber, "Any non-heart-rate event ends the undo window")
    }

    func test_pauseAndResumeRecordAnInterval() {
        let state = SessionState.replay([
            started(),
            .paused(at: t(100)),
            .resumed(at: t(400)),
        ])

        XCTAssertFalse(state.isPaused)
        XCTAssertEqual(state.pausedIntervals.count, 1)
        XCTAssertEqual(state.pausedSeconds(between: t(0), and: t(500)), 300, accuracy: 0.001)
    }

    func test_anOpenPauseCountsUpToTheQueriedMoment() {
        let state = SessionState.replay([started(), .paused(at: t(100))])

        XCTAssertTrue(state.isPaused)
        XCTAssertEqual(state.pausedSeconds(between: t(0), and: t(250)), 150, accuracy: 0.001)
    }

    func test_pausedSecondsClipsToTheQueriedWindow() {
        let state = SessionState.replay([
            started(),
            .paused(at: t(100)),
            .resumed(at: t(400)),
        ])

        // Only the overlap counts, not the whole interval.
        XCTAssertEqual(state.pausedSeconds(between: t(200), and: t(300)), 100, accuracy: 0.001)
        XCTAssertEqual(state.pausedSeconds(between: t(500), and: t(600)), 0, accuracy: 0.001)
    }

    func test_runSplitDurationExcludesPauseTakenDuringTheRun() {
        let state = SessionState.replay([
            started(),
            .paused(at: t(100)),
            .resumed(at: t(400)),
            .runFinished(index: 1, at: t(800), distanceMeters: nil),
        ])

        // 800s of wall time, 300s of it paused.
        XCTAssertEqual(state.runSplits[0].durationSeconds, 500, accuracy: 0.001)
    }

    func test_abandonKeepsThePhaseItStoppedIn() {
        let state = SessionState.replay([
            started(),
            .runFinished(index: 1, at: t(500), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(560)),
            .abandoned(at: t(600)),
        ])

        XCTAssertEqual(state.status, .abandoned)
        XCTAssertEqual(state.phase, .rounds, "Phase records where the attempt stopped")
        XCTAssertEqual(state.completedRounds, 1)
        XCTAssertTrue(state.isTerminal)
    }

    func test_heartRateUpdatesLatestOnly() {
        let state = SessionState.replay([
            started(),
            .heartRate(bpm: 120, at: t(10)),
            .heartRate(bpm: 155, at: t(20)),
        ])

        XCTAssertEqual(state.latestHeartRate, 155)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/SessionStateReplayTests`

Expected: compile failure — `cannot find 'SessionState' in scope`.

- [ ] **Step 3: Write SessionState**

Create `MurphCore/SessionState.swift`:

```swift
// MurphCore/SessionState.swift
import Foundation

/// One paused stretch, excluded from every duration that spans it.
struct PausedInterval: Codable, Equatable {
    var start: Date
    var end: Date
}

/// A completed run, with its duration already net of any pause taken during it.
struct RunSplitState: Codable, Equatable {
    var index: Int
    var startTime: Date
    var durationSeconds: Double
    var distanceMeters: Double?
}

/// The state of a live session, produced entirely by folding an event array.
///
/// Nothing here is authored directly — `replay` and `apply` are the only ways
/// in, which is what makes crash recovery free: replay the journal and you are
/// exactly where you were.
struct SessionState: Equatable {
    var template: TemplateSpec?
    var vestOn: Bool = false
    var vestWeightLbs: Int?
    var indoor: Bool = false

    var phase: SessionPhase = .notStarted
    var status: SessionStatus = .inProgress

    var startedAt: Date?
    /// When the *current* phase began — used to time runs.
    var currentPhaseStartedAt: Date?
    /// When the rounds phase began; the boundary before round 1. Kept
    /// separately from `currentPhaseStartedAt` so undoing out of run 2 can
    /// restore the rounds phase without losing the round-timing origin.
    var roundsStartedAt: Date?
    var completedAt: Date?

    var completedRounds: Int = 0
    var roundTimestamps: [Date] = []
    var runSplits: [RunSplitState] = []

    var pausedAt: Date?
    var pausedIntervals: [PausedInterval] = []

    var latestHeartRate: Int?

    /// The round that may still be undone, or `nil` if undo is not available.
    /// Set by `roundCompleted` and cleared by any other non-heart-rate event —
    /// heart rate arrives every 5 seconds and must not close the undo window.
    var undoableRoundNumber: Int?

    var isPaused: Bool { pausedAt != nil }
    var isTerminal: Bool { status == .completed || status == .abandoned }

    static func replay(_ events: [SessionEvent]) -> SessionState {
        var state = SessionState()
        for event in events { state.apply(event) }
        return state
    }

    /// Total paused time overlapping the window, including an in-progress pause
    /// which counts up to `end`.
    func pausedSeconds(between start: Date, and end: Date) -> TimeInterval {
        var intervals = pausedIntervals
        if let pausedAt {
            intervals.append(PausedInterval(start: pausedAt, end: end))
        }
        return intervals.reduce(0) { total, interval in
            let overlapStart = max(interval.start, start)
            let overlapEnd = min(interval.end, end)
            return total + max(0, overlapEnd.timeIntervalSince(overlapStart))
        }
    }

    mutating func apply(_ event: SessionEvent) {
        // Heart rate is the only event that does not close the undo window.
        if !event.isHeartRate, case .roundCompleted = event {} else if !event.isHeartRate {
            undoableRoundNumber = nil
        }

        switch event {
        case let .started(at, template, vestOn, vestWeightLbs, indoor):
            self.template = template
            self.vestOn = vestOn
            self.vestWeightLbs = vestWeightLbs
            self.indoor = indoor
            startedAt = at
            phase = .run1
            currentPhaseStartedAt = at

        case let .runFinished(index, at, distanceMeters):
            if let phaseStart = currentPhaseStartedAt {
                let gross = at.timeIntervalSince(phaseStart)
                let paused = pausedSeconds(between: phaseStart, and: at)
                runSplits.append(RunSplitState(
                    index: index,
                    startTime: phaseStart,
                    durationSeconds: gross - paused,
                    distanceMeters: distanceMeters
                ))
            }
            if index == 1 {
                phase = .rounds
                currentPhaseStartedAt = at
                roundsStartedAt = at
            } else {
                phase = .completed
                status = .completed
                completedAt = at
                currentPhaseStartedAt = nil
            }

        case let .roundCompleted(number, at):
            roundTimestamps.append(at)
            completedRounds = number
            undoableRoundNumber = number
            if let template, completedRounds >= template.rounds {
                phase = .run2
                currentPhaseStartedAt = at
            }

        case .roundUndone:
            if !roundTimestamps.isEmpty { roundTimestamps.removeLast() }
            completedRounds = max(0, completedRounds - 1)
            if phase == .run2 {
                phase = .rounds
                currentPhaseStartedAt = roundsStartedAt
            }

        case let .paused(at):
            if pausedAt == nil { pausedAt = at }

        case let .resumed(at):
            if let start = pausedAt {
                pausedIntervals.append(PausedInterval(start: start, end: at))
                pausedAt = nil
            }

        case let .heartRate(bpm, _):
            latestHeartRate = bpm

        case let .abandoned(at):
            status = .abandoned
            completedAt = at
            currentPhaseStartedAt = nil
            // `phase` is deliberately left where it was: it is the record of
            // how far the attempt got, which the history screens display.
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/SessionStateReplayTests`

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MurphCore/SessionState.swift MurphPlusTests/SessionStateReplayTests.swift
git commit -m "feat: add SessionState with event replay and pause intervals"
```

---

### Task 3: SessionStateMachine

**Files:**
- Create: `MurphCore/SessionStateMachine.swift`
- Test: `MurphPlusTests/SessionStateMachineTests.swift`

**Interfaces:**
- Consumes: `SessionState`, `SessionEvent`, `TemplateSpec`.
- Produces, all returning `Result<SessionEvent, SessionTransitionError>`:
  - `SessionStateMachine.start(_:template:vestOn:vestWeightLbs:indoor:now:)`
  - `SessionStateMachine.finishRun(_:at:distanceMeters:)`
  - `SessionStateMachine.completeRound(_:at:)`
  - `SessionStateMachine.undoLastRound(_:at:)`
  - `SessionStateMachine.pause(_:at:)`
  - `SessionStateMachine.resume(_:at:)`
  - `SessionStateMachine.abandon(_:at:)`
  - `SessionTransitionError` — `.sessionIsTerminal`, `.wrongPhase`, `.sessionIsPaused`, `.alreadyPaused`, `.notPaused`, `.nothingToUndo`, `.noTemplate`

- [ ] **Step 1: Write the failing tests**

Create `MurphPlusTests/SessionStateMachineTests.swift`:

```swift
// MurphPlusTests/SessionStateMachineTests.swift
import XCTest
@testable import MurphPlus

final class SessionStateMachineTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    private let spec = TemplateSpec(
        id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
        totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 3
    )

    /// Replays a scripted history so each test starts from a real state.
    private func state(_ events: [SessionEvent]) -> SessionState {
        SessionState.replay(events)
    }

    private var startedEvent: SessionEvent {
        .started(at: t(0), template: spec, vestOn: false, vestWeightLbs: nil, indoor: false)
    }

    private var inRounds: [SessionEvent] {
        [startedEvent, .runFinished(index: 1, at: t(500), distanceMeters: nil)]
    }

    private func expectFailure(
        _ result: Result<SessionEvent, SessionTransitionError>,
        _ expected: SessionTransitionError,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        switch result {
        case .success(let event):
            XCTFail("Expected \(expected), got event \(event)", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error, expected, file: file, line: line)
        }
    }

    // MARK: - Start

    func test_startFromNotStartedProducesStartedEvent() throws {
        let result = SessionStateMachine.start(
            SessionState(), template: spec, vestOn: true, vestWeightLbs: 20,
            indoor: false, now: t(0)
        )

        let event = try result.get()
        XCTAssertEqual(event, .started(at: t(0), template: spec, vestOn: true, vestWeightLbs: 20, indoor: false))
    }

    func test_startTwiceIsRejected() {
        let result = SessionStateMachine.start(
            state([startedEvent]), template: spec, vestOn: false, vestWeightLbs: nil,
            indoor: false, now: t(10)
        )

        expectFailure(result, .wrongPhase)
    }

    // MARK: - Terminal guard

    func test_everyTransitionIsRejectedOnAnAbandonedSession() {
        // Abandon changes only `status`, leaving `phase` where it stopped — so a
        // phase-only guard would let an abandoned session be flipped back to
        // completed, destroying the record.
        let abandoned = state(inRounds + [.abandoned(at: t(600))])

        expectFailure(SessionStateMachine.completeRound(abandoned, at: t(700)), .sessionIsTerminal)
        expectFailure(SessionStateMachine.finishRun(abandoned, at: t(700), distanceMeters: nil), .sessionIsTerminal)
        expectFailure(SessionStateMachine.pause(abandoned, at: t(700)), .sessionIsTerminal)
        expectFailure(SessionStateMachine.abandon(abandoned, at: t(700)), .sessionIsTerminal)
        expectFailure(SessionStateMachine.undoLastRound(abandoned, at: t(700)), .sessionIsTerminal)
    }

    // MARK: - Rounds

    func test_completeRoundNumbersTheNextRound() throws {
        let s = state(inRounds + [.roundCompleted(number: 1, at: t(560))])

        let event = try SessionStateMachine.completeRound(s, at: t(620)).get()

        XCTAssertEqual(event, .roundCompleted(number: 2, at: t(620)))
    }

    func test_completeRoundIsRejectedDuringARun() {
        expectFailure(
            SessionStateMachine.completeRound(state([startedEvent]), at: t(100)),
            .wrongPhase
        )
    }

    func test_completeRoundIsRejectedWhilePaused() {
        let paused = state(inRounds + [.paused(at: t(520))])

        expectFailure(SessionStateMachine.completeRound(paused, at: t(560)), .sessionIsPaused)
    }

    func test_finishRunIsRejectedWhilePaused() {
        let paused = state([startedEvent, .paused(at: t(100))])

        expectFailure(SessionStateMachine.finishRun(paused, at: t(200), distanceMeters: nil), .sessionIsPaused)
    }

    // MARK: - Undo

    func test_undoIsAvailableImmediatelyAfterARound() throws {
        let s = state(inRounds + [.roundCompleted(number: 1, at: t(560))])

        let event = try SessionStateMachine.undoLastRound(s, at: t(570)).get()

        XCTAssertEqual(event, .roundUndone(number: 1, at: t(570)))
    }

    func test_undoSurvivesInterveningHeartRate() throws {
        let s = state(inRounds + [
            .roundCompleted(number: 1, at: t(560)),
            .heartRate(bpm: 150, at: t(565)),
        ])

        let event = try SessionStateMachine.undoLastRound(s, at: t(570)).get()

        XCTAssertEqual(event, .roundUndone(number: 1, at: t(570)))
    }

    func test_undoIsRejectedWhenNoRoundWasJustLogged() {
        expectFailure(
            SessionStateMachine.undoLastRound(state(inRounds), at: t(560)),
            .nothingToUndo
        )
    }

    func test_undoIsRejectedTwiceInARow() {
        let s = state(inRounds + [
            .roundCompleted(number: 1, at: t(560)),
            .roundUndone(number: 1, at: t(570)),
        ])

        expectFailure(SessionStateMachine.undoLastRound(s, at: t(580)), .nothingToUndo)
    }

    func test_undoIsAllowedAcrossTheRun2Boundary() throws {
        let s = state(inRounds + [
            .roundCompleted(number: 1, at: t(560)),
            .roundCompleted(number: 2, at: t(620)),
            .roundCompleted(number: 3, at: t(680)),
        ])
        XCTAssertEqual(s.phase, .run2)

        let event = try SessionStateMachine.undoLastRound(s, at: t(690)).get()

        XCTAssertEqual(event, .roundUndone(number: 3, at: t(690)))
    }

    // MARK: - Pause

    func test_pauseAndResume() throws {
        let s = state(inRounds)

        let pausedEvent = try SessionStateMachine.pause(s, at: t(520)).get()
        XCTAssertEqual(pausedEvent, .paused(at: t(520)))

        var paused = s
        paused.apply(pausedEvent)
        let resumedEvent = try SessionStateMachine.resume(paused, at: t(700)).get()
        XCTAssertEqual(resumedEvent, .resumed(at: t(700)))
    }

    func test_pauseTwiceIsRejected() {
        let paused = state(inRounds + [.paused(at: t(520))])

        expectFailure(SessionStateMachine.pause(paused, at: t(530)), .alreadyPaused)
    }

    func test_resumeWithoutPauseIsRejected() {
        expectFailure(SessionStateMachine.resume(state(inRounds), at: t(530)), .notPaused)
    }

    func test_pauseBeforeStartingIsRejected() {
        expectFailure(SessionStateMachine.pause(SessionState(), at: t(0)), .wrongPhase)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/SessionStateMachineTests`

Expected: compile failure — `cannot find 'SessionStateMachine' in scope`.

- [ ] **Step 3: Write the state machine**

Create `MurphCore/SessionStateMachine.swift`:

```swift
// MurphCore/SessionStateMachine.swift
import Foundation

enum SessionTransitionError: Error, Equatable {
    case sessionIsTerminal
    case wrongPhase
    case sessionIsPaused
    case alreadyPaused
    case notPaused
    case nothingToUndo
    case noTemplate
}

/// The transition rules for a live session.
///
/// Every function is pure: it takes the current state and *returns an event*,
/// never mutating anything. Callers apply the returned event — to a
/// `SessionState`, to SwiftData, to a journal file — which is what lets the
/// phone and the Watch share one set of rules while persisting differently.
enum SessionStateMachine {

    private static func guardActive(_ state: SessionState) -> SessionTransitionError? {
        // Status, not phase. `abandon` changes only `status`, leaving `phase`
        // wherever it stopped — a phase-only guard would let a later transition
        // silently flip an abandoned session back to completed.
        state.isTerminal ? .sessionIsTerminal : nil
    }

    static func start(
        _ state: SessionState, template: TemplateSpec, vestOn: Bool,
        vestWeightLbs: Int?, indoor: Bool, now: Date
    ) -> Result<SessionEvent, SessionTransitionError> {
        if let error = guardActive(state) { return .failure(error) }
        guard state.phase == .notStarted else { return .failure(.wrongPhase) }
        return .success(.started(
            at: now, template: template, vestOn: vestOn,
            vestWeightLbs: vestWeightLbs, indoor: indoor
        ))
    }

    static func finishRun(
        _ state: SessionState, at now: Date, distanceMeters: Double?
    ) -> Result<SessionEvent, SessionTransitionError> {
        if let error = guardActive(state) { return .failure(error) }
        guard !state.isPaused else { return .failure(.sessionIsPaused) }
        guard state.phase == .run1 || state.phase == .run2 else { return .failure(.wrongPhase) }
        let index = state.phase == .run1 ? 1 : 2
        return .success(.runFinished(index: index, at: now, distanceMeters: distanceMeters))
    }

    static func completeRound(
        _ state: SessionState, at now: Date
    ) -> Result<SessionEvent, SessionTransitionError> {
        if let error = guardActive(state) { return .failure(error) }
        guard !state.isPaused else { return .failure(.sessionIsPaused) }
        guard state.phase == .rounds else { return .failure(.wrongPhase) }
        guard state.template != nil else { return .failure(.noTemplate) }
        return .success(.roundCompleted(number: state.completedRounds + 1, at: now))
    }

    /// Permitted only while a round is still the most recent meaningful event —
    /// which allows correcting a mis-tap, including one that just advanced the
    /// session into run 2, without letting history be unwound further back.
    static func undoLastRound(
        _ state: SessionState, at now: Date
    ) -> Result<SessionEvent, SessionTransitionError> {
        if let error = guardActive(state) { return .failure(error) }
        guard let number = state.undoableRoundNumber else { return .failure(.nothingToUndo) }
        return .success(.roundUndone(number: number, at: now))
    }

    static func pause(
        _ state: SessionState, at now: Date
    ) -> Result<SessionEvent, SessionTransitionError> {
        if let error = guardActive(state) { return .failure(error) }
        guard state.phase != .notStarted else { return .failure(.wrongPhase) }
        guard !state.isPaused else { return .failure(.alreadyPaused) }
        return .success(.paused(at: now))
    }

    static func resume(
        _ state: SessionState, at now: Date
    ) -> Result<SessionEvent, SessionTransitionError> {
        if let error = guardActive(state) { return .failure(error) }
        guard state.isPaused else { return .failure(.notPaused) }
        return .success(.resumed(at: now))
    }

    static func abandon(
        _ state: SessionState, at now: Date
    ) -> Result<SessionEvent, SessionTransitionError> {
        if let error = guardActive(state) { return .failure(error) }
        return .success(.abandoned(at: now))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/SessionStateMachineTests`

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MurphCore/SessionStateMachine.swift MurphPlusTests/SessionStateMachineTests.swift
git commit -m "feat: add pure SessionStateMachine returning events"
```

---

### Task 4: Pause-aware derivation

The highest-risk math in the plan. Round durations feed the least-squares
fatigue fit, so a pause not subtracted from the round containing it produces a
plausible-looking but wrong prediction, with no visible symptom.

**Files:**
- Create: `MurphCore/SessionDerivation.swift`
- Test: `MurphPlusTests/SessionDerivationTests.swift`

**Interfaces:**
- Consumes: `SessionState`.
- Produces:
  - `SessionDerivation.elapsed(_ state: SessionState, now: Date) -> TimeInterval`
  - `SessionDerivation.roundDurations(_ state: SessionState) -> [TimeInterval]`

- [ ] **Step 1: Write the failing tests**

Create `MurphPlusTests/SessionDerivationTests.swift`:

```swift
// MurphPlusTests/SessionDerivationTests.swift
import XCTest
@testable import MurphPlus

final class SessionDerivationTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    private let spec = TemplateSpec(
        id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
        totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 3
    )

    private var startedEvent: SessionEvent {
        .started(at: t(0), template: spec, vestOn: false, vestWeightLbs: nil, indoor: false)
    }

    // MARK: - Elapsed

    func test_elapsedOnARunningSessionCountsToNow() {
        let state = SessionState.replay([startedEvent])

        XCTAssertEqual(SessionDerivation.elapsed(state, now: t(300)), 300, accuracy: 0.001)
    }

    func test_elapsedExcludesPausedTime() {
        let state = SessionState.replay([
            startedEvent,
            .paused(at: t(100)),
            .resumed(at: t(400)),
        ])

        // 500s of wall clock, 300s paused.
        XCTAssertEqual(SessionDerivation.elapsed(state, now: t(500)), 200, accuracy: 0.001)
    }

    func test_elapsedStopsCountingWhilePaused() {
        let state = SessionState.replay([startedEvent, .paused(at: t(100))])

        XCTAssertEqual(SessionDerivation.elapsed(state, now: t(400)), 100, accuracy: 0.001)
        XCTAssertEqual(SessionDerivation.elapsed(state, now: t(900)), 100, accuracy: 0.001)
    }

    func test_elapsedOnACompletedSessionIgnoresNow() {
        let state = SessionState.replay([
            startedEvent,
            .runFinished(index: 1, at: t(100), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(200)),
            .roundCompleted(number: 2, at: t(300)),
            .roundCompleted(number: 3, at: t(400)),
            .runFinished(index: 2, at: t(500), distanceMeters: nil),
        ])

        XCTAssertEqual(SessionDerivation.elapsed(state, now: t(99_999)), 500, accuracy: 0.001)
    }

    func test_elapsedIsZeroBeforeStarting() {
        XCTAssertEqual(SessionDerivation.elapsed(SessionState(), now: t(500)), 0, accuracy: 0.001)
    }

    // MARK: - Round durations

    func test_roundDurationsMeasureFromTheRoundsPhaseStart() {
        let state = SessionState.replay([
            startedEvent,
            .runFinished(index: 1, at: t(500), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(560)),
            .roundCompleted(number: 2, at: t(650)),
            .roundCompleted(number: 3, at: t(700)),
        ])

        let durations = SessionDerivation.roundDurations(state)

        XCTAssertEqual(durations.count, 3)
        XCTAssertEqual(durations[0], 60, accuracy: 0.001)
        XCTAssertEqual(durations[1], 90, accuracy: 0.001)
        XCTAssertEqual(durations[2], 50, accuracy: 0.001)
    }

    /// THE test this whole task exists for. A pause inside round 2 must be
    /// charged to round 2 and to no other round — otherwise the fatigue fit
    /// reads a ten-minute round and predicts nonsense.
    func test_pauseInsideARoundIsSubtractedFromThatRoundOnly() {
        let state = SessionState.replay([
            startedEvent,
            .runFinished(index: 1, at: t(500), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(560)),
            .paused(at: t(580)),
            .resumed(at: t(1180)),          // a ten-minute interruption
            .roundCompleted(number: 2, at: t(1240)),
            .roundCompleted(number: 3, at: t(1300)),
        ])

        let durations = SessionDerivation.roundDurations(state)

        XCTAssertEqual(durations[0], 60, accuracy: 0.001, "Round 1 predates the pause")
        XCTAssertEqual(durations[1], 80, accuracy: 0.001, "680s of wall time minus 600s paused")
        XCTAssertEqual(durations[2], 60, accuracy: 0.001, "Round 3 postdates the pause")
    }

    func test_pauseSpanningARoundBoundaryIsSplitAcrossBothRounds() {
        let state = SessionState.replay([
            startedEvent,
            .runFinished(index: 1, at: t(500), distanceMeters: nil),
            .paused(at: t(520)),
            .roundCompleted(number: 1, at: t(560)),   // logged during the pause window
            .resumed(at: t(600)),
            .roundCompleted(number: 2, at: t(660)),
        ])

        let durations = SessionDerivation.roundDurations(state)

        // Round 1: 60s wall, 40s of it paused. Round 2: 100s wall, 40s paused.
        XCTAssertEqual(durations[0], 20, accuracy: 0.001)
        XCTAssertEqual(durations[1], 60, accuracy: 0.001)
    }

    func test_noRoundsYieldsNoDurations() {
        let state = SessionState.replay([
            startedEvent,
            .runFinished(index: 1, at: t(500), distanceMeters: nil),
        ])

        XCTAssertTrue(SessionDerivation.roundDurations(state).isEmpty)
    }

    func test_undoneRoundIsNotCounted() {
        let state = SessionState.replay([
            startedEvent,
            .runFinished(index: 1, at: t(500), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(560)),
            .roundCompleted(number: 2, at: t(620)),
            .roundUndone(number: 2, at: t(625)),
        ])

        XCTAssertEqual(SessionDerivation.roundDurations(state).count, 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/SessionDerivationTests`

Expected: compile failure — `cannot find 'SessionDerivation' in scope`.

- [ ] **Step 3: Write the derivation**

Create `MurphCore/SessionDerivation.swift`:

```swift
// MurphCore/SessionDerivation.swift
import Foundation

/// Durations derived from a session's state, all of them net of paused time.
///
/// Pause exists so an interruption does not skew a logged time. That is only
/// true if every duration that spans a pause excludes it — including per-round
/// durations, which feed the least-squares fatigue fit. A pause charged to a
/// round produces a plausible-looking but wrong prediction with no visible
/// symptom, which is the most expensive kind of bug this app can have.
enum SessionDerivation {

    static func elapsed(_ state: SessionState, now: Date) -> TimeInterval {
        guard let startedAt = state.startedAt else { return 0 }
        let end = state.completedAt ?? now
        let gross = end.timeIntervalSince(startedAt)
        return max(0, gross - state.pausedSeconds(between: startedAt, and: end))
    }

    /// One duration per completed round, in order. Round *n* is measured from
    /// the previous round's completion — or from the start of the rounds phase,
    /// for round 1 — with any overlapping paused time removed.
    static func roundDurations(_ state: SessionState) -> [TimeInterval] {
        guard let roundsStartedAt = state.roundsStartedAt else { return [] }

        var durations: [TimeInterval] = []
        var boundary = roundsStartedAt
        for timestamp in state.roundTimestamps {
            let gross = timestamp.timeIntervalSince(boundary)
            let paused = state.pausedSeconds(between: boundary, and: timestamp)
            durations.append(max(0, gross - paused))
            boundary = timestamp
        }
        return durations
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/SessionDerivationTests`

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MurphCore/SessionDerivation.swift MurphPlusTests/SessionDerivationTests.swift
git commit -m "feat: add pause-aware elapsed and round duration derivation

Pause time overlapping a round's interval is subtracted from that
round. Round durations feed the fatigue regression, so a pause charged
to a round would produce a wrong prediction with no visible symptom."
```

---

### Task 5: Rewire SessionEngine as an adapter

**Files:**
- Modify: `MurphPlus/Session/SessionEngine.swift` (full rewrite of the body, same public API)
- Modify: `MurphPlus/Models/MurphSession.swift`, `MurphPlus/Models/RoundLog.swift`
- Modify: `MurphPlus/Prediction/RoundThroughputBuilder.swift`
- Test: `MurphPlusTests/SessionEngineTests.swift` — **must not be edited**

**Interfaces:**
- Consumes: everything from Tasks 1–4.
- Produces:
  - `SessionEngine` keeps `start()`, `finishRun()`, `completeRound()`, `abandon()`, `totalElapsed`, `session`, `startNew(template:vestOn:vestWeightLbs:context:)` — all unchanged in signature.
  - Adds `pause()`, `resume()`, `undoLastRound()`, and `var isPaused: Bool`. Task 6 consumes `pause()`, `resume()`, `isPaused`.
  - `MurphSession.pausedSeconds: Double`, `MurphSession.pausedAt: Date?`
  - `RoundLog.pausedSecondsInRound: Double`

**On persisting pause:** the phone stores *net* values at write time rather
than an interval list — `RunSplit.durationSeconds` is already net, and
`RoundLog` gains `pausedSecondsInRound`. This is why a relaunch mid-session is
safe with an empty `pausedIntervals`: every already-logged round carries its
own correction, and only future rounds need live tracking.

- [ ] **Step 1: Add the model fields**

In `MurphPlus/Models/MurphSession.swift`, add:

```swift
    var pausedSeconds: Double = 0
    var pausedAt: Date?
```

and make total elapsed net of pause:

```swift
    var totalElapsedSeconds: Double? {
        guard let startedAt, let completedAt else { return nil }
        return max(0, completedAt.timeIntervalSince(startedAt) - pausedSeconds)
    }
```

In `MurphPlus/Models/RoundLog.swift`, add:

```swift
    /// Paused time falling inside this round's interval, already excluded from
    /// the round's effective duration. Stored rather than derived so a relaunch
    /// mid-session cannot lose the correction.
    var pausedSecondsInRound: Double = 0
```

- [ ] **Step 2: Rewrite SessionEngine as an adapter**

Replace the body of `MurphPlus/Session/SessionEngine.swift`:

```swift
// MurphPlus/Session/SessionEngine.swift
import Foundation
import Observation
import SwiftData

/// The phone's adapter over `MurphCore`.
///
/// Every method asks `SessionStateMachine` for an event and then applies that
/// event to both the in-memory `SessionState` and the SwiftData model. The
/// state machine owns the rules; this type owns persistence. Its public API is
/// unchanged from the pre-extraction version, and `SessionEngineTests` passes
/// untouched — that is the proof the extraction preserved behavior.
@Observable
final class SessionEngine {
    private(set) var session: MurphSession
    private(set) var state: SessionState
    private let context: ModelContext

    init(session: MurphSession, context: ModelContext) {
        self.session = session
        self.context = context
        self.state = SessionEngine.rebuildState(from: session)
    }

    static func startNew(template: WorkoutTemplate, vestOn: Bool, vestWeightLbs: Int?, context: ModelContext) -> SessionEngine {
        let session = MurphSession(template: template, vestOn: vestOn, vestWeightLbs: vestWeightLbs)
        context.insert(session)
        try? context.save()
        return SessionEngine(session: session, context: context)
    }

    var isPaused: Bool { state.isPaused }

    var totalElapsed: TimeInterval {
        SessionDerivation.elapsed(state, now: .now)
    }

    // MARK: - Transitions

    func start() {
        guard let spec = session.template?.spec else { return }
        perform(SessionStateMachine.start(
            state, template: spec, vestOn: session.vestOn,
            vestWeightLbs: session.vestWeightLbs, indoor: session.indoor, now: .now
        ))
    }

    func finishRun() {
        perform(SessionStateMachine.finishRun(state, at: .now, distanceMeters: nil))
    }

    func completeRound() {
        perform(SessionStateMachine.completeRound(state, at: .now))
    }

    func undoLastRound() {
        perform(SessionStateMachine.undoLastRound(state, at: .now))
    }

    func pause() {
        perform(SessionStateMachine.pause(state, at: .now))
    }

    func resume() {
        perform(SessionStateMachine.resume(state, at: .now))
    }

    func abandon() {
        perform(SessionStateMachine.abandon(state, at: .now))
    }

    // MARK: - Applying events

    /// A rejected transition is silently ignored, matching the pre-extraction
    /// engine's `guard … else { return }` posture: these are impossible-button
    /// guards, not user-facing errors.
    private func perform(_ result: Result<SessionEvent, SessionTransitionError>) {
        guard case let .success(event) = result else { return }
        let before = state
        state.apply(event)
        applyToModel(event, before: before)
        save()
    }

    private func applyToModel(_ event: SessionEvent, before: SessionState) {
        switch event {
        case let .started(at, _, _, _, _):
            session.startedAt = at
            session.phase = .run1
            session.currentPhaseStartedAt = at

        case .runFinished:
            // `state` already computed the split net of pause; mirror it.
            if let split = state.runSplits.last {
                let model = RunSplit(
                    runIndex: split.index,
                    startTime: split.startTime,
                    durationSeconds: split.durationSeconds,
                    session: session
                )
                context.insert(model)
                session.runSplits.append(model)
            }
            session.phase = state.phase
            session.currentPhaseStartedAt = state.currentPhaseStartedAt
            if state.phase == .completed {
                session.status = .completed
                session.completedAt = state.completedAt
            }

        case let .roundCompleted(number, at):
            let boundary = before.roundTimestamps.last ?? before.roundsStartedAt ?? at
            let log = RoundLog(roundNumber: number, completedAt: at, session: session)
            log.pausedSecondsInRound = before.pausedSeconds(between: boundary, and: at)
            context.insert(log)
            session.roundLogs.append(log)
            session.completedRounds = number
            session.phase = state.phase
            session.currentPhaseStartedAt = state.currentPhaseStartedAt

        case .roundUndone:
            if let last = session.roundLogs.max(by: { $0.roundNumber < $1.roundNumber }) {
                session.roundLogs.removeAll { $0.roundNumber == last.roundNumber }
                context.delete(last)
            }
            session.completedRounds = state.completedRounds
            session.phase = state.phase
            session.currentPhaseStartedAt = state.currentPhaseStartedAt

        case let .paused(at):
            session.pausedAt = at

        case let .resumed(at):
            if let start = session.pausedAt {
                session.pausedSeconds += at.timeIntervalSince(start)
                session.pausedAt = nil
            }

        case .heartRate:
            break // Stage 2 concern; the phone collects none.

        case let .abandoned(at):
            session.status = .abandoned
            session.completedAt = at
            session.currentPhaseStartedAt = nil
        }
    }

    /// Reconstructs core state from a persisted session, for resume-after-relaunch.
    ///
    /// `pausedIntervals` is deliberately left empty: every already-logged round
    /// and split carries its own net correction, so only pauses taken from now
    /// on need tracking. `pausedSeconds` carries the running total for elapsed.
    private static func rebuildState(from session: MurphSession) -> SessionState {
        var state = SessionState()
        state.template = session.template?.spec
        state.vestOn = session.vestOn
        state.vestWeightLbs = session.vestWeightLbs
        state.indoor = session.indoor
        state.phase = session.phase
        state.status = session.status
        state.startedAt = session.startedAt
        state.currentPhaseStartedAt = session.currentPhaseStartedAt
        state.completedAt = session.completedAt
        state.completedRounds = session.completedRounds
        state.pausedAt = session.pausedAt
        state.roundTimestamps = session.roundLogs
            .sorted { $0.roundNumber < $1.roundNumber }
            .map(\.completedAt)
        state.runSplits = session.runSplits
            .sorted { $0.runIndex < $1.runIndex }
            .map { RunSplitState(index: $0.runIndex, startTime: $0.startTime,
                                 durationSeconds: $0.durationSeconds, distanceMeters: nil) }
        // Round 1's boundary is the end of run 1.
        state.roundsStartedAt = session.runSplits.first { $0.runIndex == 1 }
            .map { $0.startTime.addingTimeInterval($0.durationSeconds) }
        return state
    }

    private func save() {
        try? context.save()
    }
}
```

Note: `session.indoor` does not exist yet — add `var indoor: Bool = false` to
`MurphSession` alongside the pause fields in Step 1. It is written by the Watch
in Stage 2 and defaults to `false` for phone sessions.

- [ ] **Step 3: Subtract per-round pause in the throughput builder**

In `MurphPlus/Prediction/RoundThroughputBuilder.swift`, where a round's duration
is computed from consecutive `RoundLog` timestamps, subtract that round's
`pausedSecondsInRound` before it becomes `secondsForRound`. Keep the existing
structure; this is a subtraction, not a rewrite. Add the comment:

```swift
        // Net of pause: an interruption inside a round would otherwise read as
        // a very slow round and bend the fatigue curve.
```

- [ ] **Step 4: Run the full suite — including the untouched engine tests**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`

Expected: `** TEST SUCCEEDED **`.

**If `SessionEngineTests` fails, the extraction changed behavior it was not
supposed to. Fix the engine — do not edit the test.** That file is the contract.

- [ ] **Step 5: Commit**

```bash
git add MurphCore MurphPlus/Session/SessionEngine.swift MurphPlus/Models \
        MurphPlus/Prediction/RoundThroughputBuilder.swift
git commit -m "refactor: rewire SessionEngine as an adapter over MurphCore

The state machine now owns the rules and returns events; the engine
owns persistence and applies them. Public API and behavior unchanged —
SessionEngineTests passes untouched, which is the proof.

Pause is persisted as net values at write time (RunSplit duration,
RoundLog.pausedSecondsInRound) so a relaunch mid-session cannot lose
the per-round correction."
```

---

### Task 6: Pause control on the phone

**Files:**
- Modify: `MurphPlus/Views/Session/LiveSessionView.swift`

**Interfaces:**
- Consumes: `engine.pause()`, `engine.resume()`, `engine.isPaused` from Task 5.
- Produces: nothing consumed later.

- [ ] **Step 1: Add the pause control**

In `LiveSessionView.swift`, in the bottom `VStack` that holds the primary
action, add a secondary control beneath it (this is the same `VStack` the fix
batch left holding only the primary button):

```swift
            VStack(spacing: MurphSpacing.space3) {
                MurphButton(variant: .primary, size: .lg, full: true, icon: Image(systemName: copy.icon), title: copy.action) {
                    advance()
                }
                if phase != .notStarted && phase != .completed {
                    MurphButton(
                        variant: .secondary,
                        full: true,
                        icon: Image(systemName: engine.isPaused ? "play.fill" : "pause.fill"),
                        title: engine.isPaused ? "Resume" : "Pause"
                    ) {
                        if engine.isPaused { engine.resume() } else { engine.pause() }
                    }
                }
            }
```

- [ ] **Step 2: Stop the clock and block the primary action while paused**

The clock already reads `engine.totalElapsed`, which `SessionDerivation`
freezes during a pause, so it stops on its own. Mark it visually and prevent
logging a round while paused — the state machine rejects it anyway, but a
button that silently does nothing is the exact defect the fix batch removed
from the toolbar.

In the `TimelineView` block, set the clock's `running` argument to also require
not-paused:

```swift
                    running: phase != .notStarted && phase != .completed && !engine.isPaused,
```

and disable the primary action:

```swift
                .disabled(engine.isPaused)
```

applied to the primary `MurphButton`.

- [ ] **Step 3: Add a paused badge**

In the `MurphFlowLayout` of badges near the top of `content`, add:

```swift
                if engine.isPaused {
                    MurphBadge(tone: .abandoned, title: "Paused")
                }
```

`.abandoned` is the dust tone — the design system's existing "stopped, not
failed" colour, which is exactly what a pause is.

- [ ] **Step 4: Build and run the full suite**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Verify by hand in the simulator**

Start a session against a 3-round template. Finish run 1, complete round 1,
then **Pause**. Confirm: the clock stops, a dust "Paused" badge appears, the
primary button is disabled, and the control reads "Resume". Wait ~30 seconds,
resume, complete rounds 2 and 3, finish run 2. Open the session in History and
confirm the total time excludes the paused stretch, and that round 2's pace is
in line with rounds 1 and 3 rather than wildly slower.

That last check is the whole point of Task 4 — if round 2 looks slow, the pause
was charged to the round.

- [ ] **Step 6: Commit**

```bash
git add MurphPlus/Views/Session/LiveSessionView.swift
git commit -m "feat: add pause to the phone live session"
```

---

## Self-Review

**Spec coverage for this stage:**

| Spec section | Task |
|---|---|
| `MurphCore` directory, Foundation-only, both targets | Task 1 |
| `TemplateSpec` | Task 1 |
| `SessionEvent` incl. all eight cases | Task 1 |
| `SessionState` + replay | Task 2 |
| Implicit phase transitions | Task 2 |
| Undo rule (last non-HR event is a round) | Tasks 2, 3 |
| `SessionStateMachine` + terminal guard on status | Task 3 |
| Pause: elapsed excludes paused time | Task 4 |
| Pause: per-round subtraction | Task 4 (the task's central test) |
| Pause rejects round/run transitions | Task 3 |
| `SessionEngine` as adapter, existing tests untouched | Task 5 |
| `WorkoutTemplate.id` | Task 1 |
| Phone pause control | Task 6 |

Deferred to later stages, by design: the watchOS target, HealthKit, heart rate
capture and bucketing, the journal file, `WatchConnectivity`, the phone mirror,
`MurphSession.id`/`originRaw`/`journalData`/`lastCheckpointSeq`, and the
session-detail HR and distance columns.

**Placeholder scan:** No TBD/TODO. Two steps describe an edit rather than
showing a full diff — Task 5 Step 3 (`RoundThroughputBuilder`) and Task 6
Step 2 — because both are single-expression changes inside code whose
surrounding structure the implementer must read anyway; both name the exact
symbol and the exact change.

**Type consistency:** `SessionEvent` case labels used in Task 2 and 3 tests
match the declaration in Task 1. `SessionState.pausedSeconds(between:and:)` is
declared in Task 2 and used in Tasks 4 and 5. `SessionDerivation.elapsed(_:now:)`
and `.roundDurations(_:)` are declared in Task 4 and used in Task 5.
`SessionTransitionError` cases asserted in Task 3's tests match the enum in the
same task. `engine.isPaused`, `engine.pause()`, `engine.resume()` are declared
in Task 5 and consumed in Task 6. `session.indoor` is flagged in Task 5 Step 2
as needing addition in Step 1.
