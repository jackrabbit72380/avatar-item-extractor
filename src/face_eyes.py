"""Put a painted face's pupils back on the centre of its eyes.

A 360sona face is a painted texture: the eyes are ink on a flat skin tone, and
the pupil is drawn wherever the artist wanted the gaze to sit. Each eye is one
stroke - a thin tail at one corner that swells into the pupil at the other - so
the gaze is fixed in the paint, and nothing in the mesh or the UVs moves it.

The head's UVs were measured on the file: ``du/dx`` is positive on both sides
of the nose, so they run left to right on both eyes and do not mirror. The
drawn pair is itself mirrored, so a straight copy of one eye into the other
comes out with both lash tails on the same side of the nose - a pair that does
not match, which is what it looked like. So this works on one eye and stamps
it, mirrored, into the second:

  * the first drawn eye is the pattern - its lash is drawn again from the
    stroke's own top edge and weight, sampled well under a texel so it is a
    line rather than a staircase,
  * one pupil is drawn in the middle, hung from that lash,
  * the finished eye is stamped into both drawn eyes, mirrored into the second
    one, because the head's UVs run left to right on both sides: a straight
    copy puts the lash tail toward the nose on one side and toward the ear on
    the other, which is a pair that does not match.

Nothing here imports ``bpy``; the pixels and the PNG are plain Python so
``tools/test_face_eyes.py`` can pin the behaviour without Blender.
"""

import math
import struct
import zlib

# Ink is far darker than any of these faces: a full-strength skin tone lands
# around 180-200 luma, and the eyes, brows, mouth and beard sit near 60-110.
INK = 140

# Two eye shapes land in one row band; the brows are a second such band above
# them, so the eyes are the lower of the two. A band has to split into two
# groups with a gap between them to be either.
GAP = 12

# How many samples across a texel the redrawn eye is measured at: the eye is
# only about twenty texels tall, so its curves are drawn well under a texel and
# averaged down, which is what keeps them smooth on screen.
SAMPLES = 6


def _luma(rgba, width, x, y):
    at = (y * width + x) * 4
    return 0.299 * rgba[at] + 0.587 * rgba[at + 1] + 0.114 * rgba[at + 2]


def _bands(rgba, width, height):
    """Row bands of ink, each as (first row, last row)."""
    rows = {}
    for y in range(height):
        columns = [x for x in range(width) if _luma(rgba, width, x, y) < INK]
        if columns:
            rows[y] = columns
    bands = []
    for y in sorted(rows):
        if bands and y - bands[-1][1] <= 2:
            bands[-1][1] = y
        else:
            bands.append([y, y])
    return bands


def _groups(rgba, width, first, last):
    """The column groups of one band, split where a gap of GAP or more appears."""
    columns = {}
    for x in range(width):
        count = sum(1 for y in range(first, last + 1)
                    if _luma(rgba, width, x, y) < INK)
        if count:
            columns[x] = count
    groups = []
    for x in sorted(columns):
        if groups and x - groups[-1][-1] <= GAP:
            groups[-1].append(x)
        else:
            groups.append([x])
    return groups


def find_eyes(rgba, width, height):
    """The two eyes as (first row, last row, [(left, right), ...]) or None.

    Both brows and eyes make a row band that splits in two; the eyes are the
    lower of the two such bands. A face with no brows, or with the eyes merged
    into one shape, gives None and the caller leaves the texture alone.
    """
    two_part = []
    for first, last in _bands(rgba, width, height):
        groups = [group for group in _groups(rgba, width, first, last)
                  if len(group) >= 10]
        if len(groups) == 2 and groups[1][0] - groups[0][-1] > GAP:
            two_part.append((first, last, groups))
    if not two_part:
        return None
    first, last, groups = two_part[-1]
    return first, last, groups


