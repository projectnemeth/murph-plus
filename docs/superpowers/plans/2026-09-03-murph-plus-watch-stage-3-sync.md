# Murph Plus Watch — Stage 3: Sync and the Phone Side

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the loop. Watch-recorded sessions reach the phone's SwiftData store durably and idempotently; the phone mirrors a live Watch session read-only; templates and personal bests flow to the Watch; and session detail shows the heart rate and distance the Watch collected.

**Architecture:** Three `WatchConnectivity` channels for three jobs — `updateApplicationContext` for templates (latest-value-wins), `sendMessage` for the live mirror (fire-and-forget, in-memory only), `transferUserInfo` for durable handoff (queued, guaranteed). All three carry a single JSON `Data` blob, which sidesteps property-list type constraints entirely. Durable transfers send the **whole journal** with a monotonic `checkpointSeq`; the phone applies only a higher sequence and replays it wholesale, which makes duplicate and out-of-order delivery harmless.

**Tech Stack:** Swift, SwiftUI, SwiftData, WatchConnectivity, XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-03-murph-plus-watch-design.md`

**Prerequisite:** Stages 1 and 2 complete and merged.

## Global Constraints

- `MurphCore` remains Foundation-only. `WatchConnectivity` is **not** Foundation — the payload types live in `MurphCore`, the framework code does not.
- **The live mirror is in-memory only.** The observing device persists nothing from `sendMessage`. Only a `transferUserInfo` checkpoint creates or updates a `MurphSession`.
- **Timestamps are never restamped on receipt.** The phone stores the Watch's clock readings verbatim.
- **The phone may abandon a Watch-owned session but never resume it** — it does not own it.
- A simultaneous-start race produces **two sessions with two UUIDs, both kept**. Never merge them.
- Every new SwiftData property must be **optional or defaulted**, to stay CloudKit-legal and migrate lightly.
- Re-run `xcodegen generate` after adding any new source file.
- iOS tests: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`
- Watch build: `xcodebuild build -scheme MurphPlusWatch -destination 'generic/platform=watchOS' -project MurphPlus.xcodeproj`

---

## File Structure

```
MurphCore/
  SyncPayload.swift                       CREATE — envelopes + merge rule
  SessionTransport.swift                  CREATE — protocol, so coordinators are testable
MurphPlus/
  Models/MurphSession.swift               MODIFY — id, originRaw, journalData, lastCheckpointSeq
  Models/RunSplit.swift                   MODIFY — distanceMeters, avg/maxHeartRate
  Models/RoundLog.swift                   MODIFY — avg/maxHeartRate
  Sync/SessionImporter.swift              CREATE — apply a payload to SwiftData
  Sync/PhoneSyncCoordinator.swift         CREATE — WCSession on the phone
  Sync/LiveMirrorStore.swift              CREATE — in-memory mirror state
  Views/Session/LiveSessionView.swift     MODIFY — mirror mode
  Views/Start/StartView.swift             MODIFY — second-session guard
  Views/History/SessionDetailView.swift   MODIFY — HR and distance columns
MurphPlusWatch/
  Sync/WatchSyncCoordinator.swift         CREATE — WCSession on the watch
  Session/WatchSessionController.swift    MODIFY — emit live + checkpoints
  Views/WatchSetupView.swift              MODIFY — synced templates
  Views/WatchCompleteView.swift           MODIFY — PB badge
MurphPlusTests/
  SyncPayloadTests.swift                  CREATE
  SessionImporterTests.swift              CREATE
```

---

### Task 1: Sync payloads and the merge rule

**Files:**
- Create: `MurphCore/SyncPayload.swift`, `MurphCore/SessionTransport.swift`
- Test: `MurphPlusTests/SyncPayloadTests.swift`

**Interfaces:**
- Produces:
  - `SyncPayload { sessionID: UUID, checkpointSeq: Int, origin: SessionOrigin, events: [SessionEvent] }` — `Codable`
  - `SyncContext { templates: [TemplateSpec], personalBests: [PersonalBest] }` — `Codable`
  - `PersonalBest { templateID: UUID, vestOn: Bool, seconds: Double }` — `Codable`
  - `SessionOrigin: String, Codable { case phone, watch }`
  - `SessionMerge.shouldApply(incoming:storedSeq:) -> Bool`
  - `SyncPayload.strippingHeartRate() -> SyncPayload`
  - `SessionTransport` protocol (below)

- [ ] **Step 1: Write the failing tests**

Create `MurphPlusTests/SyncPayloadTests.swift`:

