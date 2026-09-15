# Four ways in: watchOS 27

iOS 27 and watchOS 27 shipped on 2026-09-14. Nothing in this app is broken by
them — the installed build was compiled against the iOS 26 SDK, the new gates
fire at build time, and the deployment floors (iOS 17.0, watchOS 10.0) sit well
inside what Xcode 27 still accepts. There is no forced migration: this app is
dev-signed and installed with `xcrun devicectl` (`scripts/install-to-devices.sh`),
so the April 2027 App Store SDK deadline does not apply to it.

So this spec is not a compatibility exercise. It is about four things the watch
app could do and does not, three of which have been possible for a while and one
of which is genuinely new in 27.

---

## What is actually new, and what merely isn't done

**New in iOS 27 / watchOS 27:** HealthKit tracks heart-rate and cycling-power
zones natively — `HKWorkoutZoneConfiguration`, `HKWorkoutZoneGroup`,
`HKLiveWorkoutZoneUpdate`, and a new
`workoutBuilder(_:didUpdateWorkoutZone:)` delegate callback. This is the only
item here that did not exist before this month.

**Not new, but absent from this project:** Double Tap
(`.handGestureShortcut(.primaryAction)`, watchOS 11+), App Intents (watchOS 9+),
and Smart Stack widgets (watchOS 10+). watchOS 27 raises the value of all three
— the Smart Stack now surfaces widgets contextually and adds a single-tap
gesture to open the suggested one, and App Intents is the documented route into
the new Siri — but none of them required this release. They were simply never
built. A repo-wide grep confirms it: no `WidgetKit`, no `AppIntents`, no
`ActivityKit`, no `handGestureShortcut`, and no extension targets at all —
`project.yml` defines exactly two apps and one test bundle.

Being honest about which is which matters, because it sets the order of work
below. The genuinely new thing is not the most valuable thing.

## Scope

**In:** Double Tap on the advancing action; HealthKit workout zones; a
`StartMurph` App Intent; a Smart Stack widget.

**Out:** Live Activities on the phone, Workout Buddy (no third-party API),
Foundation Models (on watchOS it has no on-device model and always goes to the
network — a poor fit mid-workout, see Open questions), route recording, and any
change to the phone's UI beyond what the zone summary needs.

**Also out: the Xcode 27 move itself.** It is a precondition, not part of this
design, and it is written up separately below only because none of this compiles
without it.

---

## Precondition: the toolchain move

Xcode 27 accepts iOS 15–27 and watchOS 9–27, so the current floors need no
change *to build*. Four things in this tree are worth looking at on the first
compile, in descending order of likelihood:

1. **`WatchLiveView.swift:39`.** Apple's watchOS 27 notes say that in apps built
   against the watchOS 27 SDK, `TabView.selection` updates only once the user
   crosses the 50% threshold between pages, rather than as the offset begins to
   change. This view is a four-slot `.verticalPage` TabView binding `selection`,
   and two things drive that binding programmatically: the once-only
   `.onAppear` initial-page set (`WatchLiveView.swift:57-61`) and the DEBUG
   `WatchLayoutHarness`. Re-screenshot all four pages.
2. **`@State` is a macro in Swift 6.4, not a property wrapper.** Three sites
   assign the backing store directly in `init`: `MurphPlusApp.swift:32`,
   `MurphPlusWatchApp.swift:13-14`. The pattern that breaks is setting a default
   *at the declaration* and reassigning in `init`; none of these do, so this
   should pass, but it is the first compile error to look for.
3. **Liquid Glass is no longer optional** — the `UIDesignRequiresCompatibility`
   opt-out is ignored by the iOS 27 SDK. This app never set that key and was
   already built against the iOS 26 SDK, so it is already rendering Liquid
   Glass; 27 is a refinement, not a cliff. Two surfaces are still exposed:
   `MurphDialog.swift:24-25` (`.ultraThinMaterial`, the only system material in
   the app, and materials changed how they diffuse content underneath), and
   `RootTabView.swift` — `.tabItem` plus
   `.toolbarBackground(MurphColor.surfaceCard, for: .tabBar)` plus
   `.toolbarBackground(.visible, for: .tabBar)`, paired with
   `.safeAreaInset(edge: .bottom)` at `StartView.swift:74`. That combination is
   the app's most exposed surface to the floating tab bar's inset behaviour.
