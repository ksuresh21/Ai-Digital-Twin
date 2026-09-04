"""What she remembers, and how she finds it again.

Two tiers, because they answer different questions:

**The transcript** (`turns.jsonl`) is what was said. Append-only, one JSON
object per line, so a crash mid-write costs one line rather than the file.
Recent turns go into the prompt verbatim.

**Notes** (`notes.jsonl`) are what she learned — durable facts worth carrying
across days. Written deliberately, never scraped automatically from every
message, because a companion that remembers everything you said is not warm,
it is unnerving.

Retrieval is keyword overlap plus recency, with no embeddings and no vector
store. That is a real limit and it is written up in ROADMAP.md, but it means
this whole module has zero dependencies and works offline, and for a few
hundred notes it is genuinely hard to beat.
"""

from __future__ import annotations

import json
import re
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Iterable, Literal

from .config import HOME

Role = Literal["user", "soraya", "system"]

# Words too common to discriminate between notes. Kept short on purpose: a full
# stopword list would strip the words that actually distinguish one memory from
# another in a conversation about ordinary life.
_STOP = {
    "the", "a", "an", "and", "or", "but", "if", "so", "to", "of", "in", "on",
    "at", "for", "with", "is", "are", "was", "were", "be", "been", "it", "its",
    "this", "that", "these", "those", "i", "im", "me", "my", "you", "your",
    "we", "they", "he", "she", "do", "does", "did", "have", "has", "had",
    "will", "would", "can", "could", "should", "just", "about", "not",
}


def _tokens(text: str) -> set[str]:
    return {
        w for w in re.findall(r"[a-z0-9']+", text.lower())
        if len(w) > 2 and w not in _STOP
    }


@dataclass
class Turn:
    role: Role
    text: str
    at: float = field(default_factory=time.time)
    # The affect label at the time, for the log and for later review.
    mood: str = ""
    posture: str = ""


@dataclass
class Note:
    """One durable thing she knows."""

    text: str
    at: float = field(default_factory=time.time)
    # "fact" (they have a cat), "preference" (hates video calls),
    # "thread" (the migration at work), "promise" (said they'd call their mum).
    kind: str = "fact"
    # Bumped whenever the note proves useful, so what matters surfaces.
    uses: int = 0


class Memory:
    """File-backed memory. Cheap to construct, safe to construct twice."""

    def __init__(self, home: Path | None = None, *, window: int = 12) -> None:
        self.home = home or HOME
        self.home.mkdir(parents=True, exist_ok=True)
        self.turns_path = self.home / "turns.jsonl"
        self.notes_path = self.home / "notes.jsonl"
        # How many recent turns go into the prompt. Small deliberately: a
        # companion whose replies are shaped by a 200-turn history starts
        # repeating old moods back at you.
        self.window = window

    # ---- transcript -------------------------------------------------------

    def add_turn(self, turn: Turn) -> None:
        with self.turns_path.open("a") as handle:
            handle.write(json.dumps(asdict(turn)) + "\n")

    def recent_turns(self, limit: int | None = None) -> list[Turn]:
        limit = limit or self.window
        rows = _read_jsonl(self.turns_path)
        out: list[Turn] = []
        for row in rows[-limit:]:
            try:
                out.append(Turn(**row))
            except TypeError:
                # A row written by a different version. Skipping one line beats
                # refusing to load the history.
                continue
        return out

    def as_messages(self, limit: int | None = None) -> list[dict[str, str]]:
        """Recent turns in the shape every chat API wants."""
        messages: list[dict[str, str]] = []
        for turn in self.recent_turns(limit):
            if turn.role == "system":
                continue
            role = "user" if turn.role == "user" else "assistant"
            # Consecutive same-role turns are legal but merge into one turn;
            # collapsing them here keeps the history honest about who spoke.
            if messages and messages[-1]["role"] == role:
                messages[-1]["content"] += "\n" + turn.text
            else:
                messages.append({"role": role, "content": turn.text})
        # Every provider requires the history to open on a user turn.
        while messages and messages[0]["role"] != "user":
            messages.pop(0)
        return messages

    def last_spoke_at(self) -> float | None:
        """When she last said something, for deciding whether to approach."""
        for turn in reversed(self.recent_turns(limit=60)):
            if turn.role == "soraya":
                return turn.at
        return None

    # ---- notes ------------------------------------------------------------

    def remember(self, text: str, kind: str = "fact") -> Note | None:
        """Stores a durable fact, ignoring near-duplicates.

        Deduplication is by token overlap rather than exact string match: the
        model will phrase the same fact three different ways across a week, and
        without this the notes file fills with restatements of one thing.

        The measure is the *overlap coefficient* — shared tokens over the
        smaller set — not Jaccard. Jaccard was the first attempt and it does not
        work here: "has a cat called Mowgli" and "owns a cat named Mowgli" score
        0.4 by Jaccard and sail straight through, because a paraphrase changes
        as many words as it keeps. Over the smaller set the same pair scores
        0.67 and is caught.

        The trade-off, stated plainly: this is biased toward *not* storing.
        A richer restatement of a fact she already knows can be dropped. That
        is the cheaper mistake — she already has the fact, whereas duplicates
        accumulate in the prompt and she starts repeating herself. Proper
        semantic dedupe needs embeddings; see ROADMAP.md.
        """
        text = text.strip()
        if not text:
            return None
        incoming = _tokens(text)
        if not incoming:
            return None
        for existing in self.notes():
            other = _tokens(existing.text)
            if not other:
                continue
            overlap = len(incoming & other) / min(len(incoming), len(other))
            if overlap >= 0.6:
                return None
        note = Note(text=text, kind=kind)
        with self.notes_path.open("a") as handle:
            handle.write(json.dumps(asdict(note)) + "\n")
        return note

    def notes(self) -> list[Note]:
        out: list[Note] = []
        for row in _read_jsonl(self.notes_path):
            try:
                out.append(Note(**row))
            except TypeError:
                continue
        return out

    def recall(self, query: str, limit: int = 4) -> list[str]:
        """The notes most likely to matter for this message.

        Score is keyword overlap, nudged by recency and by how often a note has
        been useful before. Notes with no overlap at all are excluded rather
        than padded in — an irrelevant memory in the prompt is worse than a
        short prompt, because she will find a way to mention it.
        """
        wanted = _tokens(query)
        if not wanted:
            return []
        now = time.time()
        scored: list[tuple[float, str]] = []
        for note in self.notes():
            overlap = len(wanted & _tokens(note.text))
            if not overlap:
                continue
            age_days = max(0.0, (now - note.at) / 86_400)
            # Halves roughly every three weeks: old facts still count, old
            # threads mostly should not.
            recency = 0.5 ** (age_days / 21)
            scored.append((overlap + 0.5 * recency + 0.1 * note.uses, note.text))
        scored.sort(reverse=True)
        return [text for _, text in scored[:limit]]

    def forget_all(self) -> None:
        """Deletes everything. Only ever called from an explicit user action."""
        for path in (self.turns_path, self.notes_path):
            if path.exists():
                path.unlink()


def _read_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    rows: list[dict] = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            # A truncated final line from a crash mid-append. Skip it.
            continue
        if isinstance(row, dict):
            rows.append(row)
    return rows
