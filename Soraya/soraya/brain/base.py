"""The seam every model sits behind.

One small protocol, because the whole point of this folder is that the model is
replaceable. Anything that can turn (system prompt, messages) into text can be
her mind: Claude today, a local Llama on Ollama tomorrow, something that does
not exist yet after that.

Two methods, not one. `speak` streams because a companion that pauses for four
seconds and then dumps a paragraph feels like a machine; `judge` does not,
because the affect read is small, structured, and nobody watches it happen.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterator, Protocol, runtime_checkable


class BrainUnavailable(RuntimeError):
    """No usable model: no key, no server, wrong package version.

    Its message is shown to the user, so it says what to do about it rather
    than what went wrong internally.
    """


@dataclass
class Reply:
    text: str = ""
    # Whatever the provider will tell us. Used for the cost line in the UI.
    input_tokens: int = 0
    output_tokens: int = 0
    cached_tokens: int = 0
    model: str = ""
    # Set when the provider stopped for a reason worth surfacing.
    stop_reason: str = ""
    # Anything the provider returned that does not fit above.
    extra: dict = field(default_factory=dict)


@runtime_checkable
class Brain(Protocol):
    """What a mind must be able to do."""

    name: str

    def speak(
        self,
        stable_system: str,
        turn_system: str,
        messages: list[dict[str, str]],
        *,
        effort: str = "medium",
        max_tokens: int = 4096,
    ) -> Iterator[str]:
        """Yields her reply in pieces as they arrive.

        `stable_system` is byte-identical every turn and `turn_system` is not;
        keeping them apart is what lets a provider cache the expensive half.
        A provider with no caching just concatenates them.
        """
        ...

    def judge(self, system: str, user: str, *, max_tokens: int = 400) -> str:
        """One non-streaming call, for structured work like the affect read."""
        ...
