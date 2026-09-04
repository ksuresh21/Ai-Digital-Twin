"""A mind with no model behind it.

This exists so the entire application — UI, voice, sprite, memory, postures —
can be run and judged before anyone has an API key or has decided on a model.
It is also what the tests use, so the test suite never touches the network and
never costs anything.

It is not an imitation of intelligence. It reads the posture out of the turn
prompt and returns a fixed line for it, which is enough to see that the
plumbing is right and honest about being nothing more.
"""

from __future__ import annotations

import random
import re
from typing import Iterator

_LINES: dict[str, list[str]] = {
    "retreat": ["Okay. I'll be here.", "Right — going."],
    "hold": [
        "I'm not going anywhere. Tell me as much or as little as you want.",
    ],
    "ground": [
        "That's a lot at once. Pick the one thing that's due first — leave the rest.",
        "Deadline tomorrow, everything else shouting. What's the smallest piece you could finish now?",
    ],
    "support": [
        "You sound worn through. Nothing to fix, just noticing.",
        "That's a long stretch with no let-up.",
    ],
    "lift": ["Slow one, then. Want company or quiet?", "Flat afternoon. Happens."],
    "celebrate": ["There it is. That one took you a while.", "Good. That was the hard part."],
    "answer": ["(echo brain — plug in a model and I'll actually answer that.)"],
    "banter": ["Still here.", "Hey.", "Nothing to report."],
}


class EchoBrain:
    name = "echo"

    def __init__(self, seed: int | None = None) -> None:
        self._random = random.Random(seed)

    def _pick(self, turn_system: str) -> str:
        match = re.search(r"Posture:\s*(\w+)", turn_system)
        posture = match.group(1) if match else "banter"
        return self._random.choice(_LINES.get(posture, _LINES["banter"]))

    def speak(
        self, stable_system: str, turn_system: str, messages: list[dict[str, str]],
        *, effort: str = "medium", max_tokens: int = 4096,
    ) -> Iterator[str]:
        # Yielded word by word so the UI's streaming path is exercised rather
        # than bypassed — a bug that only shows up while text is arriving is
        # exactly the bug the offline mode should still catch.
        for word in self._pick(turn_system).split(" "):
            yield word + " "

    def judge(self, system: str, user: str, *, max_tokens: int = 400) -> str:
        # Enough shape for the caller's JSON parse to succeed; the fast
        # lexical read is what actually drives the posture in offline mode.
        return '{"valence": 0, "arousal": 0.3, "label": "neutral", "confidence": 0.1}'
