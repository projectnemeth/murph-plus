# Murph Plus v1 Fix Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct five defects in the shipped v1 phone app: a dead toolbar button, a destructive button in the thumb zone, straight-sets Half/Mini templates that should be Cindy-style, abandoned sessions that hide the progress they actually recorded, and a start screen titled with an instruction instead of the app name.

**Architecture:** All changes are presentation or seed-data. **No task touches `SessionEngine`**, so this plan is fully independent of the Apple Watch work and can ship before it. Two tasks add pure, unit-testable logic (a seed migration and a progress describer); the rest are SwiftUI changes verified by build plus manual walkthrough, following the v1 plan's established testing approach.

**Tech Stack:** Swift, SwiftUI, SwiftData, XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-03-murph-plus-v1-fixes-design.md`

## Global Constraints

- iOS 17.0 minimum (required by SwiftData).
- Native Swift/SwiftUI only — no third-party runtime dependencies.
- **Re-run `xcodegen generate` after adding any new source file**, before building. The `sources` glob is folder-based, so new files need no `project.yml` edit — but the project must be regenerated to see them.
- Test command throughout: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`. If `iPhone 17` is not an installed simulator, run `xcrun simctl list devicetypes` and substitute an available iPhone name in every `-destination` flag in this plan.
- Logged sessions can be deleted but never edited — nothing in this plan may add a path that mutates a logged time.
- Template **names stay byte-identical**. Only `rounds` changes. Do not rename `Half Murph` or `Mini Murph`.
- Personal-best and trend statistics continue to consider completed sessions only. Nothing here lets a partial attempt compete with a finished one.

---

## File Structure

```
MurphPlus/
  Persistence/
    DefaultTemplates.swift              MODIFY — corrected seed rounds
    DefaultTemplateMigration.swift      CREATE — one-time correction for existing installs
  Support/
    SessionProgressDescriber.swift      CREATE — "how far did this attempt get" strings
  Views/
    Start/StartView.swift               MODIFY — screen title
    Session/LiveSessionView.swift       MODIFY — toolbar rework, Abandon out of bottom stack
    History/SessionDetailView.swift     MODIFY — real stopped-at time + progress line
  DesignSystem/Components/
    MurphSessionRow.swift               MODIFY — optional progress label
  MurphPlusApp.swift                    MODIFY — run the migration at launch
MurphPlusTests/
  DefaultTemplateMigrationTests.swift   CREATE
  SessionProgressDescriberTests.swift   CREATE
  DefaultTemplatesTests.swift           MODIFY — assert corrected seed values
```

---

### Task 1: Corrective template migration

The riskiest change in the batch, and the one that silently does nothing if
done naively. `DefaultTemplates.seedIfNeeded` returns early when the store is
non-empty, so editing the seed constants alone fixes no existing install.

**Files:**
- Create: `MurphPlus/Persistence/DefaultTemplateMigration.swift`
- Modify: `MurphPlus/Persistence/DefaultTemplates.swift`
- Modify: `MurphPlus/MurphPlusApp.swift:19`
- Test: `MurphPlusTests/DefaultTemplateMigrationTests.swift`
- Test: `MurphPlusTests/DefaultTemplatesTests.swift`

**Interfaces:**
- Consumes: `WorkoutTemplate` (existing `@Model`), `ModelContext`.
- Produces: `DefaultTemplateMigration.runIfNeeded(context:defaults:) throws`, called once at launch. No later task depends on it.

- [ ] **Step 1: Write the failing tests**

Create `MurphPlusTests/DefaultTemplateMigrationTests.swift`:

```swift
// MurphPlusTests/DefaultTemplateMigrationTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

final class DefaultTemplateMigrationTests: XCTestCase {
    var context: ModelContext!
    var defaults: UserDefaults!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self,
            configurations: config
        )
        context = ModelContext(container)

        // A throwaway suite per test run, so the migration flag never leaks
        // between tests or into the developer's real defaults.
        let suiteName = "DefaultTemplateMigrationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    /// The Half Murph exactly as v1 shipped it: straight sets.
    private func insertShippedHalfMurph() {
        context.insert(WorkoutTemplate(
            name: "Half Murph",
            runDistanceMiles: 0.5,
            totalPullUps: 50, totalPushUps: 100, totalSquats: 150,
            rounds: 1
        ))
    }

    private func fetchTemplate(named name: String) throws -> WorkoutTemplate? {
        try context.fetch(FetchDescriptor<WorkoutTemplate>()).first { $0.name == name }
    }

    func test_correctsUntouchedHalfMurphToTenRounds() throws {
        insertShippedHalfMurph()

        try DefaultTemplateMigration.runIfNeeded(context: context, defaults: defaults)

        let half = try XCTUnwrap(fetchTemplate(named: "Half Murph"))
        XCTAssertEqual(half.rounds, 10)
        XCTAssertEqual(half.pullUpsPerRound, 5)
        XCTAssertEqual(half.pushUpsPerRound, 10)
        XCTAssertEqual(half.squatsPerRound, 15)
    }

    func test_correctsUntouchedMiniMurphToFiveRounds() throws {
        context.insert(WorkoutTemplate(
            name: "Mini Murph",
            runDistanceMiles: 0.25,
            totalPullUps: 25, totalPushUps: 50, totalSquats: 75,
            rounds: 1
        ))

        try DefaultTemplateMigration.runIfNeeded(context: context, defaults: defaults)

        let mini = try XCTUnwrap(fetchTemplate(named: "Mini Murph"))
        XCTAssertEqual(mini.rounds, 5)
        XCTAssertEqual(mini.pullUpsPerRound, 5)
        XCTAssertEqual(mini.pushUpsPerRound, 10)
        XCTAssertEqual(mini.squatsPerRound, 15)
    }

    func test_leavesNameRepsAndDistanceUntouched() throws {
        insertShippedHalfMurph()

        try DefaultTemplateMigration.runIfNeeded(context: context, defaults: defaults)

        let half = try XCTUnwrap(fetchTemplate(named: "Half Murph"))
        XCTAssertEqual(half.name, "Half Murph")
        XCTAssertEqual(half.runDistanceMiles, 0.5)
        XCTAssertEqual(half.totalPullUps, 50)
        XCTAssertEqual(half.totalPushUps, 100)
        XCTAssertEqual(half.totalSquats, 150)
    }

    func test_leavesUserEditedTemplateAlone() throws {
        // Same name, but the user changed the pull-up count. Not ours to touch.
        context.insert(WorkoutTemplate(
            name: "Half Murph",
            runDistanceMiles: 0.5,
            totalPullUps: 60, totalPushUps: 100, totalSquats: 150,
            rounds: 1
        ))

        try DefaultTemplateMigration.runIfNeeded(context: context, defaults: defaults)

        let half = try XCTUnwrap(fetchTemplate(named: "Half Murph"))
        XCTAssertEqual(half.rounds, 1, "An edited template must not be corrected")
    }

    func test_leavesAlreadyPartitionedTemplateAlone() throws {
        // The user already fixed it themselves, to a different value.
        context.insert(WorkoutTemplate(
            name: "Half Murph",
            runDistanceMiles: 0.5,
            totalPullUps: 50, totalPushUps: 100, totalSquats: 150,
            rounds: 25
        ))

        try DefaultTemplateMigration.runIfNeeded(context: context, defaults: defaults)

        let half = try XCTUnwrap(fetchTemplate(named: "Half Murph"))
        XCTAssertEqual(half.rounds, 25)
    }

    func test_doesNotRunASecondTime() throws {
        insertShippedHalfMurph()
        try DefaultTemplateMigration.runIfNeeded(context: context, defaults: defaults)

        // Simulate the user deliberately setting it back to straight sets.
        let half = try XCTUnwrap(fetchTemplate(named: "Half Murph"))
        half.rounds = 1
        try context.save()

        try DefaultTemplateMigration.runIfNeeded(context: context, defaults: defaults)

        XCTAssertEqual(half.rounds, 1, "Migration must be one-shot, not re-applied every launch")
    }

    func test_setsFlagEvenWhenNothingMatched() throws {
        try DefaultTemplateMigration.runIfNeeded(context: context, defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: DefaultTemplateMigration.flagKey))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/DefaultTemplateMigrationTests`

