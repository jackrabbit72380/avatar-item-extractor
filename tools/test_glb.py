#!/usr/bin/env python3
"""Pin the .glb reader: what it takes off an avatar, and what it refuses.

An avatar exported by 360sona carries the game's own body, head and hands, and
the item again in a re-packed atlas that Halo cannot compile. So the reader has
to do three separate things exactly:

  * read a glTF 2.0 binary the way the exporter writes one - accessors, embedded
    PNGs, materials, joints - and refuse anything it has no reader for,
  * leave out the meshes named after the item, because the container already
    gives the item's own geometry, UVs and masks,
  * hand back an image as raw RGBA and as a TIFF the bitmap compiler takes, with
    no Pillow anywhere, because the rig pass runs inside Blender.

A synthetic avatar is built here, so the whole test runs without Blender and
without any file on the machine. When a real export is beside the repository it
is read too, and the counts it must have are checked.

    python3 tools/test_glb.py
"""

import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(HERE)
MODULES = os.environ.get("RIG_MODULES") or os.path.join(
    os.path.dirname(HERE), "src")
sys.path.insert(0, MODULES)

import glb_model                                                # noqa: E402
from extract_items import tiff_bytes                            # noqa: E402

FAILURES = []


def check(label, condition, detail=""):
    if condition:
        print("  ok    %s%s" % (label, detail and (" - " + detail) or ""))
    else:
        print("  FAIL  %s%s" % (label, detail and (" - " + detail) or ""))
        FAILURES.append(label)


# ---------------------------------------------------------------- a real PNG

def png_bytes(width, height, rows, filt=0):
    """A PNG the way an exporter writes one, filtering the rows as asked.

    Each row's filter is applied by hand so the decoder is tested against real
    Sub and Up rows, not only against the unfiltered case it would pass by
    accident.
    """
    def chunk(kind, body):
        return (struct.pack(">I", len(body)) + kind + body
                + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF))

    raw = bytearray()
    previous = bytes(width * 4)
    for row in rows:
        if row and isinstance(row[0], (tuple, list)):
            row = bytes(channel for pixel in row for channel in pixel)
        row = bytes(row)
        encoded = bytearray(row)
        if filt == 1:      # Sub
            for at in range(len(row)):
                encoded[at] = (row[at] - (row[at - 4] if at >= 4 else 0)) & 0xFF
        elif filt == 2:    # Up
            for at in range(len(row)):
                encoded[at] = (row[at] - previous[at]) & 0xFF
        raw += bytes([filt]) + bytes(encoded)
        previous = row
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(bytes(raw))) + chunk(b"IEND", b""))


def sample_rows(width, height, seed=0):
    """Rows of distinct colours, so a wrong pixel is visible as a wrong pixel."""
    return [[((x * 7 + y * 11 + seed) & 0xFF, (x * 3) & 0xFF,
              (y * 5) & 0xFF, 255) for x in range(width)]
            for y in range(height)]


# ---------------------------------------------------------------- a real GLB

