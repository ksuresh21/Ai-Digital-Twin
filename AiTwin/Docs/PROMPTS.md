# Pixel-Art Generation Prompts

Copy-paste prompts for generating your own AiTwin character with an image model
(ChatGPT / DALL·E, Nano Banana, Midjourney, Stable Diffusion — anything that
accepts a reference image).

**The hard part is not making one good frame. It is making twelve frames that
are unmistakably the same character.** Everything below is organised around that.

---

## How to use this document

1. Fill in the **Character Sheet** below — once. Every prompt refers back to it.
2. Generate **Prompt 1** (the base reference). Iterate until you love it. Don't move on until you do.
3. Use that image as the **reference image on every subsequent prompt**.
4. **Ask for all of a clip's frames in ONE image**, side by side. Do not crop them.
5. Drop the sheets in a folder and run the importer:
   ```bash
   python3 Scripts/import_character.py <that folder> --name <PackName> --install
   ```

### Generate sheets, not single frames

This is the biggest time-saver available, and it also improves quality.

Asking for four poses in **one** generation means the model draws them in a
single pass, so they agree with each other on colour, scale and proportion by
construction. Four separate generations means four chances to drift — which is
exactly where "the colour shifted and the size changed" comes from.

It also cuts the work from ~24 generations to **6**, one per clip. The importer
slices each sheet automatically, so cropping by hand is not part of the workflow
at all.

---

## Your Character Sheet

Fill these in and paste the filled block into every prompt where it says
`[CHARACTER SHEET]`. Leave anything you don't care about as "artist's choice" —
being *specific* matters far more than being *detailed*, and an unspecified
detail is one the model will re-invent differently on every frame.

```
[HAIR]        e.g. short dark brown, side-parted  ............ ______________________
[EYES]        e.g. large dark eyes, friendly  .............. ______________________
[SKIN TONE]   e.g. warm light brown  ...................... ______________________
[TOP]         e.g. loose teal hoodie  .................... ______________________
[BOTTOM]      e.g. dark navy jeans  ...................... ______________________
[SHOES]       e.g. white sneakers  ....................... ______________________
[ACCESSORY]   e.g. small silver hoop earrings, or "none"  . ______________________
[BUILD]       e.g. slim, average height  .................. ______________________
[PALETTE]     e.g. teal / cream / warm brown / charcoal  .. ______________________
```

> **Do not skip the palette line.** Naming 4–6 specific colours is the single
> most effective consistency lever you have. Models drift on colour faster than
> on shape.

---

## The Style Block

This is appended to every prompt. It never changes.

```
STYLE: 64x64 pixel art sprite, retro 16-bit game style, hard pixel edges,
NO anti-aliasing, NO gradients, limited palette of 8-16 colours, flat cel
shading with a single light source from the upper left.

VIEW: straight-on side-scroller view, full body visible head to toe, character
centred horizontally, feet resting near the bottom of the canvas.

PROPORTIONS: slightly chibi — head roughly 1/4 of total height, small hands
and feet. Consistent proportions across all frames.

BACKGROUND: fully transparent. No background colour, no checkerboard pattern,
no ground shadow, no scenery, no border, no text, no watermark.

OUTPUT: single sprite on transparent background, 64x64 pixels.
```

---

## Prompt 1 — Base / reference image

**Generate this first. Everything else depends on it.**

```
Create a 64x64 pixel art character sprite for a desktop companion app.

CHARACTER:
[CHARACTER SHEET]

POSE: standing straight, facing the viewer at a slight three-quarter angle,
arms relaxed at the sides, neutral friendly expression, eyes open.

[STYLE BLOCK]

This is a reference sheet image. Make the character clear and readable at
small size, with distinctive silhouette and colours that will be easy to
reproduce in later frames.
```

**Save as:** `reference.png` — keep it outside the pack folders. You will attach it to every prompt from here on.

---

