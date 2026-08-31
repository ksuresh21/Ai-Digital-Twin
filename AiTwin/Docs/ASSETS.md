# Asset Specification

Everything you need to know to replace AiTwin's character with your own.

---

## 1. Which format, and why

| | Option A: PNG frames | Option B: Sprite sheet | Option C: GIF | Option D: APNG / WebP |
|---|---|---|---|---|
| Per-frame timing control | ✅ full | ✅ full | ❌ baked in | ❌ baked in |
| Alpha quality | ✅ 8-bit | ✅ 8-bit | ❌ 1-bit — fringing | ✅ 8-bit |
| Replace one frame | ✅ drop a file | ❌ regenerate the sheet | ❌ regenerate | ❌ regenerate |
| Needs metadata | ❌ none | ✅ JSON of slice rects | ❌ | ❌ |
| Native AppKit frame access | ✅ `NSImage` | ✅ + slicing code | ⚠️ coarse | ❌ none for APNG |
| Good for AI-generated art | ✅ generate one at a time | ❌ must compose | ❌ | ❌ |

**AiTwin uses Option A: individual PNG frames.** Three reasons that actually matter:

1. **GIF's alpha is one bit.** A pixel is either fully opaque or fully transparent, so anti-aliased sprite edges get a hard, ugly fringe against your wallpaper. This is the concrete reason not to "just use a GIF", independent of convenience.
2. **You are generating frames with an image model, one at a time.** A sprite sheet would mean compositing them into a grid and maintaining a JSON of slice rectangles — work that exists only to be undone at load time. With PNG frames, generating a new walk cycle means dropping four files in a folder.
3. **APNG has no frame-level AppKit API.** You can display an animated APNG, but you cannot ask it "show me frame 3", which is exactly what the animation engine needs in order to keep the sprite in step with the character's movement across the screen.

The cost of Option A is more files on disk. At a few kilobytes each, that is not a real cost.

---

## 1b. The importer (use this instead of doing it by hand)

```bash
python3 Scripts/import_character.py <folder of your images> --name <PackName> --install
```

It handles the four jobs that make manual preparation slow and error-prone:

| Job | What it does |
|---|---|
| **Slice** | Splits a multi-pose contact sheet into frames on its empty columns, so you never crop by hand |
| **Deduplicate** | Drops byte-identical frames, and the redundant half when a clip has both a sheet and crops of it |
| **Normalise** | Scales each clip so the character is the **same height everywhere** and stands on a **shared baseline** |
| **Name** | Writes `Idle/idle_01.png` and friends into the right folders |

