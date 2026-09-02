# AiTwin Character Pack Studio

Turn a real photograph of a human or pet into an installable AiTwin character
pack without paying for an image API.

The local browser app prepares complete prompts for ChatGPT or Gemini. You
generate and download the images manually, place them in one folder, and select
that folder once. The app then removes simple backgrounds, slices contact
sheets, normalizes every frame, displays animated QA previews, and builds the
final ZIP.

No API key is required. No image is sent anywhere by this application.

## Run

```bash
python3 -m pip install -r requirements.txt
python3 app.py
```

Open `http://127.0.0.1:5000` if the browser does not open automatically. The
server deliberately binds only to localhost.

## Workflow

1. Choose **Human** or **Pet**, enter a pack name, and optionally describe
   details the source photograph does not show.
2. Copy Prompt 1 into ChatGPT or Gemini and attach the real photograph.
3. Save the accepted base sprite as `reference.png`.
4. Copy each selected animation prompt. Attach `reference.png` every time.
5. Save each generated contact sheet using the filename displayed by the app.
6. Select the containing folder once.
7. Review every processed animation, exclude anything unsuitable, and build.
8. Drag the downloaded ZIP onto **AiTwin → Settings → Character**.

The complete default folder contains 15 images:

```text
reference.png
idle.png
walk.png
wave.png
drink.png
eyebreak.png
happy.png
sleep.png
focus.png
stretch.png
sitting.png
concerned.png
cheer.png
peek.png
yawn.png
```

PNG is preferred, but the importer also accepts JPEG, WebP, and TIFF. Generated
contact sheets may use a fixed landscape size such as 16:9. Exact model output
dimensions are not trusted; final frames are put on one shared AiTwin canvas.

## What processing does

- Preserves existing PNG transparency.
- Removes simple solid or checkerboard-like backgrounds only when the removable
  colour region is connected to the image border.
- Splits on transparent gutters when possible.
- Falls back to the prompt's equal-width horizontal regions when necessary.
- Uses one scale per clip and nearest-neighbour resizing.
- Bottom-aligns normal clips, preserves edge-anchored `peek`, and computes one
  canvas, baseline, and `clipTopFractions` manifest for the complete pack.
- Runs frame-count, scale, transparency, palette, aspect, non-empty, and foot
  registration checks without automatically discarding the user's artwork.

Automatic background removal is intentionally conservative. A complex scene,
gradient, or background sharing colours with the character may require manual
cleanup. The review screen shows both the uploaded original and cleaned sheet so
the user can decide.

## Offline CLI

The original offline paths remain available for scripting:

```bash
# Print the 14 assembled human animation prompts.
python3 generate_character.py reference.png --name Nish --dry-run

# Build directly from an existing sheet folder without network access.
python3 generate_character.py reference.png --name Nish --from-sheets sheets/
```

The legacy API backend classes remain isolated extension points for developers;
they are not used by the browser workflow. Gemini SDK support is optional:

```bash
python3 -m pip install -r requirements-api.txt
```

## Tests

```bash
pytest
```

The suite uses synthetic images and makes no network calls.

See [MANUAL_WORKFLOW.md](MANUAL_WORKFLOW.md) for prompt design, import rules,
error handling, and future API automation guidance.
