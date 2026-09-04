# Murph Plus — Apple Watch Companion (v2) Design Spec

Date: 2026-09-03
Status: Approved for planning
Supersedes: the "v2: Apple Watch companion app" sketch in
`2026-08-30-murph-plus-design.md`

## Overview

An Apple Watch companion that makes the wrist the primary in-workout surface.
Murph is performed with hands on a pull-up bar and on the floor; tapping "round
done" twenty times on a phone is the wrong ergonomics, and a wrist tap is the
right one. The Watch also collects data the phone cannot — heart rate — and
registers the workout with HealthKit so the screen stays awake and the effort
lands in the user's Activity rings.

**Scope:** live session capture on the wrist (setup, runs, rounds, pause,
abandon, completion), heart rate and distance capture, HealthKit workout
registration, and bidirectional sync with the phone. Plus **pause**, which
lands on both platforms as part of this work.

**Not in scope:** history, calendar, session detail, prediction, or template
editing on the Watch. Those stay on the phone. Browsing your log is a couch
activity; the Watch is a workout instrument.

## Decisions Taken

These were settled during brainstorming and are not open for re-litigation
during planning:

| Decision | Choice |
|---|---|
| Device availability | Either device may be absent; neither can assume the other |
| Session ownership | Single writer, **fixed at start**. No handoff, no dual input |
| Watch scope | Session only, plus minimal setup |
| Heart rate | Captured and stored per round and per run; **not** fed into prediction |
| Run distance | Live distance and pace, manual stop, no auto-advance, no route map |
| Phone during a Watch session | Live read-only mirror |
| Watch live UI | Four pages, hard stops at both ends (no wrap-around) |
| Pause | Ships with this work, not before |

The two rejected options worth recording: **dual-writable sessions** were
refused because a round logged on both devices while disconnected is a genuine
conflict with no correct resolution, and it corrupts the round timestamps the
fatigue prediction reads. **CloudKit as the durable transport** was refused
because it requires network the Watch will not have when the phone is absent,
and two devices writing to one CloudKit zone reintroduces the duplicate-record
problem.

## Architecture

### Targets

Add `MurphPlusWatch`, a modern single-target watch app (`WKApplication`, no
separate extension), bundle ID `com.projectnemeth.MurphPlus.watchkitapp`,
`WKCompanionAppBundleIdentifier` pointing at the phone app, embedded into the
phone target's `Watch` directory. Deployment target **watchOS 10**, the natural
pair for the existing iOS 17 floor.

### `MurphCore`

A new top-level `MurphCore/` directory, listed in the `sources` of **both** app
targets in `project.yml`. Compiled into each binary directly — no framework
target, no `import`, no dynamic linking. `MurphPlusTests` already depends on
`MurphPlus`, so `@testable import MurphPlus` reaches these types with no
test-target changes.

**Hard rule: `MurphCore` imports `Foundation` and nothing else.** No SwiftData,
no SwiftUI, no HealthKit, no WatchConnectivity. This is what keeps the Watch
free of the phone's CloudKit-shaped schema, and it is mechanically checkable.

Contents:

- `SessionEvent` — the `Codable` event enum (below)
- `SessionState` — a plain struct produced by folding an event array
- `SessionStateMachine` — transition rules and terminal guards, operating on
  `(SessionState, TemplateSpec)`, returning either an event or a rejection
- `TemplateSpec` — value-type snapshot of a template's numbers
- `SessionDerivation` — elapsed time, per-round durations, HR bucketing
- `SyncPayload` — the transfer envelope

### What happens to `SessionEngine`

It stays at its current path as the **phone's adapter**. It keeps its
`MurphSession` and `ModelContext`, but each method becomes *ask the state
machine for an event, then apply that event to SwiftData*.

Its public signatures (`start()`, `finishRun()`, `completeRound()`,
`abandon()`) and its terminal-guard behavior are preserved exactly, and
`LiveSessionView` should not need to change for the extraction itself.
**The existing `SessionEngine` tests must pass untouched** — that is the
contract on this refactor. If they need editing, the extraction changed
behavior it was not supposed to.

## Event Model

```swift
enum SessionEvent: Codable {
    case started(at: Date, templateID: UUID, template: TemplateSpec,
                 vestOn: Bool, vestWeightLbs: Int?, indoor: Bool)
    case runFinished(index: Int, at: Date, distanceMeters: Double?)
    case roundCompleted(number: Int, at: Date)
    case roundUndone(number: Int, at: Date)
    case paused(at: Date)
    case resumed(at: Date)
    case heartRate(bpm: Int, at: Date)
    case abandoned(at: Date)
}
```

