# GPS for the runs, off for the rounds

The watch app has never used Core Location. Not approximate location — none at
all. Run distance has always come from HealthKit's `distanceWalkingRunning`,
which without a location manager running is the wrist accelerometer's stride
estimate. On a known 0.70–0.75 mile route it recorded **0.46 miles**.

This spec adds GPS to the two runs and keeps it off for everything else.

---

## What is actually wrong

Four facts, each checkable:

1. **No Core Location anywhere.** `CLLocation`, `CoreLocation`,
   `locationManager`, `requestWhenInUse` — zero hits across the tree.

2. **Authorization is never requested.** `WorkoutSessionController.requestAuthorization`
   (`MurphPlusWatch/Session/WorkoutSessionController.swift:52`) asks HealthKit
   for heart rate, distance and workout-share. It asks for nothing else.
   `NSLocationWhenInUseUsageDescription` ships (`project.yml:64`), so the
   permission *string* exists, but nothing ever triggers the prompt. The user
   has never been asked, and watchOS grants nothing unasked.

3. **`locationType = .outdoor` is a label, not a switch.**
   `WorkoutSessionController.swift:70` tells HealthKit and Fitness the workout
   happened outdoors. It does not power the GPS receiver. A third-party app
   must run its own `CLLocationManager` for that.

4. **Distance is HealthKit-only.** `WorkoutSessionController.swift:50, 184-188`.

This was intended and then missed, not decided against. The Stage 2 plan says
the setup flow "Requests HealthKit authorization … **plus location-when-in-use**"
(`docs/superpowers/plans/2026-09-03-murph-plus-watch-stage-2-watch-app.md:74`)
and the watch design says "Outdoor enables GPS (accurate mile, real battery
cost)" (`docs/superpowers/specs/2026-09-03-murph-plus-watch-design.md:268`). The
Info.plist key got written; the location manager did not. The documented
accelerometer fallback (plan line 22) became the only path that exists.

## Scope

**In:** an accurate run distance, and a start gate that waits for a fix.

**Out:** route recording (`HKWorkoutRouteBuilder`), the map in session detail
(`2026-09-03-murph-plus-watch-design.md:413`), and any change to `RunSplit`,
`SyncPayload`, `SessionImporter` or the phone. Route recording stays a clean
later addition: it needs a HealthKit entitlement and a save path, and it can be
layered on this without reworking any of it.

**Distance still comes from HealthKit.** Core Location's only job here is to
power the receiver. HealthKit then fuses GPS with the accelerometer, which beats
either alone and keeps working under tree cover where raw GPS would not.
Re-deriving distance from `CLLocation` deltas would be reimplementing that
fusion, worse.

## Why a separate seam

The GPS lifecycle **starts before the workout exists**. The gate warms the
receiver while the user is still on the setup screen, at which point
`WorkoutSessionController` holds no `HKWorkoutSession` and no builder, and every
method on it is contractually a no-op (`WorkoutSessionController.swift:152`,
`163`, and the failure path at `88-90`).

Folding GPS into `WorkoutControlling` would mean calling methods on an object
whose whole documented contract is "I wrap a live session" during the window
when it wraps nothing. The two subsystems have different lifetimes, so they get
different seams. This also keeps `WorkoutControlling`'s docstring honest — "The
HealthKit side of a live session, expressed without HealthKit" — and gives the
setup view something to observe without reaching through the workout controller.

The cost is one protocol, one watch-side type and one test fake. Paid gladly.

## Components

### `MurphCore/LocationProviding.swift` — new, Foundation only

Foundation-only because `WatchSessionController` compiles into the phone target
so the iOS bundle can exercise it (`project.yml:19`); anything it touches must
follow it there.

```swift
enum GPSFixState: Equatable {
    case off        // not updating: indoor, rounds, or never started
    case denied     // refused or restricted — a fix will never come
    case acquiring  // updating, no sample yet at usable accuracy
    case fixed      // a sample at or better than the accuracy threshold
}

@MainActor
protocol LocationProviding: AnyObject {
    var fixState: GPSFixState { get }
    func requestAuthorization() async
    func startUpdating()   // idempotent
    func stopUpdating()    // idempotent
}
```

`.denied` is separate from `.off` because it is the single state where waiting
is pointless, and the gate branches on exactly that.

**Idempotence is load-bearing.** It lets every transition point assert the
desired state unconditionally instead of tracking "did I already start it",
which is what makes the policy below a pure function rather than a state machine.

### `MurphCore/LocationPolicy.swift` — new, pure

One function, no hardware, no I/O:

```swift
enum LocationPolicy {
    /// Whether the receiver should be running, given where the session is.
    static func shouldWarm(for state: SessionState) -> Bool
}
```

The rule:

> Not `indoor`, **not terminal**, and either the phase is `.run1`/`.run2`, **or**
> the phase is `.rounds` with `template.safeRounds - completedRounds <= 1`.

