Soraya's character frames
=========================

These are the Nish artwork, imported from AiTwin/Resources/Characters/Nish so
this folder is self-contained -- Soraya/ can be moved or shipped on its own
without the Swift app's Resources folder next to it.

To re-import after changing the art over there:

    python3 scripts/import_pack.py --from Nish --to Soraya --replace

Four clips are deliberately absent: Talking, Listening, Thinking and Greeting.
The source pack predates them, and rather than fill the folders with copies of
other clips under a second name, presence/sprite.py substitutes the nearest
pose -- greeting plays Waving, thinking plays Focus. The interface says which
substitutions are in effect.

Drawing those four is the only thing that would improve this pack. Two
mouth-open frames for Talking and a head-tilt for Listening would cover the two
that currently fall back to plain Idle.

The one rule that matters if you draw anything: keep the character's FEET at
the same height in every frame of every clip. If the feet move between clips
she appears to hop when the clip changes, and no amount of code fixes that
afterwards. This pack's canvas is 466x744 with the feet at y=728.

The old stick-figure placeholders are not gone, just not here:

    python3 scripts/make_placeholders.py     # writes a "Placeholder" pack
