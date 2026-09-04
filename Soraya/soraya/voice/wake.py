"""Matching "Hey Soraya" against whatever the microphone thought it heard.

Speech recognition mangles names, and it mangles them *consistently*: "Soraya"
comes back as "sorry a", "so raya", "soraia", "sarah ya". Exact matching on
the configured phrase therefore fails almost always, which reads to the user
as the wake word not working at all.

So: normalise hard, squash out spaces and doubled letters, then allow a small
edit distance. Squashing alone is not enough — it was the first attempt, and
"sorry a" squashes to "sorya", which is still not "soraya". One edit of slack
catches that, and "soraia", and "sorayah".

The tolerance is one edit per six characters, with a floor of one. That number
is a false-positive budget, not a guess: at two edits the six-letter "soraya"
starts matching the word "sorry", which is far too common in ordinary speech to
be a wake word. Longer phrases get proportionally more slack because there is
more context to be wrong about.

A collision worth knowing about, because it cannot be fixed at this layer:
after squashing, "sorry a…" and "soraya" are the *same string*. So "hey sorry a,
what's the weather" — the single most common misrecognition of her name — is
caught, and so is "sorry about that", which you did not mean for her. There is
no rule that separates them; they are identical by the time they reach here.

The lever, rather than a fake fix: `ears.wake_phrases` is configurable. Anyone
bothered by the false fire should drop the bare "soraya" and keep only
"hey soraya", which is long enough not to collide. Talking *about* her
("Soraya's cat") fires too — every wake word has that, and the mitigation is
that she only listens while the microphone is on.
"""

from __future__ import annotations

import re
from dataclasses import dataclass


def _normalise(text: str) -> str:
    text = text.lower()
    text = re.sub(r"[^a-z0-9 ]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def _squash(text: str) -> str:
    """Drops spaces and doubled letters, so "so raya" == "soraya"."""
    joined = re.sub(r"[^a-z0-9]+", "", text.lower())
    out: list[str] = []
    for char in joined:
        if not out or out[-1] != char:
            out.append(char)
    return "".join(out)


def _within(candidate: str, target: str, tolerance: int) -> bool:
    """Bounded Levenshtein: True if `candidate` is within `tolerance` edits.

    Bounded because it can abandon a row once every cell exceeds the budget,
    which turns the worst case from "measure the whole string" into "give up
    after a few characters" — and this runs on every recognised phrase.
    """
    if abs(len(candidate) - len(target)) > tolerance:
        return False
    previous = list(range(len(target) + 1))
    for i, a in enumerate(candidate, start=1):
        current = [i] + [0] * len(target)
        for j, b in enumerate(target, start=1):
            current[j] = min(
                previous[j] + 1,          # deletion
                current[j - 1] + 1,       # insertion
                previous[j - 1] + (a != b),  # substitution
            )
        if min(current) > tolerance:
            return False
        previous = current
    return previous[-1] <= tolerance


def _tolerance(target: str) -> int:
    return max(1, len(target) // 6)


@dataclass
class Match:
    hit: bool
    phrase: str = ""
    # What was left after the wake phrase — usually the actual request,
    # as in "hey soraya what's the weather".
    remainder: str = ""


class WakeMatcher:
    def __init__(self, phrases: list[str] | None = None) -> None:
        self.phrases = [p for p in (phrases or ["hey soraya", "soraya"]) if p.strip()]
        self._squashed = [(p, _squash(p)) for p in self.phrases]

    def match(self, heard: str) -> Match:
        if not heard.strip() or not self._squashed:
            return Match(False)

        normal = _normalise(heard)
        squashed = _squash(normal)

        # Longest phrase first, so "soraya come back" is not swallowed by the
        # bare "soraya" and reported with the wrong remainder.
        for phrase, target in sorted(
            self._squashed, key=lambda pair: len(pair[1]), reverse=True
        ):
            if target and target in squashed:
                return Match(True, phrase, self._remainder_after(normal, target))

            # Fuzzy matching only earns its keep on a phrase long enough to be
            # distinctive. On a three-letter custom wake word, one edit of
            # slack matches most of the language.
            if len(target) < 6:
                continue

            # No exact hit — slide a window and allow a little slack. The
            # window varies in length because a misheard phrase is usually
            # slightly shorter or longer than the real one, not the same size.
            tolerance = _tolerance(target)
            for width in range(len(target) - tolerance, len(target) + tolerance + 1):
                if width <= 0:
                    continue
                for start in range(0, max(1, len(squashed) - width + 1)):
                    window = squashed[start:start + width]
                    if len(window) < width:
                        break
                    if _within(window, target, tolerance):
                        return Match(True, phrase,
                                     self._remainder_after(normal, window))
        return Match(False)

    @staticmethod
    def _remainder_after(normal: str, squashed_target: str) -> str:
        words = normal.split(" ")
        # Walk word by word, squashing as we go, and cut at the first prefix
        # that contains the target.
        accumulated = ""
        for index, word in enumerate(words):
            accumulated = _squash(accumulated + word)
            if squashed_target in accumulated:
                return " ".join(words[index + 1:]).strip()
        return ""
