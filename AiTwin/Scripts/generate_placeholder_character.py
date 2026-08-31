#!/usr/bin/env python3
"""
Generates the bundled "Default" character pack.

This exists so that a fresh clone runs and shows something on screen before you
have generated any art of your own. It is deliberately plain -- the real
character is meant to come from Docs/PROMPTS.md and go in a pack of its own.

Everything is drawn on a 64x64 transparent canvas at 1 logical pixel per pixel,
which is the source resolution Docs/ASSETS.md recommends.

    python3 Scripts/generate_placeholder_character.py

Requires Pillow (pip3 install pillow). Only needed to regenerate the art; the
app itself has no Python dependency.
"""

import os
from PIL import Image, ImageDraw

SIZE = 64
OUT = os.path.join(os.path.dirname(__file__), "..", "Resources", "Characters", "Default")

SKIN    = (242, 201, 160, 255)
SKIN_SH = (214, 172, 132, 255)
HAIR    = (74, 59, 50, 255)
SHIRT   = (78, 127, 193, 255)
SHIRT_SH= (58, 100, 158, 255)
PANTS   = (53, 65, 92, 255)
SHOES   = (42, 42, 51, 255)
LINE    = (35, 32, 43, 255)
WHITE   = (255, 255, 255, 255)
GLASS   = (159, 216, 240, 220)
WATER   = (80, 168, 214, 255)
FRAME   = (60, 60, 70, 255)


def box(d, x0, y0, x1, y1, colour):
    """Inclusive rectangle, so coordinates read like pixel counts."""
    d.rectangle([x0, y0, x1, y1], fill=colour)


def draw_character(bob=0, leg=0, left_arm="down", right_arm="down",
                   eyes="open", glasses=False, glass=None, zzz=False):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    y = bob  # whole-body vertical offset for the idle breathing bob

    # Legs -------------------------------------------------------------
    # leg: 0 = together, 1 = left forward, -1 = right forward
    left_x, right_x = 27, 33
    if leg == 1:
        left_x, right_x = 25, 35
    elif leg == -1:
        left_x, right_x = 29, 31
    box(d, left_x, 46 + y, left_x + 3, 56 + y, PANTS)
    box(d, right_x, 46 + y, right_x + 3, 56 + y, PANTS)
    box(d, left_x - 1, 56 + y, left_x + 3, 58 + y, SHOES)
    box(d, right_x - 1, 56 + y, right_x + 3, 58 + y, SHOES)

    # Torso ------------------------------------------------------------
    box(d, 26, 31 + y, 38, 47 + y, SHIRT)
    box(d, 26, 43 + y, 38, 47 + y, SHIRT_SH)
    box(d, 25, 31 + y, 25, 47 + y, LINE)
    box(d, 39, 31 + y, 39, 47 + y, LINE)

    # Arms -------------------------------------------------------------
    def arm(x_outer, pose, mirrored):
        if pose == "up":
            box(d, x_outer, 24 + y, x_outer + 3, 34 + y, SHIRT)
            box(d, x_outer, 21 + y, x_outer + 3, 24 + y, SKIN)
        elif pose == "mid":
            box(d, x_outer, 31 + y, x_outer + 3, 38 + y, SHIRT)
            box(d, x_outer + (2 if mirrored else -2), 36 + y,
                x_outer + (5 if mirrored else 1), 40 + y, SKIN)
        else:
            box(d, x_outer, 32 + y, x_outer + 3, 42 + y, SHIRT)
            box(d, x_outer, 42 + y, x_outer + 3, 45 + y, SKIN)

    arm(21, left_arm, False)
    arm(40, right_arm, True)

    # Head -------------------------------------------------------------
    box(d, 25, 15 + y, 39, 31 + y, SKIN)
    box(d, 25, 27 + y, 39, 31 + y, SKIN_SH)
    box(d, 24, 16 + y, 24, 30 + y, LINE)
    box(d, 40, 16 + y, 40, 30 + y, LINE)
    box(d, 25, 14 + y, 39, 14 + y, LINE)

    # Hair
    box(d, 24, 12 + y, 40, 19 + y, HAIR)
    box(d, 23, 15 + y, 23, 25 + y, HAIR)
    box(d, 41, 15 + y, 41, 25 + y, HAIR)

    # Face
    if eyes == "open":
        box(d, 28, 22 + y, 30, 24 + y, WHITE)
        box(d, 34, 22 + y, 36, 24 + y, WHITE)
        box(d, 29, 23 + y, 29, 24 + y, LINE)
        box(d, 35, 23 + y, 35, 24 + y, LINE)
    else:  # closed / resting
        box(d, 28, 23 + y, 30, 23 + y, LINE)
        box(d, 34, 23 + y, 36, 23 + y, LINE)
    box(d, 30, 27 + y, 34, 27 + y, LINE)  # mouth

    if glasses:
        box(d, 27, 21 + y, 31, 25 + y, FRAME)
        box(d, 28, 22 + y, 30, 24 + y, (255, 255, 255, 90))
        box(d, 33, 21 + y, 37, 25 + y, FRAME)
        box(d, 34, 22 + y, 36, 24 + y, (255, 255, 255, 90))
        box(d, 31, 23 + y, 33, 23 + y, FRAME)

    # Held glass of water ----------------------------------------------
    if glass is not None:
        gx, gy = glass
        box(d, gx, gy + y, gx + 5, gy + 8 + y, GLASS)
        box(d, gx + 1, gy + 3 + y, gx + 4, gy + 7 + y, WATER)
        box(d, gx, gy + y, gx, gy + 8 + y, FRAME)
        box(d, gx + 5, gy + y, gx + 5, gy + 8 + y, FRAME)

    if zzz:
        box(d, 44, 12 + y, 46, 12 + y, LINE)
        box(d, 45, 13 + y, 45, 13 + y, LINE)
        box(d, 44, 14 + y, 46, 14 + y, LINE)
        box(d, 48, 7 + y, 51, 7 + y, LINE)
        box(d, 49, 8 + y, 50, 9 + y, LINE)
        box(d, 48, 10 + y, 51, 10 + y, LINE)

    return img


