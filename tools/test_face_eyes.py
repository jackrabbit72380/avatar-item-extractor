#!/usr/bin/env python3
"""Pin the face fix: the painted lid is kept, the old pupil is replaced.

The faces an avatar exports carry their gaze in the paint. The Marine face this
was written against has each eye drawn as one stroke - a thin tail at the outer
corner swelling into the pupil at the inner one - so the avatar looks down his
nose in every frame Halo renders. The head's UVs then mirror one eye while the
drawn pair is itself mirrored, so the two eyes do not even match each other.

So one eye is treated as the pattern and copied:

  * the lid is kept texel for texel, exactly as painted,
  * the swelling under it is cleared and an iris drawn centred under the lid,
  * the finished eye is stamped into both drawn eyes, so the UV mirroring makes
    a matching pair.

A synthetic face is painted here, so the test runs without Blender and without
an asset on the machine:

  * a pupil drawn at one end ends up centred, with the lid rows untouched,
  * both drawn eyes end up byte-identical,
  * a face already level, or with no eyes at all, is left byte for byte alone,
  * the PNG written out reads back as the same pixels the fix produced.

    python3 tools/test_face_eyes.py
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODULES = os.environ.get("RIG_MODULES") or os.path.join(os.path.dirname(HERE), "src")
sys.path.insert(0, MODULES)

import face_eyes  # noqa: E402
import glb_model  # noqa: E402

SKIN = (215, 170, 113, 255)
INK = (24, 20, 14, 255)
WIDTH = HEIGHT = 256
LEFT_EYE = (40, 110)
RIGHT_EYE = (146, 216)
TOP = 96
BOTTOM = 130


def canvas(colour=SKIN):
    pixels = bytearray(WIDTH * HEIGHT * 4)
    for index in range(0, len(pixels), 4):
        pixels[index:index + 4] = bytes(colour)
    return pixels


def paint(pixels, x, y, colour=INK):
    at = (y * WIDTH + x) * 4
    pixels[at:at + 4] = bytes(colour)


def paint_eye(pixels, left, right, swell):
    """One eye: a swept lid across the span, swelling into a pupil at `swell`.

    `swell` is 0.0 for a pupil at the left corner and 1.0 for the right, which
    is how these faces are drawn - the pupil sits at one end of the stroke, not
    under the middle of it.
    """
    span = right - left
    for x in range(left, right + 1):
        t = (x - left) / float(span)
        arc = TOP + int(round(4 * (1 - (2 * t - 1) ** 2)))
        paint(pixels, x, arc)
        paint(pixels, x, arc + 1)
        depth = int(round(9 * max(0.0, 1 - abs(t - swell) * 4)))
        for extra in range(1, depth + 1):
            paint(pixels, x, arc + 1 + extra)


def rectangle(pixels, left, right):
    return [bytes(pixels[(y * WIDTH + x) * 4:(y * WIDTH + x) * 4 + 4])
            for y in range(TOP, BOTTOM + 1) for x in range(left, right + 1)]


def lid_rows(pixels, left, right):
    rows = {}
    for x in range(left, right + 1):
        for y in range(TOP - 8, BOTTOM + 8):
            at = (y * WIDTH + x) * 4
            if 0.299 * pixels[at] + 0.587 * pixels[at + 1] + 0.114 * pixels[at + 2] < 140:
                rows[x] = y
                break
    return rows


def ink_profile(pixels, left, right):
    weight = 0
    moment = 0
    for x in range(left, right + 1):
        for y in range(TOP - 8, BOTTOM + 8):
            at = (y * WIDTH + x) * 4
            if 0.299 * pixels[at] + 0.587 * pixels[at + 1] + 0.114 * pixels[at + 2] < 140:
                weight += 1
                moment += x
    if not weight:
        return None
    return (moment / float(weight) - left) / float(right - left)


def main():
    failures = []
    checks = 0

    def report(name, ok, detail=""):
        nonlocal checks
        checks += 1
        print("%s %s%s" % ("PASS" if ok else "FAIL", name, detail))
        if not ok:
            failures.append(name)

    # The case that started this: both pupils drawn at one end of their stroke.
    face = canvas()
    paint_eye(face, LEFT_EYE[0], LEFT_EYE[1], 0.9)
    paint_eye(face, RIGHT_EYE[0], RIGHT_EYE[1], 0.9)
    before = ink_profile(face, LEFT_EYE[0], LEFT_EYE[1])
    fixed, notes = face_eyes.centre_pupils(face, WIDTH, HEIGHT, force=True)
    report("drawn at one end: the swelling was off centre",
           before is not None and abs(before - 0.5) > 0.1, " (%.2f)" % (before or 0))
    # A pupil is added in the middle, and nothing painted is removed, so the
    # drawing keeps the weight and the edges it was painted with.
    def ink_texels(pixels):
        return {(x, y) for x in range(LEFT_EYE[0], LEFT_EYE[1] + 1)
                for y in range(TOP - 8, BOTTOM + 8)
                if 0.299 * pixels[(y * WIDTH + x) * 4]
                + 0.587 * pixels[(y * WIDTH + x) * 4 + 1]
                + 0.114 * pixels[(y * WIDTH + x) * 4 + 2] < 140}

    added = ink_texels(fixed) - ink_texels(face)
    lost = ink_texels(face) - ink_texels(fixed)
    middle = (LEFT_EYE[0] + LEFT_EYE[1]) / 2.0
    where = (sum(x for x, _ in added) / float(len(added)) - LEFT_EYE[0]) \
        / (LEFT_EYE[1] - LEFT_EYE[0]) if added else None
    report("a pupil is added in the middle of the eye",
           where is not None and abs(where - 0.5) <= 0.12,
           " (%s of the eye's width, %d texels)"
           % ("%.2f" % where if where is not None else "none", len(added)))
    report("not one painted texel is removed", not lost,
           " (%d of %d lost)" % (len(lost), len(ink_texels(face))))
    report("the added pupil sits on the eye's middle",
           bool(added) and all(abs(x - middle) <= 0.35 * (LEFT_EYE[1] - LEFT_EYE[0])
                               for x, _ in added))
    report("both eyes reported", len(notes) == 2, " (%d notes)" % len(notes))

    # The lid is not redrawn: its rows are the ones that were painted.
    painted_lid = lid_rows(face, LEFT_EYE[0], LEFT_EYE[1])
    fixed_lid = lid_rows(fixed, LEFT_EYE[0], LEFT_EYE[1])
    kept = sum(1 for x in painted_lid if painted_lid[x] == fixed_lid.get(x))
    report("the lid is kept exactly as painted", kept == len(painted_lid),
           " (%d of %d columns on their own row)" % (kept, len(painted_lid)))

    # Both drawn eyes end up identical, which is what makes the mirrored UVs
    # produce a matching pair on the head.
    report("both drawn eyes are identical",
           rectangle(fixed, LEFT_EYE[0], LEFT_EYE[1])
           == rectangle(fixed, RIGHT_EYE[0], RIGHT_EYE[1]))

    # Already level: nothing may change, not one byte.
    level = canvas()
    paint_eye(level, LEFT_EYE[0], LEFT_EYE[1], 0.5)
    paint_eye(level, RIGHT_EYE[0], RIGHT_EYE[1], 0.5)
    untouched, level_notes = face_eyes.centre_pupils(level, WIDTH, HEIGHT)
    report("already level: left alone", bytes(untouched) == bytes(level))
    report("already level: said so", all("untouched" in note or "forward" in note
                                         for note in level_notes),
           " (%s)" % "; ".join(level_notes[:1]))

    # No eyes at all: no pair found, no edits made.
    blank = canvas()
    bare, bare_notes = face_eyes.centre_pupils(blank, WIDTH, HEIGHT, force=True)
    report("no eyes: left alone", bytes(bare) == bytes(blank))
    report("no eyes: said so", any("untouched" in note for note in bare_notes),
           " (%s)" % "; ".join(bare_notes[:1]))

    # The writing: a PNG that reads back as exactly the pixels handed to it.
    written = face_eyes.png_bytes(fixed, WIDTH, HEIGHT)
    again, got_width, got_height = glb_model.decode_png(written)
    report("png: same size", (got_width, got_height) == (WIDTH, HEIGHT),
           " (%dx%d)" % (got_width, got_height))
    report("png: same pixels", bytes(again) == bytes(fixed))

    print()
    if failures:
        print("FAILED: %d of %d checks failed: %s" % (len(failures), checks,
                                                      ", ".join(failures)))
        return 1
    print("PASSED: %d of %d checks" % (checks, checks))
    return 0


if __name__ == "__main__":
    sys.exit(main())
