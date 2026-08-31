#!/usr/bin/env python3
"""
Turns a folder of AI-generated character images into a character pack AiTwin
can use.

This exists because hand-cropping and hand-naming frames is slow and, more
importantly, does not fix the thing that actually breaks the animation: frames
generated in separate requests come back at different scales, so the character
visibly changes size when it switches from standing to walking. No amount of
renaming fixes that. This tool does.

What it does, in order:

  1. SLICES contact sheets. If an image contains several characters side by
     side, it is split on the empty columns between them. So you can drop in the
     sheet the image model gave you and skip cropping altogether.
  2. DEDUPLICATES. Byte-identical frames (a stray copy of an idle frame sitting
     in the EyeBreak folder, say) are dropped once, with a note.
  3. NORMALISES. Every clip is scaled so the character is the SAME HEIGHT
     everywhere, and shifted so every clip stands on the SAME BASELINE. The
     transform is applied per clip, not per frame, so motion inside a clip --
     a walk cycle's bob, a breathing idle -- is preserved exactly as drawn.
  4. RENAMES to the convention the app expects and writes the folder layout.

Usage
-----
    # Normalise a pack in place (a backup is kept):
    python3 Scripts/import_character.py Resources/Characters/Nish

    # From a flat folder of downloads into a new pack:
    python3 Scripts/import_character.py ~/Downloads/my-character --name Luna

    # Install straight into Application Support (no rebuild needed):
    python3 Scripts/import_character.py ~/Downloads/my-character --name Luna --install

    # See what it would do without touching anything:
    python3 Scripts/import_character.py Resources/Characters/Nish --dry-run

Requires: Pillow, numpy.  (pip3 install pillow numpy)
"""

import argparse
import hashlib
import os
import re
import shutil
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("error: Pillow is required.  pip3 install pillow numpy")
try:
    import numpy as np
except ImportError:
    sys.exit("error: numpy is required.  pip3 install pillow numpy")

LANCZOS = getattr(getattr(Image, "Resampling", Image), "LANCZOS")

# ---------------------------------------------------------------------------
# Output geometry
#
# 512px tall is chosen to match the app: the character can be displayed at up to
# 256 points, which is 512 device pixels on a Retina display. So the art is used
# at 1:1 at maximum size and downscaled from there -- never upscaled, which is
# what would make it soft.
# ---------------------------------------------------------------------------
CANVAS_HEIGHT = 512
CHARACTER_HEIGHT = 470      # the character itself, leaving room for hair/arms
BOTTOM_MARGIN = 16          # gap between the feet and the bottom of the canvas
MIN_CANVAS_WIDTH = 320
ALPHA_THRESHOLD = 16        # below this a pixel counts as empty

# Clip name -> (output folder, file prefix, keywords that identify it).
# Keywords are matched against both the folder name and the filename, longest
# first, so "eyebreak" wins over "eye" and "walking" over "walk".
CLIPS = [
    ("idle",          "Idle",          "idle",     ["idle", "idel", "stand", "breath"]),
    ("walk",          "Walking",       "walk",     ["walking", "walk"]),
    ("wave",          "Waving",        "wave",     ["waving", "wave", "greet", "hello"]),
    ("drink",         "WaterReminder", "drink",    ["waterreminder", "water", "drink", "hydrat"]),
    ("eyebreak",      "EyeBreak",      "eyebreak", ["eyebreak", "eye_break", "eyerest", "eye"]),
    ("sleep",         "Sleep",         "sleep",    ["sleeping", "sleep", "tired", "rest"]),
    ("happy",         "HappyMood",     "happy",    ["happymood", "happy", "celebrat", "cheer"]),
    # Glasses is a VARIANT, not a state -- it lands in Idle/ as idle_glasses_NN.
    ("focus",         "Focus",         "focus",    ["focus", "reading", "read", "chair", "pomodoro"]),
    ("stretch",       "Stretch",       "stretch",  ["stretch", "posture"]),
    ("concerned",     "Concerned",     "concerned", ["concerned", "worried", "worry"]),
    ("cheer",         "Cheer",         "cheer",    ["cheer", "celebrate", "milestone", "proud"]),
    ("peek",          "Peek",          "peek",     ["peek", "peeking", "hiding"]),
    ("yawn",          "Yawn",          "yawn",     ["yawn", "yawning", "drowsy"]),
    # Glasses is a VARIANT, not a state -- it lands in Idle/ as idle_glasses_NN.
    ("idle_glasses",  "Idle",          "idle_glasses", ["glasses", "specs"]),
]


