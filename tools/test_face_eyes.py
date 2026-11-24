#!/usr/bin/env python3
"""Pin the face fix: one pupil in the middle, a lash that keeps its shape.

The faces an avatar exports carry their gaze in the paint. The Marine face this
was written against has each eye drawn as one stroke - a thin tail at one corner
swelling into the pupil at the other - so the avatar looks down his nose in
every frame Halo renders. The head's UVs then run left to right on both sides
of the nose, so the pair has to be mirrored to match.

So one eye is measured and drawn again:

  * the lash follows a curve fitted through the painted stroke's top edge, at
    the weight the stroke was painted with,
  * one pupil is an ellipse hung under the middle of that lash,
  * both are sampled many times per texel, so their edges are smooth,
  * the finished eye is stamped into both drawn eyes, mirrored into the second.

A synthetic face is painted here, so the test runs without Blender and without
an asset on the machine:

  * a pupil drawn at one end ends up alone, centred, and under the lash,
  * the lash keeps the painted top edge and the painted weight,
  * the second drawn eye ends up the exact mirror of the first,
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
LID = 5          # rows of painted lash in every column
RISE = 5         # how far the lash climbs from one corner to the other
SWELL = 9        # rows the pupil was painted under the lash


def canvas(colour=SKIN):
    pixels = bytearray(WIDTH * HEIGHT * 4)
    for index in range(0, len(pixels), 4):
        pixels[index:index + 4] = bytes(colour)
    return pixels


def paint(pixels, x, y, colour=INK):
    at = (y * WIDTH + x) * 4
    pixels[at:at + 4] = bytes(colour)


def paint_eye(pixels, left, right, swell):
    """One eye: a lash across the span, swelling into a pupil at `swell`.

    `swell` is 0.0 for a pupil at the left corner and 1.0 for the right, which
    is how these faces are drawn - the pupil sits at one end of the stroke, not
    under the middle of it.
    """
    span = right - left
    for x in range(left, right + 1):
        t = (x - left) / float(span)
        arc = TOP + int(round(RISE * t))
        for row in range(LID):
            paint(pixels, x, arc + row)
        depth = int(round(SWELL * max(0.0, 1 - abs(t - swell) * 4)))
        for extra in range(depth):
            paint(pixels, x, arc + LID + extra)


def ink(pixels, x, y):
    at = (y * WIDTH + x) * 4
    return 0.299 * pixels[at] + 0.587 * pixels[at + 1] + 0.114 * pixels[at + 2] < 140


def texels(pixels, left, right, first=TOP, last=BOTTOM):
    return {(x, y) for x in range(left, right + 1)
            for y in range(first, last + 1) if ink(pixels, x, y)}


def top_row(pixels, left, right):
    """The row each column's ink starts on, which is the lash's top edge."""
    rows = {}
    for x in range(left, right + 1):
        for y in range(TOP - 8, BOTTOM + 8):
            if ink(pixels, x, y):
                rows[x] = y
                break
    return rows


def pupil(pixels, left, right):
    """Everything painted under the lash: the pupil, if the fix did its job."""
    rows = top_row(pixels, left, right)
    return {(x, y) for x, y in texels(pixels, left, right)
            if y > rows.get(x, TOP) + LID + 1}


def touching(pixels, points, left, right):
    """The columns of `points` whose ink starts right under that column's lash."""
    rows = top_row(pixels, left, right)
    columns = {}
    for x, y in points:
        columns.setdefault(x, []).append(y)
    return [x for x, ys in columns.items()
            if min(ys) <= rows.get(x, TOP) + LID + 2]


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


def rectangle(pixels, left, right):
    """One eye's rectangle, as rows of texels, for comparing two of them."""
    return [[bytes(pixels[(y * WIDTH + x) * 4:(y * WIDTH + x) * 4 + 4])
             for x in range(left, right + 1)]
            for y in range(TOP, BOTTOM + 1)]


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
    # each toward its own corner.
    face = canvas()
    paint_eye(face, LEFT_EYE[0], LEFT_EYE[1], 0.9)
    paint_eye(face, RIGHT_EYE[0], RIGHT_EYE[1], 0.1)
    before = centre(pupil(face, LEFT_EYE[0], LEFT_EYE[1]),
                    LEFT_EYE[0], LEFT_EYE[1])
    fixed, notes = face_eyes.centre_pupils(face, WIDTH, HEIGHT, force=True)
    report("drawn at one end: the pupil was off centre",
           before is not None and abs(before - 0.5) > 0.1, " (%.2f)" % (before or 0))

    # One pupil, in the middle, hanging from the lash.
    drawn = pupil(fixed, LEFT_EYE[0], LEFT_EYE[1])
    where = centre(drawn, LEFT_EYE[0], LEFT_EYE[1])
    hanging = touching(fixed, drawn, LEFT_EYE[0], LEFT_EYE[1])
    report("one pupil is drawn, not two", blob_count(drawn) == 1,
           " (%d blob(s), %d texels)" % (blob_count(drawn), len(drawn)))
    report("it sits on the middle of the eye",
           where is not None and abs(where - 0.5) <= 0.08, " (%.2f)" % (where or 0))
    report("it hangs from the lash", bool(hanging),
           " (%d of its columns touch the lash)" % len(hanging))
    report("it is no wider than the eye it is in",
           bool(drawn)
           and max(x for x, _ in drawn) - min(x for x, _ in drawn)
           <= 0.5 * (LEFT_EYE[1] - LEFT_EYE[0]),
           " (%d of %d columns)"
           % (max(x for x, _ in drawn) - min(x for x, _ in drawn),
              LEFT_EYE[1] - LEFT_EYE[0]))
    report("both eyes reported", len(notes) == 2, " (%d notes)" % len(notes))

    # The lash is redrawn from the painting, not invented: its top edge lands on
    # the painted rows, and it keeps the weight the stroke was painted with.
    painted_top = top_row(face, LEFT_EYE[0], LEFT_EYE[1])
    fixed_top = top_row(fixed, LEFT_EYE[0], LEFT_EYE[1])
    on_row = sum(1 for x in painted_top
                 if abs(painted_top[x] - fixed_top.get(x, -99)) <= 1)
    report("the lash keeps the painted top edge",
           on_row >= 0.9 * len(painted_top),
           " (%d of %d columns within a row)" % (on_row, len(painted_top)))
    weight = sorted(fixed_top[x] for x in fixed_top)
    spread = sorted(max(y for y in range(TOP - 8, BOTTOM + 8) if ink(fixed, x, y))
                    - fixed_top[x] + 1 for x in fixed_top if x < LEFT_EYE[0] + 8)
    report("the lash keeps the painted weight",
           spread and abs(sorted(spread)[len(spread) // 2] - LID) <= 1,
           " (%s rows at the ends, painted %d)"
           % (sorted(spread)[len(spread) // 2] if spread else "?", LID))

    # A pair has to match across the nose. The head's UVs run left to right on
    # both sides of the face, so the second eye is the first one mirrored - a
    # straight copy puts both lash tails on the same side of the nose.
    report("both drawn eyes are a matching pair",
           rectangle(fixed, RIGHT_EYE[0], RIGHT_EYE[1])
           == [row[::-1] for row in rectangle(fixed, LEFT_EYE[0], LEFT_EYE[1])])
    report("the second eye is not a straight copy of the first",
           rectangle(fixed, RIGHT_EYE[0], RIGHT_EYE[1])
           != rectangle(fixed, LEFT_EYE[0], LEFT_EYE[1]))
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
