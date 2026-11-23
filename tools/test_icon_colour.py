#!/usr/bin/env python3
"""Prove a textureless item is painted in the colour its own icon is drawn in.

Every retail garment declares its texture slots and ships none, so the item
carries no colour of its own: no colour table, no batch colour, no pixels. What
it does ship is its own picture - the closet thumbnail it was chosen by - and
that picture is the only colour it has. The base map written for Halo is painted
from it, and `report.txt` says so, instead of the flat #CCCCCC clay that used to
say "the file states nothing".

Four things are checked:

  * the PNG reader: every filter, palette, grey, grey+alpha and RGBA
  * the colour taken from a picture: page and outline ignored, body averaged
  * the fallbacks: a colour table wins, an icon beats clay, clay is last
  * `report.txt` names the icon as the source, and says clay when there is none

    python3 tools/test_icon_colour.py
    MESH_MODULES=/tmp/unpacked python3 tools/test_icon_colour.py   # any build
"""

import importlib.util
import os
import struct
import sys
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
MODULES = os.environ.get("MESH_MODULES") or os.path.join(
    os.path.dirname(HERE), "src")


def load(name, filename):
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(MODULES, filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


items = load("extract_items", "extract_items.py")

# ------------------------------------------------------------ a PNG writer here
# Written by this test rather than by the code under test: a reader checked
# against its own writer only proves the two agree.


def paeth(left, up, corner):
    guess = left + up - corner
    pa, pb, pc = abs(guess - left), abs(guess - up), abs(guess - corner)
    if pa <= pb and pa <= pc:
        return left
    return up if pb <= pc else corner


def png(rows, width, height, colour=6, filters=None, palette=None,
        transparency=b"", depth=8, interlace=0):
    """A PNG from raw rows, filtered with the list given (0 when absent)."""
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour]
    stride = width * channels
    filters = filters or [0] * height
    previous = bytearray(stride)
    raw = bytearray()
    for index, row in enumerate(rows):
        line = bytearray(row)
        kind = filters[index]
        raw.append(kind)
        if kind == 0:
            raw += line
        elif kind == 1:
            raw += bytes((line[x] - (line[x - channels] if x >= channels else 0)) & 0xFF
                         for x in range(stride))
        elif kind == 2:
            raw += bytes((line[x] - previous[x]) & 0xFF for x in range(stride))
        elif kind == 3:
            raw += bytes((line[x] - (((line[x - channels] if x >= channels else 0)
                                      + previous[x]) >> 1)) & 0xFF
                         for x in range(stride))
        elif kind == 4:
            raw += bytes((line[x] - paeth(line[x - channels] if x >= channels else 0,
                                          previous[x],
                                          previous[x - channels] if x >= channels else 0)) & 0xFF
                         for x in range(stride))
        else:
            raise ValueError("no filter %d" % kind)
        previous = line

    def chunk(tag, body):
        return (struct.pack(">I", len(body)) + tag + body
                + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, depth,
                                         colour, 0, 0, interlace))
            + (chunk(b"PLTE", palette) if palette is not None else b"")
            + (chunk(b"tRNS", transparency) if transparency else b"")
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + chunk(b"IEND", b""))


# A marine thumbnail, 8x8, the way a closet icon is laid out: transparent page,
# a white one behind the figure, a near-black outline and an olive body.
PAGE = (0, 0, 0, 0)
WHITE = (255, 255, 255, 255)
OUTLINE = (18, 17, 14, 255)
OLIVE = (77, 73, 53, 255)
SECOND = (92, 89, 65, 255)


def figure():
    rows = []
    for y in range(8):
        row = []
        for x in range(8):
            if x in (0, 7) or y == 0:
                row.append(PAGE)
            elif x == 1:
                row.append(WHITE)
            elif x == 2:
                row.append(OUTLINE)
            elif x == 3:
                row.append(SECOND)
            else:
                row.append(OLIVE)
        rows.append(row)
    return rows


def flatten(rows, colour=6):
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour]
    out = bytearray()
    for row in rows:
        for pixel in row:
            out += bytes(pixel[:channels])
    return out


# ------------------------------------------------------------------ the checks

