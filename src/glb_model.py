"""Read a 360sona ``.glb``: the avatar's own body and head, for the rig pass.

An avatar item is a garment on somebody's body. The item file says nothing about
the body it is worn on, so the body has to come from somewhere: an avatar
exported by 360sona carries the game's own body, head and hands, already posed on
the avatar skeleton and cut down to the parts the item does not cover.

That export also carries the item's own geometry again, re-textured into its own
atlas. That copy is not used: extraction already reads the item from its
container, where every vertex, UV set, mask and decal is the item's own data, and
the export's atlas is a re-pack that cannot become a Halo bitmap anyway (1004 by
912 is not a power of two). So a port keeps the body and head and drops the
meshes named after the item.

Nothing here imports ``bpy``. The reading, the choosing, the PNG decoding and
the TIFF writing are plain Python, so ``tools/test_glb.py`` can pin all of it
without Blender - and the rig pass builds Blender meshes out of what this
returns.

Layout read here is glTF 2.0:

    header      magic "glTF", version 2, total length
    chunk       JSON, then the binary buffer the accessors index into

Only what a 360sona export uses is supported, and anything else is refused with a
sentence rather than a traceback: triangles only, embedded images only, no Draco,
no sparse accessors, no 16-bit or interlaced PNG.
"""

import json
import os
import struct
import zlib
from collections import deque

FORMAT_VERSION = 2
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942
MODE_TRIANGLES = 4

# glTF component types, as the struct code and size each one is read with.
COMPONENTS = {
    5120: ("b", 1),   # BYTE
    5121: ("B", 1),   # UNSIGNED_BYTE
    5122: ("h", 2),   # SHORT
    5123: ("H", 2),   # UNSIGNED_SHORT
    5125: ("I", 4),   # UNSIGNED_INT
    5126: ("f", 4),   # FLOAT
}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


class GlbError(Exception):
    """A file this reader will not guess at."""


# ------------------------------------------------------------------ the file

def _chunks(data):
    """The JSON and binary chunks of a .glb, checked against its own header."""
    if len(data) < 12 or data[:4] != b"glTF":
        raise GlbError("not a .glb: the file does not start with glTF")
    version, length = struct.unpack_from("<II", data, 4)
    if version != FORMAT_VERSION:
        raise GlbError("glTF version %d: this reader is for version %d"
                       % (version, FORMAT_VERSION))
    if length != len(data):
        raise GlbError("the header says %d bytes, the file is %d"
                       % (length, len(data)))
    at = 12
    found = {}
    while at + 8 <= len(data):
        size, kind = struct.unpack_from("<II", data, at)
        body = data[at + 8:at + 8 + size]
        if len(body) != size:
            raise GlbError("a chunk ends %d bytes past the file"
                           % (size - len(body)))
        found[kind] = body
        at += 8 + size
    if CHUNK_JSON not in found:
        raise GlbError("no JSON chunk")
    return json.loads(found[CHUNK_JSON].decode("utf-8")), found.get(CHUNK_BIN, b"")


def _accessor(document, binary, index):
    """One accessor as a list of floats, one tuple a vertex."""
    where = "accessor %d" % index
    entry = document["accessors"][index]
    if "sparse" in entry:
        raise GlbError("%s is sparse, which this reader does not read" % where)
    width = WIDTHS.get(entry["type"])
    if width is None:
        raise GlbError("%s has type %s" % (where, entry["type"]))
    code, size = COMPONENTS.get(entry["componentType"], (None, None))
    if code is None:
        raise GlbError("%s has component type %d"
                       % (where, entry["componentType"]))
    count = entry["count"]
    if "bufferView" not in entry:
        return [tuple([0.0] * width) for _ in range(count)]
    view = document["bufferViews"][entry["bufferView"]]
    if view.get("byteStride") not in (None, width * size):
        # Interleaved data: the stride is honoured below rather than refused.
        pass
    start = view.get("byteOffset", 0) + entry.get("byteOffset", 0)
    stride = view.get("byteStride") or (width * size)
    if start + stride * (count - 1) + width * size > len(binary):
        raise GlbError("%s runs past the binary chunk" % where)
    scale = 1.0
    if entry.get("normalized") and entry["componentType"] in (5120, 5121, 5122, 5123):
        scale = 1.0 / (2 ** (8 * size - 1) - 1 if entry["componentType"] in (5120, 5122)
                       else 2 ** (8 * size) - 1)
    out = []
    for step in range(count):
        at = start + step * stride
        values = struct.unpack_from("<" + code * width, binary, at)
        out.append(tuple(value * scale for value in values))
    return out


