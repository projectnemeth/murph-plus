# Murph Plus v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the v1 Murph Plus iOS app: live in-workout tracker, history/calendar log, and fatigue-adjusted finish-time prediction.

**Architecture:** Native SwiftUI + SwiftData (with CloudKit sync), MVVM. A pure-Swift prediction/state-machine core (no SwiftData or UI dependencies) is unit tested; SwiftUI views consume that core and are verified by build + manual simulator walkthrough, per the spec's own testing approach.

**Tech Stack:** Swift, SwiftUI, SwiftData, XCTest. Project scaffolded and kept in sync via [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml` → generates `MurphPlus.xcodeproj`) so setup is scriptable instead of requiring manual Xcode project creation.

**Spec:** `docs/superpowers/specs/2026-08-30-murph-plus-design.md`

## Global Constraints

- iOS 17.0 minimum (required by SwiftData).
- Native Swift/SwiftUI only — no third-party runtime dependencies. XcodeGen is a local build tool only, not a runtime dependency.
- Persistence is SwiftData + its built-in CloudKit integration, syncing only across the same user's own devices. No shared backend, no cross-user data in v1.
- Round entry is a single "round done" tap per round — never per-exercise (pull-up/push-up/squat) counters.
- Run tracking is a plain start/stop timer in v1 — no GPS/Core Location/MapKit.
- Vest on/off status is never mixed in a prediction, even as a soft caveat — a prediction with no matching-vest source data is simply not offered.
- Logged sessions can be deleted (confirm-guarded) but never edited — the log stays a trustworthy record.
- Calendar view is read-only navigation into existing sessions — tapping an empty day does nothing; there is no v1 flow to log a session retroactively.

---

## File Structure

```
murph-plus/
  project.yml
  .gitignore
  README.md
  MurphPlus/
    MurphPlusApp.swift
    Models/
      SessionEnums.swift
      WorkoutTemplate.swift
      MurphSession.swift
      RunSplit.swift
      RoundLog.swift
    Persistence/
      DefaultTemplates.swift
      ResumableSessionFinder.swift
    Support/
      DurationFormatting.swift
    Prediction/
      FatiguePrediction.swift
      RoundThroughputBuilder.swift
      HistoryStats.swift
      CalendarMonthBuilder.swift
    Session/
      SessionEngine.swift
    Views/
      RootTabView.swift
      Start/
        StartView.swift
        TemplateEditorView.swift
      Session/
        LiveSessionView.swift
        ResumeSessionPrompt.swift
      History/
        HistoryView.swift
        HistoryListView.swift
        SessionDetailView.swift
        PredictionControlView.swift
        CalendarView.swift
  MurphPlusTests/
    SmokeTests.swift
    ModelTests.swift
    DefaultTemplatesTests.swift
    ResumableSessionFinderTests.swift
    FatiguePredictionTests.swift
    RoundThroughputBuilderTests.swift
    SessionEngineTests.swift
    HistoryStatsTests.swift
    CalendarMonthBuilderTests.swift
```

---

### Task 1: Project Scaffolding

**Files:**
- Create: `project.yml`
- Create: `.gitignore`
- Create: `README.md`
- Create: `MurphPlus/MurphPlusApp.swift`
- Test: `MurphPlusTests/SmokeTests.swift`

**Interfaces:**
- Produces: an `xcodegen generate`-able project that builds and runs `MurphPlusTests` via `xcodebuild`. All later tasks assume this pipeline works and add files under `MurphPlus/` or `MurphPlusTests/` (picked up automatically by the folder-based `sources` glob — re-run `xcodegen generate` after adding files, no `project.yml` edits needed for new files).

- [ ] **Step 1: Confirm XcodeGen is installed**

Run: `xcodegen --version`
Expected: a version string. If the command isn't found, run: `brew install xcodegen`

CloudKit entitlements are deliberately **not** configured here — they require a
paid Apple Developer account and a provisioned iCloud container, which would
block every build in this plan from Task 1 onward. Local SwiftData persistence
works without them; CloudKit sync is switched on at the end, in Task 15.

- [ ] **Step 2: Write `project.yml`**

```yaml
name: MurphPlus
options:
  bundleIdPrefix: com.projectnemeth
  deploymentTarget:
    iOS: "17.0"
targets:
  MurphPlus:
    type: application
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - MurphPlus
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.projectnemeth.MurphPlus
        SWIFT_VERSION: "5.0"
        TARGETED_DEVICE_FAMILY: "1"
        GENERATE_INFOPLIST_FILE: true
        INFOPLIST_KEY_UILaunchScreen_Generation: true
        INFOPLIST_KEY_UISupportedInterfaceOrientations: UIInterfaceOrientationPortrait
        INFOPLIST_KEY_CFBundleDisplayName: "Murph Plus"
  MurphPlusTests:
    type: bundle.unit-test
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - MurphPlusTests
    settings:
      base:
        # Required: without it the test bundle fails to code sign with
        # "target does not have an Info.plist file and one is not being
        # generated automatically". The app target is not enough — the test
        # bundle needs its own.
        GENERATE_INFOPLIST_FILE: true
        SWIFT_VERSION: "5.0"
    dependencies:
      - target: MurphPlus
schemes:
  MurphPlus:
    build:
      targets:
        MurphPlus: all
        MurphPlusTests: [test]
    test:
      targets:
        - MurphPlusTests
    run:
      config: Debug
```

- [ ] **Step 3: Write `.gitignore`**

```
.DS_Store
DerivedData/
xcuserdata/
*.xcodeproj
.build/
```

- [ ] **Step 4: Write `README.md`**

```markdown
# Murph Plus

Native iOS Murph workout tracker. Design spec: `docs/superpowers/specs/2026-08-30-murph-plus-design.md`.

## Setup

1. Install XcodeGen: `brew install xcodegen`
2. Generate the Xcode project: `xcodegen generate`
3. Open `MurphPlus.xcodeproj` in Xcode
4. Select your Apple ID/Team under Signing & Capabilities for the MurphPlus target
5. Build and run

Re-run `xcodegen generate` whenever new source files are added, before building.
```

- [ ] **Step 5: Write the minimal app entry point**

```swift
// MurphPlus/MurphPlusApp.swift
import SwiftUI

@main
struct MurphPlusApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Murph Plus")
        }
    }
}
```

- [ ] **Step 6: Write a trivial smoke test**

```swift
// MurphPlusTests/SmokeTests.swift
import XCTest

final class SmokeTests: XCTestCase {
    func test_trivialArithmetic() {
        XCTAssertEqual(1 + 1, 2)
    }
}
```

- [ ] **Step 7: Generate the Xcode project**

Run: `xcodegen generate`
Expected: `Generated project at MurphPlus.xcodeproj`

- [ ] **Step 8: (Deferred) signing team**

No action needed now. Simulator builds and tests — everything this plan runs — do
not require a signing team. Setting one is only necessary to install on a
physical device or ship to TestFlight; it's covered in Task 15, alongside
CloudKit. Skip this step and continue.

- [ ] **Step 9: Run the test suite from the command line**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `** TEST SUCCEEDED **`. If `iPhone 17` isn't an installed simulator, run `xcrun simctl list devicetypes` and substitute an available iPhone name in the `-destination` flag (use this substitution for every `xcodebuild` command in this plan).

- [ ] **Step 10: Commit**

```bash
git add project.yml .gitignore README.md MurphPlus/MurphPlusApp.swift MurphPlusTests/SmokeTests.swift
git commit -m "chore: scaffold Murph Plus Xcode project via XcodeGen"
```

---

### Task 2: Data Models & Persistence Bootstrap

**Files:**
- Create: `MurphPlus/Models/SessionEnums.swift`
- Create: `MurphPlus/Models/WorkoutTemplate.swift`
- Create: `MurphPlus/Models/MurphSession.swift`
- Create: `MurphPlus/Models/RunSplit.swift`
- Create: `MurphPlus/Models/RoundLog.swift`
- Modify: `MurphPlus/MurphPlusApp.swift`
- Test: `MurphPlusTests/ModelTests.swift`

**Interfaces:**
- Produces:
  - `enum SessionStatus: String, Codable { case inProgress, completed, abandoned }`
  - `enum SessionPhase: String, Codable { case notStarted, run1, rounds, run2, completed }`
  - `WorkoutTemplate` (`@Model`): `name: String`, `runDistanceMiles: Double`, `totalPullUps/totalPushUps/totalSquats: Int`, `rounds: Int`, computed `totalReps`, `pullUpsPerRound`, `pushUpsPerRound`, `squatsPerRound`, `repsPerRound`.
  - `MurphSession` (`@Model`): `date: Date`, `template: WorkoutTemplate?`, `vestOn: Bool`, `vestWeightLbs: Int?`, `status: SessionStatus`, `phase: SessionPhase`, `notes: String?`, `startedAt/currentPhaseStartedAt/completedAt: Date?`, `completedRounds: Int`, `runSplits: [RunSplit]`, `roundLogs: [RoundLog]`, computed `totalElapsedSeconds: Double?`.
  - `RunSplit` (`@Model`): `runIndex: Int`, `startTime: Date`, `durationSeconds: Double`, `session: MurphSession?`.
  - `RoundLog` (`@Model`): `roundNumber: Int`, `completedAt: Date`, `session: MurphSession?`.

- [ ] **Step 1: Write the failing model tests**

```swift
// MurphPlusTests/ModelTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