4. **`MurphFlowLayout.swift:86` reads `UIScreen.main.bounds.width`.**
   Deprecated since iOS 16, and it is the default for `MurphFlowWidth.screen`,
   so it sizes badge rows in `LiveSessionView`, `MirroredSessionView` and
   `SessionDetailView`. iOS 27 makes apps live-resizable (iPhone Mirroring on
   Mac, large iPad displays), which is exactly the case a width snapshotted from
   `UIScreen.main` gets wrong. Worth replacing with the containing view's size
   while in the area.

**Verified 2026-09-15, Xcode 27.0 (27A266a), iOS 27.0 SDK: the project builds
clean.** `xcodebuild -scheme MurphPlus -destination 'generic/platform=iOS'`
succeeds with no errors. Item 2 is therefore settled — the `@State` macro
accepts all three `init` assignments as written. The only warnings are
pre-existing Swift 6 language-mode ones (the project is on `SWIFT_VERSION 5.0`):
`WatchSyncCoordinator`'s `SessionTransport` conformance crossing actor
isolation, two nonisolated references to main-actor statics, and
`AnyInsettableShape`'s non-`Sendable` stored closure — none of them new in this
SDK, all of them errors whenever Swift 6 mode is adopted. Plus one benign
XcodeGen artefact about a file reference in multiple groups.

Items 1, 3 and 4 are runtime and visual, not compile-time, so a clean build says
nothing about them. They still need eyes on hardware.

Not applicable, checked: the UIScene lifecycle mandate hits UIKit `AppDelegate`
apps, and both `@main` types are SwiftUI `App` with no AppDelegate. The
launch-screen requirement is already met by
`INFOPLIST_KEY_UILaunchScreen_Generation: true` (`project.yml:33`).
`WKExtension`/`WKExtensionDelegate` are deprecated at a watchOS 9.2+ floor and
this app uses neither.

## The deployment-target decision

This decides how much of the rest of the spec is gating code rather than
feature code, so it comes first.

Each part below has its own floor: Double Tap needs watchOS 11, zones need
watchOS 27, App Intents (watchOS 9) and widgets (watchOS 10) are already under
the current floor. The codebase today contains **zero** `@available` or
`#available` — grep returns nothing across the tree. Every API in it is assumed
present at the floor. So this spec either introduces the first version gating in
the project, or moves the floor.

### What raising the floor would actually cost

watchOS 27 is not an ordinary year. It supports **Series 9, Series 10, Series
11, Ultra 2, Ultra 3 and SE 3 — and nothing else**, dropping Series 6, 7, 8,
SE 2 and Ultra 1 in one go. Against the current floor:

| Floor | Watches that can install |
|---|---|
| watchOS 10.0 — current | Series 4 and later, SE 1 and later |
| watchOS 11.0 | Series 6 and later, SE 2 and later |
| watchOS 27.0 | Series 9 and later, Ultra 2 and later, SE 3 |

A watchOS 27 floor therefore excludes **every Apple Watch older than a Series
9**. On the phone side iOS 27 dropped no models relative to iOS 26, but iOS 26
had already cut the A12s, so an iOS 27 floor additionally excludes iPhone XS,
XS Max and XR.

For an app whose entire subject is bodyweight work — pull-ups, push-ups, squats,
no equipment — that is close to the worst possible segment to cut. The hardware
this workout needs is a bar and a floor.

### "Install last supported version" does not help here

The App Store does keep older builds available: a device that cannot run the
current version is offered the last one that fits. It is automatic and there is
nothing to configure. But it has two limits that make it useless as cover for
raising the floor now.