def _indices(document, binary, primitive):
    if "indices" in primitive:
        flat = [value[0] for value in _accessor(document, binary,
                                                primitive["indices"])]
    else:  # no index buffer: vertices are used in order
        flat = list(range(document["accessors"][primitive["attributes"]["POSITION"]]["count"]))
    # Integers, not the floats every accessor is read as: a face is a set of
    # indices, and Blender refuses a mesh built from 0.0 rather than 0.
    return [(int(flat[at]), int(flat[at + 1]), int(flat[at + 2]))
            for at in range(0, len(flat) - 2, 3)]


def read(path):
    """A .glb as meshes, materials, images and joint names.

    Returns a dict::

        {"meshes": [{"name", "material", "image", "positions", "uvs", "triangles"}],
         "images": [{"name", "mime", "data"}],
         "joints": ["Hips", ...],
         "generator": "360sona"}

    ``image`` is an index into ``images``. Positions and UVs are as the file
    stores them: y-up metres, which is the space avatar items are authored in, so
    nothing needs converting before the head is placed under the item.
    """
    with open(path, "rb") as handle:
        data = handle.read()
    document, binary = _chunks(data)
    used = document.get("extensionsRequired") or []
    if used:
        raise GlbError("this file needs %s, which this reader does not have"
                       % ", ".join(used))

    images = []
    for entry in document.get("images") or []:
        if "bufferView" not in entry:
            raise GlbError("image %r is a link, not pixels"
                           % entry.get("uri", "?"))
        view = document["bufferViews"][entry["bufferView"]]
        start = view.get("byteOffset", 0)
        images.append({"name": os.path.basename(entry.get("name") or
                                                ("image%d" % len(images))),
                       "mime": entry.get("mimeType", "image/png"),
                       "data": binary[start:start + view["byteLength"]]})

    textures = document.get("textures") or []
    materials = document.get("materials") or []

    def material_of(primitive):
        """(name, image index or None) for a primitive's material."""
        if "material" not in primitive:
            return ("material", None)
        entry = materials[primitive["material"]]
        name = entry.get("name") or ("material%d" % primitive["material"])
        source = None
        texture = (entry.get("pbrMetallicRoughness") or {}).get("baseColorTexture")
        if texture is not None and texture.get("index") is not None:
            if texture["index"] < len(textures):
                source = textures[texture["index"]].get("source")
        return (name, source)

    meshes = []
    seen = set()
    broken = []
    for mesh in document.get("meshes") or []:
        for primitive in mesh.get("primitives") or []:
            if primitive.get("mode", MODE_TRIANGLES) != MODE_TRIANGLES:
                raise GlbError("%s is not drawn as triangles" % mesh.get("name"))
            if "POSITION" not in (primitive.get("attributes") or {}):
                raise GlbError("%s has no positions" % mesh.get("name"))
            positions = _accessor(document, binary,
                                  primitive["attributes"]["POSITION"])
            triangles = _indices(document, binary, primitive)
            # The same geometry twice, whatever accessors or material index it
            # was written under, draws twice. Two primitives that merely share a
            # vertex array do not: a 360sona head is written as two halves over
            # the same 648 vertices, 324 indices each and not one vertex shared,
            # and dropping either would cut the head in two.
            key = (tuple(tuple(round(value, 6) for value in point)
                         for point in positions),
                   tuple(tuple(triangle) for triangle in triangles))
            if key in seen:
                continue
            seen.add(key)
            uvs = (_accessor(document, binary, primitive["attributes"]["TEXCOORD_0"])
                   if "TEXCOORD_0" in primitive["attributes"] else [])
            name, image = material_of(primitive)
            if len(positions) >= 40 and len(triangles) * 10 < len(positions):
                # A body of 1137 vertices carrying 34 triangles is how a broken
                # export arrives; carried through silently it becomes a body a
                # few centimetres tall and a model scaled x4.578 into a giant.
                broken.append("%s: %d vertices but only %d triangles"
                              % (mesh.get("name"), len(positions),
                                 len(triangles)))
            meshes.append({
                "name": mesh.get("name") or ("mesh%d" % len(meshes)),
                "material": name,
                "image": image,
                "positions": positions,
                "uvs": uvs,
                "triangles": triangles,
            })

    joints = []
    for skin in document.get("skins") or []:
        for index in skin.get("joints") or []:
            node = (document.get("nodes") or [{}])[index]
            joints.append(node.get("name") or ("node%d" % index))
    return {"meshes": meshes, "images": images, "joints": joints,
            "broken": broken,
            "generator": (document.get("asset") or {}).get("generator", "")}


