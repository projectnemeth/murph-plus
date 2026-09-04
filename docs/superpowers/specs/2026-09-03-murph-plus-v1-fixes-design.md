# Murph Plus — v1 Fix Batch Design Spec

Date: 2026-09-03
Status: Approved for planning

## Overview

Five corrections to the shipped v1 phone app, arising from real use. All are
presentation or seed-data changes — **none touches `SessionEngine`**, so this
batch is independent of, and can ship before, the Apple Watch work in
`2026-09-03-murph-plus-watch-design.md`.

Pause was raised alongside these and is deliberately **not** here. It belongs
to the Watch work, where the event-sourced core lets the round-duration
correction be written once for both platforms instead of built twice.

## 1. The Inert Close Button, and the Misplaced Abandon

**Two reported problems with one cause and one fix.**

`LiveSessionView.swift:54` declares the toolbar's close button as
`disabled: phase != .completed`, and `MurphIconButton` renders a disabled
button at `opacity 0.35`. It is not broken logic — it is deliberately dead for
the entire workout, only becoming live at the finish. But it presents as a
persistent, visible affordance that does nothing for fifty minutes.

Separately, `LiveSessionView.swift:112–121` stacks the danger-variant
**Abandon** button directly beneath the primary action with a single
`MurphSpacing.space3` gap — putting a destructive control in the thumb zone
immediately under a button the user taps twenty times while exhausted.

**Fix: give the toolbar slot to Abandon during an active session, and to Close
only at `.completed`.**

- `phase != .completed` → toolbar trailing shows **Abandon** (danger tone),
  opening the existing `showAbandonConfirm` dialog. No dead affordance.
- `phase == .completed` → toolbar trailing shows **Close** (`xmark`), enabled,
  calling `onFinished()` as it does today.
- The `Abandon` button is removed from the bottom action stack entirely, which
  leaves the primary action alone in the thumb zone.

This also aligns the phone with the Watch design, where destructive actions
live on a separate Controls page rather than beside the advancing button.

## 2. Half and Mini Murph Are Cindy-Style

`DefaultTemplates.swift` seeds both `halfMurph` and `miniMurph` with
`rounds: 1` (straight sets). Both should be partitioned Cindy-style, and their
rep totals already divide perfectly into 5/10/15 sets:

| Template | Reps | Rounds | Per round |
|---|---|---|---|
| Half Murph | 50 / 100 / 150 | **10** | 5 / 10 / 15 |
| Mini Murph | 25 / 50 / 75 | **5** | 5 / 10 / 15 |

Names gain their round count, matching the convention the Full templates
already use (`Full Murph (Cindy-Style, 20 Rounds)`): **`Half Murph (10
Rounds)`** and **`Mini Murph (5 Rounds)`**.

### The migration is the real work here

`seedIfNeeded` returns early when the store is non-empty, so **editing the
constants fixes nothing on any existing install** — not the developer's, not
any TestFlight tester's. Without a corrective migration this change appears to
do nothing when tested.

A one-time migration, gated behind a `UserDefaults` flag, runs at launch after
seeding. For each of the two templates it corrects **only if the stored record
still matches the shipped default exactly** — original name, original three rep
totals, original run distance, and `rounds == 1`. If any field differs the user
has edited it, and it is left completely alone.

Sessions already performed against these templates are untouched: they keep
their logged round data, and `WorkoutTemplate`'s inverse relationship uses
`.nullify`, so no history is at risk.

## 3. Abandoned Sessions Should Show How Far You Got

An abandoned session is a record of partial progress — "I set out to do a full
Murph, finished run 1 and 15 of 20 rounds, and stopped" — not a write-off.

**The data is already there.** `SessionEngine.abandon()` retains every
`RoundLog` and `RunSplit`, leaves `completedRounds` intact, and sets
`completedAt`. What fails is presentation:

- `SessionDetailView.swift:140` renders total time as an em-dash captioned
  "Abandoned before finishing" — discarding an elapsed time that is fully
  derivable, since both `startedAt` and `completedAt` are set.
- `MurphSessionRow` shows a bare "Abandoned" badge with no indication of
  progress.

**Fix:**

- **Session detail** shows the real elapsed time at the moment of abandonment
  rather than a dash, captioned to make clear it is a stopping point and not a
  finish. Add a progress line naming the phase reached and the rounds
  completed — e.g. `Stopped during rounds · 15 of 20 · 375 of 600 reps`.
  Logged run splits and round-by-round pace continue to display as they
  already do.
- **History row** gains the round progress alongside the existing dust-toned
  "Abandoned" badge, so the log is scannable without opening each session.
- Sessions abandoned before any round completes state the phase reached
  (`Stopped during run 1`) and omit the rounds figure rather than printing
  `0 of 20`.

Personal-best and trend statistics continue to consider completed sessions
only; nothing about this change lets a partial attempt compete with a finished
one.

## 4. Start Screen Title

`StartView.swift:18` renders `MurphScreenTitle(title: "Start Murph")`. It
should read **`Murph+`** — the app's name, not an instruction.

## Testing

The seed migration is the only piece with logic worth unit testing, and it is
the piece most likely to go wrong:

- an untouched default Half/Mini template is corrected (rounds and name)
- a user-edited template matching on name but differing in reps, distance, or
  rounds is left completely alone
- the migration is idempotent and does not re-run once flagged
- a fresh install seeds the corrected values directly and does not need the
  migration at all

The abandoned-session progress derivation is worth a small test for the
boundary cases: abandoned during run 1, abandoned mid-rounds, abandoned during
run 2.

The remaining three changes are visual and verified by hand: the toolbar shows
Abandon during a session and Close only at completion, Abandon no longer sits
in the bottom stack, and the start screen reads `Murph+`.