Phase transitions are **implicit**, exactly as `SessionEngine` handles them
today: `started` begins run 1; `runFinished(1)` begins the rounds; the round
that reaches the template's total begins run 2; `runFinished(2)` completes the
session. No separate transition events.

**Undo** is permitted only when the last non-`heartRate` event is a
`roundCompleted`. That single rule allows correcting a mis-tap — including one
that just advanced the session into run 2, which reverts to the rounds phase
and discards the run-2 start — while making it impossible to unwind history
further back.

**Timestamps always come from the owning device**, and the receiving device
never restamps on receipt. Because every duration is a difference between two
timestamps from the same device's clock, clock skew between watch and phone
cannot distort a split. This is a property of the design and must not be
"helpfully" optimized away later.

## Pause

Pause exists so an interruption does not skew a logged time.

`paused`/`resumed` bracket an excluded interval. Two derivations must account
for it:

1. **Elapsed time** = `now − startedAt − Σ(paused intervals so far)`.
2. **Per-round duration** — and this is the trap. Round durations are derived
   from consecutive `RoundLog` timestamps, so a ten-minute pause between rounds
   7 and 8 makes round 8 look eleven minutes long. That figure feeds directly
   into the least-squares fatigue fit, so **pause time falling inside a round's
   interval must be subtracted from that round's duration.** A naive pause
   implementation silently poisons the exact data the app exists to produce,
   with no visible symptom.

While paused: `roundCompleted` and `runFinished` are rejected by the state
machine, heart rate is not sampled (the `HKWorkoutSession` is itself paused, so
collection stops), and the Watch's slot-2 primary action becomes **Resume**.

## Persistence

### Watch — an event journal

Each session is an append-only file at `sessions/<uuid>.journal`, one
JSON-encoded `SessionEvent` per line, flushed on write. State is rebuilt by
replay, so a crash or a watchOS eviction mid-workout costs at most the last
event (≤5s of heart rate).

On launch, a journal whose last event is non-terminal means an interrupted
session: the Watch offers **resume or abandon**, mirroring
`ResumableSessionFinder` on the phone. The journal is deleted only after the
phone acknowledges the terminal checkpoint by session ID.

### Phone — SwiftData remains the system of record

The phone stores each session's journal **minus `heartRate` events** (which are
bulky, already aggregated, and whose raw form lives in HealthKit), alongside
the derived aggregates.

This applies to **both** origins. A Watch-owned session stores the journal it
received; a phone-owned session builds the identical journal locally as
`SessionEngine` emits events, so `journalData` is populated the same way
regardless of which device ran the workout. `lastCheckpointSeq` is meaningful
only for received sessions and stays `0` for phone-owned ones.

Model additions, all optional or defaulted so they stay CloudKit-legal and
migrate lightly:

- `MurphSession`: `id: UUID`, `originRaw: String`, `pausedSeconds: Double = 0`,
  `indoor: Bool = false`, `lastCheckpointSeq: Int = 0`, `journalData: Data?`
- `RunSplit`: `distanceMeters: Double?`, `avgHeartRate: Int?`, `maxHeartRate: Int?`
- `RoundLog`: `avgHeartRate: Int?`, `maxHeartRate: Int?`
- `WorkoutTemplate`: `id: UUID`

`MurphSession.totalElapsedSeconds` must subtract `pausedSeconds`.

Existing v1 sessions keep `nil` for every new optional, so the detail view must
render the no-HR, no-distance case — which it must anyway for every
phone-owned session.

## Sync Protocol

Three channels, three jobs:

**Templates, phone → Watch.** `updateApplicationContext` carrying
`[TemplateSpec]`, sent on template create/edit/delete and on activation.
Latest-value-wins is exactly right here; a stale intermediate list is never
interesting.

**Live mirror, owner → observer.** `sendMessage`, fire-and-forget, only when
reachable. Symmetric — the same event type flows whichever device owns the
session. **The mirror is in-memory only:** the observing device persists
nothing from this stream. When the link drops the mirror goes stale and says
so.

**Durable handoff, Watch → phone.** `transferUserInfo`, which is queued,
guaranteed, and survives app termination and reboot.

