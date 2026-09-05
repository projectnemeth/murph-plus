# Roadmap — open items

Things known to be wrong or missing, parked deliberately rather than forgotten.
Newest section first. Each item says what the evidence is, what is already known
about the cause, and where to start — so it can be picked up cold.

---

## Watch sync — from the hardware matrix (2026-09-04)

The first paired-device pass over Watch Stage 3. **5 pass, 4 fail, 3 not run —
then test 08's pass was withdrawn, see below.** Results with the original
per-test notes:
https://claude.ai/code/artifact/1c056016-b5ec-429d-9c0b-114408ea30db

Confirmed working on real hardware, so don't re-litigate these: the session lands
in History without a relaunch (the `mainContext` switch), the personal-best badge
holds, the cold-launch activation race is closed, and pause accounting survives
the journal round trip.

### Test method correction — read before re-running anything in group B

Test 08 ("walk out of Bluetooth range") was run using **iOS Control Center's
Bluetooth button, which does not disconnect an Apple Watch** — it drops other
accessories while deliberately preserving Watch, Handoff and Continuity. The link
was never severed, so that pass proved nothing and has been withdrawn.

The instruction was wrong independently of how it was carried out: **Watch and
iPhone also communicate over Wi-Fi**, so even genuinely walking out of Bluetooth
range passes spuriously whenever both devices sit on the same network. Turning
Bluetooth off in Settings is not sufficient either.

The reliable sever is **Airplane Mode on the Watch**, confirmed by the
disconnected glyph appearing on the watch face — the glyph, not the toggle, is the
evidence.

### 1 & 2. Addressed on branch `overnight/roadmap-sync-hardening` — RE-RUN NEEDED

Both were worked on 2026-09-04 (see the branch). **Neither is confirmed fixed:
they were fixed by reasoning and unit tests, and the evidence that mattered was
always hardware.**

**§2, sync logging, is done.** Both sides now log successes as well as failures:
the Watch logs every `transferCheckpoint` with session, sequence, byte size,
carrier and reachability — including all three previously silent early returns,
the `activationState` guard among them — and the phone logs each arrival and
what became of it. `os.Logger`, subsystem `com.projectnemeth.MurphPlus`,
category `sync`. Filter Console on that category.

**§1 has a fix, not a diagnosis.** The Watch now resends any finished journal the
phone has not acknowledged, and deletes the ones it has (see §7's retention item
— they were one feature). That recovers a workout lost this way whatever the
cause, but it does **not** tell you what the cause was.

**So the tests still to run, in this order:**

1. **Test 08, properly** — Airplane Mode on the Watch, confirmed by the
   disconnected glyph. Two minutes, no reboot. With logging in place this now
   answers the original question directly: whether checkpoints queue at all when
   the phone is unreachable.
2. **Test 09** — the phone-off reboot case. Watch the log for `DROPPED
   checkpoint … WCSession is not activated`. If it appears, §1's prime suspect
   was right and the guard needs rethinking rather than just compensating for.
3. **The recovery path itself** — after 09, bring the phone back and confirm the
   stranded workout arrives via the resend pass (`resending N of M
   unacknowledged journal(s)` in the log).

### 3. The phone offers Begin while the Watch owns a live session — MEDIUM

Tests 01 and 07. Pausing on the Watch and returning to the phone's Start tab gives
back the Begin button, and a second concurrent workout can be started. The guard
that exists to make two live sessions *unreachable* does not hold.

Root cause is identified. `LiveMirrorStore.staleAfter` is 10 seconds, and its
comment justifies that by saying live events arrive on every 5-second heart-rate
sample — but `WatchSessionController.attachHeartRateHandler` does
`guard !self.state.isPaused`, so **a paused Watch deliberately sends nothing.**
Ten seconds into a pause the mirror expires. Task 2's staleness fix meeting
Stage 2's pause behaviour; neither is wrong alone.

A second path to the same place: the mirror is in-memory only, so force-quitting
the phone app wipes it, and Begin is offered until the next live event lands.