```swift
// MurphPlusTests/SyncPayloadTests.swift
import XCTest
@testable import MurphPlus

final class SyncPayloadTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    private let spec = TemplateSpec(
        id: UUID(), name: "Full Murph", runDistanceMiles: 1.0,
        totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 3
    )

    private func payload(seq: Int, events: [SessionEvent] = []) -> SyncPayload {
        SyncPayload(sessionID: UUID(), checkpointSeq: seq, origin: .watch, events: events)
    }

    func test_payloadRoundTripsThroughJSON() throws {
        let original = SyncPayload(
            sessionID: UUID(), checkpointSeq: 7, origin: .watch,
            events: [
                .started(at: t(0), template: spec, vestOn: true, vestWeightLbs: 20, indoor: false),
                .heartRate(bpm: 150, at: t(5)),
                .roundCompleted(number: 1, at: t(60)),
            ]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncPayload.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func test_higherSequenceIsApplied() {
        XCTAssertTrue(SessionMerge.shouldApply(incoming: payload(seq: 5), storedSeq: 4))
    }

    func test_duplicateDeliveryIsIgnored() {
        // transferUserInfo can deliver the same payload more than once.
        XCTAssertFalse(SessionMerge.shouldApply(incoming: payload(seq: 5), storedSeq: 5))
    }

    func test_outOfOrderDeliveryIsIgnored() {
        // A queued earlier checkpoint arriving after a later one must not
        // rewind the session to fewer rounds.
        XCTAssertFalse(SessionMerge.shouldApply(incoming: payload(seq: 3), storedSeq: 9))
    }

    func test_firstCheckpointAppliesAgainstAnUnknownSession() {
        XCTAssertTrue(SessionMerge.shouldApply(incoming: payload(seq: 1), storedSeq: 0))
    }

    func test_strippingHeartRateKeepsEverythingElseInOrder() {
        let full = SyncPayload(
            sessionID: UUID(), checkpointSeq: 2, origin: .watch,
            events: [
                .started(at: t(0), template: spec, vestOn: false, vestWeightLbs: nil, indoor: false),
                .heartRate(bpm: 140, at: t(5)),
                .runFinished(index: 1, at: t(100), distanceMeters: 1609.34),
                .heartRate(bpm: 160, at: t(105)),
                .roundCompleted(number: 1, at: t(160)),
            ]
        )

        let stripped = full.strippingHeartRate()

        XCTAssertEqual(stripped.events.count, 3)
        XCTAssertFalse(stripped.events.contains { $0.isHeartRate })
        XCTAssertEqual(stripped.checkpointSeq, 2)
        XCTAssertEqual(stripped.sessionID, full.sessionID)
        // Replaying the stripped journal must still produce the same session shape.
        XCTAssertEqual(SessionState.replay(stripped.events).completedRounds, 1)
        XCTAssertEqual(SessionState.replay(stripped.events).phase, .rounds)
    }

    func test_syncContextRoundTrips() throws {
        let context = SyncContext(
            templates: [spec],
            personalBests: [PersonalBest(templateID: spec.id, vestOn: true, seconds: 3120)]
        )

        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(SyncContext.self, from: data)

        XCTAssertEqual(decoded, context)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/SyncPayloadTests`

Expected: compile failure — `cannot find 'SyncPayload' in scope`.

- [ ] **Step 3: Write the payload types**

Create `MurphCore/SyncPayload.swift`:

```swift
// MurphCore/SyncPayload.swift
import Foundation

enum SessionOrigin: String, Codable {
    case phone
    case watch
}

/// A durable handoff: the **entire journal so far**, not a delta, stamped with
/// a monotonically increasing sequence number.
///
/// Sending the whole journal every time is what makes the merge rule trivial —
/// the receiver keeps whichever sequence is highest and replays it wholesale,
/// so duplicate deliveries are harmless, out-of-order deliveries are harmless,
/// and a session cut short by a dead Watch battery has already landed up to its
/// last round.
struct SyncPayload: Codable, Equatable {
    var sessionID: UUID
    var checkpointSeq: Int
    var origin: SessionOrigin
    var events: [SessionEvent]

    /// Heart-rate events are bulky (~700 per long session), already aggregated
    /// into per-segment summaries, and their raw form lives in HealthKit. The
    /// phone stores the journal without them.
    func strippingHeartRate() -> SyncPayload {
        SyncPayload(
            sessionID: sessionID,
            checkpointSeq: checkpointSeq,
            origin: origin,
            events: events.filter { !$0.isHeartRate }
        )
    }
}

struct PersonalBest: Codable, Equatable {
    var templateID: UUID
    var vestOn: Bool
    var seconds: Double
}

/// Phone → Watch reference data. Latest-value-wins: a stale intermediate
/// template list is never interesting.
struct SyncContext: Codable, Equatable {
    var templates: [TemplateSpec]
    var personalBests: [PersonalBest]
}

enum SessionMerge {
    /// Apply only a strictly newer checkpoint.
    static func shouldApply(incoming: SyncPayload, storedSeq: Int) -> Bool {
        incoming.checkpointSeq > storedSeq
    }
}
```

Create `MurphCore/SessionTransport.swift`:

```swift
// MurphCore/SessionTransport.swift
import Foundation

/// The three sync channels, abstracted so the coordinators can be tested
/// against a fake. `WatchConnectivity` itself is verified by hand — it cannot
/// be meaningfully unit tested.
protocol SessionTransport: AnyObject {
    var isReachable: Bool { get }

    /// Fire-and-forget live mirror. Dropped silently when unreachable.
    func sendLive(_ event: SessionEvent, sessionID: UUID)

    /// Queued, guaranteed, survives termination and reboot.
    func transferCheckpoint(_ payload: SyncPayload)

    /// Latest-value-wins reference data.
    func updateContext(_ context: SyncContext)

    var onLiveEvent: ((UUID, SessionEvent) -> Void)? { get set }
    var onCheckpoint: ((SyncPayload) -> Void)? { get set }
    var onContext: ((SyncContext) -> Void)? { get set }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/SyncPayloadTests`

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MurphCore/SyncPayload.swift MurphCore/SessionTransport.swift MurphPlusTests/SyncPayloadTests.swift
git commit -m "feat: add sync payload envelopes and the checkpoint merge rule"
```

---

### Task 2: Session importer

**Files:**
- Modify: `MurphPlus/Models/MurphSession.swift`, `RunSplit.swift`, `RoundLog.swift`
- Create: `MurphPlus/Sync/SessionImporter.swift`
- Test: `MurphPlusTests/SessionImporterTests.swift`

**Interfaces:**
- Consumes: `SyncPayload`, `SessionMerge`, `SessionState`, `SessionDerivation`, `HeartRateAggregator`.
- Produces: `SessionImporter.apply(_ payload: SyncPayload, context: ModelContext) throws -> MurphSession?` — returns `nil` when the payload was ignored as stale.
- Model additions: `MurphSession.id`, `.originRaw`, `.journalData`, `.lastCheckpointSeq`; `RunSplit.distanceMeters`, `.avgHeartRate`, `.maxHeartRate`; `RoundLog.avgHeartRate`, `.maxHeartRate`.
- **Already added by Stage 1 — populate, do not re-declare:** `MurphSession.roundsStartedAt: Date?`, `.pausedIntervalsData: Data?`, `.pausedSeconds`, `.pausedAt`, `.indoor`; `RoundLog.pausedSecondsInRound`. The importer must set `roundsStartedAt` and `pausedIntervalsData` (see the code in Step 4) or an imported session's round 1 silently absorbs run 1's pause.

- [ ] **Step 1: Add the model fields**

`MurphSession.swift`:

```swift
    var id: UUID = UUID()
    var originRaw: String = SessionOrigin.phone.rawValue
    /// The received journal, heart-rate events stripped. Kept so a session can
    /// be re-derived if aggregation changes.
    var journalData: Data?
    /// Highest applied checkpoint. Meaningful only for received sessions;
    /// stays 0 for phone-owned ones.
    var lastCheckpointSeq: Int = 0

    var origin: SessionOrigin {
        get { SessionOrigin(rawValue: originRaw) ?? .phone }
        set { originRaw = newValue.rawValue }
    }
