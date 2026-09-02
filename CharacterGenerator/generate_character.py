#!/usr/bin/env python3
"""Secondary CLI for generating and packaging AiTwin characters."""

import argparse
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

import yaml
from PIL import Image

from character_generator.backends import available_backend_names
from character_generator.clips import CLIPS, CLIP_BY_NAME
from character_generator.environment import load_local_env
from character_generator.image_ops import normalize, run_qa, slice_sheet
from character_generator.packaging import build_zip, validate_pack_name
from character_generator.prompts import assemble_prompts
from character_generator.session import GenerationManager, SessionStore
from character_generator.sheets import load_sheets


def parse_clips(value: str) -> list[str]:
    clips = [part.strip().lower() for part in value.split(",") if part.strip()]
    unknown = [clip for clip in clips if clip not in CLIP_BY_NAME]
    if unknown:
        raise argparse.ArgumentTypeError(f"unknown clip(s): {', '.join(unknown)}")
    if len(set(clips)) != len(clips):
        raise argparse.ArgumentTypeError("clip names must not be repeated")
    return clips


def load_sheet(path: str | None) -> dict:
    if not path:
        return {}
    with Path(path).expanduser().open(encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    if not isinstance(data, dict):
        raise ValueError("Character sheet YAML must contain a mapping of field names to values")
    return data


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description="Generate an installable AiTwin character pack")
    result.add_argument("reference", help="reference.png supplied by the user")
    result.add_argument("--name", required=True, help="pack/folder name")
    result.add_argument("--out", help="output zip (default: <NAME>.zip)")
    result.add_argument("--sheet", help="character sheet YAML")
    result.add_argument("--clips", type=parse_clips,
                        default=[clip.name for clip in CLIPS], help="comma-separated clips")
    result.add_argument("--backend", choices=["openai", "gemini", "cloudflare"], default="openai")
    result.add_argument("--height", type=int, default=470, help="standing character height")
    result.add_argument("--dry-run", action="store_true", help="print prompts and call nothing")
    result.add_argument("--from-sheets", help="skip generation and read sheets from this directory")
    result.add_argument("--force", action="store_true", help="replace an existing output zip")
    return result


def main(argv=None) -> int:
    load_local_env(Path(__file__).resolve().parent / ".env")
    args = parser().parse_args(argv)
    try:
        name = validate_pack_name(args.name)
        if args.height < 32 or args.height > 4096:
            raise ValueError("--height must be between 32 and 4096")
        reference = Path(args.reference).expanduser().resolve()
        if not reference.is_file():
            raise FileNotFoundError(f"Reference image not found: {reference}")
        Image.open(reference).verify()
        sheet = load_sheet(args.sheet)
        prompts = assemble_prompts(sheet)
        if args.dry_run:
            for index, clip in enumerate(args.clips, 1):
                print(f"\n===== {index:02d}/{len(args.clips):02d} {clip.upper()} =====\n")
                print(prompts[clip])
            return 0

        output = Path(args.out or f"{name}.zip").expanduser().resolve()
        if output.exists() and not args.force:
            raise FileExistsError(f"Output already exists: {output}. Use --force to replace it.")

        if args.from_sheets:
            frames = load_sheets(Path(args.from_sheets).expanduser(), set(args.clips))
            preview = normalize(frames, args.height)
            reference_art = Image.open(reference).convert("RGBA")
            details = {
                clip: {
                    "backend": "from-sheets",
                    "checks": run_qa(clip, raw, preview.frames.get(clip, []), reference_art),
                    "cost": {"currency": "USD", "amount": 0, "note": "no API call"},
                }
                for clip, raw in frames.items()
            }
        else:
            available = available_backend_names()
            if args.backend == "gemini" and "gemini" not in available:
                raise RuntimeError("GEMINI_API_KEY was not found in the environment")
            if args.backend == "cloudflare" and "cloudflare" not in available:
                raise RuntimeError("Cloudflare account ID or API token was not found in the environment")
            if args.backend == "openai" and not available:
                raise RuntimeError("Neither OPENAI_API_KEY nor GEMINI_API_KEY was found in the environment")
            with tempfile.TemporaryDirectory(prefix="aitwin-cli-") as temporary:
                store = SessionStore(Path(temporary))
                state = store.create(reference, {
                    "name": name, "height": args.height, "clips": args.clips,
                    "backend": args.backend, "sheet": sheet,
                })
                manager = GenerationManager(store)
                manager._generate_all(state["id"])
                final = store.load(state["id"])
                frames = {}
                details = {}
                for clip, item in final["clips"].items():
                    raw = store.path(state["id"]) / "raw" / f"{clip}.png"
                    if item["status"] == "ready" and raw.exists():
                        frames[clip] = slice_sheet(Image.open(raw).convert("RGBA"))
                    details[clip] = item
                build_zip(name, reference, frames, output, args.height, details, args.force)
                print(f"Wrote {output}")
                return 0

        build_zip(name, reference, frames, output, args.height, details, args.force)
        print(f"Wrote {output}")
        print(f"Wrote {output.with_name('report.json')}")
        return 0
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
