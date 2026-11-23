#!/usr/bin/env python3
"""Prove an item's own textures are read out of the model block's table.

An item's colours are not in a separate texture block: the model ends with a
table of (offset, allocated size, 33-byte header, pixels) for each slot its
materials bind - base colour, tint mask, decal. A table that is not read is an
item that looks colourless, which is what the Marine armour did until this
reader was fixed.

Three things are checked:

  * the walk: three entries, the right sizes, the empty slot skipped, and the
    padded `bytes a frame` not walking off the table
  * the pixels: a DXT1 and a DXT5 block decode to the colours that went in
  * the item: the base map comes out of the table, in its own colours

    python3 tools/test_model_texture.py
    MESH_MODULES=/tmp/unpacked python3 tools/test_model_texture.py   # any build
"""

import importlib.util
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODULES = os.environ.get("MESH_MODULES") or os.path.join(
    os.path.dirname(HERE), "src")


# The reader imports its own decompressor from beside itself.
sys.path.insert(0, MODULES)


def load(name, filename):
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(MODULES, filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


mesh = load("avatar_mesh", "avatar_mesh.py")
items = load("extract_items", "extract_items.py")

# ------------------------------------------------------------ a texture here


def rgb565(rgb):
    r, g, b = (channel * 255 // 255 for channel in rgb)
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


def dxt1(rgb, blocks=4):
    """Solid-colour DXT1: colour0, a second colour, and every texel on index 0."""
    block = struct.pack("<HHI", rgb565(rgb), 0, 0)
    return block * blocks


def dxt5(rgb, blocks=4):
    """Solid-colour DXT5: opaque alpha ramp, then the same colour block."""
    alpha = bytes((255, 255)) + bytes(6)
    colour = struct.pack("<HHI", rgb565(rgb), 0, 0)
    return (alpha + colour) * blocks


def entry(fmt, width, height, pixels, empty=False, per_frame=None,
          offset=0, allocated=None):
    """One table entry: offset, allocated size, 33-byte header, pixels."""
    allocated = len(pixels) if allocated is None else allocated
    per_frame = len(pixels) if per_frame is None else per_frame
    header = (bytes((fmt, 0x00, 0x20, 0x1A))
              + struct.pack("<II", width, height)
              + struct.pack("<IIIII", allocated, per_frame, 1,
                            (0x200 | 1) if empty else 0x200, height)
              + b"\x00")
    assert len(header) == 33, len(header)
    body = b"" if empty else pixels
    return struct.pack("<II", offset, allocated) + header + body


def table(entries):
    return b"".join(entries)


# ------------------------------------------------------------------ the checks

def main():
    failures = []

    def check(name, got, want):
        if got != want:
            failures.append("%s: %r, expected %r" % (name, got, want))
        else:
            print("  %-44s %r" % (name, got))

    olive = (0x4B, 0x4A, 0x35)
    mask = (0xFF, 0x00, 0x00)

    # 1. The walk. The middle entry's header claims 4,096 bytes a frame for 64
    #    real bytes - the padded GPU size - and the walk must still find the
    #    third entry after it.
    blob = table([entry(0x12, 8, 8, dxt1(olive), per_frame=4096),
                  entry(0x14, 8, 8, dxt5(mask), per_frame=4096, offset=32),
                  entry(0x14, 8, 8, b"", empty=True, offset=96)])
    stream = mesh.BitStream(blob)
    found = mesh.read_texture_table(stream, 3)
    check("entries read", len(found), 3)
    if len(found) == 3:
        check("base map size", (found[0]["width"], found[0]["height"]), (8, 8))
        check("base map format", hex(found[0]["format"]), "0x12")
        check("base map bytes", len(found[0]["data"]), 32)
        check("base map is not empty", found[0]["empty"], False)
        check("tint mask format", hex(found[1]["format"]), "0x14")
        check("tint mask bytes", len(found[1]["data"]), 64)
        check("third slot empty", found[2]["empty"], True)
        check("third slot has no pixels", found[2]["data"], b"")

    # 2. The pixels are the colours that went in (the byte decoder hands back
    #    RGBA row after row, so the first texel is the first four bytes).
    if len(found) == 3:
        base = mesh.decode_dxt_bytes(found[0]["data"], 8, 8, False, swap=False)
        # DXT stores 5:6:5, so the colour comes back within a few counts.
        if any(abs(int(got) - want) > 4 for got, want in zip(base[0:3], olive)):
            failures.append("base map colour: %r, expected ~%r"
                            % (tuple(base[0:3]), olive))
        else:
            print("  %-44s %r" % ("base map colour", tuple(base[0:3])))
        tint = mesh.decode_dxt_bytes(found[1]["data"], 8, 8, True, swap=False)
        check("tint mask colour", tuple(tint[0:3]), mask)
        check("tint mask alpha", tint[3], 255)

    # 3. A table that is not a table stops cleanly instead of reading junk.
    junk = b"\x00" * 8 + b"\xAA" * 33 + b"\x00" * 64
    check("junk table", mesh.read_texture_table(mesh.BitStream(junk), 3), [])
    short = table([entry(0x12, 8, 8, dxt1(olive))])[:-16]
    check("truncated table", len(mesh.read_texture_table(
        mesh.BitStream(short), 1)), 0)
    check("no entries asked for", mesh.read_texture_table(
        mesh.BitStream(b""), 0), [])

    # 4. The item: the base map comes out of the table in its own colours.
    batches = [{"textures": found,
                "materials": [{"kind": "texture", "id": 1, "texture": 0,
                               "uv_set": 0, "mode": 3},
                              {"kind": "texture", "id": 2, "texture": 1,
                               "uv_set": 1, "mode": 3}]}]
    base = items.texture_from_model(mesh, batches)
    if not base:
        failures.append("texture_from_model found no base map in the table")
    else:
        check("base map from the item", (base["width"], base["height"]), (8, 8))
        check("base map bytes recorded", base["pixels"], 32)
        if any(abs(int(got) - want) > 4
               for got, want in zip(base["rgba"][0:3], olive)):
            failures.append("base map colour again: %r, expected ~%r"
                            % (tuple(base["rgba"][0:3]), olive))
        else:
            print("  %-44s %r" % ("base map colour again",
                                   tuple(base["rgba"][0:3])))
    roles = items.slot_textures(mesh, batches)
    check("roles read", sorted(roles), [1, 2])
    if 2 in roles:
        check("tint mask size", (roles[2]["width"], roles[2]["height"]), (8, 8))

    print("")
    if failures:
        for line in failures:
            print("FAIL: " + line)
        return 1
    print("PASS: an item's own textures are read out of the model block")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
