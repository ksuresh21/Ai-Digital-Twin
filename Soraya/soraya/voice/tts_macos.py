"""Her voice, using the `say` command macOS already has.

No dependency, no model download, no API key, no network — and the voices are
genuinely good since macOS started shipping the neural ones (Ava, Zoe, Jamie).
`say -v '?'` lists what is installed.

Run as a background process rather than blocking, because she has to be
interruptible: the moment you start typing, whatever she was saying should
stop mid-word. A blocking call cannot do that.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


class MacSpeaker:
    #: Voices worth defaulting to, best first. Checked against what is
    #: actually installed, since none of them are guaranteed.
    PREFERRED = ("Ava (Premium)", "Ava", "Zoe", "Jamie", "Serena", "Samantha")

    def __init__(self) -> None:
        self._binary = shutil.which("say")
        self._process: subprocess.Popen | None = None

    @property
    def available(self) -> bool:
        return self._binary is not None

    @property
    def is_speaking(self) -> bool:
        return self._process is not None and self._process.poll() is None

    def voices(self) -> list[str]:
        """Installed voice names, English first."""
        if not self._binary:
            return []
        try:
            output = subprocess.run(
                [self._binary, "-v", "?"], capture_output=True, text=True,
                timeout=5, check=False,
            ).stdout
        except (OSError, subprocess.SubprocessError):
            return []
        names: list[str] = []
        for line in output.splitlines():
            # Format: "Ava (Premium)     en_US    # Hi, my name is Ava."
            if "#" not in line:
                continue
            name = line.split("#")[0]
            # The locale is the last whitespace-separated token before the #.
            parts = name.rsplit(None, 1)
            if len(parts) != 2:
                continue
            label, locale = parts[0].strip(), parts[1].strip()
            if label:
                names.append(f"{label}|{locale}")
        english = [n for n in names if "|en" in n]
        return english + [n for n in names if n not in english]

    def default_voice(self) -> str:
        installed = {n.split("|")[0] for n in self.voices()}
        for candidate in self.PREFERRED:
            if candidate in installed:
                return candidate
        return ""

    def say(self, text: str, *, rate: int = 165, volume: float = 0.8,
            voice: str = "") -> bool:
        if not self._binary or not text.strip():
            return False
        self.stop()

        # `say` has no volume flag, so volume rides in the text itself as an
        # embedded speech command. Undocumented-looking but it is a documented
        # part of Apple's speech synthesis markup, and it is the only way to
        # be quieter than the system volume without touching the system
        # volume — which a companion has absolutely no business doing.
        volume = max(0.0, min(1.0, volume))
        spoken = f"[[volm {volume:.2f}]] {text}"

        command = [self._binary, "-r", str(max(90, min(300, rate)))]
        if voice:
            command += ["-v", voice]
        command.append(spoken)
        try:
            self._process = subprocess.Popen(
                command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
        except OSError:
            return False
        return True

    def stop(self) -> None:
        if self.is_speaking and self._process is not None:
            self._process.terminate()
        self._process = None

    def to_file(self, text: str, path: Path, *, voice: str = "") -> Path | None:
        """Renders to AIFF, for the browser to play instead of the speakers.

        Needed for the web UI: the server may not be on the same machine as
        the person listening, and `say` always plays on the *server*.
        """
        if not self._binary or not text.strip():
            return None
        command = [self._binary, "-o", str(path)]
        if voice:
            command += ["-v", voice]
        command.append(text)
        try:
            subprocess.run(command, check=True, timeout=60,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.SubprocessError):
            return None
        return path if path.exists() else None
