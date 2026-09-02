"""Build self-contained human and pet prompts for the manual image workflow.

The shipped human pose language continues to come from ``reference/PROMPTS.md``.
Pet poses live here because they are a product extension and intentionally do
not alter the read-only reference material supplied with the original brief.
"""

import re
from pathlib import Path
from typing import Mapping

from .clips import CLIPS


ROOT = Path(__file__).resolve().parents[1]
PROMPTS_PATH = ROOT / "reference" / "PROMPTS.md"
HUMAN_FIELDS = (
    ("hair", "HAIR", "short dark brown, side-parted"),
    ("eyes", "EYES", "large dark eyes, friendly"),
    ("skin_tone", "SKIN TONE", "warm light brown"),
    ("top", "TOP", "loose teal hoodie"),
    ("bottom", "BOTTOM", "dark navy jeans"),
    ("shoes", "SHOES", "white sneakers"),
    ("accessory", "ACCESSORY", 'small silver hoop earrings, or "none"'),
    ("build", "BUILD", "slim, average height"),
    ("palette", "PALETTE", "teal / cream / warm brown / charcoal"),
)

PET_FIELDS = (
    ("species", "SPECIES", "cat, dog, rabbit, bird, or other pet"),
    ("breed", "BREED / TYPE", "domestic shorthair, corgi, lop rabbit, etc."),
    ("coat", "COAT / FEATHERS", "colour, length, and texture from the photo"),
    ("eyes", "EYES", "colour, shape, and friendly expression from the photo"),
    ("markings", "DISTINCTIVE MARKINGS", "face blaze, patches, ear tips, tail rings"),
    ("accessory", "ACCESSORY", 'collar, bandana, tag, or "none"'),
    ("build", "BUILD", "small and slim, sturdy, fluffy, long-bodied, etc."),
    ("palette", "PALETTE", "4–6 defining coat/accessory colours"),
)

PET_CONSISTENCY = """CONSISTENCY — MOST IMPORTANT REQUIREMENT:
Attach reference.png to this request. Use it as the definitive character design.
This must be recognisably the SAME character: identical species or character
type, identical face and eye shape, identical coat, fur, feathers, skin or
clothing, identical markings, identical ears, tail, body proportions, outline
style, palette, and accessory.

Change ONLY the pose described below. Do not redesign, recolour, groom, dress,
restyle, or change the anatomy. Do not add or remove markings or accessories.
Keep the same camera, sprite scale, light direction, and level of pixel detail.

ANATOMY COMES FROM THE REFERENCE:
Copy exactly the body plan shown in the attached reference and never change it.
If the reference stands upright on two legs and has hands, keep the upright
posture and the hands, and let it gesture as that character naturally would. If
the reference is a four-legged animal, keep it on four legs and never give it
human hands, fingers, upright posture or human gestures. If it has a tail, ears,
wings, a snout or a beak, those stay and take part in the movement. Never make
the character more human or less human than the reference already is.

WHOLE FIGURE IN EVERY FRAME:
Every frame is a complete drawing of the entire character at the same scale,
standing on one shared ground line. Never draw a partial figure, a floating or
disembodied head, a cropped body, an inset close-up, a detail callout, a
turnaround, or a back or side view of the same pose. If a pose would not fit,
draw the whole character slightly smaller — never draw only part of it.

ONE CONNECTED BODY:
Head, neck, shoulders, spine, hips, limbs, fur or clothing, ears and tail belong
to one body and move together. The head always sits on the neck and the neck
always joins the shoulders: it is never repositioned, resized, rotated or
detached on its own, and it never floats free of the body. When the head turns or
tilts, the neck bends with it and the shoulders answer. The character is never
assembled from separate parts laid over a frozen body.

FIXED MEASUREMENTS:
Neck length, shoulder width, body length, limb length, ear size, tail length and
head size are identical in every frame. Limbs bend only at real joints and never
stretch, shorten, swap sides or detach.

CONTINUOUS MOVEMENT:
Consecutive frames are consecutive moments of ONE continuous action, not separate
illustrations. Movement is led from the body outward and travels in smooth arcs,
with the spine and tail helping to balance it. Weight stays believably carried by
whichever limbs are on the ground, and grounded paws or feet stay planted in the
same spot unless the pose is explicitly a jump or hop.

Across every panel, keep the character at the same visual scale and keep the
grounded contact point on one shared baseline so the animation does not jump."""

