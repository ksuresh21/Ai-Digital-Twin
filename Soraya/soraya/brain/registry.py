"""Picks a mind from settings, and says something useful when it cannot.

`SORAYA_BRAIN` overrides the settings file, so you can force offline mode for
one run — `SORAYA_BRAIN=echo ./run.sh` — without editing anything.
"""

from __future__ import annotations

import os

from ..config import BrainSettings
from .base import Brain, BrainUnavailable
from .echo import EchoBrain

available_providers = ("claude", "openai_compat", "echo")


def build_brain(settings: BrainSettings) -> Brain:
    provider = os.environ.get("SORAYA_BRAIN", settings.provider).strip().lower()

    if provider == "echo":
        return EchoBrain()

    if provider == "claude":
        from .claude import ClaudeBrain
        return ClaudeBrain(model=settings.model, temperature=settings.temperature)

    if provider in ("openai_compat", "openai", "ollama", "lmstudio", "local"):
        from .openai_compat import OpenAICompatBrain
        return OpenAICompatBrain(
            model=settings.model,
            base_url=settings.base_url,
            api_key=os.environ.get("OPENAI_API_KEY"),
            temperature=settings.temperature
            if settings.temperature is not None else 0.7,
        )

    raise BrainUnavailable(
        f"Unknown brain provider {provider!r}. "
        f"Choose one of: {', '.join(available_providers)}."
    )


def build_brain_or_echo(settings: BrainSettings) -> tuple[Brain, str | None]:
    """The forgiving version, for startup.

    Returns the brain plus a warning to show the user. She must always start:
    a missing API key is a thing to tell someone about in the interface, not a
    reason for the app to refuse to open.
    """
    try:
        return build_brain(settings), None
    except BrainUnavailable as exc:
        return EchoBrain(), str(exc)
