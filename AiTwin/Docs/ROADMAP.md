# AiTwin Roadmap

Running checklist. Tick things off as they land, and keep the *Next* list short
enough that it stays a plan rather than a wish list.

Last updated: **2026-08-30**

---

## ✅ Shipped

### Reminders
- [x] Water reminder on a configurable interval
- [x] Eye-break reminder, 40 min default, configurable
- [x] Deadline-based timers that survive sleep and lid-close
- [x] Snooze, with its own interval
- [x] Auto-dismiss when nobody responds
- [x] One reminder at a time, queued deterministically
- [x] Pause / resume, keeping banked progress
- [x] Quiet hours, including windows crossing midnight
- [x] Idle detection — only counts time actually at the Mac
- [x] Daily water counter with a goal, resetting at midnight
- [x] Non-repeating reminder messages

### Character
- [x] Walk-in / walk-out to a configurable corner (bottom-left default)
- [x] Idle, walk, wave, drink, eye-break, sleep, happy clips
- [x] Glasses as a variant layer, not a separate state
- [x] One walk cycle mirrored for both directions
- [x] Graceful fallback chain for missing art → idle → vector placeholder
- [x] Character packs loaded from disk, no rebuild needed
- [x] Auto-selected rendering: nearest-neighbour for pixel art, smooth for illustration
- [x] Celebration animation when the daily water goal is reached

### Eye break that actually works
- [x] Accepting an eye break starts a real countdown (10/20/30/60s, configurable)
- [x] The screen dims for the duration, so there is nothing to read
- [x] Dimming is visual only — never blocks clicks or typing
- [x] Countdown shown in her bubble, with Skip
- [x] She walks off once the break is done

### Greetings
- [x] Time-of-day greeting on launch (morning / afternoon / evening / late night)
- [x] Greeting on wake and unlock, coalesced so it fires once
- [x] **Your name in Settings** — "Hey Suresh 👋"
- [x] Multiple creative variants per slot, non-repeating
- [x] First-run: Settings opens automatically after the first hello

### Window
- [x] Non-activating transparent panel — never steals focus
- [x] Click-through except while a thought cloud with buttons is showing
- [x] Follows across Spaces, survives display disconnect
- [x] Pixel-art thought cloud, drawn procedurally, in the character's colours
- [x] Four selectable message-box styles with live previews in Settings
- [x] Pop-in entrance for greetings and celebrations; walking reserved for reminders
- [x] Ten rotating lines for every moment, personalised with your name

### App
- [x] Menu bar only, no Dock icon
- [x] Menu bar shows countdowns, pause, +1 glass, remind now
- [x] Ai_Twin logo as the app icon and menu bar glyph
- [x] Settings window: reminders, character, general
- [x] Test mode with 10s / 30s / 1min intervals
- [x] Start at login
- [x] Settings survive adding new fields in later versions
- [x] `import_character.py` — slices sheets, normalises scale, names frames
- [x] 143 automated tests

---

## 🔜 Phase 1 — Launch

Everything needed for a version people can actually use. Ordered; take from the top.

> **Sound is deliberately out of scope for now.** It moves to Phase 3 with voice.

### 1. Streaks and weekly stats
- [ ] `StreakTracker` in Core — consecutive days the water goal was met
- [ ] Menu bar: "🔥 4 day streak"
- [ ] Current streak + best streak
- [ ] Settings → Stats tab with a **7-day bar chart**: glasses drunk, eye breaks taken
- [ ] **Breaks accepted vs snoozed vs ignored**, per day
- [ ] Rolling history store (`UserDefaults` JSON, tolerant-decode pattern as settings)
- [ ] Streak milestones (3 / 7 / 14 / 30 days) trigger the `cheer` animation
- [ ] Streak survives one missed day gracefully — a single slip should not feel punitive

> **Record everything from day one.** Focus minutes and skip counts cannot be
> backfilled, so the store should capture them even before the views that show
> them exist.

### 2. Posture and stretch reminders
- [ ] Third `ReminderKind.stretch`, reusing the whole existing engine
- [ ] Own interval (default 60 min), own enable toggle
- [ ] New `stretch` clip; falls back to idle if a pack lacks it
- [ ] Ten stretch messages, in the same rotating personalised style
- [ ] Optional guided sequence — "roll your shoulders… now your neck" over ~30s

