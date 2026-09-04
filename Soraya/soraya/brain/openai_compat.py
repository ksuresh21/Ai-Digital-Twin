"""Any OpenAI-compatible endpoint — which in practice means any local model.

Ollama, LM Studio, llama.cpp's server, vLLM, LocalAI and OpenAI itself all
speak the same `/chat/completions` shape, so one adapter covers the entire
"switch it to a local model later" requirement.

Written against `urllib` from the standard library rather than the `openai`
package on purpose: it adds no dependency, and this folder's whole promise is
that it runs without an install step going wrong first.

What it cannot do: prompt caching (no such concept here — the two system
blocks are simply concatenated) and server-side web search (there is no server
to run it). The research agent checks for that capability rather than assuming.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from typing import Iterator

from .base import BrainUnavailable, Reply


class OpenAICompatBrain:
    name = "openai_compat"

    def __init__(
        self,
        model: str,
        base_url: str = "http://localhost:11434/v1",
        *,
        api_key: str | None = None,
        temperature: float | None = 0.7,
        timeout: float = 120.0,
    ) -> None:
        self.model = model
        self.base_url = base_url.rstrip("/")
        # Local servers ignore this; OpenAI needs it. "ollama" is the
        # conventional placeholder that satisfies servers which require the
        # header to be present but do not check it.
        self.api_key = api_key or "ollama"
        self.temperature = temperature
        self.timeout = timeout
        self.last_reply = Reply()

    def _post(self, payload: dict):
        request = urllib.request.Request(
            f"{self.base_url}/chat/completions",
            data=json.dumps(payload).encode(),
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.api_key}",
            },
            method="POST",
        )
        try:
            return urllib.request.urlopen(request, timeout=self.timeout)
        except urllib.error.HTTPError as exc:
            body = exc.read().decode(errors="replace")[:400]
            raise BrainUnavailable(
                f"The model server returned {exc.code}: {body}"
            ) from exc
        except urllib.error.URLError as exc:
            raise BrainUnavailable(
                f"No model server at {self.base_url}. Start one — for Ollama:\n"
                f"    ollama serve && ollama pull {self.model}\n"
                "or set brain.provider to \"claude\", or to \"echo\" to run "
                "with no model at all.\n"
                f"({exc.reason})"
            ) from exc

    def speak(
        self, stable_system: str, turn_system: str, messages: list[dict[str, str]],
        *, effort: str = "medium", max_tokens: int = 4096,
    ) -> Iterator[str]:
        system = stable_system if not turn_system else f"{stable_system}\n\n{turn_system}"
        payload = {
            "model": self.model,
            "messages": [{"role": "system", "content": system}, *messages],
            "max_tokens": max_tokens,
            "stream": True,
        }
        if self.temperature is not None:
            payload["temperature"] = self.temperature

        collected: list[str] = []
        with self._post(payload) as response:
            for raw in response:
                line = raw.decode("utf-8", errors="replace").strip()
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                try:
                    event = json.loads(data)
                except json.JSONDecodeError:
                    # Some servers emit keep-alive comments and partial
                    # frames. Dropping an unparseable line is correct; failing
                    # the whole reply over one is not.
                    continue
                choices = event.get("choices") or []
                if not choices:
                    continue
                piece = (choices[0].get("delta") or {}).get("content")
                if piece:
                    collected.append(piece)
                    yield piece

        self.last_reply = Reply(text="".join(collected), model=self.model)

    def judge(self, system: str, user: str, *, max_tokens: int = 400) -> str:
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "max_tokens": max_tokens,
            "temperature": 0,
            "stream": False,
        }
        with self._post(payload) as response:
            body = json.loads(response.read().decode())
        choices = body.get("choices") or [{}]
        return ((choices[0].get("message") or {}).get("content")) or ""

    def supports_web_research(self) -> bool:
        # No server-side tools on a local endpoint. The research agent needs a
        # client-side search tool to work here — see ROADMAP.md.
        return False
