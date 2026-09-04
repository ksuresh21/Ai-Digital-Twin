"""When she starts a conversation you did not start.

This is the module most likely to make her insufferable, so it is the one with
the most conservative rules. "It has to come and it has to talk" is easy to
build and easy to overdo: a companion who approaches whenever a rule fires is
one you close after a day.

Everything here is a pure function of (settings, clock, recent history), so
"would she interrupt me at 3pm on a Tuesday when I'm heads-down" is a question
with a testable answer.
"""

from __future__ import annotations

import time
from dataclasses import dataclass

from .config import Settings, in_quiet_hours

#: initiative -> (minutes of silence before she may approach, chance she takes
#: the opening when it appears). The chance matters as much as the interval:
#: a companion who *always* appears after 40 minutes is a scheduled event, and
#: you stop reading her. One who usually does not is a presence.
INITIATIVE: dict[str, tuple[int, float]] = {
    "quiet": (180, 0.25),
    "normal": (55, 0.5),
    "lively": (20, 0.8),
}


@dataclass(frozen=True)
class Approach:
    """Whether she comes over, and what she has come about."""

    should: bool
    reason: str = ""
    # Fed to the persona as `situation`, so her opening line is about
    # something rather than being "hi" for the fourth time.
    situation: str = ""
    pose: str = "wave"


def _minutes_since(then: float | None, now: float) -> float:
    if then is None:
        return float("inf")
    return max(0.0, (now - then) / 60)


def consider(
    settings: Settings,
    *,
    now: float | None = None,
    last_spoke_at: float | None = None,
    last_approach_at: float | None = None,
    idle_minutes: float = 0.0,
    unlocked_just_now: bool = False,
    roll: float = 1.0,
    mood_label: str = "",
) -> Approach:
    """Decides whether she approaches. Ordered, and the order is the design."""
    now = now if now is not None else time.time()
    clock = time.localtime(now)

    # 1. Quiet hours beat everything except an unlock greeting, which is a
    #    response to you arriving rather than an interruption of anything.
    quiet = in_quiet_hours(settings.quiet_hours, clock.tm_hour, clock.tm_min)

    # 2. Coming back to the machine. The one approach that is always welcome,
    #    because you just chose to be here.
    if unlocked_just_now and settings.presence.greet_on_unlock:
        return Approach(
            True, "unlock",
            situation="They just unlocked the Mac and came back to the desk.",
            pose="greeting",
        )

    if quiet:
        return Approach(False, "quiet hours")

    # 3. The floor. Whatever any rule below thinks, she does not approach more
    #    often than this. Without it, "emotionally responsive" becomes
    #    "interrupts you constantly".
    floor = settings.presence.min_minutes_between_approaches
    if _minutes_since(last_approach_at, now) < floor:
        return Approach(False, "too soon since the last time")

    # 4. Do not talk to an empty chair. If the keyboard has been still for a
    #    long time you are not there, and she would be performing to nobody
    #    while burning tokens.
    if idle_minutes > 20:
        return Approach(False, "nobody at the desk")

    window, chance = INITIATIVE.get(
        settings.presence.initiative, INITIATIVE["normal"]
    )

    silence = _minutes_since(last_spoke_at, now)
    if silence < window:
        return Approach(False, "spoke recently")

    # 5. The dice. `roll` is injected so tests are deterministic; the caller
    #    passes random.random() in real use.
    if roll > chance:
        return Approach(False, "not this time")

    if mood_label in ("stressed", "flat", "tired"):
        return Approach(
            True, "mood",
            situation=(
                f"It has been quiet for a while and the last read of them was "
                f"'{mood_label}'. You are coming over to check in — lightly. "
                "Do not make it a big moment."
            ),
        )

    return Approach(
        True, "quiet stretch",
        situation=(
            "Nothing in particular has happened; it has just been a while. "
            "You are wandering over to say something small. It is completely "
            "fine for this to be almost nothing."
        ),
    )
