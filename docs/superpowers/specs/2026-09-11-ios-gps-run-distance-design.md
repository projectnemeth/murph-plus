# GPS on the phone: the device that owns the session owns the receiver

The watch measures its runs. The phone does not measure anything.

`SessionEngine.finishRun()` passes `distanceMeters: nil`
(`MurphPlus/Session/SessionEngine.swift:49`), and `rebuildState` hardcodes `nil`
again on the resume path (`:238`). Every phone-origin session in history has a
duration for each run and a blank where the distance goes. The formatter that
would render it already exists and already works — `SessionDetailValue.run`
(`MurphPlus/Views/History/SessionDetailValue.swift:13-16`), fed by
`SessionDetailView.swift:178` — and watch-imported sessions display a real
number through it today. The phone simply never produces one.

This spec gives the phone its own GPS, on the same terms the watch got:
accurate where it matters, off where it does not.

---

## The ownership rule

**The device that owns the session owns the receiver.** One sentence, and it is
the whole answer to running two GPS chips at once.

It costs nothing to enforce because the conflict is already unreachable in the
direction that matters. `StartView.swift:34` hides the Begin button entirely
while `mirror.isMirroring`, with a comment that says why: "Two live sessions is
the one conflict this design refuses to resolve, so the guard is to make it
unreachable rather than to merge it afterwards." A watch-owned session therefore
cannot coexist with a phone-owned one, so the phone's receiver has no occasion
to power on while the watch's is running. The phone in your pocket during a
watch Murph is a mirror, and a mirror needs no sensors.

This is a rule, not a protocol. No handshake, no negotiation, no live phone→watch
channel — today the watch talks down and never listens up mid-session, and
nothing here changes that.

## Scope

**In:** an accurate run distance for phone-owned sessions, a live readout during
the runs, an Indoor/Outdoor choice at setup, and the background-location
plumbing that lets a pocketed phone keep measuring.

**Out:** route recording and any map, exactly as the watch spec ruled them out.
Also out: HealthKit on the phone (see below — it is not the shortcut it looks
like), any change to `SyncPayload`, `SessionImporter`, `PhoneSyncCoordinator`,
or the watch, and any change to `LocationPolicy`.

**`LocationPolicy` is reused untouched, known defect included.** The watch spec
documents that `safeRounds - completedRounds <= 1` is true from the first rep on
a single-round template, so `Full Murph (Straight Sets)` (`rounds: 1`,
`DefaultTemplates.swift:8`) keeps the receiver powered through the entire
calisthenics block. That is a real bug and the phone will inherit it. Fixing it
means a rep- or time-based trigger, it changes watch behaviour, and it belongs
in its own change where it can be reasoned about and measured on its own terms.
Deliberately inherited, not overlooked.

## Why the phone cannot copy the watch

The watch spec argues, correctly and at length, against deriving distance from
`CLLocation` deltas:

> Re-deriving distance from `CLLocation` deltas would be reimplementing that
> fusion, worse.

**That argument does not transfer to iOS, and the reason is worth writing down
because "why not just do what the watch does" is the first question any reader
will have.**

On watchOS the fusion is real: `HKLiveWorkoutBuilder` combines the GPS receiver
with the wrist accelerometer, and `distanceWalkingRunning` is the product of
both. **There is no `HKLiveWorkoutBuilder` on iOS.** It is a watchOS-only type.
On an iPhone, `distanceWalkingRunning` is pedometer-derived — the stride
estimate, with no location data in it at all. It is precisely the mechanism that
recorded 0.46 miles on a known 0.70–0.75 mile route and caused the watch work in
the first place.

So adopting HealthKit on the phone would mean adding a `com.apple.developer.healthkit`
entitlement and two permission prompts to a target that has zero HealthKit
today, in order to reproduce the exact defect this feature exists to remove. The
phone must derive its own distance. There is no fusion to defer to.

A hybrid — GPS as primary with `CMPedometer` bridging dropouts under bridges and
between buildings — is a real idea and a real improvement, but it means
inventing a fusion policy of our own, a third permission, and a reconciliation
rule for two numbers that disagree. The accumulator has to exist either way.
That is a v2 built on this, not part of this.

