# AiTwin

**A pixel-art desktop companion for macOS that reminds you to drink water and rest your eyes.**

A small character lives at the corner of your screen. It greets you when you sit
down, walks in every so often to remind you to drink something, and taps you on
the shoulder when you've been staring at the screen for too long. Then it walks
away again.

No Dock icon. No windows. No notification spam.

---

## Features

- **Walk-in reminders** — the character walks in from the screen edge, says its piece, and leaves
- **Water reminders** with a daily glass counter and goal
- **40-minute eye-break cycle** (configurable), which only counts time you are actually at the Mac
- **Quiet hours** so nothing appears while you sleep
- **Four corner positions** — bottom-left by default
- **Bring your own character** — drop a folder of PNGs in and select it; no rebuild
- **Never steals focus, never blocks a click** — a non-activating panel that ignores mouse events
- **Menu bar controls** — pause, snooze, log a glass, trigger a reminder, countdown to the next one
- **Test mode** — 10-second intervals for trying things out, using the same code path as production

## Demo

*(Add a screen recording here. `⌘⇧5` records a region of your screen.)*

```
Placeholder — record: launch → greeting → water reminder → dismiss → walk off
```

---

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel
- **Swift 6 toolchain** — Xcode *or* just the Command Line Tools (`xcode-select --install`)

Xcode is **not** required.

---

## Installation

### Build it yourself

```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
cd YOUR_REPO/AiTwin
./Scripts/build-app.sh
open build/AiTwin.app
```

To keep it:

```bash
cp -R build/AiTwin.app /Applications/
```

### From a release

Download the `.dmg` from Releases, drag AiTwin to Applications.

> The app is not notarised, so the first launch needs **right-click → Open →
> Open**. After that it opens normally. See [Docs/PACKAGING.md](Docs/PACKAGING.md).

---

## Running locally

```bash
swift build          # compile
swift run AiTwin     # run without building a bundle
swift test           # 125 tests, ~10ms
```

`swift run` works for quick iteration, but a few features need a real bundle:
start-at-login (`SMAppService` requires one) and the bundled character pack path.
Use `./Scripts/build-app.sh` when testing those.

If you have Xcode: `open Package.swift` — no `.xcodeproj` required.

---

## Project structure

```
AiTwin/
├── Package.swift
├── Sources/
│   ├── AiTwinCore/      Domain logic. Foundation only — no AppKit, no SwiftUI
│   ├── AiTwinPlatform/  6 protocols: the seam between domain and OS
│   ├── AiTwinMac/       macOS implementations. All AppKit lives here
│   ├── AiTwinUI/        SwiftUI views and view models
│   └── AiTwinApp/       Composition root, menu bar, coordinator
├── Tests/AiTwinCoreTests/
├── Resources/Characters/Default/   Bundled placeholder character
├── Scripts/
│   ├── build-app.sh                → build/AiTwin.app
│   ├── package-dmg.sh              → build/AiTwin-1.0.0.dmg
│   └── generate_placeholder_character.py
└── Docs/
    ├── ARCHITECTURE.md   Design decisions, window strategy, Windows roadmap
    ├── ASSETS.md         Image spec, folder layout, format comparison
    ├── PROMPTS.md        AI prompts for generating your own character
    ├── TESTPLAN.md       What is tested, and what deliberately is not
    ├── MANUAL_TESTS.md   Checklist for verifying on your Mac
    └── PACKAGING.md      .app vs .dmg vs Release, signing, notarisation
```

Dependencies point one way: `App → UI → Mac → Platform → Core`. `AiTwinCore`
imports only Foundation, which is enforced by the module boundary.

---

## Adding your own character

1. **Settings → Character → Open Characters Folder…**
   (that's `~/Library/Application Support/AiTwin/Characters/`)
2. Create a folder named after your character
3. Add frames in this layout:

```
YourCharacter/
├── Idle/            idle_01.png   idle_02.png   …
├── Walking/         walk_01.png   walk_02.png   …
├── Waving/          wave_01.png   …
├── WaterReminder/   drink_01.png  …
├── EyeBreak/        eyebreak_01.png …
└── Sleep/           sleep_01.png  …
```

4. **Settings → Character → Reload Characters**, then select it

### Or let the importer do it

Hand-cropping and hand-naming frames is slow, and it does not fix the thing that
actually breaks the animation: frames generated in separate requests come back at
different scales, so the character visibly changes size the moment it starts
walking. The importer fixes that:

```bash
python3 Scripts/import_character.py ~/Downloads/my-character --name Luna --install
```

It **slices contact sheets** (drop in the multi-pose image your model returned —
no cropping), **drops duplicates**, **normalises** every clip to one character
height and one shared baseline, and **names** everything correctly. Add
`--dry-run` to see what it would do first.

So the whole workflow is: generate one sheet per animation → drop the sheets in a
folder → run the importer → Reload Characters.

Requires `pip3 install pillow numpy`.

**A pack with a single `Idle/idle_01.png` is valid.** Everything else falls back
to idle, so you can start small and fill in animations later.

Requirements: 64×64 px, PNG with real transparency, no anti-aliasing, and the
character in the same position on every frame. Full spec in
[Docs/ASSETS.md](Docs/ASSETS.md).

Two things you don't need to draw: **walking left** (the app mirrors the
right-facing cycle) and **glasses off** (that's just your normal frames — glasses
are a `_glasses` variant suffix).

