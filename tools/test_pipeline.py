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
import os
import shutil
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
BAT = os.path.join(os.path.dirname(HERE), "Extract-AvatarItem-v20.bat")

EXPECTED = (
    "UNSC Marine Armor.obj",
    "UNSC Marine Armor.mtl",
    "UNSC Marine Armor base map.png",
    "UNSC Marine Armor base map.tga",
    "UNSC Marine Armor base map.tif",
    "UNSC Marine Armor_colours.txt",
    "colour_00.png",
    "catalogue.json",
)


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
        print("Not covered: the rigging half (.fbx, .glb, .blend, .jms, report.txt,")
        print("scene.json, skeleton.json) needs Blender and cannot run here.")
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
