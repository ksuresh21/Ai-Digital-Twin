"""Claude, via the official Anthropic SDK.

Three deliberate choices worth reading before changing anything here.

**Thinking stays on, effort goes down.** Conversation runs at `medium` effort
(research at `high`), rather than turning thinking off to save latency.
Disabling thinking on Opus 5 has two known failure modes — a tool call written
into the visible text instead of a `tool_use` block, and `<thinking>` tags
leaking into the reply — and lowering effort cuts cost without either.

**The system prompt is split in two.** The identity and craft rules are
byte-identical on every turn and carry the cache breakpoint; the posture, mood
and recalled memories go in a second block after it. Prompt caching is a prefix
match, so this ordering is the difference between paying for her personality
once a session and paying for it on every sentence.

**Refusal fallback is client-side.** The server-side `fallbacks` parameter needs
the beta messages endpoint, and the SDK pinned here (0.103.x) has no `betas`
argument on `messages.create`. Rather than reach through `extra_body` for a
safety net, this retries once on a second model when a reply comes back
refused. Same outcome, no beta surface. See ROADMAP.md to move it server-side
once the SDK is on 1.x.
"""

from __future__ import annotations

import os
from typing import Iterator

from .base import BrainUnavailable, Reply

# Sampling parameters are removed on Opus 5 and the 4.7+ family — sending
# temperature returns a 400. Anyone who sets one in config gets it dropped with
# a warning rather than a failed conversation.
_NO_SAMPLING = ("claude-opus-5", "claude-opus-4-8", "claude-opus-4-7",
                "claude-sonnet-5", "claude-fable-5")


class ClaudeBrain:
    name = "claude"

    def __init__(
        self,
        model: str = "claude-opus-5",
        *,
        fallback_model: str = "claude-opus-4-8",
        temperature: float | None = None,
    ) -> None:
        try:
            import anthropic
        except ImportError as exc:  # pragma: no cover - install-time only
            raise BrainUnavailable(
                "The anthropic package is not installed. Run:\n"
                "    pip install anthropic"
            ) from exc

        self._anthropic = anthropic
        self.model = model
        self.fallback_model = fallback_model
        self.temperature = temperature
        self.last_reply = Reply()

        # An unset ANTHROPIC_API_KEY does not mean there are no credentials —
        # the SDK also resolves ANTHROPIC_AUTH_TOKEN and an `ant auth login`
        # profile on disk. So construct the client and let it decide, rather
        # than checking for the env var and wrongly refusing to start.
        try:
            self._client = anthropic.Anthropic()
        except Exception as exc:
            raise BrainUnavailable(
                "Could not reach Claude. Either export a key:\n"
                "    export ANTHROPIC_API_KEY=sk-ant-...\n"
                "or sign in once with:\n"
                "    ant auth login\n"
                "or set SORAYA_BRAIN=echo to run her with no model at all.\n"
                f"({exc})"
            ) from exc

    # ---- request shaping ---------------------------------------------------

    def _system_blocks(self, stable: str, volatile: str) -> list[dict]:
        """Stable first and cached; volatile after the breakpoint."""
        blocks: list[dict] = [{
            "type": "text",
            "text": stable,
            # An hour, not the default five minutes: a companion is talked to
            # in bursts across a working day, and a five-minute TTL means
            # paying to re-cache her personality every time you come back from
            # a meeting.
            "cache_control": {"type": "ephemeral", "ttl": "1h"},
        }]
        if volatile:
            blocks.append({"type": "text", "text": volatile})
        return blocks

    def _kwargs(self, effort: str, max_tokens: int) -> dict:
        kwargs: dict = {
            "model": self.model,
            "max_tokens": max_tokens,
            "thinking": {"type": "adaptive"},
            "output_config": {"effort": effort},
        }
        if self.temperature is not None and self.model not in _NO_SAMPLING:
            kwargs["temperature"] = self.temperature
        return kwargs

    # ---- the protocol ------------------------------------------------------

    def speak(
        self, stable_system: str, turn_system: str, messages: list[dict[str, str]],
        *, effort: str = "medium", max_tokens: int = 4096,
    ) -> Iterator[str]:
        yield from self._stream(
            self.model, stable_system, turn_system, messages, effort, max_tokens
        )

    def _stream(
        self, model: str, stable: str, volatile: str,
        messages: list[dict[str, str]], effort: str, max_tokens: int,
    ) -> Iterator[str]:
        kwargs = self._kwargs(effort, max_tokens)
        kwargs["model"] = model
        try:
            with self._client.messages.stream(
                system=self._system_blocks(stable, volatile),
                messages=messages,
                **kwargs,
            ) as stream:
                for chunk in stream.text_stream:
                    yield chunk
                final = stream.get_final_message()
        except self._anthropic.APIStatusError as exc:
            raise BrainUnavailable(_explain(exc)) from exc
        except self._anthropic.APIConnectionError as exc:
            raise BrainUnavailable(
                "Could not reach the Claude API — check the network. "
                "Set SORAYA_BRAIN=echo to keep working offline."
            ) from exc

        usage = getattr(final, "usage", None)
        self.last_reply = Reply(
            text="".join(block.text for block in final.content
                         if getattr(block, "type", "") == "text"),
            input_tokens=getattr(usage, "input_tokens", 0) or 0,
            output_tokens=getattr(usage, "output_tokens", 0) or 0,
            cached_tokens=getattr(usage, "cache_read_input_tokens", 0) or 0,
            model=getattr(final, "model", model),
            stop_reason=getattr(final, "stop_reason", "") or "",
        )

        # The client-side half of the refusal fallback. A refusal arrives as a
        # normal 200 with an empty-ish body, so without this the user sees
        # nothing at all and assumes she is broken.
        if self.last_reply.stop_reason == "refusal" and model != self.fallback_model:
            yield from self._stream(
                self.fallback_model, stable, volatile, messages, effort, max_tokens
            )

    def judge(self, system: str, user: str, *, max_tokens: int = 400) -> str:
        """One small structured call. Low effort — this is not a hard question."""
        try:
            response = self._client.messages.create(
                model=self.model,
                max_tokens=max_tokens,
                thinking={"type": "adaptive"},
                output_config={"effort": "low"},
                system=[{
                    "type": "text", "text": system,
                    "cache_control": {"type": "ephemeral", "ttl": "1h"},
                }],
                messages=[{"role": "user", "content": user}],
            )
        except (self._anthropic.APIStatusError,
                self._anthropic.APIConnectionError) as exc:
            # A failed mood read must never take the conversation down with it.
            # The caller falls back to the fast lexical pass.
            raise BrainUnavailable(_explain(exc)) from exc
        return "".join(block.text for block in response.content
                       if getattr(block, "type", "") == "text")

    # ---- capability the local providers do not have ------------------------

    @property
    def client(self):
        """The raw SDK client, for the research agent's server-side tools."""
        return self._client

    def supports_web_research(self) -> bool:
        return True


def _explain(exc: Exception) -> str:
    """Turns an SDK exception into something worth showing a person."""
    status = getattr(exc, "status_code", None)
    if status == 401:
        return ("Claude rejected the credentials. Check ANTHROPIC_API_KEY, or "
                "run `ant auth login`.")
    if status == 404:
        return ("Claude does not recognise that model name. Check "
                "brain.model in settings.json.")
    if status == 429:
        return "Rate limited by the Claude API. Wait a moment and try again."
    if status and status >= 500:
        return "The Claude API is having trouble. Try again shortly."
    return f"Claude returned an error: {getattr(exc, 'message', exc)}"