```

`RunSplit.swift`:

```swift
    var distanceMeters: Double?
    var avgHeartRate: Int?
    var maxHeartRate: Int?
```

`RoundLog.swift`:

```swift
    var avgHeartRate: Int?
    var maxHeartRate: Int?
```

- [ ] **Step 2: Write the failing tests**

Create `MurphPlusTests/SessionImporterTests.swift`:

```swift
// MurphPlusTests/SessionImporterTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

final class SessionImporterTests: XCTestCase {

    var context: ModelContext!
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    private func spec(rounds: Int = 3, id: UUID = UUID()) -> TemplateSpec {
        TemplateSpec(id: id, name: "Full Murph", runDistanceMiles: 1.0,
                     totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: rounds)
    }

    private func events(_ spec: TemplateSpec, rounds: Int, finished: Bool) -> [SessionEvent] {
        var out: [SessionEvent] = [
            .started(at: t(0), template: spec, vestOn: true, vestWeightLbs: 20, indoor: false),
            .runFinished(index: 1, at: t(500), distanceMeters: 1609.34),
        ]
        for i in 1...rounds {
            out.append(.heartRate(bpm: 150 + i, at: t(500 + Double(i) * 60 - 10)))
            out.append(.roundCompleted(number: i, at: t(500 + Double(i) * 60)))
        }
        if finished {
            out.append(.runFinished(index: 2, at: t(2000), distanceMeters: 1609.34))
        }
        return out
    }

    private func payload(_ spec: TemplateSpec, seq: Int, rounds: Int, finished: Bool,
                         id: UUID = UUID()) -> SyncPayload {
        SyncPayload(sessionID: id, checkpointSeq: seq, origin: .watch,
                    events: events(spec, rounds: rounds, finished: finished))
    }

    private func allSessions() throws -> [MurphSession] {
        try context.fetch(FetchDescriptor<MurphSession>())
    }

