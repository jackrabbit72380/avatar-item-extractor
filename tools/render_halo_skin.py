#!/usr/bin/env python3
"""Draw the compiled .jms the way Halo would draw it, so it can be looked at.

The measurement in test_halo_skin.py counts edges; it cannot say whether the
thing on screen looks like a person in armour. This poses the same file with
the same node maths and rasterises it, writing PNGs to look at.

    python3 tools/render_halo_skin.py "model superhigh.jms" /tmp/shots

No Blender, no GPU, no third-party module: a z-buffered triangle fill and a
zlib PNG writer, so it runs anywhere the measurement does.

Colours:
    surface  plain lit grey, which is where shape and cracks show
    bone     each vertex tinted by the node that owns most of it, so the
             boundaries between bones can be seen across the surface
"""

import math
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_halo_skin as H


def posed_points(path, shoulder, elbow):
    """Every vertex where Halo puts it for this pose."""
    names, first, sib, turns, spots, points, weights, triangles = H.parse(path)
    worlds, parent = H.bind_worlds(first, sib, turns, spots)
    posed = H.posed_worlds(worlds, parent, turns, spots, names, shoulder, elbow)
    shift = []
    for index in range(len(names)):
        posed_r, posed_t = posed[index]
        back = H.inverse(worlds[index])
        shift.append((H.product(posed_r, back[0]),
                      tuple(posed_t[a] + H.carried(posed_r, back[1])[a]
                            for a in range(3))))
    moved = []
    for point, ride in zip(points, weights):
        total = (0.0, 0.0, 0.0)
        for node, share in ride.items():
            rotation, spot = shift[node]
            turned = H.carried(rotation, point)
            total = tuple(total[a] + share * (turned[a] + spot[a])
                          for a in range(3))
        moved.append(total)
    return names, points, moved, weights, triangles


def write_png(path, width, height, pixels):
    rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            at = (y * width + x) * 3
            row += pixels[at:at + 3]
        rows.append(bytes(row))
    body = zlib.compress(b"".join(rows), 6)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", body) + chunk(b"IEND", b""))
    open(path, "wb").write(png)


def basis(target, up=(0.0, 0.0, 1.0)):
    """Camera frame looking from target towards the origin: right, up, out."""
    length = math.sqrt(sum(a * a for a in target)) or 1.0
    out = tuple(-a / length for a in target)
    side = (out[1] * up[2] - out[2] * up[1],
            out[2] * up[0] - out[0] * up[2],
            out[0] * up[1] - out[1] * up[0])
    size = math.sqrt(sum(a * a for a in side)) or 1.0
    side = tuple(a / size for a in side)
    level = (side[1] * out[2] - side[2] * out[1],
             side[2] * out[0] - side[0] * out[2],
             side[0] * out[1] - side[1] * out[0])
    return side, level, out


def render(points, triangles, colours, target, size=760, zoom=1.0, background=(18, 20, 26)):
    """One orthographic view, two-by-two supersampled, z-buffered."""
    side, level, out = basis(target)
    light = tuple(-a for a in target)
    norm = math.sqrt(sum(a * a for a in light)) or 1.0
    light = tuple(a / norm for a in light)

    flat = []
    for p in points:
        flat.append((sum(p[a] * side[a] for a in range(3)),
                     sum(p[a] * level[a] for a in range(3)),
                     sum(p[a] * out[a] for a in range(3))))
    low = [min(p[a] for p in flat) for a in range(2)]
    high = [max(p[a] for p in flat) for a in range(2)]
    span = max(high[0] - low[0], high[1] - low[1]) / zoom or 1.0
    middle = ((low[0] + high[0]) / 2.0, (low[1] + high[1]) / 2.0)

    step = 2
    wide = size * step
    screen = []
    for a, b, _back in flat:
        screen.append(((a - middle[0]) / span * wide + wide / 2.0,
                       wide / 2.0 - (b - middle[1]) / span * wide))
    deep = [p[2] for p in flat]

    colour = bytes(background) * (wide * wide)
    colours_out = bytearray(colour)
    depth = [1e30] * (wide * wide)

    for triangle in triangles:
        one, two, three = triangle[0], triangle[1], triangle[2]
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
        shade = 0.28 + 0.72 * abs(facing)
        tints = [colours[one], colours[two], colours[three]]
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
                r = (w0 * tints[0][0] + w1 * tints[1][0] + w2 * tints[2][0]) * shade
                g = (w0 * tints[0][1] + w1 * tints[1][1] + w2 * tints[2][1]) * shade
                b = (w0 * tints[0][2] + w1 * tints[1][2] + w2 * tints[2][2]) * shade
                out_at = at * 3
                colours_out[out_at] = min(255, int(r))
                colours_out[out_at + 1] = min(255, int(g))
                colours_out[out_at + 2] = min(255, int(b))

    small = bytearray(size * size * 3)
    for y in range(size):
        for x in range(size):
            total = [0, 0, 0]
            for dy in range(step):
                for dx in range(step):
                    at = ((y * step + dy) * wide + x * step + dx) * 3
                    for a in range(3):
                        total[a] += colours_out[at + a]
            at = (y * size + x) * 3
            for a in range(3):
                small[at + a] = total[a] // (step * step)
    return bytes(small)


