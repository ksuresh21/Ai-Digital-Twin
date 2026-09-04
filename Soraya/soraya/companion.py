"""Soraya herself: the one object that holds the mind, the memory and the voice.

Everything above this line is pure or nearly pure. This is where the side
effects live, and it is deliberately the *only* place they do — the same
arrangement as `AppCoordinator` in the Swift app, and for the same reason: when
one object owns the wiring, the pieces stay testable and the seams stay honest.

A turn is a generator of events rather than a returned string, so the interface
can put her pose on screen and start her voice before the sentence is finished.
The event stream is the contract the browser and the Swift app both consume;
see INTEGRATION.md.
"""

from __future__ import annotations

import json
import random
import re
import time
from dataclasses import asdict
from pathlib import Path
from typing import Iterator

from . import emotion, persona, pulse
from .brain import BrainUnavailable
from .brain.registry import build_brain_or_echo
from .config import HOME, Settings, in_quiet_hours
from .memory import Memory, Turn
from .presence.sprite import Sprite, available_packs, clip_for, find_pack
from .voice.base import SilentSpeaker, speech_text
from .voice.tts_macos import MacSpeaker

#: Kept for anything that still wants the local pack folder by name. Pack
#: *lookup* goes through `find_pack`, which also searches the Swift app's
#: character folders — see presence/sprite.py § PACK_ROOTS.
ASSETS = Path(__file__).resolve().parent.parent / "assets" / "characters"

# She is asked to note what is worth keeping *after* she has replied, so it
# never delays the reply. One small call, low effort.
NOTE_SYSTEM = """\
From the exchange below, extract only durable facts worth remembering for
months — a name, a relationship, a job, a preference, a commitment they made,
an ongoing thread in their life.

Return a JSON array of objects: [{"text": "...", "kind": "fact"}]
kind is one of: fact, preference, thread, promise.

Return [] far more often than not. Do NOT record: passing moods, what they were
doing today, anything they would find unsettling to be told you had written
down, or anything already obvious. Three items is a lot. Zero is normal.
Write each in the third person, plainly: "Works at a company called X."
"""