### 3. Focus sessions (Pomodoro)
- [ ] Start from the menu bar: "Start Focus — 25 min"
- [ ] Character sits and reads in a chair, **completely still**, at the corner
- [ ] Session timer floats above her, ticking down
- [ ] **All reminders suppressed during a focus session** — water included.
      A hydration nudge mid-flow is exactly the interruption you started the
      session to avoid
- [ ] Break between sessions: she stands, stretches, suggests water
- [ ] Session lengths configurable (25/45/50 min), and a long break every 4th
- [ ] **Suppressed reminders are delivered in the break**, not dropped
- [ ] New clips: `focus` (sitting, reading), and a chair prop
- [ ] Sessions counted toward the weekly stats

> **Design note:** the character must not animate during focus beyond the
> gentlest breathing loop. Movement in peripheral vision is exactly what breaks
> concentration, so the reading pose should be near-static by design — a 2-frame
> idle at most.

### 4. Idle chatter
- [ ] Occasional unprompted lines when nothing else is happening
- [ ] Uses the **`peek`** pose — half-hidden at the screen edge, no full entrance
- [ ] Its own pool of ten, context-aware (time of day, streak, session length)
- [ ] **Default: rare** — at most once every ~90 minutes, often less
- [ ] Frequency setting: Off / Rare / Occasional
- [ ] **Rate limited hard** — see the note below

> **"Rate limited hard" means:** a strict ceiling on how often she may speak
> unprompted — at most once every ~90 minutes, never twice in a row, never
> within 10 minutes of a real reminder, never during focus or quiet hours, and
> silent entirely if you are idle. A desktop pet that chats freely is charming
> for one day and uninstalled on the third. The limit is the feature.

### 5. More moods

Four new poses, each tied to a behaviour rather than added for their own sake.
Art prompts 16–19 are written; the clips are already registered in the loader
and the importer.

- [ ] **Concerned** — after a long stretch with no break, or several skips in a
      row. Tone is caring, never scolding; a companion that induces guilt gets quit
- [ ] **Proud / cheering** — streak milestones and completed focus sets only, so
      it stays special. Everyday goal celebrations keep using `happy`
- [ ] **Peeking** — half-hidden at the screen edge. This is what makes idle
      chatter unintrusive: she can say something small without walking in
- [ ] **Sleepy / yawning** — late nights and very long sessions, nudging you to stop

### 6. iCloud sync
- [ ] Settings and streaks sync via `NSUbiquitousKeyValueStore`
- [ ] Last-write-wins with a timestamp; no merge UI
- [ ] Works offline and syncs later — never blocks the app
- [ ] Character packs stay local (too large, and picked per-machine)

### 7. Apple Health — investigated, parked

**Verified on this Mac, not assumed:**

| Check | Result |
|---|---|
| `HealthKit.framework` in the macOS SDK | ✅ present |
| Annotated available on macOS | ✅ `API_AVAILABLE(… macos(13.0))` |
| `HKQuantityTypeIdentifier.dietaryWater` exists | ✅ yes — water intake is a first-class Health type |
| Compiles and links against it | ✅ built a probe |
| **`HKHealthStore.isHealthDataAvailable()`** | ❌ **returns `false`** on this machine |

So the API is real on macOS 13+, and water intake is exactly the kind of data
Health wants. Two things block it today:

1. **`isHealthDataAvailable()` is false here.** There is no Health app on macOS;
   the store is not backed by anything on a Mac that has never had it provisioned.
2. **Writing needs the `com.apple.developer.healthkit` entitlement**, which
   requires a paid Apple Developer account and a real provisioning profile. An
   ad-hoc signed build cannot claim it.

- [ ] Re-check `isHealthDataAvailable()` once there is a Developer ID and a
      properly signed build — that is the cheap experiment that settles it
- [ ] If still false: the fallback is a small **iOS companion app** that receives
      the water log over iCloud and writes it to HealthKit on the phone, where
      the store definitely exists. That is a real project, not a flag
- [ ] Either way this lands *after* iCloud sync, since both paths need it first

