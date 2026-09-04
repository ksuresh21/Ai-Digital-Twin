#!/usr/bin/env python3
"""Copies a character pack into Soraya's own assets folder.

Soraya can read the Swift app's packs where they sit, which costs nothing and
duplicates nothing. Copying is for one specific reason: it makes this folder
**self-contained**, so `Soraya/` can be moved or shipped on its own without
`../AiTwin/Resources/Characters/` next to it.

    python3 scripts/import_pack.py --from Nish --to Soraya --replace

Only clips Soraya actually uses are copied — the Swift app's `EyeBreak` and
`WaterReminder` are skipped, since she does not do reminders. Clips the source
pack lacks are left absent on purpose rather than filled with copies of other
folders: `presence/sprite.py` already substitutes the nearest pose, and a
duplicated folder would be the same pixels under a second name.

Safety, because this script overwrites artwork:

* Without `--replace` nothing already in the target is touched.
* With `--replace`, existing frames are removed **only after** every new frame
  has been written and verified readable. The order matters — the point is that
  a failure halfway through leaves you with the old art, not with neither.
* It refuses to run if the source has no frames at all.
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from soraya.presence.sprite import CLIPS, Sprite, find_pack  # noqa: E402


def resolve_source(name: str) -> Path | None:
    """A pack name searched across the roots, or a direct path."""
    direct = Path(name).expanduser()
    if direct.is_dir():
        return direct
    return find_pack(name)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--from", dest="source", required=True,
                        help="pack name or path to copy from")
    parser.add_argument("--to", dest="target", default="Soraya",
                        help="pack name under assets/characters (default: Soraya)")
    parser.add_argument("--replace", action="store_true",
                        help="remove frames the source does not provide, "
                             "after the new ones are verified")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    source_dir = resolve_source(args.source)
    if source_dir is None:
        print(f"  ✗ no pack called {args.source!r}, and no such directory")
        return 1

    source = Sprite(source_dir)
    plan: list[tuple[Path, Path]] = []
    target_dir = ROOT / "assets" / "characters" / args.target

    for clip, (folder, _prefix, _loops) in CLIPS.items():
        frames = source.frames(clip)
        if not frames:
            continue
        for frame in frames:
            plan.append((frame, target_dir / folder / frame.name))

    if not plan:
        # Guard against the worst case: wiping real art in exchange for
        # nothing, because the source folder was empty or misnamed.
        print(f"  ✗ {source_dir} has no frames for any clip Soraya uses.")
        print("    Refusing to replace anything with nothing.")
        return 1

    missing = source.missing_clips()
    total_mb = sum(src.stat().st_size for src, _ in plan) / 1e6
    print(f"  from : {source_dir}")
    print(f"  to   : {target_dir}")
    print(f"  {len(plan)} frames across {len({d.parent for _, d in plan})} clips, "
          f"{total_mb:.1f} MB")
    if missing:
        print(f"  not in the source ({len(missing)}): {', '.join(missing)}")
        print("    left absent — the fallback chain substitutes the nearest pose")

    if args.dry_run:
        print("\n  --dry-run, nothing written")
        return 0

    # 1. Write everything new first.
    written: set[Path] = set()
    for src, dst in plan:
        dst.parent.mkdir(parents=True, exist_ok=True)
        if dst.exists() and not args.replace and dst.stat().st_size:
            continue
        shutil.copy2(src, dst)
        written.add(dst.resolve())

    # 2. Verify before removing anything. This is the whole safety argument:
    #    if a copy silently failed, the old art is still there.
    unreadable = [
        dst for _, dst in plan
        if not dst.is_file() or dst.stat().st_size == 0
    ]
    if unreadable:
        print(f"\n  ✗ {len(unreadable)} frames did not copy. Nothing removed.")
        for dst in unreadable[:5]:
            print(f"      {dst}")
        return 1

    # 3. Only now clear out what the source did not provide.
    removed = 0
    if args.replace:
        keep = {dst.resolve() for _, dst in plan}
        for clip, (folder, _prefix, _loops) in CLIPS.items():
            directory = target_dir / folder
            if not directory.is_dir():
                continue
            for existing in directory.glob("*.png"):
                if existing.resolve() not in keep:
                    existing.unlink()
                    removed += 1
            if not any(directory.glob("*.png")):
                directory.rmdir()

    result = Sprite(target_dir)
    print(f"\n  ✓ {len(written)} frames written"
          + (f", {removed} stale frames removed" if removed else ""))
    print(f"    {args.target} now covers {len(result.manifest())} of "
          f"{len(CLIPS)} clips")
    swaps = result.substitutions()
    if swaps:
        print("    substituting: "
              + ", ".join(f"{a} → {b}" for a, b in swaps.items()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
