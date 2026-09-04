"""Everything the user can change, persisted as one JSON file.

Deliberately the same shape as `AiTwinSettings` in the Swift app: one struct,
one file, tolerant loading. A field missing from the file falls back to its
default rather than failing the whole load, so adding a setting in a later
version cannot wipe someone's configuration.
"""

from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass, field, fields
from pathlib import Path
from typing import Any

# Where state lives. Kept out of the repo so a `git clean` cannot delete
# someone's memories, and out of the app bundle so an app update cannot either.
HOME = Path(os.environ.get("SORAYA_HOME", Path.home() / ".soraya"))


@dataclass
class VoiceSettings:
    """Her voice. Off by default — see the note on `enabled`."""

    # Off until asked for. A companion that starts talking out loud the first
    # time you run it is a companion you turn off and never turn back on; the
    # first thing this must never do is embarrass you in a meeting.
    enabled: bool = False
    # macOS voice name. `say -v ?` lists them. Empty means the system default.
    name: str = ""
    # Words per minute. macOS default is ~175; a companion reads better slower.
    rate: int = 165
    # 0..1, applied by the player.
    volume: float = 0.8
    # Never speak during these hours, even with voice on. Mirrors the Swift
    # app's quiet hours so the two cannot disagree about when to shut up.
    quiet_start_minute: int = 22 * 60
    quiet_end_minute: int = 7 * 60
    quiet_hours_enabled: bool = True


@dataclass
class EarsSettings:
    """Voice input, and the phrase that summons her."""

    enabled: bool = False
    # Matched loosely — see wake.py. The bare name is deliberately *not* here:
    # after normalisation it collides with "sorry a…", so it fires on "sorry
    # about that". Both two-word phrases are long enough not to. Add "soraya"
    # yourself if you would rather have the false fires than say two words.
    wake_phrases: list[str] = field(
        default_factory=lambda: ["hey soraya", "soraya come back"]
    )
    # Seconds of silence that ends a spoken turn.
    silence_timeout: float = 1.8


@dataclass
class BrainSettings:
    """Which model thinks, and how hard."""

    # "claude" | "openai_compat" | "echo".
    # `echo` needs no key and no network: it is how you see the whole app work
    # before you have decided on a model at all.
    provider: str = "claude"
    model: str = "claude-opus-5"
    # Only used by openai_compat. Ollama: http://localhost:11434/v1
    # LM Studio: http://localhost:1234/v1
    base_url: str = "http://localhost:11434/v1"
    # low | medium | high | xhigh | max. Conversation does not need `high`;
    # research does.
    effort: str = "medium"
    research_effort: str = "high"
    max_tokens: int = 4096
    temperature: float | None = None


@dataclass
class PresenceSettings:
    """How forward she is."""

    # quiet | normal | lively. Drives how often she starts a conversation
    # rather than waiting to be spoken to.
    initiative: str = "normal"
    # Minimum minutes between two unprompted approaches, whatever the mood
    # says. The single most important number in the file: without a floor,
    # "emotionally responsive" becomes "interrupts you constantly".
    min_minutes_between_approaches: int = 25
    # Greet when the screen unlocks.
    greet_on_unlock: bool = True


@dataclass
class Settings:
    name: str = "Soraya"
    # What she calls you.
    user_name: str = ""
    voice: VoiceSettings = field(default_factory=VoiceSettings)
    ears: EarsSettings = field(default_factory=EarsSettings)
    brain: BrainSettings = field(default_factory=BrainSettings)
    presence: PresenceSettings = field(default_factory=PresenceSettings)
    # Which folder under assets/characters/ to draw from.
    character_pack: str = "Soraya"

    # ---- persistence -------------------------------------------------------

    @property
    def path(self) -> Path:
        return HOME / "settings.json"

    @classmethod
    def load(cls, path: Path | None = None) -> "Settings":
        target = path or (HOME / "settings.json")
        if not target.exists():
            return cls()
        try:
            raw = json.loads(target.read_text())
        except (json.JSONDecodeError, OSError):
            # A corrupt settings file must not stop her from starting.
            return cls()
        return cls.from_dict(raw)

    @classmethod
    def from_dict(cls, raw: dict[str, Any]) -> "Settings":
        """Tolerant: unknown keys are ignored, missing keys take defaults.

        This is what lets a settings file written by an older or newer version
        still load. It recurses one level, which is all the nesting there is.
        """
        if not isinstance(raw, dict):
            return cls()
        kwargs: dict[str, Any] = {}
        for f in fields(cls):
            if f.name not in raw:
                continue
            value = raw[f.name]
            nested = {
                "voice": VoiceSettings,
                "ears": EarsSettings,
                "brain": BrainSettings,
                "presence": PresenceSettings,
            }.get(f.name)
            if nested is not None:
                if isinstance(value, dict):
                    allowed = {g.name for g in fields(nested)}
                    kwargs[f.name] = nested(
                        **{k: v for k, v in value.items() if k in allowed}
                    )
                continue
            kwargs[f.name] = value
        try:
            return cls(**kwargs)
        except TypeError:
            return cls()

    def save(self, path: Path | None = None) -> Path:
        target = path or self.path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(asdict(self), indent=2) + "\n")
        return target

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def minute_of_day(hour: int, minute: int) -> int:
    return hour * 60 + minute


def in_quiet_hours(voice: VoiceSettings, hour: int, minute: int) -> bool:
    """Whether the clock is inside the do-not-speak window.

    Ported deliberately from `QuietHours.swift`, including the case a naive
    `start <= t < end` gets wrong: a window that crosses midnight (22:00 to
    07:00), which is the common one.
    """
    if not voice.quiet_hours_enabled:
        return False
    start, end = voice.quiet_start_minute, voice.quiet_end_minute
    if start == end:
        # An empty window silences nothing. Treating it as "always quiet" would
        # let one mis-set number mute her forever.
        return False
    now = minute_of_day(hour, minute)
    if start < end:
        return start <= now < end
    return now >= start or now < end