### Checkpoint-and-replace

Every durable transfer carries `(sessionID, checkpointSeq, events)` — the
**entire journal so far**, not a delta. The owner increments `checkpointSeq` on
every checkpoint, and checkpoints on every non-`heartRate` event. The phone
applies a batch only when `checkpointSeq > lastCheckpointSeq` for that session
ID, replaying it wholesale.

That single rule makes application idempotent and monotonic: duplicate
deliveries are harmless, out-of-order deliveries are harmless, and a session
interrupted by a dead Watch battery has already landed on the phone up to its
last round.

### The simultaneous-start race

Each device refuses to start a session while it knows the other is running one.
If they race while disconnected they produce two sessions with two UUIDs, and
**both land in history as separate records**. Showing two sessions the user can
delete one of is strictly better than silently merging two workouts into one
corrupted round sequence.

## HealthKit

**One workout, three activities.** A single `HKWorkoutSession` typed
`.crossTraining` runs for the whole session, so Murph appears in Fitness as one
workout rather than three. Within it, `HKLiveWorkoutBuilder`'s activity
segmentation (`beginNewActivity` / `endCurrentActivity`, watchOS 9+) marks
`.running` for run 1, `.functionalStrengthTraining` for the rounds, and
`.running` for run 2. Segment boundaries are the same moments as the
`runFinished` and round events, so the two systems stay in step by
construction.

This segmentation is load-bearing for **calorie accuracy**: with
`.functionalStrengthTraining`, Apple estimates active energy primarily from
heart-rate elevation, which is the correct model for calisthenics — a
motion-driven estimate would badly under-count pull-ups, since the user burns
energy while going nowhere. The runs get the motion-and-pace model that suits
them.

**Heart rate.** `workoutBuilder(_:didCollectDataOf:)` delivers updates;
journaled as one `heartRate` event per 5 seconds. Live on-screen BPM reads the
builder's current statistics directly and is not journaled at display rate.
Per-round and per-run averages and maxima are **derived** by bucketing those
events between round and run timestamps — never tracked in running state, so a
crash cannot corrupt a partial aggregate.

**Distance.** Read from the builder's `.distanceWalkingRunning` statistics, but
accumulated **only during run activities**. Distance collected during the
rounds segment is discarded rather than added to a run split; otherwise pacing
between pull-up sets inflates the mile.

**Indoor vs outdoor** is chosen at setup and cannot change mid-session.
Outdoor enables GPS (accurate mile, real battery cost); indoor uses the
accelerometer.

**Always-on display.** The workout session keeps the app frontmost and the
screen alive — the primary reason for using one. In the dimmed always-on state,
updates drop to roughly once a minute per Apple's guidance: the clock renders
at minute resolution and BPM freezes at its last value, driven off the
`isLuminanceReduced` environment value.

**Permissions are all optional to the app functioning.** We request HealthKit
read (heart rate, distance), HealthKit share (workout), and
location-when-in-use. Deny HealthKit and the session still runs completely —
clock, rounds, splits, sync — with `nil` heart rate. Deny location and distance
falls back to the accelerometer. Nothing in the core tracker is gated behind a
permission prompt, and setup never blocks on one.

## Watch UI

### Setup

A single scrolling screen, no paging: the template list (synced from the
phone), then two segmented controls, then Start.

- `[ VEST | NO VEST ]` — preselected from last use, but both states always
  visible. Vest state is load-bearing data, not a preference: the prediction
  refuses to mix vest and non-vest sessions, so a wrong flag silently
  disqualifies the session as source data. A lone toggle reads as a settled
  state; a segmented control reads as a live choice.
- `[ OUTDOOR | INDOOR ]` — same control, per-session rather than
  preference-shaped.
- A weight chip (`20 lb`, Digital Crown adjustable) appears only when Vest is
  selected.

### Live session — four pages, hard stops

A plain paged `TabView` with the system page indicator. **No wrap-around** —
`TabView` does not support it, faking it requires clone pages and programmatic
selection snapping, and the native Workout app doesn't wrap either.

| Slot | Content |
|---|---|
| 1 · Controls | Pause/Resume · Undo last round · Abandon |
| 2 · Primary *(default)* | The number that matters now + the button that advances |
| 3 · Clock | Elapsed time as hero |
| 4 · Now Playing | System-provided view |