final class ModelTests: XCTestCase {
    var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        context = ModelContext(container)
    }

    func test_workoutTemplate_defaultsToFullMurphNumbers() {
        let template = WorkoutTemplate(name: "Test")
        XCTAssertEqual(template.totalPullUps, 100)
        XCTAssertEqual(template.totalPushUps, 200)
        XCTAssertEqual(template.totalSquats, 300)
        XCTAssertEqual(template.totalReps, 600)
        XCTAssertEqual(template.rounds, 1)
    }

    func test_workoutTemplate_repsPerRoundDividesEvenly() {
        let template = WorkoutTemplate(name: "Cindy-Style", rounds: 20)
        XCTAssertEqual(template.pullUpsPerRound, 5)
        XCTAssertEqual(template.pushUpsPerRound, 10)
        XCTAssertEqual(template.squatsPerRound, 15)
        XCTAssertEqual(template.repsPerRound, 30)
    }

    func test_murphSession_vestOffClearsWeight() {
        let template = WorkoutTemplate(name: "Test")
        let session = MurphSession(template: template, vestOn: false, vestWeightLbs: 20)
        XCTAssertNil(session.vestWeightLbs)
    }

    func test_murphSession_vestOnDefaultsToTwentyPounds() {
        let template = WorkoutTemplate(name: "Test")
        let session = MurphSession(template: template, vestOn: true, vestWeightLbs: nil)
        XCTAssertEqual(session.vestWeightLbs, 20)
    }

    func test_murphSession_totalElapsedSecondsNilUntilCompleted() {
        let template = WorkoutTemplate(name: "Test")
        let session = MurphSession(template: template, vestOn: false)
        XCTAssertNil(session.totalElapsedSeconds)
    }

    func test_murphSession_totalElapsedSecondsComputedFromTimestamps() {
        let template = WorkoutTemplate(name: "Test")
        let session = MurphSession(template: template, vestOn: false)
        let start = Date(timeIntervalSince1970: 1000)
        session.startedAt = start
        session.completedAt = start.addingTimeInterval(2520)
        XCTAssertEqual(session.totalElapsedSeconds, 2520)
    }

    func test_runSplitAndRoundLog_persistWithSessionRelationship() throws {
        let template = WorkoutTemplate(name: "Test", rounds: 2)
        context.insert(template)
        let session = MurphSession(template: template, vestOn: false)
        context.insert(session)

        let split = RunSplit(runIndex: 1, startTime: .now, durationSeconds: 480, session: session)
        context.insert(split)
        session.runSplits.append(split)

        let round = RoundLog(roundNumber: 1, completedAt: .now, session: session)
        context.insert(round)
        session.roundLogs.append(round)

        try context.save()

        XCTAssertEqual(session.runSplits.count, 1)
        XCTAssertEqual(session.roundLogs.count, 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail (types don't exist yet)**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: build failure — `cannot find type 'WorkoutTemplate' in scope` (or similar)

- [ ] **Step 3: Write the enums**

```swift
// MurphPlus/Models/SessionEnums.swift
enum SessionStatus: String, Codable {
    case inProgress
    case completed
    case abandoned
}

enum SessionPhase: String, Codable {
    case notStarted
    case run1
    case rounds
    case run2
    case completed
}
```

- [ ] **Step 4: Write `WorkoutTemplate`**

Every stored property carries a default value. This is not stylistic: SwiftData's
CloudKit backing (added in Task 15) requires all attributes to be optional or
defaulted, and it validates the whole schema at container creation — a
non-defaulted property fails at launch, not at compile time. Building the models
this way now avoids a migration later.

```swift
// MurphPlus/Models/WorkoutTemplate.swift
import SwiftData

@Model
final class WorkoutTemplate {
    var name: String = ""
    var runDistanceMiles: Double = 1.0
    var totalPullUps: Int = 100
    var totalPushUps: Int = 200
    var totalSquats: Int = 300
    var rounds: Int = 1

    init(
        name: String,
        runDistanceMiles: Double = 1.0,
        totalPullUps: Int = 100,
        totalPushUps: Int = 200,
        totalSquats: Int = 300,
        rounds: Int = 1
    ) {
        self.name = name
        self.runDistanceMiles = runDistanceMiles
        self.totalPullUps = totalPullUps
        self.totalPushUps = totalPushUps
        self.totalSquats = totalSquats
        self.rounds = rounds
    }

    // `max(rounds, 1)` guards against integer division by zero, which would be a
    // hard crash rather than a recoverable error if a stored value ever hits 0.
    private var safeRounds: Int { max(rounds, 1) }

    var totalReps: Int { totalPullUps + totalPushUps + totalSquats }
    var pullUpsPerRound: Int { totalPullUps / safeRounds }
    var pushUpsPerRound: Int { totalPushUps / safeRounds }
    var squatsPerRound: Int { totalSquats / safeRounds }
    var repsPerRound: Int { totalReps / safeRounds }
}
```

- [ ] **Step 5: Write `MurphSession`**

```swift
// MurphPlus/Models/MurphSession.swift
import Foundation
import SwiftData

@Model
final class MurphSession {
    var date: Date = Date.distantPast
    var template: WorkoutTemplate?
    var vestOn: Bool = false
    var vestWeightLbs: Int?
    var statusRaw: String = SessionStatus.inProgress.rawValue
    var phaseRaw: String = SessionPhase.notStarted.rawValue
    var notes: String?
    var startedAt: Date?
    var currentPhaseStartedAt: Date?
    var completedAt: Date?
    var completedRounds: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \RunSplit.session)
    var runSplits: [RunSplit] = []

    @Relationship(deleteRule: .cascade, inverse: \RoundLog.session)
    var roundLogs: [RoundLog] = []

    init(
        date: Date = .now,
        template: WorkoutTemplate?,
        vestOn: Bool,
        vestWeightLbs: Int? = nil
    ) {
        self.date = date
        self.template = template
        self.vestOn = vestOn
        self.vestWeightLbs = vestOn ? (vestWeightLbs ?? 20) : nil
        self.statusRaw = SessionStatus.inProgress.rawValue
        self.phaseRaw = SessionPhase.notStarted.rawValue
        self.completedRounds = 0
    }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .inProgress }
        set { statusRaw = newValue.rawValue }
    }

    var phase: SessionPhase {
        get { SessionPhase(rawValue: phaseRaw) ?? .notStarted }
        set { phaseRaw = newValue.rawValue }
    }

    var totalElapsedSeconds: Double? {
        guard let startedAt, let completedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }
}
```

- [ ] **Step 6: Write `RunSplit`**

```swift
// MurphPlus/Models/RunSplit.swift
import Foundation
import SwiftData

@Model
final class RunSplit {
    var runIndex: Int = 1
    var startTime: Date = Date.distantPast
    var durationSeconds: Double = 0
    var session: MurphSession?

    init(runIndex: Int, startTime: Date, durationSeconds: Double, session: MurphSession? = nil) {
        self.runIndex = runIndex
        self.startTime = startTime
        self.durationSeconds = durationSeconds
        self.session = session
    }
}
```

- [ ] **Step 7: Write `RoundLog`**

```swift
// MurphPlus/Models/RoundLog.swift
import Foundation
import SwiftData

@Model
final class RoundLog {
    var roundNumber: Int = 0
    var completedAt: Date = Date.distantPast
    var session: MurphSession?

    init(roundNumber: Int, completedAt: Date, session: MurphSession? = nil) {
        self.roundNumber = roundNumber
        self.completedAt = completedAt
        self.session = session
    }
}
```

- [ ] **Step 8: Wire the model container into the app**

```swift
// MurphPlus/MurphPlusApp.swift
import SwiftUI
import SwiftData

@main
struct MurphPlusApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self)
        } catch {
            // Container creation fails on schema problems (a non-defaulted
            // property under CloudKit, a bad migration). Surface the reason
            // rather than crashing opaquely on `try!`.
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Text("Murph Plus")
        }
        .modelContainer(container)
    }
}
```

- [ ] **Step 9: Regenerate the project and run tests**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 10: Commit**

```bash
git add MurphPlus/Models MurphPlus/MurphPlusApp.swift MurphPlusTests/ModelTests.swift
git commit -m "feat: add SwiftData models and wire up model container"
```

---

### Task 3: Default Template Seeding

**Files:**
- Create: `MurphPlus/Persistence/DefaultTemplates.swift`
- Modify: `MurphPlus/MurphPlusApp.swift`
- Test: `MurphPlusTests/DefaultTemplatesTests.swift`

**Interfaces:**
- Consumes: `WorkoutTemplate` (Task 2).
- Produces: `enum DefaultTemplates { static func seedIfNeeded(context: ModelContext) throws }`.

- [ ] **Step 1: Write the failing tests**

```swift
// MurphPlusTests/DefaultTemplatesTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

final class DefaultTemplatesTests: XCTestCase {
    func test_seedIfNeeded_insertsTwoStarterTemplatesWhenEmpty() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)

        try DefaultTemplates.seedIfNeeded(context: context)

        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        XCTAssertEqual(templates.count, 2)
        XCTAssertTrue(templates.contains { $0.rounds == 1 })
        XCTAssertTrue(templates.contains { $0.rounds == 20 })
    }

    func test_seedIfNeeded_doesNothingWhenTemplatesExist() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)
        context.insert(WorkoutTemplate(name: "Custom"))
        try context.save()

        try DefaultTemplates.seedIfNeeded(context: context)

        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        XCTAssertEqual(templates.count, 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `cannot find 'DefaultTemplates' in scope`

- [ ] **Step 3: Implement seeding**

```swift
// MurphPlus/Persistence/DefaultTemplates.swift
import SwiftData

enum DefaultTemplates {
    static func seedIfNeeded(context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        guard existing.isEmpty else { return }

        let straightSets = WorkoutTemplate(name: "Full Murph (Straight Sets)", rounds: 1)
        let cindyStyle = WorkoutTemplate(name: "Full Murph (Cindy-Style, 20 Rounds)", rounds: 20)
        context.insert(straightSets)
        context.insert(cindyStyle)
        try context.save()
    }
}
```

- [ ] **Step 4: Call seeding on launch**

```swift
// MurphPlus/MurphPlusApp.swift
import SwiftUI
import SwiftData

@main
struct MurphPlusApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self)
        } catch {
            // Container creation fails on schema problems (a non-defaulted
            // property under CloudKit, a bad migration). Surface the reason
            // rather than crashing opaquely on `try!`.
            fatalError("Failed to create ModelContainer: \(error)")
        }
        try? DefaultTemplates.seedIfNeeded(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            Text("Murph Plus")
        }
        .modelContainer(container)
    }
}
```

- [ ] **Step 5: Regenerate and run tests**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add MurphPlus/Persistence/DefaultTemplates.swift MurphPlus/MurphPlusApp.swift MurphPlusTests/DefaultTemplatesTests.swift
git commit -m "feat: seed starter workout templates on first launch"
```

---

### Task 4: Fatigue Prediction Engine

**Files:**
- Create: `MurphPlus/Prediction/FatiguePrediction.swift`
- Test: `MurphPlusTests/FatiguePredictionTests.swift`

