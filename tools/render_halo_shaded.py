#!/usr/bin/env python3
"""Draw the compiled .jms with its own base maps on it, so it can be looked at.

render_halo_skin.py draws the shape in flat grey and one colour per bone. That
answers "is the surface torn, and which bone owns it", and it cannot answer
"is the pad where the pad belongs, and is the paint on the right part of it" -
a plate that slid halfway down an arm is still one flat grey plate there.

This samples the sheet each material is bound to, per pixel, through the same
UVs the .jms carries, and lights it. No Blender, no GPU, no third-party module.

    python3 tools/render_halo_shaded.py "<model.jms>" <textures-dir> <out-dir>

The textures directory is searched for "<stem> face.png" and the base map; a
material whose name ends in "face" gets the face sheet, everything else gets the
base map.
"""

import math
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_halo_skin as R
import test_halo_skin as H


def read_png(path):
    """Un-filtered RGB rows and their size, for a PNG this repo writes."""
    data = open(path, "rb").read()
    at, idat, wide, tall, depth, kind = 8, b"", None, None, None, None
    while at < len(data):
        length = struct.unpack(">I", data[at:at + 4])[0]
        tag = data[at + 4:at + 8]
        body = data[at + 8:at + 8 + length]
        if tag == b"IHDR":
            wide, tall, depth, kind = struct.unpack(">IIBB", body[:10])
        elif tag == b"IDAT":
            idat += body
        at += 12 + length
    if kind not in (2, 6) or depth != 8:
        raise SystemExit("%s: only 8-bit RGB/RGBA PNG is read here" % path)
    channels = 3 if kind == 2 else 4
    raw = zlib.decompress(idat)
    stride = wide * channels + 1
    rows, before = [], bytearray(wide * channels)
    for y in range(tall):
        kind_of_row = raw[y * stride]
        line = bytearray(raw[y * stride + 1:y * stride + stride])
        if kind_of_row == 1:
            for k in range(channels, len(line)):
                line[k] = (line[k] + line[k - channels]) & 255
        elif kind_of_row == 2:
            for k in range(len(line)):
                line[k] = (line[k] + before[k]) & 255
        elif kind_of_row == 3:
            for k in range(len(line)):
                left = line[k - channels] if k >= channels else 0
                line[k] = (line[k] + ((left + before[k]) >> 1)) & 255
        elif kind_of_row == 4:
            for k in range(len(line)):
                left = line[k - channels] if k >= channels else 0
                up = before[k]
                corner = before[k - channels] if k >= channels else 0
                guess = left + up - corner
                to_left = abs(guess - left)
                to_up = abs(guess - up)
                to_corner = abs(guess - corner)
                if to_left <= to_up and to_left <= to_corner:
                    nearest = left
                elif to_up <= to_corner:
                    nearest = up
                else:
                    nearest = corner
                line[k] = (line[k] + nearest) & 255
        rows.append(line)
        before = line
    return wide, tall, channels, rows


def read_uvs_and_materials(path):
    """The UVs and the material of each triangle, in the file's own order."""
    lines = [line.rstrip("\r\n") for line in open(path, encoding="latin-1")]

    def fields(text, least):
        parts = text.split("\t")
        return parts if len(parts) >= least else text.split()

    head = fields(lines[0], 3)
    at = 1 + int(head[2])
    materials = []
    count = int(lines[at])
    for k in range(1, count + 1):
        materials.append(fields(lines[at + k], 2)[0])
    at += 1 + count
    at += 1 + int(lines[at])          # markers
    at += 1 + int(lines[at])          # regions
    verts = int(lines[at])
    at += 1
    uvs = []
    for k in range(verts):
        field = fields(lines[at + k], 11)
        uvs.append((float(field[9]), float(field[10])))
    at += verts
    faces = int(lines[at])
    at += 1
    shaders = []
    for k in range(faces):
        shaders.append(int(fields(lines[at + k], 5)[1]))
    return materials, uvs, shaders


def sheet_for(materials, uvs, shaders, folder, stem):
    """One decoded sheet per material, picked by the material's own name."""
    sheets = {}
    names = sorted(os.listdir(folder))
    face_name = None
    base_name = None
    for name in names:
        if not name.lower().endswith(".png"):
            continue
        if name.lower().startswith(stem.lower() + " face"):
            face_name = name
        elif base_name is None:
            base_name = name
    for name in names:
        if not name.lower().endswith(".png"):
            continue
        if name.lower().startswith(stem.lower()) and "face" not in name.lower():
            base_name = name
            break
    for index, material in enumerate(materials):
        wanted = face_name if material.lower().endswith("face") else base_name
        if wanted is None:
            continue
        sheets[index] = read_png(os.path.join(folder, wanted))
    return sheets


