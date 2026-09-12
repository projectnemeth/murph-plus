# Run distance hero — implementation plan

## Context

`MurphPlus/Views/Session/LiveSessionView.swift` shows, during a run phase, a 56pt
elapsed clock with the run distance as a 13pt muted caption beneath it
(`liveDistanceText`, line ~36). Everything below the hazard rule during a run is a
near-empty `phaseBody` branch rendering a `figure.run` icon and "0.25 MILE OUT".

The runner cannot read a 13pt caption while running. This plan makes distance the
hero numeral of the run screen.

Approved design:

- During `.run1` / `.run2`, **distance covered** is the giant numeral, with a
  progress bar toward the run target, and the elapsed clock demoted to a small
  secondary readout.
- When distance is unavailable — indoor sessions, or before the GPS fix is
  trustworthy — **elapsed takes the hero slot** instead, with a caption saying why
  distance is absent. No dead placeholder is ever shown in the hero.
- `.notStarted`, `.rounds` and `.completed` are unchanged.

## Global Constraints

- Design-system discipline: no raw colours, fonts, or spacings. Use
  `MurphColor`, `MurphSpacing`, `MurphShape` and `murphType(_:)` tokens only.
  New numeral sizes go through `MurphTypeStyle.clock(_:)`.
- `MurphCore/` holds pure, simulator-free logic and is where tested decision
  logic lives (see `MurphCore/RunModeStatus.swift` as the pattern to follow —
  including its doc-comment style, which explains *why* a rule exists).
- TDD: tests are written before the implementation they cover, and must fail
  for the right reason first.
- Test command (the `iPhone 17 Pro` simulator is the watch-paired one and is
  required):
  `xcodebuild test -project MurphPlus.xcodeproj -scheme MurphPlus -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- Run `xcodegen generate` after adding ANY new source file, or the build will
  not see it. `*.xcodeproj` is gitignored; do not commit it.
- Baseline is 366 tests passing. The suite must stay green.
- Do not modify `MurphPlusWatch/` or `MurphPlus/Views/Session/MirroredSessionView.swift`.
- Existing behaviour that must not regress: distance is shown only during run
  phases; an untrustworthy fix must never render as `0.00`.

## Task 1 — `RunHeroMetric` in MurphCore, with tests

Create `MurphCore/RunHeroMetric.swift` and `MurphPlusTests/RunHeroMetricTests.swift`.

A pure value type deciding what the hero slot shows. Follow `RunModeStatus` for
shape, naming and doc-comment style (explain *why*, not *what*).

```swift
enum RunHeroKind: Equatable { case distance, elapsed }