> Apple Watch already nudges you to stand, so stretch reminders would overlap.
> Water intake is the one metric AiTwin has that Health genuinely lacks.

---

## 🎨 Phase 2 — Character generation

**Give it one reference image; it produces every pose.**

Today, making a character means running twelve prompts by hand and importing the
results. Phase 2 automates that: drop in one `reference.png`, and every mode is
generated for you.

- [ ] Separate Python service, not part of the Mac app
- [ ] Takes one reference image + a character description
- [ ] Calls an image model (OpenAI Images, or Gemini) once per clip, passing the
      reference every time for consistency
- [ ] Requests each clip as a **single multi-pose sheet**, which is what keeps
      frames within a clip consistent
- [ ] Feeds output straight into the existing `import_character.py` pipeline —
      slicing, normalisation and naming already work and do not change
- [ ] Validates results: character height per clip, silhouette similarity to the
      reference, transparency present. Flags drift and offers a re-roll
- [ ] CLI first: `python3 generate_character.py reference.png --name Nish`
- [ ] Later: driven from the Mac app's Settings

> **Architecture sketch:** `reference.png` → prompt builder (per clip, from
> `PROMPTS.md`) → image API → sheet → `import_character.py` → validator →
> `~/Library/Application Support/AiTwin/Characters/<Name>/`. The Mac app needs
> **no changes at all** for this — the pack format is already the contract
> between them. That is why this is a clean phase boundary rather than a rewrite.

**Cost and keys:** the API key lives in the Python service, never in the app.
Roughly 6–10 image generations per character.

---

## 🔊 Phase 3 — Voice

- [ ] Settings: voice on/off
- [ ] Settings: **which** voice — system voices, a bundled set, or a cloned one
- [ ] Per-character voice, shipped inside the pack (`Sounds/` or a voice id)
- [ ] Speaks her lines aloud instead of, or alongside, the thought cloud
- [ ] Sound effects for reminders and the focus timer
- [ ] Off by default, and hard-muted during quiet hours and focus sessions

> Everything sound-related lives here, including the simple chimes that were
> previously slated for Phase 1.

---

## 🧊 Someday

- [ ] Character marketplace / shared pack format
- [ ] Weather- or calendar-aware moods
- [ ] Notarised release + Homebrew cask

**Explicitly not doing:** multiple characters on screen at once.

---

## 🪟 Windows — not started, not tested

Parked. No Windows code exists. See [ARCHITECTURE.md](ARCHITECTURE.md) for the
seam that would make it possible.

---

## 🐛 Known issues

- [ ] Nish pack: `wave`, `drink` and `sleep` were regenerated after data loss;
      alignment is good but worth a second look if any pose sits oddly.

## ✔️ Verified / resolved

- [x] **Full-screen apps** — confirmed working on macOS 26: the character does
      appear over apps in native full screen.
- [x] **Clip alignment** — confirmed good after importer normalisation.
- [x] **Gatekeeper** — a locally built `.app` carries no `com.apple.quarantine`
      attribute, so it opens on a double-click. The right-click warning only
      applies to a build someone *downloads* from a release, which is why this
      never appeared locally.

## ✔️ Fixed

- [x] Eye break is a full minute by default, and she vanishes when it ends
      rather than walking back across the screen
- [x] Pop-in slowed to 0.9s — at 0.45s it was over before it was noticed
- [x] Dimming defaults to 50%


- [x] Message box replaced with a hand-styled pixel thought cloud, drawn rather
      than shipped as art so it stretches to any message without distorting
- [x] Buttons and the cloud's inner ring use a colour sampled from the character
- [x] Purple sparkles removed from the cloud, and the whole box scaled down so
      it reads as smaller than the character rather than looming over her
- [x] Menu bar glyph reduced to 14pt with a transparent margin — it read as cropped
- [x] Greeting cloud pushed the character down and sometimes clipped her out of
      the panel; the walk-out went diagonally. The cloud is now an overlay
      outside layout flow, and SwiftUI no longer resizes the panel.
- [x] Character changed size ~30% between clips — fixed by the importer.
- [x] Nearest-neighbour scaling shredded high-resolution artwork.
- [x] Frame sequencer drifted out of sync from floating-point accumulation.
- [x] Changing an interval appeared to do nothing until the old one elapsed.