def render_shaded(points, triangles, uvs, shaders, sheets, target,
                  size=760, zoom=1.0, background=(18, 20, 26), focus=None):
    side, level, out = R.basis(target)
    light = tuple(-a for a in target)
    norm = math.sqrt(sum(a * a for a in light)) or 1.0
    light = tuple(a / norm for a in light)
    flat = [(sum(p[a] * side[a] for a in range(3)),
             sum(p[a] * level[a] for a in range(3)),
             sum(p[a] * out[a] for a in range(3))) for p in points]
    low = [min(p[a] for p in flat) for a in range(2)]
    high = [max(p[a] for p in flat) for a in range(2)]
    span = max(high[0] - low[0], high[1] - low[1]) / zoom or 1.0
    middle = ((low[0] + high[0]) / 2.0, (low[1] + high[1]) / 2.0)
    if focus is not None:
        middle = (sum(focus[a] * side[a] for a in range(3)),
                  sum(focus[a] * level[a] for a in range(3)))
    step = 2
    wide = size * step
    screen = [((a - middle[0]) / span * wide + wide / 2.0,
               wide / 2.0 - (b - middle[1]) / span * wide) for a, b, _ in flat]
    deep = [p[2] for p in flat]
    pixels = bytearray(bytes(background) * (wide * wide))
    depth = [1e30] * (wide * wide)
    for kind, one, two, three in triangles:
        sheet = sheets.get(kind)
        ax, ay = screen[one]
        bx, by = screen[two]
        cx, cy = screen[three]
        area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
        if abs(area) < 1e-12:
            continue
        ux, uy, uz = [points[two][a] - points[one][a] for a in range(3)]
        vx, vy, vz = [points[three][a] - points[one][a] for a in range(3)]
        nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        length = math.sqrt(nx * nx + ny * ny + nz * nz)
        if length < 1e-12:
            continue
        nx, ny, nz = nx / length, ny / length, nz / length
        facing = nx * light[0] + ny * light[1] + nz * light[2]
        shade = 0.35 + 0.65 * abs(facing)
        u_one, v_one = uvs[one]
        u_two, v_two = uvs[two]
        u_three, v_three = uvs[three]
        left = max(0, int(min(ax, bx, cx)))
        right = min(wide - 1, int(max(ax, bx, cx)) + 1)
        top = max(0, int(min(ay, by, cy)))
        bottom = min(wide - 1, int(max(ay, by, cy)) + 1)
        for y in range(top, bottom + 1):
            py = y + 0.5
            for x in range(left, right + 1):
                px = x + 0.5
                w0 = ((bx - px) * (cy - py) - (by - py) * (cx - px)) / area
                w1 = ((cx - px) * (ay - py) - (cy - py) * (ax - px)) / area
                w2 = 1.0 - w0 - w1
                if w0 < 0.0 or w1 < 0.0 or w2 < 0.0:
                    continue
                z = w0 * deep[one] + w1 * deep[two] + w2 * deep[three]
                at = y * wide + x
                if z >= depth[at]:
                    continue
                depth[at] = z
                if sheet is None:
                    red = green = blue = 200.0
                else:
                    wide_sheet, tall_sheet, channels, rows = sheet
                    u = w0 * u_one + w1 * u_two + w2 * u_three
                    v = w0 * v_one + w1 * v_two + w2 * v_three
                    sx = min(wide_sheet - 1,
                             max(0, int(u * (wide_sheet - 1))))
                    sy = min(tall_sheet - 1,
                             max(0, int((1.0 - v) * (tall_sheet - 1))))
                    row = rows[sy]
                    red, green, blue = row[sx * channels:sx * channels + 3]
                at3 = at * 3
                pixels[at3] = min(255, int(red * shade))
                pixels[at3 + 1] = min(255, int(green * shade))
                pixels[at3 + 2] = min(255, int(blue * shade))
    small = bytearray(size * size * 3)
    for y in range(size):
        for x in range(size):
            total = [0, 0, 0]
            for dy in range(step):
                for dx in range(step):
                    at = ((y * step + dy) * wide + x * step + dx) * 3
                    for a in range(3):
                        total[a] += pixels[at + a]
            at = (y * size + x) * 3
            for a in range(3):
                small[at + a] = total[a] // (step * step)
    return bytes(small)


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    path, folder, out = sys.argv[1], sys.argv[2], sys.argv[3]
    zoom = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
    focus = (tuple(float(value) for value in sys.argv[5:8])
             if len(sys.argv) >= 8 else None)
    os.makedirs(out, exist_ok=True)
    stem = os.path.basename(path).split(" superhigh")[0]
    materials, uvs, shaders = read_uvs_and_materials(path)
    sheets = sheet_for(materials, uvs, shaders, folder, stem)
    '' if sheets else print("no base map found in %s - drawing flat grey" % folder)
    poses = [(0.0, 0.0), (45.0, 45.0), (80.0, 60.0)]
    # The model looks along +x - it is Halo's own axis - so the camera has to
    # stand in front of it there. Looking down -y instead showed every build in
    # profile: the helmet's rim hid the eyes and the near shoulder hid the far
    # one, and a broken face read as a correct one.
    views = {"front": (1.0, -0.05, 0.06), "side": (0.05, -1.0, 0.06),
             "quarter": (0.72, -0.72, 0.30), "back": (-1.0, 0.05, 0.06)}
    made = 0
    for shoulder, elbow in poses:
        names, _rest, moved, weights, corners = R.posed_points(path, shoulder, elbow)
        if len(corners) != len(shaders):
            raise SystemExit("%s: %d triangles read twice - %d and %d"
                             % (path, len(corners), len(corners), len(shaders)))
        posed = [(shaders[k], a, b, c) for k, (a, b, c) in enumerate(corners)]
        for view, target in views.items():
            picture = render_shaded(moved, posed, uvs, shaders, sheets, target,
                                    zoom=zoom, focus=focus)
            name = "shaded-%s-%02d-%02d.png" % (view, int(shoulder), int(elbow))
            R.write_png(os.path.join(out, name), 760, 760, picture)
            made += 1
    print("wrote %d pictures to %s" % (made, out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