def write(folder, prefix, frames):
    directory = os.path.join(OUT, folder)
    os.makedirs(directory, exist_ok=True)
    for index, image in enumerate(frames, start=1):
        image.save(os.path.join(directory, f"{prefix}_{index:02d}.png"))
    print(f"  {folder}/{prefix}_01..{len(frames):02d}.png")


def build(glasses=False):
    suffix = "_glasses" if glasses else ""
    g = glasses
    print(f"Generating {'glasses variant' if g else 'base'} frames…")

    # Idle: a slow two-pixel breathing bob.
    write("Idle", f"idle{suffix}", [
        draw_character(bob=0, glasses=g),
        draw_character(bob=1, glasses=g),
        draw_character(bob=1, glasses=g),
        draw_character(bob=0, glasses=g),
    ])

    # Walk: a four-frame cycle, contact / passing / contact / passing.
    write("Walking", f"walk{suffix}", [
        draw_character(leg=1, left_arm="mid", right_arm="down", glasses=g),
        draw_character(leg=0, bob=1, glasses=g),
        draw_character(leg=-1, left_arm="down", right_arm="mid", glasses=g),
        draw_character(leg=0, bob=1, glasses=g),
    ])

    # Wave: one arm rises and holds.
    write("Waving", f"wave{suffix}", [
        draw_character(left_arm="mid", glasses=g),
        draw_character(right_arm="up", glasses=g),
        draw_character(right_arm="up", bob=1, glasses=g),
        draw_character(right_arm="up", glasses=g),
    ])

    # Drinking: the glass travels up to the mouth.
    write("WaterReminder", f"drink{suffix}", [
        draw_character(right_arm="mid", glass=(44, 36), glasses=g),
        draw_character(right_arm="mid", glass=(42, 30), glasses=g),
        draw_character(right_arm="up", glass=(38, 22), eyes="closed", glasses=g),
        draw_character(right_arm="mid", glass=(42, 30), glasses=g),
    ])

    # Eye break: eyes close, hands come up to rest them.
    write("EyeBreak", f"eyebreak{suffix}", [
        draw_character(eyes="closed", glasses=g),
        draw_character(eyes="closed", left_arm="up", right_arm="up", glasses=g),
        draw_character(eyes="closed", left_arm="up", right_arm="up", bob=1, glasses=g),
        draw_character(eyes="closed", glasses=g),
    ])

    # Happy: a small celebration for hitting the daily water goal.
    write("HappyMood", f"happy{suffix}", [
        draw_character(left_arm="mid", right_arm="mid", glasses=g),
        draw_character(bob=-2, left_arm="up", right_arm="up", glasses=g),
        draw_character(bob=-2, left_arm="up", right_arm="up", glasses=g),
        draw_character(left_arm="mid", right_arm="mid", glasses=g),
    ])

    # Sleep: resting, with drifting Zs.
    write("Sleep", f"sleep{suffix}", [
        draw_character(bob=1, eyes="closed", glasses=g),
        draw_character(bob=2, eyes="closed", zzz=True, glasses=g),
        draw_character(bob=2, eyes="closed", zzz=True, glasses=g),
        draw_character(bob=1, eyes="closed", glasses=g),
    ])


if __name__ == "__main__":
    build(glasses=False)
    build(glasses=True)
    print(f"\nDone. Frames written to {os.path.normpath(OUT)}")