**It only offers versions that were actually published.** It is a record of what
you shipped, not a compatibility shim. This app has never been on the App Store,
so there is no history to fall back to — ship v1.0 at a watchOS 27 floor and a
Series 8 owner gets nothing, permanently, because no compatible version ever
existed.

**It is scoped to Apple IDs that have already downloaded the app.** Even with a
history, a genuinely new user on old hardware cannot reach the older build
without first acquiring the app on a newer device under the same Apple ID.

The mechanism protects people who already have the app from a floor you raise
*later*. It does nothing for people who never got a chance to install it. The
useful conclusion is the inverse of the one it suggests: **shipping early at a
low floor is what creates the fallback**, so keeping the floor low now is also
what makes raising it later survivable.

### The tool for this is availability gating, not the floor

These are two different settings and only one of them is about exclusion:

- **Deployment target** decides who can *install*.
- **`#available`** decides what they *get* once installed.

One binary serves everyone. A Series 4 installs it and logs a Murph. A Series 11
installs the same binary and additionally gets zones and Double Tap. That is
precisely what availability checking exists for, and it is the standard answer to
the concern.

### The cost of gating, honestly

An earlier draft of this spec recommended raising the floor to watchOS 27, on the
grounds that this app is sideloaded to two devices with no install base to
strand, and that a `#available(watchOS 27, *)` inside `WatchSessionController`
would be a branch the iOS test bundle could never take. The first premise is
wrong — this is meant to be usable by other people — and the second was
overstated.

It was overstated because of how this code is already arranged:

- The zone logic that matters is `ZoneAggregator`, a pure function in `MurphCore`
  over journaled events. It has no availability requirement at all and is fully
  testable from the existing iOS bundle. That is where the behaviour worth
  testing lives.
- What actually needs gating is the thin HealthKit wrapper inside
  `WorkoutSessionController` — which **already has no unit tests**, by design,
  and already sits behind the `WorkoutControlling` seam with
  `FakeWorkoutController` standing in for it.

So the untestable branch lands inside the one type that is untested anyway. The
gate costs a few lines in a file that is already excluded from the test bundle's
reach, and costs nothing in `MurphCore`.

### Decision

**Keep watchOS 10.0 and iOS 17.0. Gate per feature.**

| Part | Floor | Gate |
|---|---|---|
| 1 · Double Tap | watchOS 11 | `if #available(watchOS 11, *)` around one modifier |
| 2 · Workout zones | watchOS 27 | `if #available(watchOS 27, *)` in `WorkoutSessionController` only |
| 3 · App Intent | watchOS 9 | none — under the floor |
| 4 · Smart Stack widget | watchOS 10 | none — at the floor |

The two gated features are also the two that are **hardware**-limited
independently of the OS: Double Tap needs Series 9 or Ultra 2 and later, and
zones need watchOS 27, which needs the same generation of hardware. So the gates
exclude exactly the people the hardware had already excluded, and nobody else. A
Series 6 owner loses nothing they could ever have had, and keeps the whole app.

Everything below is written against this decision, and each part names its own
gate rather than assuming one global floor.

---

## Part 1 — Double Tap

**Cheapest thing here, and the one whose value is specific to this workout.**
Murph is 100 pull-ups, 200 push-ups and 300 squats. The moment you need to log
a round is the moment your hands are on a bar or in chalk. A gesture that
advances the round without touching the screen is worth more here than in most
apps, and Apple provides it: `.handGestureShortcut(.primaryAction)` on a
`Button` or `Toggle` makes it the Double Tap target, with the system drawing the
highlight automatically.

### The problem this runs into

`WatchPrimaryButton` is documented as appearing on **both** metric pages so that
logging a round never requires swiping first (`WatchPrimaryButton.swift:3-5`).
There are four call sites:

- `PrimaryPage.swift:25` — "Resume"
- `PrimaryPage.swift:28` — the advance action
- `ClockPage.swift:36` — "Resume"
- `ClockPage.swift:39` — "Round Done" / "End Run"

Only one element at a time may be `.primaryAction`. Both pages are constructed
by the same `TabView` body, so a naïve modifier inside `WatchPrimaryButton`
would declare the primary action **four times**, and which one wins is not
something this design should leave to SwiftUI. The two pages that carry no
primary button — `ControlsPage` (tag 0) and `NowPlayingPage` (tag 3) — raise the
same question from the other side: Apple's rule is that Double Tap fires the
primary action only if the control is on screen, and scrolls toward it if not.

### Design

**The modifier does not go in `WatchPrimaryButton`.** It takes a parameter, and
`WatchLiveView` decides — because `WatchLiveView` is the only type that knows
which page is showing.

```swift
struct WatchPrimaryButton: View {
    let title: String
    var disabled: Bool = false
    var isPrimaryGesture: Bool = false   // new, defaults to off
    let action: () -> Void
}
```

applied as `.handGestureShortcut(isPrimaryGesture ? .primaryAction : nil)` — or,
if the modifier does not accept a nil shortcut, behind a plain `if`.

`PrimaryPage` and `ClockPage` each take the flag from `WatchLiveView`, which
passes `selection == 1` and `selection == 2` respectively. At most one button
claims the gesture, and it is always the one the user is looking at.

**Pause and Resume do not get the gesture.** Only the advancing action does.
Resume is already the whole screen on a paused session, and making the gesture
mean "advance" on one page and "resume" on another would make it unpredictable
in exactly the situation — mid-set, not looking — where it has to be reliable.
On a paused session the gesture simply does nothing.

**Pages 0 and 3 claim nothing.** The system's scroll-toward-it behaviour is the
correct fallback: from the Controls page a Double Tap moves you toward the
advancing button rather than firing an action you cannot see.

### What this depends on

Double Tap is hardware-gated to Apple Watch Series 9 and later and Ultra 2 and
later. There is no API to ask whether the gesture is available, and no fallback
is needed — on older hardware the modifier is inert and the button still works
by touch.

### Gate

`if #available(watchOS 11, *)` around the modifier, nothing else. On watchOS 10
the button renders and works by touch exactly as it does today — which is also
what happens on every watch older than a Series 9 regardless of OS, since the
gesture is hardware-limited. The gate and the hardware exclude the same people.

---

## Part 2 — HealthKit workout zones

The genuinely new API, and a good fit: this app already runs an
`HKLiveWorkoutBuilder`, already reads heart rate off it, and already segments
the session into `.running` and `.functionalStrengthTraining` activities
(`WorkoutSessionController.swift:143`, `:152`, `:174`). Zones come back per
activity as well as for the whole workout, so **time-in-zone on the rounds
versus time-in-zone on the two miles is free** once zones are on at all. That
split is the interesting number in a Murph and the app cannot currently produce
it.

### Where it goes

All of it in `MurphPlusWatch/Session/WorkoutSessionController.swift`.

Before `beginCollection` (`:92`), ask for the user's own configuration and fall
back to a default:

```swift
let heartRate = HKQuantityType(.heartRate)
if try await builder.zoneConfiguration(for: heartRate) == nil {
    let bpm = HKUnit.count().unitDivided(by: .minute())
    let boundaries = Self.defaultZoneThresholds.map { HKQuantity(unit: bpm, doubleValue: $0) }
    let configuration = try HKWorkoutZoneConfiguration(
        quantityType: heartRate, zoneBoundaries: boundaries
    )
    try await builder.setCustomZoneConfiguration(configuration, for: heartRate)
}
```

Ordering is load-bearing: a custom configuration must be set **before**
`beginCollection`, which is already the next statement. Zone counts are bounded
at 3–9; boundaries are contiguous and non-overlapping, the first zone open-ended
below and the last open-ended above.

