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
- [x] Greeting on wake and unlock, latched so it fires once — and never onto a
      still-locked screen

### Away from the Mac
- [x] Screen lock, screensaver and sleep all stop the clock
- [x] Coming back after a real absence **restarts** every cycle, so a reminder
      never ambushes you the moment you sit down
- [x] Under a minute away changes nothing — no reset, no greeting
- [x] She can never appear on the lock screen
- [x] A focus session ends rather than pausing when you lock
- [x] A reminder on screen when you lock is taken down and counted as skipped
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

**Substantially complete.** Streaks and stats, stretch reminders, focus sessions,
idle chatter and iCloud sync all ship; two mood *triggers* remain.

Everything needed for a version people can actually use.

> **Sound is deliberately out of scope for now.** It moves to Phase 3 with voice.

### 1. Streaks and weekly stats
- [x] `StreakTracker` in Core — consecutive days the water goal was met
- [x] Menu bar: "🔥 4 day streak"
- [x] Current streak + best streak
- [x] Settings → Stats tab with a **7-day bar chart**: glasses drunk, eye breaks taken
- [x] **Breaks accepted vs snoozed vs ignored**, per day
- [x] Rolling history store (`UserDefaults` JSON, tolerant-decode pattern as settings)
- [x] Streak milestones (3 / 7 / 14 / 30 days) trigger the `cheer` animation
- [x] Streak survives one missed day gracefully — a single slip should not feel punitive

> **Record everything from day one.** Focus minutes and skip counts cannot be
> backfilled, so the store should capture them even before the views that show
> them exist.

### 2. Posture and stretch reminders
- [x] Third `ReminderKind.stretch`, reusing the whole existing engine
- [x] Own interval (default 60 min), own enable toggle
- [x] New `stretch` clip; falls back to idle if a pack lacks it
- [x] Ten stretch messages, in the same rotating personalised style
- [ ] Optional guided sequence — "roll your shoulders… now your neck" over ~30s

### 3. Focus sessions (Pomodoro)
- [x] Start from the menu bar: "Start Focus — 25 min"
- [x] Character sits and reads in a chair, **completely still**, at the corner
- [x] Session timer floats above her, ticking down
- [ ] **All reminders suppressed during a focus session** — water included.
      A hydration nudge mid-flow is exactly the interruption you started the
      session to avoid
- [ ] Break between sessions: she stands, stretches, suggests water
- [x] Session lengths configurable (25/45/50 min), and a long break every 4th
- [x] **Suppressed reminders are delivered in the break**, not dropped
- [x] New clips: `focus` (sitting, reading), and a chair prop
- [x] Sessions counted toward the weekly stats

> **Design note:** the character must not animate during focus beyond the
> gentlest breathing loop. Movement in peripheral vision is exactly what breaks
> concentration, so the reading pose should be near-static by design — a 2-frame
> idle at most.

### 4. Idle chatter
- [x] Occasional unprompted lines when nothing else is happening
- [x] Uses the **`peek`** pose — half-hidden at the screen edge, no full entrance
- [x] Its own pool of ten, context-aware (time of day, streak, session length)
- [x] **Default: rare** — at most once every ~90 minutes, often less
- [x] Frequency setting: Off / Rare / Occasional
- [x] **Rate limited hard** — see the note below

> **"Rate limited hard" means:** a strict ceiling on how often she may speak
> unprompted — at most once every ~90 minutes, never twice in a row, never
> within 10 minutes of a real reminder, never during focus or quiet hours, and
> silent entirely if you are idle. A desktop pet that chats freely is charming
> for one day and uninstalled on the third. The limit is the feature.

### 5. More moods

Four new poses, each tied to a behaviour rather than added for their own sake.
Art prompts 16–19 are written; the clips are already registered in the loader
and the importer.

- [x] **Art imported and normalised** for all four, plus `focus`, `stretch` and `sitting`
- [x] **Proud / cheering** — plays on streak milestones (3/7/14/30/100 days)
- [x] **Peeking** — drives idle chatter, so she speaks without walking in
- [x] **Every mood previewable** from Settings → General → Developer
- [x] **Concerned** — fires after 3 reminders waved away in a row, or 3 hours of
      unbroken screen time. Accepting one clears the slate
- [x] **Sleepy / yawning** — fires after 23:00, or a 5-hour session at any hour.
      Sleepiness outranks concern, since "go to bed" is the more useful line at 1am
- [x] Both share a 2-hour cooldown and the same veto list as chatter

### 6. iCloud sync — **dropped**

Built, then set aside on 2026-08-31: it cannot be verified without a paid
developer account, and it is not worth carrying unverified code. `CloudSyncStore`
and `ActivityLog.merged(with:)` remain in the tree, unused by the app, if it is
ever picked back up.

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

## 🎨 Entrance policy — what walks and what doesn't

Walking is reserved for **"I have come over to tell you something"**. Everything
else appears where it belongs. Walking the full width of the screen for a
spontaneous hello reads as laboured, and repeating it for every event was the
single biggest thing making her feel mechanical.

| Moment | Entrance | Why |
|---|---|---|
| Water / eye-break / stretch reminder | **Walks in** | She is coming over with a purpose. The journey is the point |
| Greeting | Pops in at the corner | A hello is spontaneous; you do not walk across a room to wave |
| Goal / streak celebration | Pops in | Same — it is a reaction, not an errand |
| Focus session | Pops in, then sits | She settles in beside you; walking would break the calm |
| **Idle chatter** | **Leans in from the screen edge** | Half-hidden, brief, withdrawn the same way. The least intrusive arrival there is |
| Mood preview (Settings) | Pops in | It is a test, not a performance |

