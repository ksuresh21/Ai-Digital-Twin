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
camera angle or the character's size within its own frame region.

WHOLE FIGURE IN EVERY FRAME:
Every frame is a complete drawing of the entire character, head to feet, at the
same scale, standing on one shared ground line. Never draw a partial figure, a
floating or disembodied head, a cropped bust, an inset close-up, a detail
callout, a turnaround, or a back or side view of the same pose. If a pose would
not fit, draw the whole character slightly smaller — never draw only part of her.

ONE CONNECTED BODY:
Head, neck, shoulders, torso, hips, arms, legs, hair and clothing belong to one
body and move together. The head always sits on the neck and the neck always
sits between the shoulders: it is never repositioned, resized, rotated or
detached on its own, and it never floats free of the torso. When the head turns
or tilts, the neck bends with it and the shoulders answer. When the torso moves,
the head travels with it. The character is never assembled from separate parts
laid over a frozen body.

FIXED MEASUREMENTS:
Neck length, shoulder width, torso length, arm length, leg length and head size
are identical in every frame. Limbs bend only at real joints and never stretch,
shorten, swap sides or detach.

CONTINUOUS MOVEMENT:
Consecutive frames are consecutive moments of ONE continuous action, not
separate illustrations of the same character. Movement is led from the torso
outward and travels in smooth arcs. Weight stays believably balanced over the
feet, and grounded feet stay planted in the same spot unless the pose is
explicitly a jump.

The character occupies the same position and the same height within its own
frame region in every frame, so the frames play as an animation without the
character appearing to jump or drift.
```

---

## Prompt 2 — Idle

**→ `Idle/idle_01.png` … `idle_04.png`** · 2–4 frames · loops

```
[CONSISTENCY BLOCK]

POSE: standing still, breathing quietly. One slow breath, in and out.

Generate exactly 4 frames, each a different moment of that single breath:
  Frame 1: rest — neutral standing pose, chest settled, shoulders low
  Frame 2: inhale — ribcage lifts, shoulders rise a fraction with it, the neck
           lengthens very slightly and the head rides upward with the chest
  Frame 3: top of the breath — chest at its fullest, shoulders at their highest
           point and just beginning to settle, head still riding with the torso
  Frame 4: exhale — chest and shoulders sinking back toward rest, head lowering
           with them

Each frame must be visibly distinct from the others while staying extremely
subtle: the whole rise and fall is about the thickness of the character's own
jawline, not a nod or a shrug.

The lift begins in the ribcage and passes up through the shoulders to the neck
and head, so she reads as one breathing body. The head never bobs on its own and
never changes angle relative to the shoulders. Both feet stay flat and planted in
exactly the same place in all four frames, and the hips do not move.

[STYLE BLOCK]
```

---

## Prompt 3 — Walking (right-facing)

**→ `Walking/walk_01.png` … `walk_04.png`** · 4 frames · loops

```
[CONSISTENCY BLOCK]

POSE: a walk cycle, character facing RIGHT in profile, walking at an easy pace.

Generate exactly 4 frames. All four are different — the two passing frames are
mirror opposites of each other, not the same drawing twice:
  Frame 1: contact — LEFT leg reaching forward with the heel down, RIGHT leg
           extended behind with the heel lifting, RIGHT arm forward and LEFT arm
           back, body at its lowest point
  Frame 2: passing — the RIGHT leg swings through beside the planted LEFT leg,
           knee bent and foot clear of the ground, arms passing close to the
           body, hips and torso at their highest point
  Frame 3: contact — the opposite of frame 1: RIGHT leg forward with the heel
           down, LEFT leg extended behind, LEFT arm forward and RIGHT arm back,
           body at its lowest point again
  Frame 4: passing — the mirror of frame 2: the LEFT leg swings through beside
           the planted RIGHT leg, arms passing close to the body, hips high

WEIGHT: the whole body rises and falls once per step. The rise comes from the
supporting leg straightening, so the hips lift first and the chest, shoulders,
neck and head all ride upward together. The head must never bob on its own or
stay pinned at one height while the body moves beneath it — it is carried by the
spine. Total rise is a small fraction of head height; more reads as skipping.

The forward foot is genuinely planted on the ground line in the contact frames,
carrying the character's weight. Arms swing from the shoulder in opposition to
the legs, elbows softly bent, and hair and loose clothing lag a beat behind the
body's movement. The character stays in the same place within her frame region —
she walks on the spot.

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

POSE: a friendly greeting wave, character facing the viewer.

Generate exactly 4 frames of one continuous wave:
  Frame 1: the lift begins — the right shoulder rises first and the upper arm
           swings out from it, elbow bending, hand arriving at chest height,
           palm starting to turn outward
  Frame 2: arm raised beside the head, elbow bent, palm open and facing forward,
           fingers relaxed rather than splayed; the right shoulder is higher than
           the left and the torso has turned very slightly toward the viewer
  Frame 3: the hand swings outward from the wrist and the forearm follows it,
           the elbow moving a little as it does; a small smile widens
  Frame 4: the hand swings back inward through the same arc, forearm following,
           settling toward the middle

