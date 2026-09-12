# Watch-mirror layout — implementation plan

## Context

`MurphPlus/Views/Session/MirroredSessionView.swift` is the phone's read-only
reflection of a session owned by the Apple Watch. Today it shows a banner, an
elapsed clock, one or two badges, and a single "Rounds N of M" line — on a
full phone screen. Worse, the banner is visibly stretched to fill all the
leftover height.

Two approved designs (chosen from a mockup canvas):

- **Live state → "Segment ladder" (direction A).** Elapsed hero, badges, then
  three segment rows — Run 1 / Rounds / Run 2 — each with its time, a detail,
  and a bar showing its share of elapsed. Below, the round counter and tick row.
- **Completed state → "Timeline spine" (direction D) + the PR delta from B.**
  A vertical spine down the left with the three segments sized in proportion to
  their real durations, each labelled with its time and detail, a round-pace bar
  chart inside the rounds segment, and — the borrowed element — a line under the
  total reading e.g. "↓ 2:14 faster than your best".

### The architectural decision this plan rests on

The live view is driven by `LiveMirrorStore`'s `SessionState`, as today. The
**completed** view is NOT. It is driven by the phone's own saved
`MurphSession`, looked up by `mirror.sessionID`.

Why: `LiveMirrorStore` is explicitly "allowed to be lossy" (its own doc
comment) while the durable checkpoint path through `SessionImporter` "is not".
Concretely, the saved model carries things `SessionState` simply does not have:

- `RoundLog.maxHeartRate` / `RunSplit.maxHeartRate` — peak heart rate.
  `SessionState` only keeps `latestHeartRate`, so peak is unobtainable from the
  mirror.
- `RoundLog.completedAt` per round — authoritative round splits, where the live
  channel could have dropped a round event.
- The session is already in history by then, so the personal-best comparison is
  a local query rather than a sync round-trip.

`SessionImporter.apply` keys the saved session on the same `sessionID` the
mirror holds (`SessionImporter.swift:16-19`), so the lookup is direct.

**The race is real and must be handled:** the terminal live event can arrive
before the durable checkpoint lands. The completed view therefore falls back to
the cached mirror state when the saved session is not there yet, and upgrades to
the saved session when it appears. Neither state may flash "no data".

## Global Constraints

- Design-system discipline: no raw colours, fonts, or spacing numbers. Only
  `MurphColor`, `MurphSpacing`, `MurphShape`, and `.murphType(...)` tokens.
  A raw literal where a token exists is a defect (a prior branch was corrected
  for exactly this).
- Pure derivation logic goes in `MurphPlus/Support/`, NOT `MurphCore/`.
  `project.yml` compiles `MurphCore` into the watchOS target, whose sources do
  not include `MurphPlus/Support/`; logic that touches phone-only formatters or
  SwiftData models must not live in MurphCore. Follow
  `MurphCore/RunModeStatus.swift` for doc-comment style — comments explain WHY
  a rule exists, never what the code does.
- TDD: tests first, failing for the right reason, then implementation.
- Test command (that exact simulator is required — it is the watch-paired one):
  `xcodebuild test -project MurphPlus.xcodeproj -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- The watch target must also still build:
  `xcodebuild build -project MurphPlus.xcodeproj -scheme MurphPlusWatch -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 2 (49mm)'`
- Baseline is 375 tests / 0 failures. The suite must stay green.
- `xcodegen generate` after adding ANY new file. Never commit `MurphPlus.xcodeproj`.
- **Do not touch `MurphPlus/Support/DistanceFormatting.swift`.** A separate
  branch is moving it to `MurphCore/`; editing it here creates a merge conflict.
  Calling `formatMiles` / `formatMilesValue` is fine — they stay in-module
  either way.