def build_glb(meshes, images=(), joints=()):
    """A glTF 2.0 binary holding the meshes, images and joint names given."""
    buffer = bytearray()
    views = []
    accessors = []

    def add_view(blob, target=None):
        offset = len(buffer)
        data = bytes(blob)
        buffer.extend(data)
        buffer.extend(b"\x00" * ((4 - len(buffer) % 4) % 4))
        entry = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target is not None:
            entry["target"] = target
        views.append(entry)
        return len(views) - 1

    def add_accessor(values, kind, component):
        code = {5121: "B", 5123: "H", 5126: "f"}[component]
        parts = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[kind]
        if kind == "SCALAR":
            flat = [component for value in values
                    for component in (value if isinstance(value, (tuple, list))
                                      else (value,))]
            blob = b"".join(struct.pack("<" + code, int(value))
                            for value in flat)
            count = len(flat)
        else:
            blob = b"".join(struct.pack("<" + code * parts, *value)
                            for value in values)
            count = len(values)
        views_at = add_view(blob)
        accessors.append({"bufferView": views_at, "componentType": component,
                          "count": count, "type": kind})
        return len(accessors) - 1

    names = []
    for mesh in meshes:
        if mesh.get("material") is not None and mesh["material"] not in names:
            names.append(mesh["material"])
    documents = []
    for mesh in meshes:
        attributes = {"POSITION": add_accessor(mesh["positions"], "VEC3", 5126)}
        if mesh.get("uvs"):
            attributes["TEXCOORD_0"] = add_accessor(mesh["uvs"], "VEC2", 5126)
        primitive = {
            "attributes": attributes,
            "indices": add_accessor(mesh["triangles"], "SCALAR", 5123),
            "mode": 4,
        }
        if mesh.get("material") is not None:
            primitive["material"] = names.index(mesh["material"])
        documents.append({"name": mesh["name"], "primitives": [primitive]})

    image_entries = []
    for index, blob in enumerate(images):
        image_entries.append({"bufferView": add_view(blob),
                              "mimeType": "image/png",
                              "name": "image%d" % index})

    materials = []
    textures = []
    for name in names:
        mesh = next(entry for entry in meshes if entry.get("material") == name)
        materials.append({"name": name,
                          "pbrMetallicRoughness": {"baseColorTexture":
                                                   {"index": len(textures)}}})
        textures.append({"source": mesh["image"]})

    nodes = [{"name": name} for name in joints]
    nodes.append({"name": "Hips skin", "children": []})
    document = {
        "asset": {"version": "2.0", "generator": "360sona"},
        "buffers": [{"byteLength": len(buffer)}],
        "bufferViews": views,
        "accessors": accessors,
        "meshes": documents,
        "materials": materials,
        "textures": textures,
        "images": image_entries,
        "nodes": nodes,
        "skins": [{"joints": list(range(len(joints)))}] if joints else [],
    }
    import json
    payload = json.dumps(document).encode("utf-8")
    payload += b" " * ((4 - len(payload) % 4) % 4)
    binary = bytes(buffer)
    binary += b"\x00" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(payload) + 8 + len(binary)
    return (b"glTF" + struct.pack("<II", 2, total)
            + struct.pack("<II", len(payload), glb_model.CHUNK_JSON) + payload
            + struct.pack("<II", len(binary), glb_model.CHUNK_BIN) + binary)


def avatar():
    """A body, a head and an item's own copy, laid out like a real export."""
    return [
        {"name": "body", "material": "body_0", "image": 0,
         "positions": [(0.0, 0.0, 0.0), (0.02, 0.0, 0.0), (0.0, 0.05, 0.01)],
         "uvs": [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)],
         "triangles": [(0, 1, 2)]},
        {"name": "head", "material": "face", "image": 1,
         "positions": [(0.0, 1.1, 0.0), (0.1, 1.1, 0.0), (0.0, 1.4, 0.1)],
         "uvs": [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)],
         "triangles": [(0, 1, 2)]},
        {"name": "hair: Test Item", "material": "hair: Test Item_5", "image": 2,
         "positions": [(0.0, 0.0, 0.0), (0.7, 0.0, 0.0), (0.0, 1.5, 0.2)],
         "uvs": [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)],
         "triangles": [(0, 1, 2), (0, 2, 1)]},
    ]