Expected: compile failure — `cannot find 'DefaultTemplateMigration' in scope`.

- [ ] **Step 3: Write the migration**

Create `MurphPlus/Persistence/DefaultTemplateMigration.swift`:

```swift
// MurphPlus/Persistence/DefaultTemplateMigration.swift
import Foundation
import SwiftData

/// One-time correction for the Half/Mini Murph starter templates, which
/// shipped as straight sets (`rounds: 1`) but are Cindy-style in practice.
///
/// This exists because `DefaultTemplates.seedIfNeeded` returns early on a
/// non-empty store: changing the seed constants alone fixes nothing on any
/// install that has already run once, including every TestFlight build.
///
/// A template is corrected only if it still matches the shipped default in
/// every field. Any difference means the user edited it, and an edited
/// template is left completely alone.
enum DefaultTemplateMigration {
    static let flagKey = "didCorrectDefaultTemplateRounds"

    struct Correction {
        let name: String
        let runDistanceMiles: Double
        let totalPullUps: Int
        let totalPushUps: Int
        let totalSquats: Int
        let correctedRounds: Int
    }

    /// Both templates' rep totals divide exactly into Cindy 5/10/15 sets.
    static let corrections: [Correction] = [
        Correction(name: "Half Murph", runDistanceMiles: 0.5,
                   totalPullUps: 50, totalPushUps: 100, totalSquats: 150,
                   correctedRounds: 10),
        Correction(name: "Mini Murph", runDistanceMiles: 0.25,
                   totalPullUps: 25, totalPushUps: 50, totalSquats: 75,
                   correctedRounds: 5),
    ]

    static func runIfNeeded(context: ModelContext, defaults: UserDefaults = .standard) throws {
        guard !defaults.bool(forKey: flagKey) else { return }

        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        for correction in corrections {
            for template in templates where matchesAsShipped(template, correction) {
                template.rounds = correction.correctedRounds
            }
        }
        try context.save()

        // Set the flag unconditionally, including when nothing matched — a
        // fresh install seeds the corrected values directly and must never
        // re-enter this path on a later launch.
        defaults.set(true, forKey: flagKey)
    }

    private static func matchesAsShipped(_ template: WorkoutTemplate, _ correction: Correction) -> Bool {
        template.name == correction.name
            && template.rounds == 1
            && template.runDistanceMiles == correction.runDistanceMiles
            && template.totalPullUps == correction.totalPullUps
            && template.totalPushUps == correction.totalPushUps
            && template.totalSquats == correction.totalSquats
    }
}
```

- [ ] **Step 4: Correct the seed values**

In `MurphPlus/Persistence/DefaultTemplates.swift`, change `rounds: 1` to `rounds: 10` on `halfMurph` and `rounds: 1` to `rounds: 5` on `miniMurph`. Leave every other field, and both names, exactly as they are.

- [ ] **Step 5: Update the seed test**

In `MurphPlusTests/DefaultTemplatesTests.swift`, add:

```swift
    func test_seedsHalfAndMiniMurphAsCindyStyle() throws {
        try DefaultTemplates.seedIfNeeded(context: context)

        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let half = try XCTUnwrap(templates.first { $0.name == "Half Murph" })
        let mini = try XCTUnwrap(templates.first { $0.name == "Mini Murph" })

        XCTAssertEqual(half.rounds, 10)
        XCTAssertEqual(mini.rounds, 5)
        // Both partition into the same 5/10/15 Cindy set.
        XCTAssertEqual(half.pullUpsPerRound, 5)
        XCTAssertEqual(mini.pullUpsPerRound, 5)
    }
```

If the existing test file's `context` property or setup differs, match its
existing conventions rather than introducing a second style.

- [ ] **Step 6: Wire the migration into launch**

In `MurphPlus/MurphPlusApp.swift`, immediately after the existing
`try? DefaultTemplates.seedIfNeeded(context: container.mainContext)` line (line 19), add:

```swift
        try? DefaultTemplateMigration.runIfNeeded(context: container.mainContext)
```

`try?` matches the existing seeding call's error posture: a failed correction
must not prevent the app from launching.

- [ ] **Step 7: Regenerate and run the full suite**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add MurphPlus/Persistence/DefaultTemplateMigration.swift \
        MurphPlus/Persistence/DefaultTemplates.swift \
        MurphPlus/MurphPlusApp.swift \
        MurphPlusTests/DefaultTemplateMigrationTests.swift \
        MurphPlusTests/DefaultTemplatesTests.swift
git commit -m "fix: make Half and Mini Murph templates Cindy-style

Both shipped as straight sets. Their rep totals divide exactly into
5/10/15 sets — Half over 10 rounds, Mini over 5.

seedIfNeeded returns early on a non-empty store, so the seed change
alone fixes no existing install. A one-shot migration corrects records
still matching the shipped defaults exactly, and leaves any template
the user has edited completely alone."
```

---

### Task 2: Abandoned-session progress describer

Pure string derivation, no SwiftData, no UI. Task 3 consumes it.

**Files:**
- Create: `MurphPlus/Support/SessionProgressDescriber.swift`
- Test: `MurphPlusTests/SessionProgressDescriberTests.swift`

**Interfaces:**
- Consumes: `SessionPhase` (existing enum in `MurphPlus/Models/SessionEnums.swift`).
- Produces:
  - `SessionProgressDescriber.describe(phase:roundsCompleted:totalRounds:repsPerRound:) -> String?`
  - `SessionProgressDescriber.shortDescription(phase:roundsCompleted:totalRounds:) -> String?`
  - Both return `nil` for `.completed`. Task 3 calls both.

- [ ] **Step 1: Write the failing tests**

Create `MurphPlusTests/SessionProgressDescriberTests.swift`:

```swift
// MurphPlusTests/SessionProgressDescriberTests.swift
import XCTest
@testable import MurphPlus

final class SessionProgressDescriberTests: XCTestCase {

    // MARK: - Long form (session detail)

    func test_describe_midRounds_namesRoundsAndReps() {
        let text = SessionProgressDescriber.describe(
            phase: .rounds, roundsCompleted: 15, totalRounds: 20, repsPerRound: 30
        )

        XCTAssertEqual(text, "Stopped during rounds · 15 of 20 · 450 of 600 reps")
    }

    func test_describe_duringRun1_omitsRoundsEntirely() {
        let text = SessionProgressDescriber.describe(
            phase: .run1, roundsCompleted: 0, totalRounds: 20, repsPerRound: 30
        )

        // "0 of 20 rounds" is noise when the user never reached the rounds.
        XCTAssertEqual(text, "Stopped during run 1")
    }

    func test_describe_duringRun2_notesAllRoundsDone() {
        let text = SessionProgressDescriber.describe(
            phase: .run2, roundsCompleted: 20, totalRounds: 20, repsPerRound: 30
        )

        XCTAssertEqual(text, "Stopped during run 2 · all 20 rounds complete")
    }

    func test_describe_beforeStarting() {
        let text = SessionProgressDescriber.describe(
            phase: .notStarted, roundsCompleted: 0, totalRounds: 20, repsPerRound: 30
        )

        XCTAssertEqual(text, "Stopped before starting")
    }

    func test_describe_completedSessionHasNoProgressLine() {
        let text = SessionProgressDescriber.describe(
            phase: .completed, roundsCompleted: 20, totalRounds: 20, repsPerRound: 30
        )

        XCTAssertNil(text, "A finished session is described by its time, not its progress")
    }

    func test_describe_straightSetsSessionStillReadsSensibly() {
        let text = SessionProgressDescriber.describe(
            phase: .rounds, roundsCompleted: 0, totalRounds: 1, repsPerRound: 600
        )

        XCTAssertEqual(text, "Stopped during rounds · 0 of 1 · 0 of 600 reps")
    }

    // MARK: - Short form (history row)

