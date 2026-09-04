# Watch Stage 3 Review Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the ten defects a high-effort code review found across PR #1 (Watch
Stage 3), so the watch-to-phone sync can be merged without known data loss.

**Architecture:** Nine tasks in dependency order, blockers first. Tasks 1–4 fix
paths where a workout is silently lost or the phone becomes unusable; Tasks 5–7
fix state that leaks between sessions; Tasks 8–9 fix a broken preview and the
transfer-size ceiling. Each task is independently testable and commits on its own.

**Tech Stack:** Swift 5, SwiftUI, SwiftData, HealthKit, WatchConnectivity,
XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-03-murph-plus-watch-design.md`
**Stage 3 plan:** `docs/superpowers/plans/2026-09-03-murph-plus-watch-stage-3-sync.md`
**Handoff:** `docs/superpowers/handoffs/2026-09-04-watch-stage-3-handoff.md`

---

## Where things stand (read this first after a reboot)

- **Worktree:** `/Users/nemeth/Documents/Claude/Projects/murph-plus/.claude/worktrees/watch-stage-3`
  on branch `worktree-watch-stage-3`. Working tree was clean at handoff.
- **PR #1 is open:** https://github.com/projectnemeth/murph-plus/pull/1
  (`worktree-watch-stage-3` → `main`, 12 commits). **Do not merge it** until
  Tasks 1–4 below are done.
- **Baseline:** iOS **227 tests / 0 failures**; watch **BUILD SUCCEEDED**. Any
  task that leaves those worse has regressed something.
- Stage 3 Tasks 1–6 are complete. **Stage 3 Task 7 (hardware verification) is
  still not done** and is unrelated to this plan — it needs a physically paired
  iPhone and Apple Watch. See the handoff doc.
- The SDD briefs under `.superpowers/sdd/` are **gitignored** — they exist only
  in this worktree on this machine. Do not delete the worktree.

## Global Constraints

- **Regenerate the project after adding any file:** `xcodegen generate`.
  `MurphPlus.xcodeproj` is gitignored and generated; a new `.swift` file that
  is not regenerated is silently not compiled.
- **iOS test command:**
  `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
  Expected: `** TEST SUCCEEDED **`
- **Watch build command:**
  `xcodebuild build -scheme MurphPlusWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' -project MurphPlus.xcodeproj`
  Expected: `** BUILD SUCCEEDED **`
- **Never build the watch with `-destination 'generic/platform=watchOS'`.** It
  fails with "Signing for MurphPlusWatch requires a development team" — a
  signing error, not a code error. Several older task briefs quote that form.
- **TDD is required.** Every task writes a failing test first and watches it
  fail before implementing. Use `superpowers:test-driven-development`.
- **Single-writer is the design invariant.** The device that owns a session is
  its only writer. No fix may introduce a second writer.
- **The merge rule is strictly-greater** (`SessionMerge.shouldApply`). Any change
  to checkpoint numbering must preserve monotonicity across app launches.
- The watch target compiles only `MurphPlus/DesignSystem/Foundations`, not
  `Components`. `MurphBadge`/`MurphBanner`/`MurphSplitRow` do **not** exist on
  the watch.

## File Structure

| File | Responsibility | Tasks |
|---|---|---|
| `MurphPlusWatch/Session/WatchSessionController.swift` | Session ownership, journal, emit | 1, 3, 9 |
| `MurphPlus/Sync/LiveMirrorStore.swift` | In-memory mirror of a watch session | 2 |
| `MurphPlus/Views/Start/StartView.swift` | Start guard, Begin button, preview | 2, 8 |
| `MurphPlus/Persistence/StuckWatchSessionReaper.swift` *(new)* | Abandon watch sessions the phone can no longer reach | 4 |
| `MurphPlus/Views/History/HistoryView.swift` | Surfaces the stuck-session affordance | 4 |
| `MurphPlus/Sync/SessionImporter.swift` | Checkpoint → SwiftData; template resolution | 5 |
| `MurphPlusWatch/Views/WatchSetupView.swift` | Starter templates, selection | 5, 6 |
| `MurphPlus/Sync/PhoneSyncCoordinator.swift` | WCSession delegate, ingest, context push | 7, 9 |
| `MurphPlusWatch/Sync/WatchSyncCoordinator.swift` | WCSession transport, transfer errors | 9 |

---

### Task 1: Restore the checkpoint sequence on resume

**Severity: CRITICAL — silent loss of an entire workout.**

`checkpointSeq` is instance state on a controller rebuilt at every watch-app
launch, but `resumeExistingSession()` restores a journal with the *same*
`sessionID`. The phone has already stored `lastCheckpointSeq = N` from before
the crash. After resume the watch numbers checkpoints 1, 2, 3…, the
strictly-greater merge rule rejects every one of them — including the
`.runFinished(2)` that marks the session complete — and the phone's copy stays
`.inProgress` forever, which `HistoryView` filters out of history entirely.

**Files:**
- Modify: `MurphPlusWatch/Session/WatchSessionController.swift:35` (the counter),
  `:113` (`resumeExistingSession`)