# These remain species-neutral on purpose. The model is asked to use natural
# anatomy from the attached pet reference instead of inventing human limbs.
PET_POSES = {
    "idle": """POSE: standing or sitting at rest, breathing quietly. One slow breath, in and out.

Generate exactly 4 frames, each a different moment of that single breath:
  Frame 1: rest — settled neutral pose, looking calmly toward the viewer
  Frame 2: inhale — the ribcage expands and the shoulders or withers rise a
           fraction, the neck lengthens very slightly and the head rides upward
           with the body
  Frame 3: top of the breath — chest at its fullest and just beginning to settle,
           head still carried by the body
  Frame 4: exhale — the chest sinks back toward rest and the head lowers with it

Each frame must be visibly distinct while staying extremely subtle: the whole
rise and fall is about the thickness of the character's own muzzle or jaw.

The lift begins in the ribcage and passes up through the shoulders to the neck
and head, so it reads as one breathing body. The head never bobs on its own and
never changes angle relative to the shoulders. Every grounded paw, foot or
contact point stays in exactly the same place, and the hips do not move. Ears and
tail stay still apart from the faintest settle.""",
    "walk": """POSE: a natural walk cycle, character facing RIGHT in profile, moving at an easy pace.

Use the body plan from the reference: a four-legged animal walks on four legs
with its own natural gait, and an upright character walks on two. Do not change
which it is.

Generate exactly 4 frames. All four are different — the two passing frames are
mirror opposites of each other, not the same drawing twice:
  Frame 1: contact — the leading limb reaches forward and takes the ground, the
           trailing limb is extended behind, body at its lowest point
  Frame 2: passing — the trailing limb swings through beside the supporting one,
           clear of the ground, hips and body at their highest point
  Frame 3: contact — the opposite of frame 1, with the other side leading
  Frame 4: passing — the mirror of frame 2, with the other limb swinging through

WEIGHT: the body rises and falls once per step, driven by the supporting limb
straightening. The lift starts at the hips and travels forward along the spine so
the shoulders, neck and head all rise together. The head must never bob on its
own, and must never stay pinned at one height while the body moves beneath it —
it is carried by the spine. Total rise is a small fraction of head height.

The spine flexes gently with the gait and the tail swings to balance it. Ears
carry a beat behind the head. Grounded limbs genuinely bear weight on the ground
line. The character stays in the same place within its frame region — it walks on
the spot.""",
    "wave": """POSE: a friendly greeting, using whatever limb the reference actually has.

Generate exactly 4 frames of one continuous greeting:
  Frame 1: the lift begins — the shoulder rises first and the limb swings up out
           of it, weight shifting onto the remaining grounded limbs to free it
  Frame 2: the limb is raised beside the face, held comfortably, with the body
           leaning very slightly to stay balanced over its supports
  Frame 3: the raised limb swings outward along a small arc, the joint above it
           moving as it does, ears perking and the expression brightening
  Frame 4: the limb swings back inward through the same arc, settling toward the
           middle

The greeting is led from the shoulder, travels through the elbow or wing joint,
and finishes at the paw, hand or wingtip — the tip never pivots on its own while
the limb stays frozen.

If the reference is a four-legged animal, this is a natural raised paw with no
fingers, no wrist articulation and no human wave; the animal stays balanced on
its other three legs and keeps its natural posture. If the reference is an
upright character with hands, it waves as that character naturally would. If the
species has no suitable limb, greet instead with a perked-ear head tilt led by
the neck. Never add anatomy the reference does not have.

The rest of the body responds quietly rather than freezing: the raised side of
the chest lifts, the head tilts a few degrees toward the raised limb with the
neck bending naturally, and the tail shifts for balance.""",
    "drink": """POSE: drinking water.

If the reference is a four-legged animal, it drinks from a simple pixel-art bowl
on the ground. If the reference is an upright character with hands, it drinks
from a simple pixel-art cup or glass held in one hand. Use whichever matches the
reference, and keep the same vessel, at the same size, in the same place, in all
four frames.

Generate exactly 4 frames of one continuous drink:
  Frame 1: settled in front of the water, head and eyes angled down toward it,
           weight balanced over the supporting limbs
  Frame 2: the neck lowers or the arm lifts, carrying head and water toward each
           other along a curved path; the shoulders and upper spine follow
  Frame 3: drinking — muzzle, beak or lips meet the water, with a small
           species-appropriate tongue or beak movement; the neck is at full
           extension and the back curves to match
  Frame 4: the head lifts back to level along the same arc, content and
           refreshed, the spine unwinding with it

The head, neck and spine move as one curve — the head never travels toward the
water on its own while the body stays upright. The vessel never floats, never
changes size and never moves between frames unless it is being held.""",
    "eyebreak": """POSE: calmly resting tired eyes.

Generate exactly 4 frames of one continuous settling:
  Frame 1: settled pose with the eyes closing and the head lowering a fraction on
           the neck as it lets go of the day
  Frame 2: if the reference can comfortably reach its face, one paw, wing or hand
           travels up along a visible curved path toward the eyes, clearly
           mid-journey; if it cannot, the head instead tucks a little further
           down and toward the shoulder
  Frame 3: the deepest point — the limb rests against the face, or the head is
           fully tucked; the shoulders drop and the chest empties in a slow sigh,
           the head settling lower with them
  Frame 4: the limb travels back down the same arc, or the head lifts back out of
           the tuck, eyes still closed and shoulders still low

Limbs never appear or disappear between frames — whatever moves must travel a
visible path in every frame. The head keeps the same angle relative to the
shoulders throughout: this is a rest, not a nod.

The mood is restful, not distressed. Grounded paws or feet stay planted.""",
    "sleep": """POSE: asleep in a natural resting position for this character — curled, lying,
perched, or slumped comfortably as the reference's body plan suggests.

Generate exactly 4 frames. The BODY is almost perfectly still across all four.
Draw the identical sleeping pose each time and change only the amount of breath
and the floating "z" shapes:
  Frame 1: eyes closed, body settled, the neck relaxed so any head tilt clearly
           comes from the neck curving rather than a rotated head
  Frame 2: the same pose at the top of a slow breath — the ribcage a fraction
           fuller and the head riding up with it — plus one small hard-edged
           pixel-art "z" floating just above and to one side of the head
  Frame 3: the same pose part-way through the exhale, with the first "z" drifted
           higher and a second, smaller "z" appearing below it
  Frame 4: back to the frame 1 rest position, both "z" shapes gone

The head keeps exactly the same angle relative to the body in all four frames. The
face keeps the same closed eyes and relaxed mouth throughout — no expression
changes. Paws, tail and ears stay exactly where they are.

The "z" shapes are simple hard-edged pixel forms in the outline colour, never a
rendered font, and they are the only things that visibly travel.""",
    "happy": """POSE: happy to see you — a small, gentle celebration.

Generate exactly 2 frames:
  Frame 1: the gather before the lift — the limbs bend and the weight settles
           down through them, the chest lifting, with a bright expression and a
           species-appropriate happy signal such as perked ears, a raised tail or
           half-lifted wings
  Frame 2: the top of a small hop — the grounded limbs are just clear of the
           ground, the body stretched a fraction taller, ears and tail carried
           upward with it

The whole body leaves the ground together: hips, chest, shoulders, neck and head
all rise by the same amount, and the head stays attached and level on the neck.
Fur, feathers and ears lift slightly behind the movement. Do not lift the front
of the body while the back stays planted.

Keep the celebration gentle and keep the reference's anatomy exactly.""",
    "focus": """POSE: resting quietly in a calm, attentive position beside a small closed book.

Generate exactly 2 frames ONLY:
  Frame 1: settled quiet pose, eyes relaxed, body completely still
  Frame 2: the same drawing with the ribcage lifted by the smallest visible
           amount in one quiet breath, the head riding fractionally upward with
           it rather than moving on its own

CRITICAL: these two frames must be as close to identical as possible. Redraw the
same pose, not a new one. This animation plays while someone is concentrating,
and movement in peripheral vision breaks focus.

Nothing else may change at all: no ear flick, no tail movement, no blink or
expression change, no paw or head movement, no page turning. The book, every paw
or foot, the tail and the ears are in pixel-identical positions in both frames.""",
    "stretch": """POSE: a comfortable natural full-body stretch after resting too long.

Generate exactly 4 frames of one continuous stretch:
  Frame 1: the stretch begins — the shoulders roll and the chest opens as the
           weight shifts back over the hind limbs or feet
  Frame 2: the front of the body extends and the spine lengthens; a four-legged
           character pushes its forelimbs forward and dips its chest toward the
           ground with the hips staying high, while an upright character reaches
           upward and lengthens its spine
  Frame 3: the deepest point of the stretch — the spine at full comfortable
           extension, the tail extended in line with it, the head following the
           line of the spine rather than tilting independently
  Frame 4: the spine unwinds back through the neutral standing position, limbs
           returning under the body, relaxed and satisfied

The movement starts at the shoulders and travels the length of the spine, and the
recovery passes back through neutral. The neck lengthens and shortens with the
spine, but the head keeps the same size and the same relationship to the
shoulders throughout.

Relaxed and pleasant, never strain. Grounded paws or feet stay in the same place
throughout.""",
    "sitting": """POSE: a natural relaxed sitting or perched pose, looking calmly toward the viewer.

Generate exactly 2 frames of one quiet breath:
  Frame 1: settled and at rest, weight carried through the seated contact point,
           spine relaxed
  Frame 2: the same drawing at the top of a small breath — the ribcage and
           shoulders lift by the smallest visible amount and the head rides up
           with them

The seated contact point does not move at all: the hips, the grounded paws or
feet, and the surface beneath them are in pixel-identical positions in both
frames. The tail, wings, ears and head keep exactly the same position and angle —
no ear flick, no tail sway, no head turn, no expression change.""",
    "concerned": """POSE: gently concerned, checking on you.

Generate exactly 4 frames of one continuous movement:
  Frame 1: attentive pose with the head tilted slightly to one side — the tilt
           comes from the neck curving, so the near shoulder rises a little and
           the far shoulder drops with it; ears turn forward
  Frame 2: the head tilts a fraction further into the same curve as the character
           leans in, the weight shifting forward over the front limbs, ears and
           eyebrows following the movement
  Frame 3: a small sigh — the chest empties, the shoulders settle downward, and
           the head lowers with them while keeping exactly the same tilt angle
           relative to the shoulders
  Frame 4: the chest refills, the shoulders rise back to where they began and the
           lean returns to neutral

The head tilt is produced by the NECK curving, never by rotating a head that sits
straight on level shoulders. Ears and tail take part in the movement rather than
staying frozen.

The expression is caring and curious, never angry, frightened or injured.""",
    "cheer": """POSE: a big delighted celebration jump, with a real gather before it and a real
landing after it.

Generate exactly 4 frames:
  Frame 1: ANTICIPATION — the limbs bend and the body sinks into a crouch, weight
           down through every grounded limb, ready to spring, with an excited
           expression
  Frame 2: TAKE-OFF — the limbs drive straight and the body rises; the grounded
           limbs have just left the ground, the body stretched upward, ears and
           tail lifting with it
  Frame 3: PEAK — the highest point, roughly a head's height above the ground
           line, the body at its most stretched, limbs relaxed and slightly
           tucked, tail carried high
  Frame 4: LANDING — every grounded limb is back on the ground line with the
           joints bending to absorb the impact, the body low again, fur and ears
           still settling, visibly pleased

The entire figure leaves and returns to the ground as one body: hips, chest,
shoulders, neck and head all rise and fall by the same amount, and the head stays
attached and level on the neck the whole way. Never draw the front of the body
airborne while the back stays down, and never crop the limbs out of an airborne
frame — every frame shows the complete character.

Optional: 3-4 tiny pixel confetti shapes in frames 2 and 3, in the character's own
palette colours. Confetti must not touch or overlap the character, and must never
be mistaken for a separate frame. Do not alter anatomy.""",
    "peek": """POSE: leaning into view around the LEFT edge of the frame, as though standing
behind a wall or doorway just off screen to the left.

Only the right portion of the head, one eye, one shoulder and one paw, hand or
wing braced against that unseen wall edge are visible. The rest of the body
continues out of frame past the left edge — this is a whole animal or character
standing behind the edge, not a head on its own.

Generate exactly 2 frames:
  Frame 1: leaning around the edge with a curious friendly expression, weight
           carried on the hidden limbs behind the wall, ears forward
  Frame 2: leaned a little further into view — the neck and shoulder come forward
           together as the hidden body shifts its weight, so slightly more of the
           face and shoulder appear

The visible parts must be believably connected to the body hiding off screen: the
head sits on a neck, the neck runs into the visible shoulder, and the shoulder
continues into the body beyond the frame edge. The lean comes from the whole body
shifting sideways behind the wall, not from a head sliding across on its own.
Keep the head at the same size and height in both frames.

This is the one clip that is intentionally cropped by the LEFT edge of its frame
region. Do not centre the character and do not show the full body — but never
draw a detached floating head.""",
    "yawn": """POSE: a natural sleepy yawn.

Generate exactly 4 frames of one continuous yawn:
  Frame 1: the eyes droop toward closed and the posture softens as the breath
           starts, the chest beginning to fill
  Frame 2: the jaw or beak begins to open and the eyes squeeze shut; the chest
           expands and the shoulders rise with the intake
  Frame 3: the peak — the mouth at its widest, the chin or beak tipping upward as
           the neck arches back and the shoulders lift with it; the tongue may
           show if natural for the species
  Frame 4: the yawn releases — the jaw closes, the head comes back to level, and
           the chest and shoulders sink; sleepy and content

The head tips back by the NECK arching, with the base of the neck staying at the
shoulders — never by sliding the head upward or rotating it free of the body. The
jaw opens downward from the skull rather than the whole head changing shape. Ears
soften back during the yawn and return afterwards.

Keep it cosy and anatomically natural, not distressed or unwell. Grounded paws or
feet stay planted.""",
}