    func test_shortDescription_midRounds() {
        XCTAssertEqual(
            SessionProgressDescriber.shortDescription(phase: .rounds, roundsCompleted: 15, totalRounds: 20),
            "15/20 rounds"
        )
    }

    func test_shortDescription_duringRuns() {
        XCTAssertEqual(
            SessionProgressDescriber.shortDescription(phase: .run1, roundsCompleted: 0, totalRounds: 20),
            "Run 1"
        )
        XCTAssertEqual(
            SessionProgressDescriber.shortDescription(phase: .run2, roundsCompleted: 20, totalRounds: 20),
            "Run 2"
        )
    }

    func test_shortDescription_completedIsNil() {
        XCTAssertNil(
            SessionProgressDescriber.shortDescription(phase: .completed, roundsCompleted: 20, totalRounds: 20)
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/SessionProgressDescriberTests`

Expected: compile failure — `cannot find 'SessionProgressDescriber' in scope`.

- [ ] **Step 3: Write the describer**

Create `MurphPlus/Support/SessionProgressDescriber.swift`:

```swift
// MurphPlus/Support/SessionProgressDescriber.swift
import Foundation

/// "How far did this attempt get" copy for an abandoned session.
///
/// Abandoning retains every logged `RoundLog` and `RunSplit` and leaves
/// `completedRounds` intact, so a stopped attempt is already a complete
/// partial record — it was simply never displayed as one. This turns that
/// stored progress into the strings the history row and detail screen show.
///
/// Both functions return `nil` for a completed session, which is described
/// by its finishing time rather than by how far it got.
enum SessionProgressDescriber {

    /// Long form, for the session detail screen.
    static func describe(
        phase: SessionPhase,
        roundsCompleted: Int,
        totalRounds: Int,
        repsPerRound: Int
    ) -> String? {
        switch phase {
        case .completed:
            return nil
        case .notStarted:
            return "Stopped before starting"
        case .run1:
            // Rounds hadn't begun; "0 of 20" would be noise, not information.
            return "Stopped during run 1"
        case .rounds:
            let reps = roundsCompleted * repsPerRound
            let totalReps = totalRounds * repsPerRound
            return "Stopped during rounds · \(roundsCompleted) of \(totalRounds) · \(reps) of \(totalReps) reps"
        case .run2:
            return "Stopped during run 2 · all \(totalRounds) rounds complete"
        }
    }

    /// Short form, for the history list row.
    static func shortDescription(
        phase: SessionPhase,
        roundsCompleted: Int,
        totalRounds: Int
    ) -> String? {
        switch phase {
        case .completed: return nil
        case .notStarted: return "Not started"
        case .run1: return "Run 1"
        case .rounds: return "\(roundsCompleted)/\(totalRounds) rounds"
        case .run2: return "Run 2"
        }
    }
}
```

- [ ] **Step 4: Regenerate and run tests**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/SessionProgressDescriberTests`

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MurphPlus/Support/SessionProgressDescriber.swift \
        MurphPlusTests/SessionProgressDescriberTests.swift
git commit -m "feat: add progress describer for abandoned sessions"
```

---

### Task 3: Surface abandoned progress in history and detail

**Files:**
- Modify: `MurphPlus/Views/History/SessionDetailView.swift:64` and `:136-145`
- Modify: `MurphPlus/DesignSystem/Components/MurphSessionRow.swift:1-4` and `:44-52`
- Modify: `MurphPlus/Views/History/HistoryView.swift` (the `MurphSessionRow` call site)

**Interfaces:**
- Consumes: `SessionProgressDescriber.describe(...)` and `.shortDescription(...)` from Task 2.
- Produces: `MurphSessionRow` gains `var progressLabel: String? = nil`. Defaulted, so existing call sites compile unchanged.

- [ ] **Step 1: Show the real stopped-at time in the summary card**

In `SessionDetailView.swift`, replace the `else` branch of `summaryCard`
(currently `MurphStatTile(label: "Total time", value: "\u{2014}", caption: "Abandoned before finishing")`):

```swift
                } else {
                    // Both startedAt and completedAt are set on abandon, so this
                    // duration is real — the em-dash it replaced was discarding
                    // data the session already had.
                    MurphClock(label: "Stopped at", seconds: session.totalElapsedSeconds ?? 0, size: .md)
                }
```

- [ ] **Step 2: Add the progress line**

In `SessionDetailView.swift`, add this computed property alongside the other
private view properties:

```swift
    @ViewBuilder
    private var progressLine: some View {
        if let text = SessionProgressDescriber.describe(
            phase: session.phase,
            roundsCompleted: session.completedRounds,
            totalRounds: session.template?.rounds ?? 0,
            repsPerRound: session.template?.repsPerRound ?? 0
        ) {
            Text(text)
                .murphType(.bodySm)
                .foregroundStyle(MurphColor.textMuted)
        }
    }
```

Then insert it into the main `VStack` immediately after `summaryCard` (line 64):

```swift
                    header
                    summaryCard
                    progressLine
                    if run1 != nil || run2 != nil { splitsSection }
```

`progressLine` renders nothing for a completed session, because `describe`
returns `nil` for `.completed`.

- [ ] **Step 3: Add the optional progress label to the history row**

In `MurphSessionRow.swift`, add the property after `isCompleted`:

```swift
    var progressLabel: String? = nil
```

Then in the trailing `VStack`, add the label beneath the badge:

```swift
                    if isCompleted, let time {
                        Text(time)
                            .murphType(.metric(17))
                            .foregroundStyle(MurphColor.textPrimary)
                    } else {
                        MurphBadge(tone: .abandoned, title: "Abandoned")
                        if let progressLabel {
                            Text(progressLabel)
                                .murphType(.bodySm)
                                .foregroundStyle(MurphColor.textMuted)
                        }
                    }
```

Update the file's header comment, which currently states the old intent:

```swift
// MurphPlus/DesignSystem/Components/MurphSessionRow.swift
// History list row. Left bar is lime for completed, dust for abandoned
// (components/data/SessionRow.jsx). Abandoned rows show a dust "Abandoned"
// badge and how far the attempt got — never a fabricated duration.
```

- [ ] **Step 4: Pass the label from the history list**

In `HistoryView.swift`, at the `MurphSessionRow(...)` call site, add:

```swift
                        progressLabel: SessionProgressDescriber.shortDescription(
                            phase: session.phase,
                            roundsCompleted: session.completedRounds,
                            totalRounds: session.template?.rounds ?? 0
                        ),
```

Place it after the `isCompleted:` argument to match the property order in the
struct. Adjust the local variable name if the call site binds the session
under a different name.

- [ ] **Step 5: Build and run the full suite**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Verify by hand in the simulator**

Start a session against a multi-round template, complete run 1 and two rounds,
then abandon. Confirm: History shows the "Abandoned" badge **with** `2/20 rounds`
beneath it; the detail screen shows a real stopped-at time instead of an
em-dash, and the line `Stopped during rounds · 2 of 20 · … reps`. Confirm a
completed session shows neither the progress line nor a progress label.

- [ ] **Step 7: Commit**

```bash
git add MurphPlus/Views/History/SessionDetailView.swift \
        MurphPlus/Views/History/HistoryView.swift \
        MurphPlus/DesignSystem/Components/MurphSessionRow.swift
git commit -m "fix: show how far abandoned sessions got

Abandoning already retained every round log and split, and set
completedAt — so both the em-dash total time and the bare Abandoned
badge were discarding data the session had. Detail now shows the real
stopped-at time plus phase, rounds and reps reached; the history row
carries the round progress."
```

---

### Task 4: Live session toolbar rework and start screen title

Two reported problems, one fix: the toolbar slot holds a button that is dead
for the entire workout, while a destructive button sits in the thumb zone
directly under the one the user taps twenty times. Giving the toolbar slot to
Abandon during a session solves both.

**Files:**
- Modify: `MurphPlus/Views/Session/LiveSessionView.swift:52-58` and `:112-121`
- Modify: `MurphPlus/Views/Start/StartView.swift:18`

**Interfaces:**
- Consumes: existing `MurphButton`, `MurphIconButton`, `showAbandonConfirm` state, `onFinished()` callback. Nothing new.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Replace the toolbar item**

In `LiveSessionView.swift`, replace the `.toolbar { ... }` block (lines 52–58):

```swift
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // One slot, two phases. During a session it carries Abandon,
                    // which keeps the destructive action out of the thumb zone
                    // under "Round Done". At completion it becomes Close.
                    // Previously this held a Close button that was disabled —
                    // and so visibly inert — for the entire workout.
                    if phase == .completed {
                        MurphIconButton(label: "Close", systemImage: "xmark") {
                            onFinished()
                        }
                    } else {
                        MurphButton(variant: .danger, size: .sm, title: "Abandon") {
                            showAbandonConfirm = true
                        }
                    }
                }
            }
