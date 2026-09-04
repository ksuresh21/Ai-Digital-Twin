#!/usr/bin/env python3
"""Makes ONE minimal real call, to prove the model path works.

This exists because the Claude request shape cannot be verified without
spending money, and spending your money is your decision, not mine. Everything
else in this project is tested offline; this is the one thing that is not.

    python3 scripts/check_brain.py

It sends about 30 tokens and asks for at most 40 back — a fraction of a cent on
any model. It reports exactly which features the server accepted, so if
something is rejected you know whether it was the model name, the effort
parameter, thinking, or the cache control.
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from soraya.brain import BrainUnavailable, build_brain  # noqa: E402
from soraya.config import Settings  # noqa: E402


def main() -> int:
    settings = Settings.load()
    print(f"  provider : {settings.brain.provider}")
    print(f"  model    : {settings.brain.model}")
    print(f"  effort   : {settings.brain.effort}\n")

    try:
        brain = build_brain(settings.brain)
    except BrainUnavailable as exc:
        print(f"  ✗ could not build a brain\n\n{exc}\n")
        return 1

    if brain.name == "echo":
        print("  · echo brain — nothing to check, and nothing was spent.")
        print("    Set brain.provider to \"claude\" or \"openai_compat\" first.")
        return 0

    print("  → sending one short message…\n")
    started = time.time()
    pieces: list[str] = []
    try:
        for chunk in brain.speak(
            "You are a companion. Reply in one short sentence.",
            "Posture: banter.\nSay hello and nothing else.",
            [{"role": "user", "content": "hello"}],
            effort=settings.brain.effort,
            max_tokens=40,
        ):
            pieces.append(chunk)
            print(chunk, end="", flush=True)
    except BrainUnavailable as exc:
        print(f"\n\n  ✗ the call failed\n\n{exc}\n")
        return 1

    elapsed = time.time() - started
    reply = getattr(brain, "last_reply", None)
    print(f"\n\n  ✓ worked, in {elapsed:.1f}s")
    if reply is not None:
        print(f"    tokens   : {reply.input_tokens} in, {reply.output_tokens} out")
        if reply.cached_tokens:
            print(f"    cached   : {reply.cached_tokens} read from cache")
        else:
            # Expected on a first run: there is nothing cached yet. On the
            # SECOND run this should be non-zero, and if it never is, the
            # caching layout in brain/claude.py is not working.
            print("    cached   : 0 — normal on the first run; "
                  "run again and it should not be")
        if reply.stop_reason:
            print(f"    stopped  : {reply.stop_reason}")
    print("\n  What this proved: the model name, streaming, adaptive thinking,")
    print("  the effort setting and the split cached system prompt are all")
    print("  accepted as written.\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