**Interfaces:**
- Consumes: nothing (pure Swift, no SwiftData/UI dependency — this is deliberate so the fatigue math is trivially unit-testable).
- Produces:
  - `struct RoundThroughput { cumulativeRepsAfter: Int; secondsForRound: Int; repsInRound: Int; var secondsPerRep: Double { get } }`
  - `enum FatiguePrediction` with:
    - `struct LinearFit { intercept: Double; slope: Double }`
    - `struct RunPace { run1SecondsPerMile: Double; run2SecondsPerMile: Double }`
    - `struct PredictionResult { predictedRun1Seconds, predictedWorkSeconds, predictedRun2Seconds: Double; var totalSeconds: Double { get }; usedFatigueCurve: Bool }`
    - `static func fitFatigueCurve(rounds: [RoundThroughput]) -> LinearFit?`
    - `static func predictWorkTime(targetReps: Int, fit: LinearFit) -> Double`
    - `static func predictWorkTimeFlatRate(targetReps: Int, sourceWorkSeconds: Double, sourceTotalReps: Int) -> Double?`
    - `static func predictRunTime(targetDistanceMiles: Double, secondsPerMile: Double) -> Double`
    - `static func predict(targetRunDistanceMiles: Double, targetTotalReps: Int, sourceRoundThroughputs: [RoundThroughput], sourceWorkSeconds: Double, sourceTotalReps: Int, pace: RunPace) -> PredictionResult?`

- [ ] **Step 1: Write the failing tests**

```swift
// MurphPlusTests/FatiguePredictionTests.swift
import XCTest
@testable import MurphPlus

final class FatiguePredictionTests: XCTestCase {

    func test_fitFatigueCurve_returnsNilWithFewerThanThreeRounds() {
        let rounds = [
            RoundThroughput(cumulativeRepsAfter: 10, secondsForRound: 20, repsInRound: 10),
            RoundThroughput(cumulativeRepsAfter: 20, secondsForRound: 22, repsInRound: 10)
        ]
        XCTAssertNil(FatiguePrediction.fitFatigueCurve(rounds: rounds))
    }

    // Fixture note: intercept 1.0 / slope 0.02 at 10 reps/round is chosen
    // deliberately so every round's duration lands on a whole second
    // (11, 13, 15, 17, 19, 21). Rounding to Int would otherwise bias the fit —
    // a 0.01 slope yields x.5-second rounds and shifts the recovered intercept
    // by exactly 0.05, which is enough to fail a tolerance-based assertion.
    func test_fitFatigueCurve_recoversKnownLinearRelationship() {
        let repsPerRound = 10
        var rounds: [RoundThroughput] = []
        var cumulative = 0
        for _ in 0..<6 {
            cumulative += repsPerRound
            let midpoint = Double(cumulative) - Double(repsPerRound) / 2.0
            let secPerRep = 1.0 + 0.02 * midpoint
            let secondsForRound = Int((secPerRep * Double(repsPerRound)).rounded())
            rounds.append(RoundThroughput(cumulativeRepsAfter: cumulative, secondsForRound: secondsForRound, repsInRound: repsPerRound))
        }

        let fit = FatiguePrediction.fitFatigueCurve(rounds: rounds)
        XCTAssertNotNil(fit)
        XCTAssertEqual(fit!.intercept, 1.0, accuracy: 0.0001)
        XCTAssertEqual(fit!.slope, 0.02, accuracy: 0.0001)
    }

    func test_predictWorkTime_withZeroSlope_matchesFlatMultiplication() {
        let fit = FatiguePrediction.LinearFit(intercept: 2.0, slope: 0.0)
        let predicted = FatiguePrediction.predictWorkTime(targetReps: 300, fit: fit)
        XCTAssertEqual(predicted, 600.0, accuracy: 0.001)
    }

    func test_predictWorkTimeFlatRate_scalesProportionally() {
        let predicted = FatiguePrediction.predictWorkTimeFlatRate(targetReps: 600, sourceWorkSeconds: 300, sourceTotalReps: 300)
        XCTAssertEqual(predicted!, 600.0, accuracy: 0.001)
    }

    func test_predict_usesFatigueCurveWhenEnoughRounds() {
        let repsPerRound = 15
        var rounds: [RoundThroughput] = []
        var cumulative = 0
        for _ in 0..<5 {
            cumulative += repsPerRound
            rounds.append(RoundThroughput(cumulativeRepsAfter: cumulative, secondsForRound: 20, repsInRound: repsPerRound))
        }
        let pace = FatiguePrediction.RunPace(run1SecondsPerMile: 480, run2SecondsPerMile: 540)

        let result = FatiguePrediction.predict(
            targetRunDistanceMiles: 1.0,
            targetTotalReps: 600,
            sourceRoundThroughputs: rounds,
            sourceWorkSeconds: 100,
            sourceTotalReps: 75,
            pace: pace
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.usedFatigueCurve)
        XCTAssertEqual(result!.predictedRun1Seconds, 480, accuracy: 0.001)
        XCTAssertEqual(result!.predictedRun2Seconds, 540, accuracy: 0.001)
    }

    func test_predict_fallsBackToFlatRateWithOneRound() {
        let rounds = [RoundThroughput(cumulativeRepsAfter: 600, secondsForRound: 500, repsInRound: 600)]
        let pace = FatiguePrediction.RunPace(run1SecondsPerMile: 480, run2SecondsPerMile: 540)

        let result = FatiguePrediction.predict(
            targetRunDistanceMiles: 1.0,
            targetTotalReps: 300,
            sourceRoundThroughputs: rounds,
            sourceWorkSeconds: 500,
            sourceTotalReps: 600,
            pace: pace
        )

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.usedFatigueCurve)
        XCTAssertEqual(result!.predictedWorkSeconds, 250.0, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `cannot find type 'RoundThroughput' in scope`

- [ ] **Step 3: Implement the prediction engine**

```swift
// MurphPlus/Prediction/FatiguePrediction.swift
import Foundation

struct RoundThroughput {
    let cumulativeRepsAfter: Int
    let secondsForRound: Int
    let repsInRound: Int

    var secondsPerRep: Double { Double(secondsForRound) / Double(repsInRound) }
}

enum FatiguePrediction {

    struct LinearFit {
        let intercept: Double
        let slope: Double
    }

    struct RunPace {
        let run1SecondsPerMile: Double
        let run2SecondsPerMile: Double
    }

    struct PredictionResult {
        let predictedRun1Seconds: Double
        let predictedWorkSeconds: Double
        let predictedRun2Seconds: Double
        let usedFatigueCurve: Bool

        var totalSeconds: Double { predictedRun1Seconds + predictedWorkSeconds + predictedRun2Seconds }
    }

    /// Least-squares fit of seconds/rep vs. cumulative reps completed, sampled at
    /// each round's midpoint (a round's rate is best attributed to its middle,
    /// not its start or end).
    static func fitFatigueCurve(rounds: [RoundThroughput]) -> LinearFit? {
        guard rounds.count >= 3 else { return nil }

        let points = rounds.map { round -> (x: Double, y: Double) in
            let midpoint = Double(round.cumulativeRepsAfter) - Double(round.repsInRound) / 2.0
            return (x: midpoint, y: round.secondsPerRep)
        }

        let n = Double(points.count)
        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }
        let sumXY = points.reduce(0) { $0 + $1.x * $1.y }
        let sumXX = points.reduce(0) { $0 + $1.x * $1.x }

        let denominator = n * sumXX - sumX * sumX
        guard denominator != 0 else { return nil }

        let slope = (n * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / n

        return LinearFit(intercept: intercept, slope: slope)
    }

    /// Integrates the fitted seconds/rep line from 0 to targetReps.
    static func predictWorkTime(targetReps: Int, fit: LinearFit) -> Double {
        let reps = Double(targetReps)
        return fit.intercept * reps + fit.slope * reps * reps / 2.0
    }

    static func predictWorkTimeFlatRate(targetReps: Int, sourceWorkSeconds: Double, sourceTotalReps: Int) -> Double? {
        guard sourceTotalReps > 0 else { return nil }
        let rate = sourceWorkSeconds / Double(sourceTotalReps)
        return rate * Double(targetReps)
    }

    static func predictRunTime(targetDistanceMiles: Double, secondsPerMile: Double) -> Double {
        targetDistanceMiles * secondsPerMile
    }

    static func predict(
        targetRunDistanceMiles: Double,
        targetTotalReps: Int,
        sourceRoundThroughputs: [RoundThroughput],
        sourceWorkSeconds: Double,
        sourceTotalReps: Int,
        pace: RunPace
    ) -> PredictionResult? {
        let predictedRun1 = predictRunTime(targetDistanceMiles: targetRunDistanceMiles, secondsPerMile: pace.run1SecondsPerMile)
        let predictedRun2 = predictRunTime(targetDistanceMiles: targetRunDistanceMiles, secondsPerMile: pace.run2SecondsPerMile)

        if let fit = fitFatigueCurve(rounds: sourceRoundThroughputs) {
            let work = predictWorkTime(targetReps: targetTotalReps, fit: fit)
            return PredictionResult(predictedRun1Seconds: predictedRun1, predictedWorkSeconds: work, predictedRun2Seconds: predictedRun2, usedFatigueCurve: true)
        } else if let flat = predictWorkTimeFlatRate(targetReps: targetTotalReps, sourceWorkSeconds: sourceWorkSeconds, sourceTotalReps: sourceTotalReps) {
            return PredictionResult(predictedRun1Seconds: predictedRun1, predictedWorkSeconds: flat, predictedRun2Seconds: predictedRun2, usedFatigueCurve: false)
        } else {
            return nil
        }
    }
}
```

- [ ] **Step 4: Regenerate and run tests**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MurphPlus/Prediction/FatiguePrediction.swift MurphPlusTests/FatiguePredictionTests.swift
git commit -m "feat: add fatigue-curve finish-time prediction engine"
```

---

### Task 5: Session Engine (State Machine)

**Files:**
- Create: `MurphPlus/Session/SessionEngine.swift`
- Test: `MurphPlusTests/SessionEngineTests.swift`

**Interfaces:**
- Consumes: `MurphSession`, `WorkoutTemplate`, `SessionPhase`, `SessionStatus`, `RunSplit`, `RoundLog` (Task 2).
- Produces: `@Observable final class SessionEngine` with:
  - `session: MurphSession` (read-only from outside)
  - `init(session: MurphSession, context: ModelContext)`
  - `static func startNew(template: WorkoutTemplate, vestOn: Bool, vestWeightLbs: Int?, context: ModelContext) -> SessionEngine`
  - `func start()`, `func finishRun()`, `func completeRound()`, `func abandon()`
  - `var totalElapsed: TimeInterval { get }`

