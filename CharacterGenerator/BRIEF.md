# Brief: AiTwin Character Generator

**A build brief for a coding agent.** Build one self-contained Python tool with
a local browser UI.

**This folder is everything.** You do not need the AiTwin app, its source, or
any other repository. Every rule the tool must obey is written down here or in
`reference/`. If something seems to be missing, it is not hiding in another
repo — say so rather than inventing it.

---

## 1. The mission

Turn **one reference image** into a **finished, installable AiTwin character
pack**, with the user reviewing the art in a browser before it is packed.

```
reference.png  →  [browser UI]  →  Nish.zip
```

The user drags `Nish.zip` onto **AiTwin → Settings → Character** and the
character is installed. If the zip does not install cleanly by drag-and-drop,
the tool has failed no matter how good the art is.

Four stages:

```
reference.png
   ↓  1. GENERATE   one contact sheet per clip, from an image model
   ↓  2. SLICE      split each sheet into individual frames
   ↓  3. REVIEW     the user looks at every clip in the browser  ← the point of the UI
   ↓  4. PACKAGE    correct folders, pack.json, zip, download
Nish.zip
```

---

## 2. What is in this folder

```
CharacterGenerator/
├── BRIEF.md                        this file — the spec
└── reference/
    ├── PROMPTS.md                  the 19 prompts. Stage 1 assembles these.
    ├── import_character.py         WORKING slicing + normalisation code. Port it.
    └── pack.example.json           a real pack.json from a shipped character
```

`reference/import_character.py` is 597 lines of already-debugged code covering
sheet slicing, per-clip height ratios, edge alignment, canvas sizing and
manifest writing. **It is the single most valuable file here.**

**Stages 2 and 4 are a port of that file. Stages 1 and 3 are new code.** Do not
reimplement slicing or normalisation from first principles — the traps in §9 are
all things that file already gets right and that a fresh implementation gets
wrong.

Treat `reference/` as read-only input. Build the tool alongside it.

---

## 3. Inputs and outputs

### Input

- **`reference.png`** — uploaded by the user through the browser. The tool never
  generates it. (`PROMPTS.md` Prompt 1 is a human step: the user iterates on the
  base image until they love it, and every clip derives from it.)
- **Character sheet** — hair, eyes, skin tone, top, bottom, shoes, accessory,
  build, palette. Typed into the browser form. Optional; unfilled fields become
  "artist's choice".
- **API keys from the environment**, never from the UI or a CLI argument:
  `OPENAI_API_KEY`, `GEMINI_API_KEY`. A key typed into a web form ends up in
  browser history and server logs.

### Output

```
Nish.zip
└── Nish/
    ├── pack.json
    ├── reference.png          copied through, so the pack can be regenerated later
    ├── Idle/idle_01.png …
    ├── Walking/walk_01.png …
    └── … one folder per accepted clip
```

Plus a `report.json` saved beside it recording what each clip cost, which
backend drew it, and which checks it passed.

---

## 4. The pack contract (hard requirements)

This table is authoritative — it is copied from the app's own clip catalogue.
**Folder names and file prefixes must match exactly.** A mismatched folder is
not an error the user ever sees: the app silently falls back to `idle`, and the
character just looks broken.

| Clip | Folder | File prefix | Ask for | Accept | Loops |
|---|---|---|---|---|---|
| idle | `Idle/` | `idle` | 4 | 2–4 | yes |
| walk | `Walking/` | `walk` | 4 | 4 | yes |
| wave | `Waving/` | `wave` | 4 | 3–4 | no |
| drink | `WaterReminder/` | `drink` | 4 | 3–4 | yes |
| eyebreak | `EyeBreak/` | `eyebreak` | 4 | 2–4 | yes |
| sleep | `Sleep/` | `sleep` | 4 | 2–4 | yes |
| happy | `HappyMood/` | `happy` | 2 | 2 | no |
| focus | `Focus/` | `focus` | 2 | **2 exactly** | yes |
| stretch | `Stretch/` | `stretch` | 4 | 4 | yes |
| sitting | `Sitting/` | `sitting` | 2 | 2 | yes |
| concerned | `Concerned/` | `concerned` | 4 | 3–4 | yes |
| cheer | `Cheer/` | `cheer` | 4 | 4 | no |
| peek | `Peek/` | `peek` | 2 | 2 | yes |
| yawn | `Yawn/` | `yawn` | 4 | 4 | no |