- Test: `MurphPlusTests/WatchSyncEmissionTests.swift`

**Interfaces:**
- Consumes: `SessionJournal.events`, `SessionEvent.isHeartRate`
- Produces: no new API; `checkpointSeq` continues from the replayed journal

- [ ] **Step 1: Write the failing test**

Add to `MurphPlusTests/WatchSyncEmissionTests.swift`:

```swift
    /// A relaunch mid-session rebuilds the controller, but the phone still holds
    /// the checkpoint sequence from before the crash. Restarting the count at 1
    /// makes every post-resume checkpoint fail the strictly-greater merge rule,
    /// so the second half of the workout — and the event that marks it complete —
    /// never lands.
    func test_resumingContinuesTheCheckpointSequenceRatherThanRestartingIt() async throws {
        await start()
        controller.advance()                       // finishes run 1
        controller.advance()                       // logs round 1
        let beforeCrash = try XCTUnwrap(transport.checkpoints.last).checkpointSeq
        XCTAssertEqual(beforeCrash, 3)

        // A relaunch: brand-new controller and transport over the same journal.
        let resumedTransport = FakeSessionTransport()
        let resumed = WatchSessionController(
            workout: FakeWorkoutController(),
            journalDirectory: directory,
            transport: resumedTransport
        )
        let didResume = try await resumed.resumeExistingSession()
        XCTAssertTrue(didResume, "The journal on disk must be resumable")

        resumed.advance()                          // logs round 2

        let afterResume = try XCTUnwrap(resumedTransport.checkpoints.last).checkpointSeq
        XCTAssertGreaterThan(
            afterResume, beforeCrash,
            "A post-resume checkpoint must outrank the last one the phone stored"
        )
    }
```

- [ ] **Step 2: Run the test and watch it fail**

Run the iOS test command. Expected: FAIL — `afterResume` is 1, not greater than 3.

- [ ] **Step 3: Restore the counter when resuming**

In `WatchSessionController.resumeExistingSession()`, immediately after
`journal = found` and `state = found.state`, add:

```swift
        // Continue the sequence the phone has already seen rather than
        // restarting it. Every non-heart-rate event in the replayed journal
        // produced exactly one checkpoint before the relaunch (see `emit`), so
        // counting them reproduces the last sequence number sent. Restarting at
        // 1 would make every checkpoint from here fail `SessionMerge`'s
        // strictly-greater test, and the phone would keep the pre-crash copy
        // forever — stuck `.inProgress`, and so hidden from history.
        checkpointSeq = found.events.filter { !$0.isHeartRate }.count
```

- [ ] **Step 4: Run the test and watch it pass**

Run the iOS test command. Expected: `** TEST SUCCEEDED **`, 228 tests.

- [ ] **Step 5: Commit**

```bash
git add MurphPlusWatch/Session/WatchSessionController.swift MurphPlusTests/WatchSyncEmissionTests.swift
git commit -m "fix: continue the checkpoint sequence across a watch relaunch"
```

---

### Task 2: Make the mirror expire, and refuse post-terminal events

**Severity: CRITICAL — the phone loses its Begin button permanently.**

Two defects in one file, fixed together because the second one re-creates the
first. (a) `isMirroring` consults only `state != nil && !isTerminal`; nothing
clears the mirror when the link dies, so a flat watch battery or a walk out of
range hides the phone's Begin button for the life of the process. (b) `receive`
clears on terminal, setting `sessionID = nil`; a later heart-rate event for the
same workout then takes the "different session" branch and installs a *fresh
empty* state — non-terminal, so the phone flips back into mirroring and shows a
live 00:00 clock. Heart rate genuinely does arrive after the terminal event:
`attachHeartRateHandler` guards only on `isPaused`, and `workout.finish()` is
awaited asynchronously.

**Files:**
- Modify: `MurphPlus/Sync/LiveMirrorStore.swift:30` (`isMirroring`), `:38` (`receive`)
- Modify: `MurphPlus/Views/Start/StartView.swift:26`
- Test: `MurphPlusTests/LiveMirrorStoreTests.swift`

**Interfaces:**
- Produces: `LiveMirrorStore.isMirroring` now returns `false` once stale;
  `LiveMirrorStore.receive(sessionID:event:)` ignores events for a session it
  has already seen end.

- [ ] **Step 1: Write the failing tests**

Add to `MurphPlusTests/LiveMirrorStoreTests.swift`:

```swift
    /// A watch whose battery dies sends no terminal event — it simply stops.
    /// If the mirror never expires, `StartView` hides Begin forever and the
    /// phone can never start a workout again.
    func test_aMirrorThatHasGoneStaleIsNoLongerMirroring() {
        let store = LiveMirrorStore(staleAfter: 0.05)
        store.receive(sessionID: UUID(), event: started(t(0)))
        XCTAssertTrue(store.isMirroring)

        Thread.sleep(forTimeInterval: 0.1)

        XCTAssertTrue(store.isStale)
        XCTAssertFalse(store.isMirroring, "A dead link must release the Start screen")
    }

    /// Heart rate keeps arriving after the workout ends: the handler guards
    /// only on `isPaused`, and HealthKit's `finish()` is awaited asynchronously.
    /// Without a guard the first straggler re-opens the mirror as an empty
    /// session and the phone shows a live 00:00 clock for a finished workout.
    func test_anEventArrivingAfterTheSessionEndedDoesNotReopenTheMirror() {
        let store = LiveMirrorStore()
        let id = UUID()
        store.receive(sessionID: id, event: started(t(0)))
        store.receive(sessionID: id, event: .abandoned(at: t(60)))
        XCTAssertFalse(store.isMirroring)

        store.receive(sessionID: id, event: .heartRate(bpm: 140, at: t(61)))

        XCTAssertNil(store.state, "A finished session must stay finished")
        XCTAssertFalse(store.isMirroring)
    }

    /// But a genuinely new workout must still be able to start mirroring.
    func test_aNewSessionAfterAFinishedOneStillMirrors() {
        let store = LiveMirrorStore()
        let first = UUID()
        store.receive(sessionID: first, event: started(t(0)))
        store.receive(sessionID: first, event: .abandoned(at: t(60)))

        let second = UUID()
        store.receive(sessionID: second, event: started(t(100)))

        XCTAssertTrue(store.isMirroring)
        XCTAssertEqual(store.sessionID, second)
    }
```

- [ ] **Step 2: Run the tests and watch them fail**

Run the iOS test command. Expected: FAIL — no `staleAfter:` initialiser, and the
post-terminal event re-opens the mirror.

- [ ] **Step 3: Implement**

Replace the body of `LiveMirrorStore` above `clear()` with:

```swift
    private(set) var sessionID: UUID?
    private(set) var state: SessionState?
    private(set) var lastUpdate: Date?

    /// Sessions already seen to completion. Heart rate keeps arriving for a
    /// short while after the terminal event, and without this the first
    /// straggler would be read as a brand-new workout.
    private var finished: Set<UUID> = []

    private let staleAfter: TimeInterval

    init(staleAfter: TimeInterval = 10) {
        self.staleAfter = staleAfter
    }

    var isStale: Bool {
        guard let lastUpdate else { return true }
        return Date.now.timeIntervalSince(lastUpdate) > staleAfter
    }

    /// Deliberately consults `isStale`. A watch that runs out of battery sends
    /// no terminal event, it just stops; without the staleness test the mirror
    /// would claim a session is live forever and `StartView` would never give
    /// the Begin button back.
    var isMirroring: Bool {
        guard let state, !state.isTerminal else { return false }
        return !isStale
    }

    func receive(sessionID: UUID, event: SessionEvent) {
        guard !finished.contains(sessionID) else { return }

        if self.sessionID != sessionID {
            self.sessionID = sessionID
            self.state = SessionState()
        }
        state?.apply(event)
        lastUpdate = .now

        if state?.isTerminal == true {
            finished.insert(sessionID)
            clear()
        }
    }
```

- [ ] **Step 4: Make the Start screen re-evaluate on a timer**

`isStale` is time-derived, so `@Observable` will not re-render when it flips.
In `MurphPlus/Views/Start/StartView.swift`, wrap the guarded block so it
re-evaluates once a second:

```swift
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            if sync.mirror.isMirroring {
                                // ... existing NavigationLink + MurphBanner ...
                            } else {
                                // ... existing MurphButton "Begin" ...
                            }
                        }
```

- [ ] **Step 5: Run the tests and the watch build**

Run the iOS test command and the watch build command.
Expected: `** TEST SUCCEEDED **` (230 tests) and `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add MurphPlus/Sync/LiveMirrorStore.swift MurphPlus/Views/Start/StartView.swift MurphPlusTests/LiveMirrorStoreTests.swift
git commit -m "fix: expire the live mirror and ignore post-terminal events"
```

---

### Task 3: Sync an abandoned resumable session

**Severity: HIGH — leaves a permanently stuck session on the phone.**

`abandonResumableSession()` appends `.abandoned` straight to the journal via
`found.append(event)` rather than through `record(_:)`, so `emit` never runs and
no checkpoint is sent. The phone has already received checkpoints for that
session and keeps it `.inProgress` forever.

**Files:**
- Modify: `MurphPlusWatch/Session/WatchSessionController.swift:323`
- Test: `MurphPlusTests/WatchSyncEmissionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
    /// Discarding a recovered session must tell the phone. The phone already
    /// holds checkpoints for it, so without a final checkpoint it keeps the
    /// session `.inProgress` forever — hidden from history and (before the
    /// reaper) unreachable.
    func test_abandoningARecoveredSessionSendsAFinalCheckpoint() async throws {
        await start()
        controller.advance()
        let sessionID = try XCTUnwrap(controller.journal?.sessionID)

        let relaunchTransport = FakeSessionTransport()
        let relaunched = WatchSessionController(
            workout: FakeWorkoutController(),
            journalDirectory: directory,
            transport: relaunchTransport
        )
        relaunched.abandonResumableSession()

        let final = try XCTUnwrap(relaunchTransport.checkpoints.last)
        XCTAssertEqual(final.sessionID, sessionID)
        XCTAssertTrue(
            SessionState.replay(final.events).isTerminal,
            "The phone must be told the session ended"
        )
    }
```

