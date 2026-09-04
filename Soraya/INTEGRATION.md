# Wiring her into the Swift app

Right now Soraya lives in a browser tab and `AiTwin` lives on your desktop.
They are the two halves of one character: `AiTwin` has the body, this has the
mind. This is how they meet.

Nothing here has been built yet — this is the design, written down while the
reasons are fresh. It is the first item in [ROADMAP.md](ROADMAP.md).

## The shape

```
   AiTwin.app  (Swift)                  Soraya  (Python)
   ┌────────────────────┐               ┌──────────────────────┐
   │ CompanionPanel     │               │ server.py            │
   │  the character on  │  HTTP + SSE   │  /api/say            │
   │  your actual       │◄─────────────►│  /api/state          │
   │  screen            │  127.0.0.1    │  /api/approach       │
   │                    │               │                      │
   │ MacPresenceObserver│──── unlock ──►│  pulse.consider()    │
   │ MacIdleMonitor     │──── idle ────►│                      │
   └────────────────────┘               └──────────────────────┘
```

`AiTwin` keeps everything it already does well — the panel, the placement, the
animation, the screen-lock awareness, the reminders. It gains one new thing: a
client that can ask Soraya what to say.

## Why HTTP and not a rewrite

The alternative is porting `emotion.py`, `persona.py`, `pulse.py` and the brain
adapters to Swift. That is a week of work to arrive at the same behaviour, and
then two copies of the posture rules to keep in step. Worse: the model
ecosystem is Python. `openai_compat` covering Ollama and LM Studio in 120 lines
of `urllib` has no equivalent in Swift.

A local HTTP call costs about a millisecond. The model call it wraps costs a
second. The seam is free.

## Step 1 — one protocol on the Swift side

`AiTwinPlatform/PlatformProtocols.swift` already holds seven of these. This is
the eighth, and it follows the same rule as the others: it states what the
domain needs and imports nothing.

```swift
/// Somewhere that can hold a conversation.
public protocol MindConsulting: AnyObject {
    /// Sends a message and receives her reply in pieces.
    func say(_ message: String, onEvent: @escaping (MindEvent) -> Void)
    /// Asks whether she would approach right now, and lets her open.
    func approach(unlocked: Bool, onEvent: @escaping (MindEvent) -> Void)
    /// Whether the service is reachable at all.
    var isAvailable: Bool { get }
}

public enum MindEvent: Equatable, Sendable {
    case pose(clip: String)
    case affect(label: String, valence: Double, arousal: Double, posture: String)
    case chunk(String)
    case done(text: String, spoke: Bool)
    case failed(String)
}
```

`AiTwinMac/MacMindClient.swift` implements it with `URLSession`, reading the
SSE stream with `URLSession.bytes(for:)` and splitting on `\n\n`. Roughly 80
lines. `MindEvent` maps one-to-one onto the event table in
[ARCHITECTURE.md](ARCHITECTURE.md#the-event-stream).

## Step 2 — three wires in AppCoordinator

`AppCoordinator` is already the only object that knows about both the domain
and the screen, so it is the right place and the only place.

**Speech bubbles become her words.** `CompanionViewModel.Bubble` takes a
message; `chunk` events append to it. Her existing `MessageCatalog` lines stay
as the offline fallback when `isAvailable` is false — she should still work
with the service down.

**Poses come from the event stream.** `enter(_ state:)` already drives clips
from `CharacterState`. A `pose` event is the same instruction from a different
source; it needs a state that means "saying something", alongside `.chattering`.

**Presence already reports what `pulse` wants.** This is the part that is
genuinely done already:

| Soraya wants | `AiTwin` already has |
|---|---|
| `unlocked_just_now` | `MacPresenceObserver.onBack` → `handleBack()` |
| `idle_minutes` | `MacIdleMonitor.idleSeconds` |
| quiet hours | `AiTwinSettings.quietHours` — **already the same shape** |

`QuietHours.swift` and `config.in_quiet_hours` are deliberately the same
algorithm, midnight-crossing case included, so the two cannot disagree about
when to shut up.

## Step 3 — one settings section

A `Mind` tab in the existing Settings window, backed by `/api/state` and
`/api/settings`. Voice on/off, wake phrases, provider, model, initiative. The
Swift side owns no state here; it reads and writes hers, so there is one source
of truth rather than two that drift.

## Step 4 — starting the service

Three options, in increasing order of effort and polish:

1. **You start it.** `./run.sh` in a terminal. Fine for building it.
2. **A LaunchAgent.** A plist in `~/Library/LaunchAgents/` with `KeepAlive`, so
   it comes up at login. A dozen lines, no app changes.
3. **The app launches it.** `Process` spawning `python3 -m soraya.server` on
   first need, killed on quit. Best experience, and the most to get wrong —
   Python path, working directory, port already in use, orphaned processes.

Do 1 while building, ship 2, consider 3 only if it turns out to matter.

## What must not leak across the seam

- **No API key in the Swift app.** The key lives in the environment of the
  Python process. The app never sees it, never stores it, and never needs a
  Keychain entry for it.
- **No conversation history in the app.** `~/.soraya/` is the one home for it.
  Two stores would diverge within a day.
- **Bind to `127.0.0.1` only.** Already the case, and it must stay the case.
- **She still works with the service down.** If `isAvailable` is false she
  falls back to `MessageCatalog` and behaves exactly as she does today. A
  water reminder must not depend on a language model.

## Testing it without the service

`MindConsulting` is a protocol, so `FakeMind` returns a scripted event
sequence, and the Swift tests never start a Python process or touch a network.
Same arrangement as `FakeClock` and the injected notification centres in
`MacPresenceObserver` — the pattern is already in the codebase.