## The Consistency Block

Paste this into **every prompt from 2 onwards**, with the reference image attached.

```
CONSISTENCY (most important requirement):
Use the attached reference image as the definitive character design. This must
be recognisably the SAME character: identical hairstyle, identical hair colour,
identical face, identical clothing, identical colour palette, identical
proportions, identical outline style.

Change ONLY the pose described below. Do not redesign, restyle, re-colour or
"improve" the character. Do not add or remove accessories. Do not change the
camera angle or the character's size within the frame.

The character must occupy the same position and the same height on the canvas
as the reference, so the frames can be played as an animation without the
character appearing to jump.
```

---

## Prompt 2 — Idle

**→ `Idle/idle_01.png` … `idle_04.png`** · 2–4 frames · loops

```
[CONSISTENCY BLOCK]

POSE: standing still, idle breathing animation.

Generate 4 separate frames as a numbered sequence:
  Frame 1: neutral standing pose (identical to reference)
  Frame 2: chest and shoulders raised by 1 pixel (inhale)
  Frame 3: same as frame 2 (hold)
  Frame 4: back to neutral (exhale)

The movement must be SUBTLE — 1 to 2 pixels only. Feet stay planted in exactly
the same place in all four frames.

[STYLE BLOCK]
```

---

## Prompt 3 — Walking (right-facing)

**→ `Walking/walk_01.png` … `walk_04.png`** · 4 frames · loops

```
[CONSISTENCY BLOCK]

POSE: walking cycle, character facing RIGHT in profile.

Generate 4 frames of a classic 4-frame walk cycle:
  Frame 1: contact — left leg forward, right leg back, arms opposed
  Frame 2: passing — legs together, body raised 1 pixel
  Frame 3: contact — right leg forward, left leg back, arms opposed
  Frame 4: passing — legs together, body raised 1 pixel

The character's head must stay at a consistent height (a 1 pixel bob on the
passing frames is correct; more looks like hopping). Same position on canvas
in all frames.

[STYLE BLOCK]
```

---

## Prompt 4 — Walking left · Prompt 5 — Walking right

**You do not need to generate these.**

AiTwin ships one walk cycle and mirrors it horizontally in code for the other
direction. Generating both separately guarantees they will drift apart. Generate
Prompt 3 facing right, and the app handles left.

*(Only generate a separate left-facing set if your character is genuinely
asymmetric — carrying a bag on one shoulder, say — and even then, consider
whether a mirrored bag is really a problem.)*

---

## Prompt 6 — Waving

**→ `Waving/wave_01.png` … `wave_04.png`** · 3–4 frames · **does not loop**

```
[CONSISTENCY BLOCK]

POSE: friendly greeting wave, character facing the viewer.

Generate 4 frames:
  Frame 1: right arm beginning to lift, elbow bent, hand at chest height
  Frame 2: right arm raised beside the head, palm open, fingers spread
  Frame 3: same arm position, hand tilted slightly to the right (wave motion)
  Frame 4: same arm position, hand tilted slightly to the left

Expression: warm and welcoming, a small smile. The LEFT arm and both legs stay
exactly as in the reference — only the right arm and the expression change.

[STYLE BLOCK]
```

---

## Prompt 7 — Glasses ON · Prompt 8 — Glasses OFF

**→ `Idle/idle_glasses_01.png` etc.** · optional

"Glasses off" is just your existing idle frames — you don't generate anything
for it. For glasses on, regenerate whichever clips you want a bespectacled
version of, and save them with the `_glasses` suffix.

```
[CONSISTENCY BLOCK]

POSE: identical to the attached reference — same stance, same expression,
same everything.

ONLY CHANGE: the character is now wearing [GLASSES DESCRIPTION — e.g. round
thin-rimmed dark glasses / thick black square frames].

The glasses must sit naturally over the eyes without obscuring them, drawn in
the same pixel-art style with hard edges. Nothing else about the character
changes.

[STYLE BLOCK]
```

