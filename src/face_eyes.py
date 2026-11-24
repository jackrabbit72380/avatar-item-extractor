"""Put a painted face's pupils back on the centre of its eyes.

A 360sona face is a painted texture: the eyes are ink on a flat skin tone, and
the pupil is drawn wherever the artist wanted the gaze to sit. Export after
export has them looking off to one side - measured on a real Marine face, both
pupils sit about 70% of the way across their own eye, toward the same side, so
the avatar glances sideways while the head geometry looks straight ahead.
Nothing in the mesh or the UVs causes that and nothing in the mesh or the UVs
can fix it: the ink has to move.

The head's UVs mirror one eye, and the drawn pair is itself mirrored, so the
two eyes come out *unmirrored* on the model: one lash sweeps up to the left and
the other up to the left too, and no amount of care with the pupil makes the
pair look alike. Which is why this works on one eye and copies it:

  * the first drawn eye is the pattern - its lid is kept texel for texel,
    exactly as painted, and only the swelling under that lid is erased,
  * a pupil is drawn on the middle of the same lid, hanging from it,
  * the finished eye is stamped into both drawn eyes unchanged, so the head's
    mirroring turns one drawing into two eyes that are exact mirrors - which is
    what a pair of eyes is supposed to be.

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

# How many rows under a column's highest ink belong to the lid line rather than
# to the pupil under it. The lash is drawn two or three texels thick wherever
# it is not swelling into the pupil, so this is the line as it was painted.
LASH_ROWS = 3


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


def _pattern(rgba, width, height, left, right, first, last, top, low):
    """One finished eye: the painted lid, and a pupil in the middle of it.

    Each eye is painted as one stroke: a thin tail at the outer corner that
    swells into the pupil at the inner one, and the swelled end is where the
    avatar looks. The lid is everything else in that stroke, and its weight and
    its sharp edge are the drawing, so the lid is kept texel for texel and only
    the swelling under it is taken away:

      * the lid's underside is the line the stroke follows where it is not
        swollen - fitted through the thin columns and run on through the
        swollen ones,
      * every texel above that line keeps its painted colour, and the ink below
        it is erased to the cheek's own tone - the row against the lid keeps
        its own coverage, so the stroke's soft underside survives,
      * a pupil is drawn on the middle of that line, hanging from the lid, in
        the eye's own ink and with a soft edge.

    Returned as a grid covering the eye's own rectangle, so the same drawing can
    be stamped into both eyes and the head's mirroring makes a matching pair.
    """
    rows = last - first + 1
    columns = right - left + 1

    # Where the lid's underside runs: the stroke's own bottom edge, smoothed so
    # the one place it swells down - the pupil - cannot drag the line with it.
    thickness = sorted(low[x] - top[x] + 1 for x in low)
    ordinary = thickness[len(thickness) // 2]
    thin = [x for x in sorted(low) if low[x] - top[x] + 1 <= ordinary]
    if len(thin) >= 4:
        # Least-squares line through the underside of the columns that are not
        # swollen: it says where the lid ends and the pupil begins.
        count = float(len(thin))
        mean_x = sum(thin) / count
        mean_y = sum(low[x] for x in thin) / count
        sxx = sum((x - mean_x) ** 2 for x in thin) or 1.0
        sxy = sum((x - mean_x) * (low[x] - mean_y) for x in thin)
        slope = sxy / sxx
        line = {x: mean_y + slope * (x - mean_x) for x in low}
    else:
        line = {x: float(low[x]) for x in low}
    underside = {x: int(math.floor(line[x])) for x in line}

    # The eye as painted, minus the swelling under the lid. The face is flat
    # toned under the eye, and the cheek a few rows below it is the honest
    # sample of that tone, column by column: erasing to it leaves no rim of
    # guessed skin behind. The one row against the lid keeps its own coverage,
    # so the stroke's soft underside survives; everything under that is opening.
    cheek = {}
    probe = min(height - 1, last + 4)
    for x in range(left, right + 1):
        at = (probe * width + x) * 4
        cheek[x] = (rgba[at], rgba[at + 1], rgba[at + 2], rgba[at + 3])
    grid = {}
    stolen = []
    for oy in range(rows):
        for ox in range(columns):
            x = left + ox
            y = first + oy
            at = (y * width + x) * 4
            colour = (rgba[at], rgba[at + 1], rgba[at + 2], rgba[at + 3])
            if x not in underside or y <= underside[x]:
                grid[(ox, oy)] = colour
                continue
            tone = cheek[x]
            if y == underside[x] + 1:
                tone_luma = 0.299 * tone[0] + 0.587 * tone[1] + 0.114 * tone[2]
                cover = min(1.0, max(0.0, (tone_luma - _luma(rgba, width, x, y))
                                  / max(1.0, tone_luma - INK)))
            else:
                cover = 1.0
            if cover > 0.5:
                stolen.append(colour)
            grid[(ox, oy)] = tuple(
                int(round(colour[channel] * (1 - cover) + tone[channel] * cover))
                for channel in range(4))

    # The pupil: the middle of the opening under the lid, in the ink the eye was
    # drawn with, and never over the lid itself.
    opening = sorted(last - underside[x] for x in underside)
    depth = opening[len(opening) // 2]
    if depth < 3 or not stolen:
        return None
    stolen.sort(key=lambda colour: 0.299 * colour[0] + 0.587 * colour[1]
                + 0.114 * colour[2])
    ink = stolen[len(stolen) // 8]
    radius_x = max(2.5, columns * 0.17)
    radius_y = max(2.0, depth * 0.42)
    centre_x = (columns - 1) / 2.0
    middle = left + int(round(centre_x))
    centre_y = underside.get(middle, last - depth // 2) - first + depth / 2.0
    for oy in range(rows):
        for ox in range(columns):
            x = left + ox
            if x in underside and first + oy <= underside[x]:
                # Never over the lid line itself.
                continue
            dx = (ox - centre_x) / radius_x
            dy = (oy - centre_y) / radius_y
            reach = (dx * dx + dy * dy) ** 0.5
            cover = min(1.0, max(0.0, (1.0 - reach) * min(radius_x, radius_y) + 0.5))
            if cover <= 0.02:
                continue
            here = grid[(ox, oy)]
            grid[(ox, oy)] = tuple(
                int(round(here[channel] * (1 - cover) + ink[channel] * cover))
                for channel in range(3)) + (here[3],)
    return grid


def centre_pupils(rgba, width, height, force=False):
    """A copy of the face with one painted eye stamped into both eyes.

    Returns (pixels, notes): the notes say what was done, in plain numbers, so a
    run can report it rather than silently rewriting somebody's art. A face
    whose eyes already look level is left alone unless ``force`` is set.

    The pupil moves; the lid does not. The off-centre ink is erased under the
    painted lid and a pupil is drawn in the middle, and that finished eye is
    stamped into both, so each eye keeps the shape it was drawn with and the
    pair looks straight ahead.
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
        for ox in range(span + 1):
            x = offset + ox
            if x < gle or x > gright:
                continue
            source_ox = ox + int(round((right - left - span) / 2.0))
            for oy in range(last - first + 1):
                colour = grid.get((source_ox, oy))
                if colour is None:
                    continue
                at = ((first + oy) * width + x) * 4
                pixels[at:at + 4] = bytes(colour)

    notes = ["face: the painted lid kept texel for texel, with the pupil erased "
             "from under it and redrawn in the middle of the eye",
             "face: that eye stamped into both, so the head's mirrored UVs make "
             "the pair exact mirrors"]
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
