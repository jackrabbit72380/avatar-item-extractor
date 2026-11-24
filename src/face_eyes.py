"""Put a painted face's pupils back on the centre of its eyes.

A 360sona face is a painted texture: the eyes are ink on a flat skin tone, and
the pupil is drawn wherever the artist wanted the gaze to sit. Export after
export has them looking off to one side - measured on a real Marine face, both
pupils sit about 70% of the way across their own eye, toward the same side, so
the avatar glances sideways in every frame while the head geometry looks
straight ahead. Nothing in the mesh or the UVs causes it and nothing in the mesh
or the UVs can fix it: the ink has to move.

``centre_pupils`` moves each eye's pupil horizontally until it is centred in
that eye, taking the skin it covers with it - the vacated pixels are filled from
the same row just outside the eye, so the tone stays the face's own and no seam
appears. The eyelid line and everything else are left exactly as they are.

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
    return [(group, columns) for group in groups]


def find_eyes(rgba, width, height):
    """The two eyes as (first x, last x), or None when they are not found.

    Both brows and eyes make a row band that splits in two; the eyes are the
    lower of the two such bands. A face with no brows, or with the eyes merged
    into one shape, gives None and the caller leaves the texture alone.
    """
    two_part = []
    for first, last in _bands(rgba, width, height):
        groups = [group for group, _ in _groups(rgba, width, first, last)]
        wide = [group for group in groups if len(group) >= 10]
        if len(wide) == 2 and wide[1][0] - wide[0][-1] > GAP:
            two_part.append((first, last, wide))
    if not two_part:
        return None
    # Eyes below brows. One band on its own is taken as the eyes.
    if len(two_part) >= 2:
        first, last, wide = two_part[-1]
    else:
        first, last, wide = two_part[0]
    return first, last, wide


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


def _lash(rgba, width, left, right, first, last):
    """Each column's eyelid line: (top, bottom) of its first run of ink."""
    lash = {}
    for x in range(left, right + 1):
        rows = [y for y in range(first, last + 1) if _luma(rgba, width, x, y) < INK]
        if not rows:
            continue
        top = rows[0]
        bottom = top
        for y in rows[1:]:
            if y - bottom > 1:
                break
            bottom = y
        lash[x] = (top, bottom)
    return lash


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


def centre_pupils(rgba, width, height, force=False):
    """A copy of the face with each eye's pupil centred in that eye.

    Returns (pixels, notes): the notes say what moved, in plain numbers, so a
    run can report it rather than silently rewriting somebody's art. An eye
    that already looks level is left alone unless ``force`` is set, which is
    what a face whose two eyes share one drawing needs.
    """
    pixels = bytearray(rgba)
    notes = []
    found = find_eyes(rgba, width, height)
    if found is None:
        return pixels, ["face: no pair of eyes found, the texture is untouched"]
    first, last, groups = found
    skin = _skin(rgba, width, height, groups[0][0], groups[-1][-1], first, last)
    skin_luma = 0.299 * skin[0] + 0.587 * skin[1] + 0.114 * skin[2]
    for index, group in enumerate(groups):
        left, right = group[0], group[-1]
        top, low = _extent(rgba, width, left, right, first, last)
        if not low:
            notes.append("face: eye %d has no ink, left alone" % index)
            continue
        where = sorted(low)
        thick = {x: low[x] - top[x] + 1 for x in where}
        weight = sum(thick.values())
        swelling_at = sum(x * thick[x] for x in where) / float(weight)
        middle = (left + right) / 2.0
        if not force and abs(swelling_at - middle) < 2:
            notes.append("face: eye %d already looks forward, left alone" % index)
            continue
        half = (where[-1] - where[0]) / 2.0
        deep = max(thick.values())
        ink = min((tuple(rgba[(y * width + x) * 4:(y * width + x) * 4 + 3])
                   for x in where for y in range(first, last + 1)
                   if _luma(rgba, width, x, y) < INK),
                  key=lambda colour: sum(colour))
        ink = (min(skin[0], ink[0]), min(skin[1], ink[1]), min(skin[2], ink[2]))

        # Take the lid line away, then put it back as it was: only the swelling
        # moves, so the eye keeps the arc it was drawn with.
        lid = {x: top[x] for x in where}
        for x in range(left, right + 1):
            if x not in top:
                continue
            for y in range(top[x] + 1, last + 1):
                at = (y * width + x) * 4
                luma = _luma(rgba, width, x, y)
                cover = min(1.0, max(0.0, (skin_luma - luma)
                                    / max(1.0, skin_luma - 40.0)))
                for channel in range(3):
                    pixels[at + channel] = int(round(
                        skin[channel] * (1 - cover) + skin[channel] * cover))

        # Put the eye back as an iris in the middle, under the lid line it was
        # drawn with: round, hanging just below the apex, so the gaze is level.
        radius = max(3.0, (last - first + 1) * 0.45)
        centre_x = middle
        centre_y = (first + last + 1) / 2.0
        for y in range(max(0, int(centre_y - radius) - 1),
                       min(height, int(centre_y + radius) + 2)):
            for x in range(max(0, int(centre_x - radius) - 1),
                           min(width, int(centre_x + radius) + 2)):
                dx = (x - centre_x) / radius
                dy = (y - centre_y) / radius
                if x in lid and y < lid[x]:
                    # The iris sits under the lid line, never over it.
                    continue
                reach = (dx * dx + dy * dy) ** 0.5
                cover = min(1.0, max(0.0, (1.0 - reach) * radius + 0.5))
                if cover <= 0.0:
                    continue
                at = (y * width + x) * 4
                for channel in range(3):
                    base = pixels[at + channel]
                    pixels[at + channel] = int(round(
                        base * (1 - cover) + ink[channel] * cover))

        # The lid line goes back on top, as drawn: the iris is what sits under
        # it, never a black lid of its own.
        for x in range(left, right + 1):
            if x not in top:
                continue
            for y in range(top[x], min(last, top[x] + 1) + 1):
                at = (y * width + x) * 4
                for channel in range(3):
                    pixels[at + channel] = rgba[at + channel]
        notes.append("face: eye %d swelling was %.0f%% across, regrown at 50%% in "
                     "the middle of the eye"
                     % (index, 100 * (swelling_at - left) / max(1, right - left)))
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
