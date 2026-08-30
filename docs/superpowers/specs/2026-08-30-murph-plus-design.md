# Murph Plus — Design Spec

Date: 2026-08-30
Status: Approved for planning

## Overview

Murph Plus is a native iOS app for tracking attempts at the "Murph" workout
(1 mile run, 100 pull-ups, 200 push-ups, 300 air squats, 1 mile run — often
done in a 20lb weighted vest), and its scaled-down variants. It replaces
ad-hoc notes/spreadsheets with a purpose-built live workout tracker and
history log.

**Audience:** the developer plus friends/gym community, distributed via
TestFlight. Not a public App Store release (for now).

**Scope for this version (v1):** in-workout live tracker + workout
history/log, including a calendar view and calculation-based finish-time
prediction. Explicitly deferred:
- **v2:** structured training plans ("trainer" — build toward a full Murph)
- **v3 (roadmap, contingent on v1/v2 traction):** social features /
  leaderboards comparing times across friends/gym

## Tech Stack & Architecture

- **Platform:** iOS only, native Swift.
- **UI:** SwiftUI.
- **Persistence:** SwiftData, using its built-in CloudKit integration for
  sync across the user's own devices. No shared backend — each person's
  data is private to their own iCloud account; there is no cross-user data
  sharing in v1 (that's what v3's social layer would add later).
- **Pattern:** MVVM.

This was chosen over Core Data (more mature CloudKit sync, but more
boilerplate — fallback option if SwiftData sync proves flaky during
implementation) and over TCA (better testability/scaling, but overkill for
an app whose only complex state is a single live-session state machine).

**Minimum iOS version:** iOS 17+ (required for SwiftData).

## Data Model

### `WorkoutTemplate`
A reusable definition of "what the workout consists of" — deliberately not
tied to fixed Full/Half/Mini tiers. Fields:
- `name: String`
- `runDistanceMiles: Double` (default 1.0, applies to each of the two runs)
- `totalPullUps: Int`, `totalPushUps: Int`, `totalSquats: Int` (defaults
  100/200/300)
- `rounds: Int` (1 = straight sets; >1 = partitioned, reps-per-round =
  totals ÷ rounds)

Ships with a couple of starter templates (Full Murph straight sets, Full
Murph Cindy-style 20 rounds). Users can create their own by editing any of
the above fields directly — "Half Murph" or "Mini Murph" are just templates
a user saves with smaller numbers, not app-defined concepts.

### `MurphSession`
One attempt (in-progress, completed, or abandoned):
- `date: Date`
- `template: WorkoutTemplate` (reference)
- `vestOn: Bool`, `vestWeightLbs: Int?` (defaults to 20 if vest on and left
  blank)
- `status: enum { inProgress, completed, abandoned }`
- `notes: String?`
- derived: total elapsed time (from run splits + round logs)

### `RunSplit`
Belongs to a `MurphSession`:
- `runIndex: Int` (1 or 2)
- `startTime: Date`, `durationSeconds: Double`

### `RoundLog`
Belongs to a `MurphSession`:
- `roundNumber: Int`
- `completedAt: Date`

Per-round duration and per-round seconds/rep are derived from consecutive
`RoundLog` timestamps plus the template's reps-per-round — this is what
powers both the history detail view and the fatigue-adjusted prediction
calculation.

## Pre-Session Setup

Before starting: pick a `WorkoutTemplate` (defaults to a starter template),
toggle vest on/off, and if on, enter vest weight (defaults to 20lbs if left
blank).

## Live Session Flow

A single state machine drives the workout screen:

```
notStarted → run1 (timer) → rounds (1...N) → run2 (timer) → completed
```

- One primary action per state (Start Run, Round Done, Finish) — the screen
  reconfigures around the current state rather than switching UI modes.
- Elapsed time is one continuous clock from first "Start" tap through
  completion; run splits and round timestamps are markers along it.
- **Round entry:** a single "round done" tap per round (not per-exercise
  counters) — matches how partitioned WODs are actually done in practice.
- **Backgrounding/app kill:** session state is persisted to SwiftData
  continuously (not just at completion). Elapsed time is recomputed from a
  stored start timestamp on foreground/relaunch, not from an in-memory
  timer. On relaunch with an in-progress session found, offer to resume or
  abandon it.