- Do not touch `MurphPlusWatch/`, `LiveSessionView.swift`, or `RunHeroMetric.swift`.
- Behaviour that must not regress: the staleness banner ("Disconnected, showing
  last known state") and its reasoning; the completion state surviving
  `LiveMirrorStore.clear()`; not walking a finished clock past its final time
  (today's `finishedElapsed`); and a second workout started on the Watch
  resetting the finished state rather than drawing live under "Workout complete".

## Task 1 — Fix the stretched banner

`MurphPlus/DesignSystem/Components/MurphBanner.swift:32` draws its accent rule
as `Rectangle().fill(tone.accent).frame(width: 3)`. A `Rectangle` is greedy in
both axes; constraining only the width leaves the height greedy, so inside any
container that offers unbounded height — `MirroredSessionView`'s
`.frame(maxHeight: .infinity)` VStack — the banner absorbs every spare point.

Fix it so the rule matches the text's height and the banner is always its
natural size. The rule must still span the full height of the banner including
its vertical padding (that is the look today on the screens where it renders
correctly).

`MurphBanner` is used at 6 other call sites — `StartView.swift:458`,
`TemplateEditorView.swift:69`, `HistoryView.swift:51`,
`SessionDetailView.swift:262` and `:268`, plus `MirroredSessionView` — all
inside scroll views, which is why only the mirror screen shows the bug. Verify
by reading each that the fix changes nothing for them.

Add a test if one can be written meaningfully at the model level; if the fix is
purely a layout modifier with no testable surface, say so in your report rather
than writing a test that asserts nothing.

## Task 2 — `MirrorSegments`: the live segment ladder's data

Create `MurphPlus/Support/MirrorSegments.swift` + `MurphPlusTests/MirrorSegmentsTests.swift`.

A pure derivation from a `SessionState` to the three rows the live view draws:

```swift
enum MirrorSegmentState: Equatable { case done, current, ahead }

struct MirrorSegment: Equatable {
    let label: String        // "Run 1" | "Rounds" | "Run 2"
    let value: String        // "8:42", or "—" when ahead
    let detail: String?      // "1.02 mi", "12 of 20", "2:02 avg", nil
    let fraction: Double     // 0...1, share of elapsed; 0 when ahead
    let state: MirrorSegmentState
}

static func of(_ state: SessionState, now: Date) -> [MirrorSegment]
```

Rules:
- Always exactly three segments, in order, whatever the phase — a row that
  disappears mid-workout would make the screen jump.
- Run 1 / Run 2 read their duration and distance from `state.runSplits`
  (`RunSplitState.index` is 1-based; distance is optional — indoor runs have
  none, and the detail is then nil, never "0.00 mi").
- The in-progress segment's `value` is its elapsed-so-far, derived from
  `state.currentPhaseStartedAt` net of pauses via
  `state.pausedSeconds(between:and:)` — a paused stretch must not inflate it.
- Rounds' detail is "N of M" while current, "M rounds" when done; add the
  average round time when at least one round is complete.
- `fraction` is each segment's share of total elapsed, so the three bars sum to
  at most 1. A segment not yet started is 0.
- Use `formatDuration` and `formatMiles` — do not re-implement either.

Tests, each with a comment naming the regression it catches: the not-started
state (three rows, all ahead, no crash with no splits); mid-run-1; mid-rounds
with run 1 logged; mid-run-2 with both prior segments; an indoor run (distance
detail absent, not "0.00 mi"); a paused session (the current segment's value
does not include the pause); and fractions summing to <= 1.

## Task 3 — `SessionRecap`: the completed spine's data, including the PR delta

Create `MurphPlus/Support/SessionRecap.swift` + `MurphPlusTests/SessionRecapTests.swift`.

A pure derivation from a saved `MurphSession` plus the prior bests, to
everything the completed view draws. Shape it as the view needs it — at
minimum:

- `total: String`, and the three segments with durations, details, and each
  one's **proportion of the total** (the spine's segment heights — these are
  real, not projected, so no estimation is involved).
- `roundSplits: [Double]` (seconds per round, from consecutive
  `RoundLog.completedAt`, first measured from `roundsStartedAt`), plus the
  fastest and slowest for the bar chart's colouring, and the average.
- `peakHeartRate: Int?` — the max of `maxHeartRate` across `roundLogs` and
  `runSplits`; nil when no sample was ever recorded (do not render 0).
- `negativeSplit: String?` — e.g. "↓ 0:30 negative split" when run 2 beat
  run 1; nil otherwise (do not render a positive split as a failure).
- `personalBestDelta: (text: String, isImprovement: Bool)?` — the borrowed
  element. Compute against the fastest COMPLETED session with the same template
  **and** the same `vestOn`, **excluding this session's own id** (it is already
  in history by now, so including it would always compare against itself).
  Vest state is part of the identity, never a tiebreak — follow the reasoning
  already written in `MurphCore/PersonalBestCheck.swift`. With no prior
  matching session, this is nil: a first attempt has nothing to beat, and
  badging one would claim a best that does not exist.
  Faster → "↓ 2:14 faster than your best". Slower → "1:12 off your best".

