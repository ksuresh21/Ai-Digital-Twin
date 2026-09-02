"""Manual ChatGPT/Gemini prompt, folder-import, review, and build workflow."""

from __future__ import annotations

import re
import tempfile
import time
from pathlib import Path

from PIL import Image

from .clips import CLIPS, CLIP_BY_NAME
from .image_ops import (
    content_bbox,
    normalize,
    open_image,
    remove_background,
    run_qa,
    save_frames,
    slice_sheet,
    split_contact_sheet,
)
from .packaging import build_zip
from .sheets import classify_filename


SUPPORTED_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".tif", ".tiff"}
REFERENCE_STEMS = {"reference", "reference_image", "base_reference", "base-reference"}
MAX_FILES = 100


def _safe_display_name(filename: str) -> str:
    # Browsers may submit a relative directory name for webkitdirectory.
    name = Path(str(filename).replace("\\", "/")).name
    return re.sub(r"[^A-Za-z0-9_. -]", "_", name)[:160] or "image"


def _is_reference(filename: str) -> bool:
    return Path(filename).stem.lower().strip() in REFERENCE_STEMS


def _source_record(upload) -> dict:
    name = _safe_display_name(upload.filename or "")
    return {"upload": upload, "name": name, "suffix": Path(name).suffix.lower()}