- [ ] **Step 2: Run it and watch it fail**

Expected: FAIL — `relaunchTransport.checkpoints` is empty.

- [ ] **Step 3: Implement**

At the end of `abandonResumableSession()`, before the `if !wrote ||` cleanup,
send a final checkpoint built from the journal now on disk:

```swift
        // The phone already holds checkpoints for this session, so it has to be
        // told the session ended. This path deliberately does not go through
        // `record(_:)` — that mutates `state`, and this controller is not the
        // one running the session — so the checkpoint is sent directly.
        if found.state.isTerminal, let transport {
            checkpointSeq = found.events.filter { !$0.isHeartRate }.count
            transport.transferCheckpoint(SyncPayload(
                sessionID: found.sessionID,
                checkpointSeq: checkpointSeq,
                origin: .watch,
                events: found.events
            ))
        }
```

- [ ] **Step 4: Run the tests**

Expected: `** TEST SUCCEEDED **`, 231 tests.

- [ ] **Step 5: Commit**

```bash
git add MurphPlusWatch/Session/WatchSessionController.swift MurphPlusTests/WatchSyncEmissionTests.swift
git commit -m "fix: tell the phone when a recovered watch session is discarded"
```

---

### Task 4: Give stuck watch-owned sessions an exit

**Severity: HIGH — currently indistinguishable from data loss.**

A watch-owned `.inProgress` session is unreachable from the phone: the origin
filter added to `ResumableSessionFinder` keeps it out of the resume prompt,
`HistoryView` filters `.inProgress` out, and `NeverStartedSessionPurger` only
deletes rows with `startedAt == nil`, which imported sessions never have. The
comment says "the phone's answer is abandon, never resume" — but no abandon
affordance exists.

**Files:**
- Create: `MurphPlus/Persistence/StuckWatchSessionReaper.swift`
- Create: `MurphPlusTests/StuckWatchSessionReaperTests.swift`
- Modify: `MurphPlus/Views/History/HistoryView.swift`

**Interfaces:**
- Produces: `StuckWatchSessionReaper.stuckSessions(context:olderThan:now:) -> [MurphSession]`
  and `StuckWatchSessionReaper.abandon(_:context:)`

- [ ] **Step 1: Write the failing tests**

```swift
// MurphPlusTests/StuckWatchSessionReaperTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

final class StuckWatchSessionReaperTests: XCTestCase {
    private var context: ModelContext!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    @discardableResult
    private func session(origin: SessionOrigin, startedHoursAgo: Double,
                         status: SessionStatus = .inProgress) -> MurphSession {
        let s = MurphSession(date: now, template: nil, vestOn: false)
        s.origin = origin
        s.status = status
        s.startedAt = now.addingTimeInterval(-startedHoursAgo * 3600)
        context.insert(s)
        return s
    }

    /// A Murph takes an hour or two, never twelve. A watch session still
    /// in progress long past any plausible workout is a dead watch.
    func test_findsAWatchSessionStuckWellPastAnyPlausibleWorkout() throws {
        session(origin: .watch, startedHoursAgo: 12)

        let stuck = StuckWatchSessionReaper.stuckSessions(context: context, olderThan: 6 * 3600, now: now)

        XCTAssertEqual(stuck.count, 1)
    }

    func test_leavesAWatchSessionThatCouldStillBeRunning() throws {
        session(origin: .watch, startedHoursAgo: 1)

        XCTAssertTrue(StuckWatchSessionReaper.stuckSessions(context: context, olderThan: 6 * 3600, now: now).isEmpty)
    }

    /// Phone sessions have their own resume prompt; this must not touch them.
    func test_ignoresPhoneOwnedSessions() throws {
        session(origin: .phone, startedHoursAgo: 12)

        XCTAssertTrue(StuckWatchSessionReaper.stuckSessions(context: context, olderThan: 6 * 3600, now: now).isEmpty)
    }

    func test_ignoresSessionsThatAlreadyEnded() throws {
        session(origin: .watch, startedHoursAgo: 12, status: .completed)

        XCTAssertTrue(StuckWatchSessionReaper.stuckSessions(context: context, olderThan: 6 * 3600, now: now).isEmpty)
    }

    /// Abandon, never delete: the rounds the user actually did are real and
    /// belong in history.
    func test_abandoningKeepsTheSessionAndItsProgress() throws {
        let stuck = session(origin: .watch, startedHoursAgo: 12)
        stuck.completedRounds = 8

        StuckWatchSessionReaper.abandon(stuck, context: context)

        XCTAssertEqual(stuck.status, .abandoned)
        XCTAssertEqual(stuck.completedRounds, 8, "The work done is not erased")
        XCTAssertNotNil(stuck.completedAt)
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Expected: FAIL — `cannot find 'StuckWatchSessionReaper' in scope`.

- [ ] **Step 3: Implement the reaper**

```swift
// MurphPlus/Persistence/StuckWatchSessionReaper.swift
import Foundation
import SwiftData

