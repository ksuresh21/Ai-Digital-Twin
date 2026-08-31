# Test Plan

Written before the implementation, as Section 10 of the spec requires. The
suite it describes now exists and passes.

```
swift test
```

**Current status: 125 tests, all passing, 0.010s.**

---

## Why it runs in ten milliseconds

The suite tests a 40-minute eye-break cycle, a full day of water reminders, and
a quiet-hours window that crosses midnight — without sleeping for a single
second. That is not a trick; it is the reason the architecture looks the way it
does.

`AiTwinCore` never calls `Date()` and never owns a `Timer`. It asks an injected
`Clock` for the time, and it advances when someone calls `tick()`. In production
a one-second repeating timer calls `tick()`; in a test, `FakeClock.advance(2400)`
does, and forty minutes pass instantly.

If timing logic lived inside a `Timer` closure — the obvious way to write this —
none of the tests below could exist, and the spec's "test before implementing"
instruction would have been impossible to follow honestly.

---

## Mac automated tests (`swift test`)

### Timer behaviour — `ReminderTimerTests` (14 tests)

| Test | What it protects |
|---|---|
| a new timer is not running until started | No reminders before `start()` |
| start schedules a deadline one interval away | Correct scheduling |
| does not fire before the interval elapses | Tested at 40min − 1s |
| fires exactly at the configured interval | Tested at exactly 40min |
| stays fired if nothing looks at it for a while | A busy main thread cannot swallow a reminder |
| stop cancels the countdown | Cancellation |
| restarting gives a full fresh interval | Restart |
| pause preserves the time remaining | Pausing does not lose progress |
| resume continues from where it paused | Resumption |
| pausing twice does not lose the remaining time | Idempotent pause |
| snooze pushes the deadline out by the snooze duration | Snooze uses the snooze interval |
| changing the interval on a running timer takes effect immediately | Test Mode works without a 40-minute wait |
| changing the interval on a stopped timer does not start it | Interval change ≠ enable |
| a paused timer stays paused across an interval change | Pause survives reconfiguration |

### Reminder orchestration — `ReminderEngineTests` (27 tests)

Launch: both timers start · disabled reminders never start · nothing fires early
· ticking before `start()` does nothing.

The 40-minute cycle: fires at exactly 40 min, not at 39:59 · acknowledging
starts the next 40-minute cycle.

Water: fires on its own interval · acknowledging logs a glass · an eye break
does *not* log a glass · the daily goal is reported exactly once, not on every
glass after it · the count resets on a new day.

Snooze: reschedules by the snooze interval rather than a whole cycle · touches
only the snoozed timer, leaving the other's deadline byte-identical · is ignored
for a reminder that isn't showing.

Concurrency: only one reminder shows at a time, even when both come due in the
same tick · the second appears once the first is acknowledged · an unanswered
reminder times out and reschedules itself.

Pause / idle / quiet hours: pausing suppresses everything · resuming keeps
prior progress (39 of 40 minutes stay banked) · time away from the keyboard
does not count as screen time · idle pausing can be turned off · nothing fires
during quiet hours · reminders resume when quiet hours end.

Settings: Test Mode intervals apply without waiting out the old one · changing
one interval leaves the other timer untouched · enabling a reminder starts its
timer · disabling one mid-cycle stops it · `triggerNow` fires immediately · and
is ignored while a reminder is already up.

Messages: every message in the pool is used before any repeats.

### Animation — `FrameDiscoveryTests`, `FrameSequencerTests`, `CharacterPackTests` (26 tests)

Frame discovery: **numeric not alphabetical ordering** (`walk_10` must not
precede `walk_2`) · zero-padded names · gaps tolerated · `.DS_Store` and stray
files ignored · `idle` does not swallow `idle_glasses_01.png` · empty folder
yields no frames rather than an error · non-numeric and unsupported extensions
rejected · full paths matched on last component.

Sequencing: starts on frame one · advances in order at the configured rate ·
holds each frame for its full duration · loops wrap · one-shot clips hold the
final frame and report finished · a finished clip does not advance further · a
long delta catches up rather than dropping frames · switching clips restarts
from frame zero · **an empty clip is inert instead of crashing** · a zero frame
duration does not spin forever · restart works.

Pack resolution: exact clip · **a missing clip falls back to idle rather than
nothing** · glasses variant used when present · falls back to the plain clip
when absent · an empty clip counts as missing · a pack with no idle frames is
rejected · missing clips are reported for display in Settings.

### Window geometry — `CharacterPlacementTests`, `CompanionLayoutTests` (18 tests)

All four corners position correctly against a realistic visible frame · every
corner keeps the character fully on screen · top corners sit below the menu bar,
not under it · the walk-in starts fully off screen · enters at the resting
height (no diagonal drift) · right-hand corners enter from the right · facing
matches the walk direction · positions off the right and bottom are clamped
back · **a stale position from a disconnected display is brought back on screen**
· a screen smaller than the character does not produce NaN · walk duration is
distance over speed · zero speed does not divide by zero · the panel reserves
room for the bubble · has a minimum width · still fits in every corner at
maximum character size.

> These test the *maths* of window placement. They do not open a window — that
> is what the manual checklist is for.

### State machine — `CharacterStateMachineTests` (13 tests)

Starts hidden · greeting summons a walk-in · arriving triggers the wave · the
wave settles to idle · water and eye-break reminders use their own clips ·
dismissing sends the character away · **the full launch → greet → idle → leave →
reminder → dismiss → hidden loop asserts the exact sequence of nine states** · a
reminder while already on screen does not re-walk from off screen · a reminder
while walking away turns the character around · reset hides from any state ·
unexpected events are ignored rather than crashing · no callback fires on a
no-op transition.

### Settings, quiet hours, water log — (25 tests)

Version 1 defaults to bottom-left · the production eye-break interval is 40
minutes · the testing configuration uses the spec's 30s/60s · presets convert
and display correctly · settings round-trip through storage · encode and decode
as JSON · **corrupted stored settings fall back to defaults instead of failing
to launch** · greetings match the time of day.

Quiet hours: a disabled window silences nothing · a same-day window matches
inside it · start inclusive, end exclusive · **a window crossing midnight matches
on both sides of it** · an empty window silences nothing rather than everything.

Water log: starts empty · increments · resets on the next day · survives within
a day · **a backwards clock correction resets rather than corrupts** · progress
clamps at 1.0 · a zero goal does not divide by zero.

---

## What the automated tests deliberately do not cover

Honesty about coverage matters more than a high number:

| Not covered | Why | Covered instead by |
|---|---|---|
| The panel is actually transparent | Requires a rendered window and pixel inspection | Manual test 3 |
| The window floats above other apps | Depends on live window-server state | Manual tests 8–10 |
| Clicks pass through to apps beneath | Requires real event routing | Manual test 11 |
| Animation looks smooth | Perceptual, not assertable | Manual test 6 |
| Behaviour over full-screen apps | Apple has changed this between releases | Manual test 10 — **needs verification** |
| Sleep / wake greeting | Requires actually sleeping the Mac | Manual test 15 |
| Login item registration | Needs a signed, installed bundle | Manual test 17 |
| Multiple displays | Needs a second display | Manual tests 12–14 |
| **Anything on Windows** | **No Windows implementation exists** | Nothing. Untested. |

See [MANUAL_TESTS.md](MANUAL_TESTS.md).

---

## Running

```bash
swift test                                  # everything
swift test --filter ReminderEngineTests     # one suite
swift test --filter "40 minutes"            # one test by name
```