---

## Prompt 9 — Drinking water

**→ `WaterReminder/drink_01.png` … `drink_04.png`** · 3–4 frames · loops

```
[CONSISTENCY BLOCK]

POSE: drinking from a glass of water.

The character now holds a simple pixel-art glass of water in the right hand:
a clear/light-blue tumbler with visible blue water inside, about 8 pixels tall.

Generate 4 frames:
  Frame 1: glass held low, at waist height, character looking at it
  Frame 2: glass raised to chest height
  Frame 3: glass at the lips, head tilted back slightly, eyes closed, drinking
  Frame 4: glass lowered back to chest height, content expression

Only the right arm, the glass and the head tilt change between frames.

[STYLE BLOCK]
```

---

## Prompt 10 — Eye break

**→ `EyeBreak/eyebreak_01.png` … `eyebreak_04.png`** · 2–4 frames · loops

```
[CONSISTENCY BLOCK]

POSE: resting tired eyes, taking a screen break.

Generate 4 frames:
  Frame 1: standing, eyes closed, calm expression
  Frame 2: both hands raised, palms gently covering the eyes
  Frame 3: same as frame 2, shoulders relaxed 1 pixel lower (a sigh)
  Frame 4: hands lowered, eyes still closed, peaceful expression

The mood is restful and calm, NOT distressed or in pain.

[STYLE BLOCK]
```

---

## Prompt 11 — Happy mood

**→ optional; use as extra `Idle` frames or a future mood clip**

```
[CONSISTENCY BLOCK]

POSE: happy and pleased — a small celebration.

Generate 2 frames:
  Frame 1: standing with a bright smile, eyes curved happily, both arms
           slightly raised at the sides
  Frame 2: same pose, hopped 2 pixels off the ground, arms a little higher

Expression is delighted but gentle — this is a small companion being pleased
for you, not a victory pose.

[STYLE BLOCK]
```

---

## Prompt 12 — Sleep / tired

**→ `Sleep/sleep_01.png` … `sleep_04.png`** · 2–4 frames · loops · optional

```
[CONSISTENCY BLOCK]

POSE: sleepy and resting.

Generate 4 frames:
  Frame 1: standing, eyes closed, head tilted slightly to one side, drowsy
  Frame 2: same pose with a small pixel-art "z" floating up and to the right
           of the head
  Frame 3: same pose, the "z" higher and a second smaller "z" appearing
  Frame 4: back to frame 1, both "z"s faded away

The "z" characters must be simple hard-edged pixel shapes in the outline
colour, not a rendered font.

[STYLE BLOCK]
```

---

## Prompt 13 — Focus / reading in a chair

**→ `Focus/focus_01.png` … `focus_02.png`** · 2 frames · loops · for Pomodoro sessions

```
[CONSISTENCY BLOCK]

POSE: sitting sideways in a simple wooden chair, reading a book held in both
hands, absorbed and calm. Shown in profile facing RIGHT, so the chair and the
character read clearly as a silhouette.

The chair is a plain pixel-art wooden chair drawn in the same style — no
cushions, no detail beyond a seat, a back and legs.

Generate 2 frames ONLY:
  Frame 1: settled reading pose, eyes down on the book
  Frame 2: identical, with the chest raised by exactly 1 pixel (a slow breath)

CRITICAL: these two frames must be almost identical. This animation plays while
the user is concentrating, and movement in peripheral vision breaks focus. No
page turning, no head movement, no foot tapping.

[STYLE BLOCK]
```

> **Why only two frames:** the focus clip is the one animation deliberately kept
> near-static. See the design note in [ROADMAP.md](ROADMAP.md) — a lively
> character beside your work is exactly what a focus session must not have.

---

## Prompt 14 — Stretching

**→ `Stretch/stretch_01.png` … `stretch_04.png`** · 4 frames · loops · for posture reminders