- [ ] **Step 1: Write the failing tests**

```swift
// MurphPlusTests/SessionEngineTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

final class SessionEngineTests: XCTestCase {
    var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        context = ModelContext(container)
    }

    private func makeTemplate(rounds: Int) -> WorkoutTemplate {
        let template = WorkoutTemplate(name: "Test Template", rounds: rounds)
        context.insert(template)
        return template
    }

    func test_start_transitionsToRun1AndSetsTimestamps() {
        let template = makeTemplate(rounds: 3)
        let engine = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)

        engine.start()

        XCTAssertEqual(engine.session.phase, .run1)
        XCTAssertNotNil(engine.session.startedAt)
        XCTAssertNotNil(engine.session.currentPhaseStartedAt)
    }

    func test_finishRun_afterRun1_transitionsToRoundsAndRecordsSplit() {
        let template = makeTemplate(rounds: 3)
        let engine = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)
        engine.start()

        engine.finishRun()

        XCTAssertEqual(engine.session.phase, .rounds)
        XCTAssertEqual(engine.session.runSplits.count, 1)
        XCTAssertEqual(engine.session.runSplits.first?.runIndex, 1)
    }

    func test_completeRound_incrementsCountAndTransitionsToRun2OnLastRound() {
        let template = makeTemplate(rounds: 2)
        let engine = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)
        engine.start()
        engine.finishRun()

        engine.completeRound()
        XCTAssertEqual(engine.session.completedRounds, 1)
        XCTAssertEqual(engine.session.phase, .rounds)

        engine.completeRound()
        XCTAssertEqual(engine.session.completedRounds, 2)
        XCTAssertEqual(engine.session.phase, .run2)
    }

    func test_finishRun_afterRun2_completesSession() {
        let template = makeTemplate(rounds: 1)
        let engine = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)
        engine.start()
        engine.finishRun()
        engine.completeRound()

        engine.finishRun()

        XCTAssertEqual(engine.session.phase, .completed)
        XCTAssertEqual(engine.session.status, .completed)
        XCTAssertNotNil(engine.session.completedAt)
        XCTAssertEqual(engine.session.runSplits.count, 2)
    }

    func test_abandon_marksSessionAbandoned() {
        let template = makeTemplate(rounds: 2)
        let engine = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)
        engine.start()

        engine.abandon()

        XCTAssertEqual(engine.session.status, .abandoned)
        XCTAssertNotNil(engine.session.completedAt)
    }

    // An abandoned session is terminal. Without a status guard, `abandon()`
    // leaves `phase` untouched, so a phase-only guard would let completeRound()
    // and then finishRun() run afterwards and flip the session back to
    // .completed — silently erasing the user's abandonment.
    func test_abandonedSession_cannotBeResurrectedByFurtherTransitions() {
        let template = makeTemplate(rounds: 1)
        let engine = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)
        engine.start()
        engine.finishRun()
        engine.abandon()

        engine.completeRound()
        engine.finishRun()

        XCTAssertEqual(engine.session.status, .abandoned)
        XCTAssertEqual(engine.session.roundLogs.count, 0)
    }

    func test_completedSession_cannotBeAbandoned() {
        let template = makeTemplate(rounds: 1)
        let engine = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)
        engine.start()
        engine.finishRun()
        engine.completeRound()
        engine.finishRun()
        let completedAt = engine.session.completedAt

        engine.abandon()

        XCTAssertEqual(engine.session.status, .completed)
        XCTAssertEqual(engine.session.completedAt, completedAt)
    }

    func test_invalidPhaseTransitionsAreIgnored() {
        let template = makeTemplate(rounds: 2)
        let engine = SessionEngine.startNew(template: template, vestOn: false, vestWeightLbs: nil, context: context)

        engine.completeRound()
        XCTAssertEqual(engine.session.completedRounds, 0)

        engine.start()
        engine.start()
        XCTAssertEqual(engine.session.phase, .run1)

        engine.completeRound()
        XCTAssertEqual(engine.session.completedRounds, 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `cannot find 'SessionEngine' in scope`

- [ ] **Step 3: Implement the state machine**

```swift
// MurphPlus/Session/SessionEngine.swift
import Foundation
import Observation
import SwiftData

@Observable
final class SessionEngine {
    private(set) var session: MurphSession
    private let context: ModelContext

    init(session: MurphSession, context: ModelContext) {
        self.session = session
        self.context = context
    }

    static func startNew(template: WorkoutTemplate, vestOn: Bool, vestWeightLbs: Int?, context: ModelContext) -> SessionEngine {
        let session = MurphSession(template: template, vestOn: vestOn, vestWeightLbs: vestWeightLbs)
        context.insert(session)
        try? context.save()
        return SessionEngine(session: session, context: context)
    }

    /// A completed or abandoned session is terminal: no further transition may
    /// mutate it. Guarding on phase alone is not enough, because `abandon()`
    /// changes only `status` — leaving `phase` wherever it was, which would let
    /// `completeRound()`/`finishRun()` run afterwards and silently flip an
    /// abandoned session back to `.completed`, destroying the record.
    private var isTerminal: Bool {
        session.status == .completed || session.status == .abandoned
    }

    func start() {
        guard !isTerminal else { return }
        guard session.phase == .notStarted else { return }
        let now = Date.now
        session.startedAt = now
        session.phase = .run1
        session.currentPhaseStartedAt = now
        save()
    }

    func finishRun() {
        guard !isTerminal else { return }
        guard session.phase == .run1 || session.phase == .run2,
              let start = session.currentPhaseStartedAt else { return }

        let runIndex = session.phase == .run1 ? 1 : 2
        let now = Date.now
        let split = RunSplit(runIndex: runIndex, startTime: start, durationSeconds: now.timeIntervalSince(start), session: session)
        context.insert(split)
        session.runSplits.append(split)

        if session.phase == .run1 {
            session.phase = .rounds
            session.currentPhaseStartedAt = now
        } else {
            session.phase = .completed
            session.status = .completed
            session.completedAt = now
            session.currentPhaseStartedAt = nil
        }
        save()
    }

    func completeRound() {
        guard !isTerminal else { return }
        guard session.phase == .rounds, let template = session.template else { return }

        let nextRoundNumber = session.completedRounds + 1
        let log = RoundLog(roundNumber: nextRoundNumber, completedAt: .now, session: session)
        context.insert(log)
        session.roundLogs.append(log)
        session.completedRounds = nextRoundNumber

        if session.completedRounds >= template.rounds {
            session.phase = .run2
            session.currentPhaseStartedAt = .now
        }
        save()
    }

    func abandon() {
        guard !isTerminal else { return }
        session.status = .abandoned
        session.completedAt = .now
        session.currentPhaseStartedAt = nil
        save()
    }

    var totalElapsed: TimeInterval {
        guard let startedAt = session.startedAt else { return 0 }
        let end = session.completedAt ?? .now
        return end.timeIntervalSince(startedAt)
    }

    private func save() {
        try? context.save()
    }
}
```

- [ ] **Step 4: Regenerate and run tests**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MurphPlus/Session/SessionEngine.swift MurphPlusTests/SessionEngineTests.swift
git commit -m "feat: add live session state machine"
```

---

### Task 6: Start View (Pre-Session Setup)

**Files:**
- Create: `MurphPlus/Views/Start/StartView.swift`

**Interfaces:**
- Consumes: `WorkoutTemplate` (Task 2, via `@Query`).
- Produces: `struct StartView: View { let onBegin: (WorkoutTemplate, Bool, Int?) -> Void }` — decoupled from `SessionEngine`/navigation so it can be built and previewed standalone.

- [ ] **Step 1: Implement the view**

```swift
// MurphPlus/Views/Start/StartView.swift
import SwiftUI
import SwiftData

struct StartView: View {
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]
    @State private var selectedTemplate: WorkoutTemplate?
    @State private var vestOn = false
    @State private var vestWeightText = ""

    let onBegin: (WorkoutTemplate, Bool, Int?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    Picker("Template", selection: $selectedTemplate) {
                        ForEach(templates) { template in
                            Text(template.name).tag(Optional(template))
                        }
                    }
                }

                Section("Vest") {
                    Toggle("Wearing a weighted vest", isOn: $vestOn)
                    if vestOn {
                        TextField("Weight (lbs, default 20)", text: $vestWeightText)
                            .keyboardType(.numberPad)
                    }
                }

                Section {
                    Button("Begin") {
                        guard let template = selectedTemplate else { return }
                        let weight = vestOn ? Int(vestWeightText) : nil
                        onBegin(template, vestOn, weight)
                    }
                    .disabled(selectedTemplate == nil)
                }
            }
            .navigationTitle("Start Murph")
            .onAppear {
                if selectedTemplate == nil {
                    selectedTemplate = templates.first
                }
            }
        }
    }
}

#Preview {
    StartView { _, _, _ in }
        .modelContainer(for: [WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self], inMemory: true)
}
```

- [ ] **Step 2: Regenerate and build**

Run: `xcodegen generate && xcodebuild build -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manual verification**

Open the Xcode canvas preview for `StartView.swift`. Verify: the template picker lists the two seeded starter templates, the vest toggle reveals a weight field when on, and "Begin" is disabled until a template is selected.

- [ ] **Step 4: Commit**

```bash
git add MurphPlus/Views/Start/StartView.swift
git commit -m "feat: add pre-session setup view"
```

---

### Task 7: Live Session View

**Files:**
- Create: `MurphPlus/Views/Session/LiveSessionView.swift`

**Interfaces:**
- Consumes: `SessionEngine` (Task 5).
- Produces: `struct LiveSessionView: View { let engine: SessionEngine; let onFinished: () -> Void }`.

- [ ] **Step 1: Implement the view**

```swift
// MurphPlus/Views/Session/LiveSessionView.swift
import SwiftUI

struct LiveSessionView: View {
    let engine: SessionEngine
    let onFinished: () -> Void

    @State private var showAbandonConfirm = false

    var body: some View {
        VStack(spacing: 24) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(elapsedTimeText)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
            }

            phaseContent