**Only slot 2 changes with phase.** During runs it is distance (hero) with
pace and remaining, plus **End Run**. During rounds it is round count (hero)
with the rep breakdown, plus **Round Done**. While paused it becomes
**Resume**. Slots 1, 3, and 4 are stable for the whole workout.

Two rules that make paging safe:

1. **The advancing button appears on both metric pages** (2 and 3). Paging
   changes what you *read*, never what you can *do* — logging a round never
   requires swiping first.
2. **Page position survives a phase change.** Finish run 1 while reading the
   clock page and you stay on the clock page; the workout changed underneath
   you, your position did not.

Undo is present but **disabled** during runs rather than absent, so the
Controls page does not reshuffle mid-workout.

Each page carries a two-cell status strip showing the metrics its hero doesn't:
a labelled banded row, not a caption.

### Completion

A single screen: total time, average BPM, the three splits, a PB badge when the
time beats the user's best for that template at that vest setting, and Done.
The session is already on its way to the phone when this appears.

## Phone Changes

All additive; a phone with no paired Watch behaves exactly as v1 does today.

- **`LiveSessionView` gains a mirror mode** — same screen, read-only: clock,
  phase, round X of N, live BPM, a "Controlled by Apple Watch" banner, controls
  disabled. It displays its own staleness ("updated 3s ago" → "Disconnected"),
  because a frozen clock with no explanation is worse than an honest one.
- **The Start screen guards against a second session.** While the phone knows a
  Watch session is live, Start is replaced by a "Session running on Apple
  Watch" state. If the link is down we cannot know, so it stays enabled — that
  is the race resolved above.
- **Session detail grows two columns, not new screens**: avg/max BPM beside the
  existing per-round pace, and measured distance beside each run split's
  duration, plus a small origin badge.
- **Pause control** on the phone's live session, matching the Watch.
- **Template push** on any create/edit/delete.

## Edge Cases

- **Watch dies mid-workout.** Checkpoints mean the phone already holds
  everything up to the last round, as an `inProgress` session. The phone may
  **abandon** it but never resume it — it does not own it. Resume is offered
  only on the Watch, from its journal.
- **Watch app force-quit mid-rounds.** Journal replay restores exact state; at
  most 5 seconds of heart rate is lost.
- **Template deleted while a session references it.** The `started` event
  carries both `templateID` and a full `TemplateSpec` snapshot. The phone links
  to the live `WorkoutTemplate` when the ID resolves and reconstructs from the
  snapshot when it does not, so history never loses what the workout actually
  was.
- **Phone reinstalled.** Queued `transferUserInfo` payloads still deliver.
- **Never-paired Watch.** Journals accumulate on the Watch and deliver whenever
  pairing occurs.

## Testing

`MurphCore` is pure Foundation, so the interesting logic is unit-testable with
no store and no device:

- state machine transitions, including every rejection path
- event replay and undo semantics (including undo across the run-2 boundary)
- elapsed and per-round duration derivation **with pause intervals**, which is
  the highest-risk math in this spec
- HR bucketing into round and run windows
- the checkpoint merge rule under duplicate and out-of-order delivery

`WatchConnectivity` is hidden behind a transport protocol so the coordinators
are testable against a fake; the framework itself is verified by hand.

**The existing `SessionEngine` tests must pass untouched.**

Manual matrix, on real hardware: phone-owned; Watch-owned with phone present;
Watch-owned with phone powered off; link dropped mid-rounds; Watch force-quit
mid-rounds; pause spanning a round boundary.

## Build Order

**First task is a throwaway spike:** `HKWorkoutSession` with activity
segmentation, on a real watch, confirming always-on dimming behavior and that
per-segment distance and energy behave as expected. This is the largest
remaining unknown and the one thing that cannot be validated in the simulator.

Then: `MurphCore` extraction (with the existing tests as the safety net) →
phone adapter → Watch persistence and state → Watch UI → sync layer → phone
mirror and detail changes.

## Deferred

- Heart rate as an input to the fatigue prediction. The data is captured from
  day one specifically so this becomes possible later, with real sessions to
  validate against rather than a formula designed on a hunch. Heart rate cannot
  be collected retroactively; the math can be invented at any time.
- GPS route recording and map rendering in session detail.
- History, calendar, or prediction on the Watch.
- A bare `HKWorkout` written for phone-only sessions (no HR, no energy) — worth
  doing, but an independent decision.