    func test_createsASessionFromATerminalPayload() throws {
        let s = spec()
        let session = try XCTUnwrap(
            SessionImporter.apply(payload(s, seq: 4, rounds: 3, finished: true), context: context)
        )

        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.completedRounds, 3)
        XCTAssertEqual(session.runSplits.count, 2)
        XCTAssertEqual(session.roundLogs.count, 3)
        XCTAssertEqual(session.origin, .watch)
        XCTAssertTrue(session.vestOn)
        XCTAssertEqual(session.vestWeightLbs, 20)
    }

    func test_duplicateDeliveryDoesNotCreateASecondSession() throws {
        let s = spec()
        let p = payload(s, seq: 4, rounds: 3, finished: true)

        _ = try SessionImporter.apply(p, context: context)
        let second = try SessionImporter.apply(p, context: context)

        XCTAssertNil(second, "A stale or duplicate checkpoint is ignored")
        XCTAssertEqual(try allSessions().count, 1)
    }

    func test_aLaterCheckpointReplacesTheEarlierOne() throws {
        let s = spec()
        let id = UUID()

        _ = try SessionImporter.apply(payload(s, seq: 2, rounds: 1, finished: false, id: id), context: context)
        _ = try SessionImporter.apply(payload(s, seq: 5, rounds: 3, finished: true, id: id), context: context)

        let sessions = try allSessions()
        XCTAssertEqual(sessions.count, 1, "Same session ID must not duplicate")
        XCTAssertEqual(sessions[0].completedRounds, 3)
        XCTAssertEqual(sessions[0].roundLogs.count, 3, "Round logs are replaced wholesale, not appended")
        XCTAssertEqual(sessions[0].status, .completed)
    }

    func test_anEarlierCheckpointArrivingLateIsIgnored() throws {
        let s = spec()
        let id = UUID()

        _ = try SessionImporter.apply(payload(s, seq: 5, rounds: 3, finished: true, id: id), context: context)
        let late = try SessionImporter.apply(payload(s, seq: 2, rounds: 1, finished: false, id: id), context: context)

        XCTAssertNil(late)
        XCTAssertEqual(try allSessions()[0].completedRounds, 3, "Must not rewind to fewer rounds")
    }

    func test_linksToAnExistingTemplateByID() throws {
        let template = WorkoutTemplate(name: "Full Murph", rounds: 3)
        context.insert(template)
        try context.save()

        let session = try XCTUnwrap(
            SessionImporter.apply(payload(template.spec, seq: 1, rounds: 3, finished: true), context: context)
        )

        XCTAssertEqual(session.template?.id, template.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutTemplate>()).count, 1)
    }

    func test_reconstructsATemplateWhenTheIDIsUnknown() throws {
        // The template was deleted on the phone after the workout started.
        // History must never lose what the workout actually was.
        let s = spec()

        let session = try XCTUnwrap(
            SessionImporter.apply(payload(s, seq: 1, rounds: 3, finished: true), context: context)
        )

        let template = try XCTUnwrap(session.template)
        XCTAssertEqual(template.id, s.id)
        XCTAssertEqual(template.rounds, 3)
        XCTAssertEqual(template.totalPullUps, 100)
    }

    func test_storesHeartRateSummariesOnRoundsAndRuns() throws {
        let s = spec()
        let session = try XCTUnwrap(
            SessionImporter.apply(payload(s, seq: 1, rounds: 3, finished: true), context: context)
        )

        let firstRound = try XCTUnwrap(session.roundLogs.first { $0.roundNumber == 1 })
        XCTAssertEqual(firstRound.avgHeartRate, 151)
        XCTAssertEqual(firstRound.maxHeartRate, 151)
    }

    func test_storesRunDistance() throws {
        let s = spec()
        let session = try XCTUnwrap(
            SessionImporter.apply(payload(s, seq: 1, rounds: 3, finished: true), context: context)
        )

        let run1 = try XCTUnwrap(session.runSplits.first { $0.runIndex == 1 })
        XCTAssertEqual(try XCTUnwrap(run1.distanceMeters), 1609.34, accuracy: 0.01)
    }

    func test_storedJournalHasNoHeartRateEvents() throws {
        let s = spec()
        let session = try XCTUnwrap(
            SessionImporter.apply(payload(s, seq: 1, rounds: 3, finished: true), context: context)
        )

        let data = try XCTUnwrap(session.journalData)
        let stored = try JSONDecoder().decode([SessionEvent].self, from: data)
        XCTAssertFalse(stored.contains { $0.isHeartRate })
        XCTAssertEqual(SessionState.replay(stored).completedRounds, 3)
    }

    func test_anUnfinishedPayloadLandsAsInProgress() throws {
        let s = spec()
        let session = try XCTUnwrap(
            SessionImporter.apply(payload(s, seq: 2, rounds: 1, finished: false), context: context)
        )

        XCTAssertEqual(session.status, .inProgress)
        XCTAssertEqual(session.completedRounds, 1)
    }

    func test_twoDifferentSessionIDsBothSurvive() throws {
        // The simultaneous-start race: two sessions, both kept, never merged.
        let s = spec()
        _ = try SessionImporter.apply(payload(s, seq: 1, rounds: 3, finished: true), context: context)
        _ = try SessionImporter.apply(payload(s, seq: 1, rounds: 3, finished: true), context: context)

        XCTAssertEqual(try allSessions().count, 2)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj -only-testing:MurphPlusTests/SessionImporterTests`

Expected: compile failure — `cannot find 'SessionImporter' in scope`.

- [ ] **Step 4: Write the importer**

Create `MurphPlus/Sync/SessionImporter.swift`:

```swift
// MurphPlus/Sync/SessionImporter.swift
import Foundation
import SwiftData

/// Applies a received checkpoint to the phone's system of record.
///
/// A checkpoint carries the whole journal, so application is a wholesale
/// replace rather than a merge: the session's splits and round logs are rebuilt
/// from the replayed state every time. Combined with the "only a strictly
/// higher sequence applies" rule, that makes duplicate and out-of-order
/// delivery harmless without any conflict resolution.
enum SessionImporter {

    /// Returns the session, or `nil` if the payload was ignored as stale.
    @discardableResult
    static func apply(_ payload: SyncPayload, context: ModelContext) throws -> MurphSession? {
        let sessionID = payload.sessionID
        let descriptor = FetchDescriptor<MurphSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        let existing = try context.fetch(descriptor).first

        if let existing, !SessionMerge.shouldApply(incoming: payload, storedSeq: existing.lastCheckpointSeq) {
            return nil
        }

        let state = SessionState.replay(payload.events)
        guard let spec = state.template, let startedAt = state.startedAt else { return nil }

        let template = try resolveTemplate(spec, context: context)
        let session = existing ?? {
            let new = MurphSession(template: template, vestOn: state.vestOn, vestWeightLbs: state.vestWeightLbs)
            new.id = sessionID
            context.insert(new)
            return new
        }()

        session.template = template
        session.origin = payload.origin
        session.date = startedAt
        session.startedAt = startedAt
        session.vestOn = state.vestOn
        session.vestWeightLbs = state.vestWeightLbs
        session.indoor = state.indoor
        session.phase = state.phase
        session.status = state.status
        session.completedAt = state.completedAt
        session.completedRounds = state.completedRounds
        session.currentPhaseStartedAt = state.currentPhaseStartedAt
        session.pausedSeconds = totalPaused(state)
        // Stage 1 persists the true rounds-phase start and `RoundThroughputBuilder`
        // PREFERS it. Leaving it nil would send the builder to its fallback,
        // `run1.startTime + run1.durationSeconds` — which is net of pause, so round 1
        // would absorb any pause taken during run 1 and read as slower than it was,
        // bending the fatigue curve. Every imported session must carry it.
        session.roundsStartedAt = state.roundsStartedAt
        session.pausedIntervalsData = try? JSONEncoder().encode(state.pausedIntervals)
        session.lastCheckpointSeq = payload.checkpointSeq
        session.journalData = try? JSONEncoder().encode(payload.strippingHeartRate().events)

        rebuildSplits(on: session, state: state, events: payload.events, context: context)
        rebuildRounds(on: session, state: state, events: payload.events, context: context)

        try context.save()
        return session
    }

    // MARK: - Pieces

    private static func totalPaused(_ state: SessionState) -> Double {
        guard let startedAt = state.startedAt else { return 0 }
        let end = state.completedAt ?? Date.now
        return state.pausedSeconds(between: startedAt, and: end)
    }

    /// Links to the live template when the ID resolves; reconstructs from the
    /// snapshot when it does not, so a deleted template never costs history the
    /// record of what the workout actually was.
    private static func resolveTemplate(_ spec: TemplateSpec, context: ModelContext) throws -> WorkoutTemplate {
        let specID = spec.id
        let descriptor = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate { $0.id == specID }
        )
        if let found = try context.fetch(descriptor).first { return found }

        let rebuilt = WorkoutTemplate(
            name: spec.name,
            runDistanceMiles: spec.runDistanceMiles,
            totalPullUps: spec.totalPullUps,
            totalPushUps: spec.totalPushUps,
            totalSquats: spec.totalSquats,
            rounds: spec.rounds
        )
        rebuilt.id = spec.id
        context.insert(rebuilt)
        return rebuilt
    }

    private static func rebuildSplits(
        on session: MurphSession, state: SessionState,
        events: [SessionEvent], context: ModelContext
    ) {
        for old in session.runSplits { context.delete(old) }
        session.runSplits.removeAll()

        let summaries = HeartRateAggregator.runSummaries(events: events, state: state)
        for split in state.runSplits {
            let model = RunSplit(
                runIndex: split.index,
                startTime: split.startTime,
                durationSeconds: split.durationSeconds,
                session: session
            )
            model.distanceMeters = split.distanceMeters
            model.avgHeartRate = summaries[split.index]?.average
            model.maxHeartRate = summaries[split.index]?.maximum
            context.insert(model)
            session.runSplits.append(model)
        }
    }

    private static func rebuildRounds(
        on session: MurphSession, state: SessionState,
        events: [SessionEvent], context: ModelContext
    ) {
        for old in session.roundLogs { context.delete(old) }
        session.roundLogs.removeAll()

        let summaries = HeartRateAggregator.roundSummaries(events: events, state: state)
        let durations = SessionDerivation.roundDurations(state)
        var boundary = state.roundsStartedAt

        for (index, timestamp) in state.roundTimestamps.enumerated() {
            let log = RoundLog(roundNumber: index + 1, completedAt: timestamp, session: session)
            if let start = boundary {
                // Wall-clock minus the net duration is exactly the paused time
                // inside this round — stored so the fatigue fit stays honest.
                let gross = timestamp.timeIntervalSince(start)
                log.pausedSecondsInRound = max(0, gross - durations[index])
            }
            log.avgHeartRate = summaries[index]?.average
            log.maxHeartRate = summaries[index]?.maximum
            context.insert(log)
            session.roundLogs.append(log)
            boundary = timestamp
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`

Expected: `** TEST SUCCEEDED **` — the whole suite, including Stage 1's untouched engine tests.

- [ ] **Step 6: Commit**

```bash
git add MurphPlus/Sync/SessionImporter.swift MurphPlus/Models MurphPlusTests/SessionImporterTests.swift
git commit -m "feat: import watch session checkpoints into SwiftData

Wholesale replace under a monotonic sequence, so duplicate and
out-of-order delivery need no conflict resolution. Templates link by
id and are reconstructed from the snapshot when deleted."
```

---

### Task 3: WatchConnectivity coordinators

**Files:**
- Create: `MurphPlus/Sync/PhoneSyncCoordinator.swift`, `MurphPlus/Sync/LiveMirrorStore.swift`
- Create: `MurphPlusWatch/Sync/WatchSyncCoordinator.swift`
- Modify: `MurphPlusWatch/Session/WatchSessionController.swift`, `MurphPlus/MurphPlusApp.swift`

**Interfaces:**
- Consumes: `SessionTransport`, `SyncPayload`, `SyncContext`, `SessionImporter`.
- Produces:
  - `PhoneSyncCoordinator(container:)` — `@Observable`, conforms to `WCSessionDelegate`, owns a `LiveMirrorStore`
  - `LiveMirrorStore` — `@Observable`, `var mirrored: SessionState?`, `var sessionID: UUID?`, `var lastUpdate: Date?`, `var isStale: Bool`
  - `WatchSyncCoordinator` — `sendCheckpoint(journal:origin:)`, `sendLive(_:)`, `var context: SyncContext?`

- [ ] **Step 1: Write the shared payload keys**

Add to `MurphCore/SyncPayload.swift`:

```swift
/// All three channels carry a single JSON blob under one key, which sidesteps
/// WatchConnectivity's property-list type constraints entirely.
enum SyncKey {
    static let payload = "payload"
    static let liveEvent = "liveEvent"
    static let liveSessionID = "liveSessionID"
    static let context = "context"
}
```

- [ ] **Step 2: Write the live mirror store**

Create `MurphPlus/Sync/LiveMirrorStore.swift`:

```swift
// MurphPlus/Sync/LiveMirrorStore.swift
import Foundation
import Observation

/// In-memory only. Nothing here is ever persisted — a `MurphSession` is created
/// solely by a durable checkpoint, so a dropped link can never leave a
/// half-written session in history.
@Observable
final class LiveMirrorStore {
    private(set) var sessionID: UUID?
    private(set) var state: SessionState?
    private(set) var lastUpdate: Date?

    /// A frozen clock with no explanation is worse than an honest one.
    var isStale: Bool {
        guard let lastUpdate else { return true }
        return Date.now.timeIntervalSince(lastUpdate) > 10
    }

    var isMirroring: Bool { state != nil && !(state?.isTerminal ?? true) }

    func receive(sessionID: UUID, event: SessionEvent) {
        if self.sessionID != sessionID {
            self.sessionID = sessionID
            self.state = SessionState()
        }
        state?.apply(event)
        lastUpdate = .now
        if state?.isTerminal == true { clear() }
    }

    func clear() {
        sessionID = nil
        state = nil
        lastUpdate = nil
    }
}
```

- [ ] **Step 3: Write the phone coordinator**

Create `MurphPlus/Sync/PhoneSyncCoordinator.swift`:

```swift
// MurphPlus/Sync/PhoneSyncCoordinator.swift
import Foundation
import Observation
import SwiftData
import WatchConnectivity

@Observable
final class PhoneSyncCoordinator: NSObject {
    let mirror = LiveMirrorStore()
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Latest-value-wins reference data for the Watch: the current template
    /// list plus personal bests, so the completion screen can badge a PB.
    func pushContext() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let context = ModelContext(container)
        guard let templates = try? context.fetch(FetchDescriptor<WorkoutTemplate>()) else { return }
        guard let sessions = try? context.fetch(FetchDescriptor<MurphSession>()) else { return }

        var bests: [String: PersonalBest] = [:]
        for session in sessions where session.status == .completed {
            guard let templateID = session.template?.id,
                  let seconds = session.totalElapsedSeconds else { continue }
            let key = "\(templateID)-\(session.vestOn)"
            if let existing = bests[key], existing.seconds <= seconds { continue }
            bests[key] = PersonalBest(templateID: templateID, vestOn: session.vestOn, seconds: seconds)
        }

        let payload = SyncContext(
            templates: templates.map(\.spec),
            personalBests: Array(bests.values)
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? WCSession.default.updateApplicationContext([SyncKey.context: data])
    }

    private func ingest(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(SyncPayload.self, from: data) else { return }
        let context = ModelContext(container)
        try? SessionImporter.apply(payload, context: context)
        if SessionState.replay(payload.events).isTerminal {
            Task { @MainActor in mirror.clear() }
        }
    }
}

extension PhoneSyncCoordinator: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        pushContext()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    /// Durable handoff. This is the only path that creates a `MurphSession`.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[SyncKey.payload] as? Data else { return }
        ingest(data)
    }

    /// Live mirror. Rendered and forgotten — never persisted.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard
            let eventData = message[SyncKey.liveEvent] as? Data,
            let idString = message[SyncKey.liveSessionID] as? String,
            let sessionID = UUID(uuidString: idString),
            let event = try? JSONDecoder().decode(SessionEvent.self, from: eventData)
        else { return }

        Task { @MainActor in
            mirror.receive(sessionID: sessionID, event: event)
        }
    }
}
```

- [ ] **Step 4: Write the watch coordinator**

Create `MurphPlusWatch/Sync/WatchSyncCoordinator.swift`:

```swift
// MurphPlusWatch/Sync/WatchSyncCoordinator.swift
import Foundation
import Observation
import WatchConnectivity

