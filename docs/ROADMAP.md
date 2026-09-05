# Roadmap — open items

Things known to be wrong or missing, parked deliberately rather than forgotten.
Newest section first. Each item says what the evidence is, what is already known
about the cause, and where to start — so it can be picked up cold.

---

## Watch sync — from the hardware matrix (2026-09-04)

The first paired-device pass over Watch Stage 3. **5 pass, 4 fail, 3 not run.**
Results with the original per-test notes:
https://claude.ai/code/artifact/1c056016-b5ec-429d-9c0b-114408ea30db

Confirmed working on real hardware, so don't re-litigate these: the session lands
in History without a relaunch (the `mainContext` switch), the personal-best badge
holds, the cold-launch activation race is closed, pause accounting survives the
journal round trip, and every round logged out of Bluetooth range arrives.

### 1. A completed workout was lost across a phone reboot — HIGH

**Not an edge case: this is a finished workout that never reached History.**

Test 09: phone powered fully off, whole session completed on the Watch, phone
powered back on and opened — the session never arrived, and Console showed
nothing.

What is already known:

- **Test 08 passed**, and it exercises the same queued `transferUserInfo`. The
  difference is that out-of-range keeps the phone powered with its app alive,
  while 09 needs the phone's `WCSession` to re-activate and drain the queue after
  boot. That points away from "the Watch never sent" and toward delivery on the
  phone side.
- **Prime suspect is a regression from the review-fix wave.** The
  `activationState == .activated` guard added to
  `WatchSyncCoordinator.transferCheckpoint` returns early **with no log**. If the
  Watch's session was not activated during the phone-off window, every checkpoint
  was dropped silently — the same silent-drop class that fix wave existed to
  abolish, reintroduced by the fix for a different defect.
- **Mitigating:** the data is not destroyed. `finishAndReset()` deliberately keeps
  the journal on the Watch, so the workout still exists there — it was simply
  never delivered.

**Start here:** instrumentation, not a fix. See item 2 below; the diagnosis is
blocked on it and cannot be settled by reading.

**Worth designing together with the journal-retention item (§7):** a "resend any
journal the phone has not acknowledged" pass would both recover workouts lost this
way and give the retention problem its natural answer — a journal can be deleted
once the phone has confirmed it.

### 2. Sync logs only failures, never successes — HIGH (blocks §1)

The five `MurphPlus sync` lines fire only on error. When a checkpoint simply never
arrives, there is no way to tell "never sent" from "sent but not delivered", which
is exactly why §1 is undiagnosable today.

**Start here:** log every `transferCheckpoint` call with its carrier
(userInfo vs file), payload size and activation state; log the silent early return
in that guard; log every `didReceiveUserInfo` / `didReceive file:` arrival on the
phone. Then re-run test 09. Consider keeping a reduced version permanently — this
feature's whole failure surface is silent by construction.

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

**This needs a design conversation, not a patch.** There is a real tension: the
staleness expiry exists so a dead Watch cannot hide Begin forever, and making the
mirror survive a pause pulls directly against it. The promising signal is that the
phone already persists the Watch session's journal (`journalData`), so it can tell
"paused, therefore legitimately quiet" from "gone" — which the live channel alone
cannot.

Note for whoever picks this up: test 07's actual assertion **passed** — one record
per session with the full round count, so the checkpoint-sequence fix holds on real
hardware. What was recorded as its failure is this same mirror problem.

### 4. No way to delete a template on the phone — MEDIUM (missing feature)

Made test 05 unrunnable. Sessions can be deleted from `SessionDetailView`;
templates have no delete affordance anywhere. Small feature, and it unblocks a test
that covers `resolveTemplate`'s rebuild-from-snapshot path.

### 5. Mirror discoverability — LOW

The only way into the live mirror is a banner reading "Session running on Apple
Watch · Tap to follow along", and it did not read as tappable during testing.

### 6. Three matrix tests never run — they need temporary constant changes

None is testable as shipped. Make the edit, run the check, revert before
committing:

| Test | Edit | What it proves |
|---|---|---|
| 10 · Dead watch → abandon, never resume | `StuckWatchSessionReaper.defaultThreshold` → `60` | Single-writer: the phone may abandon a Watch-owned session, never continue one |
| 11 · Oversize payload takes the file path | `SyncPayload.userInfoByteLimit` → `2_000` | The file-transfer carrier works end to end (real trigger is a session past ~2h13m) |
| 12 · Staged files are cleaned up | keep 11's limit | Whether `fileTransfer.file.fileURL` is our staged file or a system copy — deleting the wrong one would be silent |

### 7. Parked during code review, with reasoning

Carried from the Stage 3 reviews. Full reasoning in
`docs/superpowers/handoffs/2026-09-04-watch-stage-3-handoff.md`.

- **Watch journals accumulate forever**, and every launch decodes all of them on
  the main actor (`SessionJournal.all` fully decodes each file; `WatchSetupView`
  calls it on appear). ~60–75 KB each. Degrades over months. **See §1 — this and
  the resend pass are one feature.**
- The resume test does not actually pin `checkpointSequence`'s `!isHeartRate`
  filter; its assertion passes with or without it. One-line remedy:
  `XCTAssertEqual(afterResume, beforeCrash + 1)`.
- `SessionImporterTests` builds `ModelContext(container)` while `ingest` now ships
  against `container.mainContext`, so `apply` is not exercised against the flavour
  that ships.
- The six-hour stuck-session threshold has no boundary test. Deliberate: direction
  is pinned by tests either side, and exact equality on a wall-clock heuristic is a
  judgement call, not a contract.
- The mirror pops the user out with no completion feedback when the session ends.
- `SessionTransport` declares three closures (`onLiveEvent`, `onCheckpoint`,
  `onContext`) that nothing in production assigns.
- `SessionJournal.resumable()` does not sort by mtime, so with two non-terminal
  journals the launch prompt could offer the wrong one.
- A staged `checkpoint-*.json` leaks if the Watch app is killed mid-transfer.
