"""Puts a phone around a screenshot, so the README shows a device and not a
raw framebuffer dump.

AGENTS.md has asked for "`scripts/frame.py`-style device framing" since before
this file existed, which is how the last set of screenshots ended up framed by
hand and the set after that ended up not framed at all. This is that script.

The frame is deliberately plain: a rounded slab in near-black, a even bezel,
and the screen's own corners rounded to match. No glare, no shadow, no
perspective — the point is the app, and a photorealistic phone competes with
it. The area outside the body is transparent, so the same PNG sits correctly on
GitHub's light and dark themes.

    python scripts/frame.py shot.png framed.png
    python scripts/frame.py --in-place assets/screenshots/home.png

Requires Pillow, which is not a project dependency: this runs on a maintainer's
machine when screenshots are retaken, never in the app or in CI.
"""

import sys

from PIL import Image, ImageDraw

# Proportions, not pixels, so a screenshot from any phone frames the same.
BEZEL = 0.031  # of the screenshot's width, on every side
BODY_RADIUS = 0.098  # of the framed width
SCREEN_RADIUS = 0.070  # of the screenshot's width

BODY = (10, 10, 11, 255)
# A hairline lighter than the body, which is what keeps the slab from
# disappearing into a dark README rather than reading as an object on it.
EDGE = (38, 38, 41, 255)
EDGE_WIDTH = 2

# Drawn large and resampled down: Pillow's rounded rectangles are not
# antialiased, and a hard-edged corner is the one thing that makes a frame look
# pasted on rather than photographed.
SUPERSAMPLE = 4


def without_system_bar(shot: Image.Image) -> Image.Image:
    """Trims Android's back/home/recents bar off the bottom.

    It belongs to the phone, not to the app, and a frame that includes it is
    showing the reader somebody else's furniture. The published screenshots
    have always been cropped this way; it was done by hand before.

    Found rather than assumed, because the bar's height depends on the device
    and on whether gesture navigation is on: the bar is a solid band in a grey
    of its own, so this reads the colour in the very bottom corner and walks
    up while it holds. If the app itself happens to end in that exact colour
    the walk would run away, so it is capped at a fifth of the screen.
    """
    rgb = shot.convert("RGB")
    w, h = rgb.size
    bar = rgb.getpixel((4, h - 1))
    limit = h // 5
    y = h - 1
    while y > h - limit:
        pixel = rgb.getpixel((4, y))
        if max(abs(a - b) for a, b in zip(pixel, bar)) > 6:
            break
        y -= 1
    # Nothing found: the shot was already cropped, or the bar is translucent
    # over the app, in which case cutting a guess would be worse than leaving
    # it alone.
    return shot if y <= h - limit else shot.crop((0, 0, w, y + 1))


def frame(shot: Image.Image) -> Image.Image:
    shot = without_system_bar(shot.convert("RGBA"))
    w, h = shot.size
    bezel = round(w * BEZEL)
    out_w, out_h = w + bezel * 2, h + bezel * 2
    s = SUPERSAMPLE

    canvas = Image.new("RGBA", (out_w * s, out_h * s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(
        [0, 0, out_w * s - 1, out_h * s - 1],
        radius=round(out_w * BODY_RADIUS) * s,
        fill=BODY,
        outline=EDGE,
        width=EDGE_WIDTH * s,
    )

    # The screen's own rounded corners, cut as a mask so the screenshot's
    # square corners do not poke into the bezel.
    mask = Image.new("L", (w * s, h * s), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, w * s - 1, h * s - 1],
        radius=round(w * SCREEN_RADIUS) * s,
        fill=255,
    )
    screen = shot.resize((w * s, h * s), Image.LANCZOS)
    canvas.paste(screen, (bezel * s, bezel * s), mask)

    return canvas.resize((out_w, out_h), Image.LANCZOS)


def main(argv: list[str]) -> int:
    args = [a for a in argv[1:] if not a.startswith("--")]
    in_place = "--in-place" in argv
    if not args or (not in_place and len(args) != 2):
        print(__doc__)
        return 2

    for path in args if in_place else args[:1]:
        framed = frame(Image.open(path))
        target = path if in_place else args[1]
        framed.save(target)
        print(f"framed {path} -> {target} ({framed.width}x{framed.height})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