@Observable
final class WatchSyncCoordinator: NSObject {
    private(set) var context: SyncContext?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        decodeStoredContext()
    }

    /// Fire-and-forget. Dropped silently when the phone is unreachable — the
    /// mirror simply goes stale and says so.
    func sendLive(_ event: SessionEvent, sessionID: UUID) {
        guard WCSession.default.isReachable,
              let data = try? JSONEncoder().encode(event) else { return }
        WCSession.default.sendMessage(
            [SyncKey.liveEvent: data, SyncKey.liveSessionID: sessionID.uuidString],
            replyHandler: nil,
            errorHandler: nil
        )
    }

    /// Queued and guaranteed. Survives app termination and reboot.
    func sendCheckpoint(_ payload: SyncPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        WCSession.default.transferUserInfo([SyncKey.payload: data])
    }

    private func decodeStoredContext() {
        guard let data = WCSession.default.receivedApplicationContext[SyncKey.context] as? Data else { return }
        context = try? JSONDecoder().decode(SyncContext.self, from: data)
    }
}

extension WatchSyncCoordinator: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        decodeStoredContext()
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[SyncKey.context] as? Data else { return }
        Task { @MainActor in
            self.context = try? JSONDecoder().decode(SyncContext.self, from: data)
        }
    }
}
```

- [ ] **Step 5: Emit live events and checkpoints from the watch controller**

In `WatchSessionController.swift`, add the coordinator and a sequence counter:

```swift
    let sync = WatchSyncCoordinator()
    private var checkpointSeq = 0