def classify(path, root):
    """Works out which clip an image belongs to, from its folder and filename."""
    rel = os.path.relpath(path, root).lower()
    best, best_len = None, 0
    for clip, folder, prefix, keywords in CLIPS:
        for kw in keywords:
            if kw in rel and len(kw) > best_len:
                best, best_len = (clip, folder, prefix), len(kw)
    return best


def content_bbox(image):
    """Bounding box of the non-transparent pixels, or None if fully empty."""
    alpha = image.split()[-1].point(lambda p: 255 if p > ALPHA_THRESHOLD else 0)
    return alpha.getbbox()


def slice_sheet(image, min_run_fraction=0.02):
    """
    Splits a contact sheet into individual frames on its empty columns.

    Image models routinely return several poses side by side in one picture.
    Rather than making you crop them, we find the runs of columns that contain
    any pixels and treat each run as a frame. Returns [image] unchanged if only
    one run is found, so this is safe to call on everything.
    """
    alpha = np.array(image.split()[-1]) > ALPHA_THRESHOLD
    columns = alpha.any(axis=0)

    runs, start = [], None
    for index, filled in enumerate(columns):
        if filled and start is None:
            start = index
        elif not filled and start is not None:
            runs.append((start, index))
            start = None
    if start is not None:
        runs.append((start, len(columns)))

    # Ignore slivers -- a stray dot should not become a frame.
    minimum = max(8, int(image.width * min_run_fraction))
    runs = [r for r in runs if r[1] - r[0] >= minimum]

    if len(runs) < 2:
        return [image]

    frames = []
    for left, right in runs:
        pad = 2
        frames.append(image.crop((
            max(0, left - pad), 0,
            min(image.width, right + pad), image.height,
        )))
    return frames


def natural_key(text):
    """Sorts walk_2 before walk_10, which a plain string sort gets wrong."""
    return [int(part) if part.isdigit() else part.lower()
            for part in re.split(r"(\d+)", text)]


def collect(source):
    """
    Walks the source tree and returns {clip: [(label, image), ...]}.

    Sheets are sliced, duplicates are dropped, and anything that cannot be
    classified is reported rather than silently ignored.
    """
    found, skipped, unmatched, seen = {}, [], [], {}
    clip_order = {clip: i for i, (clip, _, _, _) in enumerate(CLIPS)}

    paths = []
    for directory, _, filenames in os.walk(source):
        if os.path.basename(directory).startswith("."):
            continue
        for filename in filenames:
            if filename.lower().endswith((".png", ".tif", ".tiff")) and not filename.startswith("."):
                paths.append(os.path.join(directory, filename))

    classified = []
    for path in paths:
        match = classify(path, source)
        if match is None:
            unmatched.append(os.path.relpath(path, source))
        else:
            classified.append((match[0], path))

    # Sort by clip order first, so that when the same image has been filed under
    # two clips -- a copy of an idle pose sitting in EyeBreak/, say -- the more
    # fundamental clip claims it and the stray copy is the one dropped.
    classified.sort(key=lambda item: (clip_order[item[0]], natural_key(item[1])))

    for clip, path in classified:
        digest = hashlib.md5(open(path, "rb").read()).hexdigest()
        if digest in seen:
            skipped.append((os.path.relpath(path, source), seen[digest]))
            continue
        seen[digest] = os.path.relpath(path, source)

        try:
            image = Image.open(path).convert("RGBA")
        except Exception as error:
            unmatched.append(f"{os.path.relpath(path, source)} (unreadable: {error})")
            continue

        pieces = slice_sheet(image)
        label = os.path.relpath(path, source)
        from_sheet = len(pieces) > 1
        for index, piece in enumerate(pieces):
            if content_bbox(piece) is None:
                continue
            name = label if not from_sheet else f"{label}[{index + 1}/{len(pieces)}]"
            found.setdefault(clip, []).append((name, piece, from_sheet))

    return found, skipped, unmatched


