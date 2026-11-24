#!/usr/bin/env python3
"""Pin the face fix: a pupil drawn at one end of an eye is put back in the middle.

The faces an avatar exports carry their gaze in the paint. The Marine face this
was written against has each eye drawn as one stroke - a thin tail at the outer
corner swelling into the pupil at the inner one - so the avatar looks down his
nose in every frame Halo renders. Nothing in the mesh or the UVs causes that and
nothing in them can fix it, so the ink is redrawn: the lid line stays exactly as
it was drawn and the swelling moves to the middle of the eye.

A synthetic face is painted here, so the test runs without Blender and without
an asset on the machine:

  * an eye drawn at either end is redrawn level, and the lid line survives,
  * a face whose eyes are already level is left byte for byte alone,
  * a face with no pair of eyes is left alone rather than half-edited,
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


def canvas(width=256, height=256, colour=SKIN):
    pixels = bytearray(width * height * 4)
    for index in range(0, len(pixels), 4):
        pixels[index:index + 4] = bytes(colour)
    return pixels


def paint(pixels, width, x, y, colour=INK):
    at = (y * width + x) * 4
    pixels[at:at + 4] = bytes(colour)


def paint_eye(pixels, width, left, right, top, swell):
    """One eye: a thin lid arc across the span, swelling into a pupil at `swell`.

    `swell` is 0.0 for a pupil at the left corner and 1.0 for the right, which
    is how these faces are drawn - one eye per socket, both pupils on the same
    side of their own eye.
    """
    span = right - left
    for x in range(left, right + 1):
        t = (x - left) / float(span)
        arc = top + int(round(4 * (1 - (2 * t - 1) ** 2)))
        paint(pixels, width, x, arc)
        paint(pixels, width, x, arc + 1)
        depth = int(round(9 * max(0.0, 1 - abs(t - swell) * 4)))
        for extra in range(1, depth + 1):
            paint(pixels, width, x, arc + 1 + extra)


def ink_profile(pixels, width, left, right, top, bottom):
    """Where the eye's swelling sits: the ink-weighted middle column, 0 to 1."""
    weight = 0
    moment = 0
    for x in range(left, right + 1):
        for y in range(top, bottom + 1):
            at = (y * width + x) * 4
            if 0.299 * pixels[at] + 0.587 * pixels[at + 1] + 0.114 * pixels[at + 2] < 140:
                weight += 1
                moment += x
    if not weight:
        return None
    return (moment / float(weight) - left) / float(right - left)


def main():
    width = height = 256
    failures = []
    checks = 0

    def report(name, ok, detail=""):
        nonlocal checks
        checks += 1
        print("%s %s%s" % ("PASS" if ok else "FAIL", name, detail))
        if not ok:
            failures.append(name)

    # A face with both pupils drawn at one end: the case that started this.
    face = canvas(width, height)
    paint_eye(face, width, 40, 110, 96, 0.9)
    paint_eye(face, width, 146, 216, 96, 0.9)
    before = ink_profile(face, width, 40, 110, 96, 130)
    fixed, notes = face_eyes.centre_pupils(face, width, height, force=True)
    after = ink_profile(fixed, width, 40, 110, 96, 130)
    report("drawn at one end: swelling was off centre", before is not None
           and abs(before - 0.5) > 0.1, " (%.2f)" % (before or 0))
    report("drawn at one end: redrawn in the middle", after is not None
           and abs(after - 0.5) <= 0.12, " (%.2f)" % (after or 0))
    report("both eyes reported", len(notes) == 2, " (%d notes)" % len(notes))

    # The lid: folded about each eye's own middle, so the two eyes are mirror
    # images of one another - and no column is left blank, which is how a lid
    # drawn offset by offset on a half-pixel centre comes out as a comb.
    def lid_rows(pixels, left, right):
        rows = {}
        for x in range(left, right + 1):
            for y in range(88, 140):
                at = (y * width + x) * 4
                if 0.299 * pixels[at] + 0.587 * pixels[at + 1] + 0.114 * pixels[at + 2] < 140:
                    rows[x] = y
                    break
        return rows

    left_eye = lid_rows(fixed, 40, 110)
    right_eye = lid_rows(fixed, 146, 216)
    report("every column still has its lid",
           len(left_eye) == 71 and len(right_eye) == 71,
           " (%d and %d of 71 columns)" % (len(left_eye), len(right_eye)))
    mirrored = 0
    compared = 0
    for offset in range(0, 36):
        here = left_eye.get(75 + offset)
        there = right_eye.get(181 - offset)
        if here is None or there is None:
            continue
        compared += 1
        if abs(here - there) <= 1:
            mirrored += 1
    report("the two eyes mirror each other", compared >= 30 and mirrored == compared,
           " (%d of %d mirror columns agree within a pixel)" % (mirrored, compared))
    apex = min(left_eye.values())
    report("the lid still sits on its own rows", 90 <= apex <= 104,
           " (apex row %d)" % apex)

    # A face whose eyes are already level: nothing may change, not one byte.
    level = canvas(width, height)
    paint_eye(level, width, 40, 110, 96, 0.5)
    paint_eye(level, width, 146, 216, 96, 0.5)
    untouched, level_notes = face_eyes.centre_pupils(level, width, height)
    report("already level: left alone", bytes(untouched) == bytes(level))
    report("already level: said so", all("left alone" in note or "forward" in note
                                         for note in level_notes),
           " (%s)" % "; ".join(level_notes[:1]))

    # A face with no eyes at all: no pair found, no edits made.
    blank = canvas(width, height)
    bare, bare_notes = face_eyes.centre_pupils(blank, width, height, force=True)
    report("no eyes: left alone", bytes(bare) == bytes(blank))
    report("no eyes: said so", any("untouched" in note for note in bare_notes),
           " (%s)" % "; ".join(bare_notes[:1]))

    # The writing: a PNG that reads back as exactly the pixels handed to it.
    written = face_eyes.png_bytes(fixed, width, height)
    again, got_width, got_height = glb_model.decode_png(written)
    report("png: same size", (got_width, got_height) == (width, height),
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