class Companion:
    def __init__(self, settings: Settings | None = None,
                 home: Path | None = None) -> None:
        self.home = home or HOME
        self.settings = settings or Settings.load()
        self.memory = Memory(self.home)
        self.brain, self.brain_warning = build_brain_or_echo(self.settings.brain)

        self._mac_speaker = MacSpeaker()
        self._silent = SilentSpeaker()
        self.last_approach_at: float | None = None
        self.last_affect = emotion.NEUTRAL
        self._random = random.Random()

    # ---- wiring ------------------------------------------------------------

    @property
    def speaker(self):
        """The real voice when it is on and permitted, silence otherwise.

        Resolved per call rather than at construction so toggling voice in the
        interface takes effect on the next sentence, with no restart.
        """
        voice = self.settings.voice
        if not voice.enabled or not self._mac_speaker.available:
            return self._silent
        clock = time.localtime()
        if in_quiet_hours(self.settings.quiet_hours, clock.tm_hour, clock.tm_min):
            return self._silent
        return self._mac_speaker

    @property
    def sprite(self) -> Sprite:
        """The configured pack, or the best available one if it has gone.

        A pack can disappear between runs — renamed, moved, or the settings
        file names one from another machine. Falling back to something real
        beats rendering an empty box, and the interface reports which pack it
        actually used.
        """
        # "Soraya" second on purpose: it is the pack that ships with this
        # folder, so it is a better fallback than whichever pack happens to
        # sort first in whatever roots exist on this machine.
        for name in (self.settings.character_pack, "Soraya"):
            found = find_pack(name)
            if found is not None:
                return Sprite(found)
        packs = available_packs()
        if packs:
            return Sprite(packs[0][1])
        return Sprite(ASSETS / self.settings.character_pack)

    def apply(self, settings: Settings) -> None:
        """Adopts new settings, rebuilding the brain only if it changed."""
        rebuild = asdict(settings.brain) != asdict(self.settings.brain)
        self.settings = settings
        settings.save(self.home / "settings.json")
        if rebuild:
            self.brain, self.brain_warning = build_brain_or_echo(settings.brain)

    # ---- the affect read ---------------------------------------------------

    def read_affect(self, message: str) -> emotion.Affect:
        """Fast read first, then the model's — and the model only if it is better.

        The fast read is always computed because it is free and instant. The
        model's read replaces it only when it comes back more confident, so a
        failed or vague model call degrades to the lexical answer instead of
        losing the mood entirely.
        """
        fast = emotion.read_fast(message)
        # An explicit "leave me alone" or a safety signal is not worth a
        # round-trip: acting on it a second later is the whole point.
        if fast.wants_space or fast.distress_escalation:
            return fast
        try:
            raw = self.brain.judge(persona.AFFECT_SYSTEM, message, max_tokens=300)
        except BrainUnavailable:
            return fast
        parsed = _first_json_object(raw)
        if parsed is None:
            return fast
        considered = emotion.Affect.from_model(parsed)
        # The fast pass keeps its safety flag no matter what the model says:
        # a lexical hit on self-harm language must not be talked out of.
        if fast.distress_escalation:
            considered = emotion.Affect(**{
                **asdict(considered), "distress_escalation": True,
            })
        return considered if considered.confidence >= fast.confidence else fast

    # ---- a turn ------------------------------------------------------------

    def respond(self, message: str, *, situation: str = "",
                proactive: bool = False) -> Iterator[dict]:
        """Runs one exchange, yielding events as they happen."""
        message = message.strip()
        if not message and not proactive:
            return

        # She stops talking the instant you say something. Nothing is more
        # irritating than being talked over by software.
        self._mac_speaker.stop()

        yield {"type": "pose", "clip": clip_for("", state="thinking")}

        affect = self.read_affect(message) if message else self.last_affect
        self.last_affect = affect
        response = emotion.posture_for(affect, is_proactive=proactive)

        yield {
            "type": "affect",
            "label": affect.label,
            "valence": round(affect.valence, 2),
            "arousal": round(affect.arousal, 2),
            "confidence": round(affect.confidence, 2),
            "posture": response.posture,
            "evidence": list(affect.evidence),
        }
        yield {"type": "pose", "clip": clip_for(response.posture)}

        if message:
            self.memory.add_turn(Turn("user", message, mood=affect.label))

        recalled = self.memory.recall(message) if message else []
        stable = persona.stable_prompt(self.settings)
        volatile = persona.turn_prompt(
            self.settings, affect, response,
            recalled=recalled, situation=situation,
        )
        history = self.memory.as_messages()
        if proactive and (not history or history[-1]["role"] != "user"):
            # Every provider needs the history to end on a user turn. When she
            # is the one opening, the prompt itself becomes that turn.
            history = history + [{
                "role": "user",
                "content": "(You are choosing to say something. They have not "
                           "spoken yet.)",
            }]

        collected: list[str] = []
        try:
            for chunk in self.brain.speak(
                stable, volatile, history,
                effort=self.settings.brain.effort,
                max_tokens=self.settings.brain.max_tokens,
            ):
                collected.append(chunk)
                yield {"type": "chunk", "text": chunk}
        except BrainUnavailable as exc:
            yield {"type": "error", "message": str(exc)}
            yield {"type": "pose", "clip": "idle"}
            return

        reply = "".join(collected).strip()
        if not reply:
            yield {"type": "pose", "clip": "idle"}
            return

        self.memory.add_turn(
            Turn("soraya", reply, mood=affect.label, posture=response.posture)
        )

        spoken = speech_text(reply)
        did_speak = self.speaker.say(
            spoken,
            rate=self.settings.voice.rate,
            volume=self.settings.voice.volume,
            voice=self.settings.voice.name or self._mac_speaker.default_voice(),
        )

        yield {
            "type": "done",
            "text": reply,
            "spoke": did_speak,
            "spoken_text": spoken if did_speak else "",
            "posture": response.posture,
            "usage": asdict(getattr(self.brain, "last_reply", None))
            if hasattr(self.brain, "last_reply") else {},
        }
        yield {"type": "pose", "clip": "idle"}

    # ---- unprompted --------------------------------------------------------

    def consider_approach(self, *, idle_minutes: float = 0.0,
                          unlocked_just_now: bool = False) -> pulse.Approach:
        return pulse.consider(
            self.settings,
            last_spoke_at=self.memory.last_spoke_at(),
            last_approach_at=self.last_approach_at,
            idle_minutes=idle_minutes,
            unlocked_just_now=unlocked_just_now,
            roll=self._random.random(),
            mood_label=self.last_affect.label,
        )

    def approach(self, approach: pulse.Approach) -> Iterator[dict]:
        """She comes over. Records the time so the floor rule can see it."""
        if not approach.should:
            return
        self.last_approach_at = time.time()
        yield {"type": "approach", "reason": approach.reason}
        yield from self.respond("", situation=approach.situation, proactive=True)

    # ---- remembering -------------------------------------------------------

    def note_from_last_exchange(self) -> list[str]:
        """Asks her what was worth keeping. Called after the reply is sent.

        Deliberately after: extraction costs a round-trip, and nothing about it
        should make you wait for her to answer.
        """
        turns = self.memory.recent_turns(limit=4)
        if len(turns) < 2:
            return []
        transcript = "\n".join(
            f"{'Them' if t.role == 'user' else 'You'}: {t.text}" for t in turns
        )
        try:
            raw = self.brain.judge(NOTE_SYSTEM, transcript, max_tokens=500)
        except BrainUnavailable:
            return []
        items = _first_json_array(raw) or []
        kept: list[str] = []
        for item in items[:3]:
            if not isinstance(item, dict):
                continue
            text = str(item.get("text", "")).strip()
            kind = str(item.get("kind", "fact")).strip() or "fact"
            if not text:
                continue
            if self.memory.remember(text, kind):
                kept.append(text)
        return kept


# ---------------------------------------------------------------------------
# Parsing what the model returned
# ---------------------------------------------------------------------------
# Models wrap JSON in prose and code fences however much you ask them not to,
# and a companion must not fall over because of a stray ```json. These pull the
# first well-formed structure out and ignore everything around it.


def _first_json_object(text: str) -> dict | None:
    for match in re.finditer(r"\{", text or ""):
        chunk = _balanced(text, match.start(), "{", "}")
        if chunk is None:
            continue
        try:
            value = json.loads(chunk)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            return value
    return None


def _first_json_array(text: str) -> list | None:
    for match in re.finditer(r"\[", text or ""):
        chunk = _balanced(text, match.start(), "[", "]")
        if chunk is None:
            continue
        try:
            value = json.loads(chunk)
        except json.JSONDecodeError:
            continue
        if isinstance(value, list):
            return value
    return None


def _balanced(text: str, start: int, opener: str, closer: str) -> str | None:
    """The substring from `start` to its matching close, respecting strings."""
    depth = 0
    in_string = False
    escaped = False
    for index in range(start, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == opener:
            depth += 1
        elif char == closer:
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    return None