The wave is led by the shoulder, travels down through the elbow, and finishes at
the wrist — the hand never pivots on its own while the arm stays frozen. Keep the
same number of fingers, the same hand size and the same arm length throughout.

The rest of the body responds quietly rather than freezing: the raised shoulder
lifts that side of the chest, the head tilts a few degrees toward the raised arm
with the neck bending naturally, and the weight settles onto the opposite leg.
Both feet stay planted. Expression is warm and welcoming.

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

The character holds a simple pixel-art glass of water in her right hand: a
clear/light-blue tumbler with visible blue water inside, roughly the height of
her own hand. It is the same glass, the same size, in all four frames, and it
stays in the same hand throughout.

Generate exactly 4 frames of one continuous drink:
  Frame 1: glass held low at waist height, elbow nearly straight, head and eyes
           angled down toward it, chin slightly tucked
  Frame 2: the elbow folds and the shoulder lifts, carrying the glass up to chest
           height along a curved path; the head begins to come back up to meet it
  Frame 3: the glass reaches the lips — the forearm is vertical, the wrist has
           rotated to tip it, the chin lifts and the head tips back a little on
           the neck, eyes closed; the upper spine and shoulders lean back very
           slightly to balance the raised arm
  Frame 4: the wrist rotates level again and the elbow unfolds, lowering the
           glass back toward the chest; the head returns to level with a content
           expression, eyes open

The glass, hand, wrist, forearm and elbow travel as one linked chain along a
smooth arc — the glass never jumps to the mouth or floats away from the hand.

The head tips back from the NECK, not by sliding upward: the jaw rotates up while
the base of the neck stays between the shoulders. The rest of the body responds
quietly — the free arm hangs naturally and shifts a little for balance, and both
feet stay planted.

[STYLE BLOCK]
```

---

## Prompt 10 — Eye break

**→ `EyeBreak/eyebreak_01.png` … `eyebreak_04.png`** · 2–4 frames · loops

```
[CONSISTENCY BLOCK]

POSE: resting tired eyes, taking a screen break.

Generate exactly 4 frames of one continuous movement. The hands travel a visible
path — they must never appear or disappear between frames:
  Frame 1: standing with eyes closed and a calm expression, both arms relaxed at
           the sides, chin dropping a fraction as she lets go of the screen
  Frame 2: both elbows bend and the arms swing up along a curved path, hands
           arriving in front of the face at about chin-to-nose height, palms
           beginning to turn inward — the hands are clearly mid-journey, not yet
           at the eyes
  Frame 3: palms rest gently over the closed eyes, fingertips at the forehead,
           elbows out to the sides; the shoulders drop and the chest empties in a
           slow sigh, and the head settles a little lower on the neck with them
  Frame 4: the elbows unfold and the hands travel back down the same arc to
           roughly chest height, eyes still closed, shoulders still low, a
           peaceful expression

Both arms move together and symmetrically, from the shoulder through the elbow to
the wrist. Keep the same hand size and arm length in every frame, and keep the
head at the same angle on the neck throughout — this is a rest, not a nod.

The mood is restful and calm, NOT distressed or in pain. Both feet stay planted.

[STYLE BLOCK]
```

---

## Prompt 11 — Happy mood

**→ optional; use as extra `Idle` frames or a future mood clip**

```
[CONSISTENCY BLOCK]

POSE: happy and pleased — a small, gentle celebration hop.

Generate exactly 2 frames:
  Frame 1: the crouch before the hop — knees softly bent, weight settled down
           through both flat feet, both arms starting to swing out and up from
           the shoulders, chest lifting, bright smile with eyes curved happily
  Frame 2: the top of the little hop — both feet just clear of the ground with
           the toes pointing softly down, legs nearly straight, arms a little
           higher and still swinging outward, body stretched a fraction taller

The whole body leaves the ground together: hips, chest, shoulders, neck and head
all rise by the same amount, and the head stays exactly where it belongs on the
neck. Hair and loose clothing lift slightly behind the movement. Do not raise the
arms while leaving the feet planted, and do not float the upper body away from
the legs.

Expression is delighted but gentle — this is a small companion being pleased for
you, not a victory pose.

[STYLE BLOCK]
```

---

## Prompt 12 — Sleep / tired

**→ `Sleep/sleep_01.png` … `sleep_04.png`** · 2–4 frames · loops · optional

```
[CONSISTENCY BLOCK]

POSE: standing asleep on her feet, drowsy and peaceful.