def prefer_sheets(found, prefer="sheet"):
    """
    Drops the redundant half when a clip has both a contact sheet and hand-made
    crops of the same poses.

    People usually end up with both: the sheet the model returned, plus the
    frames they cropped out of it by hand. Keeping both would double every
    animation with near-identical frames. The sheet is preferred by default
    because slicing it is exact, whereas hand crops vary by a few pixels.
    """
    notes = []
    for clip, frames in list(found.items()):
        sheet = [f for f in frames if f[2]]
        loose = [f for f in frames if not f[2]]
        if not sheet or not loose:
            continue
        keep, drop, why = (sheet, loose, "sheet") if prefer == "sheet" else (loose, sheet, "crops")
        found[clip] = keep
        notes.append(f"{clip}: kept {len(keep)} frame(s) from the {why}, "
                     f"dropped {len(drop)} duplicate(s) of the same poses")
    return notes


def normalise(found, verbose=True):
    """
    Puts every clip on one scale and one baseline.

    The transform is computed PER CLIP and applied to all of that clip's frames
    identically. That is the important detail: normalising each frame
    individually would flatten the very motion the frames exist to show -- a
    walk cycle would stop bobbing and an idle would stop breathing.
    """
    measured = {}
    for clip, frames in found.items():
        boxes = [content_bbox(image) for _, image, _ in frames]
        boxes = [b for b in boxes if b]
        if not boxes:
            continue
        measured[clip] = {
            "height": max(b[3] - b[1] for b in boxes),   # tallest pose in the clip
            "bottom": max(b[3] for b in boxes),          # lowest point (the feet)
            "left":   min(b[0] for b in boxes),
            "right":  max(b[2] for b in boxes),
        }

    if not measured:
        return {}, MIN_CANVAS_WIDTH

    # One scale per clip, so the character is the same height in all of them.
    for clip, m in measured.items():
        m["scale"] = CHARACTER_HEIGHT / m["height"]

    # The canvas has to be wide enough for the widest clip once scaled --
    # a walk cycle with swinging arms is much wider than a standing pose.
    widest = max((m["right"] - m["left"]) * m["scale"] for m in measured.values())
    canvas_width = max(MIN_CANVAS_WIDTH, int(widest) + 32)
    canvas_width += canvas_width % 2

    baseline = CANVAS_HEIGHT - BOTTOM_MARGIN
    output = {}

    for clip, frames in found.items():
        if clip not in measured:
            continue
        m = measured[clip]
        scale = m["scale"]
        centre_x = (m["left"] + m["right"]) / 2.0

        if verbose:
            print(f"    {clip:14s} {len(frames)} frame(s)  "
                  f"character {m['height']}px -> {CHARACTER_HEIGHT}px  (x{scale:.3f})")

        rendered = []
        for label, image, _ in frames:
            scaled = image.resize(
                (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
                LANCZOS,
            )
            canvas = Image.new("RGBA", (canvas_width, CANVAS_HEIGHT), (0, 0, 0, 0))
            # Align the clip's lowest point to the shared baseline and its
            # horizontal centre to the canvas centre.
            offset_x = round(canvas_width / 2.0 - centre_x * scale)
            offset_y = round(baseline - m["bottom"] * scale)
            canvas.alpha_composite(scaled, (offset_x, offset_y))
            rendered.append((label, canvas))
        output[clip] = rendered

    return output, canvas_width


def write(output, destination, dry_run=False, clean=False):
    """
    Writes the normalised frames using the naming convention the app expects.

    With `clean`, the originals are removed from the pack first. Without it, the
    old files would sit alongside the new ones -- harmless, because the app
    ignores anything not named `prefix_NN.png`, but it doubles the pack's size
    on disk and makes the folder impossible to read. Only ever passed when the
    originals have already been backed up.
    """
    folders = {clip: (folder, prefix) for clip, folder, prefix, _ in CLIPS}
    known_folders = {folder for _, folder, _, _ in CLIPS}
    written, removed = [], 0

    if clean and not dry_run:
        for entry in sorted(os.listdir(destination)):
            path = os.path.join(destination, entry)
            if entry.startswith(".") or not os.path.isdir(path):
                continue
            for filename in os.listdir(path):
                if filename.lower().endswith((".png", ".tif", ".tiff")):
                    os.remove(os.path.join(path, filename))
                    removed += 1
            # A folder that no longer maps to a clip -- Glasses/, now that
            # glasses live in Idle/ as a variant -- is left empty; drop it.
            if entry not in known_folders and not os.listdir(path):
                os.rmdir(path)

    for clip, frames in sorted(output.items()):
        folder, prefix = folders[clip]
        target = os.path.join(destination, folder)
        if not dry_run:
            os.makedirs(target, exist_ok=True)
            # Clear only this clip's own files, so two clips sharing a folder
            # (idle and idle_glasses both live in Idle/) do not delete each other.
            for existing in os.listdir(target):
                if re.fullmatch(rf"{re.escape(prefix)}_\d+\.png", existing, re.IGNORECASE):
                    os.remove(os.path.join(target, existing))

        for index, (_, image) in enumerate(frames, start=1):
            name = f"{prefix}_{index:02d}.png"
            if not dry_run:
                image.save(os.path.join(target, name))
            written.append(f"{folder}/{name}")

    return written, removed


def main():
    parser = argparse.ArgumentParser(
        description="Slice, normalise and name character frames for AiTwin.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("source", help="folder containing your character images")
    parser.add_argument("--name", help="pack name (default: the source folder's name)")
    parser.add_argument("--out", help="destination pack folder (default: in place)")
    parser.add_argument("--install", action="store_true",
                        help="write into ~/Library/Application Support/AiTwin/Characters")
    parser.add_argument("--dry-run", action="store_true", help="report only, change nothing")
    parser.add_argument("--no-backup", action="store_true", help="skip backing up the originals")
    parser.add_argument("--prefer", choices=["sheet", "crops"], default="sheet",
                        help="when both a contact sheet and individual crops exist "
                             "for a clip, which to keep (default: sheet)")
    args = parser.parse_args()

    source = os.path.abspath(os.path.expanduser(args.source))
    if not os.path.isdir(source):
        sys.exit(f"error: no such folder: {source}")

    name = args.name or os.path.basename(source.rstrip("/"))

    if args.install:
        destination = os.path.expanduser(
            f"~/Library/Application Support/AiTwin/Characters/{name}")
    elif args.out:
        destination = os.path.abspath(os.path.expanduser(args.out))
    else:
        destination = source

    print(f"Reading   {source}")
    print(f"Pack      {name}")
    print(f"Writing   {destination}{'   (DRY RUN)' if args.dry_run else ''}\n")

    print("Collecting frames…")
    found, skipped, unmatched = collect(source)

    if not found:
        sys.exit("error: no recognisable character frames found.\n"
                 "       Name folders or files after the animation, e.g. Idle/, walk_01.png.")

    for label, original in skipped:
        print(f"    skipped duplicate: {label}  (same image as {original})")
    for label in unmatched:
        print(f"    ignored (no matching clip): {label}")

    for note in prefer_sheets(found, args.prefer):
        print(f"    {note}")
    if skipped or unmatched:
        print()

    print("Normalising…")
    output, canvas_width = normalise(found)
    print(f"\n    canvas {canvas_width}x{CANVAS_HEIGHT}, character {CHARACTER_HEIGHT}px, "
          f"feet on a shared baseline\n")

    backed_up = False
    if not args.dry_run and not args.no_backup and destination == source:
        backup = os.path.join(destination, ".source-backup")
        backed_up = True
        if not os.path.exists(backup):
            os.makedirs(backup)
            for entry in os.listdir(source):
                if entry.startswith("."):
                    continue
                path = os.path.join(source, entry)
                target = os.path.join(backup, entry)
                shutil.copytree(path, target) if os.path.isdir(path) else shutil.copy2(path, target)
            print(f"Originals backed up to {os.path.relpath(backup, source)}/\n")

    written, removed = write(output, destination,
                             dry_run=args.dry_run, clean=backed_up)

    if removed:
        print(f"Replaced {removed} original file(s) — they are safe in .source-backup/\n")
    print(f"{'Would write' if args.dry_run else 'Wrote'} {len(written)} frames:")
    for clip, frames in sorted(output.items()):
        folder, prefix = {c: (f, p) for c, f, p, _ in CLIPS}[clip]
        print(f"    {folder}/{prefix}_01..{len(frames):02d}.png")

    missing = [c for c, _, _, _ in CLIPS if c not in output and c != "idle_glasses"]
    if missing:
        print(f"\nNo frames for: {', '.join(missing)} — these fall back to idle at runtime.")

    if not args.dry_run:
        print("\nDone. In AiTwin: Settings › Character › Reload Characters, then pick "
              f"\"{name}\".")


if __name__ == "__main__":
    main()