            Button("Abandon", role: .destructive) {
                showAbandonConfirm = true
            }
        }
        .padding()
        .confirmationDialog("Abandon this session?", isPresented: $showAbandonConfirm) {
            Button("Abandon", role: .destructive) {
                engine.abandon()
                onFinished()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch engine.session.phase {
        case .notStarted:
            Button("Start Run 1") { engine.start() }
                .buttonStyle(.borderedProminent)
        case .run1:
            Button("Finish Run 1") { engine.finishRun() }
                .buttonStyle(.borderedProminent)
        case .rounds:
            VStack {
                Text("Round \(engine.session.completedRounds + 1) of \(engine.session.template?.rounds ?? 1)")
                    .font(.title2)
                Button("Round Done") { engine.completeRound() }
                    .buttonStyle(.borderedProminent)
            }
        case .run2:
            Button("Finish Run 2") {
                engine.finishRun()
                onFinished()
            }
            .buttonStyle(.borderedProminent)
        case .completed:
            Text("Done!")
                .font(.title)
        }
    }

    private var elapsedTimeText: String {
        let seconds = Int(engine.totalElapsed)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
```

- [ ] **Step 2: Regenerate and build**

Run: `xcodegen generate && xcodebuild build -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add MurphPlus/Views/Session/LiveSessionView.swift
git commit -m "feat: add live session tracking view"
```

---

### Task 8: Resume-In-Progress-Session Flow

**Files:**
- Create: `MurphPlus/Persistence/ResumableSessionFinder.swift`
- Create: `MurphPlus/Views/Session/ResumeSessionPrompt.swift`
- Test: `MurphPlusTests/ResumableSessionFinderTests.swift`

**Interfaces:**
- Consumes: `MurphSession`, `SessionStatus` (Task 2).
- Produces:
  - `enum ResumableSessionFinder { static func findInProgress(context: ModelContext) -> MurphSession? }`
  - `struct ResumeSessionPrompt: View { let session: MurphSession; let onResume: () -> Void; let onAbandon: () -> Void }`

- [ ] **Step 1: Write the failing test**

```swift
// MurphPlusTests/ResumableSessionFinderTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

final class ResumableSessionFinderTests: XCTestCase {
    func test_findInProgress_returnsSessionWithInProgressStatus() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)

        let template = WorkoutTemplate(name: "Test")
        context.insert(template)
        let completed = MurphSession(template: template, vestOn: false)
        completed.status = .completed
        context.insert(completed)
        let inProgress = MurphSession(template: template, vestOn: false)
        inProgress.startedAt = .now
        context.insert(inProgress)
        try context.save()

        let found = ResumableSessionFinder.findInProgress(context: context)

        XCTAssertEqual(found?.persistentModelID, inProgress.persistentModelID)
    }

    func test_findInProgress_ignoresSessionThatWasNeverStarted() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)

        let template = WorkoutTemplate(name: "Test")
        context.insert(template)
        let neverStarted = MurphSession(template: template, vestOn: false)
        context.insert(neverStarted)
        try context.save()

        XCTAssertNil(ResumableSessionFinder.findInProgress(context: context))
    }

    func test_findInProgress_returnsNilWhenNoneInProgress() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)

        let template = WorkoutTemplate(name: "Test")
        context.insert(template)
        let completed = MurphSession(template: template, vestOn: false)
        completed.status = .completed
        context.insert(completed)
        try context.save()

        XCTAssertNil(ResumableSessionFinder.findInProgress(context: context))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `cannot find 'ResumableSessionFinder' in scope`

- [ ] **Step 3: Implement the finder**

```swift
// MurphPlus/Persistence/ResumableSessionFinder.swift
// `Foundation` is required: #Predicate and SortDescriptor are not visible with
// `import SwiftData` alone (omitting it yields "no macro named 'Predicate'" and
// "cannot find 'SortDescriptor' in scope").
import Foundation
import SwiftData

enum ResumableSessionFinder {
    static func findInProgress(context: ModelContext) -> MurphSession? {
        // Captured in a local so the predicate tracks the enum rather than a
        // hardcoded string that would silently stop matching if a case is renamed.
        let inProgressRaw = SessionStatus.inProgress.rawValue
        let descriptor = FetchDescriptor<MurphSession>(
            predicate: #Predicate { $0.statusRaw == inProgressRaw },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        // `startedAt != nil` excludes sessions that were created at the setup
        // screen but never started — prompting to "resume" one of those would
        // be confusing, since there is nothing to resume.
        return (try? context.fetch(descriptor))?.first { $0.startedAt != nil }
    }
}
```

- [ ] **Step 4: Implement the prompt view**

```swift
// MurphPlus/Views/Session/ResumeSessionPrompt.swift
import SwiftUI

struct ResumeSessionPrompt: View {
    let session: MurphSession
    let onResume: () -> Void
    let onAbandon: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("You have an unfinished Murph from \(session.date.formatted(date: .abbreviated, time: .shortened))")
                .multilineTextAlignment(.center)
            HStack {
                Button("Abandon", role: .destructive, action: onAbandon)
                Button("Resume", action: onResume)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
```

- [ ] **Step 5: Regenerate and run tests**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add MurphPlus/Persistence/ResumableSessionFinder.swift MurphPlus/Views/Session/ResumeSessionPrompt.swift MurphPlusTests/ResumableSessionFinderTests.swift
git commit -m "feat: add in-progress session resume detection and prompt"
```

---

### Task 9: History List View & Stats

**Files:**
- Create: `MurphPlus/Support/DurationFormatting.swift`
- Create: `MurphPlus/Prediction/HistoryStats.swift`
- Create: `MurphPlus/Views/History/HistoryListView.swift`
- Test: `MurphPlusTests/HistoryStatsTests.swift`

This task also introduces a shared `formatDuration` helper. Tasks 10 and 11 need
the same `M:SS` formatting — defining it once here and importing it there avoids
three copies of the same private function.

**Interfaces:**
- Consumes: `MurphSession` (Task 2).
- Produces:
  - `func formatDuration(_ seconds: Double) -> String` (top-level, file-private to no one — used directly by name from any file in the target).
  - `enum HistoryStats { struct Summary { personalBestSeconds, mostRecentSeconds, trendSeconds: Double? }; static func summarize(completedSessions: [MurphSession]) -> Summary }`
  - `struct HistoryListView: View { let onSelect: (MurphSession) -> Void }`

- [ ] **Step 1: Write the failing tests**

```swift
// MurphPlusTests/HistoryStatsTests.swift
import XCTest
@testable import MurphPlus

final class HistoryStatsTests: XCTestCase {
    private func completedSession(daysAgo: Int, elapsedSeconds: Double) -> MurphSession {
        let template = WorkoutTemplate(name: "Test")
        let session = MurphSession(template: template, vestOn: false)
        let start = Date.now.addingTimeInterval(Double(-daysAgo) * 86400)
        // `summarize` sorts on `session.date`, so the fixture must set it —
        // setting only startedAt/completedAt leaves every fixture at the same
        // default date and makes the ordering assertions meaningless.
        session.date = start
        session.startedAt = start
        session.completedAt = start.addingTimeInterval(elapsedSeconds)
        session.status = .completed
        return session
    }

    func test_summarize_withNoSessions_returnsNils() {
        let summary = HistoryStats.summarize(completedSessions: [])
        XCTAssertNil(summary.personalBestSeconds)
        XCTAssertNil(summary.mostRecentSeconds)
        XCTAssertNil(summary.trendSeconds)
    }

    func test_summarize_findsPersonalBestAcrossSessions() {
        let sessions = [
            completedSession(daysAgo: 10, elapsedSeconds: 3000),
            completedSession(daysAgo: 5, elapsedSeconds: 2700),
            completedSession(daysAgo: 1, elapsedSeconds: 2900)
        ]
        let summary = HistoryStats.summarize(completedSessions: sessions)
        XCTAssertEqual(summary.personalBestSeconds, 2700)
    }

    func test_summarize_mostRecentIsLatestByDate() {
        let sessions = [
            completedSession(daysAgo: 10, elapsedSeconds: 3000),
            completedSession(daysAgo: 1, elapsedSeconds: 2900)
        ]
        let summary = HistoryStats.summarize(completedSessions: sessions)
        XCTAssertEqual(summary.mostRecentSeconds, 2900)
    }

