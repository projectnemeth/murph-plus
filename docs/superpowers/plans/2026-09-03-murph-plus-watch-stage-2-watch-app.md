# Murph Plus Watch — Stage 2: The Watch App

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A watchOS app that runs a complete Murph on the wrist — setup, runs with live distance, round tapping, pause, undo, abandon, completion — backed by an `HKWorkoutSession` for heart rate, distance, screen wake and Activity rings, persisting to an event journal that survives a crash.

**Architecture:** The watch app is a thin shell over `MurphCore` from Stage 1. It adds three things: a journal file (append-only `SessionEvent` lines, state rebuilt by replay), a HealthKit controller, and SwiftUI. The journal lives in `MurphCore` — it is Foundation-only — so it is unit-tested from the existing iOS test bundle rather than needing a watchOS test target.

**Tech Stack:** Swift, SwiftUI, HealthKit, XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-03-murph-plus-watch-design.md`

**Prerequisite:** Stage 1 complete and merged.

**Ships working software on its own:** a standalone wrist tracker. **Caveat, stated plainly:** sessions recorded in this stage stay on the Watch — they do not reach the phone until Stage 3. The completion screen is the end of the story for now.

## Global Constraints

- watchOS 10 deployment target; iOS 17 unchanged.
- `MurphCore` still imports `Foundation` and nothing else. `SessionJournal` joins it and must respect that — `FileManager` and `JSONEncoder` are Foundation, HealthKit is not.
- **Never auto-advance a run on distance.** GPS drift ending a run at 0.97 mi while the user is still running is worse than a button. Distance is displayed, never acted on.
- **Every HealthKit and location permission is optional to the app functioning.** Denied HealthKit yields a complete session with no heart rate. Denied location falls back to the accelerometer. Setup never blocks on a prompt.
- **`Round Done` must appear on both metric pages** (slots 2 and 3). Paging changes what the user reads, never what they can do.
- Page position survives a phase change — do not reset `selection` when the phase changes.
- Re-run `xcodegen generate` after adding any new source file.
- iOS test command unchanged: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`.
- Watch build command: `xcodebuild build -scheme MurphPlusWatch -destination 'generic/platform=watchOS' -project MurphPlus.xcodeproj`.

---

## File Structure

```
MurphCore/
  SessionJournal.swift                CREATE — append-only event log, replay, resume
  HeartRateAggregation.swift          CREATE — bucket HR events into windows
MurphPlusWatch/                       CREATE — the watchOS target
  MurphPlusWatchApp.swift             CREATE — entry point
  Session/
    WatchSessionController.swift      CREATE — journal + state machine + HealthKit, @Observable
    WorkoutSessionController.swift    CREATE — HKWorkoutSession wrapper
  Views/
    WatchSetupView.swift              CREATE — templates, vest, indoor/outdoor, Start
    WatchLiveView.swift               CREATE — the four-page TabView
    Pages/ControlsPage.swift          CREATE — pause/resume, undo, abandon
    Pages/PrimaryPage.swift           CREATE — slot 2, phase-dependent
    Pages/ClockPage.swift             CREATE — slot 3
    Pages/NowPlayingPage.swift        CREATE — slot 4
    WatchCompleteView.swift           CREATE — summary
  Components/
    WatchStatusStrip.swift            CREATE — the two-cell banded row
    WatchPrimaryButton.swift          CREATE — the advancing action
  Resources/                          CREATE — font files (copied)
project.yml                           MODIFY — watch target, embedding
MurphPlusTests/
  SessionJournalTests.swift           CREATE
  HeartRateAggregationTests.swift     CREATE
```

---

### Task 1: HealthKit spike — throwaway

The largest remaining unknown, and the only one the simulator cannot answer.
**Its output is an answer, not code you keep.** Do this before building any UI
on top of assumptions it might invalidate.

**Files:** a scratch watchOS target or Xcode playground app — **not committed**.

- [ ] **Step 1: Build a minimal watch app that runs a segmented workout**

On a real Apple Watch, stand up the smallest possible app that:

1. Requests HealthKit authorization for heart rate and distance (read) and workouts (share), plus location-when-in-use.
2. Starts an `HKWorkoutSession` configured `activityType: .crossTraining`, `locationType: .outdoor`, with an `HKLiveWorkoutBuilder`.
3. Calls `beginNewActivity` with `.running`, waits, `endCurrentActivity`, then `beginNewActivity` with `.functionalStrengthTraining`, waits, ends it, then `.running` again.
4. Prints live heart rate and cumulative `.distanceWalkingRunning` to the screen.
5. Calls `endCollection` then `finishWorkout()`.

- [ ] **Step 2: Answer these five questions and write the answers down**

1. Does the screen stay awake and the app stay frontmost for the full session?
2. In the dimmed always-on state, what actually renders — and how stale does it get? (Confirms the `isLuminanceReduced` design in Task 7.)
3. Does `.distanceWalkingRunning` accumulate **only** during the `.running` activities, or does it keep counting through the strength segment? **This determines whether Task 5 can read cumulative distance directly or must snapshot the value at each segment boundary and subtract.**
4. Does the finished workout appear in Fitness as **one** workout with three activities, and does it credit the Move and Exercise rings?
5. Does `HKWorkoutSession.pause()` actually suspend heart-rate collection, or do samples keep arriving?

- [ ] **Step 3: Report findings and discard the code**

Write the answers into the plan review, delete the scratch target, and — if
question 3 or 5 came back differently than assumed — say so before starting
Task 5, which is built on those assumptions.

**Do not commit anything from this task.**

---

### Task 2: SessionJournal

**Files:**
- Create: `MurphCore/SessionJournal.swift`
- Test: `MurphPlusTests/SessionJournalTests.swift`

**Interfaces:**
- Consumes: `SessionEvent`, `SessionState` from Stage 1.
- Produces:
  - `SessionJournal(sessionID:directory:)` throws — loads existing or creates empty
  - `journal.append(_ event: SessionEvent) throws`
  - `journal.events: [SessionEvent]`
  - `journal.state: SessionState`
  - `journal.delete() throws`
  - `SessionJournal.resumable(in directory: URL) throws -> SessionJournal?`
  - `SessionJournal.all(in directory: URL) throws -> [SessionJournal]`

- [ ] **Step 1: Write the failing tests**

Create `MurphPlusTests/SessionJournalTests.swift`:

```swift
// MurphPlusTests/SessionJournalTests.swift
import XCTest
@testable import MurphPlus

final class SessionJournalTests: XCTestCase {

    private var directory: URL!
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    private let spec = TemplateSpec(
        id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
        totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 3
    )

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("journal-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var startedEvent: SessionEvent {
        .started(at: t(0), template: spec, vestOn: false, vestWeightLbs: nil, indoor: false)
    }

    func test_appendedEventsSurviveReopening() throws {
        let id = UUID()
        let journal = try SessionJournal(sessionID: id, directory: directory)
        try journal.append(startedEvent)
        try journal.append(.runFinished(index: 1, at: t(500), distanceMeters: 1609.34))

        // A fresh instance simulates a crash and relaunch.
        let reopened = try SessionJournal(sessionID: id, directory: directory)

        XCTAssertEqual(reopened.events.count, 2)
        XCTAssertEqual(reopened.state.phase, .rounds)
        XCTAssertEqual(reopened.state.runSplits.first?.distanceMeters, 1609.34)
    }

    func test_stateIsRebuiltByReplay() throws {
        let journal = try SessionJournal(sessionID: UUID(), directory: directory)
        try journal.append(startedEvent)
        try journal.append(.runFinished(index: 1, at: t(500), distanceMeters: nil))
        try journal.append(.roundCompleted(number: 1, at: t(560)))

        XCTAssertEqual(journal.state.completedRounds, 1)
        XCTAssertEqual(journal.state.phase, .rounds)
    }

    func test_resumableFindsAnUnfinishedSession() throws {
        let journal = try SessionJournal(sessionID: UUID(), directory: directory)
        try journal.append(startedEvent)
        try journal.append(.roundCompleted(number: 1, at: t(560)))

        let found = try XCTUnwrap(SessionJournal.resumable(in: directory))

        XCTAssertEqual(found.sessionID, journal.sessionID)
    }

    func test_resumableIgnoresACompletedSession() throws {
        let journal = try SessionJournal(sessionID: UUID(), directory: directory)
        try journal.append(startedEvent)
        try journal.append(.runFinished(index: 1, at: t(100), distanceMeters: nil))
        try journal.append(.roundCompleted(number: 1, at: t(200)))
        try journal.append(.roundCompleted(number: 2, at: t(300)))
        try journal.append(.roundCompleted(number: 3, at: t(400)))
        try journal.append(.runFinished(index: 2, at: t(500), distanceMeters: nil))

        XCTAssertNil(try SessionJournal.resumable(in: directory))
    }

    func test_resumableIgnoresAnAbandonedSession() throws {
        let journal = try SessionJournal(sessionID: UUID(), directory: directory)
        try journal.append(startedEvent)
        try journal.append(.abandoned(at: t(100)))

        XCTAssertNil(try SessionJournal.resumable(in: directory))
    }

    func test_deleteRemovesTheFile() throws {
        let id = UUID()
        let journal = try SessionJournal(sessionID: id, directory: directory)
        try journal.append(startedEvent)

        try journal.delete()

        XCTAssertTrue(try SessionJournal.all(in: directory).isEmpty)
    }

    func test_aHighVolumeOfHeartRateEventsReplaysCorrectly() throws {
        // A long Murph journals ~700 heart-rate events; replay must stay correct
        // and the file must stay well-formed with that many lines.
        let journal = try SessionJournal(sessionID: UUID(), directory: directory)
        try journal.append(startedEvent)
        for i in 0..<700 {
            try journal.append(.heartRate(bpm: 140 + (i % 20), at: t(Double(i) * 5)))
        }

        let reopened = try SessionJournal(sessionID: journal.sessionID, directory: directory)

        XCTAssertEqual(reopened.events.count, 701)
        XCTAssertEqual(reopened.state.latestHeartRate, 140 + (699 % 20))
    }

    func test_anEmptyDirectoryHasNothingToResume() throws {
        XCTAssertNil(try SessionJournal.resumable(in: directory))
        XCTAssertTrue(try SessionJournal.all(in: directory).isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/SessionJournalTests`

Expected: compile failure — `cannot find 'SessionJournal' in scope`.

- [ ] **Step 3: Write the journal**

Create `MurphCore/SessionJournal.swift`:

```swift
// MurphCore/SessionJournal.swift
import Foundation

/// An append-only log of a session's events, one JSON object per line.
///
/// This is both the Watch's persistence and — in Stage 3 — its sync payload:
/// the same bytes are written to disk and shipped to the phone, so there is no
/// third representation to keep consistent. State is rebuilt by replay, which
/// is what makes crash recovery free.
///
/// Lives in `MurphCore` (Foundation only) so it is unit-testable from the iOS
/// test bundle rather than needing a watchOS test target.
final class SessionJournal {
    let sessionID: UUID
    let url: URL
    private(set) var events: [SessionEvent]

    private static let fileExtension = "journal"

    init(sessionID: UUID, directory: URL) throws {
        self.sessionID = sessionID
        self.url = directory
            .appendingPathComponent(sessionID.uuidString)
            .appendingPathExtension(Self.fileExtension)

        if FileManager.default.fileExists(atPath: url.path) {
            self.events = try Self.decodeLines(at: url)
        } else {
            self.events = []
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    var state: SessionState { SessionState.replay(events) }

    /// Appends and flushes before returning. A crash costs at most the event
    /// currently being written, never the ones already acknowledged.
    func append(_ event: SessionEvent) throws {
        var line = try JSONEncoder().encode(event)
        line.append(0x0A) // newline

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.synchronize()

        events.append(event)
    }

    func delete() throws {
        try FileManager.default.removeItem(at: url)
        events = []
    }

    static func all(in directory: URL) throws -> [SessionJournal] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        return try contents
            .filter { $0.pathExtension == fileExtension }
            .compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
            .map { try SessionJournal(sessionID: $0, directory: directory) }
    }

    /// The one unfinished session, if any — a journal whose replayed state is
    /// not terminal. The Watch offers resume or abandon for this on launch.
    static func resumable(in directory: URL) throws -> SessionJournal? {
        try all(in: directory).first { !$0.state.isTerminal && $0.state.startedAt != nil }
    }

    private static func decodeLines(at url: URL) throws -> [SessionEvent] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return data
            .split(separator: 0x0A)
            .compactMap { try? decoder.decode(SessionEvent.self, from: Data($0)) }
    }
}
```

Note the `compactMap` in `decodeLines`: a truncated final line — the signature
of a crash mid-write — is dropped rather than failing the whole journal. Losing
one event is recoverable; losing the workout is not.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/SessionJournalTests`

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MurphCore/SessionJournal.swift MurphPlusTests/SessionJournalTests.swift
git commit -m "feat: add append-only session journal with replay recovery"
```

---

### Task 3: Heart rate aggregation

**Files:**
- Create: `MurphCore/HeartRateAggregation.swift`
- Test: `MurphPlusTests/HeartRateAggregationTests.swift`

**Interfaces:**
- Consumes: `SessionEvent`, `SessionState`.
- Produces:
  - `HeartRateSummary { average: Int, maximum: Int }`
  - `HeartRateAggregator.summary(events:from:to:) -> HeartRateSummary?`
  - `HeartRateAggregator.roundSummaries(events:state:) -> [HeartRateSummary?]`
  - `HeartRateAggregator.runSummaries(events:state:) -> [Int: HeartRateSummary]` keyed by run index

- [ ] **Step 1: Write the failing tests**

Create `MurphPlusTests/HeartRateAggregationTests.swift`:

```swift
// MurphPlusTests/HeartRateAggregationTests.swift
import XCTest
@testable import MurphPlus

final class HeartRateAggregationTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    private let spec = TemplateSpec(
        id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
        totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 2
    )

    func test_summaryAveragesAndMaximisesInsideTheWindow() {
        let events: [SessionEvent] = [
            .heartRate(bpm: 100, at: t(10)),
            .heartRate(bpm: 140, at: t(20)),
            .heartRate(bpm: 120, at: t(30)),
        ]

        let summary = HeartRateAggregator.summary(events: events, from: t(0), to: t(60))

        XCTAssertEqual(summary?.average, 120)
        XCTAssertEqual(summary?.maximum, 140)
    }

    func test_summaryExcludesSamplesOutsideTheWindow() {
        let events: [SessionEvent] = [
            .heartRate(bpm: 90, at: t(5)),
            .heartRate(bpm: 150, at: t(25)),
            .heartRate(bpm: 200, at: t(95)),
        ]

        let summary = HeartRateAggregator.summary(events: events, from: t(10), to: t(60))

        XCTAssertEqual(summary?.average, 150)
        XCTAssertEqual(summary?.maximum, 150)
    }

    func test_summaryIsNilWithNoSamples() {
        // A denied HealthKit permission produces exactly this, and it must be
        // an absent summary rather than a zero.
        XCTAssertNil(HeartRateAggregator.summary(events: [], from: t(0), to: t(60)))
    }

    func test_summaryIgnoresNonHeartRateEvents() {
        let events: [SessionEvent] = [
            .roundCompleted(number: 1, at: t(20)),
            .heartRate(bpm: 130, at: t(30)),
        ]

        XCTAssertEqual(HeartRateAggregator.summary(events: events, from: t(0), to: t(60))?.average, 130)
    }

    func test_roundSummariesBucketBetweenRoundBoundaries() {
        let events: [SessionEvent] = [
            .started(at: t(0), template: spec, vestOn: false, vestWeightLbs: nil, indoor: false),
            .runFinished(index: 1, at: t(100), distanceMeters: nil),
            .heartRate(bpm: 140, at: t(120)),
            .heartRate(bpm: 160, at: t(140)),
            .roundCompleted(number: 1, at: t(200)),
            .heartRate(bpm: 170, at: t(220)),
            .heartRate(bpm: 190, at: t(240)),
            .roundCompleted(number: 2, at: t(300)),
        ]
        let state = SessionState.replay(events)

        let summaries = HeartRateAggregator.roundSummaries(events: events, state: state)

        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries[0]?.average, 150)
        XCTAssertEqual(summaries[0]?.maximum, 160)
        XCTAssertEqual(summaries[1]?.average, 180)
        XCTAssertEqual(summaries[1]?.maximum, 190)
    }

    func test_runSummariesAreKeyedByRunIndex() {
        let events: [SessionEvent] = [
            .started(at: t(0), template: spec, vestOn: false, vestWeightLbs: nil, indoor: false),
            .heartRate(bpm: 150, at: t(50)),
            .runFinished(index: 1, at: t(100), distanceMeters: nil),
            .roundCompleted(number: 1, at: t(200)),
            .roundCompleted(number: 2, at: t(300)),
            .heartRate(bpm: 180, at: t(350)),
            .runFinished(index: 2, at: t(400), distanceMeters: nil),
        ]
        let state = SessionState.replay(events)

        let summaries = HeartRateAggregator.runSummaries(events: events, state: state)

        XCTAssertEqual(summaries[1]?.average, 150)
        XCTAssertEqual(summaries[2]?.average, 180)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/HeartRateAggregationTests`

Expected: compile failure — `cannot find 'HeartRateAggregator' in scope`.

- [ ] **Step 3: Write the aggregator**

Create `MurphCore/HeartRateAggregation.swift`:

```swift
// MurphCore/HeartRateAggregation.swift
import Foundation

struct HeartRateSummary: Codable, Equatable {
    var average: Int
    var maximum: Int
}

/// Per-segment heart rate, derived by bucketing journaled samples between the
/// round and run boundaries.
///
/// Deliberately derived rather than accumulated in running state: a crash
/// cannot corrupt a partial average, and the aggregation can be changed later
/// without re-recording anything.
enum HeartRateAggregator {

    /// `nil` when the window holds no samples — an absent summary, never a zero.
    /// Denied HealthKit authorization produces exactly this case.
    static func summary(events: [SessionEvent], from start: Date, to end: Date) -> HeartRateSummary? {
        var readings: [Int] = []
        for event in events {
            guard case let .heartRate(bpm, at) = event else { continue }
            guard at >= start, at <= end else { continue }
            readings.append(bpm)
        }
        guard !readings.isEmpty else { return nil }
        return HeartRateSummary(
            average: readings.reduce(0, +) / readings.count,
            maximum: readings.max() ?? 0
        )
    }

    /// One entry per completed round, in order, aligned with
    /// `SessionDerivation.roundDurations`.
    static func roundSummaries(events: [SessionEvent], state: SessionState) -> [HeartRateSummary?] {
        guard let roundsStartedAt = state.roundsStartedAt else { return [] }
        var result: [HeartRateSummary?] = []
        var boundary = roundsStartedAt
        for timestamp in state.roundTimestamps {
            result.append(summary(events: events, from: boundary, to: timestamp))
            boundary = timestamp
        }
        return result
    }

    /// Keyed by run index (1 or 2).
    static func runSummaries(events: [SessionEvent], state: SessionState) -> [Int: HeartRateSummary] {
        var result: [Int: HeartRateSummary] = [:]
        for split in state.runSplits {
            let end = split.startTime.addingTimeInterval(split.durationSeconds)
            if let summary = summary(events: events, from: split.startTime, to: end) {
                result[split.index] = summary
            }
        }
        return result
    }
}
```

> Note on `runSummaries`: `durationSeconds` is net of pause, so a run
> containing a long pause computes an end slightly earlier than wall-clock.
> Samples are not collected while paused (the `HKWorkoutSession` is itself
> paused), so no real sample falls in the discarded tail.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/HeartRateAggregationTests`

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MurphCore/HeartRateAggregation.swift MurphPlusTests/HeartRateAggregationTests.swift
git commit -m "feat: derive per-round and per-run heart rate summaries"
```

---

### Task 4: watchOS target scaffolding

**Files:**
- Modify: `project.yml`
- Create: `MurphPlusWatch/MurphPlusWatchApp.swift`
- Copy: `MurphPlus/Resources/Fonts/*` → `MurphPlusWatch/Resources/Fonts/`

**Interfaces:**
- Produces: a buildable `MurphPlusWatch` target compiling `MurphCore` and the shared design-system foundations. Every later task adds files under `MurphPlusWatch/`, picked up by the folder glob.

- [ ] **Step 1: Add the target to project.yml**

```yaml
  MurphPlusWatch:
    type: application
    platform: watchOS
    deploymentTarget: "10.0"
    sources:
      - MurphPlusWatch
      - MurphCore
      - path: MurphPlus/DesignSystem/Foundations
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.projectnemeth.MurphPlus.watchkitapp
        SWIFT_VERSION: "5.0"
        TARGETED_DEVICE_FAMILY: "4"
        GENERATE_INFOPLIST_FILE: true
        INFOPLIST_KEY_CFBundleDisplayName: "Murph+"
        INFOPLIST_KEY_WKApplication: true
        INFOPLIST_KEY_WKCompanionAppBundleIdentifier: com.projectnemeth.MurphPlus
        INFOPLIST_KEY_NSHealthShareUsageDescription: "Murph+ reads your heart rate and distance during a workout so your session records what your body actually did."
        INFOPLIST_KEY_NSHealthUpdateUsageDescription: "Murph+ saves your Murph as a workout so it counts toward your Activity rings."
        INFOPLIST_KEY_NSLocationWhenInUseUsageDescription: "Murph+ uses location during the two runs to measure distance and pace. Choose Indoor at setup to skip this."
    info:
      properties:
        UIAppFonts:
          - ArchivoBlack-Regular.ttf
          - DMSans-Variable.ttf
          - MartianMono-Variable.ttf
```

Note `sources` deliberately includes only `DesignSystem/Foundations`, not
`Components` — the phone components are sized for a phone.

Then add the embedding dependency to the existing `MurphPlus` target:

```yaml
    dependencies:
      - target: MurphPlusWatch
        embed: true
        copy:
          destination: productsDirectory
          subpath: "$(CONTENTS_FOLDER_PATH)/Watch"
```

And a scheme:

```yaml
  MurphPlusWatch:
    build:
      targets:
        MurphPlusWatch: all
    run:
      config: Debug
```

