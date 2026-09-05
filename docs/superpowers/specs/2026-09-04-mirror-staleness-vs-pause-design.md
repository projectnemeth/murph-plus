# The phone offers Begin while the Watch owns a live session

Roadmap §3. Written up rather than patched, because the roadmap says so and the
roadmap is right: there is a real tension here and the cheap fix makes one half
worse. **This memo ends with a decision to make.** Nothing in it is implemented.

---

## What happens

Hardware tests 01 and 07. Pause the workout on the Watch, return to the phone's
Start tab, and the Begin button comes back — so a second concurrent workout can
be started. Single-writer is the one conflict this design refuses to resolve, so
that guard exists to make two live sessions *unreachable*, and it does not hold.

Two independent paths get there.

**Path 1 — a pause looks like a disconnection.** `LiveMirrorStore.isMirroring`
requires `!isStale`, and `staleAfter` is 10 seconds. The comment justifying ten
seconds says live events arrive on every 5-second heart-rate sample — true,
except that `WatchSessionController.attachHeartRateHandler` opens with
`guard !self.state.isPaused`, so **a paused Watch deliberately sends nothing**.
Ten seconds into a pause the mirror expires. Task 2's staleness fix meeting
Stage 2's pause behaviour; neither is wrong on its own.

**Path 2 — the mirror is in-memory only.** Force-quit the phone app and the
mirror is gone; Begin is offered until the next live event lands. A pause makes
that "never".

Worth carrying forward: test 07's actual assertion **passed** — one record per
session, full round count — so the checkpoint-sequence fix holds on hardware.
What was recorded as its failure is this same mirror problem wearing a different
hat.

## Why the obvious fix is not obviously right

Staleness expiry is not incidental. It is what stops a Watch that ran out of
battery — which sends no terminal event, it just stops — from hiding Begin
forever. Making the mirror survive a pause pulls directly against that. Any
option below has to say what happens when a Watch dies *while paused*, because
that is the case where the two requirements meet head-on.

## Options

### A — keep the mirror fresh through a pause

Send something while paused: either drop the `!isPaused` guard on the live
channel, or add a periodic "still here" event.

- **For.** Keeps `isMirroring` meaning what it says — the Watch is talking to me
  right now. Staleness still catches a dead Watch, unchanged.
- **Against.** The pause guard is load-bearing: dropping heart-rate samples taken
  while paused keeps a stopped-still spike out of the surrounding round's
  average. So this needs a *separate* liveness signal, which is a new
  `SessionEvent` case (and its Codable-compatibility question) or a new message
  key. It also spends radio through every pause, on a device mid-workout.
- **Doesn't fix.** Path 2 at all.

### B — decide Begin from the durable record, not the live mirror

The phone already persists every Watch session it has received: a `MurphSession`
with `origin == .watch` and `status == .inProgress`, journal and all. Hide Begin
when such a session exists, and leave `LiveMirrorStore` purely a display
concern.

- **For.** The only option that fixes **both** paths. Survives a force-quit,
  because it is on disk. Immune to pause quietness, because it does not depend
  on traffic. No wire-format change, no Watch change, no new constant — the
  escape hatch already exists in `StuckWatchSessionReaper`, and History already
  surfaces "N Apple Watch sessions never finished" with a one-tap abandon.
- **Against.** Depends on at least one checkpoint having landed. A session
  started while the phone was unreachable leaves no record, and Begin would
  still be offered — though the first checkpoint is sent at `started` on the
  queued, guaranteed channel, so it lands as soon as the link returns, and the
  live mirror still covers the reachable case.
- **The real cost.** The reaper's threshold is six hours. A genuinely dead Watch
  would hide Begin for six hours unless the user goes to History and abandons
  the session by hand. That is the trade this option is really asking about, and
  it argues for surfacing the abandon action on the Start tab rather than only
  in History.

### C — make staleness pause-aware

`isStale` ignores the clock while the last known state `isPaused`.

- **For.** Small, local, and aimed exactly at the reported cause.
- **Against.** A Watch that dies while paused then hides Begin forever — the
  precise failure staleness exists to prevent. Fixing that needs a second, much
  longer timeout for the paused case, which is a second magic number justified
  by nothing in particular.
- **Doesn't fix.** Path 2 at all.

### D — persist the mirror

- **For.** Fixes path 2.
- **Against.** `LiveMirrorStore`'s own documentation is emphatic that nothing
  here is persisted, so that a dropped link can never leave a half-written
  session in history. The lossy path and the durable path are kept apart on
  purpose; this puts them back together.
- **Doesn't fix.** Path 1 at all.

## Recommendation

**B, with C alongside it.**

B is the only option that closes both paths, and it does so with a record the
phone already keeps — no new event type, no new wire compatibility question, no
new timeout. C is worth doing anyway but for a *different* reason than this bug:
while the user is paused the mirror currently says "Disconnected, showing last
known state", which is simply untrue. That is a display defect in the same file,
and fixing it should not be confused with fixing the Begin guard.

A is the most correct in a protocol sense — liveness really is what the mirror
is trying to measure — but it buys with a wire change and battery what B gets
from data already on disk.

### What B looks like

- `StartView` queries for a watch-origin session in `.inProgress` alongside the
  live mirror. Begin is withheld if **either** says a session is live.
- Three states rather than two, since the reason matters to the user:
  Begin · mirroring live (tap to follow) · Watch session in progress but not
  connected.
- That third state carries the abandon action inline, so a user whose Watch died
  is never told "no" without being told what to do about it. The logic already
  exists in `StuckWatchSessionReaper`; this is a second entry point to it, not a
  new rule.
- The decision itself is a pure function of (mirror state, durable session
  present) and should be tested as one, separately from the view.

Rough size: an evening, most of it the third banner state and its tests.

## Decide

1. **B, C, both, or something else?**
2. **If B: how long before the phone stops believing in a Watch session it
   cannot see?** Reusing the reaper's six hours is the conservative answer and
   costs a user with a dead Watch a trip to History. A shorter dedicated
   threshold for *this* decision — long enough to cover a genuine pause, say 30
   minutes — would take the sting out, at the price of a second constant that
   has to be justified.
3. **Does the third banner state carry the abandon action inline?** It is the
   difference between a rule and a dead end, but it does put a destructive
   action on the Start tab.