# ---------------------------------------------------------------- choosing

def flatten(name):
    """A name reduced to what two spellings of it share."""
    return " ".join((name or "").replace("_", " ").replace("-", " ").split()).lower()


def mesh_box(mesh):
    """(low, high) per axis over the vertices a mesh actually uses."""
    points = mesh.get("positions") or []
    if not points:
        return None
    low = [min(point[axis] for point in points) for axis in range(3)]
    high = [max(point[axis] for point in points) for axis in range(3)]
    return low, high


def box_sizes(box):
    """A box as its three extents, smallest first."""
    return sorted(box[1][axis] - box[0][axis] for axis in range(3))


def same_box(one, other, share=0.01):
    """Whether two boxes are the same size, within a hundredth of the larger.

    The item's copy in an export is the item's own geometry, so its extents are
    the item's extents to the millimetre. The three are compared smallest to
    smallest rather than axis by axis, because the two files are not guaranteed
    to be turned the same way round: an .obj comes into Blender through an
    importer that may carry a rotation on the object, and comparing x to x
    there would call the same suit two different things.

    The body under a suit is a different size on at least one extent - the
    armour is 1.51 m head to toe where the body in it stops at 1.17 m - so the
    body is not mistaken for the item.
    """
    mine, theirs = box_sizes(one), box_sizes(other)
    for a, b in zip(mine, theirs):
        if abs(a - b) > share * max(a, b, 1e-4) + 1e-3:
            return False
    return True


# What a full-body costume takes the place of. An export names each worn mesh
# after the slot it fills - ``hair``, ``glasses``, ``shirt`` - and the wardrobe's
# own record for a costume is the slot ``costume``, which is worn over the body
# instead of clothes. So the pieces below are left out under one, and anything
# else - glasses, a ring, a watch - stays: those sit on skin the costume does
# not cover, and a person should not have to undress their avatar to wear it.
REPLACED_BY_COSTUME = frozenset((
    "hair", "headwear", "shirt", "trousers", "shorts", "skirt", "dress",
    "coat", "jacket", "shoes", "socks", "boots", "gloves", "belt",
))
# A costume is the whole figure, so it takes the place of the body itself and not
# just its clothes. The body is NOT dropped when the export is read, though: it
# is what the fit measures the avatar against, and a head on its own measures
# 0.55 m and lands the model 2.5 m tall. It is cut away after the scale is
# settled - see cut_body in rig_items.
BODY_SLOT = "body"

