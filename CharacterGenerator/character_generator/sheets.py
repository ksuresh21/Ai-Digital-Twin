"""Find contact sheets in a directory without relying on network generation."""

import re
from pathlib import Path

from PIL import Image

from .clips import CLIPS


KEYWORDS = {
    "idle": ["idle", "stand", "breath"],
    "walk": ["walking", "walk"],
    "wave": ["waving", "wave", "greet"],
    "drink": ["waterreminder", "water", "drink", "hydrat"],
    "eyebreak": ["eyebreak", "eye_break", "eyerest"],
    "sleep": ["sleeping", "sleep", "tired"],
    "happy": ["happymood", "happy", "pleased"],
    "focus": ["focus", "reading", "pomodoro"],
    "stretch": ["stretch", "posture"],
    "sitting": ["sitting", "seated"],
    "concerned": ["concerned", "worried", "worry"],
    "cheer": ["cheer", "celebrate", "milestone"],
    "peek": ["peek", "peeking", "hiding"],
    "yawn": ["yawn", "yawning", "drowsy"],
}


def natural_key(path: Path):
    return [int(part) if part.isdigit() else part.lower()
            for part in re.split(r"(\d+)", str(path))]


def classify(path: Path, root: Path) -> str | None:
    text = str(path.relative_to(root)).lower()
    return classify_filename(text)


def classify_filename(filename: str) -> str | None:
    text = str(filename).replace("\\", "/").lower()
    best = None
    best_length = 0
    for clip in CLIPS:
        for keyword in KEYWORDS[clip.name]:
            if keyword in text and len(keyword) > best_length:
                best = clip.name
                best_length = len(keyword)
    return best


def load_sheets(directory: Path, requested: set[str] | None = None) -> dict[str, list[Image.Image]]:
    directory = directory.resolve()
    if not directory.is_dir():
        raise FileNotFoundError(f"No sheets directory: {directory}")
    grouped: dict[str, list[Path]] = {}
    for path in sorted(directory.rglob("*"), key=natural_key):
        if not path.is_file() or path.suffix.lower() not in {".png", ".tif", ".tiff"}:
            continue
        clip = classify(path, directory)
        if clip and (requested is None or clip in requested):
            grouped.setdefault(clip, []).append(path)

    from .image_ops import slice_sheet
    result = {}
    for clip, paths in grouped.items():
        images = []
        for path in paths:
            images.extend(slice_sheet(Image.open(path).convert("RGBA")))
        result[clip] = images
    return result
