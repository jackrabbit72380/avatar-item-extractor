"""Show what an item's derived team-colour mask does to its base map.

Renders nothing in 3D: it applies the engine's own rule to the pixels,
`out = lerp(base, base * colour, mask)`, and writes a sheet of the item's base
map under a few team colours next to the mask itself. Use it to judge a derived
amount before building anything in the editing kit - a mask that tints the
whole item, or none of it, is obvious here and easy to miss in a lit render.

    python3 tools/tint_preview.py \
        --base "out/extracted for max users/Item base map + decal.png" \
        --mask "out/extracted for max users/Item change colour.png" \
        --out preview/item --colour 215,35,30 --colour 40,90,215

Colours are r,g,b out of 255 and default to red, blue, green and yellow.
"""
import argparse
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))
from extract_items import write_png  # noqa: E402


def read_png(path):
    """Decode a PNG to RGBA bytes, whatever its colour type or filters."""
    raw = open(path, "rb").read()
    if raw[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("%s is not a PNG" % path)
    pos, chunks, width, height, kind = 8, b"", 0, 0, 6
    while pos + 8 <= len(raw):
        size = struct.unpack_from(">I", raw, pos)[0]
        tag = raw[pos + 4:pos + 8]
        if tag == b"IHDR":
            width, height, _depth, kind = struct.unpack_from(">IIBB", raw, pos + 8)
        elif tag == b"IDAT":
            chunks += raw[pos + 8:pos + 8 + size]
        pos += 12 + size
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[kind]
    data = zlib.decompress(chunks)
    stride = width * channels
    lines = bytearray(stride * height)
    previous = bytearray(stride)
    at = 0
    for y in range(height):
        kind_of_row = data[at]
        at += 1
        line = bytearray(data[at:at + stride])
        at += stride
        if kind_of_row == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 255
        elif kind_of_row == 2:
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 255
        elif kind_of_row == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 255
        elif kind_of_row == 4:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                up = previous[i]
                corner = previous[i - channels] if i >= channels else 0
                guess = left + up - corner
                da, db, dc = abs(guess - left), abs(guess - up), abs(guess - corner)
                near = left if (da <= db and da <= dc) else (up if db <= dc else corner)
                line[i] = (line[i] + near) & 255
        lines[y * stride:(y + 1) * stride] = line
        previous = line
    out = bytearray(width * height * 4)
    for y in range(height):
        for x in range(width):
            src = y * stride + x * channels
            dst = (y * width + x) * 4
            if channels >= 3:
                out[dst:dst + 3] = lines[src:src + 3]
            else:
                grey = lines[src]
                out[dst:dst + 3] = bytes([grey, grey, grey])
            out[dst + 3] = lines[src + 3] if channels == 4 else 255
    return width, height, bytes(out)


def scale_mask(mask, mask_w, mask_h, width, height):
    """Nearest-sample the mask onto the base map's grid."""
    out = bytearray(width * height)
    for y in range(height):
        row = min(mask_h - 1, y * mask_h // height) * mask_w
        for x in range(width):
            out[y * width + x] = mask[(row + min(mask_w - 1, x * mask_w // width)) * 4]
    return out


def tint(base, amount, colour):
    out = bytearray(len(base))
    for i in range(0, len(base), 4):
        share = amount[i // 4] / 255.0
        for channel in range(3):
            value = base[i + channel]
            out[i + channel] = int(round(
                value * (1.0 - share) + value * colour[channel] / 255.0 * share))
        out[i + 3] = 255
    return bytes(out)


def sheet(panels, gap=4):
    """Lay the panels out three across, doubled so cloth texture reads."""
    zoom = 2
    cell_w = panels[0][0] * zoom
    cell_h = panels[0][1] * zoom
    columns = 3
    rows = (len(panels) + columns - 1) // columns
    width = cell_w * columns + gap * (columns - 1)
    height = cell_h * rows + gap * (rows - 1)
    out = bytearray(b"\x18\x18\x18" * (width * height))
    for i in range(3, len(out), 4):
        out[i] = 255
    for index, (w, h, data) in enumerate(panels):
        left = (index % columns) * (cell_w + gap)
        top = (index // columns) * (cell_h + gap)
        for y in range(cell_h):
            sy = min(h - 1, y // zoom)
            for x in range(cell_w):
                sx = min(w - 1, x // zoom)
                src = (sy * w + sx) * 4
                dst = ((top + y) * width + left + x) * 4
                out[dst:dst + 4] = data[src:src + 4]
    return width, height, bytes(out)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", required=True,
                        help="the base map the mp build will carry (base map + decal if it has one)")
    parser.add_argument("--mask", required=True, help="the change colour map, used for its red channel")
    parser.add_argument("--out", required=True, help="a folder for the images")
    parser.add_argument("--colour", action="append", default=None,
                        help="r,g,b out of 255; repeat for more colours")
    args = parser.parse_args(argv)

    width, height, base = read_png(args.base)
    mask_w, mask_h, mask = read_png(args.mask)
    amount = scale_mask(mask, mask_w, mask_h, width, height)
    os.makedirs(args.out, exist_ok=True)

    colours = args.colour or ["215,35,30", "40,90,215", "45,145,60", "220,190,40"]
    panels = [(width, height, base)]
    write_png(os.path.join(args.out, "base.png"), base, width, height)
    for text in colours:
        rgb = tuple(int(part) for part in text.split(","))
        if len(rgb) != 3 or max(rgb) > 255:
            print("FAIL: --colour wants r,g,b out of 255, not %r" % (text,))
            return 1
        name = "colour-%02x%02x%02x" % rgb
        data = tint(base, amount, rgb)
        write_png(os.path.join(args.out, name + ".png"), data, width, height)
        panels.append((width, height, data))
        print("  %s  base map under %r" % (name, rgb))

    grey = bytearray(width * height * 4)
    for i, value in enumerate(amount):
        grey[i * 4:i * 4 + 3] = bytes([value, value, value])
        grey[i * 4 + 3] = 255
    panels.append((width, height, bytes(grey)))

    sheet_w, sheet_h, data = sheet(panels)
    write_png(os.path.join(args.out, "sheet.png"), data, sheet_w, sheet_h)
    shares = sorted(amount)
    print("  mask %dx%d sampled to %dx%d: median %d, %d%% at 255, %d%% at 82 or below"
          % (mask_w, mask_h, width, height, shares[len(shares) // 2],
             100 * amount.count(255) // len(amount),
             100 * sum(1 for v in amount if v <= 82) // len(amount)))
    print("  wrote %s" % os.path.join(args.out, "sheet.png"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
