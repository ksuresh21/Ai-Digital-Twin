#!/usr/bin/env python3
"""Builds the app icon and the menu bar icon from Resources/AiTwin_logo.png.

Run: python3 Scripts/make_icons.py

Both are derived from the one logo file, so there is a single source of truth
for the brand. What differs is how much of it each can carry.

The app icon takes the whole logo, mark and wordmark, on the logo's own
near-white plate. No rounded-rectangle mask is applied -- the logo keeps the
square it was designed with.

The menu bar icon can only take the mark. It is a *template* image: macOS
discards the colour and uses the alpha channel alone, so it can tint the icon
for light mode, dark mode and highlight. Two consequences follow.

  1. The background must be transparent. A template built from the logo as
     supplied -- opaque to its edges -- is a solid dark blob.
  2. It has to survive 14 points of height. The wordmark would be about three
     pixels tall, so it is dropped, and the thin circuit traces either side of
     the rings turn to speckle, so they are trimmed. What is left is the dense
     core: the two interlocking rings, their eye dots and the speech-bubble
     tails.

The alpha is then multiplied. Downscaling line art by twenty-five times leaves
strokes at perhaps a third opacity, which reads as grey mush; the boost pushes
them back to solid while leaving genuinely empty areas empty.
"""
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
LOGO = ROOT / "Resources" / "AiTwin_logo.png"
MENU_BAR = ROOT / "Resources" / "MenuBar"
ICNS = ROOT / "Resources" / "AppIcon.icns"

# How tall the mark is as a fraction of the logo, i.e. where the wordmark starts.
MARK_FRACTION = 0.58
# Columns carrying less than this share of the densest column are trace, not ring.
CORE_DENSITY = 0.30
# Recovers stroke opacity lost to downscaling.
ALPHA_GAIN = 3.0
MENU_BAR_HEIGHT = 14
# Breathing room around the app icon, as a fraction of the canvas.
ICON_PADDING = 0.06


def ink_mask(image: Image.Image) -> Image.Image:
    """Alpha from how much ink a pixel carries, keying out the white plate.

    Darkness alone would drop the bright cyan and violet of the mark, and
    saturation alone would drop the near-black wordmark, so it takes whichever
    is stronger.
    """
    array = np.array(image.convert("RGBA")).astype(int)[:, :, :3]
    darkness = 255 - array.max(axis=2)
    saturation = array.max(axis=2) - array.min(axis=2)
    return Image.fromarray(
        np.clip(np.maximum(darkness, saturation), 0, 255).astype(np.uint8), "L"
    )


def trimmed(mask: Image.Image, threshold: int = 20) -> tuple[Image.Image, tuple]:
    box = mask.point(lambda p: 255 if p > threshold else 0).getbbox()
    return mask.crop(box), box


def build_menu_bar(logo: Image.Image) -> None:
    mask = ink_mask(logo)
    mark, _ = trimmed(mask.crop((0, 0, logo.width, int(logo.height * MARK_FRACTION))))

    # Drop the circuit traces: thin, so their columns carry far less ink than
    # the rings. Measured rather than hand-cropped, so a redrawn logo still works.
    columns = np.array(mark).sum(axis=0)
    dense = np.where(columns > columns.max() * CORE_DENSITY)[0]
    core, _ = trimmed(mark.crop((int(dense[0]), 0, int(dense[-1]) + 1, mark.height)))

    MENU_BAR.mkdir(parents=True, exist_ok=True)
    for scale, suffix in ((1, ""), (2, "@2x"), (3, "@3x")):
        height = MENU_BAR_HEIGHT * scale
        width = round(core.width * height / core.height)
        alpha = core.resize((width, height), Image.LANCZOS)
        boosted = np.clip(np.array(alpha).astype(float) * ALPHA_GAIN, 0, 255).astype(np.uint8)
        white = Image.new("L", (width, height), 255)
        icon = Image.merge("RGBA", (white, white, white, Image.fromarray(boosted, "L")))
        path = MENU_BAR / f"MenuBarIcon{suffix}.png"
        icon.save(path)
        print(f"  {path.name:22} {width}x{height}")


def opaque_alpha(mask: Image.Image, low: int = 8, high: int = 40) -> Image.Image:
    """Turns the ink mask into a normal alpha channel.

    Using ink density directly as alpha washes the logo out: a pale cyan stroke
    carries little ink, so it would come out half transparent. This keeps
    anything above `high` fully opaque and only fades the last few levels down
    to the white plate, so a soft edge survives without bleaching the artwork.
    """
    array = np.array(mask).astype(float)
    scaled = (array - low) / float(high - low) * 255.0
    return Image.fromarray(np.clip(scaled, 0, 255).astype(np.uint8), "L")


def plate_colour(logo: Image.Image) -> tuple[int, int, int]:
    """The logo's own background colour, taken from its corners.

    Sampled rather than assumed white: the supplied file is (252, 253, 254),
    very slightly cool, and painting pure white behind it would leave a visible
    seam where the plate met the artwork.
    """
    rgb = logo.convert("RGB")
    width, height = rgb.size
    samples = [rgb.getpixel(p) for p in
               ((2, 2), (width - 3, 2), (2, height - 3), (width - 3, height - 3))]
    return tuple(sorted(channel)[len(channel) // 2] for channel in zip(*samples))


def build_app_icon(logo: Image.Image) -> None:
    """The whole logo on its own white plate, then iconutil to .icns.

    The plate is kept. A transparent icon would float without the square every
    other Dock icon has, and the logo was designed with that background.

    The artwork is still re-centred rather than used verbatim: as supplied it
    fills only the middle 65% across and 43% down, so at a 32-pixel icon the
    mark would be a handful of pixels with a wide empty border. Trimming and
    re-padding keeps the same composition but sized to be legible.
    """
    mask = ink_mask(logo)
    _, box = trimmed(mask)
    art = logo.convert("RGBA").crop(box)
    art.putalpha(opaque_alpha(mask.crop(box)))

    side = max(art.size)
    canvas_side = int(side / (1 - 2 * ICON_PADDING))
    # alpha_composite rather than paste: paste blends the *alpha* channel too,
    # which left the anti-aliased edges of the artwork slightly transparent and
    # the icon not quite opaque.
    plate = Image.new("RGBA", (canvas_side, canvas_side), plate_colour(logo) + (255,))
    layer = Image.new("RGBA", (canvas_side, canvas_side), (0, 0, 0, 0))
    layer.paste(art, ((canvas_side - art.width) // 2, (canvas_side - art.height) // 2))
    canvas = Image.alpha_composite(plate, layer)

    iconset = ROOT / "build" / "AppIcon.iconset"
    iconset.mkdir(parents=True, exist_ok=True)
    for point in (16, 32, 128, 256, 512):
        for scale, suffix in ((1, ""), (2, "@2x")):
            pixels = point * scale
            canvas.resize((pixels, pixels), Image.LANCZOS).save(
                iconset / f"icon_{point}x{point}{suffix}.png"
            )
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(ICNS)], check=True)
    print(f"  {ICNS.name:22} from a {canvas_side}px square")


def main() -> None:
    if not LOGO.exists():
        sys.exit(f"error: {LOGO.relative_to(ROOT)} not found")
    logo = Image.open(LOGO)
    print(f"source: {LOGO.name} {logo.size}")
    print("menu bar (template, mark only):")
    build_menu_bar(logo)
    print("app icon (whole logo, white plate, no rounding):")
    build_app_icon(logo)


if __name__ == "__main__":
    main()
