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
import os
import shutil
import struct
import sys
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
BAT = os.path.join(os.path.dirname(HERE), "Extract-AvatarItem-v20.bat")

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
    "extracted for hek users/pc/data/UNSC Marine Armor base map.tif",
    "extracted for hek users/xbox/data/UNSC Marine Armor base map.tif",
    "UNSC Marine Armor_colours.txt",
    "colour_00.png",
    "catalogue.json",
)

# Which folder each mask set belongs in, per the user it is for.
MASK_HOMES = {
    "multipurpose": ("extracted for max users", "extracted for blender users", "extracted for hek users/pc/data"),
    "multipurpose xbox": ("extracted for max users", "extracted for blender users", "extracted for hek users/xbox/data"),
    "multipurpose sp": ("extracted for max users", "extracted for blender users", "extracted for hek users/pc/data", "extracted for hek users/xbox/data"),
    "change colour": ("extracted for max users", "extracted for blender users", "extracted for hek users/pc/data", "extracted for hek users/xbox/data"),
}


def homes_for(family):
    """(folder, extension) for every copy of one bitmap family."""
    wanted = []
    for folder in MASK_HOMES[family]:
        if folder.startswith("extracted for hek users"):
            wanted.append((folder, "tif"))
        else:
            wanted.extend([(folder, "png"), (folder, "tga")])
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
    return [{
        "shader_id": 1,
        "vertices": [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)],
        "uvs": [[(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)]],
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
            "uvs": [[(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)]],
            "materials": [{"kind": "vector", "id": 22, "value": colour + [1.0]}],
            "joints": [(0, 0, 0, 0)] * 3,
            "weights": [(1.0, 0.0, 0.0, 0.0)] * 3,
            "colours": [0, 0, 0],
            "indices": [0, 1, 2],
        })
    return parts


