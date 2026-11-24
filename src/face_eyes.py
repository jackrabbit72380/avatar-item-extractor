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

  * the first drawn eye is the pattern - its lid is kept row for row, exactly
    as painted, and only the swelling under that lid is cleared away,
  * a new iris is drawn centred under that same lid,
  * the finished eye is stamped into both drawn eyes unchanged, so the head's
    mirroring turns one drawing into two eyes that are exact mirrors - which is
    what a pair of eyes is supposed to be.

Nothing here imports ``bpy``; the pixels and the PNG are plain Python so
``tools/test_face_eyes.py`` can pin the behaviour without Blender.
"""

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


def _pattern(rgba, width, skin, left, right, first, last, top, low):
    """One finished eye: the drawing as painted, with its swelling moved.

    The eye is one stroke - a thin tail at one corner swelling into the pupil at
    the other - so its thickness and its sharp edges are the drawing, not
    something to replace. This keeps every texel of it: the lash stays where it
    was painted, the swelling under it is translated along the eye until it sits
    in the middle, and its own anti-aliased coverage travels with it, which is
    what keeps it sharp instead of turning into a line.

    Returned as a grid covering the eye's own rectangle, so the same drawing can
    be stamped into both eyes and the head's mirroring makes a matching pair.
    """
    rows = last - first + 1
    columns = right - left + 1
    skin_luma = 0.299 * skin[0] + 0.587 * skin[1] + 0.114 * skin[2]
    # Coverage, not a yes/no mask: a texel half painted over skin comes back half
    # painted over skin, so moving the swelling cannot leave a hard rim behind.
    ink_luma = min(_luma(rgba, width, x, y)
                   for x in range(left, right + 1)
                   for y in range(first, last + 1))
    span = max(1.0, skin_luma - ink_luma)

    # Where the lid's underside runs: the stroke's own bottom edge, smoothed so
    # the one place it bulges down - the pupil - cannot drag the line with it.
    # The lid is then everything above that line, kept exactly as painted; the
    # pupil is the bulge below it, and only that bulge moves.
    thickness = sorted(low[x] - top[x] + 1 for x in low)
    ordinary = thickness[len(thickness) // 2]
    thin = [x for x in sorted(low) if low[x] - top[x] + 1 <= ordinary]
    if len(thin) >= 4:
        # Least-squares curve through the underside of the columns that are not
        # swollen: it says where the lid ends and the pupil begins.
        count = float(len(thin))
        mean_x = sum(thin) / count
        mean_y = sum(low[x] for x in thin) / count
        sxx = sum((x - mean_x) ** 2 for x in thin) or 1.0
        sxy = sum((x - mean_x) * (low[x] - mean_y) for x in thin)
        slope = sxy / sxx
        smooth = {x: mean_y + slope * (x - mean_x) for x in low}
    else:
        smooth = {x: low[x] for x in low}

    # The eye as painted, texel for texel: nothing is removed and nothing is
    # trimmed, because the stroke's weight and its sharp edges are the drawing.
    grid = {}
    for oy in range(rows):
        for ox in range(columns):
            at = ((first + oy) * width + left + ox) * 4
            grid[(ox, oy)] = (rgba[at], rgba[at + 1], rgba[at + 2], rgba[at + 3])

    # The room under the lid: how deep the eye is open, column by column.
    room = sorted(max(1.0, last - smooth[x]) for x in low)
    depth = room[len(room) // 2]
    if depth < 3:
        return None, 0

    # A pupil drawn in the middle, tucked a row under the lid line and clear of
    # its ends: additive, so the painted eye underneath is never disturbed.
    darkest = min((tuple(rgba[(y * width + x) * 4:(y * width + x) * 4 + 3])
                   for x in range(left, right + 1)
                   for y in range(first, last + 1)
                   if _luma(rgba, width, x, y) < INK), key=lambda colour: sum(colour))
    ink = (int(darkest[0] * 0.8), int(darkest[1] * 0.8), int(darkest[2] * 0.8))
    radius_y = max(2.5, depth * 0.55)
    radius_x = max(2.5, radius_y * 0.85)
    centre_x = (columns - 1) / 2.0
    centre_y = (first + last + 1) / 2.0 - first + 0.5
    for oy in range(rows):
        for ox in range(columns):
            x = left + ox
            if x not in top:
                continue
            if oy + first <= max(smooth[x], top[x] + 1):
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
    return grid, 0


def centre_pupils(rgba, width, height, force=False):
    """A copy of the face with one painted eye stamped into both eyes.

    Returns (pixels, notes): the notes say what was done, in plain numbers, so a
    run can report it rather than silently rewriting somebody's art. A face
    whose eyes already look level is left alone unless ``force`` is set.
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
    grid, shift = _pattern(rgba, width, skin, left, right, first, last, top, low)
    if grid is None:
        return bytearray(rgba), ["face: the eye has no swelling to move, texture untouched"]

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

    notes = ["face: eye 0 kept exactly as painted, with a pupil added in the "
             "middle of the eye",
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