    func test_summarize_trendComparesLastTwoSessions() {
        let sessions = [
            completedSession(daysAgo: 10, elapsedSeconds: 3000),
            completedSession(daysAgo: 1, elapsedSeconds: 2900)
        ]
        let summary = HistoryStats.summarize(completedSessions: sessions)
        XCTAssertEqual(summary.trendSeconds, -100)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `cannot find 'HistoryStats' in scope`

- [ ] **Step 3: Implement the shared duration formatter**

```swift
// MurphPlus/Support/DurationFormatting.swift
import Foundation

func formatDuration(_ seconds: Double) -> String {
    let total = Int(max(0, seconds))
    return String(format: "%d:%02d", total / 60, total % 60)
}
```

- [ ] **Step 4: Implement `HistoryStats`**

```swift
// MurphPlus/Prediction/HistoryStats.swift
import Foundation

enum HistoryStats {
    struct Summary {
        let personalBestSeconds: Double?
        let mostRecentSeconds: Double?
        let trendSeconds: Double?
    }

    static func summarize(completedSessions: [MurphSession]) -> Summary {
        let sorted = completedSessions
            .compactMap { session -> (Date, Double)? in
                guard let elapsed = session.totalElapsedSeconds else { return nil }
                return (session.date, elapsed)
            }
            .sorted { $0.0 < $1.0 }

        guard !sorted.isEmpty else {
            return Summary(personalBestSeconds: nil, mostRecentSeconds: nil, trendSeconds: nil)
        }

        let best = sorted.map(\.1).min()
        let mostRecent = sorted.last!.1
        let trend: Double? = sorted.count >= 2 ? mostRecent - sorted[sorted.count - 2].1 : nil

        return Summary(personalBestSeconds: best, mostRecentSeconds: mostRecent, trendSeconds: trend)
    }
}
```

- [ ] **Step 5: Implement `HistoryListView`**

```swift
// MurphPlus/Views/History/HistoryListView.swift
import SwiftUI
import SwiftData

struct HistoryListView: View {
    @Query(sort: \MurphSession.date, order: .reverse) private var allSessions: [MurphSession]
    let onSelect: (MurphSession) -> Void

    // History shows PAST sessions: completed and abandoned only. An .inProgress
    // row can outlive its workout — if the app is killed between "Begin" and
    // "Start Run 1", the session has startedAt == nil, so ResumableSessionFinder
    // deliberately refuses to offer it for resume, and it would otherwise linger
    // in the store forever, rendering here as a stray row showing "—".
    private var sessions: [MurphSession] {
        allSessions.filter { $0.status != .inProgress }
    }

    private var summary: HistoryStats.Summary {
        HistoryStats.summarize(completedSessions: sessions.filter { $0.status == .completed })
    }

    var body: some View {
        List {
            Section {
                statsRow(label: "Personal Best", seconds: summary.personalBestSeconds)
                statsRow(label: "Most Recent", seconds: summary.mostRecentSeconds)
                if let trend = summary.trendSeconds {
                    Text("Trend: \(trend <= 0 ? "↓" : "↑")\(formatDuration(abs(trend))) vs last")
                        .foregroundStyle(trend <= 0 ? .green : .red)
                }
            }

            Section("Sessions") {
                ForEach(sessions) { session in
                    Button {
                        onSelect(session)
                    } label: {
                        sessionRow(session)
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView("No Murphs Yet", systemImage: "figure.run", description: Text("Start your first session from the Start tab."))
            }
        }
    }

    private func statsRow(label: String, seconds: Double?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(seconds.map(formatDuration) ?? "—")
                .foregroundStyle(.secondary)
        }
    }

    private func sessionRow(_ session: MurphSession) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(session.template?.name ?? "Murph")
                Text(session.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if session.status == .abandoned {
                Text("Abandoned").foregroundStyle(.secondary)
            } else {
                Text(session.totalElapsedSeconds.map(formatDuration) ?? "—")
            }
        }
    }
}
```

- [ ] **Step 6: Regenerate and run tests**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add MurphPlus/Support/DurationFormatting.swift MurphPlus/Prediction/HistoryStats.swift MurphPlus/Views/History/HistoryListView.swift MurphPlusTests/HistoryStatsTests.swift
git commit -m "feat: add history list view with stats header"
```

---

### Task 10: Session Detail View & Round Throughput

**Files:**
- Create: `MurphPlus/Prediction/RoundThroughputBuilder.swift`
- Create: `MurphPlus/Views/History/SessionDetailView.swift`
- Test: `MurphPlusTests/RoundThroughputBuilderTests.swift`

**Interfaces:**
- Consumes: `MurphSession`, `RunSplit`, `RoundLog`, `WorkoutTemplate` (Task 2), `RoundThroughput` (Task 4), `formatDuration(_ seconds: Double) -> String` (Task 9 — use it directly, do not redefine a local copy).
- Produces:
  - `enum RoundThroughputBuilder { static func build(session: MurphSession) -> [RoundThroughput] }`
  - `struct SessionDetailView: View { @Bindable var session: MurphSession }` — later tasks (11) append content to its `Form`.

- [ ] **Step 1: Write the failing test**

```swift
// MurphPlusTests/RoundThroughputBuilderTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

final class RoundThroughputBuilderTests: XCTestCase {
    func test_build_computesPerRoundDurationsFromTimestamps() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)

        let template = WorkoutTemplate(name: "Test", rounds: 3)
        context.insert(template)
        let session = MurphSession(template: template, vestOn: false)
        context.insert(session)

        let run1Start = Date(timeIntervalSince1970: 0)
        let run1 = RunSplit(runIndex: 1, startTime: run1Start, durationSeconds: 480, session: session)
        context.insert(run1)
        session.runSplits.append(run1)

        let roundsStart = run1Start.addingTimeInterval(480)
        let round1 = RoundLog(roundNumber: 1, completedAt: roundsStart.addingTimeInterval(20), session: session)
        let round2 = RoundLog(roundNumber: 2, completedAt: roundsStart.addingTimeInterval(45), session: session)
        context.insert(round1)
        context.insert(round2)
        session.roundLogs.append(contentsOf: [round1, round2])

        let throughputs = RoundThroughputBuilder.build(session: session)

        XCTAssertEqual(throughputs.count, 2)
        XCTAssertEqual(throughputs[0].secondsForRound, 20)
        XCTAssertEqual(throughputs[1].secondsForRound, 25)
        XCTAssertEqual(throughputs[0].repsInRound, 200)
        // Round N must report N × repsPerRound cumulatively — this is the x-axis
        // of Task 11's fatigue regression, so an error here skews every prediction.
        XCTAssertEqual(throughputs[0].cumulativeRepsAfter, 200)
        XCTAssertEqual(throughputs[1].cumulativeRepsAfter, 400)
    }