- [ ] **Step 2: Copy the fonts**

```bash
mkdir -p MurphPlusWatch/Resources
cp -R MurphPlus/Resources/Fonts MurphPlusWatch/Resources/Fonts
```

- [ ] **Step 3: Write a placeholder entry point**

Create `MurphPlusWatch/MurphPlusWatchApp.swift`:

```swift
// MurphPlusWatch/MurphPlusWatchApp.swift
import SwiftUI

@main
struct MurphPlusWatchApp: App {
    var body: some Scene {
        WindowGroup {
            // Replaced in Task 6 by the real setup screen. This exists so the
            // target builds and the design-system foundations are proven to
            // compile for watchOS before any UI is written on top of them.
            Text("MURPH+")
                .murphType(.title(18))
                .foregroundStyle(MurphColor.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MurphColor.surfacePage)
        }
    }
}
```

- [ ] **Step 4: Build the watch target**

Run: `xcodegen generate && xcodebuild build -scheme MurphPlusWatch -destination 'generic/platform=watchOS' -project MurphPlus.xcodeproj`

Expected: `** BUILD SUCCEEDED **`

**Most likely failure:** `MurphFont.swift` does `import UIKit` and uses
`UIFont`/`UIFontDescriptor`. Both exist on watchOS, so this should compile — but
if it does not, wrap the UIKit-dependent variable-font path in
`#if canImport(UIKit)` with a `Font.custom(_:size:)` fallback for the other
branch. Do **not** fork the file into a watch copy; one definition, one
behavior.

- [ ] **Step 5: Confirm the iOS target still builds and tests pass**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add project.yml MurphPlusWatch
git commit -m "feat: add watchOS target sharing MurphCore and design foundations"
```

---

### Task 5: HealthKit workout controller

**Files:**
- Create: `MurphPlusWatch/Session/WorkoutSessionController.swift`

**Interfaces:**
- Produces, consumed by Task 6:
  - `WorkoutSessionController()` — `@Observable`
  - `requestAuthorization() async`
  - `start(indoor: Bool) async` / `pause()` / `resume()` / `finish() async`
  - `beginRunActivity()` / `beginRoundsActivity()`
  - `currentHeartRate: Int?`, `currentRunDistanceMeters: Double?`
  - `var onHeartRate: ((Int) -> Void)?` — fires at most once per 5 seconds

- [ ] **Step 1: Write the controller**

Create `MurphPlusWatch/Session/WorkoutSessionController.swift`:

```swift
// MurphPlusWatch/Session/WorkoutSessionController.swift
import Foundation
import HealthKit
import Observation

/// Wraps `HKWorkoutSession` and `HKLiveWorkoutBuilder`.
///
/// One workout session typed `.crossTraining` spans the whole Murph, so it
/// appears in Fitness as a single workout rather than three. Inside it,
/// activity segmentation marks the runs `.running` and the rounds
/// `.functionalStrengthTraining`.
///
/// That segmentation is load-bearing for calorie accuracy: with
/// `.functionalStrengthTraining`, active energy is estimated primarily from
/// heart-rate elevation, which is the correct model for calisthenics — a
/// motion-driven estimate would badly under-count pull-ups, since the user
/// burns energy while going nowhere.
///
/// Every capability here is optional to the app functioning. If authorization
/// is denied, the session still runs to completion with no heart rate and no
/// distance; nothing in this type may block the workout.
@Observable
final class WorkoutSessionController: NSObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private(set) var currentHeartRate: Int?
    private(set) var currentRunDistanceMeters: Double?
    private(set) var isAuthorized = false

    /// Fires at most once per 5 seconds; the caller journals each one.
    var onHeartRate: ((Int) -> Void)?
    private var lastHeartRateEmit: Date?
    private static let heartRateThrottle: TimeInterval = 5

    /// Distance accumulated before the current run began, so a run's distance
    /// is its own and not the workout's total.
    private var distanceAtRunStart: Double = 0
    private var isInRunActivity = false

    private let heartRateType = HKQuantityType(.heartRate)
    private let distanceType = HKQuantityType(.distanceWalkingRunning)

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKQuantityType.workoutType()]
        let read: Set<HKObjectType> = [heartRateType, distanceType]
        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
            isAuthorized = true
        } catch {
            // A denial is a normal outcome, not a failure state. The session
            // proceeds without heart rate or distance.
            isAuthorized = false
        }
    }

    func start(indoor: Bool) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .crossTraining
        configuration.locationType = indoor ? .indoor : .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore, workoutConfiguration: configuration
            )
            builder.delegate = self

            self.session = session
            self.builder = builder

            session.startActivity(with: .now)
            try await builder.beginCollection(at: .now)
        } catch {
            // Leave `session`/`builder` nil: every later call is a no-op and the
            // workout continues without HealthKit.
            self.session = nil
            self.builder = nil
        }
    }

    func beginRunActivity() {
        distanceAtRunStart = currentTotalDistance()
        isInRunActivity = true
        currentRunDistanceMeters = 0
        beginActivity(.running)
    }

    func beginRoundsActivity() {
        isInRunActivity = false
        currentRunDistanceMeters = nil
        beginActivity(.functionalStrengthTraining)
    }

    private func beginActivity(_ type: HKWorkoutActivityType) {
        guard let builder else { return }
        builder.endCurrentActivity(at: .now)
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = type
        builder.beginNewActivity(configuration: configuration, date: .now, metadata: nil)
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    func finish() async {
        guard let session, let builder else { return }
        session.end()
        try? await builder.endCollection(at: .now)
        _ = try? await builder.finishWorkout()
        self.session = nil
        self.builder = nil
    }

    private func currentTotalDistance() -> Double {
        builder?.statistics(for: distanceType)?
            .sumQuantity()?
            .doubleValue(for: .meter()) ?? 0
    }
}

extension WorkoutSessionController: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }

            if quantityType == heartRateType {
                guard let bpm = workoutBuilder.statistics(for: quantityType)?
                    .mostRecentQuantity()?
                    .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                else { continue }

                let rounded = Int(bpm.rounded())
                currentHeartRate = rounded

                // Live display updates every sample; the journal gets one every
                // 5 seconds, which is ~700 events across a long Murph.
                let now = Date.now
                if lastHeartRateEmit.map({ now.timeIntervalSince($0) >= Self.heartRateThrottle }) ?? true {
                    lastHeartRateEmit = now
                    onHeartRate?(rounded)
                }
            }

            if quantityType == distanceType, isInRunActivity {
                // Distance accumulated during the rounds is discarded rather
                // than added to a run — pacing between pull-up sets must not
                // inflate the mile.
                currentRunDistanceMeters = max(0, currentTotalDistance() - distanceAtRunStart)
            }
        }
    }
}
```

> **Task 1's spike question 3 decides one line here.** If cumulative
> `.distanceWalkingRunning` keeps counting through the strength segment, the
> `distanceAtRunStart` subtraction above is exactly right. If it does not
> accumulate outside `.running`, the subtraction is harmless but redundant.
> Either way the code is correct — but confirm before assuming.

- [ ] **Step 2: Build the watch target**

Run: `xcodegen generate && xcodebuild build -scheme MurphPlusWatch -destination 'generic/platform=watchOS' -project MurphPlus.xcodeproj`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add MurphPlusWatch/Session/WorkoutSessionController.swift
git commit -m "feat: add HKWorkoutSession controller with activity segmentation"
```

---

### Task 6: Watch session controller