## Components

### `MurphCore/LocationSample.swift` — new, Foundation only

```swift
struct LocationSample: Equatable {
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var speed: Double          // m/s; negative means invalid
    var timestamp: Date
}
```

Foundation-only for the reason `LocationProviding` is: `MurphCore` compiles into
both targets, and the iOS bundle is the only test bundle in the project. Feeding
the accumulator plain values rather than `CLLocation` is what lets the one part
of this change that must be numerically correct be tested against recorded
traces, with no hardware and no simulator location fixtures.

### `MurphCore/RunDistanceAccumulator.swift` — new, pure

```swift
func add(_ sample: LocationSample, now: Date) -> Double
```

`now` is a parameter rather than a read of the clock, matching the idiom used
throughout `MurphCore` — `SessionStateMachine.start(…, now:)`,
`SessionDerivation.elapsed(state, now:)`. It keeps the type pure and the age
check (rule 3) testable.

Five rejection rules, each a named constant with its own test:

1. **`horizontalAccuracy < 0`** — reject. The sign is the validity flag, not a
   precision reading. Same trap `WatchLocationController.swift:113-114` already
   documents.
2. **`horizontalAccuracy > maxAccuracyMeters` (20)** — reject. The same *value*
   as the watch's gate threshold but a deliberately separate constant: the gate
   asks "is the receiver warm yet", this asks "is this delta trustworthy". They
   will want tuning independently.
3. **`now.timeIntervalSince(sample.timestamp) > maxSampleAgeSeconds` (5)** —
   reject. `startUpdatingLocation` delivers a cached fix first, sometimes minutes
   old and hundreds of metres away. Unfiltered, that single sample is a phantom
   half-kilometre at the start of every run.
4. **Implausible speed** — reject, checked both against the reported `speed`
   field when it is non-negative and against implied `delta / Δt`, with
   `maxSpeedMetersPerSecond` at 12. That is roughly world-record sprint pace, so
   it catches teleports and nothing a runner can do.
5. **Noise floor** — require `delta > max(sample.horizontalAccuracy,
   minimumDeltaMeters)`. The movement must exceed its own uncertainty. It is
   self-scaling, and it is what stops a stationary receiver's jitter summing
   into distance.

**A rejected sample must not become the new anchor.** This is the rule that is
easy to get backwards and expensive when you do. Keep the last *accepted* point
and measure the next delta from it. Update the anchor on rejection and slow
movement becomes permanently invisible: every individual delta falls under the
floor, is dropped, and the anchor chases you at exactly the speed that
guarantees nothing is ever counted. A fast run would read roughly right and a
slow one would read zero — the worst possible failure, because it looks like it
works.

Distance is haversine on a sphere (radius 6 371 008.8 m) rather than
`CLLocation.distance(from:)`, because the entire point of `LocationSample` is
that `MurphCore` never imports CoreLocation.

### `MurphCore/RunDistanceMeasuring.swift` — new

```swift
@MainActor
protocol RunDistanceMeasuring: AnyObject {
    var runDistanceMeters: Double? { get }
    func beginRun()        // clear the total AND the anchor, start
    func resumeRun()       // clear the anchor only, keep the total, start
    func stopMeasuring()   // halt; runDistanceMeters stays readable
}
```

A second seam rather than an extension of `LocationProviding`, so
`WatchLocationController` does not grow a property it can never meaningfully
answer. `runDistanceMeters` is named to match what `PrimaryPage.swift:79`
already reads on the watch, so the live readout is the same expression on both
devices.

**Receiver-on is not the same as measuring**, and the separation is the reason
this protocol exists at all. `LocationPolicy` powers the receiver during the
pre-warm at rounds-remaining ≤ 1, which is *before* run 2 begins. Tying the
measurement window to receiver power would put every step taken around the
pull-up bar during that pre-warm into run 2's distance. The window follows phase
transitions; the receiver follows the policy; they overlap but they are not the
same interval.

