#!/usr/bin/env python3
"""Prove the shipped .bat produces the files it promises, without Blender.

The extractor half of the output is testable here: a container with a mesh, a
texture block and a colour table must come out as .obj, .mtl, a base map in
three formats, a colour card and a hex list. The rigging half cannot run
without Blender, so it is not covered - and this script says so rather than
pretending otherwise.

The model is synthetic. avatar_mesh.read_model is replaced with a three-vertex
batch and the container with three blocks, which is enough to drive the whole
write path: block scan, texture decode, colour-table decode, naming, catalogue.

    python3 tools/test_pipeline.py
"""

import base64
import json
import glob
import os
import shutil
import struct
import sys
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(HERE)
BAT = max(glob.glob(os.path.join(ROOT_DIR, "Extract*v*.bat")))

# Paths are the organised ones: max\ holds the model and its textures for Max,
# blender\ holds the same textures for Blender's rigs, hek\<build>\data\ holds
# the .tif bitmaps tool.exe compiles, and the item's own records stay beside
# those folders.
EXPECTED = (
    "extracted for max users/UNSC Marine Armor.obj",
    "extracted for max users/UNSC Marine Armor.mtl",
    "extracted for max users/UNSC Marine Armor base map.png",
    "extracted for max users/UNSC Marine Armor base map.tga",
    "extracted for blender users/UNSC Marine Armor base map.png",
    "extracted for hek users/pc/data/UNSC Marine Armor/bitmaps/UNSC Marine Armor base map.tif",
    "extracted for hek users/xbox/data/UNSC Marine Armor/bitmaps/UNSC Marine Armor base map.tif",
    "UNSC Marine Armor_colours.txt",
    "colour_00.png",
    "catalogue.json",
)

# Which Halo builds each mask set belongs in. The HEK side of every one lives
# inside the item's own data folder, because that is the directory tool.exe is
# pointed at: data\<item>\bitmaps.
MASK_BUILDS = {
    "multipurpose": ("pc", "xbox"),
    "change colour": ("pc", "xbox"),
}


def homes_for(family, stem):
    """(folder, extension) for every copy of one bitmap family."""
    wanted = []
    for folder in ("extracted for max users", "extracted for blender users"):
        wanted.append((folder, "png"))
        wanted.append((folder, "tga"))
    for build in MASK_BUILDS[family]:
        wanted.append(("extracted for hek users/%s/data/%s/bitmaps"
                       % (build, stem), "tif"))
    return wanted


def texture_block():
    """A 33-byte header and DXT5 pixels, the shape a Texture block has."""
    header = bytearray(33)
    header[0] = 0x14  # DXT5
    struct.pack_into("<H", header, 1, 0x1A20)
    struct.pack_into("<II", header, 4, 16, 16)
    struct.pack_into("<I", header, 12, 256)
    struct.pack_into("<I", header, 16, 256)
    struct.pack_into("<I", header, 20, 1)
    struct.pack_into("<I", header, 24, 0)
    struct.pack_into("<I", header, 28, 16)
    return bytes(header) + bytes([0xFF, 0xFF, 0xE0, 0x07, 0, 0, 0, 0]) * 16 + b"\0" * 128


def colour_block():
    """count, three base colours, then the palette - the block 7 layout."""
    out = struct.pack("<I", 3)
    for rgb in ((200, 30, 30), (30, 200, 30), (30, 30, 200)):
        out += bytes(rgb) + b"\xff" + struct.pack("<I", 0)
    for rgb in ((10, 20, 30), (40, 50, 60), (70, 80, 90)):
        out += bytes(rgb) * 3
    return out


def batches():
    # One UV set a vertex, laid out as a small island: the masks are painted from
    # this, so it has to be a real layout rather than a single shared point.
    return [{
        "shader_id": 1,
        "vertices": [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)],
        "uvs": [[(0.10, 0.10)], [(0.40, 0.10)], [(0.10, 0.40)]],
        "materials": [{"kind": "texture", "id": 1, "texture": 0, "uv_set": 0, "mode": 0}],
        "joints": [(0, 0, 0, 0)] * 3,
        "weights": [(1.0, 0.0, 0.0, 0.0)] * 3,
        "colours": [0, 0, 0],
        "indices": [0, 1, 2],
    }]


def two_parts():
    """Two batches sharing a shader id, each with its own colour."""
    parts = []
    for colour in ([0.6, 0.2, 0.1], [0.1, 0.3, 0.6]):
        parts.append({
            "shader_id": 0,
            "vertices": [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)],
            "uvs": [[(0.10, 0.10)], [(0.40, 0.10)], [(0.10, 0.40)]],
            "materials": [{"kind": "vector", "id": 22, "value": colour + [1.0]}],
            "joints": [(0, 0, 0, 0)] * 3,
            "weights": [(1.0, 0.0, 0.0, 0.0)] * 3,
            "colours": [0, 0, 0],
            "indices": [0, 1, 2],
        })
    return parts