*Ask for* is what the prompt requests; *accept* is what validation tolerates,
matching the ranges in `PROMPTS.md`. A walk cycle is 4 by definition — contact,
passing, contact, passing — so 3 frames is a misread sheet, not a short clip.

> **`focus` must be exactly 2 near-identical frames.** It plays beside the
> user's work during a Pomodoro session, and movement in peripheral vision
> breaks concentration. Four lively frames is a failed clip even if the art is
> beautiful.

Rules:

- Filenames are `<prefix>_NN.png`, 1-based, zero-padded to two digits, in play
  order: `idle_01.png`, `idle_02.png`, …
- **`Idle/` is the only required folder.** A pack containing just idle is valid;
  every other clip falls back to it. One failed clip must never block a build.
- Every frame is RGBA with a genuinely transparent background.
- Every frame in a pack shares **one canvas size**.

### `pack.json`

See `reference/pack.example.json` for a real one.

```json
{
  "characterHeight": 470,
  "canvasHeight": 744,
  "canvasWidth": 466,
  "baseline": 728,
  "clipTopFractions": { "idle": 0.2567, "walk": 0.2648, "cheer": 0.0134 }
}
```

- `characterHeight` — height in pixels of the **standing** character (the idle
  clip). The app scales the whole pack from this, so it is what keeps her the
  same size as every other character.
- `canvasWidth` / `canvasHeight` — the shared frame size.
- `baseline` — the y coordinate of the floor, where feet rest.
- `clipTopFractions` — per clip, where its artwork starts as a fraction of
  canvas height. The app positions the speech bubble from this, so a wrong value
  puts the bubble through her hands or 50 points above her head. **Compute it
  from the actual art; never guess it.**

`import_character.py` already computes all five. Reuse that code.

---

## 5. The browser UI — the primary interface

This is not a CLI with a web page bolted on. **The browser is how the tool is
used.** The user watches each clip appear, judges the art, regenerates what they
do not like, and only then builds the zip.

### Serving it

- Local server on `127.0.0.1` only. Never bind `0.0.0.0` — this holds an API key.
- **Flask + vanilla JavaScript. No frontend build step**, no npm, no bundler, no
  framework. One `index.html`, one `app.js`, one `style.css`.
- `python3 app.py` starts it and opens the browser.
- No login, no accounts, no database. State lives in one working directory per
  session.

### Screen 1 — Setup

- Drop zone / file picker for `reference.png`, with a preview of the image once
  chosen.
- The character sheet as nine text fields, each showing its example from
  `PROMPTS.md` as placeholder text.
- Pack name (defaults to the reference filename).
- Target character height, default 470.
- Checkboxes for which of the 14 clips to generate — **all ticked by default**.
- A backend indicator showing which API keys were found in the environment.
- **Generate** button. Show the estimated number of image generations before
  starting.

### Screen 2 — Review (the important one)

A grid of clip cards, one per requested clip. Cards fill in as generation
progresses — the user must not wait for all 14 before seeing the first.

Each card shows:

- **Clip name and status**: queued / generating / ready / failed / skipped.
- **The sliced frames**, side by side as thumbnails, numbered in play order.
- **An animated preview** — the frames playing on loop at roughly 8fps. This is
  how a human spots a bad frame instantly; a still grid hides bobbing entirely.
- **A drift view** — the clip's frames stacked on top of each other at ~30%
  opacity. Registration errors that are invisible frame-by-frame are obvious
  here.
- **QA badges** from §8: green for passed checks, amber with a reason for
  failures. Show the reason in plain words: *"frame 3 is 18% shorter than the
  others"*, not an error code.