# The slots that are worn on bare skin. They are named here so the costume test
# above can be read as the short list it is, and so a name nobody has thought
# about is kept rather than silently thrown away.
ACCESSORY_SLOTS = frozenset((
    "glasses", "ring", "wristwear", "earring", "earrings", "necklace",
))


def choose(model, stem, also_skip=(), item_box=None, costume=False):
    """The body meshes to keep, and the ones that are the item itself.

    One exporter names the item's own mesh after the item - ``hair: UNSC Marine
    Armor`` - and another names it after the slot it fills, so the armour comes
    back as plain ``hair``. A name test alone therefore misses it, and the item
    is joined onto a second copy of itself: two shells in the same place, which
    renders as a double image and fights itself in the game.

    So the item is recognised twice over. By name, as above, and by geometry
    when the caller passes ``item_box``: a mesh whose box is the item's box is
    the item. Anything the caller names in ``also_skip`` is dropped the same
    way.

    ``costume`` says the item is worn over the body rather than on one part of
    it. Then the clothes and the hair the export carries are the ones the
    costume replaces, and they are dropped with it; accessories stay.

    If the rules would leave nothing at all, every mesh is kept: a body with the
    item's copy still on it is visibly wrong, but an empty one is not fixable by
    looking at it.
    """
    wanted = flatten(stem)
    skips = {flatten(name) for name in also_skip if flatten(name)}
    kept, skipped = [], []
    for mesh in model["meshes"]:
        own = flatten(mesh["name"])
        box = mesh_box(mesh)
        if (wanted and wanted in own) or own in skips:
            skipped.append(mesh)
        elif item_box and box and same_box(box, item_box):
            skipped.append(mesh)
        elif costume and own in REPLACED_BY_COSTUME:
            skipped.append(mesh)
        else:
            kept.append(mesh)
    if not kept:
        return list(model["meshes"]), []
    return kept, skipped


# ------------------------------------------------------------------- images

def decode_png(data):
    """An 8-bit PNG as (rgba bytes, width, height).

    Eight bits a channel, not interlaced, grey/RGB/RGBA - which is every PNG a
    360sona export embeds. Anything else is refused by name, because a silently
    half-decoded texture is worse than a stopped run.
    """
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise GlbError("an image is not a PNG")
    at = 8
    header = None
    palette = None
    pixels = bytearray()
    while at + 8 <= len(data):
        size, kind = struct.unpack_from(">I4s", data, at)
        body = data[at + 8:at + 8 + size]
        at += 12 + size
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"PLTE":
            palette = body
        elif kind == b"IDAT":
            pixels += body
        elif kind == b"IEND":
            break
    if header is None:
        raise GlbError("a PNG has no header")
    width, height, depth, colour, _, _, interlace = header
    if depth != 8:
        raise GlbError("a %d-bit PNG; only 8-bit is read" % depth)
    if interlace:
        raise GlbError("an interlaced PNG")
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(colour)
    if channels is None:
        raise GlbError("a PNG in colour type %d" % colour)
    raw = zlib.decompress(bytes(pixels))
    stride = width * channels
    rows = []
    previous = bytearray(stride)
    at = 0
    for _ in range(height):
        if at >= len(raw):
            raise GlbError("a PNG ends before its last row")
        kind = raw[at]
        line = bytearray(raw[at + 1:at + 1 + stride])
        at += 1 + stride
        if kind == 1:      # Sub
            for index in range(channels, stride):
                line[index] = (line[index] + line[index - channels]) & 0xFF
        elif kind == 2:    # Up
            for index in range(stride):
                line[index] = (line[index] + previous[index]) & 0xFF
        elif kind == 3:    # Average
            for index in range(stride):
                left = line[index - channels] if index >= channels else 0
                line[index] = (line[index] + ((left + previous[index]) >> 1)) & 0xFF
        elif kind == 4:    # Paeth
            for index in range(stride):
                left = line[index - channels] if index >= channels else 0
                up = previous[index]
                corner = previous[index - channels] if index >= channels else 0
                guess = left + up - corner
                near = (abs(guess - left), abs(guess - up), abs(guess - corner))
                pick = (left, up, corner)[near.index(min(near))]
                line[index] = (line[index] + pick) & 0xFF
        elif kind != 0:
            raise GlbError("a PNG row uses filter %d" % kind)
        rows.append(line)
        previous = line
    rgba = bytearray(width * height * 4)
    for y, line in enumerate(rows):
        for x in range(width):
            spot = x * channels
            out = (y * width + x) * 4
            if colour == 6:
                rgba[out:out + 4] = line[spot:spot + 4]
            elif colour == 2:
                rgba[out] = line[spot]
                rgba[out + 1] = line[spot + 1]
                rgba[out + 2] = line[spot + 2]
                rgba[out + 3] = 255
            elif colour == 0:
                rgba[out] = rgba[out + 1] = rgba[out + 2] = line[spot]
                rgba[out + 3] = 255
            elif colour == 4:
                rgba[out] = rgba[out + 1] = rgba[out + 2] = line[spot]
                rgba[out + 3] = line[spot + 1]
            else:  # colour type 3, a palette
                if palette is None:
                    raise GlbError("a paletted PNG with no palette")
                entry = line[spot] * 3
                rgba[out] = palette[entry]
                rgba[out + 1] = palette[entry + 1]
                rgba[out + 2] = palette[entry + 2]
                rgba[out + 3] = 255
    return bytes(rgba), width, height


