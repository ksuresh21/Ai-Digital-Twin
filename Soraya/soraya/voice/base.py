"""The voice seam.

Speaking is a side effect on hardware, so it sits behind a protocol like every
other side effect in this project — which is what lets the tests assert "she
would have said this, at this volume, and stayed silent at 2am" without a
speaker in the room.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol, runtime_checkable


@runtime_checkable
class Speaker(Protocol):
    def say(self, text: str, *, rate: int = 165, volume: float = 0.8,
            voice: str = "") -> bool:
        """Speaks. Returns whether anything was actually said."""
        ...

    def stop(self) -> None:
        """Cuts off mid-sentence. Needed the moment the user starts typing."""
        ...

    @property
    def is_speaking(self) -> bool: ...


@dataclass
class SilentSpeaker:
    """Says nothing and records what it would have said.

    The default when voice is off, and what the tests use.
    """

    spoken: list[str] = field(default_factory=list)

    def say(self, text: str, *, rate: int = 165, volume: float = 0.8,
            voice: str = "") -> bool:
        self.spoken.append(text)
        return False

    def stop(self) -> None:
        return None

    @property
    def is_speaking(self) -> bool:
        return False


def speech_text(reply: str, limit: int = 320) -> str:
    """Trims a reply down to what is worth saying out loud.

    Written text and spoken text are not the same thing. Markdown read aloud
    is gibberish, and a long paragraph that is fine to skim is interminable to
    listen to — so the voice gets the first few sentences, cleaned.

    This also strips `[[...]]`, which is not cosmetic. macOS `say` parses that
    as an embedded speech command, and it is verifiable: rendering
    "hello [[rate 500]] world" produces 28% less audio than "hello world"
    because the command was obeyed rather than spoken. Since the volume is
    passed to `say` as exactly such a command, a reply containing `[[` could
    change her rate, pitch or volume mid-sentence — her own output steering her
    own voice.
    """
    import re

    text = reply.strip()
    text = re.sub(r"\[\[.*?\]\]", " ", text, flags=re.DOTALL)
    # Any unpaired brackets left over would still open a command.
    text = text.replace("[[", " ").replace("]]", " ")
    # Strip the markdown she is told not to use but may produce anyway.
    text = re.sub(r"[*_`#>]+", "", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) <= limit:
        return text
    # Cut at a sentence end rather than mid-word, so it does not sound like
    # the audio dropped out.
    cut = text[:limit]
    for mark in (". ", "! ", "? "):
        index = cut.rfind(mark)
        if index > limit * 0.5:
            return cut[: index + 1].strip()
    return cut.rsplit(" ", 1)[0] + "…"