def main():
    failures = []

    def check(name, got, want):
        if got != want:
            failures.append("%s: %r, expected %r" % (name, got, want))
        else:
            print("  %-42s %r" % (name, got))

    # 1. The reader: RGBA, unfiltered, pixel for pixel.
    rows = figure()
    pixels = items.read_png(png([flatten([r])[0:32] for r in rows], 8, 8))
    if pixels is None:
        failures.append("read_png refused an 8-bit RGBA PNG")
    else:
        rgba, width, height = pixels
        check("icon size", (width, height), (8, 8))
        check("icon pixel (5, 4)", tuple(rgba[(4 * 8 + 5) * 4:][:4]), OLIVE)
        check("icon pixel (0, 1)", tuple(rgba[(1 * 8 + 0) * 4:][:4]), PAGE)
        check("icon pixel (2, 1)", tuple(rgba[(1 * 8 + 2) * 4:][:4]), OUTLINE)

    # 2. Every filter decodes to the same pixels. A row filtered against the one
    #    above it is where a naive reader goes wrong, so all five are here.
    for kind in (0, 1, 2, 3, 4):
        got = items.read_png(png([flatten([r])[0:32] for r in rows], 8, 8,
                                 filters=[kind] * 8))
        if got is None:
            failures.append("read_png refused filter %d" % kind)
        else:
            check("filter %d row 4" % kind,
                  tuple(got[0][(4 * 8 + 5) * 4:][:4]), OLIVE)

    # 3. Palette, grey and grey+alpha icons, widened to RGBA.
    got = items.read_png(png([b"\x00\x01"], 2, 1, colour=3,
                             palette=bytes((10, 20, 30, 200, 100, 50)),
                             transparency=bytes((255, 128))))
    check("palette pixel 0", tuple(got[0][0:4]), (10, 20, 30, 255))
    check("palette pixel 1", tuple(got[0][4:8]), (200, 100, 50, 128))
    got = items.read_png(png([b"\x4d"], 1, 1, colour=0))
    check("grey pixel", tuple(got[0][0:4]), (77, 77, 77, 255))
    got = items.read_png(png([b"\x4d\x40"], 1, 1, colour=4))
    check("grey+alpha pixel", tuple(got[0][0:4]), (77, 77, 77, 64))

    # 4. Things that are not an icon this reader understands.
    check("not a png", items.read_png(b"nope"), None)
    check("empty", items.read_png(b""), None)
    check("interlaced", items.read_png(png([flatten([r])[0:32] for r in rows],
                                           8, 8, interlace=1)), None)

    # 5. The colour taken from the picture: the page and the outline do not vote,
    #    the body does, so the result is olive rather than grey or black.
    colour = items.icon_colour(pixels)
    if colour is None:
        failures.append("icon_colour found no colour in an olive figure")
    else:
        print("  %-42s #%02X%02X%02X" % ("icon colour", *colour))
        # The body is painted in two olives, so the average of the two is what
        # the picture says the item is drawn in.
        for channel, (got, want) in enumerate(zip(colour, (0x51, 0x4D, 0x38))):
            if abs(got - want) > 3:
                failures.append("icon colour channel %d is %d, expected ~%d"
                                % (channel, got, want))
        if colour == items.CLAY:
            failures.append("icon colour is the clay fallback")

    # 6. Fallbacks: a colour table wins, an icon beats clay, clay is last.
    table = {"bases": [((12, 34, 56), 255)], "colours": [], "count": 1}
    check("table beats icon", items.item_colour([table], (77, 73, 53)), (12, 34, 56))
    check("icon beats clay", items.item_colour([], (77, 73, 53)), (77, 73, 53))
    check("clay last", items.item_colour([], None), items.CLAY)
    check("no icon at all", items.icon_colour(None), None)
    blank = (bytes((255, 255, 255, 255)) * 64, 8, 8)
    check("blank page has no colour", items.icon_colour(blank), None)

    # 7. What the report says, which is what a person reads.
    facts = {"icon_colour": (77, 73, 53), "colours": []}
    with tempfile.TemporaryDirectory() as work:
        path = os.path.join(work, "report.txt")
        items.write_report(path, "Test Item", "test.bin", 0, facts, [], None, [])
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        if "#4D4935" not in text or "own icon" not in text:
            failures.append("the report does not name the icon's colour:\n" + text)
        else:
            print("  %-42s %s" % ("report line", "the item's own icon"))

        facts = {"colours": []}
        items.write_report(path, "Test Item", "test.bin", 0, facts, [], None, [])
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        if "clay" not in text:
            failures.append("the report does not fall back to clay:\n" + text)
        else:
            print("  %-42s %s" % ("report without an icon", "clay"))

    print("")
    if failures:
        for line in failures:
            print("FAIL: " + line)
        return 1
    print("PASS: a textureless item is painted in its own icon's colour")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