**This needs a design conversation, not a patch**, and one is now written up
rather than guessed at:
`docs/superpowers/specs/2026-09-04-mirror-staleness-vs-pause-design.md`. Four
options with their costs, a recommendation (decide Begin from the durable
record rather than the live mirror, since it is the only one that closes both
failure paths), and three questions that need an answer before any code moves.
**Still open — deliberately.**

Note for whoever picks this up: test 07's actual assertion **passed** — one record
per session with the full round count, so the checkpoint-sequence fix holds on real
hardware. What was recorded as its failure is this same mirror problem.

### 4. No way to delete a template on the phone — DONE (2026-09-04)

Delete lives on the Start tab, under the selected template's card. Past sessions
are kept and the confirmation says how many are affected; refused outright while
a session is running against that template. **Test 05 is now runnable.**

### 5. Mirror discoverability — DONE (2026-09-04)

The banner has a chevron. It was always inside a navigation control; nothing
about its shape said so.

### 6. Three matrix tests never run — now runnable without editing anything

They used to need a source edit reverted before committing, which put a
production constant one forgotten `git checkout` away from shipping wrong — on
values whose failure mode is a silently dropped checkpoint. Both are now
DEBUG-only launch-argument overrides (`DebugOverride`), so set them in the
scheme and run:

Test 08 also needs re-running — not for a code change, but because its first run
used a disconnect method that doesn't disconnect. See the method correction above.

| Test | Scheme argument | What it proves |
|---|---|---|
| 10 · Dead watch → abandon, never resume | `-MurphStuckSessionThreshold 60` | Single-writer: the phone may abandon a Watch-owned session, never continue one |
| 11 · Oversize payload takes the file path | `-MurphUserInfoByteLimit 2000` | The file-transfer carrier works end to end (real trigger is a session past ~2h13m) |
| 12 · Staged files are cleaned up | keep 11's argument | Whether `fileTransfer.file.fileURL` is our staged file or a system copy — deleting the wrong one would be silent |

Test 12's question is now guarded in code rather than only observed: staged
files live in their own `tmp/checkpoint-staging/` directory and `didFinish`
refuses to delete a URL outside it, so a system-owned copy cannot be removed by
mistake. The test is still worth running — it also proves the sweep leaves an
outstanding transfer's file alone — but it is no longer the only thing standing
between us and a silent deletion.

### 7. Parked during code review — mostly cleared (2026-09-04)

Carried from the Stage 3 reviews. Full reasoning in
`docs/superpowers/handoffs/2026-09-04-watch-stage-3-handoff.md`. Cleared on
branch `overnight/roadmap-sync-hardening` unless marked otherwise.

**Done:**

- **Journals no longer accumulate forever.** A journal is deleted once the phone
  acknowledges holding that session in a terminal state; unacknowledged finished
  ones are resent. Same feature as §1, as predicted. The main-actor decode cost
  of `SessionJournal.all` on launch is bounded by the same change — the pile no
  longer grows — but is otherwise untouched.
- The resume test now asserts `beforeCrash + 1`, which is what actually pins
  `checkpointSequence`'s `!isHeartRate` filter.
- `SessionImporterTests` runs against `container.mainContext`, matching what
  ships. Doing so exposed a second defect in the fixture: `mainContext` is owned
  by the container, and the container was a local, so every test crashed on a
  dangling context until it was held.
- The mirror now has a completion state with its own Done button, and the parent
  presents it in a way that does not pop it away mid-glance.
- `SessionTransport`'s three unassigned receive hooks are gone. One of them was
  being *called*, from a closure that could never be set.
- `SessionJournal.resumable()` picks the most recently started of several, on the
  journal's own `startedAt` rather than file mtime.
- Staged checkpoint files live in `tmp/checkpoint-staging/` and are swept after
  activation, skipping anything still in `outstandingFileTransfers`. The
  dedicated directory also lets `didFinish` check the URL it was handed is ours
  before deleting it — which is the open question test 12 exists to answer.

**Still open, deliberately:**

- The six-hour stuck-session threshold has no boundary test. Direction is pinned
  by tests either side, and exact equality on a wall-clock heuristic is a
  judgement call, not a contract.