def _skin(rgba, width, height, left, right, first, last):
    """The face's own tone: the median colour of the ring around the eye."""
    ring = []
    for y in range(first - 4, last + 5):
        for x in range(left - 6, right + 7):
            if y < 0 or y >= height or x < 0 or x >= width:
                continue
            if first <= y <= last and left <= x <= right:
                continue
            at = (y * width + x) * 4
            ring.append((rgba[at], rgba[at + 1], rgba[at + 2], rgba[at + 3]))
    if not ring:
        at = (min(height - 1, max(0, first - 6)) * width) * 4
        return (rgba[at], rgba[at + 1], rgba[at + 2], rgba[at + 3])
    ring.sort(key=lambda colour: 0.299 * colour[0] + 0.587 * colour[1]
              + 0.114 * colour[2])
    return ring[len(ring) // 2]


def _extent(rgba, width, left, right, first, last):
    """Each column of the eye: the top of its ink, and its whole ink extent.

    These eyes are painted as one stroke that starts as a thin tail at one
    corner and swells into the pupil at the other, so the ink is not a pupil
    sitting under a lash - the two are the same shape. Where the swelling is
    is therefore where the eye looks.
    """
    top, low = {}, {}
    for x in range(left, right + 1):
        rows = [y for y in range(first, last + 1) if _luma(rgba, width, x, y) < INK]
        if rows:
            top[x] = min(rows)
            low[x] = max(rows)
    return top, low


def _curve(points):
    """Least-squares y = a + b t + c t.t through (x, y), t = x - mean.

    Returns (a, b, c, mean), or None when there are too few points to fit or
    the system is singular - either way the caller leaves the texture alone.
    """
    count = float(len(points))
    if count < 4:
        return None
    mean = sum(point[0] for point in points) / count
    terms = [point[0] - mean for point in points]
    values = [point[1] for point in points]
    sums = [sum(term ** power for term in terms) for power in range(5)]
    wanted = [sum(value * term ** power for term, value in zip(terms, values))
              for power in range(3)]
    matrix = [[sums[0], sums[1], sums[2]],
              [sums[1], sums[2], sums[3]],
              [sums[2], sums[3], sums[4]]]
    for column in range(3):
        pivot = max(range(column, 3), key=lambda row: abs(matrix[row][column]))
        if abs(matrix[pivot][column]) < 1e-9:
            return None
        matrix[column], matrix[pivot] = matrix[pivot], matrix[column]
        wanted[column], wanted[pivot] = wanted[pivot], wanted[column]
        for row in range(column + 1, 3):
            factor = matrix[row][column] / matrix[column][column]
            for other in range(column, 3):
                matrix[row][other] -= factor * matrix[column][other]
            wanted[row] -= factor * wanted[column]
    solved = [0.0, 0.0, 0.0]
    for row in (2, 1, 0):
        solved[row] = (wanted[row]
                       - sum(matrix[row][other] * solved[other]
                             for other in range(row + 1, 3))) / matrix[row][row]
    return solved[0], solved[1], solved[2], mean


def _pattern(rgba, width, height, left, right, first, last, top, low):
    """One finished eye: a smooth lash, and one pupil in the middle of it.

    These eyes are painted on a 512-texel face, and the eye itself is only about
    seventy by twenty of them, so a stroke drawn a texel at a time reads as a
    staircase once the head is on screen. The eye is therefore measured, not
    copied, and drawn again on a finer grid:

      * the lash's centre line is a curve fitted through the stroke's painted
        top edge, so it keeps the shape it was drawn with but not its steps,
      * its weight is the weight the stroke was painted with where it is not
        swollen, so the bold line stays bold, and it tapers to a point at both
        corners,
      * the pupil is an ellipse the width of the middle of the eye, hung from
        the lash and rounded underneath,
      * both are sampled SAMPLES times per texel and averaged down, which is
        what makes their edges smooth instead of stepped.

    Returned as a grid covering the eye's own rectangle, so the same drawing can
    be stamped into both eyes.
    """
    rows = last - first + 1
    columns = right - left + 1

    measure = {x: low[x] - top[x] + 1 for x in low}
    weights = sorted(measure.values())
    ordinary = weights[len(weights) // 2]
    thin = sorted(x for x in low if measure[x] <= ordinary)
    if len(thin) < 4:
        return None

    curve = _curve([(x, top[x]) for x in sorted(top)])
    if curve is None:
        return None
    base, slope, bend, mean_x = curve

    def centre(x):
        """The lash's painted top edge, as a curve rather than a staircase."""
        t = x - mean_x
        return base + slope * t + bend * t * t

    # The weight the stroke was painted with where it was not swollen: that is
    # the lash, and it is the weight the redrawn one keeps.
    lash = sorted(measure[x] for x in thin)[len(thin) // 2]

    def weight(x):
        near = [min(measure[xi], lash)
                for xi in range(int(round(x)) - 3, int(round(x)) + 4)
                if xi in measure]
        return sum(near) / float(len(near)) if near else float(lash)

    # The eye's own ink, at its darker end, and the cheek it sits on.
    inks = []
    for x in range(left, right + 1):
        for y in range(first, last + 1):
            if _luma(rgba, width, x, y) < INK:
                at = (y * width + x) * 4
                inks.append((rgba[at], rgba[at + 1], rgba[at + 2]))
    if not inks:
        return None
    inks.sort(key=lambda colour: 0.299 * colour[0] + 0.587 * colour[1]
              + 0.114 * colour[2])
    lash_ink = inks[len(inks) // 10]
    # The pupil is a hair lighter than the lash, the way it is drawn: one mass,
    # but not quite one colour.
    pupil_ink = tuple(min(255, int(channel * 1.5) + 8) for channel in lash_ink)

    probe = min(height - 1, last + 4)
    skin = {}
    for x in range(left, right + 1):
        at = (probe * width + x) * 4
        skin[x] = (rgba[at], rgba[at + 1], rgba[at + 2], rgba[at + 3])

    centre_x = (left + right) / 2.0
    lash_bottom = centre(centre_x) + weight(centre_x)
    opening = last - lash_bottom
    if opening < 3:
        return None
    radius_x = max(2.5, columns * 0.24)
    radius_y = max(1.5, opening * 0.85)
    middle_y = lash_bottom + radius_y * 0.30
    taper = max(3.0, columns * 0.07)

    grid = {}
    share = float(SAMPLES * SAMPLES)
    for oy in range(rows):
        y = first + oy
        for ox in range(columns):
            x = left + ox
            lash_cover = 0
            pupil_cover = 0
            for sub_y in range(SAMPLES):
                sample_y = y - 0.5 + (sub_y + 0.5) / SAMPLES
                for sub_x in range(SAMPLES):
                    sample_x = x - 0.5 + (sub_x + 0.5) / SAMPLES
                    thick = weight(sample_x)
                    edge = min(sample_x - left + 0.5, right - sample_x + 0.5)
                    if edge < taper:
                        thick *= max(0.15, edge / taper)
                    middle = centre(sample_x) + weight(sample_x) / 2.0
                    if abs(sample_y - middle) <= thick / 2.0:
                        lash_cover += 1
                    across = (sample_x - centre_x) / radius_x
                    if abs(across) < 1.0:
                        under = centre(sample_x) + weight(sample_x)
                        bottom = middle_y + radius_y * math.sqrt(1.0 - across * across)
                        if under <= sample_y <= bottom:
                            pupil_cover += 1
            tone = skin[x]
            colour = [tone[channel] * (1.0 - pupil_cover / share)
                      + pupil_ink[channel] * (pupil_cover / share)
                      for channel in range(3)]
            colour = [colour[channel] * (1.0 - lash_cover / share)
                      + lash_ink[channel] * (lash_cover / share)
                      for channel in range(3)]
            grid[(ox, oy)] = (tuple(int(round(value)) for value in colour)
                              + (tone[3],))
    return grid


def centre_pupils(rgba, width, height, force=False):
    """A copy of the face with one painted eye stamped into both eyes.

    Returns (pixels, notes): the notes say what was done, in plain numbers, so a
    run can report it rather than silently rewriting somebody's art. A face
    whose eyes already look level is left alone unless ``force`` is set.

    The gaze moves, and the pair is made to match. The painted stroke is
    measured - its top edge, its weight, its ink - and drawn again as one smooth
    lash with one pupil in the middle of it, then stamped into both, mirrored
    into the second, since the head's UVs do not mirror.
    """
    found = find_eyes(rgba, width, height)
    if found is None:
        return bytearray(rgba), ["face: no pair of eyes found, the texture is untouched"]
    first, last, groups = found
    left, right = groups[0][0], groups[0][-1]
    top, low = _extent(rgba, width, left, right, first, last)
    if not low:
        return bytearray(rgba), ["face: the eye carries no ink, the texture is untouched"]
    middle = (left + right) / 2.0
    where = sorted(low)
    thick = {x: low[x] - top[x] + 1 for x in where}
    weight = sum(thick.values())
    swelling_at = sum(x * thick[x] for x in where) / float(weight)
    if not force and abs(swelling_at - middle) < 2:
        return bytearray(rgba), ["face: the eyes already look forward, texture untouched"]

    skin = _skin(rgba, width, height, groups[0][0], groups[-1][-1], first, last)
    grid = _pattern(rgba, width, height, left, right, first, last, top, low)
    if grid is None:
        return bytearray(rgba), ["face: the eye has no opening to put a pupil in, "
                                 "texture untouched"]

    pixels = bytearray(rgba)
    span = min(group[-1] - group[0] for group in groups)
    for index, group in enumerate(groups):
        gle, gright = group[0], group[-1]
        # Clear this eye completely - its own swelling and its own lid - so what
        # is stamped is the whole eye rather than one drawing over another.
        for x in range(gle, gright + 1):
            for y in range(first, last + 1):
                at = (y * width + x) * 4
                pixels[at:at + 4] = bytes(skin)
        offset = gle + int(round((gright - gle - span) / 2.0))
        # The head's UVs run left to right on both sides of the face (measured:
        # du/dx is positive on either side of the nose), so the two eyes cannot
        # both be the same drawing. The second one is the first, mirrored: that
        # is what puts both lash tails on the outside and both pupils in the
        # middle, which is a matching pair.
        for ox in range(span + 1):
            x = offset + ox
            if x < gle or x > gright:
                continue
            source_ox = (span - ox if index else ox) \
                + int(round((right - left - span) / 2.0))
            for oy in range(last - first + 1):
                colour = grid.get((source_ox, oy))
                if colour is None:
                    continue
                at = ((first + oy) * width + x) * 4
                pixels[at:at + 4] = bytes(colour)

    notes = ["face: the painted lash redrawn from its own top edge and weight, "
             "with one pupil drawn in the middle of it",
             "face: that eye stamped into both, mirrored into the second, so the "
             "pair matches across the nose"]
    return pixels, notes


def png_bytes(rgba, width, height):
    """A PNG for these pixels: 8-bit RGBA, no interlacing, filter 0 rows."""
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw.extend(rgba[y * width * 4:(y + 1) * width * 4])

    def chunk(tag, payload):
        body = tag + payload
        return (struct.pack(">I", len(payload)) + body
                + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + chunk(b"IEND", b""))