Binds the journal, the state machine and HealthKit into the one object the UI
observes.

**Files:**
- Create: `MurphPlusWatch/Session/WatchSessionController.swift`

**Interfaces:**
- Consumes: `SessionJournal`, `SessionStateMachine`, `SessionDerivation`, `WorkoutSessionController`.
- Produces, consumed by Tasks 7–9:
  - `WatchSessionController()` — `@Observable`
  - `var state: SessionState`, `var elapsed: TimeInterval`, `var heartRate: Int?`, `var runDistanceMeters: Double?`
  - `func startSession(template:vestOn:vestWeightLbs:indoor:) async`
  - `func advance()` — the slot-2 primary action for the current phase
  - `func pause()`, `func resume()`, `func undoLastRound()`, `func abandon()`
  - `var canUndo: Bool`, `var isPaused: Bool`, `var isFinished: Bool`
  - `func resumeExistingSession() throws -> Bool`

- [ ] **Step 1: Write the controller**

Create `MurphPlusWatch/Session/WatchSessionController.swift`:

```swift
// MurphPlusWatch/Session/WatchSessionController.swift
import Foundation
import Observation

/// The Watch's session owner: journal in, state machine deciding, HealthKit
/// alongside. Every mutation follows the same three beats — ask the state
/// machine for an event, append it to the journal, mirror the HealthKit side.
@Observable
final class WatchSessionController {
    private(set) var state = SessionState()
    private(set) var journal: SessionJournal?
    private let workout = WorkoutSessionController()

    private static var journalDirectory: URL {
        URL.documentsDirectory.appendingPathComponent("sessions", isDirectory: true)
    }

    var heartRate: Int? { workout.currentHeartRate }
    var runDistanceMeters: Double? { workout.currentRunDistanceMeters }
    var isPaused: Bool { state.isPaused }
    var isFinished: Bool { state.isTerminal }
    var canUndo: Bool { state.undoableRoundNumber != nil }

    var elapsed: TimeInterval { SessionDerivation.elapsed(state, now: .now) }

    // MARK: - Lifecycle

    func requestAuthorization() async {
        await workout.requestAuthorization()
    }

    /// Returns true if an unfinished journal was found and restored.
    func resumeExistingSession() throws -> Bool {
        guard let found = try SessionJournal.resumable(in: Self.journalDirectory) else {
            return false
        }
        journal = found
        state = found.state
        return true
    }

    func startSession(template: TemplateSpec, vestOn: Bool, vestWeightLbs: Int?, indoor: Bool) async {
        let journal = try? SessionJournal(sessionID: UUID(), directory: Self.journalDirectory)
        self.journal = journal

        await workout.start(indoor: indoor)
        workout.onHeartRate = { [weak self] bpm in
            self?.record(.heartRate(bpm: bpm, at: .now))
        }

        perform(SessionStateMachine.start(
            state, template: template, vestOn: vestOn,
            vestWeightLbs: vestWeightLbs, indoor: indoor, now: .now
        ))
        workout.beginRunActivity()
    }

    // MARK: - Transitions

    /// The slot-2 primary action: end the current run, or log a round.
    func advance() {
        switch state.phase {
        case .run1, .run2:
            let distance = workout.currentRunDistanceMeters
            let wasRun1 = state.phase == .run1
            perform(SessionStateMachine.finishRun(state, at: .now, distanceMeters: distance))
            if state.phase == .completed {
                Task { await workout.finish() }
            } else if wasRun1 {
                workout.beginRoundsActivity()
            }
        case .rounds:
            let before = state.phase
            perform(SessionStateMachine.completeRound(state, at: .now))
            // The round that reaches the template total begins run 2.
            if before == .rounds, state.phase == .run2 {
                workout.beginRunActivity()
            }
        case .notStarted, .completed:
            break
        }
    }

    func pause() {
        perform(SessionStateMachine.pause(state, at: .now))
        workout.pause()
    }

    func resume() {
        perform(SessionStateMachine.resume(state, at: .now))
        workout.resume()
    }

    func undoLastRound() {
        let wasRun2 = state.phase == .run2
        perform(SessionStateMachine.undoLastRound(state, at: .now))
        // Undoing the round that advanced into run 2 puts us back in the rounds.
        if wasRun2, state.phase == .rounds {
            workout.beginRoundsActivity()
        }
    }

    func abandon() {
        perform(SessionStateMachine.abandon(state, at: .now))
        Task { await workout.finish() }
    }

    // MARK: - Applying

    private func perform(_ result: Result<SessionEvent, SessionTransitionError>) {
        guard case let .success(event) = result else { return }
        record(event)
    }

    private func record(_ event: SessionEvent) {
        try? journal?.append(event)
        state.apply(event)
    }
}
```

- [ ] **Step 2: Build the watch target**

Run: `xcodegen generate && xcodebuild build -scheme MurphPlusWatch -destination 'generic/platform=watchOS' -project MurphPlus.xcodeproj`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add MurphPlusWatch/Session/WatchSessionController.swift
git commit -m "feat: add watch session controller binding journal, rules and HealthKit"
```

---

### Task 7: Setup screen

Templates come from the phone in Stage 3. Until then the Watch uses the same
starter set the phone seeds, so the screen is fully exercisable now.

**Files:**
- Create: `MurphPlusWatch/Views/WatchSetupView.swift`
- Modify: `MurphPlusWatch/MurphPlusWatchApp.swift`

**Interfaces:**
- Consumes: `WatchSessionController`, `TemplateSpec`.
- Produces: `WatchSetupView(controller:)`; navigates to `WatchLiveView` from Task 8.

- [ ] **Step 1: Write the setup screen**

Create `MurphPlusWatch/Views/WatchSetupView.swift`:

```swift
// MurphPlusWatch/Views/WatchSetupView.swift
import SwiftUI

/// Template list, then two segmented controls, then Start.
///
/// Vest and location are **segmented controls, not toggles**, and both states
/// are always visible. Vest is load-bearing data rather than a preference — the
/// prediction refuses to mix vest and non-vest sessions, so a wrong flag
/// silently disqualifies the session as source data. A lone toggle reads as a
/// settled state; showing the road not taken makes it read as a live choice.
struct WatchSetupView: View {
    @Bindable var controller: WatchSessionController