```

- [ ] **Step 2: Remove Abandon from the bottom action stack**

In `LiveSessionView.swift`, in the bottom `VStack` (lines 112–121), delete the
`if phase != .completed { MurphButton(variant: .danger, ...) }` block entirely,
leaving only the primary action:

```swift
            VStack(spacing: MurphSpacing.space3) {
                MurphButton(variant: .primary, size: .lg, full: true, icon: Image(systemName: copy.icon), title: copy.action) {
                    advance()
                }
            }
```

Leave the surrounding `.padding(...)` and `.overlay(alignment: .top)` modifiers
untouched. Do **not** remove `@State private var showAbandonConfirm` or the
`MurphDialog` block at lines 33–48 — the toolbar button now drives them.

- [ ] **Step 3: Fix the start screen title**

In `StartView.swift:18`, change:

```swift
                    MurphScreenTitle(title: "Murph+")
```

- [ ] **Step 4: Build and run the full suite**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Verify by hand in the simulator**

Confirm: the start screen reads `Murph+`. Start a session — the toolbar shows
an enabled **Abandon** that opens the confirm dialog, and the bottom of the
screen holds only the primary action. Cancel the dialog, finish the session —
the toolbar becomes an enabled **Close** (`xmark`) that dismisses. Confirm no
disabled, dimmed button appears at any point.

- [ ] **Step 6: Commit**

```bash
git add MurphPlus/Views/Session/LiveSessionView.swift \
        MurphPlus/Views/Start/StartView.swift