The normalisation is the part that matters most. Clips generated in separate
requests come back at different scales — in one real pack the character was 907px
tall standing and 699px walking, a 30% jump that no amount of renaming fixes.
The transform is computed **per clip and applied to all its frames identically**,
so motion *inside* a clip (a walk cycle's bob, a breathing idle) is preserved
exactly as drawn.

`--dry-run` reports without changing anything. `--install` writes to Application
Support instead of the repo.

---

## 2. Image specification

| Property | Value |
|---|---|
| Canvas | **64 × 64 px** (square, consistent across every frame) |
| Format | PNG-24 with alpha |
| Background | **Fully transparent** — no checkerboard, no white, no colour |
| Colour depth | 8-bit per channel + 8-bit alpha |
| Character height in frame | ~48 px, feet resting at y ≈ 58 |
| Anti-aliasing | **None.** Hard pixel edges only |
| Palette | 8–16 colours. Fewer reads as more deliberately "pixel art" |

**Why 64 × 64:** displayed at the default 128-point character height, that's a clean 2× scale, and 4× on a Retina display. Integer scale factors are what keep pixel art crisp. A 50 × 50 source would land on fractional pixel boundaries and look soft no matter what.

**The single most important rendering detail** — already handled in [CharacterView.swift](../Sources/AiTwinUI/CharacterView.swift) — is `.interpolation(.none)`. macOS smooths images when it scales them, which turns crisp pixel art into a blur. Nearest-neighbour is mandatory.

### Registration (the part people get wrong)

Every frame must place the character **at the same position on the canvas**. If the character sits two pixels lower in `walk_03.png` than in `walk_02.png`, it will visibly bob when it should be walking level. Draw all frames on one canvas and export separately, rather than cropping each one to its content.

---

## 3. Folder structure

```
Resources/Characters/<YourCharacterName>/
├── Idle/            idle_01.png   idle_02.png   idle_03.png   idle_04.png
├── Walking/         walk_01.png   walk_02.png   walk_03.png   walk_04.png
├── Waving/          wave_01.png   wave_02.png   wave_03.png   wave_04.png
├── WaterReminder/   drink_01.png  drink_02.png  drink_03.png  drink_04.png
├── EyeBreak/        eyebreak_01.png … eyebreak_04.png
└── Sleep/           sleep_01.png  sleep_02.png  sleep_03.png  sleep_04.png
```

**Install your own pack here — no rebuild needed:**

```
~/Library/Application Support/AiTwin/Characters/<YourCharacterName>/
```

A pack in that folder shadows a bundled pack of the same name. Settings → Character → *Open Characters Folder…* takes you straight there, and *Reload Characters* picks up changes without restarting.

### Naming rules

- `<prefix>_<number>.png` — the underscore and the numeric tail are both required.
- Numbers may be zero-padded or not; `walk_1.png` and `walk_01.png` both work.
- **Gaps are fine.** `01, 02, 05` plays as three frames.
- Anything that doesn't match is ignored, so a stray `.DS_Store`, `notes.txt` or `reference.png` in the folder is harmless.

---

## 4. Frames per clip, and frame rate

Default frame rate is **8 fps** (`animationFrameDuration = 1/8`), set in [AiTwinConfiguration.swift](../Sources/AiTwinCore/AiTwinConfiguration.swift). 8 fps is a deliberate choice: it reads as characterful pixel-art motion. At 24 fps the same art looks like a smooth modern animation that happens to be blocky, which is worse.

| Clip | Frames | Loops? | What it shows |
|---|---|---|---|
| `idle` | 2–4 | yes | Standing, breathing. A 1–2 px bob is plenty |
| `walk` | 4–8 | yes | One full stride cycle. 4 is the classic minimum |
| `wave` | 3–4 | **no** | Arm rises and holds. Ends on the raised hand |
| `drink` | 3–4 | yes | Glass travels up to the mouth |
| `eyebreak` | 2–4 | yes | Eyes closed, or hands over eyes |
| `sleep` | 2–4 | yes | Resting. Optional |

Only `wave` is one-shot; it holds its final frame and reports finished, which is how the state machine knows the greeting is over.

**Minimum viable pack: just `Idle/idle_01.png`.** Everything else falls back (see §6).

---

## 5. What you do *not* need to draw

Two things the app derives rather than requiring as art:

**Walking left.** Ship **one** walk cycle, facing right. The app mirrors it horizontally with `scaleEffect(x: -1)` for the other direction. This halves your generation work and — more importantly — guarantees the two directions are the same character. Two separately generated walk cycles will always drift apart.

*(If you genuinely need asymmetric art — a character carrying something on one side — the mirror is the only supported behaviour in v1.)*

**Glasses as a separate state.** The spec listed `glasses_on` and `glasses_off` as animation states, but glasses are orthogonal to what the character is *doing*: modelling them as states would require idle, walk, wave, drink and eye-break variants of each, i.e. twice the clips for one boolean.

Instead, glasses are a **variant suffix** on any clip:

```
Idle/idle_01.png            ← base
Idle/idle_glasses_01.png    ← worn
```

Resolution order is: glasses variant → plain clip → idle. So a pack with no glasses art simply never wears them, and a pack with only `idle_glasses` wears them while standing and not while walking. Nothing breaks either way.

---

## 6. How missing art is handled

The app never crashes over artwork. The fallback chain, in order:

```
requested clip + glasses variant
        ↓ (not present)
requested clip
        ↓ (not present or empty)
idle
        ↓ (not present)
built-in vector placeholder
```

Concretely:

- **A frame file is corrupt or truncated** → that one frame is skipped, the rest of the clip plays. Logged, not fatal.
- **A whole clip folder is missing** → falls back to `idle`. The character stands still during a water reminder instead of drinking.
- **The pack has no `idle`** → the pack is rejected and the bundled `Default` pack loads instead.
- **No packs at all** → a small vector placeholder character draws, so you can see the app is alive.

Settings → Character lists which clips your pack is missing, so you can see it rather than wonder about it.

---

## 7. How the animation system finds your frames

Loading is deliberately split so that the fiddly part is testable without touching a disk:

```
MacCharacterPackLoader          reads the directory                 (AiTwinMac)
        ↓ [String] of filenames
FrameDiscovery.orderedFrames    filters and sorts                   (AiTwinCore — pure, 9 tests)
        ↓ ordered [String]
AnimationClip                   frames + duration + loop flag       (AiTwinCore)
        ↓
FrameSequencer                  advance(by:) → currentFramePath     (AiTwinCore — 11 tests)
        ↓
FrameImageCache                 path → NSImage, decoded once        (AiTwinMac)
        ↓
CharacterView                   draws with .interpolation(.none)    (AiTwinUI)
```

The ordering rule is worth stating because it is the classic bug: **frames sort numerically, not alphabetically.** A lexicographic sort puts `walk_10.png` before `walk_2.png`, and the character moonwalks. There is a test named after exactly this.

Every frame in a pack is decoded once at load and cached, so the animation timer never touches the disk and the first walk is as smooth as the tenth. A full pack is a few hundred kilobytes in memory.

---

## 8. Checklist before you install a pack

- [ ] Every frame is 64 × 64 px
- [ ] Backgrounds are fully transparent (not white, not a checkerboard pattern)
- [ ] The character is at the same position in every frame
- [ ] Filenames are `prefix_NN.png` with the correct prefix per folder
- [ ] Folder names match exactly: `Idle`, `Walking`, `Waving`, `WaterReminder`, `EyeBreak`, `Sleep`
- [ ] At minimum, `Idle/` contains one frame
- [ ] Placed in `~/Library/Application Support/AiTwin/Characters/<Name>/`
- [ ] Settings → Character → *Reload Characters*, then select it