SHEET_FIELDS = HUMAN_FIELDS  # compatibility for existing CLI callers/tests


def _section_fence(markdown: str, heading_pattern: str) -> str:
    match = re.search(
        rf"^## {heading_pattern}[^\n]*\n.*?^```[^\n]*\n(.*?)^```",
        markdown,
        flags=re.MULTILINE | re.DOTALL,
    )
    if not match:
        raise ValueError(f"PROMPTS.md is missing a fenced block after: {heading_pattern}")
    return match.group(1).strip()


def load_blocks(path: Path = PROMPTS_PATH) -> tuple[str, str, dict[int, str]]:
    markdown = path.read_text(encoding="utf-8")
    style = _section_fence(markdown, r"The Style Block")
    consistency = _section_fence(markdown, r"The Consistency Block")
    poses = {
        clip.prompt_number: _section_fence(markdown, rf"Prompt {clip.prompt_number}\b")
        for clip in CLIPS
    }
    return consistency, style, poses


def fields_for(subject_type: str) -> tuple[tuple[str, str, str], ...]:
    if subject_type not in {"human", "pet"}:
        raise ValueError("Character type must be human or pet")
    return HUMAN_FIELDS if subject_type == "human" else PET_FIELDS


def format_character_sheet(
    values: Mapping[str, str] | None = None, subject_type: str = "human"
) -> str:
    values = values or {}
    rows = []
    for key, label, _ in fields_for(subject_type):
        value = str(values.get(key, "")).strip() or "artist's choice"
        rows.append(f"{label}: {value}")
    return "\n".join(rows)


