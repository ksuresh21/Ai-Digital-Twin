"""Reading how you are, and deciding what she should do about it.

Two passes, on purpose:

**Fast pass** (`read_fast`) — pure Python, no network, sub-millisecond. Runs on
every message so the sprite and her voice can react *before* the model has
finished thinking. Crude but honest about being crude.

The word lists are the crude part, and they are the thing to extend when she
misreads something in offline mode. "I am wrecked, nothing is working" read as
neutral until both of those phrasings were added — which mattered because with
no model configured the fast pass is the *only* read, so she answered a bad
evening with small talk. With a model configured this is a half-second cosmetic
issue at worst; the considered pass gets it right either way.

**Considered pass** (`Affect.from_model`) — the model's own structured read,
which is far better at sarcasm, understatement and "I'm fine". Replaces the
fast read when it lands.

The posture rules are pure functions of the affect, which is the whole point:
"what should she do when I am stressed at 11pm" is a question you can write a
test for, and it should never depend on which model is plugged in.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Iterable

# ---------------------------------------------------------------------------
# Affect
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Affect:
    """How you seem, on two axes plus a few flags.

    Valence and arousal rather than a list of named emotions, because the
    named-emotion approach forces a choice between "tired" and "frustrated"
    when the useful answer is "low and flat" versus "low and hot" — and those
    two want opposite responses from her.
    """

    # -1 (bad) .. +1 (good)
    valence: float = 0.0
    # 0 (flat, drained) .. 1 (activated, wired)
    arousal: float = 0.3
    # A short human label, for the log and for her own reference.
    label: str = "neutral"
    # 0..1. The fast pass is rarely confident; the model usually is.
    confidence: float = 0.2
    # Phrases that led to this read. Kept so a wrong read is debuggable
    # rather than mysterious.
    evidence: tuple[str, ...] = ()
    # Explicit signals that outrank the axes entirely.
    wants_space: bool = False
    asked_a_question: bool = False
    # Set when the text suggests risk of harm. Never handled by the persona —
    # see `posture_for`.
    distress_escalation: bool = False

    def clamped(self) -> "Affect":
        return Affect(
            valence=max(-1.0, min(1.0, self.valence)),
            arousal=max(0.0, min(1.0, self.arousal)),
            label=self.label,
            confidence=max(0.0, min(1.0, self.confidence)),
            evidence=self.evidence,
            wants_space=self.wants_space,
            asked_a_question=self.asked_a_question,
            distress_escalation=self.distress_escalation,
        )

    @classmethod
    def from_model(cls, raw: dict) -> "Affect":
        """Builds an affect from the model's JSON read.

        Every field is optional and every type is checked. The model is a
        collaborator, not a trusted input: a malformed read must degrade to
        neutral rather than crash the turn.
        """

        def num(key: str, default: float) -> float:
            value = raw.get(key, default)
            return float(value) if isinstance(value, (int, float)) else default

        def flag(key: str) -> bool:
            return bool(raw.get(key)) if isinstance(raw.get(key), bool) else False

        evidence = raw.get("evidence")
        if isinstance(evidence, str):
            evidence = [evidence]
        if not isinstance(evidence, list):
            evidence = []

        label = raw.get("label")
        return cls(
            valence=num("valence", 0.0),
            arousal=num("arousal", 0.3),
            label=label if isinstance(label, str) and label else "neutral",
            confidence=num("confidence", 0.6),
            evidence=tuple(str(e)[:120] for e in evidence[:4]),
            wants_space=flag("wants_space"),
            asked_a_question=flag("asked_a_question"),
            distress_escalation=flag("distress_escalation"),
        ).clamped()


NEUTRAL = Affect()


# ---------------------------------------------------------------------------
# The fast pass
# ---------------------------------------------------------------------------

# Small, deliberately. A big sentiment lexicon here would be false precision:
# the model does this properly a second later. These are the words that change
# what she should do *right now*, in the gap.
_LOW_HOT = (
    "angry", "furious", "pissed", "fed up", "hate", "annoying", "frustrated",
    "frustrating", "stressed", "stressing", "panic", "panicking", "deadline",
    "overwhelmed", "too much", "can't cope", "cant cope", "urgent",
    # How people actually report things going wrong.
    "nothing works", "nothing is working", "not working", "broken",
    "sick of", "falling apart", "went wrong", "keeps failing",
)
_LOW_FLAT = (
    "tired", "exhausted", "drained", "sleepy", "burnt out", "burned out",
    "bored", "boring", "meh", "empty", "numb", "lonely", "alone", "sad",
    "down", "low", "stuck", "pointless", "give up", "giving up",
    # Informal exhaustion. "wrecked" was the one that exposed the gap: it is
    # about as common as "exhausted" in speech and was read as neutral, so in
    # offline mode she answered a bad evening with small talk.
    "wrecked", "knackered", "shattered", "wiped out", "worn out", "spent",
    "can't be bothered", "cant be bothered", "no energy",
)
_HIGH_GOOD = (
    "shipped", "finished", "done it", "works", "worked", "fixed", "passed",
    "got it", "yes!", "finally", "excited", "amazing", "brilliant", "love it",
    "great news", "promoted", "won",
)
_MILD_GOOD = ("thanks", "thank you", "good", "fine", "okay", "ok", "nice", "cool")
_WANTS_SPACE = (
    "leave me", "not now", "go away", "later", "busy", "stop", "shut up",
    "don't want to talk", "dont want to talk", "no thanks",
)
# Deliberately narrow and high-signal. A false positive here is far cheaper
# than a false negative, but a *broad* list would fire on ordinary venting and
# turn every bad afternoon into a crisis script, which helps nobody.
_ESCALATION = (
    "kill myself", "end my life", "want to die", "suicide", "suicidal",
    "self harm", "self-harm", "hurt myself", "no reason to live",
)


def _hits(text: str, phrases: Iterable[str]) -> list[str]:
    return [p for p in phrases if p in text]


def read_fast(message: str) -> Affect:
    """A cheap read, for the half-second before the model answers."""
    text = " " + re.sub(r"\s+", " ", message.lower().strip()) + " "
    if not text.strip():
        return NEUTRAL

    escalation = _hits(text, _ESCALATION)
    space = _hits(text, _WANTS_SPACE)
    hot = _hits(text, _LOW_HOT)
    flat = _hits(text, _LOW_FLAT)
    good = _hits(text, _HIGH_GOOD)
    mild = _hits(text, _MILD_GOOD)

    # Typographic arousal: shouting and repeated punctuation are real signal
    # and cost nothing to read.
    exclaims = message.count("!")
    letters = [c for c in message if c.isalpha()]
    shouting = len(letters) >= 8 and sum(c.isupper() for c in letters) / len(letters) > 0.7

    valence = 0.0
    arousal = 0.3
    label = "neutral"
    evidence: list[str] = []

    if escalation:
        return Affect(
            valence=-0.9, arousal=0.6, label="distress", confidence=0.5,
            evidence=tuple(escalation[:2]), distress_escalation=True,
        )
    if space:
        return Affect(
            valence=-0.15, arousal=0.4, label="wants space", confidence=0.45,
            evidence=tuple(space[:2]), wants_space=True,
        )

    if hot:
        valence, arousal, label = -0.6, 0.8, "stressed"
        evidence = hot[:3]
    elif flat:
        valence, arousal, label = -0.5, 0.15, "flat"
        evidence = flat[:3]
    elif good:
        valence, arousal, label = 0.8, 0.75, "elated"
        evidence = good[:3]
    elif mild:
        valence, arousal, label = 0.3, 0.35, "content"
        evidence = mild[:2]

    if shouting or exclaims >= 2:
        arousal = min(1.0, arousal + 0.25)
        evidence.append("emphasis")

    # Confidence stays low throughout: this pass is a placeholder holding the
    # door open until the model's read arrives, and it should not be trusted
    # enough to override one.
    confidence = 0.15 if label == "neutral" else 0.35
    return Affect(
        valence=valence, arousal=arousal, label=label, confidence=confidence,
        evidence=tuple(evidence),
        asked_a_question="?" in message,
    ).clamped()


# ---------------------------------------------------------------------------
# What she should do about it
# ---------------------------------------------------------------------------

#: The postures, and what each one asks of her. These strings go into the
#: prompt verbatim, which is why they read as instructions rather than labels.
POSTURES: dict[str, str] = {
    "retreat": (
        "They want to be left alone. Acknowledge in one short line and stop. "
        "Do not ask a question. Do not offer anything. Leaving cleanly is the "
        "whole job."
    ),
    "hold": (
        "Something serious. Stay warm, stay plain, stay with them. Do not "
        "problem-solve, do not minimise, do not perform cheerfulness. One "
        "gentle question at most, and only if it opens a door."
    ),
    "ground": (
        "They are activated and under pressure. Slow the tempo. Reflect what "
        "you heard in fewer words than they used, then offer exactly one "
        "concrete next thing — the smallest one. No lists, no pep talk."
    ),
    "support": (
        "They are low and flat. Sit alongside rather than pulling them up. "
        "Name what you notice without diagnosing it. Company first; a small "
        "suggestion only if it arrives naturally."
    ),
    "lift": (
        "Low energy, nothing heavy behind it. A little warmth and a little "
        "momentum. Light, brief, and easy to ignore."
    ),
    "celebrate": (
        "Something went right. Be genuinely pleased and specific about what "
        "they did — not generically congratulatory. Short. Let them have it."
    ),
    "answer": (
        "They asked something. Answer it properly first. Warmth after the "
        "answer, not instead of it."
    ),
    "banter": (
        "Nothing much is happening. Be easy company: brief, a bit of "
        "character, no agenda. It is fine to say almost nothing."
    ),
}


@dataclass(frozen=True)
class Response:
    """What she should do this turn."""

    posture: str
    # The instruction text for the prompt.
    guidance: str
    # Reflect their meaning back in different words before responding. The
    # user's phrase for this was "say the conversation in another way", and it
    # is the single most useful move in the set — but not always: reframing a
    # direct question is evasion, and reframing a celebration is cold.
    reframe: bool = False
    # Say less than usual. Rough word ceiling, honoured by the persona.
    word_ceiling: int = 60
    # The sprite pose this posture wants.
    pose: str = "idle"
    # True when the reply must carry a signpost to real human help.
    signpost_help: bool = False
    notes: tuple[str, ...] = field(default_factory=tuple)


def posture_for(affect: Affect, *, is_proactive: bool = False) -> Response:
    """Picks a posture. Pure, ordered, and the ordering is the design.

    The first three checks outrank the emotional axes completely. That is
    deliberate: "leave me alone" must beat any reading of your mood, and a
    safety signal must beat everything including the persona.
    """
    a = affect.clamped()

    if a.distress_escalation:
        # She is a companion, not a clinician, and the honest thing is to say
        # so and point somewhere real. This is the one posture the persona is
        # not allowed to improvise around.
        return Response(
            posture="hold", guidance=POSTURES["hold"], reframe=False,
            word_ceiling=70, pose="concerned", signpost_help=True,
            notes=("escalation",),
        )

    if a.wants_space:
        return Response(
            posture="retreat", guidance=POSTURES["retreat"], reframe=False,
            word_ceiling=18, pose="idle", notes=("respect the no",),
        )

    # A direct question outranks mood-tending, unless the mood is heavy. Being
    # asked "what time is it" and getting "how are you feeling?" back is the
    # most irritating failure an emotionally-aware assistant has.
    if a.asked_a_question and a.valence > -0.45:
        return Response(
            posture="answer", guidance=POSTURES["answer"], reframe=False,
            word_ceiling=120, pose="idle",
        )

    hot = a.arousal >= 0.55
    if a.valence <= -0.35:
        if hot:
            return Response(
                posture="ground", guidance=POSTURES["ground"], reframe=True,
                word_ceiling=55, pose="concerned",
            )
        return Response(
            posture="support", guidance=POSTURES["support"], reframe=True,
            word_ceiling=50, pose="concerned",
        )

    if a.valence >= 0.45 and hot:
        return Response(
            posture="celebrate", guidance=POSTURES["celebrate"], reframe=False,
            word_ceiling=40, pose="cheer",
        )

    if a.arousal < 0.25 and a.valence < 0.2:
        return Response(
            posture="lift", guidance=POSTURES["lift"], reframe=False,
            word_ceiling=35, pose="idle",
        )

    return Response(
        posture="banter", guidance=POSTURES["banter"], reframe=False,
        # Unprompted small talk gets a tighter ceiling than an answer to a
        # question. She interrupted you; she can be brief about it.
        word_ceiling=28 if is_proactive else 45,
        pose="wave" if is_proactive else "idle",
    )