The terminal guard is not belt-and-braces. `abandon` sets `status` but
deliberately leaves `phase` where it was — phase is the record of how far the
attempt got, and the history screens display it (`SessionState.swift:148-149`).
A Murph abandoned mid-run therefore reads `.run1` forever, so a phase-only rule
would leave the receiver running until the app died. Found by the Task 3
implementer; the rule shipped without it would have been a battery leak on every
abandoned outdoor session.

Expressed as *rounds remaining ≤ 1* rather than "on round N−1", which buys two
things for free:

- A **single-round template** is handled correctly without a special case — at
  rounds-start the condition is already true, so the receiver simply never
  powers down.
- **Relaunch recovery** needs no separate path. Replay the journal, ask the
  policy, obey the answer. The recovered case and the live case are the same
  code.

### `MurphPlusWatch/Session/WatchLocationController.swift` — new

`@Observable`, wraps `CLLocationManager`. Mirrors `WorkoutSessionController`'s
shape: the only type in the change that touches hardware, and the only one with
no unit tests.

- `desiredAccuracy = kCLLocationAccuracyBest`
- `activityType = .fitness`
- `allowsBackgroundLocationUpdates = true` — see **Background modes** below.

An earlier draft of this spec also listed `pausesLocationUpdatesAutomatically =
false`, to stop Core Location pausing updates when it decides you have stopped
moving — which would be poison in a workout that includes standing still at a
pull-up bar. **That property does not exist on watchOS.** The SDK header
declares it `API_AVAILABLE(ios(6.0), macos(10.15)) API_UNAVAILABLE(watchos,
tvos)`, and Apple's platform list omits watchOS. Found at implementation time.
The behaviour it would have suppressed appears absent on this platform, so there
is nothing to disable — but see the open questions below.
- Publishes `.fixed` on the first sample with `horizontalAccuracy <= 20` metres;
  holds `.acquiring` until then.

### `MurphCore/LocationFixGate.swift` — new

Follows `StartCountdown`'s idiom exactly (`MurphCore/StartCountdown.swift`): an
injected `sleep` so tests do not wait thirty real seconds, and a `skip()` that
resolves the wait early. It holds the only real logic in the gate; the view
renders its state and nothing more.

### Changed: `WatchSessionController`

Takes a second injected dependency beside `workout`, and reconciles it against
`LocationPolicy.shouldWarm(for: state)` at the transition points it already
owns — `startSession`, `advance`, `resumeExistingSession`, `finishAndReset`.
One line each. No new transitions, no state-machine change, no new events, no
journal change.

### Changed: `WatchSetupView`

Requests location authorization beside the existing
`await controller.requestAuthorization()` in its `.task`
(`MurphPlusWatch/Views/WatchSetupView.swift:126`), starts the receiver when
Outdoor is selected, stops it on Indoor and on teardown, and hosts the gate.

## Lifecycle

| Moment | GPS |
|---|---|
| Setup screen appears, Outdoor | **start** — warm-up begins |
| Outdoor → Indoor toggle | stop |
| Setup torn down without starting | stop |
| Countdown reaches zero | gate (below) |
| Run 1 | running |
| Rounds begin | **stop** |
| Rounds, remaining > 1 | off |
| Rounds, remaining ≤ 1 | **start** — pre-warm for run 2 |
| Run 2 | running |
| Pause mid-run | **keeps running** |
| Session completes / reset | stop |
| Indoor session, any phase | never starts |

**Pause keeps GPS on** deliberately. Pauses are typically short, and
re-acquiring a fix on resume costs more than the battery a short pause saves.

**Rounds are the long part** — twenty rounds of Cindy run far longer than two
miles of running — so switching off there is where nearly all the saving is.
Roughly 20 minutes of receiver time across a 60-minute Murph instead of 60.

## The start gate

Warm-up is what makes the gate almost never visible. The receiver has usually
been running for tens of seconds by the time the user has chosen a template, set
the vest and tapped Start, and the existing three-second countdown adds more.

At countdown zero:

| `fixState` | Behaviour |
|---|---|
| `.off` (Indoor) | start immediately — no GPS was wanted |
| `.denied` | start immediately — waiting for a fix that will never come is pure delay |
| `.fixed` | start immediately — the ordinary case |
| `.acquiring` | hold |

The hold reuses the existing full-screen countdown overlay rather than a sheet,
for the reason already documented at `WatchSetupView.swift:110-116`: a sheet is
swipe-dismissible, and swiping this away would leave a half-started session
behind it. It shows "Acquiring GPS" and a **Start anyway** button available from
the first frame, and gives up on its own after **30 seconds**.

That bound is the point. The standing contract is that no sensor may block the
workout (`MurphCore/WorkoutControlling.swift:13-16`); an unbounded wait breaks it
the first time the user runs somewhere with a poor sky view. Thirty seconds is
long enough for a cold fix and short enough to read as a pause rather than a
failure.

**Run 2 never gates.** The clock is running and the user is mid-workout, so
there is nothing to wait with. The pre-warm at the penultimate round is what
buys the fix instead; if it somehow is not ready, the opening seconds fall back
to step estimates silently rather than stopping anyone.

## Background modes

This is the part that is a crash rather than a degradation, so it is specified
rather than discovered.