# The colour a 360sona face sheet leaves where it painted nothing: flat mid grey,
# the value a normal map is stored on. Measured on two exports, 41% and 53% of
# the pieces of head read it, and a face with it shows as blank patches - a white
# wedge over the brow, a grey cheek - which is what "half the head is missing"
# looked like. It is not missing geometry: the head is whole and its triangles
# land on the sheet; the sheet has holes in it.
UNPAINTED = 128


def fill_unpainted(rgba, width, height, value=UNPAINTED, tolerance=6):
    """Grow the painted pixels into the flat grey the exporter left, in place.

    Each grey texel takes the colour of the nearest painted one, which is how a
    hole in a painted sheet is filled without inventing anything: it is the skin
    round the hole spreading into it, so a brow keeps its brow's tone and a
    cheek its cheek's. Returns (pixels, number filled).

    Breadth-first from every painted texel at once, so the fill is by distance
    and not by passes over the image.
    """
    pixels = bytearray(rgba)
    total = width * height
    painted = bytearray(total)
    queue = deque()
    for at in range(total):
        base = at * 4
        if not (abs(pixels[base] - value) <= tolerance
                and abs(pixels[base + 1] - value) <= tolerance
                and abs(pixels[base + 2] - value) <= tolerance):
            painted[at] = 1
            queue.append(at)
    if not queue:
        return pixels, 0
    filled = 0
    while queue:
        at = queue.popleft()
        x, y = at % width, at // width
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if nx < 0 or ny < 0 or nx >= width or ny >= height:
                continue
            other = ny * width + nx
            if painted[other]:
                continue
            painted[other] = 1
            pixels[other * 4:other * 4 + 4] = pixels[at * 4:at * 4 + 4]
            filled += 1
            queue.append(other)
    return pixels, filled


def power_of_two(value):
    return value > 0 and (value & (value - 1)) == 0


def report(model, kept, skipped):
    """The lines the run writes about what it took and what it left."""
    lines = ["  port      : %s, %d mesh(es) kept, %d triangle(s)"
             % (model.get("generator") or "a .glb", len(kept),
                sum(len(mesh["triangles"]) for mesh in kept))]
    for mesh in kept:
        lines.append("              took %s - %d triangle(s), material %s"
                     % (mesh["name"], len(mesh["triangles"]), mesh["material"]))
    for mesh in skipped:
        lines.append("              left out %s - %d triangle(s), the item's "
                     "own copy" % (mesh["name"], len(mesh["triangles"])))
    return lines