Live updates arrive through a new delegate method on the existing
`HKLiveWorkoutBuilderDelegate` conformance (`:209`):

```swift
nonisolated func workoutBuilder(
    _ workoutBuilder: HKLiveWorkoutBuilder,
    didUpdateWorkoutZone zoneUpdate: HKLiveWorkoutZoneUpdate
) { ... }
```

It follows the isolation rule the existing two callbacks already establish
(`:214`, `:216`): read only from the parameter, then hop to the main actor
before touching any stored property. One new `private(set) var currentZone: Int?`
beside `currentHeartRate` (`:35`), surfaced on `WatchSessionController` as a
computed property beside `heartRate` (`WatchSessionController.swift:80`).

**Every rule in this file still applies.** Zones are a capability, not a
requirement: if authorization is denied or the configuration throws, the session
runs to completion with no zone and nothing blocks
(`WorkoutSessionController.swift:19-21`).

### Gate

`if #available(watchOS 27, *)` around the configuration call and the delegate
method, both inside `WorkoutSessionController`. Nothing in `MurphCore` is gated:
`ZoneAggregator` is a pure function over journaled events and compiles and tests
at the floor. Below watchOS 27 the boundaries event is simply never written, the
phone finds none, and the session detail omits the zone split — the same
absent-not-zero shape `HeartRateAggregator` already uses for a session with no
heart-rate samples (`HeartRateAggregation.swift:17`).

This is the whole reason the derived-on-the-phone design matters beyond
tidiness: the expensive half of the feature lives where no gate reaches it.

### The architectural call: the phone derives the summary

The tempting design is to read `workout.zoneGroupsByType?[HKQuantityType(.heartRate)]`
off the finished `HKWorkout` and ship the durations to the phone. **Don't.**

The phone does not import HealthKit at all — `WorkoutSessionController` is the
only file in the tree that does — and the watch already journals
`heartRate(bpm:at:)` every five seconds (`WorkoutSessionController.swift:39`,
throttle at `:42`). Those events are the journal, the journal is the sync
payload, and they already reach the phone's SwiftData store; `SessionRecap`
reads peak heart rate out of them today (`SessionRecap.swift:172`). Time in zone
is a pure function of that stream plus the zone boundaries.

So: **HealthKit provides zones live on the watch. The phone computes the summary
from heart-rate events it already receives.** That is the same argument
`HeartRateAggregator` already makes for itself — "deliberately derived rather
than accumulated in running state: a crash cannot corrupt a partial average, and
the aggregation can be changed later without re-recording anything"
(`HeartRateAggregation.swift:11-14`). Zones are the same shape of problem and
get the same answer. No HealthKit on the phone, no new SwiftData property, no
change to `SyncPayload` or `SessionImporter`.

What the phone still needs is the **boundaries**, which are the user's and not a
constant. One additive event:

```swift
case zoneBoundaries(bpm: [Double], at: Date)
```

journaled once, immediately after `started`. And one new pure type beside the
existing aggregator:

```swift
// MurphCore/ZoneAggregation.swift
enum ZoneAggregator {
    static func durations(
        events: [SessionEvent], boundaries: [Double], from: Date, to: Date
    ) -> [TimeInterval]
}
```

Bucketing each sample into its zone and attributing the interval to the next
sample — same windowing `HeartRateAggregator.summary(events:from:to:)` already
does, so per-round and per-phase splits come from the existing boundaries in
`SessionDerivation`.

**One hazard to name.** `SessionJournal.decodeLines` is
`compactMap { try? decoder.decode(...) }` (`SessionJournal.swift:95-101`), so a
reader that does not know a case **silently drops that line** rather than
failing the file. That is the right behaviour here and makes the new case safe
to add — but it is silent, so a watch writing `zoneBoundaries` to a phone that
cannot decode it produces a session with no zones and no error anywhere. Both
apps ship from one build and one build number by construction
(`Config/Version.xcconfig`), so this can only happen if that invariant is broken.
Worth a line of comment at the new case saying so.