/// Finds Watch-owned sessions the phone can no longer reach, and closes them.
///
/// A Watch session is imported `.inProgress` and only its owner can finish it.
/// If that Watch dies, is force-quit, or never comes back into range, nothing
/// ever moves the session on: `ResumableSessionFinder` excludes it by origin
/// (the phone must not become a second writer), `HistoryView` shows only past
/// sessions, and `NeverStartedSessionPurger` only takes rows that never
/// started. The row is real, holds real rounds, and is invisible — which is
/// indistinguishable from data loss.
///
/// Abandon rather than delete: the rounds the user actually did happened, and
/// `.abandoned` is a status history already renders.
enum StuckWatchSessionReaper {
    /// A Murph takes one to two hours. Six is generous enough that a genuinely
    /// long session is never swept, and short enough that a dead Watch surfaces
    /// the same day.
    static let defaultThreshold: TimeInterval = 6 * 3600

    static func stuckSessions(
        context: ModelContext,
        olderThan threshold: TimeInterval = defaultThreshold,
        now: Date = .now
    ) -> [MurphSession] {
        let inProgressRaw = SessionStatus.inProgress.rawValue
        let watchRaw = SessionOrigin.watch.rawValue
        let descriptor = FetchDescriptor<MurphSession>(
            predicate: #Predicate { $0.statusRaw == inProgressRaw && $0.originRaw == watchRaw }
        )
        guard let candidates = try? context.fetch(descriptor) else { return [] }
        return candidates.filter { session in
            guard let startedAt = session.startedAt else { return false }
            return now.timeIntervalSince(startedAt) > threshold
        }
    }

    static func abandon(_ session: MurphSession, context: ModelContext) {
        session.status = .abandoned
        session.completedAt = session.completedAt ?? .now
        try? context.save()
    }
}
```

- [ ] **Step 4: Run the tests**

Expected: `** TEST SUCCEEDED **`, 236 tests.

- [ ] **Step 5: Surface it in History**

In `MurphPlus/Views/History/HistoryView.swift`, add above the session list a
banner offering the action — matching how `RootTabView` already warns about
stuck phone sessions. Read the file first and follow its existing section
style; the affordance must say what happened and let the user close it:

```swift
    @Environment(\.modelContext) private var context
    @State private var stuck: [MurphSession] = []

    // in the body, above the list:
    if !stuck.isEmpty {
        MurphBanner(
            tone: .warn,
            text: "\(stuck.count) Apple Watch session\(stuck.count == 1 ? "" : "s") never finished. The Watch stopped sending before the workout ended."
        )
        MurphButton(variant: .secondary, full: true, title: "Move to history as abandoned") {
            for session in stuck { StuckWatchSessionReaper.abandon(session, context: context) }
            stuck = StuckWatchSessionReaper.stuckSessions(context: context)
        }
    }

    // and on appear:
    .onAppear { stuck = StuckWatchSessionReaper.stuckSessions(context: context) }
```

- [ ] **Step 6: Run the tests and the watch build**

Expected: `** TEST SUCCEEDED **` and `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
xcodegen generate
git add MurphPlus/Persistence/StuckWatchSessionReaper.swift MurphPlusTests/StuckWatchSessionReaperTests.swift MurphPlus/Views/History/HistoryView.swift
git commit -m "fix: give stranded watch sessions a way out of limbo"
```

---

### Task 5: Stop the importer duplicating starter templates

**Severity: MEDIUM — pollutes the phone's template picker on every watch launch.**

`WatchSetupView.starterTemplates` is a `static let` built with
`TemplateSpec(id: UUID(), …)`, so its ids are regenerated on every watch process
launch. A watch that has not yet received context records against an id the
phone has never seen, and `SessionImporter.resolveTemplate` inserts a rebuilt
`WorkoutTemplate` — a *new* "Full Murph (Straight Sets)" after each relaunch,
all of which appear in the phone's picker.

Two changes: stable ids on the starters, and a shape match in the importer so
existing installs (whose seeded templates already have random ids) do not
duplicate either.

**Files:**
- Modify: `MurphPlusWatch/Views/WatchSetupView.swift` (`starterTemplates`)
- Modify: `MurphPlus/Sync/SessionImporter.swift:79` (`resolveTemplate`)
- Test: `MurphPlusTests/SessionImporterTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
    /// The Watch's built-in starters carry ids the phone has never seen when no
    /// context has synced yet. Rebuilding one must not add a second copy of a
    /// template the phone already has under a different id — that copy shows up
    /// in the Start picker, once per Watch relaunch.
    func test_doesNotDuplicateATemplateThePhoneAlreadyHasByShape() throws {
        let existing = WorkoutTemplate(name: "Half Murph", runDistanceMiles: 0.5,
                                       totalPullUps: 50, totalPushUps: 100,
                                       totalSquats: 150, rounds: 10)
        context.insert(existing)
        try context.save()

        let unknownID = TemplateSpec(id: UUID(), name: "Half Murph", runDistanceMiles: 0.5,
                                     totalPullUps: 50, totalPushUps: 100,
                                     totalSquats: 150, rounds: 10)
        try SessionImporter.apply(payload(template: unknownID), context: context)

        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        XCTAssertEqual(templates.count, 1, "Matched the existing template by shape")
    }

    /// But a genuinely different workout must still be reconstructed.
    func test_stillRebuildsATemplateWhoseShapeIsNew() throws {
        let existing = WorkoutTemplate(name: "Half Murph", runDistanceMiles: 0.5,
                                       totalPullUps: 50, totalPushUps: 100,
                                       totalSquats: 150, rounds: 10)
        context.insert(existing)
        try context.save()

        let different = TemplateSpec(id: UUID(), name: "Quarter Murph", runDistanceMiles: 0.25,
                                     totalPullUps: 25, totalPushUps: 50,
                                     totalSquats: 75, rounds: 5)
        try SessionImporter.apply(payload(template: different), context: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutTemplate>()).count, 2)
    }