git commit -m "fix: rework live session chrome and start screen title

The toolbar Close button was disabled for the whole workout, so it read
as a control that did nothing. Abandon meanwhile sat one space3 gap
below Round Done, in the thumb zone. Abandon now owns the toolbar slot
during a session and Close takes it at completion, which fixes both.

Start screen title is the app's name, not an instruction."
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| 1. Inert close button + misplaced Abandon | Task 4 |
| 2. Half/Mini Cindy-style + migration | Task 1 |
| 3. Abandoned sessions show progress | Tasks 2, 3 |
| 4. Start screen title | Task 4 |
| Testing: migration cases | Task 1, Step 1 (six cases incl. edited, already-partitioned, idempotence) |
| Testing: progress boundary cases | Task 2, Step 1 (run 1, mid-rounds, run 2, not-started, completed) |
| Testing: three visual changes by hand | Tasks 3 and 4, verification steps |

No gaps.

**Placeholder scan:** No TBD/TODO. Every code step carries actual code. The
one instruction without a literal diff is Task 1 Step 4 (changing two integer
literals in `DefaultTemplates.swift`), which names the exact fields and values.

**Type consistency:** `SessionProgressDescriber.describe(phase:roundsCompleted:totalRounds:repsPerRound:)`
and `.shortDescription(phase:roundsCompleted:totalRounds:)` are defined in Task 2
and called with those exact labels in Task 3. `MurphSessionRow.progressLabel`
is declared and consumed in the same task. `DefaultTemplateMigration.flagKey`
is referenced by the test written in Task 1 Step 1 and defined in Step 3.
`repsPerRound` and `rounds` exist on `WorkoutTemplate` today; `phase` and
`completedRounds` exist on `MurphSession` today.