## 🛠 Development vs production

Developer tooling is excluded from release builds **by compilation** — see
[DEVELOPMENT.md](DEVELOPMENT.md). `./Scripts/build-app.sh` is production;
`--dev` adds the Developer tab and sample data. Verified by inspecting the
binary, not assumed.

## 🐛 Known issues

- [ ] Nothing outstanding from Phase 1.

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

**Round 2, 2026-08-31**

- [x] **Water is measured in millilitres.** A glass is not a unit, so the goal is
      a volume (default 3 L) and the glass size converts it (default 250 ml)
- [x] **Character sizes normalised properly.** Two earlier attempts used face
      width, which expression confounds. Waist-to-feet is unaffected by hair or
      expression, and showed the clips you approved had 16% longer legs than
      idle — so idle was the small one. Everything now lands within 270–273px
- [x] **Top corners no longer sit low.** The panel reserves 150pt above the
      character for the cloud; at a top corner that reserve was between her and
      the screen edge. She now anchors to the top with the cloud below her
- [x] **Any pack installs without Python.** `PackGeometry` in Core does the
      arithmetic, `PackInstaller` in Mac reads pixels and writes files. Verified
      with three clips drawn at three different zooms: all came out within 1px
- [x] **Drag a `.zip` onto Settings → Character** to install a character
- [x] **History exports as CSV** — 13 columns, volumes in millilitres
- [x] Glasses feature removed entirely, including the variant-clip machinery
- [x] Stretch no longer sits down first; milestones are wordless; concern waits
      for an answer instead of leaving on a timer
- [x] The two eye-break settings sections merged into one
- [x] Menu bar leads with Focus
- [x] Settings ordered General, Reminders, Focus, Character, Progress, Developer

**Code review, 2026-08-31 — all nine findings**

- [x] Streak messages always read "0 days" — `pick` expanded the template before
      the day count was applied, so the second pass had nothing left to replace
- [x] A focus break could never leave `.focusing`, so the session's own
      celebration never played and reminders released at the break were sent to
      a state that ignored them and were then logged as *ignored*
- [x] `silentCelebration` latched on when the water goal was hit, muting the
      *next* celebration entirely
- [x] A running routine overwrote the walk clip mid-exit, so she left in an idle pose
- [x] Starting a focus session while she was on screen never reached `.focusing`
- [x] Merging history took `max(waterGoal)`, which let a goal raised on another
      Mac retroactively un-meet a finished day and break an earned streak
- [x] iCloud sync is parked, so it no longer runs: that removes the merge-order
      bug, the vacuous last-write-wins stamp, and two writes per slider tick to
      a rate-limited store

**Artwork and interface**

- [x] `concerned` and `yawn` rendered ~11% small — more hair volume meant the
      same bounding box held a smaller body. Rescaled to match, measured by face
      width rather than by eye
- [x] `cheer`'s jump frames were cropped at the top. The canvas was sized by each
      clip's *height*, but a clip is aligned by its lowest point, so a jump sits
      higher than its height suggests. Canvas is now sized by full reach, and the
      importer shrinks a clip as a fallback rather than guillotining it
- [x] `cheer` was also oversized: its tallest frame is a standing pose, so the
      headroom hint that suited arms-overhead poses inflated the whole clip
- [x] Menu bar opened with five greyed-out info rows before any action. Now
      actions only, with the countdowns behind a Status submenu where every row
      is live
- [x] Menu shortcuts removed — they implied global hotkeys but only fired while
      the menu was open
- [x] Developer tab rebuilt as an inventory: every reminder, every routine with
      its clip chain, every pose, labelled by what triggers it in real use

- [x] **The character had shrunk 15%.** Growing the canvas to fit tall poses made
      everything smaller, because the app scaled frames by *canvas* height. Packs
      now ship a `pack.json` saying what share of the frame the character fills,
      and the app scales by that — so headroom for a jump costs nothing, and the
      size slider finally means her actual height
- [x] **The thought cloud sat through her head when she jumped.** It was anchored
      to the character height rather than the frame, so a reach or a jump put her
      hands behind it. Now cleared above the whole frame
- [x] **Poses with raised arms were cropped in the artwork.** Canvas height is
      computed from the tallest pose across the pack
- [x] **`happy` was headless** — it had been rebuilt from an already-cropped
      intermediate. Re-imported from the original artwork
- [x] **Previews appeared to do nothing.** Setting a window position did not
      cancel an in-flight walk, so anything summoned while she was walking off
      got dragged off screen with her. `setPosition` now cancels the walk
- [x] **Peek appeared mid-screen and tiny.** It is drawn hugging a vertical
      border, so it now hugs the canvas edge, is sized to head-and-torso rather
      than a whole body, and the window sits flush against the display edge
- [x] **She froze instead of walking.** The walk's own per-frame update called
      the public `setPosition`, which cancels a walk — so the first frame of
      every walk cancelled the walk it belonged to. She moved one pixel and
      stopped. Now guarded by a real-window regression test that fails with two
      distinct positions when the bug is reintroduced
- [x] **She stopped walking off screen.** The peek flag latched on after the
      first idle chatter, so every later exit became a 46-point slide
- [x] **The cloud floated 50 points above her head.** It cleared the whole frame,
      which carries headroom only a jump uses. Each clip now records where its
      art starts, and the cloud hugs that pose
- [x] **Multi-pose behaviours are choreographed in code** rather than baked into
      artwork — stretching is sit → stand → reach, finishing a focus session is
      look up → stand → cheer
- [x] **Settings was a row of six tabs.** Replaced with a sidebar: every section
      visible at once, named, one click instead of two

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