```

> Match the existing `payload(template:)` helper in that file; if it is named
> differently, read the file and reuse whatever builds a `SyncPayload` there.

- [ ] **Step 2: Run them and watch the first one fail**

Expected: FAIL — 2 templates, not 1.

- [ ] **Step 3: Match by shape before inserting**

In `SessionImporter.resolveTemplate`, before `context.insert(rebuilt)`:

```swift
        // Fall back to matching on shape. The Watch's starter templates carry
        // ids generated per process launch, and an existing install's seeded
        // templates carry ids from before sync existed — in both cases the id
        // misses but the workout is the one the user already has. Without this
        // the picker gains a duplicate for every Watch relaunch.
        let allTemplates = (try? context.fetch(FetchDescriptor<WorkoutTemplate>())) ?? []
        if let match = allTemplates.first(where: {
            $0.name == spec.name
                && $0.rounds == spec.rounds
                && $0.runDistanceMiles == spec.runDistanceMiles
                && $0.totalPullUps == spec.totalPullUps
                && $0.totalPushUps == spec.totalPushUps
                && $0.totalSquats == spec.totalSquats
        }) {
            return match
        }
```

- [ ] **Step 4: Give the watch starters stable ids**

In `WatchSetupView.starterTemplates`, replace each `id: UUID()` with a fixed
literal so a starter keeps one identity across launches:

```swift
        TemplateSpec(id: UUID(uuidString: "7F3A1C90-0001-4000-A000-000000000001")!, name: "Full Murph (Straight Sets)", …),
        TemplateSpec(id: UUID(uuidString: "7F3A1C90-0002-4000-A000-000000000002")!, name: "Full Murph (Cindy-Style, 20 Rounds)", …),
        TemplateSpec(id: UUID(uuidString: "7F3A1C90-0003-4000-A000-000000000003")!, name: "Half Murph", …),
        TemplateSpec(id: UUID(uuidString: "7F3A1C90-0004-4000-A000-000000000004")!, name: "Mini Murph", …),
```

Keep every other field exactly as it is.

- [ ] **Step 5: Run the tests and the watch build**

Expected: `** TEST SUCCEEDED **` and `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add MurphPlus/Sync/SessionImporter.swift MurphPlusWatch/Views/WatchSetupView.swift MurphPlusTests/SessionImporterTests.swift
git commit -m "fix: stop the importer duplicating the watch's starter templates"
```

---

### Task 6: Reconcile the watch's selected template with the synced list

**Severity: MEDIUM — starts the wrong workout with nothing highlighted.**

`templates` became a computed property in Stage 3 Task 4, but `selected` is
`@State` and is never reconciled. If the user picks a starter before the phone's
context lands, the arriving list replaces the starters: `isSelected` then matches
no row (nothing is highlighted) while Start still launches the now-invisible
starter template.

**Files:**
- Modify: `MurphPlusWatch/Views/WatchSetupView.swift:22`, `:65`, `:136`

- [ ] **Step 1: Add the reconciliation**

`WatchSetupView` has no test bundle, so this is verified by reading and by the
watch build. Add below the `templates` computed property:

```swift
    /// `templates` can change under the user: the phone's list replaces the
    /// starters the moment context arrives. A `selected` that is no longer in
    /// the list highlights no row while still being what Start launches, so
    /// drop it and fall back to the first of whatever is current.
    private var effectiveSelection: TemplateSpec? {
        guard let selected, templates.contains(where: { $0.id == selected.id }) else {
            return templates.first
        }
        return selected
    }
```

- [ ] **Step 2: Use it in both places**

Line ~65 (the Start button) becomes:

```swift
                        guard let spec = effectiveSelection else { return }