def _contact_sheet_style(style: str, frame_count: int) -> str:
    style = re.sub(
        r"\n\nOUTPUT: single sprite on transparent background, 64x64 pixels\.\s*$",
        "",
        style,
    )
    words = {2: "TWO", 3: "THREE", 4: "FOUR"}.get(frame_count, str(frame_count))
    return style + (
        "\n\nOUTPUT FORMAT — CONTACT SHEET:\n"
        f"Return exactly ONE landscape image containing exactly {frame_count} ({words}) "
        f"complete characters in one horizontal row, ordered left to right. Count them "
        f"before you finish: there must be {words} figures, no more and no fewer. Use an "
        "available landscape aspect ratio such as 16:9 when the interface requires a preset. "
        f"Divide the canvas into {frame_count} equal-width frame regions and place one whole "
        "character in each. Every region must use the same height, scale, camera, baseline, "
        "and visual proportions.\n\n"
        f"Each of the {words} figures is the SAME character at a DIFFERENT moment of the same "
        "action, drawn head to feet. Never merge two moments into one figure, and never leave "
        "a described moment out because it seems similar to another — near-identical frames "
        "are intentional and must still be drawn separately.\n\n"
        "Leave a clear band of empty transparent space between neighbouring figures. Figures "
        "must not touch, overlap, or share limbs, and no part of one figure may cross into "
        "another region — the application separates them by those gaps.\n\n"
        "FORBIDDEN: character turnarounds or model sheets; back, side, or alternate views of "
        "the same pose; inset close-ups, detail callouts, or a second head, face, or hand "
        "drawn beside a figure; partial figures, floating body parts, or cropped busts; grids, "
        "panel borders, frames, labels, numbers, captions, or arrows; extra poses beyond the "
        f"{words} requested. Every figure is complete from head to feet except where a pose "
        "explicitly requires edge cropping.\n\n"
        "The final application slices and normalizes the regions, so visual consistency and "
        "the exact figure count matter far more than the model's output dimensions."
    )