def pixels(path):
    """Every RGBA pixel of a PNG, without a decoder library."""
    with open(path, "rb") as handle:
        raw = handle.read()
    name = os.path.basename(path)
    if raw[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("%s is not a PNG" % name)
    pos, idat, width, height = 8, b"", 0, 0
    while pos + 8 <= len(raw):
        size = struct.unpack_from(">I", raw, pos)[0]
        tag = raw[pos + 4:pos + 8]
        if tag == b"IHDR":
            width, height = struct.unpack_from(">II", raw, pos + 8)
            depth, colour = raw[pos + 16], raw[pos + 17]
            if (depth, colour) != (8, 6):
                raise ValueError("%s is %d-bit type %d, not 8-bit RGBA"
                                 % (name, depth, colour))
        elif tag == b"IDAT":
            idat += raw[pos + 8:pos + 8 + size]
        pos += 12 + size
    rows = zlib.decompress(idat)
    stride = width * 4
    out = []
    for row in range(height):
        start = row * (stride + 1)
        if rows[start] != 0:
            raise ValueError("%s row %d uses filter %d"
                             % (name, row, rows[start]))
        line = rows[start + 1:start + 1 + stride]
        out.extend(struct.unpack(">%dB" % stride, line))
    return [tuple(out[i:i + 4]) for i in range(0, len(out), 4)]


def first_pixel(path):
    """The RGBA of a PNG's top-left pixel."""
    return pixels(path)[0]


def tiff(path):
    """Every RGBA texel of a one-strip 8-bit TIFF, the shape write_tiff makes."""
    with open(path, "rb") as handle:
        raw = handle.read()
    name = os.path.basename(path)
    if raw[:4] != b"II*\x00":
        raise ValueError("%s is not a little-endian TIFF" % name)
    ifd = struct.unpack_from("<I", raw, 4)[0]
    count = struct.unpack_from("<H", raw, ifd)[0]
    tags = {}
    for index in range(count):
        at = ifd + 2 + index * 12
        tag, kind, many = struct.unpack_from("<HHI", raw, at)
        tags[tag] = (struct.unpack_from("<H", raw, at + 8)[0] if kind == 3 and many == 1
                     else struct.unpack_from("<I", raw, at + 8)[0])
    width, height = tags[256], tags[257]
    strip = raw[tags[273]:tags[273] + tags[279]]
    texels = [tuple(strip[i:i + 4]) for i in range(0, len(strip), 4)]
    if len(texels) != width * height:
        raise ValueError("%s holds %d texels, header says %dx%d"
                         % (name, len(texels), width, height))
    return texels


def main():
    work = tempfile.mkdtemp(prefix="avatar-pipeline-")
    try:
        # Unpack the modules the .bat actually ships, so the test follows the
        # artifact rather than a copy of it that may have drifted.
        sys.path.insert(0, HERE)
        import payload

        with open(BAT, encoding="utf-8", newline="") as handle:
            entries = payload.read_entries(handle.read())
        for name, value in entries.items():
            path = os.path.join(work, name.replace("/", os.sep))
            parent = os.path.dirname(path)
            if parent:
                os.makedirs(parent, exist_ok=True)
            if isinstance(value, dict):
                with open(path, "wb") as handle:
                    handle.write(base64.b64decode(value["b64"].encode("ascii")))
            else:
                with open(path, "w", encoding="utf-8", newline="") as handle:
                    handle.write(value)

        # The script that drives tool.exe is part of what a player gets:
        # rig_items.py writes build-hek.bat from beside itself into the output,
        # so a payload carrying only .py files shipped nothing to run and left
        # people with an older copy. That copy asked where tool.exe was even
        # when the kit sat in its own folder, so both halves are checked here:
        # it travels, and it looks beside itself before it asks.
        shipped_bat = entries.get("build-hek.bat")
        if not isinstance(shipped_bat, str) or "%OUT%tool.exe" not in shipped_bat:
            print("FAIL: the payload does not carry the build-hek.bat that finds "
                  "a kit beside itself")
            return 1
        if 'tool.exe model "%BUILD%\\fp"' not in shipped_bat:
            print("FAIL: the payload's build-hek.bat does not compile the "
                  "fp arms model - H1's first person hands has nothing to use")
            return 1

        sys.path.insert(0, work)
        import avatar_mesh
        import extract_items

        avatar_mesh.strb_blocks = lambda data: [
            (3, 1, 0, b"model-payload"),
            (2, 1, 0, texture_block()),
            (7, 1, 0, colour_block()),
        ]
        avatar_mesh.decompress = lambda body: body
        avatar_mesh.read_model = lambda data: batches()

        item = os.path.join(work, "UNSC Marine Armor.bin")
        with open(item, "wb") as handle:
            handle.write(b"STRB" + b"\0" * 60)

        out = os.path.join(work, "extracted")
        code = extract_items.main(["--root", work, "--obj", "--out", out])
        if code not in (0, None):
            print("FAIL: extractor returned %r" % (code,))
            return 1

        missing = [name for name in EXPECTED if not os.path.exists(os.path.join(out, name))]
        for name in EXPECTED:
            mark = "ok  " if os.path.exists(os.path.join(out, name)) else "MISS"
            print("  %s %s" % (mark, name))
        if missing:
            print("\nFAIL: %d of %d expected files missing" % (len(missing), len(EXPECTED)))
            return 1

        with open(os.path.join(out, "colour_00.png"), "rb") as handle:
            head = handle.read(24)
        if head[:8] != b"\x89PNG\r\n\x1a\n":
            print("\nFAIL: colour_00.png is not a PNG")
            return 1
        width, height = struct.unpack(">II", head[16:24])
        if width <= 0 or height <= 0:
            print("\nFAIL: colour_00.png has no size")
            return 1

        print("\nPASS: %d files, colour card %dx%d" % (len(EXPECTED), width, height))

        # Second case: the shape a retail item actually has - blocks 8, 3, 4, 4,
        # with no texture block and no colour block. The base map is in the
        # model block's own texture table, which is where the item declares it.
        avatar_mesh.strb_blocks = lambda data: [
            (8, 1, 0, b"\x0f" * 15),
            (3, 1, 0, b"model-payload"),
            (4, 1, 0, b"\x00" * 906),
            (4, 1, 0, b"\x00" * 3460),
        ]

        def dxt5_block(rgb):
            """One DXT5 block: alpha 255 everywhere, one solid colour."""
            red, green, blue = rgb
            value = ((red >> 3) << 11) | ((green >> 2) << 5) | (blue >> 3)
            return bytes([255, 255, 0, 0, 0, 0, 0, 0]) + struct.pack("<HHI", value, 0, 0)

        def with_table():
            out = batches()
            out[0]["textures"] = [
                {
                    "format": 0x14, "width": 16, "height": 16, "frames": 1,
                    "per_frame": 256, "empty": False, "endian": 0,
                    "data": bytes([0xFF, 0xFF, 0xE0, 0x07, 0, 0, 0, 0]) * 16 + b"\0" * 128,
                },
                # The item's own decal map: red and blue blocks, so it holds a
                # picture rather than one flat value.
                {
                    "format": 0x14, "width": 16, "height": 16, "frames": 1,
                    "per_frame": 256, "empty": False, "endian": 0,
                    "data": (dxt5_block((255, 0, 0)) + dxt5_block((0, 0, 255))) * 8,
                },
                # A declared tint slot that holds one value in every channel.
                {
                    "format": 0x14, "width": 16, "height": 16, "frames": 1,
                    "per_frame": 256, "empty": False, "endian": 0,
                    "data": dxt5_block((128, 128, 128)) * 16,
                },
            ]
            out[0]["materials"] = [
                {"kind": "texture", "id": 1, "texture": 0, "uv_set": 0, "mode": 0},
                {"kind": "texture", "id": 3, "texture": 1, "uv_set": 1, "mode": 0},
                {"kind": "texture", "id": 2, "texture": 2, "uv_set": 1, "mode": 0},
            ]
            return out

        avatar_mesh.read_model = lambda data: with_table()
        inbox = os.path.join(work, "retail")
        os.makedirs(inbox, exist_ok=True)
        with open(os.path.join(inbox, "Model Table Item.bin"), "wb") as handle:
            handle.write(b"STRB" + b"\0" * 60)
        out2 = os.path.join(work, "retail-out")
        code = extract_items.main(["--root", inbox, "--obj", "--out", out2])
        if code not in (0, None):
            print("FAIL: the retail-shape extractor returned %r" % (code,))
            return 1

        maps = ["extracted for max users/Model Table Item base map.png",
                "extracted for max users/Model Table Item base map.tga",
                "extracted for hek users/pc/data/Model Table Item/bitmaps/Model Table Item base map.tif",
                "extracted for hek users/xbox/data/Model Table Item/bitmaps/Model Table Item base map.tif"]
        for name in maps:
            path = os.path.join(out2, name)
            mark = "ok  " if os.path.exists(path) else "MISS"
            print("  %s %s" % (mark, name))
        missing = [name for name in maps if not os.path.exists(os.path.join(out2, name))]
        if missing:
            print("\nFAIL: the model's texture table produced no base map")
            return 1

        with open(os.path.join(out2, "report.txt"), encoding="utf-8") as handle:
            report = handle.read()
        if "its own base colour texture" not in report:
            print("\nFAIL: report.txt does not say where the base map came from")
            print(report)
            return 1

        # The other slots the table declares are textures the item binds, and
        # they are what the masks are read out of - so they are written as they
        # are, in their own colours, rather than only used and thrown away.
        slot_file = os.path.join(out2, "extracted for max users",
                                 "Model Table Item decal map.png")
        print("  %s decal map.png"
              % ("ok  " if os.path.exists(slot_file) else "MISS"))
        if not os.path.exists(slot_file):
            print("\nFAIL: the item's own decal slot was not written")
            return 1
        if first_pixel(slot_file) != (255, 0, 0, 255):
            print("\nFAIL: the slot texture is %r, not the red it holds"
                  % (first_pixel(slot_file),))
            return 1
        for name in ("pc", "xbox"):
            tif = os.path.join(out2, "extracted for hek users", name, "data",
                               "Model Table Item", "bitmaps",
                               "Model Table Item decal map.tif")
            if not os.path.exists(tif):
                print("\nFAIL: the slot .tif is missing from the %s bitmaps" % name)
                return 1
        if os.path.exists(os.path.join(out2, "extracted for max users",
                                       "Model Table Item slot 2 tint mask.png")):
            print("\nFAIL: a blank texture slot was written as another black image")
            return 1
        if "slot 2:    16x16 tint mask - blank" not in report:
            print("\nFAIL: report.txt does not say which slot was blank")
            return 1

        print("\nPASS: a texture-table-only item writes its base map and its own"
              " slots, and names a blank one instead of drawing it")

        # An item whose table declares slots and leaves every one of them empty,
        # while the container carries the texture in a block of its own. Reading
        # that as "no base map" was wrong: an empty slot says the table is empty,
        # not that the item has no texture.
        avatar_mesh.strb_blocks = lambda data: [
            (2, 1, 0, texture_block()),
            (3, 1, 0, b"model-payload"),
        ]

        def with_empty_slots():
            out = batches()
            out[0]["textures"] = [{
                "format": 0x14, "width": 16, "height": 16, "frames": 1,
                "per_frame": 0, "empty": True, "endian": 0, "data": b"",
            }]
            return out

        avatar_mesh.read_model = lambda data: with_empty_slots()
        inbox_empty = os.path.join(work, "empty-slots")
        os.makedirs(inbox_empty, exist_ok=True)
        with open(os.path.join(inbox_empty, "Armor Slots.bin"), "wb") as handle:
            handle.write(b"STRB" + b"\0" * 60)
        out_empty = os.path.join(work, "empty-slots-out")
        code = extract_items.main(["--root", inbox_empty, "--obj", "--out", out_empty])
        if code not in (0, None):
            print("FAIL: the empty-slot extractor returned %r" % (code,))
            return 1
        fallback = os.path.join(out_empty, "extracted for max users",
                                "Armor Slots base map.png")
        print("  %s Armor Slots base map.png, from the item's texture block"
              % ("ok  " if os.path.exists(fallback) else "MISS"))
        if not os.path.exists(fallback):
            print("\nFAIL: an item with empty slots and a texture block got no base map")
            return 1
        with open(os.path.join(out_empty, "report.txt"), encoding="utf-8") as handle:
            report_empty = handle.read()
        if "from block 2" not in report_empty:
            print("\nFAIL: the report does not say the base map came from block 2")
            return 1

        print("\nPASS: an all-empty texture table still finds the block's base map")

        # Third case: no texture and no colour table - the shape of every garment.
        # The item's own colour must still arrive as a real image in all three
        # formats, because that image is what Max, Blender and Halo CE bind: a
        # colour that lives only in Kd is dropped on import.
        avatar_mesh.strb_blocks = lambda data: [(3, 1, 0, b"model-payload")]
        avatar_mesh.read_model = lambda data: batches()
        inbox3 = os.path.join(work, "plain")
        os.makedirs(inbox3, exist_ok=True)
        with open(os.path.join(inbox3, "Plain Tee.bin"), "wb") as handle:
            handle.write(b"STRB" + b"\0" * 60)
        out3 = os.path.join(work, "plain-out")
        # This item states no tint mask, so its faithful mask is empty. The
        # channel packing is exercised by authoring one: --tint full.
        extract_items.TINT_MODE = "full"
        try:
            code = extract_items.main(["--root", inbox3, "--obj", "--out", out3])
        finally:
            extract_items.TINT_MODE = "item"
        if code not in (0, None):
            print("FAIL: the no-texture extractor returned %r" % (code,))
            return 1

        flat = ["extracted for max users/Plain Tee colour.png", "extracted for max users/Plain Tee colour.tga",
                "extracted for blender users/Plain Tee colour.png",
                "extracted for hek users/pc/data/Plain Tee/bitmaps/Plain Tee colour.tif",
                "extracted for hek users/xbox/data/Plain Tee/bitmaps/Plain Tee colour.tif"]
        for name in flat:
            mark = "ok  " if os.path.exists(os.path.join(out3, name)) else "MISS"
            print("  %s %s" % (mark, name))
        missing = [name for name in flat if not os.path.exists(os.path.join(out3, name))]
        if missing:
            print("\nFAIL: an item with no texture wrote no colour image")
            return 1

        with open(os.path.join(out3, "extracted for max users", "Plain Tee.mtl"), encoding="utf-8") as handle:
            mtl = handle.read()
        if "map_Kd Plain Tee colour.png" not in mtl:
            print("\nFAIL: the .mtl does not bind the colour image")
            print(mtl)
            return 1

        with open(os.path.join(out3, "extracted for hek users", "pc", "data",
                              "Plain Tee", "bitmaps",
                              "Plain Tee colour.tif"), "rb") as handle:
            head = handle.read(4)
        if head not in (b"II*\0", b"MM\0*"):
            print("\nFAIL: the colour .tif is not a TIFF")
            return 1

        with open(os.path.join(out3, "report.txt"), encoding="utf-8") as handle:
            report3 = handle.read()
        if "its colour is written as Plain Tee colour.png/.tga/.tif" not in report3:
            print("\nFAIL: report.txt does not say where the colour image is")
            print(report3)
            return 1

        print("\nPASS: an item with no texture still writes its colour as .png/.tga/.tif")

        # Fourth case (masks): the team-colour path is the whole point of these
        # files, so the channels are checked, not just the names. Halo CE and the
        # HEK read Gearbox order - red detail, green self-illumination, blue
        # specular, alpha colour change. The original Xbox and H1A read Xbox
        # order when the shader's og-xbox flag (0x40) is set - red specular,
        # green self-illumination, blue colour change, alpha detail. The two
        # orders differ in exactly two channels, so a set that was copied
        # instead of reordered passes a name check and still renders wrong.
        for suffix in ("multipurpose",):
            stem_set = "Plain Tee " + suffix
            for folder, ext in homes_for(suffix, "Plain Tee"):
                name = "%s.%s" % (stem_set, ext)
                path = os.path.join(out3, *folder.split("/"), name)
                found = os.path.exists(path)
                print("  %s %s/%s" % ("ok  " if found else "MISS", folder, name))
                if not found:
                    print("\nFAIL: %s is missing from %s" % (name, folder))
                    return 1

        def mask(suffix):
            return pixels(os.path.join(out3, "extracted for max users",
                                       "Plain Tee %s.png" % suffix))

        ce = mask("multipurpose")
        change = mask("change colour")
        # The mask is painted from the item's own UV layout, so it has to follow
        # that island: a blanket fill would pass a channel check and still not
        # line up with the base map the shader samples beside it.
        coverage = [p[3] for p in ce]
        covered = sum(1 for value in coverage if value) / float(len(coverage))
        print("  multipurpose    -> %d texels, %.1f%% lit, alpha values %r"
              % (len(ce), covered * 100, sorted(set(coverage))))
        # Every mask is written at the base map's own size, texel for texel. This
        # item carries no base map, so it takes the 256 fallback.
        if len(ce) != 256 * 256:
            print("\nFAIL: the mask is %d texels, expected the base map's 256x256"
                  % (len(ce),))
            return 1
        if sorted(set(coverage)) != [0, 255]:
            print("\nFAIL: the team-colour mask is not a two-value island mask")
            return 1
        if not 0.01 <= covered <= 0.75:
            print("\nFAIL: the mask covers %.1f%% of the canvas" % (covered * 100))
            return 1
        # A mask that only lives in alpha looks like an empty black file in every
        # viewer that ignores alpha, which is how a working mask got read as a
        # broken one. The .png and .tga show it in colour as well as in its
        # channel; the .tif is what tool.exe compiles, so it keeps the channel
        # alone and must still be checked texel for texel.
        if ([p[0] for p in ce] != coverage or [p[1] for p in ce] != coverage
                or [p[2] for p in ce] != coverage):
            print("\nFAIL: the Halo CE .png does not show its mask in colour")
            return 1
        if ([p[3] for p in change] != coverage
                or [p[0] for p in change] != coverage):
            print("\nFAIL: change colour does not show its mask")
            return 1

        def hek_tif(suffix, build="pc"):
            return tiff(os.path.join(out3, "extracted for hek users", build, "data",
                                     "Plain Tee", "bitmaps",
                                     "Plain Tee %s.tif" % suffix))

        ce_tif = hek_tif("multipurpose")
        if any(p[0] or p[1] or p[2] for p in ce_tif):
            print("\nFAIL: the .tif lights something other than the colour change")
            return 1
        if not any(p[3] for p in ce_tif):
            print("\nFAIL: the .tif carries no colour change in alpha")
            return 1
        if any(p[3] for p in ce_tif) != any(value for value in coverage):
            print("\nFAIL: the .tif and the .png disagree about the mask")
            return 1
        change_tif = hek_tif("change colour")
        if [p[0] for p in change_tif] != [p[3] for p in change_tif]:
            print("\nFAIL: change colour .tif does not show its mask")
            return 1

        # An item's team colour comes from its tint mask, read as the avatar
        # reads it: lerp(base, red*C1 + green*C2 + blue*C3, alpha). Alpha is the
        # amount; red, green and blue are which of the player's three colours.
        # A flat alpha means the item marked whole regions by colour instead.
        import extract_items as masks
        tint = {"width": 2, "height": 1,
                "rgba": bytes([255, 0, 0, 255, 0, 0, 0, 0])}
        print("  tint channel   -> %r" % (masks.tint_channel(tint),))
        if masks.tint_channel(tint) != 3:
            print("\nFAIL: a tint mask with an alpha is not read from alpha")
            return 1
        got = masks.mask_from_texture(tint, 2, 3)
        print("  tint amount    -> %r" % (got,))
        if got != bytes([255, 0, 255, 0]):
            print("\nFAIL: a tint mask's amount is not read from its alpha")
            return 1
        weighted = {"width": 2, "height": 1,
                    "rgba": bytes([0, 255, 0, 255, 0, 0, 0, 255])}
        print("  weight channel -> %r, amounts %r"
              % (masks.tint_channel(weighted), masks.tint_amount(weighted, 2)))
        if (masks.tint_channel(weighted) != 0
                or masks.tint_amount(weighted, 2) != bytes([255, 0, 255, 0])):
            print("\nFAIL: a flat-alpha tint mask is not read from its colours")
            return 1

        # With no tint mask, the painted texture's own islands are the coverage:
        # transparent or black is not part of the item, anything else is.
        picture = {"width": 2, "height": 1,
                   "rgba": bytes([0, 0, 0, 0, 10, 10, 10, 255])}
        covered = masks.mask_from_coverage(picture, 2)
        print("  texture islands-> %r" % (covered,))
        if covered != bytes([0, 255, 0, 255]):
            print("\nFAIL: a painted texture is not read as islands")
            return 1

        for folder, ext in homes_for("change colour", "Plain Tee"):
            name = "Plain Tee change colour.%s" % ext
            path = os.path.join(out3, *folder.split("/"), name)
            found = os.path.exists(path)
            print("  %s %s/%s" % ("ok  " if found else "MISS", folder, name))
            if not found:
                print("\nFAIL: %s is missing from %s" % (name, folder))
                return 1

        with open(os.path.join(out3, "catalogue.json"), encoding="utf-8") as handle:
            catalogue_text = handle.read()
        for key in ("multipurpose", "change_colour"):
            if ('"%s"' % key) not in catalogue_text:
                print("\nFAIL: catalogue.json does not record %s" % key)
                return 1

        with open(os.path.join(out3, "report.txt"), encoding="utf-8") as handle:
            report_masks = handle.read()
        for phrase in ("multipurpose.png/.tga/.tif",
                       "alpha colour change"):
            if phrase not in report_masks:
                print("\nFAIL: report.txt does not say %r" % phrase)
                return 1

        print("\nPASS: one team-colour mask, worked out from the item's own paint,"
              " in both channel orders")

        # Fifth case (where a team colour may come from): an item states one
        # through its tint mask and nothing else. The Marine armour's tint slot is
        # a blank 32x32 while the decal beside it carries an alpha blend over two
        # thirds of its canvas; reading that alpha as a mask is how most of the
        # suit came out tinted on no evidence. A blank tint mask means the item
        # states no team colour: the multiplayer map is the whole item, the
        # single-player map is zero, and the decal's alpha leaks into neither.
        def dxt5_alpha(alpha, rgb):
            """One DXT5 block: one alpha value and one solid colour."""
            red, green, blue = rgb
            value = ((red >> 3) << 11) | ((green >> 2) << 5) | (blue >> 3)
            return bytes([alpha, alpha, 0, 0, 0, 0, 0, 0]) + struct.pack("<HHI", value, 0, 0)

        def tint_trap():
            out = batches()
            out[0]["textures"] = [
                {   # base colour
                    "format": 0x14, "width": 16, "height": 16, "frames": 1,
                    "per_frame": 256, "empty": False, "endian": 0,
                    "data": dxt5_block((200, 200, 200)) * 16,
                },
                {   # the tint slot: declared, and blank like the Marine's
                    "format": 0x14, "width": 16, "height": 16, "frames": 1,
                    "per_frame": 256, "empty": False, "endian": 0,
                    "data": b"\0" * 256,
                },
                {   # the decal: red, half of it fully opaque
                    "format": 0x14, "width": 16, "height": 16, "frames": 1,
                    "per_frame": 256, "empty": False, "endian": 0,
                    "data": (dxt5_alpha(255, (255, 0, 0)) * 8
                             + dxt5_alpha(0, (255, 0, 0)) * 8),
                },
            ]
            out[0]["materials"] = [
                {"kind": "texture", "id": 1, "texture": 0, "uv_set": 0, "mode": 0},
                {"kind": "texture", "id": 2, "texture": 1, "uv_set": 1, "mode": 0},
                {"kind": "texture", "id": 3, "texture": 2, "uv_set": 2, "mode": 0},
            ]
            return out

        avatar_mesh.strb_blocks = lambda data: [(3, 1, 0, b"model-payload")]
        avatar_mesh.read_model = lambda data: tint_trap()
        inbox_tint = os.path.join(work, "tint-trap")
        os.makedirs(inbox_tint, exist_ok=True)
        with open(os.path.join(inbox_tint, "Tint Trap.bin"), "wb") as handle:
            handle.write(b"STRB" + b"\0" * 60)
        out_tint = os.path.join(work, "tint-trap-out")
        code = extract_items.main(["--root", inbox_tint, "--obj", "--out", out_tint])
        if code not in (0, None):
            print("FAIL: the tint-trap extractor returned %r" % (code,))
            return 1
        # The tint slot is a decoy - a 32x32 with one texel set - and the item
        # carries no colour table, so it states no colour change at all. The
        # faithful mask is empty: the decal's half-lit alpha must not be read as
        # one, and nothing is invented to fill the gap, and the report says so.
        for suffix in ("multipurpose", "change colour"):
            path = os.path.join(out_tint, "extracted for max users",
                                "Tint Trap %s.png" % suffix)
            texels = pixels(path)
            lit = sum(1 for pixel in texels if any(pixel))
            print("  %-16s %d of %d texels lit" % (suffix, lit, len(texels)))
            if lit:
                print("\nFAIL: %s lights %d texels - the item states no colour"
                      " change, so nothing may tint" % (suffix, lit))
                return 1
        with open(os.path.join(out_tint, "report.txt"), encoding="utf-8") as handle:
            report_tint = handle.read()
        if "states no colour change" not in report_tint:
            print("\nFAIL: report.txt does not say the item states no colour change")
            return 1
        if "mask coverage: none - nothing takes the team colour" not in report_tint:
            print("\nFAIL: report.txt does not say the faithful mask is empty")
            return 1

        # --tint full authors a mask the item does not have: every texel its base
        # map paints takes the colour. The report must say it was authored.
        out_full = os.path.join(work, "tint-full-out")
        extract_items.TINT_MODE = "full"
        try:
            code = extract_items.main(["--root", inbox_tint, "--obj", "--out", out_full])
        finally:
            extract_items.TINT_MODE = "item"
        if code not in (0, None):
            print("FAIL: the --tint full extractor returned %r" % (code,))
            return 1
        full = pixels(os.path.join(out_full, "extracted for max users",
                                   "Tint Trap change colour.png"))
        lit_full = sum(1 for pixel in full if any(pixel))
        print("  --tint full       %d of %d texels lit" % (lit_full, len(full)))
        if lit_full != len(full):
            print("\nFAIL: %d of %d texels are lit under --tint full"
                  % (lit_full, len(full)))
            return 1
        with open(os.path.join(out_full, "report.txt"), encoding="utf-8") as handle:
            if "authored (--tint full)" not in handle.read():
                print("\nFAIL: report.txt does not say the mask was authored")
                return 1

        # --tint derived authors the armour/cloth rule, and lands the amounts the
        # function itself is pinned to.
        out_derived = os.path.join(work, "tint-derived-out")
        extract_items.TINT_MODE = "derived"
        try:
            code = extract_items.main(["--root", inbox_tint, "--obj", "--out", out_derived])
        finally:
            extract_items.TINT_MODE = "item"
        if code not in (0, None):
            print("FAIL: the --tint derived extractor returned %r" % (code,))
            return 1
        derived_mask = pixels(os.path.join(out_derived, "extracted for max users",
                                           "Tint Trap change colour.png"))
        amounts = sorted({pixel[3] for pixel in derived_mask})
        print("  --tint derived    %d distinct amounts, %d..%d"
              % (len(amounts), amounts[0], amounts[-1]))
        # This fixture has no shaded base map to grade (its UVs cover the whole
        # canvas), so the grading itself is pinned by the derived_amount checks
        # below; here it only has to produce a mask rather than an empty one.
        if not amounts or amounts[-1] == 0:
            print("\nFAIL: --tint derived produced an empty mask (amounts %r)"
                  % (amounts[:6],))
            return 1
        with open(os.path.join(out_derived, "report.txt"), encoding="utf-8") as handle:
            if "authored (--tint derived)" not in handle.read():
                print("\nFAIL: report.txt does not say the derived mask was authored")
                return 1

        # --detail derived writes a detail map and paints the multipurpose map's
        # RED channel with the mask that shows it: Guerilla's "detail mask" slot
        # is red in Halo PC/CE whatever the label says, and a detail map with
        # nothing in red is invisible. The team-colour copy of the base map is
        # checked here too, because CE MULTIPLIES the base map by the change
        # colour, so the team colour only reads clean where the map is white.
        out_detail = os.path.join(work, "detail-out")
        extract_items.TINT_MODE = "derived"
        extract_items.DETAIL_MODE = "derived"
        try:
            code = extract_items.main(["--root", inbox_tint, "--obj", "--out", out_detail])
        finally:
            extract_items.TINT_MODE = "item"
            extract_items.DETAIL_MODE = None
        if code not in (0, None):
            print("FAIL: the --detail derived extractor returned %r" % (code,))
            return 1
        detail_users = os.path.join(out_detail, "extracted for max users")
        detail_texels = pixels(os.path.join(detail_users, "Tint Trap detail.png"))
        grey = sum(1 for pixel in detail_texels if pixel[0] == pixel[1] == pixel[2])
        print("  --detail derived  %d of %d detail texels are grey"
              % (grey, len(detail_texels)))
        if grey != len(detail_texels):
            print("\nFAIL: the derived detail map is not grey")
            return 1
        packed = pixels(os.path.join(detail_users, "Tint Trap multipurpose.png"))
        # The mask follows the base map's size, so a texel of it sits on the
        # texel of the map it masks. The two are written from different code
        # paths and were 1024 and 256 regardless of the map before this.
        base_map_pixels = pixels(os.path.join(detail_users,
                                              "Tint Trap base map.png"))
        print("  mask size         %d texels against the base map's %d"
              % (len(packed), len(base_map_pixels)))
        if len(packed) != len(base_map_pixels):
            print("\nFAIL: the multipurpose map is %d texels and the base map %d"
                  % (len(packed), len(base_map_pixels)))
            return 1
        red = sum(1 for pixel in packed if pixel[0])
        alpha = sum(1 for pixel in packed if pixel[3])
        print("  multipurpose      red (detail mask) %d, alpha (colour change) %d"
              % (red, alpha))
        if not red:
            print("\nFAIL: the multipurpose map has no red - detail would be"
                  " invisible however the shader is set")
            return 1
        if not alpha:
            print("\nFAIL: the multipurpose map lost its colour change")
            return 1
        team_path = os.path.join(detail_users, "Tint Trap base map (team colour).png")
        if not os.path.exists(team_path):
            print("\nFAIL: no team-colour base map was written")
            return 1
        team = pixels(team_path)
        white = sum(1 for pixel in team if pixel[:3] == (255, 255, 255))
        print("  team colour       %d of %d texels taken to white"
              % (white, len(team)))
        if not white:
            print("\nFAIL: the team-colour base map was not whitened")
            return 1
        with open(os.path.join(out_detail, "report.txt"), encoding="utf-8") as handle:
            report_detail = handle.read()
        for wanted in ("detail:", "mask = multipurpose map alpha", "team colour:"):
            if wanted not in report_detail:
                print("\nFAIL: report.txt does not mention %r" % wanted)
                return 1

        # Halo's armour shines and has lights; the blue and green channels are
        # where shader_model reads those two masks, so a derived specular mask
        # and an authored glow mask must land there and nowhere else.
        glow_png = os.path.join(work, "glow.png")
        extract_items.write_png(glow_png,
                                bytes((255, 255, 255, 255)) * 64, 8, 8)
        # Authored masks here: the derived specular rule is pinned by its own
        # unit test against plate and cloth colours, and this fixture's base map
        # is bright paint that the rule rightly leaves matte.
        shine_png = os.path.join(work, "shine.png")
        extract_items.write_png(shine_png,
                                bytes((255, 255, 255, 255)) * 64, 8, 8)
        out_shine = os.path.join(work, "shine-out")
        extract_items.TINT_MODE = "derived"
        extract_items.SHINE_MODE = shine_png
        extract_items.GLOW_MASK = glow_png
        try:
            code = extract_items.main(["--root", inbox_tint, "--obj", "--out", out_shine])
        finally:
            extract_items.TINT_MODE = "item"
            extract_items.SHINE_MODE = None
            extract_items.GLOW_MASK = None
        if code not in (0, None):
            print("FAIL: the --shine/--glow extractor returned %r" % (code,))
            return 1
        shine_users = os.path.join(out_shine, "extracted for max users")
        packed_shine = pixels(os.path.join(shine_users, "Tint Trap multipurpose.png"))
        blue = sum(1 for pixel in packed_shine if pixel[2])
        green = sum(1 for pixel in packed_shine if pixel[1])
        print("  shine + glow      blue (specular) %d, green (self-illum) %d"
              % (blue, green))
        if not blue:
            print("\nFAIL: the specular mask did not reach the blue channel")
            return 1
        if not green:
            print("\nFAIL: the glow mask did not reach the green channel")
            return 1
        with open(os.path.join(out_shine, "report.txt"), encoding="utf-8") as handle:
            report_shine = handle.read()
        for wanted in ("specular:", "glow:", "BLUE channel", "GREEN channel"):
            if wanted not in report_shine:
                print("\nFAIL: report.txt does not mention %r" % wanted)
                return 1

        # Two base maps side by side: the item's own, and a copy with its decal
        # blended in - decal.rgb by its own alpha, the rule both readers of the
        # format use. The plain map must carry none of the decal, and the blend
        # must keep the texels the decal does not cover.
        max_users = os.path.join(out_tint, "extracted for max users")
        base = pixels(os.path.join(max_users, "Tint Trap base map.png"))
        composite_path = os.path.join(max_users, "Tint Trap base map + decal.png")
        if not os.path.exists(composite_path):
            print("\nFAIL: no decal-blended base map was written")
            return 1
        composite = pixels(composite_path)
        if len(composite) != len(base):
            print("\nFAIL: the decal-blended base map is a different size")
            return 1
        leaked = sum(1 for pixel in base if pixel[:3] == (255, 0, 0))
        red = sum(1 for pixel in composite if pixel[:3] == (255, 0, 0))
        kept = sum(1 for before, after in zip(base, composite)
                   if before[:3] == after[:3])
        lazy = sum(1 for pixel in composite if pixel[3] != 255)
        print("  base maps      plain: %d texels of the decal's red; blended:"
              " %d red, %d left exactly as the item's own, of %d"
              % (leaked, red, kept, len(composite)))
        if leaked:
            print("\nFAIL: the decal was blended into the item's own base map")
            return 1
        if not red or not kept or lazy:
            print("\nFAIL: the decal blend either ignored its alpha or its"
                  " colour, or wrote a transparent texel")
            return 1
        blended, changed = extract_items.decal_overlay(
            bytes([200, 200, 200, 255]) * 3, 3, 1,
            bytes([255, 0, 0, 0, 255, 0, 0, 255, 255, 0, 0, 128]), 3)
        got = [tuple(blended[i:i + 3]) for i in (0, 4, 8)]
        print("  blend maths    alpha 0, 255, 128 -> %r" % (got,))
        if got != [(200, 200, 200), (255, 0, 0), (228, 100, 100)]:
            print("\nFAIL: the decal blend is not base*(1-a) + decal.rgb*a")
            return 1
        with open(os.path.join(out_tint, "report.txt"), encoding="utf-8") as handle:
            report_decal = handle.read()
        if ("base map + decal" not in report_decal
                or "decal:     material id 3 (table slot 2)" not in report_decal):
            print("\nFAIL: report.txt does not describe the decal blend")
            return 1
        # Both maps and the decal's own slot reach each channel order's bitmaps
        # folder, which is the folder tool.exe compiles: the suit can be built
        # with its decal or without it, and the decal is there as artwork too.
        for order in ("pc", "xbox"):
            bitmaps = os.path.join(out_tint, "extracted for hek users", order,
                                   "data", "Tint Trap", "bitmaps")
            for name in ("Tint Trap base map.tif",
                         "Tint Trap base map + decal.tif",
                         "Tint Trap decal map.tif"):
                path = os.path.join(bitmaps, name)
                if not os.path.exists(path) or os.path.getsize(path) == 0:
                    print("\nFAIL: the %s bitmaps are missing %s"
                          % (order, name))
                    return 1

        # A derived amount: the item states no tint mask, so the multiplayer
        # build's amount comes from the base map's own shading - dark armour
        # takes the team colour, warm cloth takes a share. A whole-white mask
        # recoloured the tan suit as hard as the plates, and luminance alone did
        # the same: the suit is stored at (123, 109, 88), which is not bright.
        # So the two cases that pin it are the measured cloth and a *light
        # neutral* texel, which has to stay armour-full.
        def solid(rgb, size=4):
            return {"width": size, "height": size,
                    "rgba": bytes(list(rgb) + [255]) * (size * size)}

        dark = extract_items.derived_amount(solid((40, 50, 30)), 4)
        cloth = extract_items.derived_amount(solid((123, 109, 88)), 4)
        grey = extract_items.derived_amount(solid((180, 180, 180)), 4)
        middle = extract_items.derived_amount(solid((150, 145, 130)), 4)
        print("  derived amount armour %r tan cloth %r light grey %r between %r"
              % (dark[0], cloth[0], grey[0], middle[0]))
        if not (dark[0] == 255 and cloth[0] == 82 and grey[0] == 255
                and 82 < middle[0] < 255):
            print("\nFAIL: the derived team-colour amount is not armour-full,"
                  " cloth-a-share (the tan cloth reads as plate, or a light grey"
                  " reads as cloth)")
            return 1

        print("\nPASS: a blank tint slot and no colour table give an empty mask"
              " (nothing tints), --tint full and --tint derived author one and"
              " say so, and the decal is blended onto a copy of the base map,"
              " with the plain map and the decal's own slot beside it")

        # Fourth case: two parts in one item, each with its own colour, and the
        # same shader id on both. They must stay two materials with two colours -
        # naming by shader id merged them, and a hardcoded Kd made every part grey.
        avatar_mesh.strb_blocks = lambda data: [(3, 1, 0, b"model-payload")]
        avatar_mesh.read_model = lambda data: two_parts()
        inbox4 = os.path.join(work, "parts")
        os.makedirs(inbox4, exist_ok=True)
        with open(os.path.join(inbox4, "Suit.bin"), "wb") as handle:
            handle.write(b"STRB" + b"\0" * 60)
        out4 = os.path.join(work, "parts-out")
        code = extract_items.main(["--root", inbox4, "--obj", "--out", out4])
        if code not in (0, None):
            print("FAIL: the multi-part extractor returned %r" % (code,))
            return 1

        with open(os.path.join(out4, "extracted for max users", "Suit.mtl"), encoding="utf-8") as handle:
            mtl4 = handle.read()
        names = [line for line in mtl4.splitlines() if line.startswith("newmtl ")]
        kd = [line for line in mtl4.splitlines() if line.startswith("Kd ")]
        maps = [line for line in mtl4.splitlines() if line.startswith("map_Kd ")]
        print("  materials: %d, distinct Kd: %d, maps: %d"
              % (len(names), len(set(kd)), len(maps)))
        for line in kd + maps:
            print("    %s" % line)

        if len(names) != 2:
            print("FAIL: two parts became %d materials" % len(names))
            return 1
        if len(set(kd)) != 2:
            print("FAIL: the two parts share one Kd - per-part colour was lost")
            return 1
        if len(maps) != 2:
            print("FAIL: the two parts do not each have their own image")
            return 1
        for line in maps:
            image = line.split(" ", 1)[1].strip()
            if not os.path.exists(os.path.join(out4, "extracted for max users", image)):
                print("FAIL: %s is named by the .mtl but was not written" % image)
                return 1

        print("\nPASS: two parts keep two colours, two materials and two images")

        # Fifth case: the one-click shape. The .bat passes --root <its own folder>
        # and nothing else, so items are found by walking the folders under it:
        # each item arrives in a folder named after its container, holding
        # asset.bin or asset_v2.bin. Those file names are the format, not the
        # item, and the folder's GUID is the container's name, not the item's:
        # neither may name the output. Two untitled items are extracted1 and
        # extracted2, in the order they are found - one name each, so they
        # cannot overwrite each other.
        avatar_mesh.strb_blocks = lambda data: [(3, 1, 0, b"model-payload")]
        avatar_mesh.read_model = lambda data: batches()
        oneclick = os.path.join(work, "oneclick")
        containers = ["00000000-0000-0000-0000-0000000000a1",
                      "00000000-0000-0000-0000-0000000000b2"]
        for name in containers:
            folder = os.path.join(oneclick, name)
            os.makedirs(folder, exist_ok=True)
            for filename in ("asset_v2.bin", "asset.bin"):
                with open(os.path.join(folder, filename), "wb") as handle:
                    handle.write(b"STRB" + b"\0" * 60)
        out5 = os.path.join(oneclick, "extracted")
        code = extract_items.main(["--root", oneclick, "--obj", "--out", out5])
        if code not in (0, None):
            print("FAIL: the one-click shape returned %r" % (code,))
            return 1

        wanted = ("extracted for max users/%s.obj", "extracted for max users/%s.mtl", "%s_colours.txt",
                  "extracted for max users/%s multipurpose.png",
                  "extracted for max users/%s change colour.png",
                  "extracted for blender users/%s multipurpose.tga",
                  "extracted for hek users/pc/data/%s/bitmaps/%s multipurpose.tif",
                  "extracted for hek users/xbox/data/%s/bitmaps/%s multipurpose.tif",
                  "extracted for hek users/xbox/data/%s/bitmaps/%s change colour.tif")
        # Folders are walked in order, so the two untitled items are named in
        # the order they appear: a1 first, then b2.
        for name in ("extracted", "extracted 2"):
            for pattern in wanted:
                want = pattern % tuple([name] * pattern.count("%s"))
                found = os.path.exists(os.path.join(out5, want))
                print("  %s %s" % ("ok  " if found else "MISS", want))
                if not found:
                    print("\nFAIL: %s was not written from its container folder"
                          % want)
                    return 1

        with open(os.path.join(out5, "catalogue.json"), encoding="utf-8") as handle:
            catalogue5 = json.load(handle)
        entries5 = catalogue5.get("items") or []
        ids5 = [entry.get("id") for entry in entries5]
        print("  catalogue ids: %r" % (ids5,))
        if sorted(ids5) != sorted(containers):
            print("\nFAIL: catalogue ids are %r, expected the container names %r"
                  % (ids5, containers))
            return 1

        print("\nPASS: each container folder names its item, and two do not collide")

        # Sixth case: bins with no container name to borrow. Users can give the
        # bins on their own - asset.bin / asset_v2.bin in a folder that says
        # nothing about the item - so the name has to come from somewhere: the
        # fallback is extracted1, extracted2, ... numbered across the run so two
        # items never end up sharing a name.
        binfolders = os.path.join(work, "bins")
        # A non-GUID folder name is not the container's name, so it does not name
        # the item either - otherwise one folder called "Closet Stuff" would give
        # every item inside it the same name. A GUID folder in the same run shows
        # the numbering only counts the items that need it.
        named = "00000000-0000-0000-0000-0000000000c3"
        for name in ("Loose A", "Loose B", named):
            folder = os.path.join(binfolders, name)
            os.makedirs(folder, exist_ok=True)
            with open(os.path.join(folder, "asset_v2.bin"), "wb") as handle:
                handle.write(b"STRB" + b"\0" * 60)
        out6 = os.path.join(binfolders, "extracted")
        code = extract_items.main(["--root", binfolders, "--obj", "--out", out6])
        if code not in (0, None):
            print("FAIL: the bins-only extractor returned %r" % (code,))
            return 1

        fallback = ("extracted1", "extracted2")
        for name in fallback:
            for pattern in ("extracted for max users/%s.obj", "extracted for max users/%s.mtl", "extracted for max users/%s multipurpose.png",
                            "extracted for max users/%s change colour.tga",
                            "extracted for hek users/pc/data/%s/bitmaps/%s multipurpose.tif"):
                want = pattern % tuple([name] * pattern.count("%s"))
                found = os.path.exists(os.path.join(out6, want))
                print("  %s %s" % ("ok  " if found else "MISS", want))
                if not found:
                    print("\nFAIL: %s was not written for a nameless bin" % want)
                    return 1

        with open(os.path.join(out6, "catalogue.json"), encoding="utf-8") as handle:
            ids6 = [entry.get("id") for entry in json.load(handle).get("items") or []]
        print("  catalogue ids: %r" % (ids6,))
        expected6 = sorted(list(fallback) + [named])
        if sorted(ids6) != expected6:
            print("\nFAIL: the run got %r, expected %r"
                  % (sorted(ids6), expected6))
            return 1
        if os.path.exists(os.path.join(out6, "extracted for max users", "extracted3.obj")):
            print("\nFAIL: the fallback numbering counted the GUID item")
            return 1
        for name in fallback:
            if os.path.exists(os.path.join(out6, "extracted for max users", name + " asset_v2.obj")):
                print("\nFAIL: an item is still named after its bin file")
                return 1

        # The HEK tree is named once, by the item's own stem: data\<stem>\ with
        # bitmaps, models and animations inside it. Naming the bitmap folders
        # from the item's id instead left a second data\<GUID>\ folder beside
        # the named one - the rigging pass names its folders by the stem - so
        # one item arrived split across two folders, one called after a hex id.
        guid = "00000FFC39723261C09A3B1E4D530877"
        split = os.path.join(work, "split")
        os.makedirs(split)
        with open(os.path.join(split, guid + ".bin"), "wb") as handle:
            handle.write(b"STRB" + b"\0" * 60)
        real_title = extract_items.item_title
        extract_items.item_title = lambda name, path, item_id: ("UNSC Armor", "test")
        try:
            out7 = os.path.join(work, "split-out")
            code = extract_items.main(["--root", split, "--obj", "--out", out7])
        finally:
            extract_items.item_title = real_title
        if code not in (0, None):
            print("FAIL: the titled run returned %r" % (code,))
            return 1
        # A single item's output folder is renamed to its title, so look there.
        folder = os.path.join(work, "UNSC Armor")
        if not os.path.isdir(folder):
            folder = out7
        data7 = os.path.join(folder, "extracted for hek users", "xbox", "data")
        folders = sorted(os.listdir(data7)) if os.path.isdir(data7) else []
        print("  hek data folders   -> %r" % (folders,))
        if folders != ["UNSC Armor"]:
            print("\nFAIL: one item's HEK tree is %r, expected one folder named"
                  " after it" % (folders,))
            return 1
        for kind in ("bitmaps", "models", "animations"):
            if not os.path.isdir(os.path.join(data7, "UNSC Armor", kind)):
                print("\nFAIL: data\\UNSC Armor\\%s was not made" % kind)
                return 1

        print("\nPASS: nameless bins come out as extracted1, extracted2; the GUID keeps its name")
        print("Not covered: the rigging half (.fbx, .glb, .blend, .jms, the")
        print("report's scene section) needs Blender and cannot run here.")
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
