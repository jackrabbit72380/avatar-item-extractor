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


def opening(pixels, left, right):
    """The texels between the eye's own top and bottom ink: the opening itself.

    Everything in that row range, white sclera included - ``texels`` only picks
    ink, and the point of the drawing is that there is an opening to see.
    """
    rows = [y for x, y in texels(pixels, left, right)]
    if not rows:
        return set()
    return {(x, y) for x in range(left, right + 1)
            for y in range(min(rows) + 6, max(rows) - 5)}


def pixels_at(pixels, point):
    x, y = point
    at = (y * WIDTH + x) * 4
    return tuple(pixels[at:at + 3])


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

    # The eye has to come out OPEN, with one pupil in the middle of the opening:
    # the avatars are drawn shut, both pupils under the same corner, which is the
    # sideways stare this pass exists to remove.
    left, right = LEFT_EYE
    inside = opening(fixed, left, right)
    white = [point for point in inside
             if all(channel > 200 for channel in pixels_at(fixed, point))]
    report("the eye is drawn open, not shut", len(white) >= 40,
           " (%d sclera texels)" % len(white))
    # The lid line runs into the corners, where the opening pinches shut; the
    # pupil is what is dark in the middle half of the eye.
    quarter = (right - left) // 4
    dark = [point for point in inside if ink(fixed, point[0], point[1])
            and left + quarter <= point[0] <= right - quarter]
    where = centre(dark, left, right)
    report("one pupil is drawn, not two", blob_count(dark) == 1,
           " (%d blob(s), %d texels)" % (blob_count(dark), len(dark)))
    report("it sits on the middle of the eye",
           where is not None and abs(where - 0.5) <= 0.08,
           " (%.2f)" % (where if where is not None else -1))
    report("it is clear of both corners",
           bool(dark) and min(x for x, _ in dark) - left >= 3
           and right - max(x for x, _ in dark) >= 3,
           " (%d texels in from the nearest corner)"
           % min(min(x for x, _ in dark) - left, right - max(x for x, _ in dark)))
    report("it is round, not a stroke along the eye",
           bool(dark) and max(y for _, y in dark) - min(y for _, y in dark)
           <= 0.6 * (right - left),
           " (%d rows tall in a %d wide eye)"
           % (max(y for _, y in dark) - min(y for _, y in dark), right - left))
    report("both eyes reported", len(notes) == 2, " (%d notes)" % len(notes))

    # The drawing keeps the eye where it was painted - it does not wander off the
    # cheek - and the brow above it is not touched.
    painted_span = (min(x for x, _ in texels(face, left, right)),
                    max(x for x, _ in texels(face, left, right)))
    drawn_span = (min(x for x, _ in texels(fixed, left, right)),
                  max(x for x, _ in texels(fixed, left, right)))
    report("it stays in the painted eye's columns",
           abs(painted_span[0] - drawn_span[0]) <= 1
           and abs(painted_span[1] - drawn_span[1]) <= 1,
           " (painted %d..%d, drawn %d..%d)"
           % (painted_span + drawn_span))
    brow = [pixels_at(face, (x, y)) for y in range(TOP - 8, TOP - 1)
            for x in range(left, right + 1)]
    brow_after = [pixels_at(fixed, (x, y)) for y in range(TOP - 8, TOP - 1)
                  for x in range(left, right + 1)]
    report("the brow above it is untouched", brow == brow_after,
           " (%d texels)" % len(brow))

    # A pair has to match across the nose. The head's UVs run left to right on
    # both sides of the face, so the second eye is the first one mirrored - a
    # straight copy puts both lash tails on the same side of the nose.
    report("both drawn eyes are a matching pair",
           rectangle(fixed, RIGHT_EYE[0], RIGHT_EYE[1])
           == [row[::-1] for row in rectangle(fixed, LEFT_EYE[0], LEFT_EYE[1])])
    # Both eyes look the same way: the pupil of each sits on the middle of its own
    # opening. A level gaze is symmetric, so the pair is a mirror of itself - what
    # must not happen is one eye looking somewhere else than the other.
    right_dark = [point for point in opening(fixed, RIGHT_EYE[0], RIGHT_EYE[1])
                  if ink(fixed, point[0], point[1])]
    right_where = centre(right_dark, RIGHT_EYE[0], RIGHT_EYE[1])
    report("both eyes look the same way",
           where is not None and right_where is not None
           and abs((where - 0.5) + (right_where - 0.5)) <= 0.05,
           " (left %.2f, right %.2f)"
           % (where if where is not None else -1,
              right_where if right_where is not None else -1))
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