- **Which backend drew it** (`openai` / `gemini`), so the user can tell when the
  fallback kicked in.
- **Regenerate this clip** button — one clip only, never the whole run.
- **Include / exclude toggle**, on by default. Excluded clips are left out of
  the zip and fall back to idle in the app.
- The raw unsliced sheet, behind a "show original" disclosure. When slicing goes
  wrong, this is the only way to see why.

Progress across the top: `7 of 14 ready · 1 failed · 2 generating`.

### Screen 3 — Build

- **Build pack** button, enabled as soon as at least `idle` is ready.
- Builds the zip and the browser downloads it.
- A summary of what went in, and a plain-language list of what did not and what
  the app will do instead ("no `cheer` — streak celebrations will use `happy`").
- **Regenerate excluded clips** returns to screen 2 rather than starting over.

### Streaming

Server-Sent Events from a `/events` endpoint, or polling every 2 seconds.
Either is fine; SSE is nicer. **Generation must run in a background thread so
the UI stays responsive** — a blocked page during a 14-image run looks like a
crash.

If the browser is closed mid-run, generation continues and the results are still
there when the page is reopened. Keep session state on disk, not in memory.

---

## 6. Stage 1 — Generation

### One sheet per clip, never one frame per call

Ask the model for **all of a clip's frames in a single image, side by side.**

This is the main quality lever, not an optimisation. Frames drawn in one pass
agree with each other on colour, scale and proportion by construction. Four
separate calls are four independent chances to drift — and drift is the entire
difficulty of this problem. It also cuts a run from ~50 calls to 14.

### Prompt assembly

Mechanical assembly of blocks that already exist in `reference/PROMPTS.md`:

```
[CONSISTENCY BLOCK]  +  [POSE for this clip]  +  [STYLE BLOCK]
```

with `reference.png` attached to the request. Parse the blocks out of
`PROMPTS.md` at runtime, or vendor them into a `prompts.py` — **your choice, but
have exactly one source of truth.** Two copies of the style block that drift
apart is a bug that costs someone an afternoon.

Fill `[CHARACTER SHEET]` from the form. Leave blank fields as "artist's choice";
an unspecified detail is one the model re-invents differently every time.

### Backends: OpenAI first, Gemini as fallback

```python
class ImageBackend(Protocol):
    def generate(self, prompt: str, reference: Path) -> Image: ...
```

- **Primary: `openai`** — `gpt-image-1`, via the **image edit** endpoint with
  `reference.png` attached. Attaching the reference is what holds the character
  together across clips; a text-only call will not.
- **Fallback: `gemini`** — `gemini-2.5-flash-image` ("nano banana").

Fall back automatically, per clip, when any of these happen:

1. OpenAI returns a hard error, or rate limits persist past the retry budget.
2. OpenAI refuses the prompt.
3. The clip fails QA (§8) twice on OpenAI.

Record which backend produced each clip and show it on the card. If
`OPENAI_API_KEY` is absent, use Gemini directly and say so in the UI. If neither
key is present, fail on the setup screen with a clear message — never at
generation time, 20 seconds in.

### Cost control

A full run is 14 generations, more with retries, and every one costs money.

- **Cache raw sheets** under `.cache/<sha256 of prompt + reference>.png`.
  Re-slicing, reloading the page or rebuilding the zip must **never** re-generate.
- Regenerate is always per-clip, never all-or-nothing.
- Show a running count of generations used in the UI.
- Exponential backoff on 429 and transient 5xx. Never silently drop a clip on a
  rate limit — mark it failed and say why.

---

## 7. Stages 2 and 4 — Slicing, normalising, packing

**Port `reference/import_character.py`.** What follows is why its rules exist,
so you do not "simplify" them away.

### Slicing

Split each contact sheet on its **empty columns**:

