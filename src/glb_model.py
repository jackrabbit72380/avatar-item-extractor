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
# Hair is NOT in this list. A costume's headwear is a hat or a helmet, and it
# sits on top of a head rather than replacing the hair on it: dropping the hair
# with the clothes left a bare skull, and the skull is painted by the face
# sheets, which carry nothing at the back - so the nape came out as pale
# unpainted facets under the helmet's rim. The hair is the part that covers it.
# The item's own copy is still dropped, by name and by its box, in choose().
REPLACED_BY_COSTUME = frozenset((
    "headwear", "shirt", "trousers", "shorts", "skirt", "dress",
    "coat", "jacket", "shoes", "socks", "boots", "gloves", "belt",
))
# Hair is worn under a helmet, and a helmet is the whole head, so an avatar in
# one does not show any: left in, a fringe of it pokes out through the visor and
# round the rim of the helmet - the avatar's hair, not the armour's. It is
# dropped with the rest of what the costume replaces; what the head itself loses
# with it (it has no hair of its own painted on) is painted back in rig_items.
COVERED_HAIR = frozenset(("hair", "hairs", "hairstyle", "fringe", "bangs"))
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

# What the suit covers rather than replaces. Jewellery on a wrist or a finger
# is under the armour's glove, and the export draws it where its own body's hand
# was, not where the suit's glove ends up: on the Marine armour the ring and the
# watch both came out floating beside the glove, untextured. Eyewear is the one
# accessory a suit leaves showing, and it stays.
COVERED_BY_COSTUME = frozenset((
    "ring", "rings", "wristwear", "watch", "watches", "bracelet", "bracelets",
    "necklace", "necklaces", "glasses", "sunglasses", "eyewear",
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
        elif costume and (own in REPLACED_BY_COSTUME
                          or own in COVERED_BY_COSTUME
                          or own in COVERED_HAIR):
            skipped.append(mesh)
        else:
            kept.append(mesh)
    if not kept:
        return list(model["meshes"]), []
    return one_of_each(kept, skipped), skipped


def vertex_key(mesh):
    """A mesh's vertices as a value that compares two meshes by where they are."""
    return tuple(sorted(tuple(round(value, 6) for value in point)
                        for point in mesh["positions"]))


def triangle_key(mesh):
    """A mesh's triangles as a value, for telling a copy from another part.

    Two meshes can share a vertex pool and still be two different pieces: this
    export writes the face as two objects over one set of vertices, one holding
    the triangles left of the nose and one holding the triangles right of it.
    Dropping either as a "duplicate" leaves half a face, and half a face reads
    as a dark band down precisely the middle of it. A copy is the same vertices
    AND the same triangles, and nothing less.
    """
    return tuple(sorted(tuple(sorted(triangle)) for triangle in mesh["triangles"]))


def one_of_each(kept, skipped):
    """One mesh per piece, where the export writes the same piece more than once.

    A copy here is the same vertices in the same triangles, which is the only
    thing that cannot be drawn twice without fighting itself. The copy with the
    most triangles is kept; between two the same size the first is kept, because
    that is the one the exporter wrote first. Dropped copies are marked, so the
    caller can say how many it dropped.
    """
    chosen = {}
    order = []
    for mesh in kept:
        key = (vertex_key(mesh), triangle_key(mesh))
        if key not in chosen:
            chosen[key] = mesh
            order.append(key)
        elif len(mesh["triangles"]) > len(chosen[key]["triangles"]):
            chosen[key]["duplicate"] = True
            skipped.append(chosen[key])
            chosen[key] = mesh
        else:
            mesh["duplicate"] = True
            skipped.append(mesh)
    return [chosen[key] for key in order]


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
    """Grow the painted skin into the flat grey the exporter left, in place.

    Each grey texel takes the colour of the nearest painted *skin* texel. Skin,
    not just "anything painted": a face sheet also holds near-white highlights
    and pale scalp, and growing those into the holes drew a cream stripe down
    the nose and a white smear across a cheek. Growing skin into the holes keeps
    both the colour and the shading a face has, and it is still nothing that was
    not painted somewhere on the same face. Returns (pixels, number filled).

    Only the flat grey is filled. Everything else on the sheet is paint: a
    pupil, a lash, a brow, a lip, the white of an eye. The fill used to grow
    into every texel that was not skin-coloured, which is nearly all of a face -
    it painted the pupils over with the skin beside them and left the eyes as
    pale almond shapes with no centre in them, and took the lash and the brow
    with them. On the right avatar's sheet, which has no grey in it at all, it
    rewrote 21760 texels of a 512x512 face for nothing.

    Breadth-first from every skin texel at once, so the fill is by distance and
    not by passes over the image.
    """
    pixels = bytearray(rgba)
    total = width * height
    painted = bytearray(total)
    blank = bytearray(total)
    queue = deque()
    for at in range(total):
        base = at * 4
        red, green, blue = pixels[base], pixels[base + 1], pixels[base + 2]
        if (abs(red - value) <= tolerance
                and abs(green - value) <= tolerance
                and abs(blue - value) <= tolerance):
            blank[at] = 1
        # Warm, mid-bright, and not the near-white the highlights are: skin.
        elif red - blue > 30 and red > 110 and not (red > 246 and green > 216):
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
            # A hole is flat grey and nothing else. Stopping at paint is what
            # keeps the fill inside the holes instead of over the face.
            if painted[other] or not blank[other]:
                continue
            painted[other] = 1
            pixels[other * 4:other * 4 + 4] = pixels[at * 4:at * 4 + 4]
            filled += 1
            queue.append(other)
    return pixels, filled


def ink_tones(rgba, width, height, limit=300):
    """The colour a face is drawn in where it is not skin: brows, lash, beard.

    An export paints the hair sheet flat grey - the hair's colour is the site's,
    applied when it draws the avatar, and never lands in the file - but it does
    paint the same hair on the face, as brows and beard. So the colour the hair
    is meant to be is already in the export, one sheet over: this reads it. The
    median of the dark warm texels, so a black pupil or a white tooth does not
    move it.
    """
    samples = []
    for at in range(0, len(rgba), 4):
        red, green, blue = rgba[at], rgba[at + 1], rgba[at + 2]
        if red + green + blue < limit and red > blue + 8:
            samples.append((red, green, blue))
    if not samples:
        return None
    samples.sort()
    return samples[len(samples) // 2]


def paint_blank(rgba, width, height, colour, value=UNPAINTED, tolerance=6,
                neutral=18):
    """Paint the neutral texels of a sheet the export handed over unpainted.

    The hair arrives like this: flat mid grey where the sheet was left alone,
    a little white, and the rest neutral greys - the colour is the site's and
    never lands in the file. On this sheet 61% of it is the flat grey, and
    painting only that left the part the head's own triangles read still pale.

    So it paints every texel that is neutral - max and min channel within
    `neutral` of each other - which is grey, white and the shading between, and
    leaves any texel with a colour alone. A hair sheet that WAS painted is warm
    or cool hair, not grey, so it is not touched. Returns (pixels, painted).
    """
    pixels = bytearray(rgba)
    painted = 0
    for at in range(0, len(pixels), 4):
        red, green, blue = pixels[at], pixels[at + 1], pixels[at + 2]
        grey = (abs(red - value) <= tolerance
                and abs(green - value) <= tolerance
                and abs(blue - value) <= tolerance)
        if grey or max(red, green, blue) - min(red, green, blue) <= neutral:
            pixels[at], pixels[at + 1], pixels[at + 2] = colour
            painted += 1
    return pixels, painted


def tint_base(rgba, width, height, colour, value=UNPAINTED, tolerance=6, limit=2.0):
    """Colour a sheet whose paint is an untinted base, keeping its shading.

    The hair is painted - there is a hair sheet, with strands on it - but it is
    painted in the site's base colour and the hair's own colour is mixed in when
    the avatar is drawn, so the file carries a cream head of hair whatever the
    avatar's hair looks like. Filling the flat grey with brown (the first thing
    tried here) leaves every strand cream and only browns the padding around
    them, which is a white head with a brown background behind it.

    So the base is measured - the median of the sheet's own paint, leaving out
    the flat grey padding - and one gain a channel maps that base on to the
    colour the hair is meant to be. The strands keep their light and dark, and
    the whole sheet is the avatar's hair colour. Returns (pixels, gain).
    """
    samples = []
    for at in range(0, len(rgba), 4):
        red, green, blue = rgba[at], rgba[at + 1], rgba[at + 2]
        if (abs(red - value) <= tolerance and abs(green - value) <= tolerance
                and abs(blue - value) <= tolerance):
            continue
        samples.append((red, green, blue))
    if not samples:
        return bytearray(rgba), None
    samples.sort()
    base = samples[len(samples) // 2]
    gain = [min(limit, float(colour[channel]) / max(base[channel], 1))
            for channel in range(3)]
    tables = [[min(255, int(round(pixel * gain[channel]))) for pixel in range(256)]
              for channel in range(3)]
    pixels = bytearray(rgba)
    for at in range(0, len(pixels), 4):
        for channel in range(3):
            pixels[at + channel] = tables[channel][pixels[at + channel]]
    return pixels, tuple(round(value, 3) for value in gain)


def paint_uv_patch(rgba, width, height, uv_triangles, colour, pale=236,
                   bare_spread=None):
    """Paint the texels a set of triangles covers, where they are near-white.

    The back of a 360sona head is not painted: the sheet carries white there,
    the same white as the padding around the face, and the hair in the file is
    a fringe that sits inside the skull, so nothing covers it. The scalp is on
    the sheet as white, in the place the head's rear triangles read, and that
    place is exactly what this fills - from the same hair colour the face's own
    brows are drawn in.

    Only near-white texels take the colour, so what the export DID paint at the
    back stays as it was painted. Pass ``pale=None`` to paint every texel of the
    triangles whatever colour it is.

    ``bare_spread`` is the rule for a head's bare skin: a texel is taken when it
    is BRIGHT and barely coloured - the sheet's padding white and the flat grey
    the exporter leaves where it painted nothing are both like that, while skin
    (192,144,104) is 88 apart and the painted eye is 95 apart, and the pupil is
    dark enough to fail the floor. That is what makes it safe to hand this the
    whole head rather than a guess at which triangles are its back: the colour
    decides, and the sheet says plainly which texels were never painted.
    Triangles come as three (u, v) pairs in glTF's convention, v up from the
    bottom of the picture. Returns (pixels, number painted).
    """
    pixels = bytearray(rgba)
    painted = 0
    for a, b, c in uv_triangles:
        det = ((b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1]))
        if abs(det) < 1e-12:
            continue
        xs = [a[0] * width, b[0] * width, c[0] * width]
        ys = [a[1] * height, b[1] * height, c[1] * height]
        x0, x1 = max(0, int(min(xs)) - 1), min(width - 1, int(max(xs)) + 1)
        y0, y1 = max(0, int(min(ys)) - 1), min(height - 1, int(max(ys)) + 1)
        for y in range(y0, y1 + 1):
            py = (y + 0.5) / height
            for x in range(x0, x1 + 1):
                px = (x + 0.5) / width
                one = ((b[1] - c[1]) * (px - c[0]) + (c[0] - b[0]) * (py - c[1])) / det
                two = ((c[1] - a[1]) * (px - c[0]) + (a[0] - c[0]) * (py - c[1])) / det
                three = 1.0 - one - two
                if one < -0.02 or two < -0.02 or three < -0.02:
                    continue
                at = (y * width + x) * 4
                # The padding is white, but not neutral white: the sheets carry
                # 255,244,207 at the back of the skull, whose blue is well
                # under any per-channel floor - which is why a floor of 236 on
                # all three painted nothing at all. What identifies it is that
                # it is BRIGHT and barely coloured, so that is the test; skin
                # is 192,144,104 and fails on brightness alone.
                red, green, blue = pixels[at], pixels[at + 1], pixels[at + 2]
                brightest = max(red, green, blue)
                if bare_spread is not None:
                    take = (brightest >= 100
                            and brightest - min(red, green, blue) <= bare_spread)
                elif pale is None:
                    take = True
                else:
                    take = (brightest >= pale
                            and brightest - min(red, green, blue) <= 72)
                if take:
                    pixels[at], pixels[at + 1], pixels[at + 2] = colour
                    painted += 1
    return pixels, painted


def agreement(pairs):
    """How alike two paintings are, ignoring how bright either was graded.

    Pearson's r over the texels the mirror pairs: 1 is the same picture, 0 is
    unrelated. A face graded twice - one sheet brighter, one duller - is still
    the same picture and scores high, which a median difference in levels cannot
    tell apart from a face whose halves are painted differently. That is the
    question worth asking before one half's paint is copied over the other's.
    """
    if len(pairs) < 16:
        return 0.0
    count = float(len(pairs))
    mean_here = sum(one for one, two in pairs) / count
    mean_there = sum(two for one, two in pairs) / count
    cov = sum((one - mean_here) * (two - mean_there) for one, two in pairs)
    var_here = sum((one - mean_here) ** 2 for one, two in pairs)
    var_there = sum((two - mean_there) ** 2 for one, two in pairs)
    if var_here <= 0 or var_there <= 0:
        return 0.0
    return cov / ((var_here * var_there) ** 0.5)


def _surface_samples(mesh, pixels, width, height):
    """Walk a sheet's triangles: every texel it paints, where it sits on the head.

    Returns (points, colours, texels): the position each texel represents in
    model space, the colour it currently shows, and its (x, y) in the sheet.
    """
    positions = mesh["positions"]
    uvs = mesh["uvs"]
    points = []
    colours = []
    texels = []
    for tri in mesh["triangles"]:
        try:
            corners = [positions[int(i)] for i in tri]
            uv = [(uvs[int(i)][0] * width, uvs[int(i)][1] * height) for i in tri]
        except (IndexError, TypeError):
            continue
        (ax, ay), (bx, by), (cx, cy) = uv
        det = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(det) < 1e-12:
            continue
        x0, x1 = max(0, int(min(ax, bx, cx))), min(width - 1, int(max(ax, bx, cx)) + 1)
        y0, y1 = max(0, int(min(ay, by, cy))), min(height - 1, int(max(ay, by, cy)) + 1)
        if x1 <= x0 or y1 <= y0:
            continue
        for y in range(y0, y1 + 1):
            py = y + 0.5
            for x in range(x0, x1 + 1):
                px = x + 0.5
                w0 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / det
                w1 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / det
                w2 = 1.0 - w0 - w1
                if w0 < -1e-6 or w1 < -1e-6 or w2 < -1e-6:
                    continue
                at = (y * width + x) * 4
                points.append((w0 * corners[0][0] + w1 * corners[1][0] + w2 * corners[2][0],
                               w0 * corners[0][1] + w1 * corners[1][1] + w2 * corners[2][1],
                               w0 * corners[0][2] + w1 * corners[1][2] + w2 * corners[2][2]))
                colours.append((pixels[at], pixels[at + 1], pixels[at + 2]))
                texels.append((x, y))
    return points, colours, texels


def repaint_through_mirror(pixels, width, height, mesh, source, src_width,
                           src_height, src_mesh, cell=0.004):
    """Paint a head half's sheet with the other half's paint, through the mirror.

    A 360sona head is one surface in two halves on two sheets, and the two
    sheets are graded differently - a few levels apart at the cheek and nineteen
    at the forehead. Since the halves are exact mirrors of one another (the
    pairing is good to five microns), the second half can simply WEAR the first
    half's paint: each texel it shows is placed on the head, reflected across
    the midline, and given the colour the other sheet shows at that same point.

    That is the one thing a tone match cannot do - it makes the two halves
    agree statistically, this makes them the same paint, so the join cannot show.

    Point-to-point rather than triangle-to-triangle on purpose: the halves have
    different vertex counts (455 and 496), so a triangle on one side does not
    mirror onto a triangle on the other, only onto the same surface between a
    few of them.

    The copy is only meaningful if the two sheets really are the same painting -
    one face, graded twice. An avatar whose halves are painted differently (a
    scar, a closed eye, a different brow) would have one side's art stamped over
    the other, so the median difference between what the mirror offers and what
    the texel already shows is returned with it: near zero, the sheets agree and
    the copy is safe; large, they do not and the caller should leave the paint
    alone. Returns (pixels, painted, missed, median_gap, agreement) - the last
    being Pearson's r over the same texels, which says whether the two sheets
    are one painting or two.
    """
    points, colours, texels = _surface_samples(mesh, pixels, width, height)
    if not points:
        return bytearray(pixels), 0, 0, 0
    src_points, src_colours, _ = _surface_samples(
        src_mesh, source, src_width, src_height)
    if not src_points:
        return bytearray(pixels), 0, 0, 0

    # Bucket the other half's paint by where it lands once reflected, so each
    # texel here only has to look in its own voxel and the ones around it.
    buckets = {}
    for at, (x, y, z) in enumerate(src_points):
        key = (int(-x // cell), int(y // cell), int(z // cell))
        buckets.setdefault(key, []).append(at)
    nearby = [(dx, dy, dz) for dx in (-1, 0, 1) for dy in (-1, 0, 1) for dz in (-1, 0, 1)]

    out = bytearray(pixels)
    painted = 0
    missed = 0
    gaps = []
    pairs = []
    for at, point in enumerate(points):
        key = (int(point[0] // cell), int(point[1] // cell), int(point[2] // cell))
        best = None
        best_gap = 1e18
        for dx, dy, dz in nearby:
            found = buckets.get((key[0] + dx, key[1] + dy, key[2] + dz))
            if not found:
                continue
            for other in found:
                sx, sy, sz = src_points[other]
                gap = ((sx + point[0]) ** 2 + (sy - point[1]) ** 2 + (sz - point[2]) ** 2)
                if gap < best_gap:
                    best_gap, best = gap, other
        x, y = texels[at]
        to = (y * width + x) * 4
        if best is None:
            missed += 1
            continue
        r, g, b = src_colours[best]
        here = colours[at]
        gaps.append(max(abs(r - here[0]), abs(g - here[1]), abs(b - here[2])))
        pairs.append((0.299 * here[0] + 0.587 * here[1] + 0.114 * here[2],
                      0.299 * r + 0.587 * g + 0.114 * b))
        out[to], out[to + 1], out[to + 2] = r, g, b
        painted += 1
    gaps.sort()
    middle = gaps[len(gaps) // 2] if gaps else 255
    return out, painted, missed, middle, agreement(pairs)


def bitmap_side(value):
    """The smallest power of two a bitmap of this size can be given to tool.exe.

    Halo's bitmap compiler takes a power of two a side and nothing else, and a
    360sona export is not built to that rule: the face sheets are 765x930 and
    746x967, the body 827x1008. Rounded up, never down, so nothing is thrown
    away.
    """
    side = 32
    while side < value:
        side *= 2
    return side


def stretch_bitmap(rgba, width, height, new_width, new_height):
    """Resample a bitmap to another size, keeping the picture where it was.

    UVs are normalised, so a stretch preserves which texel a corner reads - the
    face stays on the face at any size. Bilinear, with numpy when it is there
    (Blender ships it) and plain arithmetic otherwise, so this can be tested
    without Blender.
    """
    if new_width == width and new_height == height:
        return bytearray(rgba), width, height
    try:
        import numpy
    except ImportError:
        numpy = None
    if numpy is not None:
        flat = numpy.frombuffer(bytes(rgba), dtype=numpy.uint8)
        picture = flat.reshape(height, width, 4).astype(numpy.float32)
        xs = (numpy.arange(new_width) + 0.5) * (width / float(new_width)) - 0.5
        ys = (numpy.arange(new_height) + 0.5) * (height / float(new_height)) - 0.5
        x0 = numpy.clip(numpy.floor(xs).astype(int), 0, width - 1)
        y0 = numpy.clip(numpy.floor(ys).astype(int), 0, height - 1)
        x1 = numpy.clip(x0 + 1, 0, width - 1)
        y1 = numpy.clip(y0 + 1, 0, height - 1)
        fx = numpy.clip(xs - numpy.floor(xs), 0.0, 1.0).reshape(1, new_width, 1)
        fy = numpy.clip(ys - numpy.floor(ys), 0.0, 1.0).reshape(new_height, 1, 1)
        top = picture[y0][:, x0] * (1 - fx) + picture[y0][:, x1] * fx
        bottom = picture[y1][:, x0] * (1 - fx) + picture[y1][:, x1] * fx
        out = top * (1 - fy) + bottom * fy
        return bytearray(numpy.clip(out + 0.5, 0, 255).astype(numpy.uint8).tobytes()), new_width, new_height
    out = bytearray(new_width * new_height * 4)
    columns = []
    for x in range(new_width):
        at = (x + 0.5) * width / float(new_width) - 0.5
        low = int(at // 1)
        blend_x = at - low
        if low < 0:
            low, blend_x = 0, 0.0
        columns.append((low, min(width - 1, low + 1), blend_x))
    for y in range(new_height):
        at = (y + 0.5) * height / float(new_height) - 0.5
        low = int(at // 1)
        blend_y = at - low
        if low < 0:
            low, blend_y = 0, 0.0
        high = min(height - 1, low + 1)
        near = low * width * 4
        far = high * width * 4
        base = y * new_width * 4
        for x, (left, right, blend_x) in enumerate(columns):
            a = near + left * 4
            b = near + right * 4
            c = far + left * 4
            d = far + right * 4
            for channel in range(4):
                top = rgba[a + channel] + (rgba[b + channel] - rgba[a + channel]) * blend_x
                bottom = rgba[c + channel] + (rgba[d + channel] - rgba[c + channel]) * blend_x
                out[base + x * 4 + channel] = int(top + (bottom - top) * blend_y + 0.5)
    return out, new_width, new_height


def paint_outside(rgba, width, height, mask, colour):
    """Paint every texel a mesh does NOT read, so a stray UV cannot show padding.

    A head's sheet is mostly padding, and the mesh is welded down its midline -
    which can leave a triangle or two whose corners no longer agree on a UV.
    Such a triangle samples whatever is at that place on the sheet, and on a
    sheet that is white padding, so the crown came out as a pale star while the
    skin beside it was right. Padding is not paint and nothing needs it, so the
    whole of it is laid down in skin: whatever a stray corner samples, it
    samples the head.
    """
    pixels = bytearray(rgba)
    for at in range(0, len(pixels), 4):
        if mask[at >> 2]:
            continue
        pixels[at], pixels[at + 1], pixels[at + 2] = colour
    return pixels


def bleed_padding(rgba, width, height, passes=6, tolerance=6, neutral=18):
    """Carry painted colour out into a sheet's padding, a few texels deep.

    A sheet is an island of paint on padding, and a mesh's UVs run right up to
    the island's edge - so the outermost ring of a face's texels is one texel of
    skin and then padding. Two halves of one head therefore draw a pale line
    down the join whatever colour their paint is, because each half's edge line
    lands on padding, not paint. Measured on this head, that line was the last
    thing left of "two colours" once the two sheets had been brought to one
    tone.

    So the paint is grown outwards into the padding, breadth first and only into
    neutral texels, a few texels deep. Nothing is invented: every texel it
    writes is the colour of the paint beside it. Returns (pixels, bled).
    """
    pixels = bytearray(rgba)
    total = width * height
    blank = bytearray(total)
    queue = deque()
    for at in range(total):
        base = at * 4
        red, green, blue = pixels[base], pixels[base + 1], pixels[base + 2]
        flat = max(red, green, blue) - min(red, green, blue) <= neutral
        grey = (abs(red - UNPAINTED) <= tolerance
                and abs(green - UNPAINTED) <= tolerance
                and abs(blue - UNPAINTED) <= tolerance)
        if flat or grey:
            blank[at] = 1
        else:
            queue.append((at, 0))
    bled = 0
    head = 0
    while head < len(queue):
        at, depth = queue[head]
        head += 1
        if depth >= passes:
            continue
        x, y = at % width, at // width
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if nx < 0 or ny < 0 or nx >= width or ny >= height:
                continue
            other = ny * width + nx
            if not blank[other]:
                continue
            blank[other] = 0
            pixels[other * 4:other * 4 + 4] = pixels[at * 4:at * 4 + 4]
            bled += 1
            queue.append((other, depth + 1))
    return pixels, bled


def uv_coverage(width, height, uv_triangles, into=None):
    """The texels a set of triangles reads, as one byte a texel.

    Two halves of one face can be painted on two sheets and each sheet can hold
    far more than its half - padding, the other side of the head, a smear. The
    tone that matters is the tone of the texels this half's triangles actually
    land on, and this says which those are. Triangles are (u, v) in glTF's
    convention, v up from the bottom of the picture.
    """
    mask = into if into is not None else bytearray(width * height)
    for a, b, c in uv_triangles:
        det = ((b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1]))
        if abs(det) < 1e-12:
            continue
        xs = [a[0] * width, b[0] * width, c[0] * width]
        ys = [a[1] * height, b[1] * height, c[1] * height]
        x0, x1 = max(0, int(min(xs))), min(width - 1, int(max(xs)) + 1)
        y0, y1 = max(0, int(min(ys))), min(height - 1, int(max(ys)) + 1)
        for y in range(y0, y1 + 1):
            py = (y + 0.5) / height
            for x in range(x0, x1 + 1):
                px = (x + 0.5) / width
                one = ((b[1] - c[1]) * (px - c[0]) + (c[0] - b[0]) * (py - c[1])) / det
                two = ((c[1] - a[1]) * (px - c[0]) + (a[0] - c[0]) * (py - c[1])) / det
                if one < 0.0 or two < 0.0 or one + two > 1.0:
                    continue
                mask[y * width + x] = 1
    return mask


def skin_tones(rgba, width, height, mask=None):
    """The colour of the skin a sheet is painted in: the median of its skin texels.

    Median, not average, so one white highlight or one brown shadow does not
    move it. Texels counted are warm ones (red well above blue) in the mid
    range, which is skin and not a highlight or a hair edge. A mask, from
    uv_coverage, limits the count to the texels some geometry reads: two halves
    of one face match by what they SHOW, not by what their sheets contain.
    """
    samples = []
    for at in range(0, len(rgba), 4):
        if mask is not None and not mask[at >> 2]:
            continue
        red, green, blue = rgba[at], rgba[at + 1], rgba[at + 2]
        if red - blue > 30 and 110 < red < 215:
            samples.append((red, green, blue))
    if not samples:
        return None
    samples.sort()
    return samples[len(samples) // 2]


def match_tone(rgba, width, height, target, limit=0.45, passes=6, close=2,
               mask=None):
    """Bring a sheet's skin to a target colour, by one gain across the sheet.

    A 360sona export paints the two halves of a face on two sheets, and the two
    sheets are not painted the same: on one avatar the right half's skin is
    (211, 154, 102) and the left half's is (166, 137, 113) - a warm bright face
    and a dull grey one on the same head. One gain per channel, applied to the
    whole sheet, keeps every painted feature where it is and only moves the
    colour, so the face ends up one colour instead of two.

    The gain is measured again after it is applied, and applied again if it did
    not land. One pass is not enough to guarantee one tone: scaling the sheet
    moves texels in and out of the warm mid-range skin_tones counts, so the
    median it reads afterwards is not the median the gain was worked out from.
    Measured on this head, one pass left the pale half at (207, 149, 99) against
    the (192, 140, 93) both sheets were aimed at - 15 levels, which draws as a
    line down the nose - and the second pass closed it to within 2.

    Returns (pixels, gain) or (pixels, None) when the sheet has no skin to
    measure or already sits on the target. A gain that would leave the sheet
    more than `limit` away from where it started is refused: that is a mistake
    in what was matched, not a grading difference, and stretching the whole
    face by it would be worse than the two-tone it was meant to fix.
    """
    total = [1.0, 1.0, 1.0]
    if skin_tones(rgba, width, height, mask) is None:
        return bytearray(rgba), None
    pixels = bytearray(rgba)
    moved = False
    for _ in range(passes):
        measured = skin_tones(pixels, width, height, mask)
        if measured is None:
            break
        if all(abs(measured[channel] - target[channel]) <= close
               for channel in range(3)):
            break
        step = [float(target[channel]) / max(measured[channel], 1)
                for channel in range(3)]
        wanted = [total[channel] * step[channel] for channel in range(3)]
        if any(abs(value - 1.0) > limit for value in wanted):
            if not moved:
                return bytearray(rgba), None
            break
        # One lookup table a channel, rather than a multiply per texel.
        tables = [[min(255, int(round(value * step[channel]))) for value in range(256)]
                  for channel in range(3)]
        for at in range(0, len(pixels), 4):
            for channel in range(3):
                pixels[at + channel] = tables[channel][pixels[at + channel]]
        total = wanted
        moved = True
    if not moved:
        return bytearray(rgba), None
    return pixels, tuple(round(value, 3) for value in total)


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