Take the prior bests as an injected parameter (an array or a small lookup
closure), NOT by querying SwiftData inside this type — that is what keeps it
testable without a store, and it matches how `PersonalBestCheck` is written.

Tests: a normal completed session; one with no prior attempt (nil delta); one
slower than the best; one where the only prior attempt has a different vest
state (nil delta — vest is identity); a session with no heart-rate samples
(nil, not 0); a positive split (nil, not a negative-split line); and round
splits derived correctly including the first round measured from
`roundsStartedAt`.

## Task 4 — The two view components

Create `MurphPlus/DesignSystem/Components/MurphSegmentLadder.swift` and
`MurphPlus/DesignSystem/Components/MurphTimelineSpine.swift`.

Read `MurphSplitRow.swift`, `MurphRoundCounter.swift` and `MurphStatTile.swift`
first and match their idiom and file-header comment style. `MurphSplitRow`
already renders a label + value + optional `fraction` bar — if the ladder row
is that component, USE it rather than writing a near-duplicate; only build a
new row if the segment row genuinely needs more (a third detail column, a state
tone).

`MurphSegmentLadder(segments: [MirrorSegment])` — the three rows. Done reads in
`bone300`/muted, current in `hazard500`, ahead in `ash400`.

`MurphTimelineSpine(recap: SessionRecap)` — the spine: a 6pt vertical bar whose
three sections are sized by the recap's proportions, with labels alongside and
the round-pace bar chart inside the rounds section. The spine must not collapse
or overflow at small heights.

Accessibility is load-bearing on this project (recent commits fixed VoiceOver
regressions): each segment is ONE element reading a full sentence
("Run 1, 8 minutes 42 seconds, 1.02 miles, done"), not a pile of fragments. The
round-pace bar chart is decorative detail on top of a spoken summary — give it
one label (e.g. "20 rounds, fastest 1:48, slowest 2:31") rather than 20
unlabelled bars.

No new unit tests are expected for purely presentational components; the logic
under them is tested in Tasks 2 and 3.

## Task 5 — Rewire `MirroredSessionView`

- Live: banner, elapsed `MurphClock(size: .lg)`, badges (phase, paused, bpm),
  then `MurphSegmentLadder`, then the round counter and tick row. Keep the
  staleness banner behaviour and its comment exactly.
- Completed: look up the saved `MurphSession` by `mirror.sessionID` via
  `@Environment(\.modelContext)` / a `@Query`, build a `SessionRecap`, and draw
  `MurphTimelineSpine` under the total and the PR delta line, with the existing
  "Done" button. **Fall back to the cached mirror state when the saved session
  has not arrived yet**, and upgrade when it does — never flash empty.
- The personal bests for the delta come from the phone's own history; source
  them the same way `HistoryView` / `HistoryStats` already do rather than
  inventing a second path.
- Preserve `finishedElapsed`, the `didFinish` reset on a new session, and every
  existing explanatory comment whose reasoning still applies. Where a comment's
  code moves, move the comment with it.

**Verification:** full suite green; watch target builds; then render the four
states (live mid-rounds, live mid-run, completed with a PR, completed without a
prior attempt) to PNGs with a temporary `ImageRenderer` harness at scale 3 on
`MurphColor.surfacePage`, write them to `/tmp/murph-mirror/`, DELETE the harness
before committing, and report the paths.
