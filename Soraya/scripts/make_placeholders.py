#!/usr/bin/env python3
"""Draws placeholder frames so the app is watchable before the real art lands.

These are **placeholders and nothing more**. They exist so that every clip has
frames, the animator has something to cycle, and the folder layout is visible
and obvious — so replacing them is a matter of dropping files in, not guessing
what the structure should have been.

Every frame is drawn on the same canvas with the same feet position, which is
the one property that actually matters when you swap in your own art: if the
feet move between clips, she appears to hop when the clip changes. See
ARCHITECTURE.md § The art contract.

    python3 scripts/make_placeholders.py            # writes the Placeholder pack
    python3 scripts/make_placeholders.py --force    # overwrite its frames

Two guards, because this script writes image files in bulk:

`--force` never runs by default. The whole point of these files is to be
replaced by real ones, and a script that silently overwrites hand-made art is a
script that eventually destroys hand-made art.

The default pack is `Placeholder`, not `Soraya`. It used to be `Soraya`, which
was harmless while that pack *was* the placeholders — and became a loaded gun
the moment real art was imported into it, because `--force` would then have
overwritten the real frames with stick figures. Even so, `--force` refuses to
touch a pack whose frames are not placeholder-shaped; see `looks_like_real_art`.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from soraya.presence.sprite import CLIPS  # noqa: E402

# One canvas for every frame of every clip. Matching the Nish pack's aspect
# ratio (466x744) so art drawn for one is drawn for both.
# Exact multiples of SCALE, so scaling back up is a whole number and the
# pixels stay square. 233 wide was the first attempt and 233/8 is not an
# integer, which gave uneven pixel widths across the figure.
W, H = 232, 368
BASELINE = 360          # where the feet sit, identical in every frame
# Drawn small then scaled up with NEAREST, which is what makes the pixels hard
# rather than smoothed. 8 rather than 4: at 4 the figure filled only 40% of the
# frame and read as a speck in a lot of white space.
SCALE = 8

# Blue and white, matching the interface.
INK = (15, 27, 45, 255)
BLUE = (22, 104, 199, 255)
BLUE_DEEP = (13, 76, 152, 255)
SKIN = (247, 223, 205, 255)
HAIR = (36, 42, 61, 255)
WHITE = (255, 255, 255, 255)

#: clip -> (frame count, how it moves). Frame counts match what the real packs
#: use, so a replacement drop-in has the same number of files.
PLAN: dict[str, tuple[int, str]] = {
    "idle":      (4, "breathe"),
    "walk":      (6, "walk"),
    "wave":      (4, "wave"),
    "concerned": (4, "concerned"),
    "cheer":     (4, "cheer"),
    "happy":     (4, "cheer"),
    "peek":      (4, "peek"),
    "sleep":     (4, "sleep"),
    "yawn":      (4, "yawn"),
    "focus":     (4, "focus"),
    "sitting":   (4, "focus"),
    "stretch":   (4, "stretch"),
    "talking":   (6, "talk"),
    "listening": (4, "listen"),
    "thinking":  (4, "think"),
    "greeting":  (4, "wave"),
}


def draw_frame(motion: str, index: int, total: int) -> Image.Image:
    """One frame, drawn small and scaled up so the pixels stay crisp."""
    small = Image.new("RGBA", (W // SCALE, H // SCALE), (0, 0, 0, 0))
    d = ImageDraw.Draw(small)
    cx = small.width // 2
    base = BASELINE // SCALE
    phase = index / max(1, total)          # 0..1 through the cycle
    swing = math.sin(phase * math.tau)     # -1..1, loops cleanly

    # Per-motion offsets. Kept as plain numbers rather than a rig: this is a
    # placeholder, and a placeholder with an animation system is a trap.
    bob = 0
    lean = 0
    arm_l = arm_r = 0
    head_tilt = 0
    eyes_open = True
    mouth = 1
    sitting = False

    if motion == "breathe":
        bob = round(swing * 0.6)
    elif motion == "walk":
        bob = abs(round(swing * 1.4))
        arm_l, arm_r = round(swing * 4), -round(swing * 4)
    elif motion == "wave":
        arm_r = -round(4 + abs(swing) * 5)
        bob = round(swing * 0.5)
    elif motion == "concerned":
        head_tilt = 1
        arm_l = arm_r = 1
        bob = round(swing * 0.4)
    elif motion == "cheer":
        bob = -abs(round(swing * 3))
        arm_l = arm_r = -7
        mouth = 3
    elif motion == "peek":
        lean = 4
        head_tilt = 1
    elif motion == "sleep":
        eyes_open = False
        head_tilt = 2
        bob = round(swing * 0.5)
        mouth = 0
    elif motion == "yawn":
        eyes_open = index % total < total // 2
        mouth = 4
        arm_r = -round(3 + abs(swing) * 3)
    elif motion == "focus":
        sitting = True
        head_tilt = 1
        mouth = 0
    elif motion == "stretch":
        arm_l = arm_r = -round(6 + abs(swing) * 3)
        bob = -1
    elif motion == "talk":
        # The mouth is the whole point of this clip.
        mouth = 1 + (index % 3)
        bob = round(swing * 0.5)
    elif motion == "listen":
        head_tilt = 1
        mouth = 0
        bob = round(swing * 0.4)
    elif motion == "think":
        head_tilt = -1
        mouth = 0
        arm_r = 2
        bob = round(swing * 0.4)

    hip = base - (6 if sitting else 13)
    shoulder = hip - 9
    head_y = shoulder - 7

    # legs
    if sitting:
        d.rectangle([cx - 5, hip, cx - 1, hip + 5], fill=BLUE_DEEP)
        d.rectangle([cx + 1, hip, cx + 5, hip + 5], fill=BLUE_DEEP)
    else:
        step = round(swing * 2) if motion == "walk" else 0
        d.rectangle([cx - 4 - step, hip, cx - 1 - step, base], fill=BLUE_DEEP)
        d.rectangle([cx + 1 + step, hip, cx + 4 + step, base], fill=BLUE_DEEP)

    # torso
    d.rectangle([cx - 5 + lean, shoulder, cx + 5 + lean, hip + 1], fill=BLUE)
    # a white collar, so she reads as blue-and-white rather than a blue blob
    d.rectangle([cx - 3 + lean, shoulder, cx + 3 + lean, shoulder + 1], fill=WHITE)

    # arms
    d.rectangle([cx - 7 + lean, shoulder + 1 + arm_l,
                 cx - 6 + lean, shoulder + 7 + arm_l], fill=SKIN)
    d.rectangle([cx + 6 + lean, shoulder + 1 + arm_r,
                 cx + 7 + lean, shoulder + 7 + arm_r], fill=SKIN)

    # head
    hx = cx + lean + head_tilt
    hy = head_y + bob
    d.rectangle([hx - 5, hy - 6, hx + 5, hy + 2], fill=SKIN)
    d.rectangle([hx - 6, hy - 8, hx + 6, hy - 4], fill=HAIR)
    d.rectangle([hx - 6, hy - 7, hx - 5, hy], fill=HAIR)
    d.rectangle([hx + 5, hy - 7, hx + 6, hy], fill=HAIR)

    # eyes
    if eyes_open:
        d.point((hx - 3, hy - 2), fill=INK)
        d.point((hx + 3, hy - 2), fill=INK)
    else:
        d.line([hx - 4, hy - 2, hx - 2, hy - 2], fill=INK)
        d.line([hx + 2, hy - 2, hx + 4, hy - 2], fill=INK)

    # mouth: 0 closed, 1 line, 2-3 open, 4 wide (yawn)
    if mouth == 1:
        d.line([hx - 1, hy + 1, hx + 1, hy + 1], fill=INK)
    elif mouth in (2, 3):
        d.rectangle([hx - 1, hy, hx + 1, hy + 1 + (mouth - 2)], fill=INK)
    elif mouth == 4:
        d.ellipse([hx - 2, hy - 1, hx + 2, hy + 3], fill=INK)

    return small.resize((W, H), Image.NEAREST)


def looks_like_real_art(root: Path) -> bool:
    """Whether a pack holds frames this script did not draw.

    Judged by canvas size, which is a reliable tell: everything here is drawn
    at exactly W x H, so anything else came from somewhere else. Cheap, and it
    fails safe — an unreadable file counts as real art rather than as fair game.
    """
    for path in root.rglob("*.png"):
        try:
            with Image.open(path) as image:
                if image.size != (W, H):
                    return True
        except OSError:
            return True
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", default="Placeholder")
    parser.add_argument("--force", action="store_true",
                        help="overwrite frames that already exist")
    args = parser.parse_args()

    root = ROOT / "assets" / "characters" / args.pack

    if args.force and looks_like_real_art(root):
        print(f"  ✗ {args.pack} contains frames that are not placeholders "
              f"(wrong canvas size for this script's output).")
        print("    Refusing to overwrite them. Use --pack with another name.")
        return 1

    written = skipped = 0

    for clip, (count, motion) in PLAN.items():
        folder, prefix, _ = CLIPS[clip]
        directory = root / folder
        directory.mkdir(parents=True, exist_ok=True)
        for index in range(count):
            path = directory / f"{prefix}_{index + 1:02d}.png"
            if path.exists() and not args.force:
                skipped += 1
                continue
            draw_frame(motion, index, count).save(path)
            written += 1

    (root / "README.txt").write_text(
        "Placeholder frames — replace them.\n"
        "=================================\n\n"
        "Drop your own PNGs into these folders, same names, same counts.\n"
        "Delete a file and re-run scripts/make_placeholders.py to get it back.\n\n"
        "The only rule that matters: keep the character's FEET at the same\n"
        f"height in every frame of every clip ({BASELINE} of {H} pixels here).\n"
        "If the feet move between clips she appears to hop when the clip\n"
        "changes, and no amount of code can fix that afterwards.\n\n"
        "Transparent background. Any canvas size works as long as it is the\n"
        "same for every frame in the pack.\n"
    )

    print(f"  {args.pack}: {written} frames written, {skipped} left alone")
    if skipped and not args.force:
        print("  (existing files are never overwritten — pass --force if you mean to)")
    print(f"  {root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