```

Line ~136 (`templateRow`) becomes:

```swift
        let isSelected = effectiveSelection?.id == template.id
```

- [ ] **Step 3: Build the watch**

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add MurphPlusWatch/Views/WatchSetupView.swift
git commit -m "fix: drop a watch template selection the synced list no longer has"
```

---

### Task 7: Re-push context after importing a checkpoint

**Severity: LOW — a stale personal best badges a workout that did not beat it.**

`pushContext()` runs on activation and from three phone UI actions, but not
after an import. Watch session A sets a new record and is imported; the watch's
`SyncContext` still holds the old one; watch session B — slower than A but
faster than the old record — badges "Personal best".

**Files:**
- Modify: `MurphPlus/Sync/PhoneSyncCoordinator.swift:57` (`ingest`)

- [ ] **Step 1: Push after a successful import**

At the end of `ingest(_:)`:

```swift
        // A landed session may have set a new record, and the Watch badges its
        // completion screen from this context. Without the push, the next
        // Watch workout is judged against a record it has already been beaten by.
        pushContext()
```

- [ ] **Step 2: Run the tests and the watch build**

Expected: `** TEST SUCCEEDED **` and `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MurphPlus/Sync/PhoneSyncCoordinator.swift
git commit -m "fix: refresh watch context after importing a session"
```

---

### Task 8: Fix the StartView preview

**Severity: LOW — the preview traps, but only in Xcode.**

`StartView` reads `@Environment(PhoneSyncCoordinator.self)`; its `#Preview` at
line 157 supplies only a model container, so rendering it fatal-errors with
"No Observable object of type PhoneSyncCoordinator found."

**Files:**
- Modify: `MurphPlus/Views/Start/StartView.swift:157`

- [ ] **Step 1: Supply the coordinator**

```swift
#Preview {
    let container = try! ModelContainer(
        for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return StartView { _, _, _ in }
        .modelContainer(container)
        .environment(PhoneSyncCoordinator(container: container))
}
```

- [ ] **Step 2: Build and confirm the preview renders in Xcode**

Run the iOS test command (the preview must at least compile), then open
`StartView.swift` in Xcode and resume the canvas.

- [ ] **Step 3: Commit**

```bash
git add MurphPlus/Views/Start/StartView.swift
git commit -m "fix: give the StartView preview its sync coordinator"
```

---

### Task 9: Keep checkpoints under the WatchConnectivity size limit

**Severity: MEDIUM — the final checkpoint of a long workout fails silently.**

`emit` skips *triggering* on heart rate but still sends `journal.events` in
full. At the 5-second throttle a 90-minute Murph journals ~1,080 samples;
at ~46 bytes of JSON each the payload reaches ~50 KB, and a two-hour attempt
exceeds `transferUserInfo`'s 65,536-byte ceiling. Oversize transfers fail
through `session(_:didFinish:error:)`, which `WatchSyncCoordinator` does not
implement — so the failure is silent, and the largest payload is the final one
that marks the session complete.

**Approach:** keep the whole-journal invariant and the merge rule exactly as
they are; switch the *carrier* when the payload is large. `transferFile` is
also queued and guaranteed, and has no 64 KB limit. Add the error handlers so a
failure is never silent again.

**Files:**
- Modify: `MurphPlusWatch/Sync/WatchSyncCoordinator.swift`
- Modify: `MurphPlus/Sync/PhoneSyncCoordinator.swift`
- Test: `MurphPlusTests/SyncPayloadTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
    /// A long Murph journals ~1,080 heart-rate samples, and every checkpoint
    /// carries the whole journal. `transferUserInfo` caps at 65,536 bytes and
    /// fails silently past it — on the final checkpoint, the one that marks the
    /// session complete.
    func test_aLongSessionsPayloadExceedsTheUserInfoLimit() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var events: [SessionEvent] = [
            .started(at: start, template: spec, vestOn: false, vestWeightLbs: nil, indoor: false)
        ]
        for i in 0..<1_440 {     // two hours at one sample per five seconds
            events.append(.heartRate(bpm: 140, at: start.addingTimeInterval(Double(i) * 5)))
        }
        let payload = SyncPayload(sessionID: UUID(), checkpointSeq: 1, origin: .watch, events: events)

        let encoded = try JSONEncoder().encode(payload)

        XCTAssertGreaterThan(
            encoded.count, SyncPayload.userInfoByteLimit,
            "This is the case that must take the file transfer path"
        )
    }
```

- [ ] **Step 2: Run it and watch it fail**

Expected: FAIL — `SyncPayload.userInfoByteLimit` does not exist.

- [ ] **Step 3: Publish the limit**

In `MurphCore/SyncPayload.swift`, inside `SyncPayload`:

```swift
    /// WatchConnectivity's documented ceiling for `transferUserInfo`. Payloads
    /// at or above this go by file transfer instead — same queued, guaranteed
    /// delivery, no size limit.
    static let userInfoByteLimit = 65_536
```

- [ ] **Step 4: Route large payloads to `transferFile`**