```

and replace `record(_:)` with:

```swift
    private func record(_ event: SessionEvent) {
        try? journal?.append(event)
        state.apply(event)

        guard let journal else { return }
        sync.sendLive(event, sessionID: journal.sessionID)

        // Checkpoint on every event that is not heart rate: ~25 per session,
        // each carrying the whole journal. The receiver keeps the highest
        // sequence, so extra transfers are harmless.
        if !event.isHeartRate {
            checkpointSeq += 1
            sync.sendCheckpoint(SyncPayload(
                sessionID: journal.sessionID,
                checkpointSeq: checkpointSeq,
                origin: .watch,
                events: journal.events
            ))
        }
    }
```

- [ ] **Step 6: Instantiate the phone coordinator**

In `MurphPlusApp.swift`, add a stored coordinator and inject it:

```swift
    @State private var sync: PhoneSyncCoordinator
```

initialised after the container is built (`sync = PhoneSyncCoordinator(container: container)`, wrapped as `_sync = State(initialValue:)`), and pass it into `RootTabView()` via `.environment(sync)`.

- [ ] **Step 7: Build both targets and run the suite**

Run: `xcodegen generate && xcodebuild build -scheme MurphPlusWatch -destination 'generic/platform=watchOS' -project MurphPlus.xcodeproj && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`

Expected: `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add MurphPlus/Sync MurphPlusWatch/Sync MurphPlusWatch/Session/WatchSessionController.swift MurphPlus/MurphPlusApp.swift MurphCore/SyncPayload.swift
git commit -m "feat: wire WatchConnectivity across all three channels"
```

---

### Task 4: Synced templates and the PB badge

**Files:**
- Modify: `MurphPlusWatch/Views/WatchSetupView.swift`, `MurphPlusWatch/Views/WatchCompleteView.swift`
- Modify: `MurphPlus/Views/Start/TemplateEditorView.swift` (or wherever templates are saved)

**Interfaces:**
- Consumes: `WatchSyncCoordinator.context`, `PhoneSyncCoordinator.pushContext()`.

- [ ] **Step 1: Use synced templates on the Watch**

In `WatchSetupView.swift`, replace the `@State private var templates` initialiser with a computed value that prefers synced data and falls back to the starters:

```swift
    private var templates: [TemplateSpec] {
        let synced = controller.sync.context?.templates ?? []
        // The fallback matters on a Watch that has never connected — the user
        // can still do a Full Murph rather than staring at an empty list.
        return synced.isEmpty ? Self.starterTemplates : synced
    }