```
[CONSISTENCY BLOCK]

POSE: a gentle standing stretch, facing the viewer.

Generate 4 frames:
  Frame 1: standing neutral, beginning to raise both arms
  Frame 2: both arms stretched straight overhead, fingers spread, body
           lengthened, standing 1 pixel taller
  Frame 3: arms overhead and leaning slightly to one side, a side stretch
  Frame 4: arms lowering back down, relaxed and satisfied expression

The mood is a comfortable stretch after sitting too long — relaxed and pleasant,
not exercise, not strain. Feet stay planted in the same place throughout.

[STYLE BLOCK]
```

---

## Prompt 15 — Sitting idle (optional)

**→ `Sitting/sitting_01.png` … `sitting_02.png`** · 2 frames · loops

```
[CONSISTENCY BLOCK]

POSE: sitting on the edge of a simple pixel-art wooden chair, relaxed, hands
resting in the lap, looking out toward the viewer with a calm expression.
Profile or three-quarter view, facing RIGHT.

Generate 2 frames with only a 1-pixel breathing difference between them.

[STYLE BLOCK]
```

---

## Prompt 16 — Concerned / worried

**→ `Concerned/concerned_01.png` … `concerned_04.png`** · 3–4 frames · loops

```
[CONSISTENCY BLOCK]

POSE: gently concerned, checking on you.

Generate 4 frames:
  Frame 1: standing, head tilted slightly, eyebrows raised in mild concern
  Frame 2: one hand raised near the chin, thinking and a little worried
  Frame 3: same, shoulders lowered 1 pixel (a small sigh)
  Frame 4: back to frame 1

The expression is CARING, not sad, angry or disappointed. She is checking in on
someone she likes, not scolding them. Avoid tears, frowns and crossed arms.

[STYLE BLOCK]
```

> Used after a long stretch with no break, or several skipped reminders in a row.
> The tone matters: this is the one mood that could easily read as nagging, and
> a companion that makes you feel guilty gets quit.

---

## Prompt 17 — Proud / cheering

**→ `Cheer/cheer_01.png` … `cheer_04.png`** · 4 frames · **does not loop**

```
[CONSISTENCY BLOCK]

POSE: a big, delighted celebration — bigger than a normal happy pose.

Generate 4 frames:
  Frame 1: standing, arms starting to rise, broad smile
  Frame 2: both arms thrown up above the head, hopped 3 pixels off the ground,
           eyes closed happily
  Frame 3: at the peak of the jump, 5 pixels off the ground, arms fully up
  Frame 4: landing, arms coming down, very pleased expression

Optionally add 3-4 small pixel-art confetti or sparkle shapes around her in
frames 2 and 3, in the character's own palette colours.

[STYLE BLOCK]
```

> Reserved for streak milestones and completed focus sets, so it stays special.
> The everyday goal celebration keeps using `happy`.

---

## Prompt 18 — Peeking from the edge

**→ `Peek/peek_01.png` … `peek_02.png`** · 2 frames · loops

```
[CONSISTENCY BLOCK]

POSE: peeking out from behind the LEFT edge of the frame, as if hiding just off
screen and leaning into view.

ONLY the right half of her head, one eye, one shoulder and one hand gripping the
edge should be visible. The rest of the character is cut off by the left edge of
the canvas — she is deliberately half-hidden.

Generate 2 frames:
  Frame 1: peeking, curious expression
  Frame 2: leaned in 2 pixels further, a small smile

IMPORTANT: unlike every other clip, this one is intentionally cropped by the
canvas edge. Do not centre her. Do not show her whole body.

[STYLE BLOCK]
```

> This is the idle-chatter pose. It lets her say something small without walking
> all the way in, which is what keeps occasional chatter from being intrusive.

---

## Prompt 19 — Yawning / winding down

**→ `Yawn/yawn_01.png` … `yawn_04.png`** · 4 frames · **does not loop**

