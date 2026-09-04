"""Soraya — the mind, voice and ears of the digital twin.

`AiTwin/` already solves *presence*: a pixel-art character who lives on your
screen, walks in, and can be seen. What it cannot do is think, listen or speak.
This package is that half, built as a standalone service so it can be run and
tested on its own today and wired into the Swift app later over one HTTP seam.

Nothing here imports AppKit, Swift, or anything from `AiTwin/`. See
ARCHITECTURE.md for the seams and INTEGRATION.md for the wiring.
"""

__version__ = "0.1.0"
