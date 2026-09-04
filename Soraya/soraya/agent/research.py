"""Her research mode: go and actually find out, then come back and say it.

Uses Claude's *server-side* web search tool, which means there is no scraper to
maintain, no search API key, no rate-limit dance and no HTML parsing — the
search runs on Anthropic's side and the results arrive as content blocks in the
same response.

The cost of that: it only works on the Claude provider. A local model has no
server to run the search on. `supports_web_research()` is how the caller finds
that out before promising the user an answer it cannot get; wiring a
client-side search tool for local models is in ROADMAP.md.

Effort is `high` here where conversation runs at `medium`. Research is the one
thing she does that is genuinely hard, and it is also the one thing where you
are willing to wait.
"""

from __future__ import annotations

from dataclasses import dataclass, field

# The dated tool type matters. `web_search_20260209` has dynamic filtering and
# needs Opus 4.6+/Sonnet 4.6+; older models take the basic `web_search_20250305`.
# Naming the wrong one for the model is a 400, so it is chosen per model rather
# than hard-coded.
_MODERN_SEARCH = "web_search_20260209"
_BASIC_SEARCH = "web_search_20250305"
_MODERN_MODELS = (
    "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6",
    "claude-sonnet-5", "claude-sonnet-4-6", "claude-fable-5", "claude-fable-5-1",
)

RESEARCH_SYSTEM = """\
You are looking something up for the person you keep company with. You are the
same character as always — brief, warm, a bit dry — but this turn you are being
useful rather than companionable.

Search before you answer. Do not answer from memory on anything that could have
changed. If the sources disagree, say so rather than picking one.

Then report back the way a person would: the answer first, in plain sentences.
No headings. No bullet lists unless you are genuinely listing things, and then
at most four. Name your sources inline, as you would in speech — "according to
X" — not as footnotes.

If what you found is thin or contradictory, say that. Being honestly uncertain
is worth more than being confidently wrong, and she does not bluff.
"""


@dataclass
class Finding:
    title: str = ""
    url: str = ""


@dataclass
class ResearchResult:
    text: str = ""
    findings: list[Finding] = field(default_factory=list)
    searches: int = 0
    input_tokens: int = 0
    output_tokens: int = 0
    error: str = ""

    @property
    def ok(self) -> bool:
        return bool(self.text) and not self.error


def search_tool_for(model: str) -> dict:
    tool_type = _MODERN_SEARCH if model in _MODERN_MODELS else _BASIC_SEARCH
    return {"type": tool_type, "name": "web_search", "max_uses": 6}


def research(brain, question: str, *, max_tokens: int = 8000,
             effort: str = "high") -> ResearchResult:
    """Runs one research turn. Returns a result rather than raising.

    Streamed because a search-and-read turn can run for a minute or more, and a
    non-streaming request that long risks the HTTP timeout — the SDK default is
    ten minutes but the failure mode of hitting it is losing the whole answer.
    """
    if not hasattr(brain, "supports_web_research") or not brain.supports_web_research():
        return ResearchResult(error=(
            f"The {getattr(brain, 'name', 'current')} brain cannot search the "
            "web — server-side search only exists on Claude. Switch "
            "brain.provider to \"claude\" for research, or ask me something "
            "I can answer without looking it up."
        ))

    client = getattr(brain, "client", None)
    if client is None:
        return ResearchResult(error="This brain exposes no client to search with.")

    model = getattr(brain, "model", "claude-opus-5")
    try:
        with client.messages.stream(
            model=model,
            max_tokens=max_tokens,
            thinking={"type": "adaptive"},
            output_config={"effort": effort},
            system=[{
                "type": "text", "text": RESEARCH_SYSTEM,
                "cache_control": {"type": "ephemeral", "ttl": "1h"},
            }],
            tools=[search_tool_for(model)],
            messages=[{"role": "user", "content": question}],
        ) as stream:
            for _ in stream.text_stream:
                # Drained rather than yielded: research is a "go away and come
                # back" action in the interface, not a live typing effect, and
                # the citations are only complete on the final message.
                pass
            final = stream.get_final_message()
    except Exception as exc:  # noqa: BLE001 - reported, never raised
        return ResearchResult(error=f"The search did not complete: {exc}")

    return _collect(final)


def _collect(message) -> ResearchResult:
    """Pulls the answer and the sources out of the response blocks."""
    text_parts: list[str] = []
    findings: list[Finding] = []
    searches = 0
    seen: set[str] = set()

    for block in getattr(message, "content", []) or []:
        kind = getattr(block, "type", "")
        if kind == "text":
            text_parts.append(getattr(block, "text", ""))
        elif kind == "server_tool_use":
            searches += 1
        elif kind == "web_search_tool_result":
            # A success `content` is a *list* of results; an error `content` is
            # a single object. Indexing without checking is the classic bug
            # here, and it only shows up when a search fails.
            payload = getattr(block, "content", None)
            if not isinstance(payload, list):
                continue
            for item in payload:
                url = getattr(item, "url", "") or ""
                if not url or url in seen:
                    continue
                seen.add(url)
                findings.append(
                    Finding(title=getattr(item, "title", "") or url, url=url)
                )

    usage = getattr(message, "usage", None)
    return ResearchResult(
        text="".join(text_parts).strip(),
        findings=findings,
        searches=searches,
        input_tokens=getattr(usage, "input_tokens", 0) or 0,
        output_tokens=getattr(usage, "output_tokens", 0) or 0,
    )