Replace `WatchSyncCoordinator.transferCheckpoint(_:)`:

```swift
    func transferCheckpoint(_ payload: SyncPayload) {
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(payload) else { return }

        guard data.count < SyncPayload.userInfoByteLimit else {
            // Same guarantee, no ceiling. The oversize case is the *final*
            // checkpoint of a long workout — the one that marks it complete —
            // so dropping it would lose the whole session on the phone.
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("checkpoint-\(payload.sessionID)-\(payload.checkpointSeq).json")
            guard (try? data.write(to: url)) != nil else { return }
            WCSession.default.transferFile(url, metadata: nil)
            return
        }
        WCSession.default.transferUserInfo([SyncKey.payload: data])
    }
```

- [ ] **Step 5: Receive files on the phone**

In the `PhoneSyncCoordinator: WCSessionDelegate` extension:

```swift
    /// The large-payload counterpart of `didReceiveUserInfo`.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let data = try? Data(contentsOf: file.fileURL) else { return }
        Task { @MainActor in self.ingest(data) }
    }
```

- [ ] **Step 6: Stop failing silently**

In both coordinators' delegate extensions:

```swift
    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        guard let error else { return }
        // Was silent before: an oversize or rejected transfer simply vanished,
        // and the payload most likely to be oversize is the one that completes
        // the session.
        NSLog("MurphPlus sync: userInfo transfer failed — \(error.localizedDescription)")
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard let error else { return }
        NSLog("MurphPlus sync: file transfer failed — \(error.localizedDescription)")
    }
```

- [ ] **Step 7: Run the tests and the watch build**

Expected: `** TEST SUCCEEDED **` and `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add MurphCore/SyncPayload.swift MurphPlusWatch/Sync/WatchSyncCoordinator.swift MurphPlus/Sync/PhoneSyncCoordinator.swift MurphPlusTests/SyncPayloadTests.swift
git commit -m "fix: carry oversize checkpoints by file transfer and surface failures"
```

---

## Finishing up

- [ ] **Full clean verification**

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/MurphPlus-*
xcodegen generate
xcodebuild build -scheme MurphPlusWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' -project MurphPlus.xcodeproj
xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj
```

- [ ] **Push and update the PR**

```bash
git push
gh pr comment 1 --body "Pushed fixes for all ten review findings. See the plan at docs/superpowers/plans/2026-09-04-watch-stage-3-review-fixes.md"
```

- [ ] **Re-review before merging.** Run `/code-review 1 --level high` again. Tasks
  2, 4 and 9 change concurrency- and lifecycle-sensitive code.

- [ ] **Stage 3 Task 7 (hardware) is still outstanding** and is not part of this
  plan. It needs a physically paired iPhone and Apple Watch. Findings 1 and 2
  above are exactly what its Steps 2 and 5 were meant to catch, so treat the
  hardware pass as still necessary, not as covered by these fixes.

## Self-Review

**Coverage of the ten findings:**

| # | Finding | Task |
|---|---|---|
| 1 | `checkpointSeq` restarts after resume | 1 |
| 2 | `isMirroring` ignores staleness | 2 |
| 3 | Post-terminal event resurrects the mirror | 2 |
| 4 | `abandonResumableSession` never syncs | 3 |
| 5 | Watch `.inProgress` sessions have no exit | 4 |
| 6 | Importer duplicates starter templates | 5 |
| 7 | `selected` not reconciled with `templates` | 6 |
| 8 | Checkpoint payload exceeds the userInfo limit | 9 |
| 9 | `StartView` preview traps | 8 |
| 10 | No context re-push after import | 7 |

All ten are covered.

**Type consistency:** `StuckWatchSessionReaper.stuckSessions(context:olderThan:now:)`
and `.abandon(_:context:)` are defined in Task 4 and used only there.
`SyncPayload.userInfoByteLimit` is defined in Task 9 Step 3 and used in Steps 1
and 4. `LiveMirrorStore.init(staleAfter:)` is added in Task 2 and used by its own
tests. `effectiveSelection` is defined and used within Task 6.
`FakeSessionTransport` and `FakeWorkoutController` already exist in
`MurphPlusTests/WatchSyncEmissionTests.swift` and
`MurphPlusTests/WatchSessionControllerTests.swift` respectively.

**Known soft spots, stated rather than hidden:**

- Task 4's six-hour threshold is a judgement call, not a spec value. It is
  generous against a two-hour Murph but would sweep a session someone paused
  overnight — which is the correct trade, since that session is unfinishable
  anyway once the Watch has stopped sending.
- Task 4 Step 5 and Task 6 have no automated test: `HistoryView` and
  `WatchSetupView` are SwiftUI views with no test bundle coverage in this
  project. The reaper's logic underneath Task 4 *is* fully tested; only the
  banner wiring is not.
- Task 9 changes the transport's carrier. `transferFile` cannot be unit tested
  here for the same reason the coordinators never could — it is real
  WatchConnectivity. The size threshold that selects it is tested; the transfer
  itself needs the hardware pass.