def first_pixel(path):
    """The RGBA of a PNG's top-left pixel, without a decoder library."""
    with open(path, "rb") as handle:
        raw = handle.read()
    name = os.path.basename(path)
    if raw[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("%s is not a PNG" % name)
    pos, idat = 8, b""
    while pos + 8 <= len(raw):
        size = struct.unpack_from(">I", raw, pos)[0]
        tag = raw[pos + 4:pos + 8]
        if tag == b"IHDR":
            depth, colour = raw[pos + 16], raw[pos + 17]
            if (depth, colour) != (8, 6):
                raise ValueError("%s is %d-bit type %d, not 8-bit RGBA"
                                 % (name, depth, colour))
        elif tag == b"IDAT":
            idat += raw[pos + 8:pos + 8 + size]
        pos += 12 + size
    rows = zlib.decompress(idat)
    if rows[0] != 0:
        raise ValueError("%s starts with filter %d" % (name, rows[0]))
    return struct.unpack(">BBBB", rows[1:5])


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

        def with_table():
            out = batches()
            out[0]["textures"] = [{
                "format": 0x14, "width": 16, "height": 16, "frames": 1,
                "per_frame": 256, "empty": False, "endian": 0,
                "data": bytes([0xFF, 0xFF, 0xE0, 0x07, 0, 0, 0, 0]) * 16 + b"\0" * 128,
            }]
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
                "extracted for hek users/pc/data/Model Table Item base map.tif",
                "extracted for hek users/xbox/data/Model Table Item base map.tif"]
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
        if "the model's own texture table" not in report:
            print("\nFAIL: report.txt does not say where the base map came from")
            print(report)
            return 1

        print("\nPASS: a texture-table-only item writes its base map in three formats")

        # Third case: no texture and no colour table - the shape of every garment.
        # The item's own colour must still arrive as a real image in all three
        # formats, because that image is what Max, Blender and Halo CE bind: a
        # colour that lives only in Kd is dropped on import.
        avatar_mesh.read_model = lambda data: batches()
        inbox3 = os.path.join(work, "plain")
        os.makedirs(inbox3, exist_ok=True)
        with open(os.path.join(inbox3, "Plain Tee.bin"), "wb") as handle:
            handle.write(b"STRB" + b"\0" * 60)
        out3 = os.path.join(work, "plain-out")
        code = extract_items.main(["--root", inbox3, "--obj", "--out", out3])
        if code not in (0, None):
            print("FAIL: the no-texture extractor returned %r" % (code,))
            return 1

        flat = ["extracted for max users/Plain Tee colour.png", "extracted for max users/Plain Tee colour.tga",
                "extracted for blender users/Plain Tee colour.png",
                "extracted for hek users/pc/data/Plain Tee colour.tif",
                "extracted for hek users/xbox/data/Plain Tee colour.tif"]
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
        mask_sets = [
            ("multipurpose", (0, 0, 0, 255),
             "Halo CE: colour change in alpha, specular in blue"),
            ("multipurpose xbox", (0, 0, 255, 0),
             "Xbox: colour change moved to blue, detail in alpha"),
            ("multipurpose sp", (0, 0, 0, 0),
             "single player: nothing masked, valid in either order"),
        ]
        for suffix, expected, meaning in mask_sets:
            stem_set = "Plain Tee " + suffix
            for folder, ext in homes_for(suffix):
                name = "%s.%s" % (stem_set, ext)
                path = os.path.join(out3, *folder.split("/"), name)
                found = os.path.exists(path)
                print("  %s %s/%s" % ("ok  " if found else "MISS", folder, name))
                if not found:
                    print("\nFAIL: %s is missing from %s" % (name, folder))
                    return 1
            got = first_pixel(os.path.join(out3, "extracted for max users", stem_set + ".png"))
            print("    %s first pixel %s - %s" % (suffix, got, meaning))
            if got != expected:
                print("\nFAIL: %s carries %s, expected %s (%s)"
                      % (suffix, got, expected, meaning))
                return 1

        for folder, ext in homes_for("change colour"):
            name = "Plain Tee change colour.%s" % ext
            path = os.path.join(out3, *folder.split("/"), name)
            found = os.path.exists(path)
            print("  %s %s/%s" % ("ok  " if found else "MISS", folder, name))
            if not found:
                print("\nFAIL: %s is missing from %s" % (name, folder))
                return 1

        with open(os.path.join(out3, "catalogue.json"), encoding="utf-8") as handle:
            catalogue_text = handle.read()
        for key in ("multipurpose", "multipurpose_xbox", "multipurpose_sp",
                    "change_colour"):
            if ('"%s"' % key) not in catalogue_text:
                print("\nFAIL: catalogue.json does not record %s" % key)
                return 1

        with open(os.path.join(out3, "report.txt"), encoding="utf-8") as handle:
            report_masks = handle.read()
        for phrase in ("multipurpose xbox.png/.tga/.tif",
                       "multipurpose sp.png/.tga/.tif",
                       "alpha colour change"):
            if phrase not in report_masks:
                print("\nFAIL: report.txt does not say %r" % phrase)
                return 1

        print("\nPASS: three mask sets in both channel orders, sp masks nothing")

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
        # item, so the folder must name the output - naming by the file left two
        # items in one run both called "asset_v2", overwriting each other.
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
                  "extracted for max users/%s multipurpose.png", "extracted for max users/%s multipurpose xbox.png",
                  "extracted for max users/%s multipurpose sp.tga", "extracted for max users/%s change colour.png",
                  "extracted for blender users/%s multipurpose.tga",
                  "extracted for hek users/pc/data/%s multipurpose.tif",
                  "extracted for hek users/xbox/data/%s multipurpose xbox.tif",
                  "extracted for hek users/xbox/data/%s change colour.tif")
        for name in containers:
            for pattern in wanted:
                want = pattern % name
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
                            "extracted for max users/%s multipurpose xbox.png",
                            "extracted for max users/%s change colour.tga",
                            "extracted for hek users/pc/data/%s multipurpose sp.tif",
                            "extracted for hek users/pc/data/%s multipurpose.tif"):
                want = pattern % name
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

        print("\nPASS: nameless bins come out as extracted1, extracted2; the GUID keeps its name")
        print("Not covered: the rigging half (.fbx, .glb, .blend, .jms, scene.json,")
        print("skeleton.json) needs Blender and cannot run here.")
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