Generate exactly 4 frames. The BODY is almost perfectly still across all four —
this is deep, slow breathing. Draw the identical sleeping pose each time and
change only the amount of breath and the floating "z" shapes:
  Frame 1: eyes closed, head tilted gently to one side with the neck relaxed so
           the tilt clearly comes from the neck and not from a rotated head;
           shoulders low, arms hanging loose, chest settled
  Frame 2: the same pose at the top of a slow breath — chest and shoulders a
           fraction higher, the tilted head riding up with them — plus one small
           hard-edged pixel-art "z" floating just above and to the right of the
           head
  Frame 3: the same pose part-way through the exhale, chest settling, with the
           first "z" drifted higher and a second, smaller "z" appearing below it
  Frame 4: back to the frame 1 rest position, both "z" shapes gone

The head keeps exactly the same tilt angle relative to the shoulders in all four
frames; it must not drift, straighten or re-tilt. The face keeps the same closed
eyes and the same relaxed mouth throughout — no expression changes. Feet stay
planted and the hips do not move.

The "z" shapes are simple hard-edged pixel forms in the outline colour, never a
rendered font, and they are the only things that visibly travel.

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

Generate exactly 2 frames ONLY:
  Frame 1: settled reading pose, eyes down on the book, chest at rest
  Frame 2: the same drawing with the chest and shoulders lifted by the smallest
           visible amount in one quiet breath, the head riding fractionally
           upward with them rather than moving on its own

CRITICAL: these two frames must be as close to identical as possible. Redraw the
same pose, not a new one. This animation plays while the user is concentrating,
and movement in peripheral vision breaks focus.

Nothing else may change at all: no page turning, no head turn or tilt, no blink
or expression change, no hand or finger movement, no foot tapping, no chair
movement, no hair movement. The book, both hands, the chair and both feet are in
pixel-identical positions in both frames.

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

POSE: a gentle standing stretch after sitting too long, facing the viewer.

Generate exactly 4 frames of one continuous stretch:
  Frame 1: the reach begins — both shoulders roll back and up, the chest opens,
           and both arms swing outward and upward to about shoulder height,
           elbows softly bent, chin lifting a little as the eyes follow the hands
  Frame 2: both arms reach straight overhead, the ribcage lifts away from the
           hips, the whole spine lengthens and the head rides upward with it so
           she stands a touch taller; heels stay down
  Frame 3: still reaching overhead, the torso curves gently to ONE side from the
           waist — the ribs on that side compress and the opposite side opens,
           both arms travel with the curve, and the head follows the line of the
           spine rather than tilting independently
  Frame 4: the spine unwinds back through centre and the arms lower along a wide
           arc to the sides, shoulders settling down and back, relaxed and
           satisfied expression

The movement starts in the shoulders and travels down the spine, and the recovery
passes back through the upright centre — the arms never simply drop from the side
lean. The neck lengthens with the spine and shortens with it, but the head keeps
the same size and the same relationship to the shoulders throughout.

Relaxed and pleasant, not exercise and not strain. Both feet stay flat and
planted in the same place in all four frames.

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

Generate exactly 2 frames of one quiet breath:
  Frame 1: settled and at rest, weight through the seat and both feet, spine
           relaxed, shoulders low
  Frame 2: the same drawing at the top of a small breath — the chest and
           shoulders lift by the smallest visible amount and the head rides up
           with them

The pelvis and the chair do not move at all: the seat, the chair legs, the hips
and both feet are in pixel-identical positions in both frames, and the contact
between her and the chair never changes. Hands stay resting in the lap. The head
keeps the same angle on the neck — no nod, no turn, no expression change.

[STYLE BLOCK]
```

---

## Prompt 16 — Concerned / worried

**→ `Concerned/concerned_01.png` … `concerned_04.png`** · 3–4 frames · loops

```
[CONSISTENCY BLOCK]

POSE: gently concerned, checking on you.

Generate exactly 4 frames of one continuous movement:
  Frame 1: standing with the head tilted slightly to one side — the tilt comes
           from the neck bending, so the near shoulder rises a little and the far
           shoulder drops with it; eyebrows raised in mild concern
  Frame 2: one elbow folds and that hand travels up along a curve to rest near
           the chin, fingers loosely curled; the shoulder on that side lifts to
           support the arm and the head tilts a fraction further into the same
           curve
  Frame 3: a small sigh — the chest empties, both shoulders settle downward, and
           the head lowers with them while keeping exactly the same tilt angle
           relative to the shoulders; the hand stays where it is at the chin
  Frame 4: the chest refills and the shoulders rise back to where they began, the
           hand lowering back down its arc toward the side

The head tilt is produced by the NECK curving, never by rotating a head that sits
straight on level shoulders — the neck, both shoulders and the upper chest all
take part in the tilt. The hand travels a visible path in every frame and never
appears or disappears.

