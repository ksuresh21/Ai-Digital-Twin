# Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  AiTwinApp        composition root — the only place that      │
│                   knows about both the domain and AppKit      │
│    main.swift · AppDelegate · AppCoordinator                  │
│    MenuBarController · SettingsWindowController               │
└──────────────┬───────────────────────────────────────────────┘
               │
     ┌─────────┴──────────┬──────────────────┐
     ▼                    ▼                  ▼
┌──────────┐      ┌──────────────┐   ┌──────────────────┐
│ AiTwinUI │      │  AiTwinMac   │   │ AiTwinPlatform   │
│ SwiftUI  │      │ AppKit lives │   │ 6 protocols.     │
│ views +  │─────▶│ here, and    │──▶│ No AppKit.       │
│ view     │      │ nowhere else │   │ The seam.        │
│ models   │      └──────────────┘   └────────┬─────────┘
└────┬─────┘                                  │
     │                                        ▼
     │                            ┌────────────────────────┐
     └───────────────────────────▶│      AiTwinCore        │
                                  │  Foundation ONLY.      │
                                  │  No AppKit, no SwiftUI,│
                                  │  no CoreGraphics.      │
                                  │  125 tests, 10ms.      │
                                  └────────────────────────┘
```

Dependencies point one way only. `AiTwinCore` imports nothing but Foundation —
that is enforced by the module boundary, not by discipline, and it is what makes
both the test suite and the Windows story credible.

---

## The three decisions that shaped everything

### 1. The domain has no clock and no timers

`ReminderEngine` does not call `Date()` and does not own a `Timer`. It asks an
injected `Clock` for the time and advances when someone calls `tick()`.

In production, one repeating one-second timer in `AppCoordinator` calls `tick()`.
In tests, `FakeClock.advance(2400)` does. That is why the suite can verify a
40-minute cycle, a full day of water reminders and a midnight-crossing quiet-hours
window in ten milliseconds total.

The alternative — logic inside timer callbacks — would have made the spec's
"write the tests first" instruction impossible to follow honestly.

### 2. Timers are deadlines, not countdowns

A timer that counts 2,400 one-second ticks toward a 40-minute break is destroyed
by a closed lid: the ticks stop, and the reminder arrives 40 minutes of *awake*
time later. `ReminderTimer` stores an absolute `Date` deadline and compares
against it. Sleep, wake, a stalled main thread and clock corrections all behave
correctly for free.

### 3. Placement maths lives in Core, not in the window manager

`MacWindowManager` contains no arithmetic. Every corner calculation, screen-boundary
clamp and walk duration is a pure function in `CharacterPlacement`, unit-tested
against realistic screen frames — including a display-disconnect case. The
platform layer supplies `NSScreen.visibleFrame` and applies the answer.

---

## Module by module

### `AiTwinCore` — the domain (Foundation only)

| File | Responsibility |
|---|---|
| `Clock.swift` | The time abstraction the whole design rests on |
| `AiTwinConfiguration.swift` | Every tunable constant, plus production/testing presets |
| `AiTwinSettings.swift` | User-changeable state + persistence protocol |
| `ReminderTimer.swift` | One deadline-based countdown |
| `ReminderEngine.swift` | Orchestrates both timers, pause, quiet hours, idle, snooze |
| `CharacterState.swift` | The state machine and its transition table |
| `AnimationClip.swift` | Clip model + `FrameSequencer` |
| `FrameDiscovery.swift` | Filename → ordered frames. Pure string work |
| `CharacterPack.swift` | Clip resolution with fallbacks |
| `CharacterPlacement.swift` | All four corners, entry points, clamping |
| `CompanionLayout.swift` | Panel sizing |
| `QuietHours.swift` | A daily window, including the crossing-midnight case |
| `WaterLog.swift` | Daily counter with midnight rollover |
| `MessageCatalog.swift` | Greetings and non-repeating reminder pools |
| `PresenceTracker.swift` | Whether a spell away from the Mac was long enough to reset for |
| `AlertSound.swift` | Which of the built-in alert sounds plays at which moment |

### `AiTwinPlatform` — the seam (7 protocols, no implementations)

`ScreenProviding` · `WindowManaging` · `IdleMonitoring` · `PresenceObserving` ·
`SoundPlaying` · `LoginItemManaging` · `CharacterPackLoading`

Everything the domain needs from an operating system, and nothing else. The
narrowness is the point: a Windows port has six things to implement, not "the
whole app minus the bits that happen to be portable".

### `AiTwinMac` — the adapters (all AppKit is here)

| File | Notes |
|---|---|
| `CompanionPanel.swift` | The `NSPanel` configuration — see below |
| `MacWindowManager.swift` | Show/hide/move. Walk interpolation at 60fps |
| `MacScreenProvider.swift` | `NSScreen` → `ScreenInfo`, and display-change notifications |
| `MacIdleMonitor.swift` | `CGEventSource` — **no permissions required** |
| `MacPresenceObserver.swift` | Lock, screensaver, sleep and their inverses, latched into one leaving and one returning |
| `MacLoginItem.swift` | `SMAppService` |
| `MacCharacterPackLoader.swift` | Directory scanning + `FrameImageCache` |

### `AiTwinUI` — SwiftUI views

`CharacterView` (the `.interpolation(.none)` that keeps pixel art crisp) ·
`SpeechBubbleView` · `CompanionOverlayView` · `SettingsView` · two view models.

### `AiTwinApp` — composition

`AppCoordinator` is the only object aware of both `ReminderEngine` and
`NSWindow`. It holds no timing policy: the engine decides *when*, the state
machine decides *what*, and the coordinator only translates between them and the
screen.

---

## The window strategy

The character lives in a `CompanionPanel`, an `NSPanel` configured as:

| Setting | Value | Why |
|---|---|---|
| Class | `NSPanel`, `.nonactivatingPanel` | **The critical one.** A plain `NSWindow` activates its app when touched, yanking focus out of whatever you were typing. A non-activating panel never does |
| Style | `.borderless` | No title bar, no traffic lights |
| Background | clear, `isOpaque = false`, no shadow | The sprite floats; there is no rectangle |
| Level | `.statusBar` (25) | Above normal *and* other floating windows |
| Collection | `.canJoinAllSpaces` | Follows you between Spaces |
| | `.stationary` | Doesn't slide during Mission Control |
| | `.fullScreenAuxiliary` | Allows appearing over full-screen apps |
| Mouse | `ignoresMouseEvents = true` | **Clicks pass through**, except while a bubble with buttons is up |
| App policy | `.accessory` + `LSUIElement` | No Dock icon, no ⌘-Tab entry |

### Answering the spec's six questions

1. **Which APIs** — `NSPanel` + `NSHostingView`, `.statusBar` level, the three collection behaviours above, `NSApp.setActivationPolicy(.accessory)`.
2. **Why** — the non-activating panel is the only configuration that gives a visible, occasionally interactive overlay which never steals focus.
3. **Limitations** — behaviour over other apps' native full-screen spaces is the flaky case; see manual test 10, marked **needs verification**. macOS also offers no API to draw *behind* desktop icons while staying interactive, so "lives on the desktop" means floating above the wallpaper, not embedded in it.
4. **Multiple displays** — positions from `NSScreen.visibleFrame` (so it respects the Dock and menu bar) and re-anchors on `didChangeScreenParametersNotification`, so unplugging a monitor relocates the character rather than stranding it. V1 keeps the character on one display; it does not roam.
5. **Above other apps** — yes, above normal and floating windows. Full-screen: see (3).
6. **Interference with clicking** — **none.** The panel ignores mouse events except during the few seconds a reminder bubble with buttons is showing.

---

## Error handling

Nothing about artwork can crash the app. The chain:

```
requested clip + glasses → requested clip → idle → built-in vector placeholder
```

- Corrupt frame → skipped, the rest of the clip plays
- Missing clip folder → falls back to idle
- Pack with no idle → the bundled Default pack loads instead
- No packs at all → the vector placeholder draws
- Corrupt settings JSON → defaults load; the app still launches
- Every display disappears → a sane fallback frame rather than an empty-array crash
- Login item refused → a warning in Settings, not a failure
- Zero frame duration in a malformed pack → the sequencer does not spin

---

## Windows roadmap (nothing here has been tested)

**Shared unchanged — `AiTwinCore`, all 125 tests:** reminder timing, the state
machine, animation sequencing, frame discovery, pack resolution, placement
maths, quiet hours, water logging, settings, messages. It imports only
Foundation, which is available in the Swift Windows toolchain.

**Requires a Windows implementation — the seven `AiTwinPlatform` protocols:**

| Protocol | Likely Windows approach | Risk |
|---|---|---|
| `WindowManaging` | Layered window: `WS_EX_LAYERED` + `WS_EX_TRANSPARENT` + `WS_EX_TOOLWINDOW`, `UpdateLayeredWindow` for per-pixel alpha | **Highest.** The closest analogue to a transparent non-activating panel; `WS_EX_NOACTIVATE` covers the focus-stealing half |
| `ScreenProviding` | `EnumDisplayMonitors`, `GetMonitorInfo` | Low — coordinate space differs (y-down), so conversion belongs in the adapter |
| `IdleMonitoring` | `GetLastInputInfo` | Low |
| `PresenceObserving` | `WM_POWERBROADCAST` for sleep, plus `WTSRegisterSessionNotification` → `WTS_SESSION_LOCK` / `WTS_SESSION_UNLOCK` | Low — and the lock half is *public* API on Windows, unlike macOS |
| `SoundPlaying` | `PlaySound` with `SND_ALIAS`, over the registry's `AppEvents` scheme | Low — the *names* differ, so `AlertSound`'s cases would need a per-platform mapping rather than being file names |
| `LoginItemManaging` | `HKCU\...\Run` registry key or Task Scheduler | Low |
| `CharacterPackLoading` | Same logic, `%APPDATA%\AiTwin\Characters` | Low |

**Also needed:** a UI layer, since SwiftUI is macOS/iOS only. `AiTwinUI` would be
rewritten; `AiTwinCore` and the view *models* would not.

**Order of work:** (1) confirm `AiTwinCore` builds and its tests pass on Windows;
(2) prototype the layered window alone — if per-pixel alpha plus click-through
plus always-on-top cannot be made to work together, the project stops there;
(3) implement the remaining five protocols; (4) build a UI.

No Windows code exists in this repository, and none should be added before
step (2) proves the approach.