## Creating animation frames

[Docs/PROMPTS.md](Docs/PROMPTS.md) has copy-paste prompts for ChatGPT / Nano
Banana / Midjourney covering all twelve frame types, plus the part that actually
matters: how to keep twelve separately generated images looking like the same
character. Short version — nail one reference image, attach it to every
subsequent prompt, and say explicitly what must *not* change.

To regenerate the bundled placeholder character:

```bash
python3 Scripts/generate_placeholder_character.py   # needs Pillow
```

---

## Configuration

Everything is in **Settings**, reachable from the menu bar icon.

| | Default | Range |
|---|---|---|
| Water reminder | 45 min | 20 min – 1 hr (+ 10s/30s/1m in Test Mode) |
| Eye break | **40 min** | 20 min – 1 hr (+ Test Mode) |
| Snooze | 5 min | 1 – 15 min |
| Daily water goal | 8 glasses | 1 – 20 |
| Corner | **Bottom-left** | any of the four |
| Character size | 128 pt | 64 – 256 |
| Idle pause | on, after 5 min | on/off |
| Quiet hours | off | any window, midnight-crossing supported |

Build-time constants live in one file —
[AiTwinConfiguration.swift](Sources/AiTwinCore/AiTwinConfiguration.swift) — with
`.production` and `.testing` presets. No timing literal appears anywhere else in
the codebase.

**Test Mode** (Settings → General) adds 10s / 30s / 1min to the interval
pickers. It changes only the numbers — the production reminder logic runs
untouched, which is the only way testing it proves anything.

---

## Testing

```bash
swift test                                  # all 125
swift test --filter ReminderEngineTests     # one suite
swift test --filter "40 minutes"            # one test
```

The whole suite runs in about ten milliseconds, including a 40-minute eye-break
cycle and a full day of water reminders, because the domain takes an injected
clock rather than calling `Date()`. See [Docs/TESTPLAN.md](Docs/TESTPLAN.md) —
including an explicit list of what the automated tests **cannot** cover.

Before shipping a change, also run [Docs/MANUAL_TESTS.md](Docs/MANUAL_TESTS.md):
transparency, click-through, multi-display and sleep/wake behaviour can only be
checked by hand.

---

## Building and packaging

```bash
./Scripts/build-app.sh          # → build/AiTwin.app
./Scripts/package-dmg.sh        # → build/AiTwin-1.0.0.dmg
```

The app is ad-hoc signed, not notarised. [Docs/PACKAGING.md](Docs/PACKAGING.md)
covers what that means for people who download it, and how to notarise if you
get a Developer ID.

---

## Windows roadmap

**Not implemented. Not tested. No Windows code exists in this repository.**

The architecture is arranged so a port is possible rather than hypothetical:
`AiTwinCore` — all reminder timing, the state machine, animation sequencing,
placement maths, settings — imports only Foundation and would move across
unchanged, tests included. The six protocols in `AiTwinPlatform` are the entire
list of what needs a Windows implementation.

The genuinely risky one is `WindowManaging`: a layered window
(`WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE`) is the closest analogue
to a transparent non-activating `NSPanel`, and whether per-pixel alpha,
click-through and always-on-top can all hold together is the thing to prototype
before writing anything else. `AiTwinUI` would need rewriting, since SwiftUI is
Apple-only.

Full analysis in [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md).

---

## Architecture

```
AiTwinApp        composition root
     ↓
AiTwinUI  ──▶  AiTwinMac  ──▶  AiTwinPlatform  ──▶  AiTwinCore
SwiftUI        AppKit only     6 protocols          Foundation only
                                                    125 tests
```

Three decisions shaped the rest:

1. **The domain has no clock.** `ReminderEngine` asks an injected `Clock` and advances on `tick()`. That is why a 40-minute cycle is testable in microseconds.
2. **Timers are deadlines, not countdowns.** Storing an absolute `Date` rather than counting ticks means closing the lid does not push your eye break 40 minutes into the future.
3. **Placement maths lives in Core.** `MacWindowManager` contains no arithmetic; every corner calculation and screen-boundary clamp is a pure, tested function.

The window itself is a non-activating, borderless, transparent `NSPanel` at
`.statusBar` level that ignores mouse events except while a reminder bubble is
up — so it floats above your work, never takes focus, and never blocks a click.
Details and the known limitation around full-screen apps are in
[Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md).

---

## Contributing

1. Fork and branch
2. **Add tests first** — domain changes belong in `AiTwinCore` with coverage in `Tests/AiTwinCoreTests`
3. `swift test` stays green
4. Keep `AiTwinCore` free of AppKit and SwiftUI imports — that boundary is the whole design
5. Run the relevant parts of [Docs/MANUAL_TESTS.md](Docs/MANUAL_TESTS.md) for anything touching windows or animation
6. Small, focused files

## License

MIT — see [LICENSE](LICENSE).