### Picked up in the same file

`WorkoutSessionController` conforms to `HKLiveWorkoutBuilderDelegate` but **not**
`HKWorkoutSessionDelegate`. Session state changes (`.running`, `.paused`,
`.ended`) and `didFailWithError` are never observed — a HealthKit session that
fails mid-workout does so silently today. This is not a watchOS 27 matter, but
it is twelve lines in the file this part already opens, and the failure it
covers is the same class the rest of the file is careful about.

---

## Part 3 — A `StartMurph` App Intent

App Intents is the documented route into the new Siri on watchOS 27, and it also
buys Spotlight, the Shortcuts app and the Action Button for free. "Start my
Murph" while walking to the bar is the case.

### What makes this harder than it looks

The setup screen collects three things before a session can start — template,
vest (on/off plus weight), indoor/outdoor — and `startSession` requires all of
them (`WatchSessionController.swift:176`). An intent has none.

Two of the three are already durable: `@AppStorage("watchVestOn")`,
`("watchVestWeight")`, `("watchIndoor")` (`WatchSetupView.swift:57-59`). The
template is not; the setup view falls back to `effectiveSelection`, which
resolves to the first template in the list.

**Design: the intent starts the last-used configuration**, reading the three
defaults and resolving the template the same way `effectiveSelection` does. It
takes no parameters in v1. A parameterised version ("start a Half Murph") is a
clean later addition once `TemplateSpec` is exposed as an `AppEntity`, and is
out of scope here.

### Two constraints it must not break

**It does not bypass the countdown or the GPS gate.** The intent lands the user
on the setup screen with the start action already fired — the same path the
Start button takes (`WatchSetupView.swift:103-136`), countdown, gate and all.
Skipping them would mean starting an outdoor run with a cold receiver, which is
the exact failure `2026-09-11-watch-gps-distance-design.md` exists to remove,
and would give the user no way to cancel a workout they started by voice.

**Watch only.** The phone must not gain a way to start a session, because it
does not reliably have one to give: the Start tab already offers Begin while the
watch owns a live session, and the mirror-staleness cause is identified but
deliberately unfixed (`docs/ROADMAP.md`, §3, and
`docs/superpowers/specs/2026-09-04-mirror-staleness-vs-pause-design.md`). Adding
a voice-triggered second entry point to a guard that is known not to hold would
make an open bug worse and harder to see. The iOS target gets no
`AppShortcutsProvider` until §3 is closed.

**Resume is not an intent either**, for the same single-writer reason: resuming
is offered once, on launch, after journal reconciliation, and the ordering there
is load-bearing (`WatchSetupView.swift:185-205`).

### Shape

`MurphPlusWatch/Intents/StartMurphIntent.swift` — an `AppIntent` with
`openAppWhenRun = true`, plus an `AppShortcutsProvider` declaring the phrases.
The intent writes a small request flag the setup view observes on appear; it
does not reach into `WatchSessionController` directly, because the countdown and
gate live in the view and this must go through them.

---

## Part 4 — A Smart Stack widget

Most expensive of the four, and the one with a real structural obstacle.

watchOS 27 surfaces Smart Stack widgets contextually — Apple's example is
workout controls appearing when you arrive at the gym — and adds a single tap to
open the suggested one. A widget showing "Start Murph", or the live round count
when a session is running, is a good fit for that.

### The obstacle: there is no App Group

A widget extension is a separate process. This app's watch-side state is in two
places, neither reachable from one:

- The journal, at `URL.documentsDirectory/sessions`
  (`WatchSessionController.swift:43`) — the app container, not shared.
- `@AppStorage` on `UserDefaults.standard` (`WatchSetupView.swift:57-59`).

The entitlements file carries only the two HealthKit keys
(`MurphPlusWatch/MurphPlusWatch.entitlements`). So this part cannot be built
without adding `com.apple.security.application-groups` to the watch app and the
new extension.