    @State private var templates: [TemplateSpec] = WatchSetupView.starterTemplates
    @State private var selected: TemplateSpec?
    @AppStorage("watchVestOn") private var vestOn = false
    @AppStorage("watchVestWeight") private var vestWeight = 20
    @AppStorage("watchIndoor") private var indoor = false
    @State private var showLive = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MurphSpacing.space3) {
                    ForEach(templates, id: \.id) { template in
                        templateRow(template)
                    }

                    segmented(
                        left: "Vest", right: "No vest",
                        leftSelected: vestOn,
                        onLeft: { vestOn = true }, onRight: { vestOn = false }
                    )

                    if vestOn {
                        weightChip
                    }

                    segmented(
                        left: "Outdoor", right: "Indoor",
                        leftSelected: !indoor,
                        onLeft: { indoor = false }, onRight: { indoor = true }
                    )

                    Button("Start") {
                        guard let spec = selected ?? templates.first else { return }
                        Task {
                            await controller.startSession(
                                template: spec, vestOn: vestOn,
                                vestWeightLbs: vestOn ? vestWeight : nil, indoor: indoor
                            )
                            showLive = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MurphColor.hazard500)
                }
                .padding(.horizontal, MurphSpacing.space2)
            }
            .background(MurphColor.surfacePage)
            .navigationTitle("Murph+")
            .navigationDestination(isPresented: $showLive) {
                WatchLiveView(controller: controller)
            }
        }
        .task {
            await controller.requestAuthorization()
            if (try? controller.resumeExistingSession()) == true {
                showLive = true
            }
        }
    }

    private func templateRow(_ template: TemplateSpec) -> some View {
        let isSelected = (selected ?? templates.first)?.id == template.id
        return Button {
            selected = template
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .murphType(.bodySm)
                    .foregroundStyle(MurphColor.textPrimary)
                Text(template.rounds == 1
                     ? "Straight sets"
                     : "\(template.rounds) rounds · \(template.pullUpsPerRound)/\(template.pushUpsPerRound)/\(template.squatsPerRound)")
                    .murphType(.micro)
                    .foregroundStyle(MurphColor.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MurphSpacing.space2)
            .background(isSelected ? MurphColor.hazard500.opacity(0.18) : MurphColor.surfaceRaised)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? MurphColor.hazard500 : MurphColor.lineHairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func segmented(
        left: String, right: String, leftSelected: Bool,
        onLeft: @escaping () -> Void, onRight: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 0) {
            segmentButton(left, selected: leftSelected, action: onLeft)
            segmentButton(right, selected: !leftSelected, action: onRight)
        }
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(MurphColor.lineStrong))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    private func segmentButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .murphType(.micro)
                .foregroundStyle(selected ? MurphColor.textOnAccent : MurphColor.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, MurphSpacing.space2)
                .background(selected ? MurphColor.hazard500 : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var weightChip: some View {
        HStack {
            Text("\(vestWeight) lb")
                .murphType(.metric(15))
                .foregroundStyle(MurphColor.textPrimary)
            Spacer()
            Text("crown")
                .murphType(.micro)
                .foregroundStyle(MurphColor.textMuted)
        }
        .padding(MurphSpacing.space2)
        .background(MurphColor.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .focusable()
        .digitalCrownRotation(
            .init(get: { Double(vestWeight) }, set: { vestWeight = Int($0) }),
            from: 5, through: 60, by: 5, sensitivity: .low
        )
    }

    /// Mirrors `DefaultTemplates` on the phone. Replaced by the synced list in
    /// Stage 3; kept here so this screen is fully exercisable before sync exists.
    static let starterTemplates: [TemplateSpec] = [
        TemplateSpec(id: UUID(), name: "Full Murph (Straight Sets)", runDistanceMiles: 1.0,
                     totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 1),
        TemplateSpec(id: UUID(), name: "Full Murph (Cindy-Style, 20 Rounds)", runDistanceMiles: 1.0,
                     totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 20),
        TemplateSpec(id: UUID(), name: "Half Murph", runDistanceMiles: 0.5,
                     totalPullUps: 50, totalPushUps: 100, totalSquats: 150, rounds: 10),
        TemplateSpec(id: UUID(), name: "Mini Murph", runDistanceMiles: 0.25,
                     totalPullUps: 25, totalPushUps: 50, totalSquats: 75, rounds: 5),
    ]
}
```

- [ ] **Step 2: Point the app entry at it**

Replace the body of `MurphPlusWatchApp.swift`:

```swift
// MurphPlusWatch/MurphPlusWatchApp.swift
import SwiftUI

@main
struct MurphPlusWatchApp: App {
    @State private var controller = WatchSessionController()

    var body: some Scene {
        WindowGroup {
            WatchSetupView(controller: controller)
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodegen generate && xcodebuild build -scheme MurphPlusWatch -destination 'generic/platform=watchOS' -project MurphPlus.xcodeproj`

Expected: `** BUILD SUCCEEDED **`. It will fail until Task 8 provides
`WatchLiveView` — implement Tasks 7 and 8 together, or stub `WatchLiveView` as
an empty `Text` and replace it in Task 8.

- [ ] **Step 4: Commit**

```bash
git add MurphPlusWatch/Views/WatchSetupView.swift MurphPlusWatch/MurphPlusWatchApp.swift
git commit -m "feat: add watch setup screen with vest and location segmented controls"
```

---

### Task 8: The four-page live session

**Files:**
- Create: `MurphPlusWatch/Views/WatchLiveView.swift`
- Create: `MurphPlusWatch/Views/Pages/ControlsPage.swift`, `PrimaryPage.swift`, `ClockPage.swift`, `NowPlayingPage.swift`
- Create: `MurphPlusWatch/Components/WatchStatusStrip.swift`, `WatchPrimaryButton.swift`

**Interfaces:**
- Consumes: `WatchSessionController`.
- Produces: `WatchLiveView(controller:)`, navigating to `WatchCompleteView` from Task 9.

- [ ] **Step 1: Write the shared components**

Create `MurphPlusWatch/Components/WatchStatusStrip.swift`:

```swift
// MurphPlusWatch/Components/WatchStatusStrip.swift
import SwiftUI

/// The two-cell banded row at the top of every page. Each page's strip carries
/// the metrics its hero does not, so no number is ever shown twice on one page.
struct WatchStatusStrip: View {
    struct Cell {
        let label: String
        let value: String
        var tone: Color = MurphColor.textPrimary
    }

    let leading: Cell
    let trailing: Cell

    var body: some View {
        HStack(spacing: 0) {
            cell(leading)
            Rectangle().fill(MurphColor.lineHairline).frame(width: 1)
            cell(trailing)
        }
        .background(MurphColor.surfaceRaised)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MurphColor.lineHairline).frame(height: 1)
        }
    }

    private func cell(_ cell: Cell) -> some View {
        VStack(spacing: 2) {
            Text(cell.label)
                .murphType(.micro)
                .foregroundStyle(MurphColor.textMuted)
            Text(cell.value)
                .murphType(.metric(16))
                .foregroundStyle(cell.tone)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MurphSpacing.space2)
    }
}
```

Create `MurphPlusWatch/Components/WatchPrimaryButton.swift`:

```swift
// MurphPlusWatch/Components/WatchPrimaryButton.swift
import SwiftUI

/// The advancing action. Appears on **both** metric pages, so logging a round
/// never requires swiping first — paging changes what you read, never what you
/// can do.
struct WatchPrimaryButton: View {
    let title: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .murphType(.tag)
                .foregroundStyle(MurphColor.textOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, MurphSpacing.space3)
                .background(disabled ? MurphColor.ash400 : MurphColor.hazard500)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
```

- [ ] **Step 2: Write the four pages**

Create `MurphPlusWatch/Views/Pages/PrimaryPage.swift`:

```swift
// MurphPlusWatch/Views/Pages/PrimaryPage.swift
import SwiftUI

/// Slot 2 — the only slot whose content changes with phase. It always holds
/// "the number that matters right now, plus the button that advances".
/// Distance during runs, round count during rounds, Resume while paused.
struct PrimaryPage: View {
    @Bindable var controller: WatchSessionController
    let elapsedText: String

    var body: some View {
        VStack(spacing: 0) {
            WatchStatusStrip(
                leading: .init(label: "Elapsed", value: elapsedText, tone: MurphColor.hazard500),
                trailing: .init(label: "BPM",
                                value: controller.heartRate.map(String.init) ?? "—",
                                tone: MurphColor.lime500)
            )

            Spacer(minLength: 0)
            hero
            Spacer(minLength: 0)

            if controller.isPaused {
                WatchPrimaryButton(title: "Resume") { controller.resume() }
                    .padding(.horizontal, MurphSpacing.space2)
            } else {
                WatchPrimaryButton(title: advanceTitle) { controller.advance() }
                    .padding(.horizontal, MurphSpacing.space2)
            }
        }
        .background(MurphColor.surfacePage)
    }

    @ViewBuilder
    private var hero: some View {
        switch controller.state.phase {
        case .run1, .run2:
            VStack(spacing: 4) {
                Text(controller.state.phase == .run1 ? "Run 1 · Distance" : "Run 2 · Distance")
                    .murphType(.micro)
                    .foregroundStyle(MurphColor.textMuted)
                Text(distanceText)
                    .murphType(.clock(38))
                    .foregroundStyle(MurphColor.textPrimary)
                Text(remainingText)
                    .murphType(.micro)
                    .foregroundStyle(MurphColor.textSecondary)
            }
        case .rounds:
            VStack(spacing: 4) {
                Text("Round")
                    .murphType(.micro)
                    .foregroundStyle(MurphColor.textMuted)
                Text("\(controller.state.completedRounds) / \(controller.state.template?.rounds ?? 0)")
                    .murphType(.clock(38))
                    .foregroundStyle(MurphColor.textPrimary)
                if let spec = controller.state.template {
                    Text("\(spec.pullUpsPerRound) pull · \(spec.pushUpsPerRound) push · \(spec.squatsPerRound) sqt")
                        .murphType(.micro)
                        .foregroundStyle(MurphColor.textSecondary)
                }
            }
        case .notStarted, .completed:
            EmptyView()
        }
    }

    private var advanceTitle: String {
        switch controller.state.phase {
        case .run1, .run2: "End Run"
        case .rounds: "Round Done"
        case .notStarted, .completed: ""
        }
    }

    private var distanceText: String {
        guard let meters = controller.runDistanceMeters else { return "—" }
        return String(format: "%.2f", meters / 1609.34)
    }

    private var remainingText: String {
        guard
            let meters = controller.runDistanceMeters,
            let target = controller.state.template?.runDistanceMiles
        else { return "miles" }
        // Displayed, never acted on: GPS drift ending a run at 0.97 mi while
        // the user is still running is worse than a button.
        let remaining = max(0, target - meters / 1609.34)
        return String(format: "%.2f to go", remaining)
    }
}
```

Create `MurphPlusWatch/Views/Pages/ClockPage.swift`:

```swift
// MurphPlusWatch/Views/Pages/ClockPage.swift
import SwiftUI

/// Slot 3 — same content, roles swapped: elapsed time is the hero and the
/// round count moves into the strip. Carries the advancing button too.
struct ClockPage: View {
    @Bindable var controller: WatchSessionController
    let elapsedText: String

    var body: some View {
        VStack(spacing: 0) {
            WatchStatusStrip(
                leading: .init(label: "Round",
                               value: "\(controller.state.completedRounds)/\(controller.state.template?.rounds ?? 0)"),
                trailing: .init(label: "BPM",
                                value: controller.heartRate.map(String.init) ?? "—",
                                tone: MurphColor.lime500)
            )

            Spacer(minLength: 0)
            VStack(spacing: 4) {
                Text(controller.isPaused ? "Paused" : "Elapsed")
                    .murphType(.micro)
                    .foregroundStyle(controller.isPaused ? MurphColor.dust500 : MurphColor.textMuted)
                Text(elapsedText)
                    .murphType(.clock(36))
                    .foregroundStyle(MurphColor.textPrimary)
            }
            Spacer(minLength: 0)

            if controller.isPaused {
                WatchPrimaryButton(title: "Resume") { controller.resume() }
                    .padding(.horizontal, MurphSpacing.space2)
            } else {
                WatchPrimaryButton(title: controller.state.phase == .rounds ? "Round Done" : "End Run") {
                    controller.advance()
                }
                .padding(.horizontal, MurphSpacing.space2)
            }
        }
        .background(MurphColor.surfacePage)
    }
}
```

Create `MurphPlusWatch/Views/Pages/ControlsPage.swift`:

```swift
// MurphPlusWatch/Views/Pages/ControlsPage.swift
import SwiftUI

/// Slot 1 — pause/resume, undo, abandon. Destructive and corrective actions
/// live here rather than beside the button tapped twenty times while exhausted.
///
/// Undo is **disabled rather than absent** when unavailable, so the page does
/// not reshuffle mid-workout.
struct ControlsPage: View {
    @Bindable var controller: WatchSessionController
    let elapsedText: String
    @Binding var showAbandonConfirm: Bool

    var body: some View {
        VStack(spacing: 0) {
            WatchStatusStrip(
                leading: .init(label: "Elapsed", value: elapsedText, tone: MurphColor.hazard500),
                trailing: .init(label: "Round",
                                value: "\(controller.state.completedRounds)/\(controller.state.template?.rounds ?? 0)")
            )

            Spacer(minLength: 0)

            VStack(spacing: MurphSpacing.space2) {
                Button(controller.isPaused ? "Resume" : "Pause") {
                    controller.isPaused ? controller.resume() : controller.pause()
                }
                .buttonStyle(.bordered)
                .tint(MurphColor.lime500)

                Button("Undo last round") { controller.undoLastRound() }
                    .buttonStyle(.bordered)
                    .disabled(!controller.canUndo)

                Button("Abandon", role: .destructive) { showAbandonConfirm = true }
                    .buttonStyle(.bordered)
            }
            .murphType(.micro)
            .padding(.horizontal, MurphSpacing.space2)
            .padding(.bottom, MurphSpacing.space2)
        }
        .background(MurphColor.surfacePage)
    }
}
```

Create `MurphPlusWatch/Views/Pages/NowPlayingPage.swift`:

```swift
// MurphPlusWatch/Views/Pages/NowPlayingPage.swift
import SwiftUI
import WatchKit

/// Slot 4 — the system's own Now Playing view, essentially free to include.
struct NowPlayingPage: View {
    var body: some View {
        NowPlayingView()
    }
}
```

- [ ] **Step 3: Write the pager**

Create `MurphPlusWatch/Views/WatchLiveView.swift`:

```swift
// MurphPlusWatch/Views/WatchLiveView.swift
import SwiftUI

/// Four fixed slots, **hard stops at both ends** — a plain paged `TabView` with
/// the system indicator. No wrap-around: `TabView` does not support it, faking
/// it needs clone pages and programmatic selection snapping, and the built-in
/// Workout app does not wrap either.
///
/// `selection` is deliberately never reset when the phase changes: finish run 1
/// while reading the clock page and you stay on the clock page. The workout
/// changed underneath you; your position did not.
struct WatchLiveView: View {
    @Bindable var controller: WatchSessionController

    @State private var selection = 1          // Count page is the landing page
    @State private var showAbandonConfirm = false
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 60 : 1)) { _ in
            TabView(selection: $selection) {
                ControlsPage(
                    controller: controller,
                    elapsedText: elapsedText,
                    showAbandonConfirm: $showAbandonConfirm
                )
                .tag(0)

                PrimaryPage(controller: controller, elapsedText: elapsedText)
                    .tag(1)

                ClockPage(controller: controller, elapsedText: elapsedText)
                    .tag(2)

                NowPlayingPage()
                    .tag(3)
            }
            .tabViewStyle(.verticalPage)
        }
        .navigationBarBackButtonHidden(true)
        .confirmationDialog(
            "Abandon this session?",
            isPresented: $showAbandonConfirm,
            titleVisibility: .visible
        ) {
            Button("Abandon", role: .destructive) { controller.abandon() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Your progress so far is kept.")
        }
        .navigationDestination(isPresented: .constant(controller.isFinished)) {
            WatchCompleteView(controller: controller)
        }
    }

    /// In the dimmed always-on state the clock renders at minute resolution,
    /// matching the once-a-minute update budget the system expects.
    private var elapsedText: String {
        let total = Int(controller.elapsed)
        if isLuminanceReduced {
            return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
```

> `.verticalPage` is the watchOS-native paging style and pairs with the Digital
> Crown. If the spike found horizontal paging reads better on-wrist, swap to
> `.page` — the slot structure is unchanged either way.

- [ ] **Step 4: Build**

Run: `xcodegen generate && xcodebuild build -scheme MurphPlusWatch -destination 'generic/platform=watchOS' -project MurphPlus.xcodeproj`

Expected: `** BUILD SUCCEEDED **` (after Task 9 provides `WatchCompleteView`).

- [ ] **Step 5: Commit**

```bash
git add MurphPlusWatch/Views MurphPlusWatch/Components
git commit -m "feat: add four-page watch live session

Controls, Count (default), Clock, Now Playing — hard stops at both
ends. Round Done sits on both metric pages so logging never requires
swiping first, and page position survives a phase change."
```

---

### Task 9: Completion screen

**Files:**
- Create: `MurphPlusWatch/Views/WatchCompleteView.swift`

**Interfaces:**
- Consumes: `WatchSessionController`, `SessionDerivation`, `HeartRateAggregator`.
- Produces: `WatchCompleteView(controller:)`.

- [ ] **Step 1: Write the screen**

Create `MurphPlusWatch/Views/WatchCompleteView.swift`:

```swift
// MurphPlusWatch/Views/WatchCompleteView.swift
import SwiftUI

/// Total, average heart rate, and the three splits at a glance.
///
/// The PB badge is deliberately absent until Stage 3: the Watch holds no
/// history to compare against, and a badge that cannot be trusted is worse
/// than no badge.
struct WatchCompleteView: View {
    @Bindable var controller: WatchSessionController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: MurphSpacing.space3) {
                Text(controller.state.status == .abandoned ? "Stopped" : "Complete")
                    .murphType(.micro)
                    .foregroundStyle(controller.state.status == .abandoned
                                     ? MurphColor.dust500 : MurphColor.lime500)

                Text(totalText)
                    .murphType(.clock(34))
                    .foregroundStyle(MurphColor.textPrimary)

                if let average = averageHeartRate {
                    Text("Avg \(average) bpm")
                        .murphType(.micro)
                        .foregroundStyle(MurphColor.textSecondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(controller.state.runSplits, id: \.index) { split in
                        row("Run \(split.index)", formatted(split.durationSeconds))
                    }
                    row("Rounds", "\(controller.state.completedRounds) of \(controller.state.template?.rounds ?? 0)")
                }

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(MurphColor.lime500)
            }
            .padding(.horizontal, MurphSpacing.space2)
        }
        .background(MurphColor.surfacePage)
        .navigationBarBackButtonHidden(true)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).murphType(.micro).foregroundStyle(MurphColor.textMuted)
            Spacer()
            Text(value).murphType(.metric(14)).foregroundStyle(MurphColor.textPrimary)
        }
    }

    private var totalText: String {
        formatted(SessionDerivation.elapsed(controller.state, now: .now))
    }

    private var averageHeartRate: Int? {
        guard
            let events = controller.journal?.events,
            let start = controller.state.startedAt,
            let end = controller.state.completedAt
        else { return nil }
        return HeartRateAggregator.summary(events: events, from: start, to: end)?.average
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
```

- [ ] **Step 2: Build both targets and run the iOS suite**

Run: `xcodegen generate && xcodebuild build -scheme MurphPlusWatch -destination 'generic/platform=watchOS' -project MurphPlus.xcodeproj && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`

Expected: `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **`

- [ ] **Step 3: Verify on real hardware**

The simulator cannot answer any of this. On a paired Apple Watch:

1. Launch, grant HealthKit and location. Pick the 20-round template, Vest, Outdoor, Start.
2. Confirm you land on the **Count** page, and that swiping reaches Controls one way and Clock then Now Playing the other, with **hard stops** at both ends.
3. Confirm **Round Done appears on both** Count and Clock.
4. End run 1. Confirm the primary page switches to round count and that **your page position did not change**.
5. Log three rounds. Undo one from Controls — confirm the count decrements and Undo then greys out.
6. Pause from Controls. Confirm the clock stops and the primary action becomes Resume on both metric pages.
7. Drop your wrist and confirm the always-on dimmed state renders legibly at minute resolution.
8. Abandon. Confirm the summary shows "Stopped" with the rounds reached.
9. Force-quit mid-rounds on a fresh session, relaunch, and confirm the resume prompt restores the exact round count and elapsed time.
10. Check the Fitness app: **one** cross-training workout, with rings credited.

- [ ] **Step 4: Commit**

```bash
git add MurphPlusWatch/Views/WatchCompleteView.swift
git commit -m "feat: add watch completion summary"
```

---

## Self-Review

**Spec coverage for this stage:**

| Spec section | Task |
|---|---|
| watchOS target, `WKApplication`, embedding, watchOS 10 | Task 4 |
| Design foundations shared, components not | Task 4 |
| Journal: append-only, one JSON per line, flushed | Task 2 |
| Journal: replay recovery, resume-or-abandon | Tasks 2, 7 |
| HR journaled at 5s throttle | Task 5 |
| HR summaries derived by bucketing | Task 3 |
| Distance only during run activities | Task 5 |
| One `HKWorkoutSession`, three activities | Task 5 |
| Calorie rationale via `.functionalStrengthTraining` | Task 5 |
| Permissions all optional | Tasks 5, 6 |
| Always-on dimmed rendering | Task 8 |
| Setup: two segmented controls + weight chip | Task 7 |
| Four pages, hard stops, Count default | Task 8 |
| Round Done on both metric pages | Tasks 8 (component doc + both pages) |
| Page position survives phase change | Task 8 |
| Undo disabled not absent | Task 8 |
| Pause → slot 2 becomes Resume | Task 8 |
| Completion summary | Task 9 |
| Spike first | Task 1 |

Deferred to Stage 3, by design: `WatchConnectivity`, template sync (Task 7 uses
a local starter list), the phone mirror, checkpoint transfer, the PB badge on
the completion screen, and the phone's session-detail HR and distance columns.

**Placeholder scan:** No TBD/TODO. Task 1 is intentionally an investigation
with no committed code — its deliverable is five written answers, and it names
exactly which later line each answer affects. Task 5 Step 1 flags the one
assumption the spike can invalidate.

**Type consistency:** `SessionJournal.resumable(in:)`, `.all(in:)`, `.append(_:)`,
`.events`, `.state`, `.sessionID` are declared in Task 2 and used in Tasks 6 and 9.
`HeartRateAggregator.summary(events:from:to:)` is declared in Task 3 and used in
Task 9. `WorkoutSessionController.beginRunActivity()`, `.beginRoundsActivity()`,
`.onHeartRate`, `.currentRunDistanceMeters`, `.currentHeartRate` are declared in
Task 5 and used in Task 6. `WatchSessionController.advance()`, `.canUndo`,
`.isPaused`, `.isFinished`, `.elapsed`, `.state`, `.journal` are declared in
Task 6 and used in Tasks 7–9. `TemplateSpec`, `SessionState`, `SessionDerivation`,
`SessionStateMachine` all come from Stage 1 with matching signatures.
