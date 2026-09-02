from dataclasses import dataclass


@dataclass(frozen=True)
class ClipSpec:
    name: str
    folder: str
    prefix: str
    ask: int
    minimum: int
    maximum: int
    loops: bool
    prompt_number: int
    height_ratio: float = 1.0
    alignment: str = "bottom"


CLIPS = (
    ClipSpec("idle", "Idle", "idle", 4, 2, 4, True, 2),
    ClipSpec("walk", "Walking", "walk", 4, 4, 4, True, 3),
    ClipSpec("wave", "Waving", "wave", 4, 3, 4, False, 6),
    ClipSpec("drink", "WaterReminder", "drink", 4, 3, 4, True, 9),
    ClipSpec("eyebreak", "EyeBreak", "eyebreak", 4, 2, 4, True, 10),
    ClipSpec("sleep", "Sleep", "sleep", 4, 2, 4, True, 12),
    ClipSpec("happy", "HappyMood", "happy", 2, 2, 2, False, 11),
    ClipSpec("focus", "Focus", "focus", 2, 2, 2, True, 13, 0.86),
    ClipSpec("stretch", "Stretch", "stretch", 4, 4, 4, True, 14, 1.16),
    ClipSpec("sitting", "Sitting", "sitting", 2, 2, 2, True, 15, 0.86),
    ClipSpec("concerned", "Concerned", "concerned", 4, 3, 4, True, 16, 1.14),
    ClipSpec("cheer", "Cheer", "cheer", 4, 4, 4, False, 17),
    ClipSpec("peek", "Peek", "peek", 2, 2, 2, True, 18, 0.62, "top-left"),
    ClipSpec("yawn", "Yawn", "yawn", 4, 4, 4, False, 19, 1.16),
)

CLIP_BY_NAME = {clip.name: clip for clip in CLIPS}

FALLBACK_MESSAGES = {
    "walk": "movement will use idle",
    "wave": "greetings will use idle",
    "drink": "water reminders will use idle",
    "eyebreak": "eye-break reminders will use idle",
    "sleep": "sleep mode will use idle",
    "happy": "happy moments will use idle",
    "focus": "focus sessions will use idle",
    "stretch": "stretch reminders will use idle",
    "sitting": "sitting moments will use idle",
    "concerned": "concerned moments will use idle",
    "cheer": "streak celebrations will use happy if present, otherwise idle",
    "peek": "peek moments will use idle",
    "yawn": "wind-down moments will use idle",
}