### Do not move the journal

The obvious move — relocate `sessions/` into the App Group container so the
widget can replay it — is the wrong one, twice over:

1. The journal is both the watch's persistence **and** its sync payload
   (`SessionJournal.swift:5-8`). Moving its directory is a migration over files
   that may be mid-flight: unfinished sessions the resume prompt will offer, and
   finished ones awaiting acknowledgement that `reconcileJournals` will resend
   (`WatchSessionController.swift:470`). Getting that wrong loses a workout,
   which is the failure mode the whole sync design is organised around.
2. A widget has no business replaying an event log to render two lines of text.
   `SessionJournal.all` already decodes every line of every journal on the main
   actor at launch; putting that in a widget timeline is worse.

**Design: a purpose-written snapshot, not shared source of truth.** The watch
app writes a small `Codable` struct — phase, completed rounds, total rounds,
started-at, terminal flag — into the App Group container at the transitions it
already owns (`startSession`, `advance`, `pause`, `resume`, `finishAndReset`),
the same set `LocationPolicy` is reconciled at today. The widget reads only
that. It is derived, disposable, and regenerable from the journal if it is ever
missing or stale; nothing depends on it being correct except the widget.

That keeps the journal untouched, keeps the widget's read cheap, and means a
corrupted or absent snapshot degrades to "Start Murph" rather than to a wrong
workout.

### Shape

A new `MurphPlusWatchWidget` target in `project.yml`, `type: app-extension`,
`platform: watchOS`, embedded in the watch app. Two families:
`accessoryRectangular` (Smart Stack and the rectangular complication slot — note
that watchOS 27's Siri Modular face mirrors the top Smart Stack widget into a
complication, so one implementation covers both) and `accessoryCircular`.

Relevance is what makes this worth building rather than just available: the
widget supplies relevant dates via the App Intent `RelevantContext` API so the
Smart Stack floats it when it matters. A live session is the strongest signal
and needs no heuristic.

Tapping it opens the app; on a live session it should land on `WatchLiveView`,
which today is reachable only by `navigationDestination(isPresented: $showLive)`
from the setup view (`WatchSetupView.swift:141`). That deep link needs the same
flag mechanism Part 3 introduces, which is why these two are sequenced together
below.

---

## Order, and what each costs

| # | Part | New targets | Entitlement | Touches | Rough size |
|---|---|---|---|---|---|
| 1 | Double Tap | — | — | 3 files | one afternoon |
| 2 | Workout zones | — | — | 4 files, 1 new type, 1 event case | a day |
| 3 | App Intent | — | — | 2 files, 1 new dir | a day |
| 4 | Smart Stack widget | 1 | App Group | project.yml, entitlements, snapshot writer, widget | two to three days |

Parts 1 and 2 are independent of everything. Part 4 depends on Part 3 for the
deep-link flag. Do them in this order; each is separately shippable and
separately revertable.

## Testing

Everything testable runs from the existing iOS bundle, as it does today. The
hardware wrappers stay untested, consistent with `WorkoutSessionController`
having no unit tests now.

**Part 1** has no unit test — it is one modifier and a boolean. It is verified
on hardware: Double Tap on the metric page advances the round; on the clock page
it advances the round; on the controls page it scrolls toward the button rather
than firing; on a paused session it does nothing.

**Part 2 — `ZoneAggregationTests`**, table-driven over the pure function, beside
`HeartRateAggregationTests`. Samples entirely inside one zone; samples crossing
a boundary; an empty window returning no durations rather than zeros (the
absent-not-zero rule `HeartRateAggregator` already sets,
`HeartRateAggregation.swift:17`); a window with one sample; boundaries of
minimum (3) and maximum (9) zone counts. Plus a `SessionEvent` round-trip test
for the new case, and one asserting that a journal line holding an **unknown**
case is dropped without failing its neighbours — pinning the tolerance at
`SessionJournal.swift:95-101` that makes the addition safe.

