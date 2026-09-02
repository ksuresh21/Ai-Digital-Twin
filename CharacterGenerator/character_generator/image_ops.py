"""Sheet slicing, one-pass normalization, and measurable quality checks."""

import math
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import numpy as np
from PIL import Image
from PIL import ImageOps

from .clips import CLIP_BY_NAME


ALPHA_THRESHOLD = 16
BASE_CANVAS_HEIGHT = 512
BOTTOM_MARGIN = 16
TOP_MARGIN = 14
MIN_CANVAS_WIDTH = 320
NEAREST = getattr(getattr(Image, "Resampling", Image), "NEAREST")


@dataclass(frozen=True)
class BackgroundCleanup:
    image: Image.Image
    changed: bool
    method: str
    removed_fraction: float
    warning: str | None = None


@dataclass(frozen=True)
class SheetSplit:
    frames: list[Image.Image]
    method: str
    warning: str | None = None


def content_bbox(image: Image.Image):
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A").point(lambda p: 255 if p > ALPHA_THRESHOLD else 0)
    return alpha.getbbox()


def open_image(source) -> Image.Image:
    """Open an uploaded image with orientation applied and return detached RGBA pixels."""
    with Image.open(source) as opened:
        return ImageOps.exif_transpose(opened).convert("RGBA").copy()


def _border_pixels(rgb: np.ndarray) -> np.ndarray:
    if rgb.shape[0] == 1 or rgb.shape[1] == 1:
        return rgb.reshape(-1, 3)
    return np.concatenate((rgb[0], rgb[-1], rgb[1:-1, 0], rgb[1:-1, -1]), axis=0)


