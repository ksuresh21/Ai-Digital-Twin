import os
import subprocess
import sys
from pathlib import Path

import pytest

from character_generator.clips import CLIPS
from character_generator.prompts import HUMAN_ANATOMY_PHRASES, assemble_prompts


def test_all_fourteen_prompts_are_fully_assembled():
    prompts = assemble_prompts({})
    assert len(prompts) == 14
    assert all("artist's choice" in prompt for prompt in prompts.values())
    assert all("CONTACT SHEET OVERRIDE" in prompt for prompt in prompts.values())
    assert not any("[STYLE BLOCK]" in prompt or "[CONSISTENCY BLOCK]" in prompt
                   or "[CHARACTER SHEET]" in prompt for prompt in prompts.values())


@pytest.mark.parametrize("subject_type", ["human", "pet"])
def test_every_frame_is_described_distinctly(subject_type):
    """Frames described as copies of each other get merged by the image model.

    Every four-frame clip came back with two or three figures while `idle`
    said "Frame 3: same as frame 2" and `walk` gave frames 2 and 4 identical
    text. A frame with no distinguishing description is not drawn twice.
    """
    for name, prompt in assemble_prompts({}, subject_type).items():
        lowered = prompt.lower()
        for phrase in ("same as frame", "identical to frame", "repeat frame"):
            assert phrase not in lowered, f"{subject_type}/{name} still copies a frame"


@pytest.mark.parametrize("subject_type", ["human", "pet"])
def test_every_prompt_states_its_exact_frame_count(subject_type):
    words = {2: "TWO", 3: "THREE", 4: "FOUR"}
    for clip in CLIPS:
        prompt = assemble_prompts({}, subject_type)[clip.name]
        assert f"exactly {clip.ask} ({words[clip.ask]})" in prompt
        assert f"exactly {clip.ask} frames" in prompt or f"exactly {clip.ask} frames ONLY" in prompt \
            or f"exactly {clip.ask} frames of" in prompt


@pytest.mark.parametrize("subject_type", ["human", "pet"])
def test_prompts_forbid_the_failures_seen_in_real_output(subject_type):
    """The model produced turnarounds, inset heads and partial figures."""
    for name, prompt in assemble_prompts({}, subject_type).items():
        lowered = prompt.lower()
        assert "turnaround" in lowered, f"{subject_type}/{name} does not forbid turnarounds"
        assert "inset close-up" in lowered, f"{subject_type}/{name} does not forbid insets"
        assert "one connected body" in lowered, f"{subject_type}/{name} lacks the connected-body rule"


def test_non_human_prompts_never_carry_human_anatomy():
    """The style block is retargeted by text substitution; if it silently
    stopped matching, pets would be asked for human hands and feet."""
    for name, prompt in assemble_prompts({"species": "cat"}, "pet").items():
        for phrase in HUMAN_ANATOMY_PHRASES:
            assert phrase not in prompt, f"pet/{name} leaked human anatomy: {phrase!r}"


def test_non_human_anatomy_is_taken_from_the_reference():
    """'Pet' also covers cartoon characters like Tom, Jerry or Chhota Bheem,
    who legitimately have hands and walk upright. The rule is to copy the
    reference's body plan, not to enforce or forbid one."""
    # Prompts are hard-wrapped, so phrases span newlines. Compare on a
    # whitespace-normalised copy rather than the raw text.
    idle = " ".join(assemble_prompts({"species": "cat"}, "pet")["idle"].split())
    assert "ANATOMY COMES FROM THE REFERENCE" in idle
    assert "never give it human hands" in idle
    assert "keep the upright posture and the hands" in idle


def test_dry_run_needs_no_api_key(reference_image: Path):
    environment = os.environ.copy()
    environment.pop("OPENAI_API_KEY", None)
    environment.pop("GEMINI_API_KEY", None)
    environment.pop("CLOUDFLARE_ACCOUNT_ID", None)
    environment.pop("CLOUDFLARE_API_TOKEN", None)
    result = subprocess.run(
        [sys.executable, "generate_character.py", str(reference_image),
         "--name", "Nish", "--dry-run"],
        cwd=Path(__file__).resolve().parents[1], env=environment,
        text=True, capture_output=True,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.count("=====") == 28  # opening and closing marker per prompt
    assert "14/14 YAWN" in result.stdout