**Part 3** — the intent's resolution logic (which template, which vest, which
location mode, given defaults) is pure and testable; the `perform()` that sets
the flag is not. Assert that absent defaults resolve to the same template
`effectiveSelection` picks.

**Part 4 — snapshot round-trip tests**: each transition writes what the widget
expects; a finished session writes terminal; an absent snapshot decodes to
nothing rather than throwing.

**On hardware, in order:**

1. `plutil -p` the built watch app and confirm the App Group is present in the
   built product, not just `project.yml`. This project has been bitten by a key
   that existed in source and not in the build
   (`2026-09-11-watch-gps-distance-design.md`, Background modes).
2. Double Tap through a full Murph without touching the screen to log a round.
3. A full outdoor Murph, then check Fitness for zone data on the workout and the
   phone's session detail for the derived time-in-zone split — rounds versus
   runs. **This is Part 2's acceptance test**: the two numbers should differ
   substantially, and if they do not, the activity segmentation is not reaching
   the zone groups.
4. "Hey Siri, start my Murph" — confirm the countdown and GPS gate both appear.

## Open, to settle on hardware

**Does `zoneConfiguration(for:)` return anything if the user has never set zones
in the Health app?** The design falls back to a default configuration when it
returns nil, so either answer works — but which path is normal decides whether
the default thresholds are load-bearing or nearly dead code.

**Are the default thresholds right for this user?** They ship as one named
constant, as the GPS accuracy threshold did. Murph under a vest is not a
steady-state effort and the generic bands may compress the whole workout into
one zone, which would make the feature useless without being wrong.

**Does the primary-action highlight fight the custom button styling?**
`WatchPrimaryButton` uses `.buttonStyle(.plain)` with a hand-drawn background
and `clipShape` (`WatchPrimaryButton.swift:19-22`). The system draws its own
outline for the Double Tap target; whether that lands correctly on a plain-styled
button with a custom shape is not something to assert from documentation.

**Does the snapshot write cost anything on the advance path?** It is a small
file written on a transition that already writes a journal event and flushes it
(`SessionJournal.append`, `SessionJournal.swift:41-52`). Expected to be noise
against that, but the advance path is the one the user is waiting on.

**Foundation Models was considered and rejected for now.** It would be a natural
fit for `SessionRecap` and `FatiguePrediction`, both of which already produce
structured output a model could narrate. But on watchOS it has no on-device
model — every call goes to Private Cloud Compute or another provider over the
network — which is wrong for a wrist mid-workout. If it is worth doing it is
worth doing on the phone, against a finished session, and that is a different
spec.

## Sources

- [Deliver workout insights with HealthKit workout zones — WWDC26](https://developer.apple.com/videos/play/wwdc2026/207/)
- [watchOS 27 release notes](https://developer.apple.com/documentation/watchos-release-notes/watchos-27-release-notes)
- [Enabling the double-tap gesture on Apple Watch](https://developer.apple.com/documentation/watchos-apps/enabling-double-tap)
- [What's new in watchOS 11 — Double Tap API](https://developer.apple.com/videos/play/wwdc2024/10205/)
- [Build widgets for the Smart Stack on Apple Watch — WWDC23](https://developer.apple.com/videos/play/wwdc2023/10029/)
- [Apple SDK minimum requirements (April 2027)](https://developer.apple.com/news/upcoming-requirements/)
- [watchOS 27 compatibility — supported and dropped models](https://9to5mac.com/2026/06/08/watchos-27-compatibility-list/)
- [watchOS 27 drops five Apple Watch models](https://9to5mac.com/2026/06/19/watchos-27-drops-support-for-five-apple-watch-models-heres-why/)
- [iOS 27 keeps iPhone 11 and newer compatibility](https://appleinsider.com/articles/26/06/08/ios-27-keeps-iphone-11-and-newer-compatibility)
- [App Store: downloading the last compatible version](https://developer.apple.com/forums/thread/708901)