```python
def slice_sheet(image, min_run_fraction=0.02):
    alpha = np.array(image.split()[-1]) > ALPHA_THRESHOLD
    columns = alpha.any(axis=0)
    # …find runs of filled columns…

    minimum = max(8, int(image.width * min_run_fraction))
    runs = [r for r in runs if r[1] - r[0] >= minimum]
    if len(runs) < 2:
        return [image]

    widest = max(r[1] - r[0] for r in runs)
    if any((r[1] - r[0]) < widest * 0.34 for r in runs):
        return [image]          # decoration, not a sheet
    …
```

**The 34% rule is the important line.** Every run in a genuine contact sheet is
a whole character, so runs are roughly equal in width. Detached decoration —
confetti in `cheer`, the floating "z" in `sleep`, a raised hand clear of the
body — produces one narrow run beside wide ones. Without this check the confetti
becomes "frame 5". That bug shipped once in this project.

**Thresholds are relative to image width, never absolute pixel counts.** A
threshold of "15 pixels" means completely different things on a 512px sheet and
a 2048px one.

### Normalising

Four rules. Getting these wrong is what makes a character look small, jump
between poses, or lose the top of her head.

**1. One scale per clip, not per frame.** Scale every frame of a clip by the
same factor. Per-frame scaling silently cancels the animation — a breath that
raises her 2px is normalised away to nothing.

**2. Align by the lowest point.** Her feet define the floor. Composite each
frame so its lowest opaque pixel lands on the shared baseline. **Centre
alignment is the bobbing bug**: it makes her float up and down as her silhouette
changes between frames.

**3. Size the canvas by full reach, not by height.** Because clips align at the
bottom, a jump extends *above* every other clip. A canvas sized to the tallest
clip's height cuts the top off `cheer`.

**4. Scale down, never crop.** If a pose does not fit, shrink it. Cropping loses
her hands.

### Per-clip height ratios

Not every clip should measure the same height as standing idle — a seated pose
is genuinely shorter floor-to-head:

| Clip | Ratio | Why |
|---|---|---|
| `focus`, `sitting` | 0.86 | seated — floor-to-head is shorter |
| `peek` | 0.62 | only head and torso lean around the edge |
| `stretch`, `yawn` | 1.16 | arms overhead |
| `concerned` | 1.14 | more hair volume than standing poses |
| everything else | 1.0 | |

A clip's target height is `characterHeight × ratio`, measured on its content.

> **Do not add a headroom hint for `cheer`.** Its tallest frame is a *standing*
> pose, so a headroom multiplier inflates the whole clip and she comes out
> oversized. Rule 3 already gives the jump its room.

### `peek` is the exception to everything

`peek` is **deliberately cropped by the canvas edge** — she leans in from
off-screen, so half of her is meant to be missing. Tight-cropping and centring
it destroys the effect and she reads as hovering in mid-air.

Pin `peek` to the canvas edge (`import_character.py` uses `top-left`). Exclude
it from the bottom-alignment path entirely, and exclude it from the QA aspect
check in §8.

---

## 8. Automatic quality checks

The user has the final say, but the tool flags what it can measure. Run these
after slicing and show the results on each card:

| Check | Fails when | Why it matters |
|---|---|---|
| Frame count | outside the *accept* range in §4 | Sheet misread, or the model drew a different number of poses |
| Size consistency | a frame's content height differs from the clip median by >12% | One frame drawn at a different scale — the classic drift |
| Transparency | the background is not transparent, or a checkerboard was drawn | Models return checkerboards constantly |
| Non-empty | a frame is blank or nearly blank | |
| Palette distance | mean colour distance from `reference.png` exceeds a threshold | Colour is the most common drift, and it is measurable |
| Aspect sanity | content is wider than tall on a standing clip (**not** `peek`) | Usually means the sheet was never sliced |
| Foot registration | the lowest opaque pixel moves more than 1px between frames | She will bob when animated |

A failed check **flags** the clip; it does not delete it. The user may keep a
clip the tool disliked, and may reject one it passed. Two consecutive QA
failures on OpenAI trigger the Gemini fallback (§6).

---

## 9. Traps — do not repeat these

Every one of these cost real debugging time on this project.

