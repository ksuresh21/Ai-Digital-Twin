"""Tests for the parts where being wrong matters.

The shape of this suite mirrors the Swift app's: the pure decisions are tested
hard and the side effects are tested through their seams. Nothing here touches
the network or costs money — the echo brain stands in for the model — so the
whole suite runs in well under a second and can be run on a plane.

What is deliberately *not* tested: whether her replies are any good. That is a
judgement, not an assertion, and pretending otherwise produces tests that pass
while she says something awful. See ROADMAP.md § Evaluating her.
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from soraya import emotion, persona, pulse
from soraya.brain.echo import EchoBrain
from soraya.companion import Companion, _first_json_array, _first_json_object
from soraya.config import Settings, VoiceSettings, in_quiet_hours
from soraya.memory import Memory, Turn
from soraya.presence.sprite import CLIPS, Sprite, clip_for
from soraya.voice.base import speech_text
from soraya.voice.wake import WakeMatcher


@pytest.fixture()
def home(tmp_path: Path) -> Path:
    return tmp_path


@pytest.fixture()
def her(home: Path, monkeypatch) -> Companion:
    monkeypatch.setenv("SORAYA_BRAIN", "echo")
    return Companion(Settings(user_name="Suresh"), home)


# ---------------------------------------------------------------- settings


class TestSettings:
    def test_voice_is_off_until_asked_for(self):
        # A companion that starts talking out loud the first time you run it is
        # one you turn off and never turn back on.
        assert Settings().voice.enabled is False

    def test_a_missing_field_takes_its_default(self):
        loaded = Settings.from_dict({"user_name": "Suresh"})
        assert loaded.user_name == "Suresh"
        assert loaded.brain.model == Settings().brain.model

    def test_an_unknown_field_is_ignored_rather_than_fatal(self):
        # Forward compatibility: a file written by a later version must load.
        loaded = Settings.from_dict({"user_name": "S", "invented_later": True})
        assert loaded.user_name == "S"

    def test_a_corrupt_file_does_not_stop_her_starting(self, tmp_path: Path):
        path = tmp_path / "settings.json"
        path.write_text("{ this is not json")
        assert Settings.load(path).name == "Soraya"

    def test_settings_survive_a_save_and_load(self, tmp_path: Path):
        original = Settings(user_name="Suresh")
        original.voice.enabled = True
        original.voice.name = "Ava"
        original.presence.initiative = "lively"
        original.save(tmp_path / "settings.json")
        assert Settings.load(tmp_path / "settings.json") == original


class TestQuietHours:
    """Ported from the Swift app, including the case it exists to get right."""

    def test_the_window_crossing_midnight_is_quiet_at_both_ends(self):
        voice = VoiceSettings()  # 22:00 -> 07:00
        assert in_quiet_hours(voice, 23, 0)
        assert in_quiet_hours(voice, 3, 0)
        assert in_quiet_hours(voice, 6, 59)
        assert not in_quiet_hours(voice, 7, 0)
        assert not in_quiet_hours(voice, 12, 0)

    def test_an_empty_window_silences_nothing(self):
        # Otherwise one mis-set number mutes her forever.
        voice = VoiceSettings(quiet_start_minute=600, quiet_end_minute=600)
        assert not in_quiet_hours(voice, 10, 0)

    def test_disabled_means_disabled(self):
        voice = VoiceSettings(quiet_hours_enabled=False)
        assert not in_quiet_hours(voice, 23, 0)


# ------------------------------------------------------------------ emotion


class TestFastRead:
    @pytest.mark.parametrize(
        "message,label,negative",
        [
            ("I am so stressed, deadline tomorrow", "stressed", True),
            ("so tired today, completely drained", "flat", True),
            ("FINALLY SHIPPED IT!!", "elated", False),
            ("thanks, that's good", "content", False),
        ],
    )
    def test_it_reads_the_obvious_cases(self, message, label, negative):
        affect = emotion.read_fast(message)
        assert affect.label == label
        assert (affect.valence < 0) is negative

    def test_hot_and_flat_are_told_apart(self):
        # The whole reason for two axes: both are negative, and they want
        # opposite responses from her.
        hot = emotion.read_fast("this is so frustrating, I'm fed up")
        flat = emotion.read_fast("I'm exhausted and a bit numb")
        assert hot.valence < 0 and flat.valence < 0
        assert hot.arousal > flat.arousal

    def test_shouting_raises_arousal_without_changing_valence(self):
        quiet = emotion.read_fast("this is frustrating")
        loud = emotion.read_fast("THIS IS FRUSTRATING")
        assert loud.arousal > quiet.arousal

    def test_the_fast_read_never_claims_confidence(self):
        # It exists to hold the door open until the model answers. If it were
        # confident it would override the better read.
        for message in ("I'm furious", "great news", "hello", ""):
            assert emotion.read_fast(message).confidence <= 0.4

    def test_empty_input_is_neutral_not_an_error(self):
        assert emotion.read_fast("   ") == emotion.NEUTRAL


class TestModelRead:
    def test_a_malformed_read_degrades_to_neutral(self):
        # The model is a collaborator, not a trusted input.
        affect = emotion.Affect.from_model({"valence": "very bad", "label": 12})
        assert affect.valence == 0.0
        assert affect.label == "neutral"

    def test_out_of_range_numbers_are_clamped(self):
        affect = emotion.Affect.from_model({"valence": 9, "arousal": -4})
        assert affect.valence == 1.0
        assert affect.arousal == 0.0

    def test_an_empty_read_is_survivable(self):
        assert emotion.Affect.from_model({}).label == "neutral"


class TestPosture:
    def test_a_safety_signal_outranks_everything(self):
        affect = emotion.read_fast("I want to kill myself")
        response = emotion.posture_for(affect)
        assert response.signpost_help
        assert response.posture == "hold"

    def test_leave_me_alone_beats_any_reading_of_the_mood(self):
        response = emotion.posture_for(emotion.read_fast("not now, busy"))
        assert response.posture == "retreat"
        # Short, and no question — a question is not leaving.
        assert response.word_ceiling < 25

    def test_a_direct_question_is_answered_not_therapised(self):
        # Being asked "what time is it" and getting "how are you feeling?"
        # back is the most irritating failure this design can have.
        response = emotion.posture_for(emotion.read_fast("what time is my meeting?"))
        assert response.posture == "answer"
        assert response.reframe is False

    def test_but_a_question_under_real_distress_still_gets_held(self):
        affect = emotion.Affect(valence=-0.8, arousal=0.7, asked_a_question=True,
                                confidence=0.9)
        assert emotion.posture_for(affect).posture == "ground"

    def test_hot_and_flat_negatives_get_different_postures(self):
        hot = emotion.Affect(valence=-0.6, arousal=0.8, confidence=0.9)
        flat = emotion.Affect(valence=-0.6, arousal=0.1, confidence=0.9)
        assert emotion.posture_for(hot).posture == "ground"
        assert emotion.posture_for(flat).posture == "support"

    def test_she_is_briefer_when_she_started_it(self):
        neutral = emotion.NEUTRAL
        asked = emotion.posture_for(neutral, is_proactive=False)
        uninvited = emotion.posture_for(neutral, is_proactive=True)
        assert uninvited.word_ceiling < asked.word_ceiling

    def test_every_posture_has_guidance_and_a_real_clip(self):
        # A posture with no text would silently produce a promptless turn; one
        # with no clip would leave her frozen on the wrong pose.
        for name, guidance in emotion.POSTURES.items():
            assert guidance.strip()
            assert clip_for(name) in CLIPS


# ------------------------------------------------------------------- memory


class TestMemory:
    def test_a_near_duplicate_note_is_not_stored_twice(self, home: Path):
        memory = Memory(home)
        assert memory.remember("has a cat called Mowgli")
        # Jaccard scores this pair 0.4 and lets it through; the overlap
        # coefficient catches it. This is the case that drove that choice.
        assert memory.remember("owns a cat named Mowgli") is None
        assert len(memory.notes()) == 1

    def test_an_unrelated_note_is_stored(self, home: Path):
        memory = Memory(home)
        memory.remember("has a cat called Mowgli")
        assert memory.remember("hates video calls before 10am")
        assert len(memory.notes()) == 2

    def test_recall_returns_nothing_rather_than_padding(self, home: Path):
        # An irrelevant memory in the prompt is worse than a short prompt,
        # because she will find a way to mention it.
        memory = Memory(home)
        memory.remember("has a cat called Mowgli")
        assert memory.recall("what is the capital of France") == []

    def test_recall_finds_the_relevant_note(self, home: Path):
        memory = Memory(home)
        memory.remember("has a cat called Mowgli")
        memory.remember("works on a data migration")
        assert memory.recall("how is the migration going") == [
            "works on a data migration"
        ]

    def test_history_always_opens_on_a_user_turn(self, home: Path):
        # Every provider rejects a history that starts with the assistant.
        memory = Memory(home)
        memory.add_turn(Turn("soraya", "hey there"))
        memory.add_turn(Turn("user", "hello"))
        messages = memory.as_messages()
        assert messages[0]["role"] == "user"

    def test_consecutive_turns_from_one_speaker_are_merged(self, home: Path):
        memory = Memory(home)
        memory.add_turn(Turn("user", "one"))
        memory.add_turn(Turn("user", "two"))
        assert memory.as_messages() == [{"role": "user", "content": "one\ntwo"}]

    def test_a_truncated_line_from_a_crash_is_skipped(self, home: Path):
        memory = Memory(home)
        memory.add_turn(Turn("user", "intact"))
        with memory.turns_path.open("a") as handle:
            handle.write('{"role": "user", "text": "trunca')
        # One bad line must cost one line, not the whole history.
        assert [t.text for t in memory.recent_turns()] == ["intact"]

    def test_forget_all_actually_removes_the_files(self, home: Path):
        memory = Memory(home)
        memory.add_turn(Turn("user", "something private"))
        memory.remember("a private fact")
        memory.forget_all()
        assert memory.notes() == []
        assert memory.recent_turns() == []


# -------------------------------------------------------------------- pulse


class TestApproach:
    @staticmethod
    def _at(hhmm: str) -> float:
        return time.mktime(time.strptime(f"2026-09-03 {hhmm}", "%Y-%m-%d %H:%M"))

    def test_the_floor_beats_every_other_rule(self):
        # The single most important number in the file. Without it,
        # "emotionally responsive" becomes "interrupts you constantly".
        now = self._at("14:00")
        approach = pulse.consider(
            Settings(), now=now, last_spoke_at=now - 99999,
            last_approach_at=now - 60, roll=0.0, mood_label="stressed",
        )
        assert not approach.should
        assert approach.reason == "too soon since the last time"

    def test_quiet_hours_stop_her_wandering_over(self):
        now = self._at("23:30")
        approach = pulse.consider(Settings(), now=now,
                                  last_spoke_at=now - 99999, roll=0.0)
        assert not approach.should

    def test_but_an_unlock_greeting_survives_quiet_hours(self):
        # It is a response to you arriving, not an interruption of anything.
        now = self._at("23:30")
        assert pulse.consider(Settings(), now=now,
                              unlocked_just_now=True).should

    def test_she_does_not_talk_to_an_empty_chair(self):
        now = self._at("14:00")
        approach = pulse.consider(Settings(), now=now,
                                  last_spoke_at=now - 99999,
                                  idle_minutes=45, roll=0.0)
        assert not approach.should
        assert approach.reason == "nobody at the desk"

    def test_the_dice_mean_she_is_a_presence_not_a_scheduled_event(self):
        now = self._at("14:00")
        common = dict(now=now, last_spoke_at=now - 99999)
        assert pulse.consider(Settings(), roll=0.0, **common).should
        assert not pulse.consider(Settings(), roll=0.99, **common).should

    def test_initiative_changes_how_long_she_waits(self):
        now = self._at("14:00")
        # 30 minutes of silence: lively steps in, quiet does not.
        common = dict(now=now, last_spoke_at=now - 30 * 60, roll=0.0)
        lively = Settings()
        lively.presence.initiative = "lively"
        lively.presence.min_minutes_between_approaches = 1
        quiet = Settings()
        quiet.presence.initiative = "quiet"
        quiet.presence.min_minutes_between_approaches = 1
        assert pulse.consider(lively, **common).should
        assert not pulse.consider(quiet, **common).should

    def test_an_unknown_initiative_falls_back_rather_than_crashing(self):
        now = self._at("14:00")
        settings = Settings()
        settings.presence.initiative = "chaotic"
        pulse.consider(settings, now=now, last_spoke_at=now - 99999, roll=0.0)


# ------------------------------------------------------------------- persona


class TestPersona:
    def test_the_stable_half_is_byte_identical_across_turns(self):
        # This is what makes prompt caching work. If it varies, the cache
        # misses every turn and her personality is paid for per sentence.
        settings = Settings(user_name="Suresh")
        assert persona.stable_prompt(settings) == persona.stable_prompt(settings)

    def test_the_name_lives_in_the_volatile_half_not_the_stable_one(self):
        stable = persona.stable_prompt(Settings(user_name="Suresh"))
        assert "Suresh" not in stable

    def test_reframing_is_asked_for_only_when_the_posture_wants_it(self):
        settings = Settings()
        hot = emotion.Affect(valence=-0.6, arousal=0.8, confidence=0.9)
        question = emotion.Affect(asked_a_question=True, confidence=0.9)
        assert "in your own words" in persona.turn_prompt(
            settings, hot, emotion.posture_for(hot))
        assert "in your own words" not in persona.turn_prompt(
            settings, question, emotion.posture_for(question))

    def test_a_low_confidence_read_is_not_mentioned_to_her_at_all(self):
        # Telling her "they seem stressed" on a 15%-confidence guess is how she
        # ends up confidently wrong about someone's mood.
        settings = Settings()
        vague = emotion.Affect(label="stressed", confidence=0.2)
        assert "they seem" not in persona.turn_prompt(
            settings, vague, emotion.posture_for(vague))

    def test_a_confident_read_is_hedged_when_it_is_mentioned(self):
        settings = Settings()
        sure = emotion.Affect(valence=-0.6, arousal=0.8, label="stressed",
                              confidence=0.9)
        prompt = persona.turn_prompt(settings, sure, emotion.posture_for(sure))
        assert "may be wrong" in prompt


# --------------------------------------------------------------------- wake


class TestWake:
    def test_the_common_misrecognitions_are_caught(self):
        matcher = WakeMatcher(["hey soraya"])
        for heard in ("Hey Soraya", "hey sorry a", "hey soraia", "hey so raya"):
            assert matcher.match(heard).hit, heard

    def test_the_request_after_the_wake_phrase_is_extracted(self):
        matcher = WakeMatcher(["hey soraya"])
        assert matcher.match("hey soraya what's the weather").remainder == (
            "what s the weather"
        )

    def test_ordinary_speech_does_not_summon_her(self):
        matcher = WakeMatcher(["hey soraya"])
        for heard in ("sorry about that", "I am sorry", "can you help me", ""):
            assert not matcher.match(heard).hit, heard

    def test_the_default_phrases_avoid_the_sorry_collision(self):
        # The bare name is left out of the defaults precisely because after
        # normalisation "soraya" and "sorry a" are the same string.
        matcher = WakeMatcher(Settings().ears.wake_phrases)
        assert not matcher.match("sorry about that").hit
        assert matcher.match("hey soraya").hit

    def test_a_longer_phrase_wins_over_a_shorter_one(self):
        matcher = WakeMatcher(["soraya", "soraya come back"])
        assert matcher.match("soraya come back").phrase == "soraya come back"

    def test_a_short_custom_phrase_is_matched_exactly_not_fuzzily(self):
        # One edit of slack on a three-letter phrase matches most of English.
        matcher = WakeMatcher(["hi"])
        assert matcher.match("hi there").hit
        assert not matcher.match("ho there").hit


# -------------------------------------------------------------------- voice


class TestSpeechText:
    def test_markdown_is_stripped_before_it_is_read_aloud(self):
        assert speech_text("**Bold** and a [link](http://x.com).") == (
            "Bold and a link."
        )

    def test_a_long_reply_is_cut_at_a_sentence_end(self):
        long = "First sentence. " + ("padding words here. " * 40)
        spoken = speech_text(long, limit=120)
        assert len(spoken) <= 121
        assert spoken.endswith((".", "…"))

    def test_a_short_reply_is_left_alone(self):
        assert speech_text("Still here.") == "Still here."


# ------------------------------------------------------------------- sprite


class TestSprite:
    def test_the_placeholder_pack_has_every_clip(self):
        pack = Path(__file__).resolve().parent.parent / "assets" / "characters" / "Soraya"
        if not pack.is_dir():
            pytest.skip("placeholders not generated")
        assert Sprite(pack).missing_clips() == []

    def test_frames_are_ordered_numerically_not_lexically(self, home: Path):
        # Lexical sort puts frame 10 before frame 2, which looks like bad
        # animation rather than like a sorting bug, so it survives for ages.
        folder = home / "Idle"
        folder.mkdir()
        for index in (1, 2, 10, 11):
            (folder / f"idle_{index}.png").write_bytes(b"")
        names = [p.name for p in Sprite(home).frames("idle")]
        assert names == ["idle_1.png", "idle_2.png", "idle_10.png", "idle_11.png"]

    def test_a_missing_clip_falls_back_to_idle_and_says_so(self, home: Path):
        folder = home / "Idle"
        folder.mkdir()
        (folder / "idle_1.png").write_bytes(b"")
        assert Sprite(home).resolve("cheer")[0] == "idle"

    def test_hidden_files_are_not_animation_frames(self, home: Path):
        folder = home / "Idle"
        folder.mkdir()
        (folder / "idle_1.png").write_bytes(b"")
        (folder / ".DS_Store.png").write_bytes(b"")
        assert len(Sprite(home).frames("idle")) == 1

    def test_the_pose_follows_the_moment_not_only_the_mood(self):
        # She should not look concerned before she has heard you.
        assert clip_for("ground", state="listening") == "listening"
        assert clip_for("ground", state="thinking") == "thinking"
        assert clip_for("ground", state="reply") == "concerned"


# ------------------------------------------------------------------ parsing


class TestJSONSalvage:
    def test_json_is_found_inside_a_code_fence_and_prose(self):
        raw = 'Sure!\n```json\n{"valence": -0.5}\n```\nHope that helps.'
        assert _first_json_object(raw) == {"valence": -0.5}

    def test_a_brace_inside_a_string_does_not_end_the_object(self):
        raw = '{"label": "a } brace", "valence": 1}'
        assert _first_json_object(raw)["label"] == "a } brace"

    def test_an_escaped_quote_does_not_end_the_string(self):
        raw = r'{"label": "she said \"fine\"", "valence": 0}'
        assert _first_json_object(raw)["label"] == 'she said "fine"'

    def test_no_json_at_all_returns_none_rather_than_raising(self):
        assert _first_json_object("just talking here") is None
        assert _first_json_array("nothing to see") is None

    def test_an_array_is_found_in_prose(self):
        assert _first_json_array('Here: [{"text": "has a cat"}] done') == [
            {"text": "has a cat"}
        ]


# ----------------------------------------------------------------- end to end


class TestATurn:
    def test_a_turn_emits_the_events_the_interface_depends_on(self, her: Companion):
        events = list(her.respond("I am so stressed, deadline tomorrow"))
        kinds = [event["type"] for event in events]
        assert kinds[0] == "pose"          # thinking, before anything else
        assert "affect" in kinds
        assert "chunk" in kinds
        assert kinds[-1] == "pose"        # back to idle at the end
        done = next(e for e in events if e["type"] == "done")
        assert done["posture"] == "ground"

    def test_the_exchange_is_written_to_memory(self, her: Companion):
        list(her.respond("hello there"))
        roles = [turn.role for turn in her.memory.recent_turns()]
        assert roles == ["user", "soraya"]

    def test_voice_off_means_nothing_is_spoken(self, her: Companion):
        done = next(e for e in her.respond("hello") if e["type"] == "done")
        assert done["spoke"] is False

    def test_quiet_hours_silence_her_even_with_voice_on(self, her: Companion,
                                                        monkeypatch):
        her.settings.voice.enabled = True
        monkeypatch.setattr(
            time, "localtime",
            lambda *a: time.struct_time((2026, 9, 3, 23, 30, 0, 3, 246, 0)),
        )
        # Resolved per call, so the toggle takes effect without a restart —
        # and so does the clock.
        assert her.speaker is her._silent

    def test_an_empty_message_is_not_a_turn(self, her: Companion):
        assert list(her.respond("   ")) == []

    def test_she_can_open_a_conversation_with_a_valid_history(self, her: Companion):
        approach = pulse.Approach(True, "test", situation="You wandered over.")
        events = list(her.approach(approach))
        assert events[0]["type"] == "approach"
        assert any(event["type"] == "chunk" for event in events)
        # The floor rule needs this recorded or she would approach again at once.
        assert her.last_approach_at is not None

    def test_a_dead_brain_is_reported_rather_than_hanging(self, her: Companion):
        class Broken:
            name = "broken"

            def speak(self, *a, **k):
                raise __import__("soraya.brain", fromlist=["BrainUnavailable"]) \
                    .BrainUnavailable("no key")
                yield  # pragma: no cover

            def judge(self, *a, **k):
                raise __import__("soraya.brain", fromlist=["BrainUnavailable"]) \
                    .BrainUnavailable("no key")

        her.brain = Broken()
        events = list(her.respond("hello"))
        assert any(event["type"] == "error" for event in events)
        # And she goes back to idle rather than staying stuck on `thinking`.
        assert events[-1] == {"type": "pose", "clip": "idle"}

    def test_a_safety_signal_reaches_the_prompt_intact(self, her: Companion):
        events = list(her.respond("I want to kill myself"))
        affect = next(e for e in events if e["type"] == "affect")
        assert affect["posture"] == "hold"

    def test_missing_settings_start_her_anyway(self, home: Path, monkeypatch):
        monkeypatch.setenv("SORAYA_BRAIN", "echo")
        assert Companion(Settings.load(home / "nothing.json"), home)


class TestBrainFallback:
    def test_a_missing_key_falls_back_to_echo_with_a_warning(self, monkeypatch):
        from soraya.brain.registry import build_brain_or_echo
        from soraya.config import BrainSettings

        monkeypatch.delenv("SORAYA_BRAIN", raising=False)
        brain, warning = build_brain_or_echo(BrainSettings(provider="nonsense"))
        # She must always start. A configuration problem is something to tell
        # someone about in the interface, not a reason to refuse to open.
        assert brain.name == "echo"
        assert warning and "nonsense" in warning

    def test_the_env_var_overrides_the_settings_file(self, monkeypatch):
        from soraya.brain.registry import build_brain
        from soraya.config import BrainSettings

        monkeypatch.setenv("SORAYA_BRAIN", "echo")
        assert build_brain(BrainSettings(provider="claude")).name == "echo"

    def test_research_refuses_clearly_when_it_cannot_search(self):
        from soraya.agent.research import research

        result = research(EchoBrain(), "what happened today")
        assert not result.ok
        assert "cannot search" in result.error

    def test_the_search_tool_matches_the_model_generation(self):
        from soraya.agent.research import search_tool_for

        # Naming the wrong dated variant for the model is a 400.
        assert search_tool_for("claude-opus-5")["type"] == "web_search_20260209"
        assert search_tool_for("claude-3-5-sonnet-latest")["type"] == (
            "web_search_20250305"
        )