    // The builder sorts roundLogs by roundNumber before walking them, because
    // SwiftData relationship arrays have no guaranteed order. Without the sort,
    // walking logs in insertion order yields wrong (and possibly negative)
    // durations. This test inserts them deliberately out of order so that
    // removing the sort fails loudly instead of silently corrupting predictions.
    func test_build_sortsRoundLogsBeforeComputingDurations() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)

        let template = WorkoutTemplate(name: "Test", rounds: 3)
        context.insert(template)
        let session = MurphSession(template: template, vestOn: false)
        context.insert(session)

        let run1Start = Date(timeIntervalSince1970: 0)
        let run1 = RunSplit(runIndex: 1, startTime: run1Start, durationSeconds: 480, session: session)
        context.insert(run1)
        session.runSplits.append(run1)

        let roundsStart = run1Start.addingTimeInterval(480)
        let round1 = RoundLog(roundNumber: 1, completedAt: roundsStart.addingTimeInterval(20), session: session)
        let round2 = RoundLog(roundNumber: 2, completedAt: roundsStart.addingTimeInterval(45), session: session)
        context.insert(round1)
        context.insert(round2)
        // Deliberately appended newest-first.
        session.roundLogs.append(contentsOf: [round2, round1])

        let throughputs = RoundThroughputBuilder.build(session: session)

        XCTAssertEqual(throughputs.count, 2)
        XCTAssertEqual(throughputs[0].secondsForRound, 20)
        XCTAssertEqual(throughputs[1].secondsForRound, 25)
    }

    func test_build_returnsEmptyWhenRunOneMissing() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)

        let template = WorkoutTemplate(name: "Test", rounds: 3)
        context.insert(template)
        let session = MurphSession(template: template, vestOn: false)
        context.insert(session)

        let round1 = RoundLog(roundNumber: 1, completedAt: .now, session: session)
        context.insert(round1)
        session.roundLogs.append(round1)

        XCTAssertTrue(RoundThroughputBuilder.build(session: session).isEmpty)
    }

    func test_build_returnsEmptyWhenNoRoundsLogged() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self, configurations: config)
        let context = ModelContext(container)

        let template = WorkoutTemplate(name: "Test", rounds: 3)
        context.insert(template)
        let session = MurphSession(template: template, vestOn: false)
        context.insert(session)

        let run1 = RunSplit(runIndex: 1, startTime: Date(timeIntervalSince1970: 0), durationSeconds: 480, session: session)
        context.insert(run1)
        session.runSplits.append(run1)

        XCTAssertTrue(RoundThroughputBuilder.build(session: session).isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `cannot find 'RoundThroughputBuilder' in scope`

- [ ] **Step 3: Implement `RoundThroughputBuilder`**

```swift
// MurphPlus/Prediction/RoundThroughputBuilder.swift
import Foundation

enum RoundThroughputBuilder {
    static func build(session: MurphSession) -> [RoundThroughput] {
        guard let template = session.template,
              let run1 = session.runSplits.first(where: { $0.runIndex == 1 }) else { return [] }

        let roundsPhaseStart = run1.startTime.addingTimeInterval(run1.durationSeconds)
        let sortedLogs = session.roundLogs.sorted { $0.roundNumber < $1.roundNumber }
        let repsPerRound = template.repsPerRound

        var results: [RoundThroughput] = []
        var previousTimestamp = roundsPhaseStart

        for log in sortedLogs {
            let duration = Int(log.completedAt.timeIntervalSince(previousTimestamp).rounded())
            results.append(RoundThroughput(
                cumulativeRepsAfter: log.roundNumber * repsPerRound,
                secondsForRound: duration,
                repsInRound: repsPerRound
            ))
            previousTimestamp = log.completedAt
        }

        return results
    }
}
```

- [ ] **Step 4: Implement `SessionDetailView`**

```swift
// MurphPlus/Views/History/SessionDetailView.swift
import SwiftUI
import SwiftData

struct SessionDetailView: View {
    @Bindable var session: MurphSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    private var roundThroughputs: [RoundThroughput] {
        RoundThroughputBuilder.build(session: session)
    }

    var body: some View {
        Form {
            Section("Summary") {
                LabeledContent("Template", value: session.template?.name ?? "—")
                LabeledContent("Total Time", value: session.totalElapsedSeconds.map(formatDuration) ?? "—")
                LabeledContent("Vest", value: session.vestOn ? "\(session.vestWeightLbs ?? 20) lbs" : "None")
                LabeledContent("Status", value: session.status == .completed ? "Completed" : "Abandoned")
            }

            if let run1 = session.runSplits.first(where: { $0.runIndex == 1 }) {
                Section("Run 1") {
                    Text(formatDuration(run1.durationSeconds))
                }
            }

            if !roundThroughputs.isEmpty {
                Section("Rounds") {
                    ForEach(Array(roundThroughputs.enumerated()), id: \.offset) { index, round in
                        LabeledContent("Round \(index + 1)", value: "\(round.secondsForRound)s")
                    }
                }
            }

            if let run2 = session.runSplits.first(where: { $0.runIndex == 2 }) {
                Section("Run 2") {
                    Text(formatDuration(run2.durationSeconds))
                }
            }

            Section("Notes") {
                TextEditor(text: Binding(
                    get: { session.notes ?? "" },
                    set: { session.notes = $0 }
                ))
                .frame(minHeight: 80)
            }

            Section {
                Button("Delete Session", role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        }
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
        .confirmationDialog("Delete this session?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                context.delete(session)
                try? context.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
```

- [ ] **Step 5: Regenerate and run tests**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add MurphPlus/Prediction/RoundThroughputBuilder.swift MurphPlus/Views/History/SessionDetailView.swift MurphPlusTests/RoundThroughputBuilderTests.swift
git commit -m "feat: add session detail view with per-round pace"
```

---

### Task 11: Prediction Control (wired into Session Detail)

**Files:**
- Create: `MurphPlus/Views/History/PredictionControlView.swift`
- Modify: `MurphPlus/Views/History/SessionDetailView.swift`

**Interfaces:**
- Consumes: `FatiguePrediction` (Task 4), `RoundThroughputBuilder` (Task 10), `WorkoutTemplate`, `MurphSession` (Task 2), `formatDuration(_ seconds: Double) -> String` (Task 9 — use it directly, do not redefine a local copy).
- Produces: `struct PredictionControlView: View { let session: MurphSession }` — a `Section` embedded directly into `SessionDetailView`'s `Form`.

- [ ] **Step 1: Implement `PredictionControlView`**

```swift
// MurphPlus/Views/History/PredictionControlView.swift
import SwiftUI
import SwiftData

struct PredictionControlView: View {
    let session: MurphSession
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]
    @State private var targetTemplate: WorkoutTemplate?

    private var sourceRoundThroughputs: [RoundThroughput] {
        RoundThroughputBuilder.build(session: session)
    }

    private var pace: FatiguePrediction.RunPace? {
        guard
            let run1 = session.runSplits.first(where: { $0.runIndex == 1 }),
            let run2 = session.runSplits.first(where: { $0.runIndex == 2 }),
            let template = session.template,
            template.runDistanceMiles > 0
        else { return nil }
        return FatiguePrediction.RunPace(
            run1SecondsPerMile: run1.durationSeconds / template.runDistanceMiles,
            run2SecondsPerMile: run2.durationSeconds / template.runDistanceMiles
        )
    }

    private var sourceWorkSeconds: Double {
        sourceRoundThroughputs.reduce(0) { $0 + Double($1.secondsForRound) }
    }

    private var sourceTotalReps: Int {
        session.template?.totalReps ?? 0
    }

    private var result: FatiguePrediction.PredictionResult? {
        guard let target = targetTemplate, let pace else { return nil }
        return FatiguePrediction.predict(
            targetRunDistanceMiles: target.runDistanceMiles,
            targetTotalReps: target.totalReps,
            sourceRoundThroughputs: sourceRoundThroughputs,
            sourceWorkSeconds: sourceWorkSeconds,
            sourceTotalReps: sourceTotalReps,
            pace: pace
        )
    }

    var body: some View {
        // Per the spec, the control is absent — not merely disabled — until this
        // session has the run data a prediction is derived from. An abandoned or
        // partial session simply shows no prediction UI at all.
        if pace != nil {
            predictionSection
        }
    }

    @ViewBuilder
    private var predictionSection: some View {
        Section("Predict Another Distance") {
            Picker("Target", selection: $targetTemplate) {
                Text("Choose a template").tag(WorkoutTemplate?.none)
                ForEach(templates) { template in
                    Text(template.name).tag(Optional(template))
                }
            }

            if let result {
                LabeledContent("Predicted Time", value: formatDuration(result.totalSeconds))
                Text(result.usedFatigueCurve
                     ? "Based on this session's fatigue curve."
                     : "Based on this session's flat average pace (not enough rounds for a fatigue curve).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Assumes the same vest status as this session: \(session.vestOn ? "\(session.vestWeightLbs ?? 20) lbs" : "no vest").")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 2: Embed it in `SessionDetailView`**

In `MurphPlus/Views/History/SessionDetailView.swift`, add the control as the last section inside the existing `Form`, right after the "Notes" section and before "Delete Session":

```swift
            PredictionControlView(session: session)

            Section {
                Button("Delete Session", role: .destructive) {
```

- [ ] **Step 3: Regenerate and build**

Run: `xcodegen generate && xcodebuild build -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MurphPlus/Views/History/PredictionControlView.swift MurphPlus/Views/History/SessionDetailView.swift
git commit -m "feat: wire fatigue prediction control into session detail"
```

---

### Task 12: Calendar View

**Files:**
- Create: `MurphPlus/Prediction/CalendarMonthBuilder.swift`
- Create: `MurphPlus/Views/History/CalendarView.swift`
- Test: `MurphPlusTests/CalendarMonthBuilderTests.swift`

**Interfaces:**
- Consumes: `MurphSession` (Task 2).
- Produces:
  - `struct CalendarDay: Identifiable { date: Date; isInCurrentMonth: Bool; session: MurphSession? }`
  - `enum CalendarMonthBuilder { static func build(month: Date, sessions: [MurphSession], calendar: Calendar = .current) -> [CalendarDay] }`
  - `struct CalendarView: View { let onSelect: (MurphSession) -> Void }`

- [ ] **Step 1: Write the failing tests**

```swift
// MurphPlusTests/CalendarMonthBuilderTests.swift
import XCTest
@testable import MurphPlus

final class CalendarMonthBuilderTests: XCTestCase {
    func test_build_returnsCompleteWeeksCoveringTheMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let month = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!

        let days = CalendarMonthBuilder.build(month: month, sessions: [], calendar: calendar)

        XCTAssertEqual(days.count % 7, 0)
        XCTAssertTrue(days.contains { calendar.isDate($0.date, equalTo: month, toGranularity: .month) })
    }

    func test_build_attachesSessionToMatchingDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let month = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let sessionDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!

        let template = WorkoutTemplate(name: "Test")
        let session = MurphSession(template: template, vestOn: false)
        session.date = sessionDate

        let days = CalendarMonthBuilder.build(month: month, sessions: [session], calendar: calendar)

        let matchingDay = days.first { calendar.isDate($0.date, inSameDayAs: sessionDate) }
        XCTAssertNotNil(matchingDay?.session)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `cannot find 'CalendarMonthBuilder' in scope`

- [ ] **Step 3: Implement `CalendarMonthBuilder`**

```swift
// MurphPlus/Prediction/CalendarMonthBuilder.swift
import Foundation

struct CalendarDay: Identifiable {
    let id = UUID()
    let date: Date
    let isInCurrentMonth: Bool
    let session: MurphSession?
}

enum CalendarMonthBuilder {
    static func build(month: Date, sessions: [MurphSession], calendar: Calendar = .current) -> [CalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let firstWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else { return [] }

        let sessionsByDay = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.date) }

        var days: [CalendarDay] = []
        var current = firstWeekInterval.start

        while current < monthInterval.end || days.count % 7 != 0 {
            let dayStart = calendar.startOfDay(for: current)
            let isInCurrentMonth = calendar.isDate(current, equalTo: month, toGranularity: .month)
            let session = sessionsByDay[dayStart]?.first
            days.append(CalendarDay(date: dayStart, isInCurrentMonth: isInCurrentMonth, session: session))
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }

        return days
    }
}
```

- [ ] **Step 4: Implement `CalendarView`**

```swift
// MurphPlus/Views/History/CalendarView.swift
import SwiftUI
import SwiftData

struct CalendarView: View {
    @Query private var sessions: [MurphSession]
    @State private var displayedMonth: Date = .now
    let onSelect: (MurphSession) -> Void

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    private var days: [CalendarDay] {
        CalendarMonthBuilder.build(month: displayedMonth, sessions: sessions, calendar: calendar)
    }

    var body: some View {
        VStack {
            HStack {
                Button { shiftMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button { shiftMonth(by: 1) } label: { Image(systemName: "chevron.right") }
            }
            .padding(.horizontal)

            LazyVGrid(columns: columns) {
                ForEach(days) { day in
                    dayCell(day)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
    }

    private func dayCell(_ day: CalendarDay) -> some View {
        Button {
            if let session = day.session {
                onSelect(session)
            }
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: day.date))")
                    .foregroundStyle(day.isInCurrentMonth ? .primary : .secondary)
                marker(for: day.session)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .disabled(day.session == nil)
    }

    @ViewBuilder
    private func marker(for session: MurphSession?) -> some View {
        switch session?.status {
        case .completed:
            Circle().fill(Color.green).frame(width: 6, height: 6)
        case .abandoned:
            Circle().strokeBorder(Color.orange).frame(width: 6, height: 6)
        default:
            Circle().fill(Color.clear).frame(width: 6, height: 6)
        }
    }

    private func shiftMonth(by value: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) ?? displayedMonth
    }
}
```

- [ ] **Step 5: Regenerate and run tests**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add MurphPlus/Prediction/CalendarMonthBuilder.swift MurphPlus/Views/History/CalendarView.swift MurphPlusTests/CalendarMonthBuilderTests.swift
git commit -m "feat: add calendar view of session history"
```

---

### Task 13: Root Navigation & Final Integration

**Files:**
- Create: `MurphPlus/Views/History/HistoryView.swift`
- Create: `MurphPlus/Views/RootTabView.swift`
- Modify: `MurphPlus/MurphPlusApp.swift`

**Interfaces:**
- Consumes: everything from Tasks 2–12.
- Produces: `struct HistoryView: View`, `struct RootTabView: View` — the assembled app.

- [ ] **Step 1: Implement `HistoryView`** (List/Calendar toggle + navigation to detail)

```swift
// MurphPlus/Views/History/HistoryView.swift
import SwiftUI

struct HistoryView: View {
    enum Mode: String, CaseIterable {
        case list = "List"
        case calendar = "Calendar"
    }

    @State private var mode: Mode = .list
    @State private var selectedSession: MurphSession?

    var body: some View {
        NavigationStack {
            VStack {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch mode {
                case .list:
                    HistoryListView(onSelect: { selectedSession = $0 })
                case .calendar:
                    CalendarView(onSelect: { selectedSession = $0 })
                }
            }
            .navigationTitle("History")
            .navigationDestination(item: $selectedSession) { session in
                SessionDetailView(session: session)
            }
        }
    }
}
```

- [ ] **Step 2: Implement `RootTabView`** (tab shell, live-session presentation, resume prompt)

```swift
// MurphPlus/Views/RootTabView.swift
import SwiftUI
import SwiftData

private struct LiveSessionWrapper: Identifiable {
    let engine: SessionEngine
    var id: ObjectIdentifier { ObjectIdentifier(engine) }
}

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @State private var liveEngine: SessionEngine?
    @State private var resumableSession: MurphSession?

    var body: some View {
        TabView {
            StartView { template, vestOn, vestWeight in
                liveEngine = SessionEngine.startNew(template: template, vestOn: vestOn, vestWeightLbs: vestWeight, context: context)
            }
            .tabItem { Label("Start", systemImage: "play.circle") }

            HistoryView()
                .tabItem { Label("History", systemImage: "list.bullet") }
        }
        .fullScreenCover(item: Binding(
            get: { liveEngine.map { LiveSessionWrapper(engine: $0) } },
            set: { liveEngine = $0?.engine }
        )) { wrapper in
            LiveSessionView(engine: wrapper.engine) {
                liveEngine = nil
            }
        }
        .sheet(item: $resumableSession) { session in
            ResumeSessionPrompt(
                session: session,
                onResume: {
                    liveEngine = SessionEngine(session: session, context: context)
                    resumableSession = nil
                },
                onAbandon: {
                    session.status = .abandoned
                    session.completedAt = .now
                    try? context.save()
                    resumableSession = nil
                }
            )
        }
        .task {
            resumableSession = ResumableSessionFinder.findInProgress(context: context)
        }
    }
}
```

- [ ] **Step 3: Wire it into the app entry point**

```swift
// MurphPlus/MurphPlusApp.swift
import SwiftUI
import SwiftData

@main
struct MurphPlusApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self)
        } catch {
            // Container creation fails on schema problems (a non-defaulted
            // property under CloudKit, a bad migration). Surface the reason
            // rather than crashing opaquely on `try!`.
            fatalError("Failed to create ModelContainer: \(error)")
        }
        try? DefaultTemplates.seedIfNeeded(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}
```

- [ ] **Step 4: Regenerate and run the full test suite**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: End-to-end manual smoke test**

Run the app in the simulator (`xcodebuild build` then launch from Xcode, or `xcrun simctl` boot + install) and walk through:
1. Start tab → pick "Full Murph (Cindy-Style, 20 Rounds)", leave vest off, tap Begin.
2. Tap "Start Run 1" → wait a moment → "Finish Run 1".
3. Tap "Round Done" 20 times, confirming the round counter advances each time.
4. "Finish Run 2" → confirm the live session dismisses and you land back in the app.
5. History tab → List: confirm the new session appears with a time, and the stats header shows a personal best.
6. Tap the session → Detail: confirm run splits and 20 round entries are listed; add a note and confirm it saves; use the "Predict Another Distance" control to pick the straight-sets template and confirm a predicted time appears.
7. Switch to Calendar: confirm today's cell shows a filled (completed) marker; tap it and confirm it opens the same session detail.
8. Start a second session, complete a couple of rounds, then force-quit the app (don't finish it) and relaunch: confirm the resume prompt appears; tap Resume and confirm the round counter and elapsed timer pick up correctly; then abandon it and confirm it shows as "Abandoned" in History.

- [ ] **Step 6: Commit**

```bash
git add MurphPlus/Views/History/HistoryView.swift MurphPlus/Views/RootTabView.swift MurphPlus/MurphPlusApp.swift
git commit -m "feat: wire up root tab navigation and complete v1 integration"
```

---

### Task 14: Custom Template Editor

Per the spec, "Half Murph" / "Mini Murph" aren't app-defined tiers — a user creates them by directly setting run distance and rep totals on a `WorkoutTemplate`. This task adds that creation UI, reachable from Start.

**Files:**
- Create: `MurphPlus/Views/Start/TemplateEditorView.swift`
- Modify: `MurphPlus/Views/Start/StartView.swift`

**Interfaces:**
- Consumes: `WorkoutTemplate` (Task 2).
- Produces: `struct TemplateEditorView: View` (no external inputs — reads/writes via `@Environment(\.modelContext)` and dismisses itself on save/cancel).

- [ ] **Step 1: Implement `TemplateEditorView`**

```swift
// MurphPlus/Views/Start/TemplateEditorView.swift
import SwiftUI
import SwiftData

struct TemplateEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var runDistanceMiles = 1.0
    @State private var totalPullUps = 100
    @State private var totalPushUps = 200
    @State private var totalSquats = 300
    @State private var rounds = 1

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && runDistanceMiles > 0
            && totalPullUps > 0 && totalPushUps > 0 && totalSquats > 0
            && rounds > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Half Murph", text: $name)
                }

                Section("Runs") {
                    Stepper(value: $runDistanceMiles, in: 0.25...5, step: 0.25) {
                        Text("\(runDistanceMiles, specifier: "%.2f") mi each")
                    }
                }

                Section("Total Reps") {
                    Stepper(value: $totalPullUps, in: 1...1000, step: 5) {
                        Text("Pull-ups: \(totalPullUps)")
                    }
                    Stepper(value: $totalPushUps, in: 1...1000, step: 5) {
                        Text("Push-ups: \(totalPushUps)")
                    }
                    Stepper(value: $totalSquats, in: 1...1000, step: 5) {
                        Text("Squats: \(totalSquats)")
                    }
                }

                Section("Partitioning") {
                    Stepper(value: $rounds, in: 1...50) {
                        Text(rounds == 1 ? "Straight sets" : "\(rounds) rounds")
                    }
                }
            }
            .navigationTitle("New Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let template = WorkoutTemplate(
                            name: name,
                            runDistanceMiles: runDistanceMiles,
                            totalPullUps: totalPullUps,
                            totalPushUps: totalPushUps,
                            totalSquats: totalSquats,
                            rounds: rounds
                        )
                        context.insert(template)
                        try? context.save()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Add a "New Template" entry point to `StartView`**

Replace the full contents of `MurphPlus/Views/Start/StartView.swift` with:

```swift
// MurphPlus/Views/Start/StartView.swift
import SwiftUI
import SwiftData

struct StartView: View {
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]
    @State private var selectedTemplate: WorkoutTemplate?
    @State private var vestOn = false
    @State private var vestWeightText = ""
    @State private var showTemplateEditor = false

    let onBegin: (WorkoutTemplate, Bool, Int?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    Picker("Template", selection: $selectedTemplate) {
                        ForEach(templates) { template in
                            Text(template.name).tag(Optional(template))
                        }
                    }
                    Button("New Template…") {
                        showTemplateEditor = true
                    }
                }

                Section("Vest") {
                    Toggle("Wearing a weighted vest", isOn: $vestOn)
                    if vestOn {
                        TextField("Weight (lbs, default 20)", text: $vestWeightText)
                            .keyboardType(.numberPad)
                    }
                }

                Section {
                    Button("Begin") {
                        guard let template = selectedTemplate else { return }
                        let weight = vestOn ? Int(vestWeightText) : nil
                        onBegin(template, vestOn, weight)
                    }
                    .disabled(selectedTemplate == nil)
                }
            }
            .navigationTitle("Start Murph")
            .onAppear {
                if selectedTemplate == nil {
                    selectedTemplate = templates.first
                }
            }
            .sheet(isPresented: $showTemplateEditor) {
                TemplateEditorView()
            }
        }
    }
}

#Preview {
    StartView { _, _, _ in }
        .modelContainer(for: [WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self], inMemory: true)
}
```

- [ ] **Step 3: Regenerate and build**

Run: `xcodegen generate && xcodebuild build -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manual verification**