class ManualWorkflow:
    def __init__(self, store):
        self.store = store

    def import_folder(self, session_id: str, uploads: list) -> dict:
        state = self.store.load(session_id)
        if state.get("mode") != "manual":
            raise ValueError("This session does not accept manual folder imports")
        if not uploads:
            raise ValueError("Choose the folder containing reference.png and the generated sheets")
        if len(uploads) > MAX_FILES:
            raise ValueError(f"The selected folder contains too many files (maximum {MAX_FILES})")

        records = [_source_record(upload) for upload in uploads]
        supported = [record for record in records if record["suffix"] in SUPPORTED_EXTENSIONS]
        ignored = [record["name"] for record in records if record["suffix"] not in SUPPORTED_EXTENSIONS]
        references = [record for record in supported if _is_reference(record["name"])]
        if not references:
            raise ValueError(
                "The folder has no reference image. Save the generated base sprite as reference.png."
            )
        if len(references) > 1:
            raise ValueError("The folder contains more than one file named as the reference image")

        grouped: dict[str, list[dict]] = {}
        unknown = []
        for record in supported:
            if record is references[0]:
                continue
            clip = classify_filename(record["name"])
            if clip:
                grouped.setdefault(clip, []).append(record)
            else:
                unknown.append(record["name"])

        selected = set(state["config"]["clips"])
        warnings = []
        if ignored:
            warnings.append(f"Ignored {len(ignored)} unsupported file(s): {', '.join(ignored[:4])}")
        if unknown:
            warnings.append(f"Could not match {len(unknown)} image(s): {', '.join(unknown[:4])}")

        path = self.store.path(session_id)
        with tempfile.TemporaryDirectory(prefix="manual-import-", dir=str(path)) as temporary:
            staging = Path(temporary)
            reference = self._read_upload(references[0], staging / "reference-upload")
            reference_cleanup = remove_background(reference)
            if content_bbox(reference_cleanup.image) is None:
                raise ValueError("reference.png is empty after background processing")

            reference.convert("RGBA").save(path / "sources" / "reference.png")
            reference_cleanup.image.save(path / "reference.png")

            updates: dict[str, dict] = {}
            for spec in CLIPS:
                if spec.name not in selected:
                    continue
                candidates = grouped.get(spec.name, [])
                if not candidates:
                    updates[spec.name] = {
                        "status": "awaiting",
                        "error": f"No {spec.name} image found. Expected {spec.name}.png.",
                        "frames": [], "qa": [], "sheet": None, "sourceSheet": None,
                        "cleanup": None, "split": None,
                    }
                    continue
                try:
                    chosen, note = self._choose_candidates(spec.name, candidates)
                    if note:
                        warnings.append(note)
                    update = self._process_clip(path, staging, spec.name, chosen)
                    updates[spec.name] = update
                except Exception as exc:
                    updates[spec.name] = {
                        "status": "failed", "error": str(exc), "frames": [], "qa": [],
                        "sheet": None, "sourceSheet": None, "cleanup": None, "split": None,
                    }

        imported = sorted(name for name, item in updates.items() if item["status"] == "ready")
        missing = sorted(name for name, item in updates.items() if item["status"] == "awaiting")
        failed = sorted(name for name, item in updates.items() if item["status"] == "failed")
        reference_state = {
            "method": reference_cleanup.method,
            "changed": reference_cleanup.changed,
            "removedFraction": round(reference_cleanup.removed_fraction, 4),
            "warning": reference_cleanup.warning,
        }

        def merge(current):
            current.update(
                stage="review", running=False, runError=None, build=None,
                reference=f"/media/{session_id}/reference.png",
                referenceSource=f"/media/{session_id}/sources/reference.png",
                referenceCleanup=reference_state,
                lastImport={
                    "imported": imported, "missing": missing, "failed": failed,
                    "warnings": warnings, "importedAt": int(time.time() * 1000),
                },
            )
            for name, values in updates.items():
                current["clips"][name].update(values)

        self.store.mutate(session_id, merge)
        self.refresh_previews(session_id)
        return self.store.load(session_id)

    @staticmethod
    def _choose_candidates(clip: str, candidates: list[dict]) -> tuple[list[dict], str | None]:
        exact = [item for item in candidates if Path(item["name"]).stem.lower() == clip]
        if exact:
            note = None
            if len(candidates) > 1:
                ignored = [item["name"] for item in candidates if item not in exact]
                note = f"Used {exact[0]['name']} for {clip}; ignored aliases: {', '.join(ignored)}"
            return [exact[0]], note
        return candidates, None

    @staticmethod
    def _read_upload(record: dict, destination: Path) -> Image.Image:
        upload = record["upload"]
        upload.stream.seek(0)
        try:
            image = open_image(upload.stream)
        except Exception as exc:
            raise ValueError(f"Could not read {record['name']} as an image: {exc}") from exc
        if image.width < 8 or image.height < 8:
            raise ValueError(f"{record['name']} is too small to process")
        if image.width * image.height > 50_000_000:
            raise ValueError(f"{record['name']} is larger than the 50-megapixel safety limit")
        image.save(destination.with_suffix(".png"))
        return image

    def _process_clip(self, path: Path, staging: Path, clip: str, records: list[dict]) -> dict:
        spec = CLIP_BY_NAME[clip]
        cleaned_images = []
        cleanup_records = []
        source_images = []
        for index, record in enumerate(records, 1):
            source = self._read_upload(record, staging / f"{clip}-{index}")
            source_images.append(source)
            cleanup = remove_background(source)
            cleaned_images.append(cleanup.image)
            cleanup_records.append(cleanup)

        # Preserve exactly what the user selected behind "show original".
        source_sheet = source_images[0] if len(source_images) == 1 else self._join(source_images)
        source_sheet.save(path / "sources" / f"{clip}.png")

        if len(cleaned_images) == 1:
            cleaned_sheet = cleaned_images[0]
            split = split_contact_sheet(cleaned_sheet, spec.ask)
            frames = split.frames
            split_method = split.method
            split_warning = split.warning
        else:
            cleaned_sheet = self._join(cleaned_images)
            frames = []
            for image in cleaned_images:
                frames.extend(slice_sheet(image))
            split_method = "multiple-files"
            split_warning = None

        # Run the conservative edge-connected cleanup again on each isolated
        # region. This catches residual matte colours that were not connected
        # to the outer edge of the complete contact sheet.
        frame_cleanups = [remove_background(frame) for frame in frames]
        frames = [item.image for item in frame_cleanups]
        cleanup_records.extend(frame_cleanups)

        if not frames or not any(content_bbox(frame) for frame in frames):
            raise ValueError(f"{clip} contains no usable character artwork")
        cleaned_sheet.save(path / "raw" / f"{clip}.png")

        slice_dir = path / "slices" / clip
        slice_dir.mkdir(parents=True, exist_ok=True)
        for old in slice_dir.glob("*.png"):
            old.unlink()
        save_frames(frames, slice_dir, "raw")

        removed = max((item.removed_fraction for item in cleanup_records), default=0.0)
        unresolved = [item.warning for item in cleanup_records if item.warning]
        cleanup_state = {
            "changed": any(item.changed for item in cleanup_records),
            "method": ", ".join(sorted({item.method for item in cleanup_records})),
            "removedFraction": round(removed, 4),
            "warning": unresolved[0] if unresolved else None,
        }
        return {
            "status": "ready", "error": None, "backend": "manual",
            "sheet": f"/media/{path.name}/raw/{clip}.png",
            "sourceSheet": f"/media/{path.name}/sources/{clip}.png",
            "cleanup": cleanup_state,
            "split": {"method": split_method, "warning": split_warning},
            "attempts": [{
                "backend": "manual", "sourceFiles": [item["name"] for item in records],
                "cost": {"currency": "USD", "amount": 0, "note": "generated manually"},
            }],
        }

    @staticmethod
    def _join(images: list[Image.Image], gap: int = 16) -> Image.Image:
        height = max(image.height for image in images)
        width = sum(image.width for image in images) + gap * (len(images) - 1)
        result = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        x = 0
        for image in images:
            result.alpha_composite(image.convert("RGBA"), (x, 0))
            x += image.width + gap
        return result

    def _load_raw_frames(self, session_id: str, state: dict | None = None) -> dict[str, list[Image.Image]]:
        state = state or self.store.load(session_id)
        path = self.store.path(session_id)
        result = {}
        for clip, item in state["clips"].items():
            if item["status"] != "ready":
                continue
            files = sorted((path / "slices" / clip).glob("raw_*.png"))
            if files:
                result[clip] = [open_image(file) for file in files]
        return result

    def refresh_previews(self, session_id: str) -> None:
        state = self.store.load(session_id)
        path = self.store.path(session_id)
        raw = self._load_raw_frames(session_id, state)
        normalized = normalize(raw, state["config"]["height"])
        reference = open_image(path / "reference.png")
        updates = {}
        for clip, frames in normalized.frames.items():
            frame_dir = path / "frames" / clip
            frame_dir.mkdir(parents=True, exist_ok=True)
            for old in frame_dir.glob("*.png"):
                old.unlink()
            names = save_frames(frames, frame_dir, CLIP_BY_NAME[clip].prefix)
            checks = run_qa(clip, raw[clip], frames, reference)
            item = state["clips"][clip]
            cleanup = item.get("cleanup") or {}
            checks.insert(0, {
                "name": "background_cleanup", "label": "Background cleanup",
                "passed": not cleanup.get("warning"),
                "reason": cleanup.get("warning") or (
                    "existing transparency preserved" if not cleanup.get("changed")
                    else f"removed {cleanup.get('removedFraction', 0):.0%} edge-connected background"
                ),
            })
            split = item.get("split") or {}
            if split.get("warning"):
                checks.insert(1, {
                    "name": "sheet_split", "label": "Sheet split", "passed": False,
                    "reason": split["warning"],
                })
            updates[clip] = {
                "frames": [f"/media/{session_id}/frames/{clip}/{name}" for name in names],
                "qa": checks,
            }

        def merge(current):
            for clip, values in updates.items():
                current["clips"][clip].update(values)

        self.store.mutate(session_id, merge)

    def set_included(self, session_id: str, clip: str, included: bool) -> dict:
        if clip not in CLIP_BY_NAME:
            raise ValueError("Unknown clip")
        if clip == "idle" and not included:
            raise ValueError("Idle is required and cannot be excluded")
        def update(state):
            state["clips"][clip]["included"] = bool(included)
            state["build"] = None

        return self.store.mutate(session_id, update)

    def build(self, session_id: str):
        state = self.store.load(session_id)
        path = self.store.path(session_id)
        all_frames = self._load_raw_frames(session_id, state)
        frames = {
            clip: images for clip, images in all_frames.items()
            if state["clips"][clip]["included"] and state["clips"][clip]["status"] == "ready"
        }
        details = {
            clip: {
                "status": item["status"], "included": item["included"],
                "backend": "manual", "checks": item["qa"], "attempts": item["attempts"],
                "cleanup": item.get("cleanup"), "split": item.get("split"),
            }
            for clip, item in state["clips"].items()
        }
        output = path / f"{state['config']['name']}.zip"
        zip_path, summary, _ = build_zip(
            state["config"]["name"], path / "reference.png", frames, output,
            state["config"]["height"], details, force=True,
        )
        result = {
            "zip": f"/media/{session_id}/{zip_path.name}",
            "report": f"/media/{session_id}/report.json",
            "summary": summary,
        }
        self.store.mutate(session_id, lambda current: current.update(build=result, stage="build"))
        return zip_path, result
