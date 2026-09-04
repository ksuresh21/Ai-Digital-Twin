"""Which drawing of her to show.

The folder names here are the same ones `AiTwin/Resources/Characters/<Name>/`
already uses — Idle, Waving, Walking, Concerned, Cheer and so on — so a pack
generated for the Swift app drops straight in here, and anything drawn for here
drops straight into the Swift app. That is not a coincidence, it is the point:
one set of art, two consumers.

Four folders are new, because a companion who talks needs states a reminder
companion never did: Talking, Listening, Thinking, Greeting.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path

#: Where packs are looked for, in order. The second entry is the point of this
#: list: the Swift app's own character folders, read in place rather than
#: copied. ARCHITECTURE.md claims "one set of art, two consumers" — this is
#: what makes that true instead of aspirational. Copying would mean 11MB
#: duplicated in the repo and two folders to keep in step.
_HERE = Path(__file__).resolve().parent.parent.parent
PACK_ROOTS: list[Path] = [
    _HERE / "assets" / "characters",
    _HERE.parent / "AiTwin" / "Resources" / "Characters",
    *(Path(p).expanduser() for p in
      os.environ.get("SORAYA_PACKS", "").split(os.pathsep) if p.strip()),
]


def pack_roots() -> list[Path]:
    """The roots that actually exist, deduplicated and resolved."""
    seen: set[Path] = set()
    out: list[Path] = []
    for root in PACK_ROOTS:
        try:
            resolved = root.resolve()
        except OSError:
            continue
        if resolved in seen or not resolved.is_dir():
            continue
        seen.add(resolved)
        out.append(resolved)
    return out


def find_pack(name: str) -> Path | None:
    """The directory for a named pack, searching the roots in order.

    First root wins, so a pack of your own in `assets/characters/` shadows one
    of the same name in the Swift app's folder rather than fighting it.
    """
    # A pack name comes from settings and from the browser, so it must not be
    # able to address a directory outside a root.
    if not name or "/" in name or "\\" in name or name.startswith("."):
        return None
    for root in pack_roots():
        candidate = root / name
        if candidate.is_dir():
            return candidate
    return None


def available_packs() -> list[tuple[str, Path]]:
    """Every pack across every root, first occurrence of a name winning."""
    found: dict[str, Path] = {}
    for root in pack_roots():
        for entry in sorted(root.iterdir()):
            if entry.is_dir() and not entry.name.startswith("."):
                found.setdefault(entry.name, entry)
    return sorted(found.items())

#: clip name -> (folder, file prefix, loops). Mirrors `ClipName.swift`.
CLIPS: dict[str, tuple[str, str, bool]] = {
    # Shared with the Swift app.
    "idle": ("Idle", "idle", True),
    "walk": ("Walking", "walk", True),
    "wave": ("Waving", "wave", False),
    "concerned": ("Concerned", "concerned", True),
    "cheer": ("Cheer", "cheer", False),
    "happy": ("HappyMood", "happy", False),
    "peek": ("Peek", "peek", True),
    "sleep": ("Sleep", "sleep", True),
    "yawn": ("Yawn", "yawn", False),
    "focus": ("Focus", "focus", True),
    "sitting": ("Sitting", "sitting", True),
    "stretch": ("Stretch", "stretch", True),
    # New for the conversational phase.
    "talking": ("Talking", "talk", True),
    "listening": ("Listening", "listen", True),
    "thinking": ("Thinking", "think", True),
    "greeting": ("Greeting", "greet", False),
}

#: clip -> what to play instead when a pack has no frames for it, best first.
#:
#: Blanket "fall back to idle" was the first version and it wastes the pack.
#: The AiTwin packs predate the conversational clips, so on `Nish` all four of
#: `talking`, `listening`, `thinking` and `greeting` were missing — and idle for
#: all four means she stands perfectly still through a whole exchange. With a
#: chain, greeting plays her real Waving frames and thinking plays Focus, which
#: is her reading pose and close enough to be right.
FALLBACKS: dict[str, tuple[str, ...]] = {
    "talking":   ("idle",),
    "listening": ("idle",),
    "thinking":  ("focus", "sitting", "idle"),
    "greeting":  ("wave", "happy", "idle"),
    "cheer":     ("happy", "wave", "idle"),
    "happy":     ("cheer", "wave", "idle"),
    "focus":     ("sitting", "idle"),
    "sitting":   ("focus", "idle"),
    "concerned": ("idle",),
    "peek":      ("idle",),
    "stretch":   ("idle",),
    "yawn":      ("sleep", "idle"),
    "sleep":     ("yawn", "idle"),
    "wave":      ("happy", "idle"),
    "walk":      ("idle",),
}

#: posture -> clip. The postures come from `emotion.POSTURES`; keeping the
#: mapping here rather than in the emotion module means how she *looks* can be
#: retuned without touching how she *decides*.
POSTURE_CLIPS: dict[str, str] = {
    "retreat": "idle",
    "hold": "concerned",
    "ground": "concerned",
    "support": "concerned",
    "lift": "idle",
    "celebrate": "cheer",
    "answer": "talking",
    "banter": "talking",
}


def clip_for(posture: str, *, state: str = "reply") -> str:
    """The clip for a posture at a moment in the exchange.

    `state` is where we are in the turn: "listening" while you type or speak,
    "thinking" while the model works, "reply" once she has words. The posture
    only gets a say in the last of those — she should not look concerned before
    she has heard you.
    """
    if state == "listening":
        return "listening"
    if state == "thinking":
        return "thinking"
    if state == "greeting":
        return "greeting"
    return POSTURE_CLIPS.get(posture, "talking")


@dataclass
class Sprite:
    """A character pack on disk, resolved to frame paths."""

    root: Path

    @property
    def name(self) -> str:
        return self.root.name

    def frames(self, clip: str) -> list[Path]:
        """Every frame of a clip, in order, or [] if the clip is missing.

        Sorted numerically rather than lexically. Lexical sort puts frame 10
        before frame 2, which is a bug that looks like bad animation rather
        than like a sorting mistake, so it survives for ages.
        """
        entry = CLIPS.get(clip)
        if entry is None:
            return []
        folder, prefix, _ = entry
        directory = self.root / folder
        if not directory.is_dir():
            return []
        found = [
            path for path in directory.iterdir()
            if path.suffix.lower() == ".png" and not path.name.startswith(".")
        ]

        def order(path: Path) -> tuple[int, str]:
            digits = re.findall(r"(\d+)", path.stem)
            return (int(digits[-1]) if digits else 0, path.name)

        return sorted(found, key=order)

    def resolve(self, clip: str) -> tuple[str, list[Path]]:
        """The clip if it has frames, else the best substitute in its chain.

        Returns which clip was actually used, not just its frames, so the
        interface can say "this pack has no Thinking frames, using Focus"
        rather than leaving someone wondering why she never changes pose.
        """
        frames = self.frames(clip)
        if frames:
            return clip, frames
        for substitute in FALLBACKS.get(clip, ("idle",)):
            frames = self.frames(substitute)
            if frames:
                return substitute, frames
        return "idle", self.frames("idle")

    def missing_clips(self) -> list[str]:
        return [name for name in CLIPS if not self.frames(name)]

    def manifest(self) -> dict[str, list[str]]:
        """clip -> web-relative frame paths, for the browser to preload.

        Every clip in `CLIPS` gets an entry, resolved through the fallback
        chain. That keeps the chain in exactly one place: the browser asks for
        `thinking` and gets whatever this pack's best answer is, without
        needing a second copy of the substitution rules in JavaScript.
        """
        out: dict[str, list[str]] = {}
        for clip in CLIPS:
            _, frames = self.resolve(clip)
            if frames:
                out[clip] = [f"{self.name}/{p.parent.name}/{p.name}" for p in frames]
        return out

    def substitutions(self) -> dict[str, str]:
        """clip -> what is really playing, for clips this pack does not have."""
        out: dict[str, str] = {}
        for clip in CLIPS:
            used, frames = self.resolve(clip)
            if frames and used != clip:
                out[clip] = used
        return out