# Phrases in the shared style block that describe a human body. They must never
# survive into a non-human prompt, so the substitutions below are verified rather
# than assumed -- see _style_for_subject.
HUMAN_ANATOMY_PHRASES = ("head to toe", "small hands", "feet resting near the bottom")


def _style_for_subject(style: str, subject_type: str) -> str:
    """Retarget the shared style block at a non-human subject.

    The two rewrites below are exact-text replacements against
    ``reference/PROMPTS.md``. If that wording is ever edited without updating
    this function, the replacements would silently do nothing and every pet or
    cartoon-character prompt would start asking for human hands and feet -- a
    failure with no visible symptom until the artwork came back wrong. The
    assertion at the end turns that into an immediate, loud error instead.
    """
    if subject_type == "human":
        return style
    style = re.sub(
        r"VIEW: straight-on side-scroller view.*?bottom of the canvas\.",
        "VIEW: straight-on side-scroller view, full body visible from ears/head to paws, "
        "feet, tail, or perch, subject centred horizontally, grounded contact point near "
        "the bottom of the canvas.",
        style,
        flags=re.DOTALL,
    )
    style = re.sub(
        r"PROPORTIONS: slightly chibi.*?across all frames\.",
        "PROPORTIONS: a slightly chibi simplification of the character in the reference "
        "while preserving its exact body plan -- species anatomy, face shape, ears, "
        "paws/feet/hands, wings, and tail exactly as the reference has them. Never add or "
        "remove limbs, hands, fingers or an upright posture that the reference does not "
        "already have. Consistent proportions across all frames.",
        style,
        flags=re.DOTALL,
    )
    leaked = [phrase for phrase in HUMAN_ANATOMY_PHRASES if phrase in style]
    if leaked:
        raise ValueError(
            "The shared style block in reference/PROMPTS.md changed and "
            f"_style_for_subject no longer strips human anatomy: {leaked}. "
            "Update the substitutions in this function before shipping."
        )
    return style