**`resumeRun` clears the anchor and that is the non-obvious half.** Pause, walk
to a water fountain, come back, resume. If the anchor survived the pause, the
first accepted sample after resume measures its delta from where you stood when
you paused, and the walk lands in the run as one lump. Dropping the anchor makes
a pause a genuine gap — which is consistent with the run's *duration*, already
net of pause everywhere else in this app.

### `MurphPlus/Session/PhoneLocationController.swift` — new

`@MainActor @Observable`, wraps `CLLocationManager`, conforms to
`LocationProviding & RunDistanceMeasuring`. Deliberately the sibling of
`WatchLocationController`: the only type in this change that touches hardware,
and the only one with no unit tests. It converts each `CLLocation` into a
`LocationSample` and hands it to the accumulator; that conversion is the whole
CoreLocation surface.

Configuration mirrors the watch — `desiredAccuracy = kCLLocationAccuracyBest`,
`activityType = .fitness`, `allowsBackgroundLocationUpdates = true` — plus one
the watch could not have. See **Background modes**.

### Changed: `SessionEngine`

```swift
init(session: MurphSession, context: ModelContext,
     location: (LocationProviding & RunDistanceMeasuring)? = nil)
```

Defaulted to `nil` so `SessionEngineTests` compiles and passes untouched. That
is not convenience: the file's own docstring calls that suite "the proof the
extraction preserved behavior", and spending it to add a sensor would be a bad
trade.

`perform` gains a reconcile step after `state.apply(event)` — assert
`LocationPolicy.shouldWarm(for: state)` against the receiver, and open or close
the measurement window on phase changes into and out of `.run1`/`.run2`. This
mirrors `WatchSessionController` exactly: the transitions are ones
`SessionEngine` already owns, no new events, no state-machine change, no journal
change. `finishRun()` passes `location?.runDistanceMeters` where it currently
hardcodes `nil` (`:49`).

### Changed: `RootTabView`

Owns one long-lived `@State private var location = PhoneLocationController()`
and injects it into **both** `SessionEngine` construction sites: `startNew` at
`:18` and the resume path at `:42`. One instance, because the receiver warms on
the setup screen and must still be the same object when the session begins.

The resume path is where `LocationPolicy`'s purity pays off — replay, ask the
policy, obey the answer, with no separate recovery branch.

### Changed: `StartView`

- An Indoor/Outdoor toggle, using the existing `MurphToggle` component. This is
  where `MurphSession.indoor` finally gets set by a human rather than defaulting
  to `false` because nobody was asked — `MurphSession.init`
  (`MurphPlus/Models/MurphSession.swift:50-55`) does not take it and never has.
- Location authorization requested in `.task`; receiver warmed while the user
  picks a template and sets the vest; stopped on Indoor and on disappear.
- Hosts the start gate (below).

`onBegin` is `(WorkoutTemplate, Bool, Int?) -> Void` today. Adding `indoor`
would put two adjacent unlabelled `Bool`s at the call site in
`RootTabView.swift:17-18`. It is replaced with a `SessionSetup` value — six
lines, and it removes a footgun rather than installing one. `MurphSession.init`
and `SessionEngine.startNew` both take `indoor: Bool = false`, defaulted so no
other caller changes.

### Changed: `LiveSessionView`

A distance readout during `.run1` and `.run2`, mirroring what the watch already
shows at `PrimaryPage.swift:40-86`. `metresPerMile` is currently a private
constant in `SessionDetailValue` (`:11`); it is hoisted so the live view and
history cannot drift apart.

**History needs no change.** `SessionDetailView.swift:178` already passes
`split.distanceMeters` to a formatter that handles both cases. Phone sessions
simply stop handing it `nil`.

## Lifecycle

| Moment | Receiver | Measuring |
|---|---|---|
| `StartView` appears, Outdoor | **start** — warm-up | — |
| Outdoor → Indoor toggle | stop | — |
| Setup left without beginning | stop | — |
| Begin tapped | gate (below) | — |
| Run 1 begins | running | **`beginRun()`** |
| Pause mid-run | **keeps running** | **`stopMeasuring()`** |
| Resume | running | **`resumeRun()`** |
| Run 1 ends | per policy → stop | `stopMeasuring()`; value read into `.runFinished` |
| Rounds, remaining > 1 | off | — |
| Rounds, remaining ≤ 1 | **start** — pre-warm for run 2 | **still off** |
| Run 2 begins | running | **`beginRun()`** |
| Run 2 ends / abandon | stop | `stopMeasuring()` |
| Indoor session, any phase | never | never |