**Two different keys, both required, doing different jobs.**

`WKBackgroundModes` has **no `location` value**. Its complete set is
`workout-processing`, `self-care`, `mindfulness`, `physical-therapy`, `alarm`,
`underwater-depth`. `workout-processing` is documented as exactly one thing:
"Allows an active workout session to run in the background." It says nothing
about location, and there is no location mode to add there.

`UIBackgroundModes` **is available on watchOS** (4.0+; this app targets 10.0)
and does carry `location`.

`CLLocationManager.allowsBackgroundLocationUpdates` is watchOS 4.0+ and its
documentation is unambiguous:

> "Setting the value to `true` but omitting the `UIBackgroundModes` key and
> `location` value in your app's `Info.plist` file is a fatal error that
> terminates the app."

A hard crash — `NSInternalInconsistencyException`, *"Invalid parameter not
satisfying: !stayUp || CLClientIsBackgroundable(…)"*. Confirmed by an Apple
Frameworks engineer in [forum thread 709894](https://developer.apple.com/forums/thread/709894),
in a case where the key was present in source and **the build system stripped it
from the built plist**.

Leaving the property `false` is not a safe middle: the same documentation says
updates then "may or may not continue in the background depending on other
factors, including other background modes" — undefined, which is precisely the
silent-undercount failure this whole spec exists to remove. Only `true` carries
the documented guarantee that "Core Location configures the system to keep the
app running to receive continuous background location updates."

Consequences:

1. `project.yml` gains `UIBackgroundModes: [location]` on the watch target,
   **alongside** the existing `WKBackgroundModes: [workout-processing]`
   (`project.yml:84`).
2. The plist key and `allowsBackgroundLocationUpdates = true` ship in **one
   commit**. Split across two, the first run after the property lands is a
   launch crash.
3. Verification is `plutil -p` against the **built** `.app`'s `Info.plist`, not
   a read of `project.yml`. The stripping bug above is exactly why.

`allowsBackgroundLocationUpdates` extends the reach of **When In Use**
authorization, so the existing `NSLocationWhenInUseUsageDescription`
(`project.yml:64`) is sufficient. No Always authorization, no second prompt.

## Testing

Everything below runs from the existing iOS bundle. `WatchLocationController`
gets no unit tests — it is a hardware wrapper, as `WorkoutSessionController` is
today.

**`LocationPolicyTests`** — table-driven over the pure rule. Indoor never warms.
`.run1`/`.run2` warm. Rounds warm only at remaining ≤ 1. A single-round template
warms from the moment rounds begin. `.notStarted` and `.completed` never warm.

**`FakeLocationController`** — a call recorder beside the existing
`FakeWorkoutController` (`MurphPlusTests/WatchSessionControllerTests.swift:12`),
with a settable `fixState`. Extends that suite to assert the full arc: start →
updating; run 1 ends → stopped; mid-rounds → still stopped; penultimate round →
updating; run 2 → updating; finish → stopped. Plus an indoor session that never
starts it once.

**Recovery tests** — cheap precisely because the policy is pure. Relaunch
mid-run-1 resumes updating; relaunch into the penultimate round resumes
updating; relaunch into round 3 of 20 does not; an indoor relaunch never does.

**`LocationFixGateTests`** — injected sleep, mirroring `StartCountdownTests`.
Fixed returns immediately; denied returns immediately; acquiring holds; `skip()`
resolves early; the 30-second bound fires.

**On-device verification**, in order:

1. `plutil -p` the built watch app; confirm `UIBackgroundModes` contains
   `location` and `WKBackgroundModes` contains `workout-processing`.
2. Launch. Confirm the location prompt appears — it never has before.
3. Run the known 0.70–0.75 mile route. **This is the acceptance test.** It reads
   in that band or the change has not worked.

## Open, to settle on hardware

**Does the watch dimming mid-run interrupt delivery** even when configured
correctly? [Forum reports](https://developer.apple.com/forums/thread/685390)
suggest it can. Correct configuration is necessary; whether it is sufficient is
not something this spec can assert from documentation.

**Does watchOS pause updates when you stand still?** `pausesLocationUpdates`
`Automatically` is unavailable on watchOS, so the auto-pause behaviour is
presumed absent rather than merely unsuppressed. If a run's distance stalls
while standing at the pull-up bar and resumes when moving again, this is the
first suspect and the presumption is wrong.

**Is 20 metres the right accuracy threshold?** Too strict and the gate waits for
nothing; too loose and it starts on a drifting fix. It ships as one named
constant, tuned against the known route.

Both are tuning questions. Neither blocks the design.

## Sources

- [`allowsBackgroundLocationUpdates`](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates)
- [`WKBackgroundModes`](https://developer.apple.com/documentation/bundleresources/information-property-list/wkbackgroundmodes)
- [`UIBackgroundModes`](https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes)
- [watchOS 9 beta: `allowsBackgroundLocationUpdates` crash](https://developer.apple.com/forums/thread/709894)
- [`didUpdateLocations` while the watch dims](https://developer.apple.com/forums/thread/685390)