struct RunHeroMetric: Equatable {
    let kind: RunHeroKind
    let label: String        // "Distance" or "Elapsed" — the consumer uppercases
    let value: String        // the giant glyphs, e.g. "0.12" or "1:06"
    let caption: String?     // e.g. "MI OF 0.25", "Indoor · distance not measured"
    let progress: Double?    // 0...1, nil when no bar should be drawn
    let accessibilityText: String
}
```

Factory:

```swift
static func of(
    indoor: Bool,
    distanceIsTrustworthy: Bool,
    distanceMeters: Double?,
    targetMiles: Double?,
    elapsedSeconds: Double
) -> RunHeroMetric
```

Rules, in precedence order:

1. `indoor == true` → `.elapsed` hero. `label` "Elapsed", `value`
   `formatDuration(elapsedSeconds)`, `caption`
   `"Indoor \u{00b7} distance not measured"`, `progress` nil. `indoor` outranks
   every other input, exactly as in `RunModeStatus`.
2. `distanceIsTrustworthy == false`, or `distanceMeters == nil` → `.elapsed`
   hero, caption `"Waiting for GPS\u{2026}"`, `progress` nil.
3. Otherwise → `.distance` hero. `label` "Distance".
   - `value` is the miles figure to 2 decimal places, WITHOUT a unit suffix
     (the unit belongs in the caption): meters / 1609.344, formatted
     `.number.precision(.fractionLength(2))`.
   - With a `targetMiles`: `caption` is `"MI OF <target>"` where `<target>` is
     the target to 2 decimals; `progress` is `miles / targetMiles` clamped into
     `0...1` (overshooting the target pins the bar full, never past it).
   - With `targetMiles == nil` or `<= 0`: `caption` is `"MI"`, `progress` nil.
     A zero or negative target must not divide.
   - `accessibilityText` reads as a sentence, e.g.
     `"Distance 0.12 of 0.25 miles"`, or `"Distance 0.12 miles"` with no target.
     The elapsed-hero cases read e.g. `"Elapsed 1:06. Indoor, distance not measured."`

`formatMiles` in `MurphPlus/Support/DistanceFormatting.swift` returns a string
WITH the "mi" suffix, so it is not directly reusable for `value`; read it and
match its conversion constant and rounding rather than inventing new ones.

Tests must cover, each with a comment saying what regression it catches:
indoor beating every combination of the other inputs; untrustworthy fix; nil
meters with a trustworthy fix; the normal distance case; a nil target; a zero
target (no divide, no bar); overshoot clamping to 1.0; and progress at a plain
midpoint.

**Verification:** the new tests fail before the implementation exists, then the
full suite passes at 366 + new tests.

## Task 2 — `MurphMetricHero` component

Create `MurphPlus/DesignSystem/Components/MurphMetricHero.swift`.

A presentational component. It takes a `RunHeroMetric` plus an optional
trailing `note` string (used for "0.25 MILE OUT") and renders:

- A micro label row: `HazardPulseDot(size: 6)` when `running` is true, the
  uppercased `label` in `.micro` / `MurphColor.textMuted`, then a `Spacer()`,
  then `note` in `.micro` / `MurphColor.textMuted` when non-nil.
- The numeral: `value` in `.clock(96)`, `MurphColor.textPrimary`,
  `.monospacedDigit()`, `.lineLimit(1)` and `.minimumScaleFactor(0.5)` so a
  long duration such as `1:06:30` shrinks instead of clipping or wrapping.
- The caption, when non-nil: `.micro`, `MurphColor.textMuted`.
- The progress bar, when `progress` is non-nil: a full-width bar built from a
  `ZStack` of two `RoundedRectangle`s (track `MurphColor.ink700`, fill
  `MurphColor.hazard500`) at height 8, sized with a `GeometryReader` or
  `.containerRelativeFrame` — whichever reads cleaner — using `MurphShape`
  corner tokens. The fill animates with `MurphMotion`'s existing easing if one
  fits; no custom durations.
- The whole component is ONE accessibility element
  (`.accessibilityElement(children: .ignore)`) with
  `.accessibilityLabel(metric.accessibilityText)`, so VoiceOver reads one
  sentence rather than four fragments.

Read `MurphClock.swift` and `MurphRoundCounter.swift` first and match their
file-header comment style and construction. Read `MurphColor`, `MurphShape` and
`MurphMotion` before using any token, and use only tokens that exist.

**Verification:** project builds; suite still green. No new unit tests are
required for a purely presentational component — the logic under it is tested
in Task 1.

## Task 3 — Rewire `LiveSessionView`

Edit `MurphPlus/Views/Session/LiveSessionView.swift` only.

- Delete the `liveDistanceText` computed property; its string building now
  lives in `RunHeroMetric`.
- In the `TimelineView` block: when `phase` is `.run1` or `.run2`, render
  `MurphMetricHero` built from
  `RunHeroMetric.of(indoor:distanceIsTrustworthy:distanceMeters:targetMiles:elapsedSeconds:)`
  using `session.indoor`, `engine.runDistanceIsTrustworthy`,
  `location.runDistanceMeters`, `session.template?.runDistanceMiles` and
  `engine.totalElapsed`. Pass `note` as
  `"<target> MILE OUT"` for `.run1` and `"<target> MILE BACK"` for `.run2`,
  target formatted to 2 decimals — this is the copy the old `phaseBody` branch
  rendered, moved up into the hero header.
- Beneath the hero, when and only when the hero's `kind` is `.distance`, show
  a secondary `MurphClock(label: "Elapsed", seconds: engine.totalElapsed,
  size: .sm, running: <same running condition as today>)`. When the hero is
  already elapsed, omit this row — never show the clock twice.
- For every other phase, render today's `MurphClock(... size: .lg ...)` block
  exactly as it is now, unchanged.
- Remove the `phase == .run1 || phase == .run2` branch from `phaseBody`
  entirely (the `figure.run` + "N mile out" `HStack`), since the hero now
  carries that copy. Leave the `.rounds` and `.notStarted` branches untouched.
- Keep the `.padding(...)`, hazard rule, scroll view, logged splits and footer
  buttons structurally as they are.

**Verification:** run `xcodegen generate`, then the full suite. Then confirm
visually: boot the `iPhone 17 Pro` simulator, build and install the app, and
capture a screenshot of a live run screen showing the large numeral — attach
the path in your report. If driving the app to a run phase is not practical,
add a `#Preview` exercising `MurphMetricHero` in all three states (distance
with target, indoor, waiting for GPS) and screenshot that instead, saying
which route you took.
