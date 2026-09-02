# Manual generation workflow and extension guide

This document describes the product contract behind the browser UI. It is
intended both for users and for developers who may later automate image
generation with an API.

## Why generation is manual

Consumer ChatGPT Plus and Gemini subscriptions provide useful image generation
in their web interfaces but do not provide equivalent prepaid API usage. The
studio therefore separates generation from deterministic pack processing:

```text
prompt preparation → manual image generation → one-folder import
                   → background cleanup → slicing → QA → review → ZIP
```

This keeps the current workflow free while leaving prompt assembly and image
processing reusable by a future provider adapter.

## Prompt sequence

Prompt 1 creates the definitive `reference.png`. It tells the image model to
extract the subject from an attached real photograph and ignore the photograph's
background. Human and pet reference prompts use different descriptive fields.

Every later prompt is self-contained and requires `reference.png` to be attached.
Human animation poses are assembled from `reference/PROMPTS.md`. Pet poses are
species-neutral adaptations defined in `character_generator/prompts.py`; they
avoid human-only anatomy and replace gestures where necessary:

- paw/wing greeting instead of a human hand wave;
- a water bowl instead of a glass;
- a quiet settled focus pose instead of reading in a chair;
- natural walking, stretching, sitting, sleeping, and yawning anatomy.

Each animation prompt requests exactly one landscape contact sheet with frames
in a single horizontal row. Four-frame clips use four equal-width regions and
two-frame clips use two. A fixed model output such as 16:9 is accepted. The
prompt does not depend on the provider returning a literal 256×64 or 128×64
file because image UIs frequently ignore exact dimensions.

## Required names

The importer uses filename stems, case-insensitively. Exact names are preferred:

| Input | Final pack folder and prefix | Frames |
|---|---|---:|
| `idle.png` | `Idle/idle_NN.png` | 2–4 |
| `walk.png` | `Walking/walk_NN.png` | exactly 4 |
| `wave.png` | `Waving/wave_NN.png` | 3–4 |
| `drink.png` | `WaterReminder/drink_NN.png` | 3–4 |
| `eyebreak.png` | `EyeBreak/eyebreak_NN.png` | 2–4 |
| `sleep.png` | `Sleep/sleep_NN.png` | 2–4 |
| `happy.png` | `HappyMood/happy_NN.png` | exactly 2 |
| `focus.png` | `Focus/focus_NN.png` | exactly 2 |
| `stretch.png` | `Stretch/stretch_NN.png` | exactly 4 |
| `sitting.png` | `Sitting/sitting_NN.png` | exactly 2 |
| `concerned.png` | `Concerned/concerned_NN.png` | 3–4 |
| `cheer.png` | `Cheer/cheer_NN.png` | exactly 4 |
| `peek.png` | `Peek/peek_NN.png` | exactly 2 |
| `yawn.png` | `Yawn/yawn_NN.png` | exactly 4 |

`reference.png` and `idle.png` are the minimum required inputs for a build.
Other missing or excluded clips fall back according to AiTwin's normal rules.

## Background handling

The importer first applies EXIF orientation and converts the image to RGBA.

If meaningful alpha already exists, it is preserved. If the image is opaque,
the processor quantizes colours sampled from the outer border, identifies up to
six dominant background colours, and clears only matching regions connected to
the border. This protects enclosed highlights and clothing that happen to share
a colour with the background. The approach handles typical white, flat-colour,
and many drawn checkerboard backgrounds.

It intentionally refuses aggressive removal when the border is complex or when
only a tiny region appears removable. The UI displays an amber QA warning in
that case. Complex scenery and gradients should be removed in an image editor
and then re-imported.

## Slicing and normalization

The primary slicer finds horizontal runs of non-transparent artwork. It retains
the relative thresholds and decoration safeguards from the supplied importer.
If the detected run count differs from the prompt's declared count, the manual
workflow splits the sheet into equal-width horizontal regions and flags that
fallback for visual review.

Raw slices are saved separately. Preview and package normalization always start
from those original slices, never from previously resized frames. All frames in
a clip share one scale. Normal clips are aligned by their lowest opaque pixel;
`peek` stays attached to the left edge. All accepted clips share one canvas,
baseline, character height, and manifest.

## Error handling

- A folder without `reference.png` is rejected without destroying prior work.
- Unsupported files are ignored and listed.
- Unmatched filenames are listed.
- Invalid or oversized images fail only their matching clip.
- Missing clips remain visible as missing and do not spin or retry.
- `idle` must be ready before Build is enabled.
- A failed optional clip never blocks packaging.
- Re-importing a corrected complete folder replaces processed previews while
  keeping the same session and pack configuration.
- Uploaded originals, cleaned sheets, raw slices, normalized previews, build
  reports, and ZIPs remain inside `.work/sessions/<session-id>/`.

## Adding an API later

A future provider should consume the exact output of
`character_generator.prompts.prompt_payload()`. It should save the base result
as `reference.png` and each clip result as `<clip>.png`, then feed those images
through `ManualWorkflow.import_folder()` or an equivalent internal adapter.

Do not bypass background cleanup, expected-count slicing, normalization, QA, or
human review. Provider retries must be bounded, quota errors must become a
stopped state, and generated results should be cached by the prompt plus
reference-image hash. Credentials must stay in environment variables and never
be accepted by the browser form.