def bone_colours(names, weights):
    """A stable hue per node, so a bone's territory is one colour on screen."""
    palette = []
    for index in range(len(names)):
        hue = (index * 0.6180339887) % 1.0
        sat, val = 0.75, 1.0
        sector = hue * 6.0
        low = val * (1.0 - sat)
        rise = val * (1.0 - sat * (sector % 1.0))
        fall = val * (1.0 - sat * (1.0 - sector % 1.0))
        table = {0: (val, fall, low), 1: (rise, val, low), 2: (low, val, fall),
                 3: (low, rise, val), 4: (fall, low, val), 5: (val, low, rise)}
        palette.append(tuple(int(c * 255) for c in table[int(sector) % 6]))
    return [palette[max(ride, key=ride.get)] for ride in weights]


def crop(points, colours, triangles, middle, radius):
    """Just the triangles inside a ball, renumbered, so the fit zooms in."""
    keep = [index for index, p in enumerate(points)
            if math.dist(p, middle) < radius]
    if not keep:
        raise SystemExit("nothing within %g of %s" % (radius, middle))
    slot = {index: at for at, index in enumerate(keep)}
    inside = []
    for triangle in triangles:
        if all(index in slot for index in triangle):
            inside.append(tuple(slot[index] for index in triangle))
    if not inside:
        raise SystemExit("no triangle wholly inside that ball")
    return ([points[i] for i in keep], [colours[i] for i in keep], inside)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    path, folder = sys.argv[1], sys.argv[2]
    os.makedirs(folder, exist_ok=True)
    poses = [(0.0, 0.0), (45.0, 45.0), (80.0, 60.0)]
    views = {"front": (0.0, -1.0, 0.06), "side": (1.0, -0.12, 0.06),
             "quarter": (0.72, -0.72, 0.30), "back": (0.05, 1.0, 0.06)}
    made = []
    close = None
    if len(sys.argv) > 6:
        close = (tuple(float(a) for a in sys.argv[3:6]), float(sys.argv[6]))
        poses = [(0.0, 0.0), (45.0, 45.0)]
        views = {"front": (0.0, -1.0, 0.10), "quarter": (0.8, -0.6, 0.35)}
    for shoulder, elbow in poses:
        names, _rest, moved, weights, triangles = posed_points(path, shoulder, elbow)
        tint = bone_colours(names, weights)
        plain = [(206, 204, 198)] * len(moved)
        for what, colours in (("surface", plain), ("bone", tint)):
            shown, shown_colours, shown_triangles = moved, colours, triangles
            if close:
                shown, shown_colours, shown_triangles = crop(
                    moved, colours, triangles, close[0], close[1])
            for view, target in views.items():
                picture = render(shown, shown_triangles, shown_colours, target)
                name = "%s-%s-%02d-%02d.png" % (what, view, int(shoulder), int(elbow))
                if close:
                    name = "close-" + name
                write_png(os.path.join(folder, name), 760, 760, picture)
                made.append(name)
    print("wrote %d pictures to %s" % (len(made), folder))
    for name in made:
        print("  " + name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