- **Abandon:** confirm-guarded action. Abandoned sessions are kept in
  history (flagged incomplete), not deleted.
- **Run tracking:** simple start/stop timer for v1, no GPS. GPS route/pace
  tracking (Core Location + MapKit) is a possible v1.1/v2 enhancement, not
  required now.

## History / Log

- List view, most recent first: date, total time, template name, vest
  status, completed/abandoned status.
- Stats header: personal best, most recent time, trend vs. last attempt.
- Session detail: run splits, round-by-round pace, notes, and the
  prediction control (below).
- Delete allowed (with confirm) for correcting mistakes; no editing of
  logged times — the log stays a trustworthy record.
- No filtering/sorting/comparison beyond this in v1 (low session volume
  expected for a single user).

## Calendar View

- A segment/toggle within History (not a separate tab) showing a month
  grid. Days with a session get a marker: filled = completed, hollow/other
  color = abandoned, blank = no attempt.
- Tapping a day with a session opens its detail (same screen as the list).
  Tapping an empty day does nothing in v1 — sessions are only created via
  the live tracker, not logged retroactively.
- Month navigation via prev/next or swipe; defaults to current month.
- Reuses `MurphSession` data directly — no new model.

## Predicted Finish Time

Calculation-based (no AI/ML), derived entirely from a single source
session's own data, applied to a different target `WorkoutTemplate`.

**Work rate (reps), fatigue-adjusted:** Each round in the source session has
a known duration (gap between consecutive `RoundLog` timestamps) and known
rep count (from its template), giving seconds/rep per round. Fit a
least-squares line to seconds/rep vs. cumulative reps completed:
`secPerRep = a + b × cumulativeReps`, where `a` is the fresh starting pace
and `b` is the measured fatigue slope. Predicted work time for a target rep
total: `predictedWorkTime = a × targetReps + b × targetReps² / 2` (the
integral of the fitted rate line) — this extrapolates the user's own
observed fatigue curve rather than assuming a flat rate.
- Requires ≥3 rounds in the source session to fit a meaningful trend.
  Straight-sets (1 round) sessions have no intra-session fatigue signal —
  fall back to a flat rate (`sessionWorkDuration ÷ sessionTotalReps`), with
  a note in the UI that a partitioned attempt gives a better prediction.

**Run pace:** Uses the source session's two *actual* runs directly — run 1
(pre-fatigue) pace applied to the target's first run distance, run 2
(post-workout) pace applied to the target's second run distance. This is
the user's own measured pre/post fatigue differential, no curve-fitting
needed since we only have two data points.

**Total predicted time** = predicted run1 time + predicted work time +
predicted run2 time.

**Vest matching (hard rule):** predictions only use a source session whose
vest on/off status matches the target scenario. If no matching-vest history
exists yet, no prediction is offered for that combination — vest and
non-vest data are never mixed, even as a soft caveat.

**Surfacing:** a secondary "Predict another distance" control on a
session's detail view (not front-and-center) — pick any template, see the
projected time computed from that session's data.

## Navigation / IA

Tab bar with three tabs:
1. **Start** — template picker + vest toggle → live session
2. **History** — list view (default), with a Calendar segment/toggle
3. *(Session detail is pushed from History or Calendar, not a top-level tab)*

## Error Handling / Edge Cases

- App killed mid-session: detected on relaunch via persisted in-progress
  session; user chooses resume or abandon.
- No completed sessions yet: History/Calendar show an empty state; the
  prediction control doesn't appear until eligible source data exists.
- Past sessions can be deleted (confirm-guarded) but not edited.

## Testing

- Unit tests for the two calculation-heavy pieces: the fatigue
  regression/prediction math, and the session state machine transitions.
- Manual/UI testing for SwiftUI flows — no dedicated UI test framework
  investment for v1.

## Deferred to Later Versions

- **v2:** structured training plans building toward a full Murph.
- **v3 (roadmap):** social features / leaderboards comparing times across
  friends and gym community.
- Possible v1.1+: GPS-tracked runs (route/pace via Core Location + MapKit).