```
[CONSISTENCY BLOCK]

POSE: a sleepy yawn.

Generate 4 frames:
  Frame 1: standing, eyes beginning to close, slightly drooped posture
  Frame 2: mid-yawn — mouth open, one hand raised toward the mouth, eyes closed
  Frame 3: the peak of the yawn, head tilted back slightly, both eyes shut
  Frame 4: yawn finished, hand lowered, sleepy contented expression, eyes
           half-open

Cosy and drowsy, not exhausted or unwell.

[STYLE BLOCK]
```

> Appears late at night and after very long sessions, as a gentle nudge to stop.

---

## Which prompts you actually need

| Prompt | Clip | Needed for |
|---|---|---|
| 1 | `reference.png` | **Everything.** Generate this first |
| 2 | `idle` | **Required.** A pack with only this still works |
| 3 | `walk` | Reminders walking in |
| 6 | `wave` | Greetings |
| 9 | `drink` | Water reminders |
| 10 | `eyebreak` | Eye-break reminders |
| 11 | `happy` | Goal celebrations, streak milestones |
| 12 | `sleep` | Late-night and idle moods |
| 7 | `*_glasses` | Optional. Glasses variant of any clip |
| **13** | `focus` | **Focus sessions (Pomodoro)** |
| **14** | `stretch` | **Posture reminders** |
| 15 | `sitting` | Optional idle variety |
| **16** | `concerned` | Long sessions, repeated skips |
| **17** | `cheer` | Streak milestones, focus sets |
| **18** | `peek` | **Idle chatter** — half-hidden at the edge |
| **19** | `yawn` | Late nights, winding down |

Prompts 4, 5 and 8 need nothing generated — walking left is mirrored in code,
and "glasses off" is simply your normal frames.

**In Phase 2 this whole page becomes automatic:** one reference image in, every
clip out. See [ROADMAP.md](ROADMAP.md). Until then, generating one sheet per clip
and running the importer is the fast path.

---

## Getting consistency out of the model

**Always attach the reference image.** Text alone will not hold a character
design across twelve generations. If your tool supports it, attach both the
original reference *and* the most recently accepted frame.

**Generate one clip per conversation, not one frame per conversation.** Models
hold context within a session; asking for all four walk frames in one request
gets you four frames that agree with each other. Starting fresh for each frame
is the fastest route to four different characters.

**Reject drift immediately.** If frame 3 has slightly different hair, regenerate
it rather than accepting it — a drifted frame becomes the reference for the next
one, and the error compounds.

**Say what must NOT change**, not just what must. "Do not redesign the
character" measurably outperforms "keep the character the same".

**Fix registration by hand.** Models will not reliably place the character at
identical canvas coordinates. Open the frames in any pixel editor (Aseprite,
Piskel — free and browser-based, Pixelorama), stack them as layers, and nudge
until the feet line up. This is five minutes of work and it is the difference
between walking and bobbing.

**Post-process to a true 64×64.** Most models output 512×512 or 1024×1024 with
soft edges regardless of what you ask. Downscale with **nearest-neighbour**
(never bilinear/bicubic), then index the palette down to 8–16 colours. In
Aseprite: *Sprite → Resize (Nearest Neighbor)*, then *Sprite → Color Mode →
Indexed*.

---

## Where files go

```
~/Library/Application Support/AiTwin/Characters/<YourCharacterName>/
├── Idle/            idle_01.png …
├── Walking/         walk_01.png …
├── Waving/          wave_01.png …
├── WaterReminder/   drink_01.png …
├── EyeBreak/        eyebreak_01.png …
└── Sleep/           sleep_01.png …
```

Then: **Settings → Character → Reload Characters**, and pick yours from the menu.

Start with just `Idle/idle_01.png` if you want to check your pipeline — one
frame is a valid pack, and everything else falls back to it.