def assemble_reference_prompt(
    subject_type: str, sheet: Mapping[str, str] | None = None
) -> str:
    _, style, _ = load_blocks()
    style = _style_for_subject(style, subject_type)
    character = format_character_sheet(sheet, subject_type)
    anatomy = (
        "Preserve recognisable facial features, hairstyle, skin tone, clothes, shoes, and "
        "accessories from the attached real photograph. Use natural human anatomy."
        if subject_type == "human"
        else "Preserve the species, face shape, ears, coat or feathers, markings, eye colour, "
        "body shape, tail, and accessories from the attached real photograph. Use natural "
        "animal anatomy; do not add human clothes or limbs unless they are present in the photo."
    )
    style = style.replace(
        "OUTPUT: single sprite on transparent background, 64x64 pixels.",
        "OUTPUT: exactly one sprite on a transparent square canvas. Aim for a 64x64 pixel-art "
        "design; if the interface outputs a larger image, keep edges hard and the design readable "
        "when reduced to 64x64 with nearest-neighbour scaling.",
    )
    return f"""Create the definitive pixel-art reference character for a desktop companion app.

ATTACHED IMAGE:
Use the attached real {subject_type} photograph as the definitive identity and appearance reference.
Extract only the subject. Ignore and do not reproduce the photograph's background, lighting,
camera crop, furniture, scenery, text, or other people/animals.

CHARACTER TYPE: {subject_type.upper()}
{character}

IDENTITY REQUIREMENT:
{anatomy}
When a requested detail is not visible in the photograph, use the character description above.
Do not beautify, redesign, change colours, or add unrequested accessories.

POSE: neutral natural standing pose, facing the viewer at a slight three-quarter angle, full
body visible from head to feet, relaxed and friendly expression, eyes open. Keep the
silhouette clear at very small size.

BUILD THE BODY AS ONE PIECE:
Draw a clearly visible neck joining the head to the shoulders, so the head reads as sitting
on the body rather than resting on top of it. Shoulders, torso and hips line up over the
feet, and the weight is carried evenly through both feet (or through every grounded limb)
onto a single ground line. Every later animation frame is built from this drawing, so an
ambiguous neck or an unclear ground contact here is inherited by all of them.

{style}

This image becomes reference.png and will be attached to every later animation prompt.
Create exactly ONE character in ONE pose, seen from ONE angle. This is not a model sheet:
no turnarounds, no back or side views, no alternate poses, no expression sheets, no inset
close-ups of the face or hands, and no labels or captions.""".strip()


