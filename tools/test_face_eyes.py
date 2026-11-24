#!/usr/bin/env python3
"""Pin the face fix: the painted lid is kept, the old pupil is moved to the middle.

The faces an avatar exports carry their gaze in the paint. The Marine face this
was written against has each eye drawn as one stroke - a thin tail at the outer
corner swelling into the pupil at the inner one - so the avatar looks down his
nose in every frame Halo renders. The head's UVs then mirror one eye while the
drawn pair is itself mirrored, so the two eyes do not even match each other.

So one eye is treated as the pattern and copied:

  * the lid is kept texel for texel, exactly as painted,
  * the swelling under it is erased to the cheek's own tone and a pupil is
    drawn in the middle of the lid, hanging from it,
  * the finished eye is stamped into both drawn eyes, so the UV mirroring makes
    a matching pair.

A synthetic face is painted here, so the test runs without Blender and without
an asset on the machine:

  * a pupil drawn at one end ends up centred, alone, and under the lid,
  * the lid's own rows are untouched, byte for byte,
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
LID = 3          # rows of painted lid, the same in every column
SWELL = 9        # rows the pupil was painted under the lid


def canvas(colour=SKIN):
    pixels = bytearray(WIDTH * HEIGHT * 4)
    for index in range(0, len(pixels), 4):
        pixels[index:index + 4] = bytes(colour)
    return pixels


def paint(pixels, x, y, colour=INK):
    at = (y * WIDTH + x) * 4
    pixels[at:at + 4] = bytes(colour)


def paint_eye(pixels, left, right, swell):
    """One eye: a lid across the span, swelling into a pupil at `swell`.

    `swell` is 0.0 for a pupil at the left corner and 1.0 for the right, which
    is how these faces are drawn - the pupil sits at one end of the stroke, not
    under the middle of it.
    """
    span = right - left
    for x in range(left, right + 1):
        t = (x - left) / float(span)
        for row in range(LID):
            paint(pixels, x, TOP + row)
        depth = int(round(SWELL * max(0.0, 1 - abs(t - swell) * 4)))
        for extra in range(depth):
            paint(pixels, x, TOP + LID + extra)


def ink(pixels, x, y):
    at = (y * WIDTH + x) * 4
    return 0.299 * pixels[at] + 0.587 * pixels[at + 1] + 0.114 * pixels[at + 2] < 140


def texels(pixels, left, right, first=TOP, last=BOTTOM):
    return {(x, y) for x in range(left, right + 1)
            for y in range(first, last + 1) if ink(pixels, x, y)}


def below_lid(pixels, left, right):
    return {(x, y) for x, y in texels(pixels, left, right)
            if y >= TOP + LID}


def blob_count(points):
    """How many separate blobs a set of texels makes, touching at 8 corners."""
    left = set(points)
    count = 0
    while left:
        count += 1
        stack = [left.pop()]
        while stack:
            x, y = stack.pop()
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    near = (x + dx, y + dy)
                    if near in left:
                        left.remove(near)
                        stack.append(near)
    return count


def centre(points, left, right):
    if not points:
        return None
    return (sum(x for x, _ in points) / float(len(points)) - left) \
        / float(right - left)


def lid_bytes(pixels, left, right):
    return [bytes(pixels[((TOP + row) * WIDTH + x) * 4:
                        ((TOP + row) * WIDTH + x) * 4 + 4])
            for x in range(left, right + 1) for row in range(LID)]


def rectangle(pixels, left, right):
    return lid_bytes(pixels, left, right) + [
        bytes(pixels[(y * WIDTH + x) * 4:(y * WIDTH + x) * 4 + 4])
        for y in range(TOP, BOTTOM + 1) for x in range(left, right + 1)]


def main():
    failures = []
    checks = 0

    def report(name, ok, detail=""):
        nonlocal checks
        checks += 1
        print("%s %s%s" % ("PASS" if ok else "FAIL", name, detail))
        if not ok:
            failures.append(name)

    # The case that started this: both pupils drawn at one end of their stroke,
    # so that eye is drawn twice rather than mirrored.
    face = canvas()
    paint_eye(face, LEFT_EYE[0], LEFT_EYE[1], 0.9)
    paint_eye(face, RIGHT_EYE[0], RIGHT_EYE[1], 0.1)
    before = centre(below_lid(face, LEFT_EYE[0], LEFT_EYE[1]),
                    LEFT_EYE[0], LEFT_EYE[1])
    fixed, notes = face_eyes.centre_pupils(face, WIDTH, HEIGHT, force=True)
    report("drawn at one end: the pupil was off centre",
           before is not None and abs(before - 0.5) > 0.1, " (%.2f)" % (before or 0))

    # One pupil, in the middle, hanging from the lid.
    pupil = below_lid(fixed, LEFT_EYE[0], LEFT_EYE[1])
    where = centre(pupil, LEFT_EYE[0], LEFT_EYE[1])
    report("one pupil is drawn, not two", blob_count(pupil) == 1,
           " (%d blob(s), %d texels)" % (blob_count(pupil), len(pupil)))
    report("it sits on the middle of the eye",
           where is not None and abs(where - 0.5) <= 0.08, " (%.2f)" % (where or 0))
    report("it hangs from the lid",
           bool(pupil) and min(y for _, y in pupil) <= TOP + LID + 1)
    report("it is no wider than the eye it is in",
           bool(pupil)
           and max(x for x, _ in pupil) - min(x for x, _ in pupil)
           <= 0.45 * (LEFT_EYE[1] - LEFT_EYE[0]),
           " (%d of %d columns)"
           % (max(x for x, _ in pupil) - min(x for x, _ in pupil),
              LEFT_EYE[1] - LEFT_EYE[0]))
    report("both eyes reported", len(notes) == 2, " (%d notes)" % len(notes))

    # The lid is not redrawn: its rows are the ones that were painted, and none
    # of those bytes moved.
    report("the lid is kept exactly as painted",
           lid_bytes(fixed, LEFT_EYE[0], LEFT_EYE[1])
           == lid_bytes(face, LEFT_EYE[0], LEFT_EYE[1]),
           " (%d columns, %d rows)" % (LEFT_EYE[1] - LEFT_EYE[0] + 1, LID))
    report("the lid keeps its painted top row",
           {x for x, y in texels(fixed, LEFT_EYE[0], LEFT_EYE[1]) if y == TOP}
           == {x for x in range(LEFT_EYE[0], LEFT_EYE[1] + 1)})

    # Both drawn eyes end up identical, which is what makes the mirrored UVs
    # produce a matching pair on the head.
    report("both drawn eyes are identical",
           rectangle(fixed, LEFT_EYE[0], LEFT_EYE[1])
           == rectangle(fixed, RIGHT_EYE[0], RIGHT_EYE[1]))
    report("the right eye was redrawn too",
           rectangle(fixed, RIGHT_EYE[0], RIGHT_EYE[1])
           != rectangle(face, RIGHT_EYE[0], RIGHT_EYE[1]))

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
