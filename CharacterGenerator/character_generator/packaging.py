"""Build AiTwin-compatible pack folders, manifests, reports, and zip files."""

import json
import re
import tempfile
import zipfile
from pathlib import Path

from PIL import Image

from .clips import CLIPS, CLIP_BY_NAME, FALLBACK_MESSAGES
from .image_ops import NormalizedPack, normalize


SAFE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 _.-]{0,79}$")


def validate_pack_name(name: str) -> str:
    name = name.strip()
    if not SAFE_NAME.fullmatch(name) or name in {".", ".."}:
        raise ValueError("Pack name must use letters, numbers, spaces, dots, dashes, or underscores")
    return name


def build_zip(
    name: str,
    reference: Path,
    frames: dict[str, list[Image.Image]],
    output_zip: Path,
    character_height: int = 470,
    report_details: dict | None = None,
    force: bool = False,
) -> tuple[Path, dict, NormalizedPack]:
    name = validate_pack_name(name)
    if "idle" not in frames or not frames["idle"]:
        raise ValueError("Idle must be ready and included before building a pack")
    output_zip = output_zip.resolve()
    output_zip.parent.mkdir(parents=True, exist_ok=True)
    if output_zip.exists() and not force:
        raise FileExistsError(f"Output already exists: {output_zip}. Use --force to replace it.")

    normalized = normalize(frames, character_height)
    included = [clip.name for clip in CLIPS if clip.name in normalized.frames]
    excluded = [clip.name for clip in CLIPS if clip.name not in normalized.frames]
    summary = {
        "pack": name,
        "included": included,
        "excluded": [{"clip": clip, "fallback": FALLBACK_MESSAGES[clip]} for clip in excluded],
        "frameCount": sum(len(images) for images in normalized.frames.values()),
        "canvas": [normalized.canvas_width, normalized.canvas_height],
    }
    report = {
        "pack": name,
        "summary": summary,
        "clips": report_details or {},
    }

    with tempfile.TemporaryDirectory(prefix="aitwin-pack-", dir=str(output_zip.parent)) as temp:
        root = Path(temp) / name
        root.mkdir()
        (root / "pack.json").write_text(
            json.dumps(normalized.manifest, indent=2), encoding="utf-8"
        )
        Image.open(reference).convert("RGBA").save(root / "reference.png")
        for clip_name, images in normalized.frames.items():
            spec = CLIP_BY_NAME[clip_name]
            folder = root / spec.folder
            folder.mkdir(parents=True, exist_ok=True)
            for index, image in enumerate(images, 1):
                image.save(folder / f"{spec.prefix}_{index:02d}.png")
        temp_zip = Path(temp) / f".{name}.zip"
        with zipfile.ZipFile(temp_zip, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(root.rglob("*")):
                if path.is_file():
                    archive.write(path, path.relative_to(root.parent))
        temp_zip.replace(output_zip)

    report_path = output_zip.with_name("report.json")
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    return output_zip, summary, normalized