1. **Centre-anchoring frames.** Must be bottom-aligned. §7 rule 2.
2. **Absolute pixel thresholds.** Must be relative to image size. §7.
3. **Splitting on empty columns alone.** Confetti and floating "z"s become
   frames. The 34% rule. §7.
4. **Per-sheet canvas sizing.** Sizing each sheet's canvas from its own
   max width/height gives every clip a different size. The pack needs **one**
   canvas and **one** character height. This was the longest-running bug in the
   project.
5. **Tight-cropping `peek`.** §7.
6. **A headroom hint on `cheer`.** §7.
7. **Bilinear or bicubic resampling.** Use `Image.NEAREST` for pixel art;
   smooth resampling turns a crisp sprite into a smear.
8. **Repeated rescaling.** Resample from the original sheet exactly once. Never
   scale an already-scaled frame — each pass loses detail.
9. **Regenerating on page reload.** Cache by prompt hash, or a refresh costs
   fourteen images.
10. **`shutil.rmtree` on a path derived from user input.** Write into a fresh
    working directory. Require an explicit overwrite flag. **Never delete the
    user's source images or a previous zip without asking.**
11. **Binding the server to `0.0.0.0`.** It holds an API key. `127.0.0.1` only.

---

## 10. CLI (secondary)

The browser is the primary interface, but keep a CLI for automation and testing:

```
python3 generate_character.py REFERENCE --name NAME [options]

  --name NAME          pack name; becomes the folder and the zip
  --out PATH           output zip (default: <NAME>.zip)
  --sheet PATH         character sheet YAML
  --clips a,b,c        only these clips (default: all 14)
  --backend openai|gemini    default: openai, falls back to gemini
  --height N           target character height in px (default: 470)
  --dry-run            assemble and print prompts, call nothing
  --from-sheets DIR    skip generation; slice sheets already on disk
  --force              overwrite an existing output
```

`--from-sheets` matters more than it looks: it makes stages 2 and 4 testable
with **zero API spend**, and it gives the user a path when they have generated
sheets by hand in ChatGPT.

---

## 11. Acceptance criteria

Done when all of these hold:

1. **`--dry-run` works with no API key** and prints 14 fully assembled prompts.
2. **`--from-sheets` produces a valid zip with no network access.** This is the
   main test path.
3. **The three-zoom test.** Build synthetic sheets drawing the same figure at
   wildly different scales — 300×900, 500×700 and 400×1200 canvases with figure
   heights 120, 300 and 160 — and run them through. Every output frame must land
   within **±2px** of the same content height, on **one** shared canvas size.
   (The app's own installer scores 471/472/472 on this test.)
4. **Decoration is not a frame.** A synthetic 4-frame sheet with confetti blobs
   between the figures still yields exactly 4 frames.
5. **Feet do not move.** Across a sliced clip, the lowest opaque pixel is on the
   same row in every frame, ±1px.
6. **`peek` stays edge-anchored** and is not centred.
7. **The zip installs.** Dragged onto AiTwin → Settings → Character it installs
   and switches to the new pack, with no missing-clip warnings for clips that
   were generated.
8. **A failed clip does not fail the build** — the pack ships without it and the
   summary says what the app will do instead.
9. **The UI survives a reload mid-run** without re-generating anything.
10. **A user can regenerate one clip** without touching the other thirteen.

Write these as `pytest` tests using synthetic images. **The test suite must run
with no API key** — stage 1 gets a fake backend returning pre-drawn sheets.

---

## 12. Non-goals

- Do not generate `reference.png`. The user always supplies it.
- Do not build a hosted or multi-user service. This is one local tool for one
  person on their own machine.
- Do not upload, publish or post anything anywhere.
- Do not add accounts, a database, or a frontend build step.
- Glasses clips (`PROMPTS.md` prompts 7 and 8) are **removed from the product**.
  Ignore them; do not generate `*_glasses` folders. `PROMPTS.md` still documents
  them because it has not been trimmed yet.
- `PROMPTS.md` also tells the reader to run `import_character.py` by hand. That
  is the old workflow this tool replaces — take the *prompts* from that file,
  not its instructions.