The expression is CARING, not sad, angry or disappointed. She is checking in on
someone she likes, not scolding them. Avoid tears, frowns and crossed arms. Both
feet stay planted and the weight rests slightly on one hip.

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

POSE: a big, delighted celebration jump — bigger than the everyday happy hop.

Generate exactly 4 frames of one jump, with a real crouch before it and a real
landing after it:
  Frame 1: ANTICIPATION — knees bend and the hips drop into a crouch, weight
           down through both flat feet, chest leaning fractionally forward, both
           arms swung down and back ready to throw upward, broad smile
  Frame 2: TAKE-OFF — the legs drive straight and the arms swing up past the
           head; the feet have just left the ground with the toes still pointing
           down, the body stretched and rising, eyes closed happily
  Frame 3: PEAK — the highest point, roughly a head's height above the ground
           line, both arms fully extended overhead, legs relaxed and slightly
           tucked, the whole body at its most stretched
  Frame 4: LANDING — both feet back on the ground line with the knees bending to
           absorb the impact, hips low again, arms coming back down through their
           arc, hair still settling, very pleased expression

The entire figure leaves and returns to the ground as one body: hips, chest,
shoulders, neck and head all rise and fall by the same amount, and the head stays
attached and level on the neck the whole way. Never draw the upper body airborne
while the legs stay on the ground, and never crop the legs out of an airborne
frame — every frame shows the complete character from head to feet.

Optionally add 3-4 small pixel-art confetti or sparkle shapes around her in
frames 2 and 3, in the character's own palette colours. Confetti must not touch
or overlap the character, and must never be mistaken for a separate frame.

[STYLE BLOCK]
```

> Reserved for streak milestones and completed focus sets, so it stays special.
> The everyday goal celebration keeps using `happy`.

---

## Prompt 18 — Peeking from the edge

**→ `Peek/peek_01.png` … `peek_02.png`** · 2 frames · loops

```
[CONSISTENCY BLOCK]

POSE: leaning into view around the LEFT edge of the frame, as though standing
behind a wall or doorway that is just off screen to the left.

Only the right portion of her head, one eye, one shoulder and the hand braced
against that unseen wall edge are visible. The rest of her body continues out of
frame past the left edge — she is a whole person standing behind the edge, not a
head and a hand on their own.

Generate exactly 2 frames:
  Frame 1: leaning around the edge with a curious expression, weight carried on
           the hidden leg behind the wall, the visible hand pressed flat against
           the corner to steady herself
  Frame 2: leaned a little further into view — the neck and shoulder come forward
           together as the hidden body shifts its weight, so slightly more of the
           face and shoulder appear; a small smile

The visible parts must be believably connected to the body hiding off screen: the
head sits on a neck, the neck runs down into the visible shoulder, and the
shoulder continues into the torso beyond the frame edge. The lean comes from the
whole body shifting sideways behind the wall, not from a head sliding across on
its own. Keep the head at the same size and the same height in both frames.

IMPORTANT: unlike every other clip, this one is intentionally cropped by the LEFT
edge of its frame region. Do not centre her and do not show her whole body — this
is the one exception to the whole-figure rule above. She must still be cut off by
a straight vertical edge, never floating as a detached head.

[STYLE BLOCK]
```

> This is the idle-chatter pose. It lets her say something small without walking
> all the way in, which is what keeps occasional chatter from being intrusive.

---

## Prompt 19 — Yawning / winding down

**→ `Yawn/yawn_01.png` … `yawn_04.png`** · 4 frames · **does not loop**

```
[CONSISTENCY BLOCK]

POSE: a sleepy yawn, standing.

Generate exactly 4 frames of one continuous yawn. The hand travels a visible path
and the head stays on the neck throughout:
  Frame 1: eyes drooping toward closed, shoulders sagging, chest beginning to
           fill as the breath starts, one elbow just beginning to bend
  Frame 2: the jaw drops open and the eyes squeeze shut; the chest expands and
           the shoulders rise with the intake, and that hand travels up along a
           curve to about chest height on its way to the mouth — clearly moving,
           not yet arrived
  Frame 3: the peak — the mouth is at its widest, the chin tips upward as the
           neck arches back a little and the shoulders lift with it, and the hand
           now covers the mouth with the elbow raised out to the side
  Frame 4: the yawn releases — the jaw closes, the chin comes back to level, the
           chest and shoulders sink, and the hand lowers back down the same arc
           toward the side; eyes half-open, sleepy and content

The head tips back by the NECK arching, with the base of the neck staying between
the shoulders — never by sliding the head upward or rotating it free of the body.
The jaw opens downward from the skull rather than the whole head changing shape.
The hand belongs to a visible arm attached at the shoulder in every frame.

Cosy and drowsy, not exhausted or unwell. Both feet stay planted.

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