Run the app, go to Start → "New Template…", enter a name (e.g. "Half Murph"), leave run distance at 1.0, set pull-ups/push-ups/squats to 50/100/150, set rounds to 10, tap Save. Confirm it now appears in the Template picker and can be selected to begin a session.

- [ ] **Step 5: Commit**

```bash
git add MurphPlus/Views/Start/TemplateEditorView.swift MurphPlus/Views/Start/StartView.swift
git commit -m "feat: add custom template editor for scaled Murph variants"
```

---

### Task 15: Enable CloudKit Sync & Device Signing

Deferred to last on purpose: CloudKit entitlements require a paid Apple Developer
account and a provisioned iCloud container, and turning them on earlier would
have blocked every simulator build in this plan. Everything above works against
local-only SwiftData; this task switches on cross-device sync.

**Prerequisite:** a paid Apple Developer Program membership. If you don't have
one yet, stop here — the app is fully functional local-only, and this task can be
picked up later without touching any other code.

**Files:**
- Modify: `project.yml`
- Create: `MurphPlus/MurphPlus.entitlements` (via `xcodegen generate`, from the `entitlements:` block added to `project.yml`)

**Interfaces:**
- Consumes: all models (Task 2). No new types produced.

- [ ] **Step 1: Verify every model property is CloudKit-compatible**

CloudKit requires all attributes to be optional or have default values, and all
relationships to be optional. Re-read the four files in `MurphPlus/Models/` and
confirm: every `var` has either a `?` or an `= default`, and both `@Relationship`
arrays are defaulted to `[]`. This was built in during Task 2 — this step is a
verification, not a change. If anything is missing a default, add one now.

- [ ] **Step 2: Add the CloudKit entitlement to `project.yml`**

Insert this block into the `MurphPlus` target, as a sibling of `settings:`:

```yaml
    entitlements:
      path: MurphPlus/MurphPlus.entitlements
      properties:
        com.apple.developer.icloud-container-identifiers:
          - iCloud.com.projectnemeth.MurphPlus
        com.apple.developer.icloud-services:
          - CloudKit
```

- [ ] **Step 3: Regenerate and set the signing team**

Run: `xcodegen generate`

Then open `MurphPlus.xcodeproj` in Xcode → `MurphPlus` target → Signing &
Capabilities → select your Team, and confirm the iCloud capability shows the
`iCloud.com.projectnemeth.MurphPlus` container (create it there if it doesn't
exist yet). This is account-specific and can't be scripted.

- [ ] **Step 4: Confirm the container picks up CloudKit**

No code change is required — `ModelContainer` automatically enables CloudKit
sync when the entitlement is present. Build and run on a device:

Run: `xcodebuild build -scheme MurphPlus -destination 'generic/platform=iOS' -project MurphPlus.xcodeproj`
Expected: `** BUILD SUCCEEDED **`

If the container now fails to initialize, the `fatalError` added in Task 2 prints
the schema violation — fix the offending property's default and rebuild.

- [ ] **Step 5: Verify sync across two devices**

Install on two devices signed into the same iCloud account. Complete a short
session on one, then confirm it appears in History on the other (allow up to a
minute; CloudKit sync is not instant). If nothing syncs, check that both devices
have iCloud Drive enabled and are on the same Apple ID.

- [ ] **Step 6: Commit**

```bash
git add project.yml MurphPlus/MurphPlus.entitlements
git commit -m "feat: enable CloudKit sync for cross-device workout history"
```