def _background_centres(rgb: np.ndarray) -> tuple[list[np.ndarray], float]:
    """Return dominant quantized border colours and their border coverage."""
    border = _border_pixels(rgb).astype(np.int16)
    if not len(border):
        return [], 0.0
    quantized = ((border + 8) // 16).clip(0, 15)
    keys, inverse, counts = np.unique(quantized, axis=0, return_inverse=True, return_counts=True)
    order = np.argsort(counts)[::-1]
    centres = []
    covered = 0
    minimum = max(2, int(len(border) * 0.015))
    for index in order[:8]:
        if counts[index] < minimum:
            continue
        members = border[inverse == index]
        centres.append(members.mean(axis=0).astype(np.float32))
        covered += int(counts[index])
        if covered / len(border) >= 0.92 or len(centres) == 6:
            break
    return centres, covered / len(border)


def remove_background(image: Image.Image, tolerance: float = 46.0) -> BackgroundCleanup:
    """Remove a simple solid/checker background using edge-connected colour regions.

    Existing alpha is preserved. For opaque images we learn up to six dominant
    colours from the outer border, then clear only matching pixels connected to
    that border. Enclosed eyes, clothes, highlights, and markings are therefore
    retained even when they share a colour with the background.
    """
    rgba = np.asarray(image.convert("RGBA")).copy()
    transparent_fraction = float(np.mean(rgba[..., 3] <= ALPHA_THRESHOLD))
    if transparent_fraction >= 0.005:
        rgba[..., 3][rgba[..., 3] <= ALPHA_THRESHOLD] = 0
        return BackgroundCleanup(
            Image.fromarray(rgba, "RGBA"), False, "existing-alpha", transparent_fraction
        )

    rgb = rgba[..., :3]
    centres, coverage = _background_centres(rgb)
    if not centres or coverage < 0.45:
        return BackgroundCleanup(
            Image.fromarray(rgba, "RGBA"), False, "unresolved", 0.0,
            "The image border is too complex for safe automatic background removal.",
        )

    pixels = rgb.astype(np.float32)
    candidate = np.zeros(rgb.shape[:2], dtype=bool)
    for centre in centres:
        candidate |= np.linalg.norm(pixels - centre, axis=2) <= tolerance

    height, width = candidate.shape
    connected = np.zeros_like(candidate)
    queue: deque[int] = deque()

    def add(y: int, x: int) -> None:
        if candidate[y, x] and not connected[y, x]:
            connected[y, x] = True
            queue.append(y * width + x)

    for x in range(width):
        add(0, x)
        if height > 1:
            add(height - 1, x)
    for y in range(1, height - 1):
        add(y, 0)
        if width > 1:
            add(y, width - 1)

    while queue:
        position = queue.popleft()
        y, x = divmod(position, width)
        if x:
            add(y, x - 1)
        if x + 1 < width:
            add(y, x + 1)
        if y:
            add(y - 1, x)
        if y + 1 < height:
            add(y + 1, x)

    removed_fraction = float(np.mean(connected))
    # A plausible contact-sheet or reference background should occupy a useful
    # part of the canvas. Refuse tiny removals because they are usually a border
    # detail or the pet/character itself touching an edge.
    if removed_fraction < 0.03:
        return BackgroundCleanup(
            Image.fromarray(rgba, "RGBA"), False, "unresolved", removed_fraction,
            "Only a tiny edge region looked removable, so the original was preserved.",
        )
    rgba[..., 3][connected] = 0
    rgba[..., :3][connected] = 0
    warning = None
    if removed_fraction < 0.20:
        warning = "Only part of the background could be removed automatically; inspect the preview."
    return BackgroundCleanup(
        Image.fromarray(rgba, "RGBA"), True, "edge-colour", removed_fraction, warning
    )


def slice_sheet(image: Image.Image, min_run_fraction: float = 0.02) -> list[Image.Image]:
    image = image.convert("RGBA")
    alpha = np.asarray(image.getchannel("A")) > ALPHA_THRESHOLD
    columns = alpha.any(axis=0)
    runs: list[tuple[int, int]] = []
    start = None
    for index, filled in enumerate(columns):
        if filled and start is None:
            start = index
        elif not filled and start is not None:
            runs.append((start, index))
            start = None
    if start is not None:
        runs.append((start, len(columns)))

    minimum = max(8, int(image.width * min_run_fraction))
    runs = [run for run in runs if run[1] - run[0] >= minimum]
    if len(runs) < 2:
        return [image]
    widest = max(right - left for left, right in runs)
    if any(right - left < widest * 0.34 for left, right in runs):
        return [image]
    return [
        image.crop((max(0, left - 2), 0, min(image.width, right + 2), image.height))
        for left, right in runs
    ]


def split_contact_sheet(image: Image.Image, expected: int) -> SheetSplit:
    """Slice by transparent runs, falling back to declared equal-width regions."""
    if expected < 1:
        raise ValueError("Expected frame count must be positive")
    image = image.convert("RGBA")
    frames = slice_sheet(image)
    if len(frames) == expected:
        return SheetSplit(frames, "transparent-columns")
    if expected == 1:
        return SheetSplit([image], "single-image")

    # Manual ChatGPT/Gemini outputs often use a fixed 16:9 canvas. The prompt
    # requires equal horizontal regions, so equal-width splitting is a safe,
    # deterministic recovery when transparent gutters are imperfect.
    edges = [round(index * image.width / expected) for index in range(expected + 1)]
    fallback = [
        image.crop((edges[index], 0, edges[index + 1], image.height))
        for index in range(expected)
    ]
    return SheetSplit(
        fallback,
        "equal-width-fallback",
        f"Detected {len(frames)} transparent run{'s' if len(frames) != 1 else ''}; "
        f"used the prompt's {expected} equal horizontal regions instead.",
    )


@dataclass
class NormalizedPack:
    frames: dict[str, list[Image.Image]]
    canvas_width: int
    canvas_height: int
    baseline: int
    character_height: int
    clip_top_fractions: dict[str, float]

    @property
    def manifest(self) -> dict:
        return {
            "characterHeight": self.character_height,
            "canvasHeight": self.canvas_height,
            "canvasWidth": self.canvas_width,
            "baseline": self.baseline,
            "clipTopFractions": self.clip_top_fractions,
        }


def normalize(
    found: dict[str, list[Image.Image]], character_height: int = 470
) -> NormalizedPack:
    measured = {}
    for clip, images in found.items():
        boxes = [box for box in (content_bbox(image) for image in images) if box]
        if not boxes:
            continue
        spec = CLIP_BY_NAME[clip]
        measured[clip] = {
            "height": max(box[3] - box[1] for box in boxes),
            "bottom": max(box[3] for box in boxes),
            "top": min(box[1] for box in boxes),
            "left": min(box[0] for box in boxes),
            "right": max(box[2] for box in boxes),
            "ratio": spec.height_ratio,
        }

    if not measured:
        return NormalizedPack({}, MIN_CANVAS_WIDTH, BASE_CANVAS_HEIGHT,
                              BASE_CANVAS_HEIGHT - BOTTOM_MARGIN, character_height, {})

    for values in measured.values():
        values["scale"] = character_height * values["ratio"] / values["height"]

    widest = max((m["right"] - m["left"]) * m["scale"] for m in measured.values())
    canvas_width = max(MIN_CANVAS_WIDTH, math.ceil(widest) + 32)
    canvas_width += canvas_width % 2
    tallest = max((m["bottom"] - m["top"]) * m["scale"] for m in measured.values())
    canvas_height = max(BASE_CANVAS_HEIGHT, math.ceil(tallest) + BOTTOM_MARGIN + TOP_MARGIN)
    canvas_height += canvas_height % 2
    baseline = canvas_height - BOTTOM_MARGIN

    for values in measured.values():
        reach = (values["bottom"] - values["top"]) * values["scale"]
        available = baseline - TOP_MARGIN
        if reach > available:
            values["scale"] *= available / reach

    output: dict[str, list[Image.Image]] = {}
    for clip, images in found.items():
        if clip not in measured:
            continue
        values = measured[clip]
        scale = values["scale"]
        centre_x = (values["left"] + values["right"]) / 2
        rendered = []
        for original in images:
            # Always resize from the original slice exactly once, with pixel-art sampling.
            scaled = original.convert("RGBA").resize(
                (max(1, round(original.width * scale)), max(1, round(original.height * scale))),
                NEAREST,
            )
            canvas = Image.new("RGBA", (canvas_width, canvas_height), (0, 0, 0, 0))
            offset_x = round(canvas_width / 2 - centre_x * scale)
            if "top" in CLIP_BY_NAME[clip].alignment:
                head_line = baseline - character_height
                offset_y = round(head_line - (values["bottom"] - values["height"]) * scale)
            else:
                # Keep one scale for the whole clip, but anchor each frame's
                # own lowest opaque pixel to the floor. This preserves pose
                # motion while eliminating the classic floating-feet bob.
                frame_box = content_bbox(original)
                frame_bottom = frame_box[3] if frame_box else values["bottom"]
                offset_y = round(baseline - frame_bottom * scale)
            if "left" in CLIP_BY_NAME[clip].alignment:
                offset_x = round(-values["left"] * scale)
            canvas.alpha_composite(scaled, (offset_x, offset_y))
            if "left" in CLIP_BY_NAME[clip].alignment:
                # Rounding during nearest-neighbour scaling can leave a single
                # transparent column. Correct the rendered result so peek is
                # truly flush with the screen edge.
                rendered_box = content_bbox(canvas)
                if rendered_box and rendered_box[0]:
                    corrected = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
                    corrected.alpha_composite(canvas, (-rendered_box[0], 0))
                    canvas = corrected
            rendered.append(canvas)
        output[clip] = rendered

    tops = {}
    for clip, images in output.items():
        values = [box[1] for box in (content_bbox(image) for image in images) if box]
        if values:
            tops[clip] = round(min(values) / canvas_height, 4)
    return NormalizedPack(output, canvas_width, canvas_height, baseline,
                          character_height, tops)


def _foreground_rgb(image: Image.Image) -> np.ndarray:
    rgba = np.asarray(image.convert("RGBA"))
    return rgba[..., :3][rgba[..., 3] > ALPHA_THRESHOLD].astype(np.float32)


def _checkerboard_likely(image: Image.Image) -> bool:
    rgba = np.asarray(image.convert("RGBA"))
    # A real transparent sheet should expose meaningful zero-alpha area.
    if np.mean(rgba[..., 3] <= ALPHA_THRESHOLD) >= 0.01:
        return False
    rgb = rgba[..., :3].reshape(-1, 3)
    if len(rgb) > 120_000:
        rgb = rgb[:: max(1, len(rgb) // 120_000)]
    colors, counts = np.unique(rgb, axis=0, return_counts=True)
    if len(colors) < 2:
        return False
    largest = np.sort(counts)[-2:]
    return largest.sum() / counts.sum() > 0.55 and np.linalg.norm(
        colors[np.argsort(counts)[-1]].astype(float) - colors[np.argsort(counts)[-2]].astype(float)
    ) < 80


def run_qa(
    clip: str,
    raw_frames: list[Image.Image],
    normalized_frames: list[Image.Image],
    reference: Image.Image,
    palette_threshold: float = 95.0,
) -> list[dict]:
    spec = CLIP_BY_NAME[clip]
    checks: list[dict] = []

    count = len(raw_frames)
    count_ok = spec.minimum <= count <= spec.maximum
    checks.append({
        "name": "frame_count", "label": "Frame count", "passed": count_ok,
        "reason": f"{count} frames; expected {spec.minimum}–{spec.maximum}"
        if spec.minimum != spec.maximum else f"{count} frames; expected exactly {spec.minimum}",
    })

    boxes = [content_bbox(frame) for frame in raw_frames]
    heights = [box[3] - box[1] for box in boxes if box]
    median = float(np.median(heights)) if heights else 0
    bad_sizes = [i + 1 for i, box in enumerate(boxes)
                 if box and median and abs((box[3] - box[1]) - median) / median > 0.12]
    checks.append({
        "name": "size_consistency", "label": "Size consistency", "passed": not bad_sizes,
        "reason": "frame sizes agree" if not bad_sizes else
                  f"frame {bad_sizes[0]} is more than 12% different in height",
    })

    nonempty = [i + 1 for i, frame in enumerate(raw_frames)
                if _foreground_rgb(frame).shape[0] < max(16, frame.width * frame.height * 0.0005)]
    checks.append({
        "name": "non_empty", "label": "Non-empty", "passed": not nonempty,
        "reason": "all frames contain artwork" if not nonempty else f"frame {nonempty[0]} is blank or nearly blank",
    })

    opaque = [i + 1 for i, frame in enumerate(raw_frames)
              if np.all(np.asarray(frame.convert("RGBA"))[..., 3] > ALPHA_THRESHOLD)]
    checker = [i + 1 for i, frame in enumerate(raw_frames) if _checkerboard_likely(frame)]
    transparency_ok = not opaque and not checker
    transparency_reason = "background is transparent"
    if checker:
        transparency_reason = f"frame {checker[0]} appears to contain a drawn checkerboard"
    elif opaque:
        transparency_reason = f"frame {opaque[0]} has no transparent background"
    checks.append({"name": "transparency", "label": "Transparency",
                   "passed": transparency_ok, "reason": transparency_reason})

    ref_pixels = _foreground_rgb(reference)
    ref_mean = ref_pixels.mean(axis=0) if len(ref_pixels) else np.zeros(3)
    distances = []
    for frame in raw_frames:
        pixels = _foreground_rgb(frame)
        distances.append(float(np.linalg.norm(pixels.mean(axis=0) - ref_mean)) if len(pixels) else 999.0)
    worst = max(distances, default=999.0)
    checks.append({
        "name": "palette", "label": "Palette", "passed": worst <= palette_threshold,
        "reason": f"palette distance {worst:.0f} (limit {palette_threshold:.0f})",
    })

    nonstanding = {"peek", "focus", "sitting", "sleep"}
    wide = []
    if clip not in nonstanding:
        wide = [i + 1 for i, box in enumerate(boxes)
                if box and (box[2] - box[0]) > (box[3] - box[1])]
    checks.append({
        "name": "aspect", "label": "Aspect sanity", "passed": not wide,
        "reason": "frame proportions look plausible" if not wide else
                  f"frame {wide[0]} is wider than tall; the sheet may not have sliced",
    })

    bottoms = [box[3] - 1 for box in (content_bbox(frame) for frame in normalized_frames) if box]
    foot_ok = not bottoms or max(bottoms) - min(bottoms) <= 1
    checks.append({
        "name": "foot_registration", "label": "Foot registration", "passed": foot_ok,
        "reason": "feet share one baseline" if foot_ok else
                  f"lowest opaque pixels vary by {max(bottoms) - min(bottoms)}px",
    })
    return checks


def save_frames(frames: Iterable[Image.Image], directory: Path, prefix: str = "frame") -> list[str]:
    directory.mkdir(parents=True, exist_ok=True)
    names = []
    for index, frame in enumerate(frames, 1):
        name = f"{prefix}_{index:02d}.png"
        frame.save(directory / name)
        names.append(name)
    return names