The receiver keeps running through a pause — inherited from the watch, where
reacquiring a fix on resume costs more than a short pause saves — while
measuring stops. That asymmetry is the clearest illustration of why the two
concerns got separate seams.

## The start gate

`LocationFixGate` already exists, with logic and tests
(`MurphCore/LocationFixGate.swift`, `MurphPlusTests/LocationFixGateTests.swift`).
The phone becomes its second caller and adds nothing to it.

The gate lives in `StartView`, not `RootTabView`, because it must resolve
*before* `onBegin` fires — the session does not exist until then. Presented as
a `.fullScreenCover` with `.interactiveDismissDisabled()`, following the
reasoning already written at `RootTabView.swift:54-61`: a dismissible
presentation here would strand a half-started session.

Behaviour at Begin is the watch's, unchanged: `.off` (Indoor), `.denied` and
`.fixed` all pass through instantly; only `.acquiring` holds, with a
Start-anyway button available from the first frame and a 30-second bound. The
standing contract that no sensor may block the workout
(`MurphCore/WorkoutControlling.swift:13-16`) holds here too.

Warm-up is what makes the gate almost never visible, and on the phone more so
than on the watch: an iPhone acquires faster, and the user spends longer on
`StartView` choosing a template than on the watch's setup screen.

**Run 2 never gates**, for the watch's reason — the clock is running and there
is nothing to wait with. The pre-warm at rounds-remaining ≤ 1 buys the fix
instead.

## Relaunch mid-run

`runDistanceMeters` is in-memory only, so a relaunch during a run loses it. The
policy restores the *receiver* correctly with no special case, but the partial
total is gone.

Reporting a run measured only from the moment of relaunch would be an undercount
with no visible signal — the exact failure mode this feature exists to remove,
reintroduced through the back door. Instead `SessionEngine` checks one thing at
construction: if `rebuildState` returns with `state.phase` already in `.run1` or
`.run2`, that run began before this engine existed and its partial total is
unrecoverable, so the run is marked untrustworthy and `finishRun` passes `nil`
for it.

The check deliberately does not ask which call site built the engine — it cannot,
since `startNew` and the resume path share one initializer. It does not need to:
`startNew` always produces `.notStarted`, so only a genuine resume can trip the
condition. The mark is cleared by the next `beginRun()`, so run 2 measures
normally.

History then shows that run with a duration and no distance, which
`SessionDetailValue.run` already renders gracefully. An honest gap beats a wrong
number.

This is rarer than it sounds: with `UIBackgroundModes: location` the app stays
alive through a run rather than being suspended at screen lock, so a mid-run
relaunch means a crash or a force-quit, not ordinary use.

## Background modes

The iOS target has **no background modes at all** today, so a locked screen
suspends the app mid-run. Elapsed time survives because it is derived from
`startedAt`, but a location manager cannot measure anything while suspended.

Three pieces, and the first two must ship in **one commit**:

1. `UIBackgroundModes: [location]` in the `MurphPlus` target's `info.properties`
   block, alongside the existing `UIAppFonts` (`project.yml:31-37`).
2. `allowsBackgroundLocationUpdates = true` on the manager.
3. `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` on the iOS target. The
   existing string is on the **watch** target only (`project.yml:64`); the
   phone has never had one.

Items 1 and 2 are inseparable for the reason the watch spec documents: setting
the property while the plist key is missing is documented as "a fatal error that
terminates the app" — `NSInternalInconsistencyException`, *"Invalid parameter
not satisfying: !stayUp || CLClientIsBackgroundable(…)"*. Split across two
commits, the first run after the property lands is a launch crash.

Leaving the property `false` is not a safe middle. Updates then "may or may not
continue in the background depending on other factors" — undefined, which is the
silent undercount again.