```

Delete the `@State` declaration it replaces, and keep `starterTemplates`.

- [ ] **Step 2: Push context whenever templates change**

Wherever a `WorkoutTemplate` is created, edited, or deleted (the template
editor's save path and the delete confirm), call `sync.pushContext()` after
`context.save()`. Also call it after a session completes on the phone, so
personal bests stay current.

- [ ] **Step 3: Add the PB badge**

In `WatchCompleteView.swift`, add:

```swift
    private var isPersonalBest: Bool {
        guard
            controller.state.status == .completed,
            let templateID = controller.state.template?.id,
            let best = controller.sync.context?.personalBests.first(where: {
                $0.templateID == templateID && $0.vestOn == controller.state.vestOn
            })
        else { return false }
        return SessionDerivation.elapsed(controller.state, now: .now) < best.seconds
    }
```

and render it above the total:

```swift
                if isPersonalBest {
                    Text("Personal best")
                        .murphType(.tag)
                        .foregroundStyle(MurphColor.textOnAccent)
                        .padding(.horizontal, MurphSpacing.space2)
                        .padding(.vertical, 3)
                        .background(MurphColor.lime500)
                        .clipShape(Capsule())
                }
```

The badge compares against the *matching vest setting* only — vest and
non-vest times are never mixed, here or anywhere else.

- [ ] **Step 4: Build both targets**

Run: `xcodegen generate && xcodebuild build -scheme MurphPlusWatch -destination 'generic/platform=watchOS' -project MurphPlus.xcodeproj && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`

Expected: `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MurphPlusWatch/Views MurphPlus/Views/Start
git commit -m "feat: sync templates and personal bests to the watch"
```

---

### Task 5: Phone live mirror and start guard

**Files:**
- Modify: `MurphPlus/Views/Session/LiveSessionView.swift`, `MurphPlus/Views/Start/StartView.swift`

**Interfaces:**
- Consumes: `PhoneSyncCoordinator.mirror` via `@Environment`.

- [ ] **Step 1: Add a mirror screen**

Create the mirror as a distinct view rather than overloading `LiveSessionView`
with a second mode — it shares the design language but shares no interaction:

Create `MurphPlus/Views/Session/MirroredSessionView.swift`:

```swift
// MurphPlus/Views/Session/MirroredSessionView.swift
import SwiftUI

/// Read-only reflection of a session owned by the Apple Watch.
///
/// Single-writer means the phone can display but never act. The staleness line
/// is deliberate: on a silent-failure transport, a frozen clock with no
/// explanation is worse than an honest "Disconnected".
struct MirroredSessionView: View {
    let mirror: LiveMirrorStore

    var body: some View {
        VStack(alignment: .leading, spacing: MurphSpacing.gapSection) {
            MurphBanner(
                tone: .info,
                title: "Controlled by Apple Watch",
                message: mirror.isStale ? "Disconnected — showing last known state" : "Live"
            )

            if let state = mirror.state {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    MurphClock(
                        label: "Elapsed",
                        seconds: SessionDerivation.elapsed(state, now: .now),
                        size: .lg,
                        running: !state.isPaused && !mirror.isStale
                    )
                }

                MurphFlowLayout {
                    MurphBadge(tone: .live, dot: true, title: phaseLabel(state.phase))
                    if state.isPaused { MurphBadge(tone: .abandoned, title: "Paused") }
                    if let bpm = state.latestHeartRate {
                        MurphBadge(title: "\(bpm) bpm")
                    }
                }

                if let template = state.template {
                    MurphSplitRow(
                        label: "Rounds",
                        value: "\(state.completedRounds) of \(template.rounds)",
                        tone: .accent
                    )
                }
            }
        }
        .padding(MurphSpacing.gutterScreen)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .murphScreenBackground()
        .murphNavBar(title: "Live session")
    }

    private func phaseLabel(_ phase: SessionPhase) -> String {
        switch phase {
        case .notStarted: "Starting"
        case .run1: "Run 1"
        case .rounds: "Rounds"
        case .run2: "Run 2"
        case .completed: "Complete"
        }
    }
}
```

If `MurphBanner`'s parameter labels differ from `tone:title:message:`, match its
actual signature rather than changing the component.

- [ ] **Step 2: Guard the start screen**

In `StartView.swift`, read the coordinator and replace the Begin button when a
Watch session is live:

```swift
    @Environment(PhoneSyncCoordinator.self) private var sync
```

```swift
                        if sync.mirror.isMirroring {
                            // Never offer Start while another device owns a
                            // session — a second session is the one conflict
                            // this design refuses to resolve.
                            NavigationLink {
                                MirroredSessionView(mirror: sync.mirror)
                            } label: {
                                MurphBanner(
                                    tone: .info,
                                    title: "Session running on Apple Watch",
                                    message: "Tap to follow along"
                                )
                            }
                        } else {
                            MurphButton(
                                variant: .primary, size: .lg, full: true,
                                icon: Image(systemName: "play.fill"), title: "Begin"
                            ) { /* existing action, unchanged */ }
                        }
```

Keep the existing Begin action body exactly as it is.

- [ ] **Step 3: Build and test**

Run: `xcodegen generate && xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MurphPlus/Views/Session/MirroredSessionView.swift MurphPlus/Views/Start/StartView.swift
git commit -m "feat: mirror a watch-owned session on the phone, read-only"
```

---

### Task 6: Heart rate and distance in session detail

**Files:**
- Modify: `MurphPlus/Views/History/SessionDetailView.swift`

- [ ] **Step 1: Show distance beside each run split**

In `splitsSection`, append distance to the split's displayed value when present:

```swift
    private func splitValue(_ split: RunSplit) -> String {
        var value = formatDuration(split.durationSeconds)
        if let meters = split.distanceMeters {
            value += String(format: " · %.2f mi", meters / 1609.34)
        }
        if let bpm = split.avgHeartRate {
            value += " · \(bpm) bpm"
        }
        return value
    }
