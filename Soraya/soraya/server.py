"""A local HTTP server for the browser UI, on the standard library alone.

No FastAPI, no uvicorn, no pydantic. That is not minimalism for its own sake:
the FastAPI install on this machine is broken (a pydantic v1/v2 mismatch), and
a companion you cannot start because of somebody else's dependency conflict is
worse than one with a plainer server. `python3 -m soraya.server` and it runs.

Streaming is a chunked `text/event-stream` on a POST, read in the browser with
`fetch` + a stream reader rather than `EventSource` — `EventSource` is GET-only
and a conversation turn has a body.

Bound to 127.0.0.1. This process can read her memories, spend money against an
API key, and speak out loud through the speakers; it has no business being
reachable from the network.
"""

from __future__ import annotations

import json
import mimetypes
import time
from dataclasses import asdict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

from .agent.research import research
from .companion import ASSETS, Companion
from .config import Settings
from .voice.wake import WakeMatcher

UI = Path(__file__).resolve().parent / "ui"


class Handler(BaseHTTPRequestHandler):
    server_version = "Soraya/0.1"
    companion: Companion  # injected in serve()

    # ---- plumbing ---------------------------------------------------------

    def log_message(self, fmt: str, *args) -> None:
        # The default logs every request to stderr, which buries the one line
        # anyone actually wants (the URL to open).
        return

    def _send(self, code: int, body: bytes, content_type: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            # The browser navigated away mid-response. Not an error.
            pass

    def _json(self, payload, code: int = 200) -> None:
        self._send(code, json.dumps(payload).encode(), "application/json")

    def _body(self) -> dict:
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            return {}
        if length <= 0:
            return {}
        try:
            parsed = json.loads(self.rfile.read(length).decode())
        except (json.JSONDecodeError, UnicodeDecodeError):
            return {}
        return parsed if isinstance(parsed, dict) else {}

    def _file(self, path: Path, root: Path) -> None:
        """Serves a file, refusing anything that escapes `root`.

        The check is on the *resolved* path, not the URL: `..` is easy to strip
        and symlinks are not, and this process sits next to somebody's private
        conversation history.
        """
        try:
            resolved = path.resolve()
            resolved.relative_to(root.resolve())
        except (ValueError, OSError):
            self._json({"error": "not found"}, 404)
            return
        if not resolved.is_file():
            self._json({"error": "not found"}, 404)
            return
        kind = mimetypes.guess_type(resolved.name)[0] or "application/octet-stream"
        self._send(200, resolved.read_bytes(), kind)

    # ---- routes -----------------------------------------------------------

    def do_GET(self) -> None:  # noqa: N802 - stdlib naming
        route = unquote(urlparse(self.path).path)

        if route in ("/", "/index.html"):
            self._file(UI / "index.html", UI)
        elif route.startswith("/ui/"):
            self._file(UI / route[4:], UI)
        elif route.startswith("/art/"):
            self._file(ASSETS / route[5:], ASSETS)
        elif route == "/api/state":
            self._json(self._state())
        elif route == "/api/notes":
            self._json({"notes": [asdict(n) for n in self.companion.memory.notes()]})
        elif route == "/api/history":
            self._json({
                "turns": [asdict(t) for t in self.companion.memory.recent_turns(40)]
            })
        elif route == "/api/pulse":
            approach = self.companion.consider_approach()
            self._json(asdict(approach))
        else:
            self._json({"error": "not found"}, 404)

    def do_POST(self) -> None:  # noqa: N802
        route = unquote(urlparse(self.path).path)
        body = self._body()

        if route == "/api/say":
            self._stream_turn(str(body.get("message", "")))
        elif route == "/api/approach":
            approach = self.companion.consider_approach(
                unlocked_just_now=bool(body.get("unlocked")),
            )
            if body.get("force") and not approach.should:
                from .pulse import Approach
                approach = Approach(
                    True, "forced",
                    situation="You have decided to wander over and say something.",
                )
            self._stream_events(self.companion.approach(approach))
        elif route == "/api/settings":
            self._json(self._apply_settings(body))
        elif route == "/api/research":
            self._json(self._research(str(body.get("question", ""))))
        elif route == "/api/wake":
            matcher = WakeMatcher(self.companion.settings.ears.wake_phrases)
            self._json(asdict(matcher.match(str(body.get("heard", "")))))
        elif route == "/api/remember":
            self._json({"kept": self.companion.note_from_last_exchange()})
        elif route == "/api/stop-voice":
            self.companion._mac_speaker.stop()
            self._json({"ok": True})
        elif route == "/api/forget":
            # Destructive, so it takes an explicit confirmation in the body
            # rather than firing on a bare POST.
            if body.get("confirm") != "yes":
                self._json({"error": "needs confirm: yes"}, 400)
                return
            self.companion.memory.forget_all()
            self._json({"ok": True})
        else:
            self._json({"error": "not found"}, 404)

    # ---- handlers ---------------------------------------------------------

    def _state(self) -> dict:
        companion = self.companion
        sprite = companion.sprite
        speaker = companion._mac_speaker
        return {
            "settings": companion.settings.to_dict(),
            "brain": {
                "name": getattr(companion.brain, "name", "?"),
                "model": getattr(companion.brain, "model", ""),
                "warning": companion.brain_warning,
                "can_research": bool(
                    getattr(companion.brain, "supports_web_research", lambda: False)()
                ),
            },
            "voice": {
                "available": speaker.available,
                "voices": speaker.voices(),
                "default": speaker.default_voice(),
            },
            "sprite": {
                "pack": sprite.name,
                "clips": sprite.manifest(),
                "missing": sprite.missing_clips(),
                "packs": sorted(
                    p.name for p in ASSETS.iterdir() if p.is_dir()
                ) if ASSETS.is_dir() else [],
            },
            "affect": asdict(companion.last_affect),
        }

    def _apply_settings(self, body: dict) -> dict:
        merged = {**self.companion.settings.to_dict(), **body}
        # Nested blocks are merged rather than replaced, so the UI can PATCH
        # one field — `{"voice": {"enabled": true}}` — without having to send
        # back every setting it did not touch.
        for key in ("voice", "ears", "brain", "presence"):
            if isinstance(body.get(key), dict):
                merged[key] = {
                    **self.companion.settings.to_dict()[key], **body[key]
                }
        self.companion.apply(Settings.from_dict(merged))
        return self._state()

    def _research(self, question: str) -> dict:
        if not question.strip():
            return {"error": "nothing to look up"}
        result = research(
            self.companion.brain,
            question,
            effort=self.companion.settings.brain.research_effort,
        )
        return asdict(result)

    def _stream_turn(self, message: str) -> None:
        self._stream_events(self.companion.respond(message))

    def _stream_events(self, events) -> None:
        """Server-sent events over a chunked response."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()
        try:
            for event in events:
                self.wfile.write(f"data: {json.dumps(event)}\n\n".encode())
                self.wfile.flush()
            self.wfile.write(b"data: {\"type\": \"end\"}\n\n")
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            # The tab was closed while she was talking. Nothing to report.
            pass
        except Exception as exc:  # noqa: BLE001
            # A crash inside a generator must reach the interface, not vanish
            # into a dead connection and look like she stopped responding.
            try:
                payload = json.dumps({"type": "error", "message": str(exc)})
                self.wfile.write(f"data: {payload}\n\n".encode())
                self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError, OSError):
                pass


def serve(port: int = 8765, companion: Companion | None = None) -> None:
    Handler.companion = companion or Companion()
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    brain = Handler.companion.brain
    # flush=True throughout: Python block-buffers stdout when it is not a
    # terminal, so under `./run.sh > log` or a LaunchAgent the one line anyone
    # needs — the URL — did not appear until the process exited.
    print(f"\n  Soraya is listening on  http://127.0.0.1:{port}", flush=True)
    print(f"  brain: {getattr(brain, 'name', '?')} "
          f"{getattr(brain, 'model', '')}".rstrip(), flush=True)
    if Handler.companion.brain_warning:
        print(f"\n  ! {Handler.companion.brain_warning}\n", flush=True)
    print("  Ctrl-C to stop.\n", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n  Bye.")
    finally:
        server.server_close()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Run Soraya's local server.")
    parser.add_argument("--port", type=int, default=8765)
    serve(parser.parse_args().port)