def assemble_prompts(
    sheet: Mapping[str, str] | None = None, subject_type: str = "human"
) -> dict[str, str]:
    consistency, style, poses = load_blocks()
    style = _style_for_subject(style, subject_type)
    if subject_type == "pet":
        consistency = PET_CONSISTENCY
    character = format_character_sheet(sheet, subject_type)
    result = {}
    for clip in CLIPS:
        pose = poses[clip.prompt_number] if subject_type == "human" else PET_POSES[clip.name]
        prompt = pose.replace("[CONSISTENCY BLOCK]", consistency)
        prompt = prompt.replace("[STYLE BLOCK]", _contact_sheet_style(style, clip.ask))
        prompt = prompt.replace("[CHARACTER SHEET]", character)
        if "[CHARACTER SHEET]" not in pose:
            insertion = f"\n\nCHARACTER (keep every detail identical):\n{character}"
            marker = "\n\nPOSE:"
            prompt = prompt.replace(marker, insertion + marker, 1)
        if subject_type == "pet":
            prompt = f"{consistency}\n\nCHARACTER (keep every detail identical):\n{character}\n\n{pose}\n\n{_contact_sheet_style(style, clip.ask)}"
        prompt += "\n\nCONTACT SHEET OVERRIDE: Follow the output-format block exactly."
        result[clip.name] = prompt.strip()
    return result


def placeholders(subject_type: str = "human") -> dict[str, str]:
    return {key: example for key, _, example in fields_for(subject_type)}


def prompt_payload(subject_type: str, sheet: Mapping[str, str] | None = None) -> dict:
    clips = assemble_prompts(sheet, subject_type)
    return {
        "reference": assemble_reference_prompt(subject_type, sheet),
        "clips": clips,
    }