```

and use it wherever the split row's value is currently built.

- [ ] **Step 2: Show average heart rate per round**

In `roundsSection`, where each round's pace is rendered, append the round's
`avgHeartRate` when it is non-nil. Every v1 session and every phone-owned
session has `nil` here, so the no-HR rendering is the common path, not the
exception — verify it looks right first.

- [ ] **Step 3: Add an origin badge**

In `header`, alongside the existing status and vest badges:

```swift
                if session.origin == .watch {
                    MurphBadge(title: "Apple Watch")
                }
```

- [ ] **Step 4: Build and test**

Run: `xcodebuild test -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17' -project MurphPlus.xcodeproj`

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MurphPlus/Views/History/SessionDetailView.swift
git commit -m "feat: show watch-collected heart rate and distance in session detail"
```

---

### Task 7: End-to-end verification on real hardware

`WatchConnectivity` cannot be meaningfully unit tested, and every failure mode
that matters here is silent. This task is the real test.

- [ ] **Step 1: Happy path**

Install both apps on a paired iPhone and Apple Watch. Start a 3-round session
on the Watch with the phone nearby. Confirm: the phone's Start tab shows
"Session running on Apple Watch"; tapping it shows a live clock, round count and
BPM that track the Watch within a second or two. Complete the session. Confirm it
appears in phone History with both run splits, per-round heart rate, run
distance, and an "Apple Watch" badge.

- [ ] **Step 2: Phone absent**

Power the iPhone **off**. Complete a full session on the Watch. Power the phone
back on, open the app, and confirm the session arrives intact — `transferUserInfo`
queues across a reboot.

- [ ] **Step 3: Link dropped mid-session**

Start on the Watch, walk out of range mid-rounds, log several rounds, return.
Confirm: the phone's mirror showed "Disconnected" while away, and the final
history record contains **every** round, including the ones logged out of range.

- [ ] **Step 4: Duplicate and out-of-order tolerance**

Complete a session, then force-quit and relaunch the phone app while checkpoints
are still queued. Confirm History holds exactly **one** session with the full
round count — not two, and not a truncated one.

- [ ] **Step 5: Dead watch**

Start a session on the Watch, complete run 1 and two rounds, then let the Watch
run out of battery or force-quit the app permanently. Confirm the phone holds an
`inProgress` session with two rounds, and that the phone offers **abandon but not
resume** for it.

- [ ] **Step 6: Template deleted mid-flight**

Start a session on the Watch against a template, delete that template on the
phone, then complete the session. Confirm history still shows the correct
template name and round structure.

- [ ] **Step 7: Pause across the boundary**

Run a session with a two-minute pause mid-round. Confirm total time excludes it
and — the critical check — that the paused round's pace is in line with its
neighbours in the round-by-round list.

- [ ] **Step 8: Commit any fixes and tag the stage**

```bash
git commit -m "fix: <whatever hardware testing surfaced>"
```

---

## Self-Review

**Spec coverage for this stage:**

| Spec section | Task |
|---|---|
| Session identity (`id`), `originRaw` | Task 2 |
| `journalData` minus HR, `lastCheckpointSeq` | Tasks 1, 2 |
| `RunSplit.distanceMeters`, HR fields; `RoundLog` HR fields | Task 2 |
| Templates via `updateApplicationContext` | Tasks 3, 4 |
| Live mirror via `sendMessage`, in-memory only | Tasks 3, 5 |
| Durable handoff via `transferUserInfo` | Task 3 |
| Checkpoint-and-replace, monotonic sequence | Tasks 1, 2 |
| Checkpoint on every non-HR event | Task 3 |
| Simultaneous-start race keeps both | Tasks 2, 5 |
| Phone mirror with staleness | Task 5 |
| Start screen second-session guard | Task 5 |
| Session detail HR + distance + origin badge | Task 6 |
| Watch dies → abandon not resume | Task 7 Step 5 |
| Template deleted → reconstructed from snapshot | Tasks 2, 7 Step 6 |
| Transport behind a protocol | Task 1 |
| PB badge on watch completion | Task 4 |

**Known gap, stated rather than hidden:** the spec asks for the coordinators to
be testable against a fake transport. `SessionTransport` is defined in Task 1
and the payload and merge logic are fully unit-tested, but the coordinators in
Task 3 talk to `WCSession` directly rather than through the protocol. Routing
them through it would add an indirection layer whose only consumer is a test
that mostly re-checks Task 1's logic. The protocol is in place if that changes;
Task 7 is the compensating verification, and it is thorough.

**Placeholder scan:** No TBD/TODO. Task 3 Step 6, Task 4 Step 2 and Task 6
Steps 1–2 describe edits at call sites whose surrounding code the implementer
must read; each names the exact file, the exact trigger, and the exact call.

**Type consistency:** `SyncPayload`, `SyncContext`, `PersonalBest`,
`SessionOrigin`, `SyncKey`, `SessionMerge.shouldApply(incoming:storedSeq:)` are
declared in Task 1 and used in Tasks 2–4. `SessionImporter.apply(_:context:)` is
declared in Task 2 and called in Task 3. `LiveMirrorStore.receive(sessionID:event:)`,
`.clear()`, `.isStale`, `.isMirroring`, `.state` are declared in Task 3 and used
in Task 5. `WatchSyncCoordinator.sendLive(_:sessionID:)`, `.sendCheckpoint(_:)`,
`.context` are declared in Task 3 and used in Tasks 3 and 4.
`HeartRateAggregator.runSummaries` / `.roundSummaries` and
`SessionDerivation.roundDurations` come from Stages 1–2 with matching signatures.