def main():
    import tempfile
    work = tempfile.mkdtemp(prefix="avatar-glb-")
    image = png_bytes(4, 2, sample_rows(4, 2))
    path = os.path.join(work, "avatar.glb")
    with open(path, "wb") as handle:
        handle.write(build_glb(avatar(), images=[image, image, image],
                               joints=["Hips", "Spine", "Head"]))

    # ------------------------------------------------------------ the read
    print("reading a synthetic avatar")
    model = glb_model.read(path)
    check("three meshes read", len(model["meshes"]) == 3,
          "%d" % len(model["meshes"]))
    check("generator kept", model["generator"] == "360sona", model["generator"])
    check("joint names kept", model["joints"] == ["Hips", "Spine", "Head"],
          ", ".join(model["joints"]))
    check("three images read", len(model["images"]) == 3)
    body = model["meshes"][0]
    check("positions are floats as stored",
          all(isinstance(value, float) for point in body["positions"]
              for value in point))
    check("uvs kept", len(body["uvs"]) == 3 and body["uvs"][1] == (1.0, 0.0),
          str(body["uvs"][1]))
    check("triangles kept", body["triangles"] == [(0, 1, 2)],
          str(body["triangles"]))
    # 0.0 == 0, so the values alone would pass a float reader; a mesh builder
    # will not, and Blender refuses one built from floats.
    check("triangle indices are integers",
          all(isinstance(index, int) and not isinstance(index, bool)
              for face in body["triangles"] for index in face),
          repr([type(index).__name__ for index in body["triangles"][0]]))
    check("material and image linked",
          body["material"] == "body_0" and body["image"] == 0,
          "%s -> image %s" % (body["material"], body["image"]))
    check("image bytes are the file's own PNG",
          model["images"][0]["data"] == image)

    # --------------------------------------------------------- the choosing
    print("choosing what to take off it")
    kept, skipped = glb_model.choose(model, "Test Item")
    check("the item's own copy is left out", len(skipped) == 1,
          ", ".join(mesh["name"] for mesh in skipped))
    check("body and head are kept",
          [mesh["name"] for mesh in kept] == ["body", "head"],
          ", ".join(mesh["name"] for mesh in kept))
    check("its triangles go with it",
          sum(len(mesh["triangles"]) for mesh in skipped) == 2)
    kept, skipped = glb_model.choose(model, "Something Else")
    check("an item the file does not name keeps every mesh",
          len(kept) == 3 and not skipped)
    kept, _ = glb_model.choose(model, "Test Item", also_skip=["head"])
    check("a name named by the caller is left out too",
          [mesh["name"] for mesh in kept] == ["body"],
          ", ".join(mesh["name"] for mesh in kept))
    check("the name rule ignores case and spacing",
          len(glb_model.choose(model, "test-item")[1]) == 1,
          str(len(glb_model.choose(model, "test-item")[1])))

    # A 360sona export can name the item's own copy after the slot it fills
    # rather than after the item: the UNSC Marine Armor comes back as a mesh
    # called plain "hair". The name test cannot see that, so the pipeline
    # measured the armour's copy as if it were the body's hair, kept it, and
    # joined the armour onto a second copy of the armour - two shells in one
    # place. The caller's box for the item is what recognises it.
    print("the item's copy under a slot's name")
    twin = [
        {"name": "body", "material": "body_0", "image": 0,
         "positions": [(0.0, 0.0, 0.0), (0.02, 0.0, 0.0), (0.0, 0.05, 0.01)],
         "uvs": [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)], "triangles": [(0, 1, 2)]},
        {"name": "hair", "material": "hair_6", "image": 2,
         "positions": [(0.0, 0.0, 0.0), (0.7, 0.0, 0.0), (0.0, 1.5, 0.2)],
         "uvs": [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)],
         "triangles": [(0, 1, 2), (0, 2, 1)]},
    ]
    twin_path = os.path.join(work, "twin.glb")
    with open(twin_path, "wb") as handle:
        handle.write(build_glb(twin, images=[image, image, image], joints=[]))
    twin_model = glb_model.read(twin_path)
    kept, skipped = glb_model.choose(twin_model, "UNSC Marine Armor")
    check("a slot's name alone does not see the copy", len(kept) == 2 and not skipped,
          ", ".join(mesh["name"] for mesh in skipped) or "nothing skipped")
    item_box = glb_model.mesh_box(twin_model["meshes"][1])
    kept, skipped = glb_model.choose(twin_model, "UNSC Marine Armor",
                                     item_box=item_box)
    check("the item's own box leaves the copy out",
          [mesh["name"] for mesh in kept] == ["body"]
          and [mesh["name"] for mesh in skipped] == ["hair"],
          "kept %s, skipped %s"
          % (", ".join(mesh["name"] for mesh in kept),
             ", ".join(mesh["name"] for mesh in skipped)))
    kept, skipped = glb_model.choose(twin_model, "UNSC Marine Armor",
                                     item_box=([0.0, 0.0, 0.0], [0.7, 1.2, 0.2]))
    check("a box one body is not keeps every mesh", len(kept) == 2 and not skipped)

    # ----------------------------------------------------------- the images
    print("turning an embedded PNG into pixels")
    for filt in (0, 1, 2):
        blob = png_bytes(4, 2, sample_rows(4, 2, seed=filt), filt=filt)
        rgba, width, height = glb_model.decode_png(blob)
        wanted = bytes(channel for row in sample_rows(4, 2, seed=filt)
                       for pixel in row for channel in pixel)
        check("filter %d decodes to the pixels it was made from" % filt,
              (width, height) == (4, 2) and rgba == wanted)

    print("writing the bitmap tool.exe compiles")
    rgba, width, height = glb_model.decode_png(image)
    tiff = tiff_bytes(rgba, width, height)
    tags, pixels = read_tiff(tiff)
    check("little-endian TIFF", tiff[:4] == b"II*\x00")
    check("size in the directory", tags.get(256) == (width,)
          and tags.get(257) == (height,), "%s" % (tags.get(256, None),))
    check("8 bits a channel, four samples",
          tags.get(258) == (8, 8, 8, 8) and tags.get(277) == (4,))
    check("uncompressed and chunky",
          tags.get(259) == (1,) and tags.get(284) == (1,))
    check("one strip holding every pixel",
          tags.get(279) == (width * height * 4,))
    check("the strip is the image", pixels == rgba)
    check("power of two, as a bitmap must be",
          glb_model.power_of_two(512) and glb_model.power_of_two(256)
          and not glb_model.power_of_two(1004)
          and not glb_model.power_of_two(912))

    # -------------------------------------------------------------- refuses
    print("refusing what it cannot read")
    for label, blob in (
            ("a file that is not a .glb", b"PK\x03\x04 not a model"),
            ("a header longer than the file",
             b"glTF" + struct.pack("<II", 2, 999) + b"\x00" * 8),
            ("a glTF 1 file", b"glTF" + struct.pack("<II", 1, 12))):
        try:
            with open(os.path.join(work, "bad.glb"), "wb") as handle:
                handle.write(blob)
            glb_model.read(os.path.join(work, "bad.glb"))
            check(label, False, "read it anyway")
        except glb_model.GlbError as problem:
            check(label, True, str(problem)[:44])

    # --------------------------------------------------------- a real export
    real = os.path.join(ROOT_DIR, "MyAvatar.glb")
    if os.path.exists(real):
        print("the real export beside the repository")
        model = glb_model.read(real)
        kept, skipped = glb_model.choose(model, "UNSC Marine Armor")
        counts = sorted(len(mesh["triangles"]) for mesh in kept)
        # The head arrives as two primitives - one index set each side of the
        # face, sharing one vertex buffer and one material - so 423 twice.
        check("head and neck are kept, 880 triangles",
              counts == [34, 423, 423] and sum(counts) == 880, str(counts))
        check("the armour's own copy is left out",
              [len(mesh["triangles"]) for mesh in skipped] == [4876])
        check("71 joints", len(model["joints"]) == 71, str(len(model["joints"])))
        check("three images", len(model["images"]) == 3)
        face = [mesh for mesh in kept if mesh["material"] == "face"][0]
        rgba, width, height = glb_model.decode_png(
            model["images"][face["image"]]["data"])
        check("the face decodes at 512x512x4",
              (width, height, len(rgba)) == (512, 512, 512 * 512 * 4),
              "%dx%d" % (width, height))
    else:
        print("no MyAvatar.glb beside the repository: the synthetic avatar is "
              "the whole test")

    print("")
    # A face sheet from the site leaves flat grey where it painted nothing, and
    # 41% of the pieces of a head read that grey, so the face shows blank
    # patches. Filling grows the painted skin into the hole, so no texel the
    # head samples is left unpainted.
    skin = (196, 148, 108, 255)
    grey = (128, 128, 128, 255)
    sheet = bytearray(bytes(skin) * 2 + bytes(grey) * 3)
    filled_pixels, filled = glb_model.fill_unpainted(sheet, 5, 1)
    check("three empty texels filled", filled == 3, str(filled))
    check("the hole takes the colour beside it",
          filled_pixels[-4:] == bytes(skin), str(tuple(filled_pixels[-4:])))
    _, none = glb_model.fill_unpainted(bytearray(bytes(skin) * 4), 4, 1)
    check("a painted sheet is left alone", none == 0, str(none))
    # A face sheet also carries paint that is not skin: a pupil, a lash, a brow,
    # a lip. The fill is for the flat grey only - growing skin over the paint is
    # what left the eyes as pale almonds with no pupils in them.
    pupil = (40, 30, 28, 255)
    mixed = bytearray(bytes(skin) + bytes(grey) + bytes(pupil) + bytes(grey))
    kept, count = glb_model.fill_unpainted(mixed, 4, 1)
    check("a pupil is not painted over", kept[8:12] == bytes(pupil),
          str(tuple(kept[8:12])))
    check("the hole beside it still fills", count == 1, str(count))

    if FAILURES:
        print("FAILED: %d check(s)" % len(FAILURES))
        for label in FAILURES:
            print("  %s" % label)
        return 1
    print("PASSED: glb reader, choosing, png and tiff")
    return 0


def read_tiff(data):
    """Read back what ``tiff_bytes`` wrote: tag directory and pixel strip."""
    if data[:4] != b"II*\x00":
        return {}, b""
    at = struct.unpack_from("<I", data, 4)[0]
    count = struct.unpack_from("<H", data, at)[0]
    tags = {}
    for index in range(count):
        spot = at + 2 + index * 12
        tag, kind, size = struct.unpack_from("<HHI", data, spot)
        code = "H" if kind == 3 else "I"
        width = 2 if kind == 3 else 4
        slot = data[spot + 8:spot + 12]
        if size * width <= 4:
            values = struct.unpack_from("<" + code * size, slot)
        else:
            offset = struct.unpack_from("<I", slot)[0]
            values = struct.unpack_from("<" + code * size, data, offset)
        tags[tag] = values
    strip = tags.get(273, (0,))[0]
    return tags, data[strip:strip + tags.get(279, (0,))[0]]


if __name__ == "__main__":
    raise SystemExit(main())