**Plus one the watch could not have: `pausesLocationUpdatesAutomatically = false`.**
`WatchLocationController.swift:42-46` documents at length that this property is
`API_UNAVAILABLE(watchos)` and that the behaviour it would suppress appears
absent on that platform. On iOS the property exists and the behaviour is real:
Core Location will stop delivering updates when it decides you have stopped
moving. Mid-Murph that is a silent undercount, and it is the single most likely
way this feature fails quietly on a phone after working on a watch. It must be
set explicitly false.

When In Use is sufficient throughout — `allowsBackgroundLocationUpdates` extends
its reach into the background, so Always would be a second prompt for nothing.

The blue status-bar indicator during a backgrounded run is expected behaviour,
not a defect.

## Testing

**`RunDistanceAccumulatorTests`** carries the weight, because it is the only
part of this change that has to be numerically right:

- a straight-line trace sums to its known length;
- a stationary-jitter trace sums to approximately zero;
- a cached first fix produces no phantom opening jump;
- an out-of-order sample is dropped;
- haversine checked against known coordinate pairs;
- **the anchor regression** — a slow-walk trace whose individual deltas fall
  under the noise floor still accumulates, and reads zero if the anchor is
  updated on rejection.

**`FakeLocationController` already exists**
(`MurphPlusTests/WatchSessionControllerTests.swift:57`), with a `transitions`
helper that collapses repeats. It is extended to conform to
`RunDistanceMeasuring` as well, recording `beginRun` / `resumeRun` /
`stopMeasuring` alongside the existing `start` / `stop` calls. The watch's
existing assertions on `transitions` are unaffected.

**`SessionEngineLocationTests`** — new, walking the full arc through the phone
engine: start → warming and measuring; pause → receiver on, measuring stopped;
resume → `resumeRun`; `finishRun(1)` → distance lands in
`RunSplit.distanceMeters` and measuring stops; mid-rounds → receiver off;
penultimate round → receiver on but not measuring; run 2 → measuring; abandon →
off. Plus an indoor session that never starts the receiver once.

**Resume-path test** — an engine built from a persisted in-progress session
mid-run reports `nil` distance for that run and a normal distance for the next.

**Unchanged:** `SessionEngineTests` must pass without edits, and
`LocationPolicyTests` is untouched — the policy is reused exactly as it stands.

## On-device verification

In order, mirroring the watch's so the two numbers are directly comparable:

1. `plutil -p` the **built** `.app`'s `Info.plist` — not a read of
   `project.yml`. Confirm `UIBackgroundModes` contains `location`. The build
   system has been observed stripping this key, which is the entire reason this
   step names the built product.
2. Launch. Confirm the location prompt appears. It never has on iOS.
3. Phone in pocket, screen locked, run the known 0.70–0.75 mile route. **This is
   the acceptance test.** It reads in that band or the change has not worked.

Running step 3 with the watch on the wrist in a separate session also
cross-checks the watch's own figure for free, against the same route.

## Open, to settle on hardware

- **Is 20 m the right accumulation threshold?** It ships as one named constant,
  tuned against the known route. Too strict and a cloudy day drops most samples;
  too loose and noise inflates the total.
- **Is the noise floor right?** `max(horizontalAccuracy, minimumDeltaMeters)` is
  principled but the constant is a guess until it has seen a real run.
- **Does the total drift on long GPS gaps?** A straight line between two good
  fixes across a tunnel understates the real path. Accepted as a known
  lower-bound undercount rather than dropped; worth measuring before deciding
  whether the `CMPedometer` hybrid is worth its cost.

None blocks the design. All three are tuning questions with a known answer shape.

## Sources

- [`HKLiveWorkoutBuilder`](https://developer.apple.com/documentation/healthkit/hkliveworkoutbuilder) — watchOS only
- [`allowsBackgroundLocationUpdates`](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates)
- [`pausesLocationUpdatesAutomatically`](https://developer.apple.com/documentation/corelocation/cllocationmanager/pauseslocationupdatesautomatically)
- [`UIBackgroundModes`](https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes)
- `docs/superpowers/specs/2026-09-11-watch-gps-distance-design.md` — the watch's counterpart
