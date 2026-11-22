#!/usr/bin/env python3
"""Extract retail Xbox 360 avatar items into a catalogue and per-item files.

Carried inside Extract-AvatarItem-v20.bat together with the two reader modules
it needs, which are written beside this script on first run. Written in plain
ASCII on purpose: the batch file copies these bytes verbatim.

You do not tell it where the items are. It reads one folder - the one the batch
file passes as --root, which is the folder the .bat sits in - and nothing else.
No Downloads, no Desktop, no Documents. Put the items beside the .bat and run it.

A "source" is a folder holding closet_index.tsv (the retail layout: index,
<guid>.bin, icons/) or one holding .bin / .asset item files. A single item file
also works as an explicit argument. Pass --root to search somewhere else, or a
path to skip discovery entirely.

An item asset is a `STRB` container. Block 3 is the model, and in retail assets
that block is LZX-framed inside the container, where the editor's own asset
pack stores its blocks plain. So the model is:

    blocks = strb_blocks(data)
    payload = block 3
    batches = read_model(decompress(payload))

which yields, per batch: vertices, u16 triangle indices, UV sets, material
records, per-vertex joints and weights, shader ids, and the item's bounds.

Usage:
    python extract_items.py                  # find everything, extract it
    python extract_items.py <folder-or-file> # that one source
    python extract_items.py --root D:\\dump --root D:\\more

Options:
    --out DIR        where to write (default: extracted)
    --obj            also write each parsed model as <out>/<id>.obj
    --only ID|NAME   extract only matching ids or names (repeatable)
    --limit N        stop after N items
    --no-icons       do not copy icons
    --root DIR       search this folder instead of the default list (repeatable)
    --mesh-dir DIR   where the reader modules go (default: beside this script)

Writes:
    <out>/catalogue.json     one record per item: name, masks, blocks, geometry
    <out>/<id>.png           copied from icons/<id>.png or a loose icon.png
    <out>/<id>.obj           with --obj

Exit status: 0 something parsed, 3 sources found but nothing parsed, 4 nothing
found. Requires Python 3.8+. No third-party packages.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import struct
import sys
import zlib

INDEX = "closet_index.tsv"
ITEM_EXTENSIONS = (".bin", ".asset")
# A container is either a bare STRB block or an Xbox package; wxPirs names
# packages by GUID with no extension at all, so the name cannot be trusted.
CONTAINER_MAGIC = (b"STRB", b"CON ", b"LIVE", b"PIRS")
SKIP_DIRS = {"node_modules", "__pycache__", ".git", "vendor", "extracted",
             "$RECYCLE.BIN", "System Volume Information"}
MAX_DEPTH = 3

def load_mesh(explicit_dir=None):
    """Import avatar_mesh.py, written out of this file beside the script."""
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = []
    if explicit_dir:
        candidates.append(explicit_dir)
    candidates += [os.path.join(here, "vendor"), here]
    for path in candidates:
        path = os.path.abspath(path)
        if os.path.exists(os.path.join(path, "avatar_mesh.py")):
            sys.path.insert(0, path)
            try:
                import avatar_mesh
                return avatar_mesh
            except ImportError as exc:
                sys.path.pop(0)
                raise SystemExit("avatar_mesh.py in %s could not be imported: %s"
                                 % (path, exc))
    raise SystemExit(
        "avatar_mesh.py not found beside this script. Run the .bat again from a "
        "simple path such as C:\\Tools, or pass --mesh-dir.")


# ---------------------------------------------------------------- discovery

def default_roots():
    """Where it runs from, and nothing else. The .bat passes --root explicitly."""
    roots = [os.getcwd()]
    # keep the originals (with ~ expanded) but drop duplicates and repeats of
    # a parent already listed, so the report does not print the same tree twice
    seen = []
    for root in roots:
        root = os.path.abspath(root)
        if not os.path.isdir(root):
            continue
        if any(root == other or root.startswith(other + os.sep) for other in seen):
            continue
        seen.append(root)
    return seen


def is_container(path):
    """True for a .bin, or any file whose first four bytes are a container."""
    if os.path.splitext(path)[1].lower() in ITEM_EXTENSIONS:
        return True
    try:
        with open(path, "rb") as handle:
            return handle.read(4) in CONTAINER_MAGIC
    except OSError:
        return False


def is_source(folder, files):
    if INDEX in files:
        return True
    return any(is_container(os.path.join(folder, name)) for name in files)


def find_sources(roots):
    """Every folder under the roots that holds items. Bounded and skippable."""
    found = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        base_depth = os.path.abspath(root).rstrip(os.sep).count(os.sep)
        for current, dirs, files in os.walk(root):
            dirs[:] = sorted(d for d in dirs
                             if not d.startswith(".") and d not in SKIP_DIRS)
            depth = current.rstrip(os.sep).count(os.sep) - base_depth
            if depth >= MAX_DEPTH:
                dirs[:] = []
            if is_source(current, files):
                found.append(current)
                dirs[:] = []
    unique = []
    for path in found:
        if path not in unique:
            unique.append(path)
    return unique


# ------------------------------------------------------------------- the index

def read_index(folder):
    """id -> (categories, bodies, name) from closet_index.tsv.

    Four tab-separated columns: the item GUID, the category bitmask, the body
    mask, the name. Column two restates the GUID's first four bytes, which is
    where the LIVE service kept the categories; column three is
    `avatarBodyType`, where 3 means male+female and 1/2 mean one body each.
    """
    path = os.path.join(folder, INDEX)
    entries = {}
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 4:
                continue
            item, cats, bodies, name = parts[0], parts[1], parts[2], parts[3]
            try:
                categories = int(cats, 16)
                body_mask = int(bodies, 10)
            except ValueError:
                continue
            entries[item] = (categories, body_mask, name)
    return entries


def guid_categories(item_id):
    """The category bitmask lives in the GUID's first four bytes."""
    match = re.match(r"^([0-9a-fA-F]{8})-", item_id)
    return int(match.group(1), 16) if match else None


def asset_rank(name):
    """Order for loose item files: the newer revision of the same item first.

    A folder holding both copies of one item is normal - asset.bin and
    asset_v2.bin are the same item in two formats. Plain sorting puts
    "asset.bin" first ('.' sorts before '_'), which reads the older revision and
    then discards the newer one as a duplicate, so the rank is explicit.
    """
    low = name.lower()
    if low == "asset_v2.bin":
        return 0
    if low == "asset.bin":
        return 1
    return 2


# A container is delivered as a folder named after it, holding one of these.
# The file name is the format, not the item, so it cannot name the output.
GENERIC_ASSET_NAMES = {"asset", "asset_v2", "avatarasset", "avatar_item",
                       "avataritem", "content", "package"}


def looks_like_container_name(name):
    """A GUID in any of the spellings a dump or a package uses."""
    bare = name.replace("-", "").replace("_", "").strip()
    return len(bare) == 32 and all(char in "0123456789abcdefABCDEF" for char in bare)


def fallback_names():
    """extracted1, extracted2, ... for items nothing else names."""
    number = 0
    while True:
        number += 1
        yield "extracted%d" % number


def item_id_for(path, unnamed=None):
    """What a loose file is called, in the order the evidence arrives.

    A package is named after the container: its own file name is the item's
    GUID, and its Title is read from inside it. Loose bins are named after the
    folder they arrived in when that folder is the container's name. Failing
    both - plain asset.bin or asset_v2.bin in a folder with no item name -
    the file name says what format the bytes are and nothing about the item, so
    it cannot name anything: the item becomes extracted1, extracted2 and so on,
    in the order they are found. Every item in a run keeps a name of its own.
    """
    base = os.path.splitext(os.path.basename(path))[0]
    if base.lower() not in GENERIC_ASSET_NAMES:
        return base
    folder = os.path.basename(os.path.dirname(os.path.abspath(path)))
    if looks_like_container_name(folder):
        return folder
    if unnamed is None:
        return base
    return next(unnamed)


def collect(source, unnamed=None):
    """Everything to extract from one source: (id, categories, bodies, name, path)."""
    entries = []
    if os.path.isfile(source):
        item_id = item_id_for(source, unnamed)
        return [(item_id, guid_categories(item_id), None, "", source)]

    if os.path.exists(os.path.join(source, INDEX)):
        for item_id, (cats, bodies, name) in sorted(read_index(source).items()):
            entries.append((item_id, cats, bodies, name,
                            os.path.join(source, item_id + ".bin")))
        return entries

    names = sorted(os.listdir(source), key=lambda entry: (asset_rank(entry), entry))
    lowered = {name.lower() for name in names}
    if "asset_v2.bin" in lowered and "asset.bin" in lowered:
        # One item in two formats, not two items. The newer revision is the item;
        # the older copy is the same part with less in it. Their models can
        # differ by a few bytes, so comparing model bytes does not identify
        # them - the name does, and it is the same item either way.
        names = [name for name in names if name.lower() != "asset.bin"]
    for name in names:
        if not is_container(os.path.join(source, name)):
            continue
        path = os.path.join(source, name)
        item_id = item_id_for(path, unnamed)
        entries.append((item_id, guid_categories(item_id), None, "", path))
    return entries


def describe_source(source):
    """A one-line account of what a source will give us."""
    if os.path.isfile(source):
        return "1 file, %d bytes" % os.path.getsize(source)
    if os.path.exists(os.path.join(source, INDEX)):
        return "%d items in the index" % len(read_index(source))
    count = sum(1 for name in os.listdir(source)
                if is_container(os.path.join(source, name)))
    return "%d item files" % count


# ------------------------------------------------------------------ the item

# What a .bin or .asset that is not an avatar item says back to the user.
NOT_AVATAR = "Error: this container does not contain Avatar Item Content. Please try another."


# An Xbox 360 package - what an avatar item downloads as - is a STFS file. Its
# Title is in the header, which is where wxPirs reads "Title : ..." from.
STFS_MAGIC = (b"CON ", b"LIVE", b"PIRS")
STFS_DISPLAY_NAME = 0x411   # 12 locales of 0x80 bytes, UTF-16BE: the Title
STFS_TITLE_NAME = 0x1691    # 0x80 bytes, UTF-16BE
STFS_HEADER = STFS_TITLE_NAME + 0x80


def utf16be(raw):
    """A NUL-terminated UTF-16BE field as text."""
    end = 0
    while end + 1 < len(raw) and raw[end:end + 2] != b"\x00\x00":
        end += 2
    return raw[:end].decode("utf-16-be", "replace").strip()


def package_title(path):
    """The Title the package shows in wxPirs, or None if it is not a package."""
    try:
        with open(path, "rb") as handle:
            head = handle.read(STFS_HEADER)
    except OSError:
        return None
    if head[:4] not in STFS_MAGIC:
        return None
    for offset in (STFS_DISPLAY_NAME, STFS_TITLE_NAME):
        if len(head) >= offset + 0x80:
            title = utf16be(head[offset:offset + 0x80])
            if title:
                return title
    return None


def _stfs_listing(data, tables):
    """The package's files, read through its file table. tables = copies of
    each hash table (2 for a writable CON, 1 for LIVE/PIRS)."""
    if len(data) < 0x400:
        return None
    header_size = struct.unpack_from(">I", data, 0x340)[0]
    base = (header_size + 0xFFF) & ~0xFFF
    desc = 0x379
    if desc + 8 > len(data):
        return None
    count = struct.unpack_from("<H", data, desc + 3)[0]
    first = int.from_bytes(data[desc + 5:desc + 8], "little")
    if not count or count > 0x100:
        return None

    def offset_of(block):
        # A hash table sits before every 170 data blocks and is not counted in
        # the block numbering, so step over one per table copy.
        return base + (block + (block // 0xAA) * tables) * 0x1000

    listing = bytearray()
    for index in range(count):
        start = offset_of(first + index)
        chunk = data[start:start + 0x1000]
        if len(chunk) < 0x1000:
            return None
        listing += chunk

    files = {}
    for index in range(len(listing) // 0x40):
        entry = listing[index * 0x40:(index + 1) * 0x40]
        flags = entry[0x28]
        name_len = flags & 0x3F
        if not name_len or name_len > 0x28:
            continue
        if flags & 0x80:
            continue                      # a folder
        name = entry[:name_len].decode("ascii", "replace")
        size = struct.unpack_from(">I", entry, 0x34)[0]
        start = int.from_bytes(entry[0x2F:0x32], "little")
        if not size or size > 0x4000000:
            continue
        body = bytearray()
        for step in range((size + 0xFFF) // 0x1000):
            at = offset_of(start + step)
            body += data[at:at + 0x1000]
        files[name] = bytes(body[:size])
    return files or None


def pick_asset(files):
    """The item asset inside a package, whatever the package calls it."""
    lowered = {name.lower(): name for name in files}
    for wanted in ("asset_v2.bin", "asset.bin"):
        if wanted in lowered:
            return files[lowered[wanted]]
    for name in sorted(files):
        if name.lower().endswith((".bin", ".asset")):
            return files[name]
    return None


def stfs_files(data):
    """name -> bytes for an STFS package, or None when nothing reads cleanly."""
    if len(data) < 0x400 or data[:4] not in STFS_MAGIC:
        return None
    fallback = None
    for tables in (1, 2):
        files = _stfs_listing(data, tables)
        if not files:
            continue
        asset = pick_asset(files)
        if asset is not None and asset[:4] in (b"STRB", b"YTGR"):
            return files
        fallback = fallback or files
    return fallback


def strb_extent(data, start):
    """Where the STRB container beginning at start ends, or None.

    The block walk stops at the first header that does not make sense, so the
    bytes after the container - other files, padding - are left out. Without
    the exact end the parser sees those bytes as a broken block.
    """
    head = data[start:start + 30]
    if len(head) < 26 or head[:4] != b"STRB":
        return None
    has_alignment = head[4] != 0
    order = "little" if head[5] else "big"
    id_size, size_size = head[22], head[23]
    if not (1 <= id_size <= 8 and 1 <= size_size <= 8):
        return None
    align_to = head[26] if has_alignment else 1
    if not align_to:
        return None

    def align(value):
        return (value + align_to - 1) & ~(align_to - 1)

    header_size = align(id_size + 2 * size_size)
    if not header_size:
        return None
    offset = start + align(30 if has_alignment else 26)
    end = offset
    while offset + header_size <= len(data):
        chunk = data[offset:offset + header_size]
        ident = int.from_bytes(chunk[:id_size], order)
        count = int.from_bytes(chunk[id_size:id_size + size_size], order)
        entry = int.from_bytes(chunk[id_size + size_size:id_size + 2 * size_size], order)
        total = count * entry
        offset += header_size
        if not ident and not count and not entry:
            break
        if offset + total > len(data):
            break
        offset += align(total)
        end = offset
    return end if end > start + 26 else None


def package_texture(files):
    """A texture kept as its own file in the package, when the asset has none."""
    for name in sorted(files or {}):
        body = files[name]
        if len(body) >= 33 and struct.unpack_from("<H", body, 1)[0] == 0x1A20:
            return body
    return None


def package_png(data):
    """The first PNG inside a package: the item's icon."""
    at = data.find(b"\x89PNG\r\n\x1a\n")
    if at == -1:
        return None
    end = data.find(b"IEND", at)
    if end == -1:
        return None
    return data[at:end + 8]


def stfs_scan(data):
    """Candidate assets taken from the package's own bytes.

    The file table can be missing or its blocks can fail to line up, but the
    asset is a STRB block sitting in the data area either way. Hand back each
    STRB container found; the caller keeps the first that parses.
    """
    at = data.find(b"STRB")
    found = 0
    while at != -1 and found < 64:
        found += 1
        end = strb_extent(data, at)
        if end:
            yield data[at:end]
        at = data.find(b"STRB", at + 4)


def choose_asset(mesh, data, package):
    """The asset to draw from a package: the newest revision it holds.

    A marketplace package holds the same item more than once - asset.bin and
    asset_v2.bin, and sometimes further copies loose in the data area. The newer
    revision is the one carrying the versioned metadata block (id 8); failing
    that, the one with the larger model; failing that, the later, larger copy.

    Every candidate is parsed before it is chosen, so a truncated or corrupt
    copy cannot win on position alone, and the caller gets facts rather than
    guesses about which one it picked.
    """
    candidates = []
    seen = set()

    def add(label, body):
        digest = hashlib.sha1(body).hexdigest()
        if digest in seen:
            return
        seen.add(digest)
        candidates.append((label, body))

    for name in sorted(package or {}):
        body = package[name]
        if body[:4] in (b"STRB", b"YTGR"):
            add(name, body)
    for index, body in enumerate(stfs_scan(data)):
        add("container %d" % index, body)

    best = None
    for label, body in candidates:
        try:
            facts, batches = summarise(mesh, body)
        except Exception:
            continue
        if not facts.get("avatar") or not batches:
            continue
        ids = {block["id"] for block in facts["blocks"]}
        model = max((block["size"] for block in facts["blocks"]
                     if block["id"] == 3), default=0)
        score = (8 in ids, model, len(body), "v2" in label.lower())
        if best is None or score > best[0]:
            best = (score, label, facts, batches)
    if best is None:
        return None
    return best[2], best[3], best[1]


def package_listing(files):
    """What a package holds, for the console when nothing in it parses."""
    if not files:
        return []
    return ["%s (%d bytes)" % (name, len(files[name])) for name in sorted(files)]


def item_title(name, path, item_id):
    """The item's title, and where it came from.

    A closet already carries the title. A loose item does not, so look for the
    package it came out of: first beside the item files, then one folder up -
    wxPirs names that folder after the package, so the names have to match.
    """
    if name:
        return name, "closet"
    # The item may itself be a package: its Title is inside it, not beside it.
    try:
        if os.path.isfile(path) and os.path.getsize(path) >= STFS_HEADER:
            with open(path, "rb") as handle:
                if handle.read(4) in STFS_MAGIC:
                    title = package_title(path)
                    if title:
                        return title, "package %s" % os.path.basename(path)
    except OSError:
        pass
    folder = os.path.dirname(os.path.abspath(path))
    folder_name = os.path.basename(folder).lower()
    for depth, parent in ((0, folder), (1, os.path.dirname(folder))):
        try:
            entries = sorted(os.listdir(parent))
        except OSError:
            continue
        for entry in entries:
            candidate = os.path.join(parent, entry)
            try:
                if not os.path.isfile(candidate) or os.path.getsize(candidate) < STFS_HEADER:
                    continue
            except OSError:
                continue
            # Package names are the item's GUID: 00000FFC3972... against the
            # closet's 00000ffc-3972-..., so compare without dashes.
            stem = os.path.splitext(entry)[0].replace("-", "").lower()
            if depth and stem not in (item_id.replace("-", "").lower(),
                                      folder_name.replace("-", "")):
                continue
            title = package_title(candidate)
            if title:
                return title, "package %s" % entry
    return None, None


def safe_folder(title):
    """A Windows-safe folder name made from a title."""
    text = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "", title or "")
    text = re.sub(r"\s+", " ", text).strip(" .")
    return text[:80].rstrip(" .")


# ------------------------------------------------------------------- layout

# The output is laid out for the person opening it, not for the extractor. A
# Max user wants the model and its textures; a Blender user wants the rigs and
# the same textures; a HEK user wants bitmaps in data\ and a tags\ folder to
# build into, in both channel orders. Nobody should have to sort through
# another program's files to find their own.
MAX_DIR = "extracted for max users"
BLENDER_DIR = "extracted for blender users"
HEK_DIR = "extracted for hek users"

LAYOUT = (MAX_DIR, BLENDER_DIR, HEK_DIR + "/pc/data", HEK_DIR + "/pc/tags",
          HEK_DIR + "/xbox/data", HEK_DIR + "/xbox/tags")


def mask_orders(name):
    """Which Halo builds a bitmap is for: pc, xbox, or both."""
    low = name.lower()
    if "multipurpose xbox" in low:
        return ("xbox",)
    if "multipurpose sp" in low:
        # Nothing is masked, so the image is the same in either channel order.
        return ("pc", "xbox")
    if "multipurpose" in low:
        return ("pc",)
    if "change colour" in low or "base map" in low:
        return ("pc", "xbox")
    # The item's own colour image, and the per-part ones the .mtl names when a
    # model's batches differ ("<stem> colour 99331A.png"). Both are textures
    # the model binds, not the palette card, which has no space in its name.
    if re.search(r" colour( [0-9a-f]{6})?\.(png|tga|tif)$", low):
        return ("pc", "xbox")
    return ()


def organise(out):
    r"""Sort one item's files into max\, blender\ and hek\pc|xbox\data|tags\.

    Runs once, after every file is written, so the shape is the same whether
    Blender ran or not. A file with one home is moved; a bitmap that two people
    need is copied, so no reader has to go looking inside another program's
    folder. Anything this does not name - the icon, the colour card, the hex
    list, report.txt, catalogue.json - stays in the item's own folder, where it
    describes the item rather than belonging to a program.
    """
    for folder in LAYOUT:
        os.makedirs(os.path.join(out, *folder.split("/")), exist_ok=True)
    for name in sorted(os.listdir(out)):
        source = os.path.join(out, name)
        if not os.path.isfile(source):
            continue
        low = name.lower()
        extension = low.rsplit(".", 1)[-1] if "." in low else ""
        homes = []
        if extension in ("obj", "mtl"):
            homes = [MAX_DIR]
        elif extension in ("blend", "fbx", "glb"):
            homes = [BLENDER_DIR]
        elif extension == "jms":
            homes = [HEK_DIR + "/pc/data"]
        elif extension in ("png", "tga", "tif"):
            orders = mask_orders(name)
            if orders:
                if extension in ("png", "tga"):
                    homes = [MAX_DIR, BLENDER_DIR]
                else:
                    # .tif is what tool.exe compiles, so it belongs to the
                    # engine folders and not beside the model.
                    homes = [HEK_DIR + "/%s/data" % order for order in orders]
        if not homes:
            continue
        for home in homes[:-1]:
            shutil.copyfile(source, os.path.join(out, *home.split("/"), name))
        shutil.move(source, os.path.join(out, *homes[-1].split("/"), name))


def titled_out(out, records):
    """The run's folder: named after the one item's title when there is one.

    One item, one folder called what the item is called - the package's Title,
    or the closet's name. Several items keep the plain output folder, because
    there is no single title to give it.
    """
    if len(records) != 1:
        return out
    folder = safe_folder(records[0].get("title") or "")
    if not folder:
        return out
    target = os.path.join(os.path.dirname(os.path.abspath(out)), folder)
    if os.path.abspath(target) == os.path.abspath(out):
        return out
    try:
        if os.path.isdir(target):
            for name in os.listdir(out):
                shutil.move(os.path.join(out, name), os.path.join(target, name))
            os.rmdir(out)
        else:
            shutil.move(out, target)
    except OSError:
        return out
    return target


def icon_candidates(path, item_id):
    """Where an item's picture may sit, best first.

    A closet keeps them in icons\\<id>.png. Loose folders, which are often an
    extract of one item, keep a single icon.png beside the .bin files.
    """
    folder = os.path.dirname(path)
    return [os.path.join(folder, "icons", item_id + ".png"),
            os.path.join(folder, "icon.png")]


def model_facts(batches):
    """The geometry summary written into the catalogue."""
    points = [point for batch in batches for point in batch["vertices"]]
    bounds = [
        [round(min(p[axis] for p in points), 4), round(max(p[axis] for p in points), 4)]
        for axis in range(3)
    ]
    return {
        "parses": True,
        "batches": len(batches),
        "vertices": len(points),
        "triangles": sum(len(batch["indices"]) // 3 for batch in batches),
        "uv_sets": max((len(uv) for batch in batches for uv in batch["uvs"]), default=0),
        "textures": max((sum(1 for record in batch.get("materials") or []
                              if record.get("kind") == "texture")
                         for batch in batches), default=0),
        "shader_ids": [batch["shader_id"] for batch in batches],
        # Item space, y up: feet sit at y = 0 and the head tops out near 1.6.
        "bounds": bounds,
    }


def extra_uv_sets(batches):
    """Every UV set past the first, in the vertex order the OBJ writes them.

    An OBJ holds one texture coordinate per corner, so only the set the item
    binds its first texture slot to can go in the file itself. The others are
    carried here instead, one flat list per set, so the Blender file can have
    them as real layers rather than losing them. Items with a single set - most
    of them - carry nothing extra.
    """
    count = max((len(pair) for batch in batches for pair in batch.get("uvs") or []),
                default=0)
    sets = []
    for index in range(1, count):
        pairs = []
        for batch in batches:
            uvs = batch.get("uvs") or []
            for position in range(len(batch.get("vertices") or [])):
                pair = uvs[position] if position < len(uvs) else None
                if pair is not None and index < len(pair):
                    pairs.append([round(pair[index][0], 5), round(pair[index][1], 5)])
                else:
                    pairs.append([0.0, 0.0])
        sets.append(pairs)
    return sets


def bare_model(mesh, data, facts):
    """A model block on its own, with no STRB container wrapped around it.

    Some extracts keep only block 3 - the LZX chain that holds the mesh - as
    asset.bin. It is the same bytes a container carries, so it parses the same
    way once the chain is decompressed.
    """
    try:
        inner = mesh.decompress(data)
        batches = mesh.read_model(inner)
    except mesh.Malformed:
        return None
    if not batches:
        return None
    facts["avatar"] = True
    facts["bare"] = True
    facts["fingerprint"] = hashlib.sha1(inner).hexdigest()
    facts["model"] = model_facts(batches)
    return batches


def wrapped(path):
    """True when the file is a Y TGR/STRB container, judged by its first bytes."""
    try:
        with open(path, "rb") as handle:
            return handle.read(4) in (b"YTGR", b"STRB")
    except OSError:
        return False


def texture_facts(entry):
    """One decoded slot, in the shape the rest of the extractor expects."""
    return {"width": entry["width"], "height": entry["height"],
            "format": entry["format"], "endian": entry.get("endian"),
            "frames": entry.get("frames"), "pixels": len(entry["data"]),
            "slot": entry.get("slot"), "rgba": entry["rgba"]}


def mask_from_texture(texture, size):
    """A mask byte a texel out of a texture's red channel, nearest neighbour.

    The tint mask is painted red where the item takes a colour (with shading
    through it on cloth), so its red channel is the mask as the item states it.
    """
    width = texture.get("width") or 0
    height = texture.get("height") or 0
    rgba = texture.get("rgba") or b""
    if width <= 0 or height <= 0 or len(rgba) < width * height * 4:
        return None
    out = bytearray(size * size)
    for y in range(size):
        source_row = min(height - 1, y * height // size) * width * 4
        target = y * size
        for x in range(size):
            out[target + x] = rgba[source_row + min(width - 1, x * width // size) * 4]
    return bytes(out)


def texture_from_model(mesh, batches):
    """The base map out of the model block's own texture table.

    The model names its slots (texture_count) and every slot carries a 33-byte
    header saying its own size, format and pixel count. Nothing here is guessed:
    the file states which slot is the base map and how big it is. A slot whose
    flags say empty is skipped, and a table of nothing but empty slots means the
    item genuinely has no base map.
    """
    for batch in batches or []:
        for entry in batch.get("textures") or []:
            if not entry or entry.get("empty") or not entry.get("data"):
                continue
            width = entry.get("width") or 0
            height = entry.get("height") or 0
            if width <= 0 or height <= 0:
                continue
            if entry.get("format") not in (0x12, 0x14):
                continue
            return {
                "width": width,
                "height": height,
                "format": entry["format"],
                "endian": entry.get("endian"),
                "frames": entry.get("frames"),
                "pixels": len(entry["data"]),
                "rgba": mesh.decode_dxt_bytes(entry["data"], width, height,
                                              entry["format"] == 0x14,
                                              swap=entry.get("endian") == 1),
            }
    return None


def slot_textures(mesh, batches):
    """Textures from the model's own table, keyed by the role a material binds.

    A material names the slot each of its textures comes from, and the role is
    the material's id: 1 the base colour, 2 the tint mask, 3 a decal, 4 a
    reflection map. Reading the table by role is what lets an item's own tint
    mask become the colour-change mask instead of one being invented.
    """
    by_role = {}
    for batch in batches or []:
        table = batch.get("textures") or []
        for record in batch.get("materials") or []:
            if record.get("kind") != "texture":
                continue
            slot = record.get("texture")
            role = record.get("id")
            if role in by_role or slot is None or not 0 <= slot < len(table):
                continue
            entry = table[slot]
            if not entry or entry.get("empty") or not entry.get("data"):
                continue
            width = entry.get("width") or 0
            height = entry.get("height") or 0
            if width <= 0 or height <= 0 or entry.get("format") not in (0x12, 0x14):
                continue
            decoded = dict(entry)
            decoded["slot"] = slot
            decoded["role"] = role
            decoded["rgba"] = mesh.decode_dxt_bytes(
                entry["data"], width, height, entry["format"] == 0x14,
                swap=entry.get("endian") == 1)
            by_role[role] = decoded
    return by_role


def summarise(mesh, data):
    """Read one item: block table plus geometry, or the reason it failed."""
    facts = {"bytes": len(data), "blocks": [], "model": {"parses": False},
             "avatar": False}
    try:
        blocks = mesh.strb_blocks(data)
    except mesh.Malformed as exc:
        # Not a container: it may still be the bare model block itself.
        batches = bare_model(mesh, data, facts)
        if batches is None:
            facts["model"]["error"] = NOT_AVATAR
            facts["container_error"] = str(exc)
        return facts, batches
    # The first bytes of each block go into the catalogue: when a texture or a
    # colour table is not found, this is the evidence of what the container
    # actually holds, rather than a guess about it.
    facts["blocks"] = [{"id": block[0], "size": block[1],
                        "name": mesh.BLOCK_NAMES.get(block[0], "unknown"),
                        "head": block[3][:8].hex()} for block in blocks]
    # The payloads themselves, so a block this tool does not decode can still be
    # handed over. Nothing is thrown away for being unrecognised.
    facts["block_data"] = [(block[0], block[3], block[1]) for block in blocks]
    facts["avatar"] = True
    # Block 7 is the item's own colour table: the choosable colours a
    # multiplayer item is tinted with. Every table in the container is kept,
    # so an item holding more than one gets colour_00.png, colour_01.png, ...
    for ident, _count, _entry, body in blocks:
        if ident != 7:
            continue
        table = mesh.colour_table(body)
        if table is None:
            # Retail blocks are LZX-framed; the editor's pack keeps them plain.
            try:
                table = mesh.colour_table(mesh.decompress(body))
            except (mesh.Malformed, ValueError, IndexError, mesh.lzx.LzxError):
                table = None
        if table:
            facts.setdefault("colours", []).append(table)
    # The item's own texture: a 33-byte header that starts 0x1A20, then DXT
    # pixels. Retail blocks are LZX-framed and the editor's pack keeps them
    # plain, so each block is tried as it stands and then decompressed. Block 2
    # is where it usually lives, but not always - so every block is checked.
    block_texture = None
    block_texture_id = None
    for block in blocks:
        ident, body = block[0], block[3]
        # The block as it stands, and the block unpacked if it is an LZX chain.
        # Any block can fail to be a chain; that is not an error, it just is not
        # the texture.
        blobs = [body]
        try:
            blobs.append(mesh.decompress(body))
        except (mesh.Malformed, ValueError, IndexError, mesh.lzx.LzxError):
            pass
        for blob in blobs:
            if not blob or len(blob) < 33:
                continue
            # A magic in the middle of vertex data is not a header, so every
            # candidate is tested and the first one that actually parses wins -
            # stopping at the first magic abandons the real header behind it.
            candidates = [0] if struct.unpack_from("<H", blob, 1)[0] == 0x1A20 else []
            for at in range(1, len(blob) - 33):
                if blob[at] == 0x20 and blob[at + 1] == 0x1A:
                    candidates.append(at - 1)
                    if len(candidates) > 64:
                        break
            for start in candidates:
                texture = mesh.texture_from_block(blob[start:])
                if texture:
                    block_texture = texture
                    block_texture_id = ident
                    facts["texture_offset"] = start
                    break
            if block_texture:
                break
        if block_texture:
            break

    payload = next((block[3] for block in blocks if block[0] == 3), None)
    if payload is None:
        # An avatar container, but it holds no item model - not an item either.
        facts["model"]["error"] = NOT_AVATAR
        return facts, None

    # Retail blocks are LZX-framed inside the STRB; the editor's pack stores
    # its blocks plain, so this step is what makes a retail item readable.
    try:
        inner = mesh.decompress(payload)
        batches = mesh.read_model(inner)
    except mesh.Malformed as exc:
        facts["model"]["error"] = str(exc)
        return facts, None
    if not batches:
        facts["model"]["error"] = "no triangle batches"
        return facts, None

    facts["fingerprint"] = hashlib.sha1(inner).hexdigest()
    facts["model"] = model_facts(batches)

    # The model's own texture table is authoritative: it is the item saying which
    # slots it has, how big they are and whether they hold anything. A table of
    # empty slots means there is no base map, and no scan of the block's bytes
    # can turn that into one. Only a model with no table at all falls back to the
    # block scan.
    table = [entry for batch in batches for entry in (batch.get("textures") or [])]
    facts["texture_slots"] = [{"empty": bool(entry.get("empty")),
                               "width": entry.get("width"),
                               "height": entry.get("height"),
                               "format": entry.get("format")}
                              for entry in table]
    # Reading the table by role, not by "first slot with pixels": an item's tint
    # mask (role 2) is exactly the data Halo's colour-change channel holds, and
    # treating it as the base map loses it.
    roles = slot_textures(mesh, batches)
    facts["texture_roles"] = [{"role": role, "slot": entry["slot"],
                               "width": entry["width"], "height": entry["height"],
                               "format": entry["format"]}
                              for role, entry in sorted(roles.items())]
    base = roles.get(1)
    if base:
        facts["texture"] = texture_facts(base)
        facts["texture_block"] = 3
        facts["texture_source"] = "its own base colour texture, slot %d" % base["slot"]
        if 2 in roles:
            facts["tint_texture"] = texture_facts(roles[2])
    else:
        from_table = texture_from_model(mesh, batches)
        if from_table:
            facts["texture"] = from_table
            facts["texture_block"] = 3
            facts["texture_source"] = "the model's own texture table"
        elif not table and block_texture:
            facts["texture"] = block_texture
            facts["texture_block"] = block_texture_id
            facts["texture_source"] = "block %s" % block_texture_id
    return facts, batches


def wanted(item_id, name, needles):
    if not needles:
        return True
    haystack = (item_id + " " + (name or "")).lower()
    return any(needle.lower() in haystack for needle in needles)


# --------------------------------------------------------------------- images

# Writing the base map in the three formats people ask for, with no library: a
# PNG through zlib, an uncompressed TGA, and a baseline RGB+alpha TIFF.

def write_png(path, rgba, width, height):
    """8-bit RGBA PNG, one filtered row at a time."""
    raw = bytearray()
    stride = width * 4
    for row in range(height):
        raw.append(0)
        raw += rgba[row * stride:(row + 1) * stride]

    def chunk(tag, body):
        return (struct.pack(">I", len(body)) + tag + body
                + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF))

    data = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + chunk(b"IEND", b""))
    with open(path, "wb") as handle:
        handle.write(data)


def write_swatches(path, colours, cell=40, gap=5):
    """The palette as chips, three across: the page the editor itself draws."""
    columns = min(3, len(colours)) or 1
    rows = (len(colours) + columns - 1) // columns
    width = columns * cell + (columns + 1) * gap
    height = rows * cell + (rows + 1) * gap
    canvas = bytearray(b"\x2a\x2a\x2e\xff" * (width * height))
    for index, colour in enumerate(colours):
        row, column = divmod(index, columns)
        x0 = gap + column * (cell + gap)
        y0 = gap + row * (cell + gap)
        pixel = bytes((colour[0], colour[1], colour[2], 255))
        for y in range(y0, y0 + cell):
            start = (y * width + x0) * 4
            canvas[start:start + cell * 4] = pixel * cell
    write_png(path, bytes(canvas), width, height)


def table_colours(table):
    """The colours a table offers, palette first and base colours otherwise."""
    return table["colours"] or [rgb for rgb, alpha in table["bases"] if alpha]


def swatch_colours(table):
    """The chips to draw: the base colour, then every swatch the table offers.

    A full table is one base colour and up to nine choosable swatches, so the
    base belongs on the sheet too - it is the colour the item is drawn in.
    """
    palette = table["colours"]
    bases = [rgb for rgb, alpha in table["bases"] if alpha]
    if palette:
        return bases[:1] + list(palette)
    return bases


def hex_and_float(rgb):
    """A colour the way the table reads it: hex, then the 0..1 triples."""
    return "#%02X%02X%02X  %.4f %.4f %.4f" % (rgb[0], rgb[1], rgb[2],
                                             rgb[0] / 255.0, rgb[1] / 255.0,
                                             rgb[2] / 255.0)


def write_colours(path, title, source, tables):
    """The colour tables as text: every colour as hex, in the order stored."""
    lines = ["%s - colours" % title, ""]
    if tables:
        lines.append("source : %s, STRB block 7 (CustomColorTable)" % source)
        lines.append("tables : %d" % len(tables))
    else:
        lines.append("source : %s, no CustomColorTable (block 7)" % source)
        lines.append("")
        lines.append("No colour table in this container, so there is no palette to")
        lines.append("draw: this item's colours are baked into its own art (SP).")
    for index, table in enumerate(tables):
        palette = table["colours"]
        bases = [rgb for rgb, alpha in table["bases"] if alpha]
        lines.append("")
        if palette:
            lines.append("table %d: base + %d swatch%s"
                         % (index, len(palette), "" if len(palette) == 1 else "es"))
        else:
            lines.append("table %d: no swatches - the base colour only" % index)
        if bases:
            lines.append("base    %s" % hex_and_float(bases[0]))
        for number, rgb in enumerate(palette, 1):
            lines.append("swatch%d %s" % (number, hex_and_float(rgb)))
    lines.append("")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")


def batch_colour(batch):
    """The batch's own surface colour, when the item states one.

    A material record of kind "vector" is a float4 parameter, and a non-zero one
    is the part's colour. Most items leave them zero, which means the part has no
    colour of its own and takes the item's.
    """
    for material in batch.get("materials") or []:
        if material.get("kind") != "vector" or not material.get("value"):
            continue
        value = [float(channel) for channel in material["value"][:3]]
        if not any(value):
            continue
        if any(channel != channel for channel in value):   # NaN
            continue
        return tuple(max(0.0, min(1.0, channel)) for channel in value)
    return None


def item_colour(tables):
    """The item's own colour, or clay when the file states none.

    The base entry of a colour table is what the item is drawn in; without a
    table the item has no colour at all, and #CCCCCC says that plainly rather
    than inventing one.
    """
    for table in tables or []:
        for rgb, _alpha in table.get("bases") or []:
            return tuple(rgb)
        colours = table_colours(table)
        if colours:
            return tuple(colours[0])
    return (204, 204, 204)


def write_report(path, stem, source, size, facts, batches, texture, tables):
    """What the container actually held, written before any Blender runs.

    This is the extractor's own account: the blocks and their sizes, the mesh
    counts, the texture slots the model declares, and whether a base map or a
    colour table was found. It is written whether or not Blender is installed,
    so a run without it still says what was in the file.
    """
    lines = [stem, ""]
    lines.append("source:    %s ({:,} bytes)".format(size) % source)
    if facts.get("asset_from"):
        lines.append("asset:     %s - the newest revision in the package"
                     % facts["asset_from"])
    blocks = facts.get("blocks") or []
    lines.append("blocks:    %d" % len(blocks))
    for block in blocks:
        lines.append("           id %-3s %-22s %9s bytes  starts %s"
                     % (block["id"], block.get("name", ""), block["size"],
                        block.get("head", "")))
    if not blocks:
        lines.append("           (no STRB container: read as a bare model)")
    for block in facts.get("unread") or []:
        lines.append("           block %-2d %s, %d bytes - %s"
                     % (block["block"], block["name"], block["bytes"], block["why"]))
    meta = facts.get("metadata")
    if meta:
        described = "%s, %s (%s %s), subcategory %s" % (
            meta["gender"], meta["asset_type"], meta["component"],
            meta["component_mask"], meta["subcategory"])
        if meta.get("version") is not None:
            described += ", %s skeleton, metadata version %d" % (
                meta["skeleton"], meta["version"])
        lines.append("metadata:  %s" % described)
    shape = facts.get("shape")
    if shape:
        lines.append("shape:     hides %d %s triangle(s), %d vertex override(s)"
                     % (shape["triangles"], shape["target"],
                        shape["vertex_overrides"]))
    skeleton = facts.get("skeleton")
    if skeleton:
        lines.append("skeleton:  %d bones, %d root(s)"
                     % (skeleton["bones"], skeleton["roots"]))

    model = facts.get("model") or {}
    if model.get("parses"):
        lines.append("mesh:      %d verts, %d tris, %d batch(es), %d uv set(s)"
                     % (model.get("vertices") or 0, model.get("triangles") or 0,
                        model.get("batches") or 0, model.get("uv_sets") or 0))
    else:
        lines.append("mesh:      did not parse (%s)"
                     % (model.get("error") or "unknown"))
    lines.append("texture slots declared: %d" % (model.get("textures") or 0))
    for index, slot in enumerate(facts.get("texture_slots") or []):
        kind = ("DXT5" if slot.get("format") == 0x14 else
                "DXT1" if slot.get("format") == 0x12 else
                "format 0x%02X" % (slot.get("format") or 0))
        lines.append("           slot %d: %sx%s %s%s"
                     % (index, slot.get("width"), slot.get("height"), kind,
                        "  (empty)" if slot.get("empty") else ""))

    if texture:
        lines.append("base map:  %dx%d %s from %s, written as .png, .tga and .tif"
                     % (texture["width"], texture["height"],
                        "DXT5" if texture["format"] == 0x14 else "DXT1",
                        facts.get("texture_source")
                        or "block %s" % facts.get("texture_block")))
    else:
        lines.append("base map:  none - the item carries no texture")
        lines.append("           its colour is written as %s colour.png/.tga/.tif"
                     % stem)
    lines.append("change colour: %s change colour.png/.tga/.tif - white takes the"
                 " team colour; this is the alpha channel of the multipurpose map"
                 " on Halo CE (blue on the original Xbox). The white is painted"
                 " where the item's own UV layout has geometry, so the mask sits"
                 " on its islands the way the base map does" % stem)
    lines.append("multipurpose: %s multipurpose.png/.tga/.tif - Halo CE order:"
                 " red detail, green self-illumination, blue specular,"
                 " alpha colour change" % stem)
    lines.append("              %s multipurpose xbox.png/.tga/.tif - the same masks in"
                 " the original Xbox order: red specular, green"
                 " self-illumination, blue colour change, alpha detail" % stem)
    lines.append("              %s multipurpose sp.png/.tga/.tif - nothing masked, so the"
                 " item keeps its own colour; every channel is zero, which"
                 " makes it valid in either order" % stem)
    if facts.get("mask_source"):
        lines.append("mask source: %s" % facts["mask_source"])
    lines.append("")
    lines.append("The folder is laid out for the program you open it in:")
    lines.append("  %s\\  %s.obj and .mtl, with every texture as .png and .tga"
                 % (MAX_DIR, stem))
    lines.append("  %s\\  the rigs (.blend, and .fbx/.glb), with the same"
                 " textures" % BLENDER_DIR)
    lines.append("  %s\\pc\\   data\\ the bitmaps tool.exe compiles, as .tif"
                 " in Halo CE's" % HEK_DIR)
    lines.append("            channel order, and the .jms; tags\\ where tool.exe"
                 " writes what it builds")
    lines.append("  %s\\xbox\\ the same bitmaps in the original Xbox channel"
                 " order, and the same .jms" % HEK_DIR)
    lines.append("")
    lines.append("multipurpose channels - the model shader packs four greyscale masks")
    lines.append("into one bitmap, and which channel holds which depends on the")
    lines.append("platform you are building for:")
    lines.append("")
    lines.append("  channel   Xbox                  Halo CE / HEK")
    lines.append("  red       specular/reflection   detail mask")
    lines.append("  green     self-illumination     self-illumination")
    lines.append("  blue      color change          specular")
    lines.append("  alpha     detail                color change")
    lines.append("")
    lines.append("  multipurpose.png is the Halo CE order; multipurpose xbox.png")
    lines.append("  is the Xbox order; multipurpose sp.png has every channel at")
    lines.append("  zero, so it is valid in either order and leaves the colour alone.")
    lines.append("  Colour change is the item's own UV coverage. Detail, specular and")
    lines.append("  self-illumination are zero: an item does not say which parts are")
    lines.append("  shiny, glow or take a detail map, and inventing that would put")
    lines.append("  someone else's look on the item.")
    lines.append("")
    lines.append("Both builds are ready; which one the item was is not recorded in")
    lines.append("the file, so pick the one you are making:")
    lines.append("  fixed colour : base map only (the colour image above). The item")
    lines.append("                 keeps the colour it was drawn in.")
    lines.append("  team colour  : the same base map, with the multipurpose map in the")
    lines.append("                 shader's multipurpose slot. Its alpha marks what takes")
    lines.append("                 the player's colour.")

    if tables:
        for index, table in enumerate(tables):
            swatches = table.get("colours") or []
            base = [rgb for rgb, alpha in table["bases"] if alpha][:1]
            lines.append("colour table %d: base %s, %d swatch(es)%s"
                         % (index,
                            " ".join("#%02X%02X%02X" % tuple(rgb) for rgb in base)
                            or "none",
                            len(swatches),
                            (" - " + " ".join("#%02X%02X%02X" % tuple(rgb)
                                             for rgb in swatches))
                            if swatches else ""))
    else:
        lines.append("colour table: none in this file (no block 7)")
        lines.append("item colour:  clay (no colour in the file)")

    for index, batch in enumerate(batches or []):
        lines.append("")
        lines.append("part %d" % index)
        lines.append("  shader %s" % batch.get("shader_id"))
        for record in batch.get("materials") or []:
            if record.get("kind") == "texture":
                lines.append("  texture %s bound to uv%s"
                             % (record.get("texture"), record.get("uv_set") or 0))
    lines.append("")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")


def write_tga(path, rgba, width, height):
    """Uncompressed 32-bit TGA, BGRA, top-left origin."""
    body = bytearray(rgba)
    body[0::4], body[2::4] = body[2::4], body[0::4]
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    with open(path, "wb") as handle:
        handle.write(header + bytes(body))


def write_tiff(path, rgba, width, height):
    """Baseline little-endian TIFF, 8 bits per channel, RGBA, one strip."""
    entries = [
        (256, 4, [width]),            # ImageWidth
        (257, 4, [height]),           # ImageLength
        (258, 3, [8, 8, 8, 8]),       # BitsPerSample
        (259, 3, [1]),                # Compression: none
        (262, 3, [2]),                # Photometric: RGB
        (273, 4, [0]),                # StripOffsets, filled in below
        (277, 3, [4]),                # SamplesPerPixel
        (278, 4, [height]),           # RowsPerStrip
        (279, 4, [len(rgba)]),        # StripByteCounts
        (284, 3, [1]),                # PlanarConfiguration: chunky
        (338, 3, [2]),                # ExtraSamples: unassociated alpha
    ]
    width_bytes = {3: 2, 4: 4}
    ifd_size = 2 + 12 * len(entries) + 4
    overflow_at = 8 + ifd_size
    overflow = bytearray()
    table = bytearray()
    for tag, kind, values in entries:
        blob = b"".join(struct.pack("<H" if kind == 3 else "<I", value) for value in values)
        if len(blob) <= 4:
            payload = blob + b"\x00" * (4 - len(blob))
        else:
            payload = struct.pack("<I", overflow_at + len(overflow))
            overflow += blob
        table += struct.pack("<HHI", tag, kind, len(values)) + payload
    pixels_at = overflow_at + len(overflow)
    # The strip offset is the one value only known once everything else is placed.
    table = bytearray(table)
    for index, (tag, kind, values) in enumerate(entries):
        if tag == 273:
            at = index * 12 + 8
            table[at:at + 4] = struct.pack("<I", pixels_at)
    data = (b"II*\x00" + struct.pack("<I", 8)
            + struct.pack("<H", len(entries)) + bytes(table) + struct.pack("<I", 0)
            + bytes(overflow) + rgba)
    with open(path, "wb") as handle:
        handle.write(data)


# --------------------------------------------------------------------- output

def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Extract avatar items. With no source argument it finds "
                    "them itself and extracts everything it finds.")
    parser.add_argument("source", nargs="?", default=None,
                        help="optional: one folder or one item file to use instead")
    parser.add_argument("out", nargs="?", default=None, help="output folder (default: extracted)")
    parser.add_argument("--out", dest="out_option", default=None, help="output folder")
    parser.add_argument("--obj", action="store_true", help="write each model as .obj")
    parser.add_argument("--only", action="append", default=[], metavar="ID|NAME",
                        help="extract only ids or names containing this (repeatable)")
    parser.add_argument("--limit", type=int, default=0, help="stop after N items")
    parser.add_argument("--no-icons", action="store_true", help="do not copy icons")
    parser.add_argument("--root", action="append", default=[], help="search here (repeatable)")
    parser.add_argument("--mesh-dir", help="directory for the reader modules")
    args = parser.parse_args(argv)

    out = args.out_option or args.out or "extracted"

    if args.source:
        sources = [args.source]
        searched = []
    else:
        # A Windows folder ending in \ hands "...folder\" through as
        # ...folder" because the backslash escapes the closing quote, so a
        # stray quote can arrive here. Drop it rather than searching nowhere.
        searched = []
        seen = set()
        for root in (args.root or default_roots()):
            root = os.path.abspath(str(root).strip().strip('"'))
            key = os.path.normcase(root)
            if key not in seen:
                seen.add(key)
                searched.append(root)
        print("Looking for avatar items in:")
        for root in searched:
            print("  %s%s" % (root, "" if os.path.isdir(root) else "  (no such folder)"))
        sources = find_sources(searched)
        if not sources:
            print("")
            print("Nothing found. That folder holds no closet_index.tsv and no")
            print(".bin/.asset item files.")
            print("Put the items in that folder and run again.")
            for root in searched:
                if not os.path.isdir(root):
                    continue
                try:
                    names = sorted(n for n in os.listdir(root)
                                   if os.path.isfile(os.path.join(root, n)))
                except OSError:
                    continue
                if names:
                    print("")
                    print("It does hold these files, though:")
                    for name in names[:12]:
                        print("    %s" % name)
            return 4
        print("")
        print("Found %d item source%s:" % (len(sources), "" if len(sources) == 1 else "s"))
        for source in sources:
            print("  %s  (%s)" % (source, describe_source(source)))
        print("")

    mesh = load_mesh(args.mesh_dir)
    # Everything goes straight into the one folder: no items\, no icons\.
    items_dir = icons_dir = out
    os.makedirs(out, exist_ok=True)

    records = []
    failures = []
    not_avatar = 0
    seen_ids = set()
    seen_models = set()
    used_stems = set()
    parsed = icons = obj_files = skipped = textures = colour_tables = 0

    # The numbering runs across the whole run, so two unnamed items in two
    # different folders cannot both become extracted1.
    unnamed = fallback_names()
    for source in sources:
        entries = collect(source, unnamed)
        if not entries:
            print("  %s holds nothing to extract, skipping" % source)
            continue
        # Containers first. When a folder holds both a wrapped item and the
        # bare model block it contains (asset_v2.bin and asset.bin), the
        # wrapped one is the richer record and wins; the bare copy is skipped.
        entries = sorted(entries, key=lambda entry: 0 if wrapped(entry[4]) else 1)
        for item_id, categories, bodies, name, path in entries:
            if not wanted(item_id, name, args.only):
                continue
            if args.limit and len(records) >= args.limit:
                break
            if item_id in seen_ids:
                skipped += 1
                continue
            seen_ids.add(item_id)

            if not os.path.exists(path):
                failures.append((item_id, "no %s" % os.path.basename(path)))
                continue
            with open(path, "rb") as handle:
                data = handle.read()

            package = None
            facts, batches = summarise(mesh, data)
            # An avatar item downloads as an Xbox 360 package: the container is
            # not the file, it is inside it, as asset.bin or asset_v2.bin.
            if not facts.get("avatar") and data[:4] in STFS_MAGIC:
                package = stfs_files(data)
                # Both revisions are in there; take the newer one, and take it
                # from the package's bytes as well as its file table, because a
                # dump's table does not always line up with its data area.
                chosen = choose_asset(mesh, data, package)
                if chosen is not None:
                    facts, batches, from_asset = chosen
                    facts["bytes"] = len(data)
                    facts["package"] = True
                    facts["asset_from"] = from_asset
                else:
                    asset = pick_asset(package or {})
                    facts["package_listing"] = package_listing(package)
                    facts["package_head"] = asset[:12].hex(" ") if asset else ""
            if package and not facts.get("texture"):
                raw = package_texture(package)
                if raw:
                    texture = mesh.texture_from_block(raw)
                    if texture:
                        facts["texture"] = texture

            # One model, one .obj: the same bytes under a second name (a bare
            # asset.bin next to asset_v2.bin) must not be written twice.
            fingerprint = facts.get("fingerprint")
            if fingerprint:
                # Two formats of one item sit in the same folder (asset.bin and
                # asset_v2.bin) and must not be written twice. Two items in
                # different folders can hold the same model and still be two
                # items - two colour variants of one garment do exactly that -
                # so the folder is part of what is compared. Comparing the model
                # bytes alone dropped the second item without a word.
                key = (os.path.abspath(source), fingerprint)
                if key in seen_models:
                    skipped += 1
                    continue
                seen_models.add(key)
            # Block 7 is the CustomColorTable. Whether the item it belongs to
            # was a team-colour item is not written anywhere in the file: a table
            # can hold a full palette or a single placeholder entry, and the
            # marketplace sold items both ways. So nothing here decides it. What
            # the item holds is recorded, and every item gets the texture for a
            # fixed colour and the mask for a team colour; the person building
            # the map picks.
            block_ids = {block["id"] for block in facts["blocks"]}
            swatch_count = sum(len(table.get("colours") or [])
                               for table in (facts.get("colours") or []))
            title, title_source = item_title(name, path, item_id)
            # One name for every file the item writes: its title, or the id when
            # nothing names it. A title already used in this run falls back to
            # the id, so two "Test Shirt"s cannot overwrite each other.
            stem = safe_folder(title or item_id) or item_id
            if stem.lower() in used_stems:
                stem = item_id
            if stem.lower() in used_stems:
                stem = "%s %s" % (item_id, len(used_stems) + 1)
            used_stems.add(stem.lower())
            record = {
                "id": item_id,
                "name": name or "",
                "title": title,
                "title_source": title_source,
                "categories": categories,
                "bodies": bodies,
                "file": os.path.basename(path),
                "source": os.path.dirname(path) or ".",
                "bytes": facts["bytes"],
                "blocks": facts["blocks"],
                "avatar_content": facts["avatar"],
                "bare_model": facts.get("bare", False),
                "colour_table": {"present": 7 in block_ids,
                                 "swatches": swatch_count},
                "model": facts["model"],
                "icon": None,
                "obj": None,
                "mtl": None,
                "texture": None,
            }

            if batches:
                parsed += 1
                if args.obj:
                    target = os.path.join(items_dir, stem + ".obj")
                    # Retail items are already y-up: feet at y = 0, head near 1.6.
                    material = stem + ".mtl"
                    # The material always names an image. Importers drop a bare
                    # Kd often enough that a colour carried only in the .mtl goes
                    # missing, so an item with no texture gets its own colour as
                    # an image instead - which is also Halo CE's bitmap source.
                    map_name = ("%s base map.png" % stem if facts.get("texture")
                                else "%s colour.png" % stem)
                    # Taken before write_obj, which regroups the UVs in place into
                    # one list per set - read afterwards, this indexes the wrong
                    # thing and carries the wrong coordinates.
                    extra_uv = extra_uv_sets(batches)
                    # One colour per batch. Armour, skin and gear are separate
                    # batches, so a model whose parts differ keeps them apart
                    # instead of arriving as a single flat colour.
                    fallback = item_colour(facts.get("colours") or [])
                    batch_colours = []
                    for batch in batches:
                        own = batch_colour(batch)
                        batch_colours.append(
                            tuple(int(round(channel * 255.0)) for channel in own)
                            if own else fallback)
                    unique = []
                    for rgb in batch_colours:
                        if rgb not in unique:
                            unique.append(rgb)
                    maps = None
                    if len(unique) > 1:
                        # Distinct parts, distinct colours: each needs its own
                        # flat image, because one map_Kd paints them all alike.
                        maps = []
                        for rgb in batch_colours:
                            name = ("%s colour %02X%02X%02X.png"
                                    % (stem, rgb[0], rgb[1], rgb[2]))
                            image_path = os.path.join(items_dir, name)
                            if not os.path.exists(image_path):
                                write_png(image_path,
                                          (bytes(rgb) + b"\xff") * (64 * 64), 64, 64)
                            maps.append(name)
                        record["part_colours"] = ["#%02X%02X%02X" % rgb
                                                  for rgb in batch_colours]
                    mesh.write_obj(target, batches, up_axis="y", material=material)
                    mesh.write_mtl(os.path.join(items_dir, material), batches,
                                   map_name=map_name, colours=batch_colours, maps=maps)
                    record["obj"] = "%s.obj" % stem
                    record["mtl"] = "%s" % material
                    obj_files += 1
                    # An OBJ cannot hold a second UV set; the Blender file can,
                    # so the extra sets travel beside it rather than being lost.
                    if extra_uv:
                        record["uv_sets"] = extra_uv
            else:
                reason = facts["model"].get("error", "unknown")
                if reason == NOT_AVATAR:
                    not_avatar += 1
                failures.append((item_id, reason))
                print("  %s: blocks %s"
                      % (item_id, " ".join(str(b["id"]) for b in facts["blocks"]) or "none"))
                if facts.get("package_listing"):
                    print("  %s is a package holding: %s"
                          % (item_id, ", ".join(facts["package_listing"])))
                elif facts.get("package_head"):
                    print("  %s: package read, its asset starts %s"
                          % (item_id, facts["package_head"]))

            if not args.no_icons:
                for icon_source in icon_candidates(path, item_id):
                    if os.path.exists(icon_source):
                        shutil.copyfile(icon_source, os.path.join(icons_dir, stem + ".png"))
                        record["icon"] = "%s.png" % stem
                        icons += 1
                        break
                if not record["icon"] and package:
                    for name in sorted(package):
                        if name.lower().endswith(".png"):
                            with open(os.path.join(icons_dir, stem + ".png"), "wb") as handle:
                                handle.write(package[name])
                            record["icon"] = "%s.png" % stem
                            icons += 1
                            break
                if not record["icon"] and data[:4] in STFS_MAGIC:
                    # No file table, but the icon is a PNG in there regardless.
                    png = package_png(data)
                    if png:
                        with open(os.path.join(icons_dir, stem + ".png"), "wb") as handle:
                            handle.write(png)
                        record["icon"] = "%s.png" % stem
                        icons += 1

            texture = facts.get("texture")
            if texture:
                base = os.path.join(out, "%s base map" % stem)
                write_png(base + ".png", texture["rgba"], texture["width"], texture["height"])
                write_tga(base + ".tga", texture["rgba"], texture["width"], texture["height"])
                write_tiff(base + ".tif", texture["rgba"], texture["width"], texture["height"])
                record["texture"] = {
                    "png": "%s base map.png" % stem,
                    "tga": "%s base map.tga" % stem,
                    "tif": "%s base map.tif" % stem,
                    "width": texture["width"],
                    "height": texture["height"],
                    "format": "DXT5" if texture["format"] == 0x14 else "DXT1",
                    "bytes": texture["pixels"],
                    "block": facts.get("texture_block"),
                }
                textures += 1
            elif facts["blocks"]:
                print("  %s: blocks %s, no texture in any of them"
                      % (item_id, " ".join(str(b["id"]) for b in facts["blocks"])))
                for block in facts["blocks"]:
                    print("      id %-4s %8s bytes, starts %s"
                          % (block["id"], block["size"], block.get("head", "")))

            if not texture:
                # No pixels anywhere in the item - which is every garment: they
                # declare texture slots and ship none. Its own colour is written
                # as a real image so the material survives import, and so Halo CE
                # has a .tif to build a bitmap from. Flat, 64x64, the same colour
                # in all three formats.
                rgb = item_colour(facts.get("colours") or [])
                rgba = (bytes(rgb) + b"\xff") * (64 * 64)
                flat = os.path.join(out, "%s colour" % stem)
                write_png(flat + ".png", rgba, 64, 64)
                write_tga(flat + ".tga", rgba, 64, 64)
                write_tiff(flat + ".tif", rgba, 64, 64)
                record["colour_image"] = {
                    "png": "%s colour.png" % stem,
                    "tga": "%s colour.tga" % stem,
                    "tif": "%s colour.tif" % stem,
                    "hex": "#%02X%02X%02X" % tuple(rgb),
                }

            # Halo's model shader packs four greyscale masks into one bitmap.
            # The Gearbox port - Halo PC, Custom Edition, and the HEK that
            # builds their bitmaps - keeps them in this order, which is not the
            # order the original Xbox used:
            #
            #            red      green             blue      alpha
            #   Halo CE  detail   self-illumination specular  colour change
            #   Xbox     specular self-illumination colour... detail
            #
            # The colour change mask is what turns a biped into the player's
            # team colour, so it is white: the whole item takes the colour. A
            # part that must keep its own needs painting black there, and nothing
            # in an item file says which parts those would be. Shiny and glowing
            # parts are equally unstated, so specular and self-illumination are
            # zero - matte and unlit - rather than invented.
            # The masks are painted where the item's own UV layout has geometry,
            # because the shader samples them in the base map's texture space: an
            # island-shaped mask lines up with the model, a flat fill only looks
            # the same where there happens to be geometry under it.
            # The PNG is the one a person looks at and keeps, so it is 1024 and
            # compresses to a few kilobytes. The .tga and .tif are the same mask
            # uncompressed - at 1024 that is 4 MB each, four masks, three
            # formats, six copies: 40-odd MB an item. They are the files that go
            # into tool.exe or a legacy slot, where 256 is plenty, so they are
            # written at 256 instead.
            png_size = 1024
            small_size = 256
            tint = facts.get("tint_texture")
            if tint:
                # The item ships its own tint mask: this is the real colour-change
                # data, painted by whoever made the item, not derived from geometry.
                big = mask_from_texture(tint, png_size)
                small = mask_from_texture(tint, small_size)
                source = ("the item's own tint mask, slot %s, %dx%d, red channel"
                          % (tint.get("slot"), tint["width"], tint["height"]))
            else:
                big = small = None
                source = "the item's own UV layout"
            if big is None:
                big, painted = mesh.uv_coverage(batches, png_size)
                small = mesh.uv_coverage(batches, small_size)[0]
                if not painted:
                    # No usable UVs. A blanket fill means the same thing in play
                    # - the shader only samples texels with geometry over them.
                    big = b"\xff" * (png_size * png_size)
                    small = b"\xff" * (small_size * small_size)
                    painted = png_size * png_size
            else:
                painted = sum(1 for value in big if value)
            facts["mask_source"] = source

            def mask_with(channel, size, data):
                """One mask byte a texel in `channel`, the other channels zero."""
                packed = bytearray(size * size * 4)
                packed[channel::4] = data
                return bytes(packed)

            def write_mask(path_base, suffix, channel):
                write_png(path_base + ".png", mask_with(channel, png_size, big),
                          png_size, png_size)
                write_tga(path_base + ".tga",
                          mask_with(channel, small_size, small),
                          small_size, small_size)
                write_tiff(path_base + ".tif",
                           mask_with(channel, small_size, small),
                           small_size, small_size)

            mask = os.path.join(out, "%s change colour" % stem)
            write_mask(mask, "change colour", 3)
            record["change_colour"] = {
                "png": "%s change colour.png" % stem,
                "tga": "%s change colour.tga" % stem,
                "tif": "%s change colour.tif" % stem,
                "channel": "alpha of the multipurpose map on Halo CE, "
                           "blue on the original Xbox",
                "meaning": "white = takes the team colour",
                "png_size": png_size,
                "tga_tif_size": small_size,
                "source": source,
                "coverage": round(painted / float(png_size * png_size), 3),
            }
            multipurpose = os.path.join(out, "%s multipurpose" % stem)
            write_mask(multipurpose, "multipurpose", 3)
            record["multipurpose"] = {
                "png": "%s multipurpose.png" % stem,
                "tga": "%s multipurpose.tga" % stem,
                "tif": "%s multipurpose.tif" % stem,
                "channels": "Halo CE: red detail, green self-illumination, "
                            "blue specular, alpha colour change",
                "xbox_order": "red specular, green self-illumination, "
                              "blue colour change, alpha detail",
                "png_size": png_size,
                "tga_tif_size": small_size,
                "painted": "the item's own UV layout",
                "coverage": round(painted / float(png_size * png_size), 3),
            }
            # The same masks in the original Xbox channel order, rather than
            # only a note saying they are different. Colour change moves from
            # alpha to blue and the auxiliary (detail) mask takes the alpha
            # slot - zero here, because an item never says where a detail map
            # would go. H1A reads this order when the shader's "multipurpose
            # map uses og xbox channel order" flag (0x40) is set; Halo CE and
            # the legacy HEK always read Gearbox order, so both are written.
            multipurpose_xbox = os.path.join(out, "%s multipurpose xbox" % stem)
            write_mask(multipurpose_xbox, "multipurpose xbox", 2)
            record["multipurpose_xbox"] = {
                "png": "%s multipurpose xbox.png" % stem,
                "tga": "%s multipurpose xbox.tga" % stem,
                "tif": "%s multipurpose xbox.tif" % stem,
                "channels": "Xbox: red specular, green self-illumination, "
                            "blue colour change, alpha detail",
                "use": "H1A with the og-xbox-channel-order flag (0x40) set",
                "png_size": png_size,
                "tga_tif_size": small_size,
                "coverage": round(painted / float(png_size * png_size), 3),
            }
            # Single player: no mask lit, so nothing takes a colour and the item
            # keeps the one it was drawn in. Every channel is zero, so the image
            # is identical in either channel order - one set covers both.
            multipurpose_sp = os.path.join(out, "%s multipurpose sp" % stem)
            write_png(multipurpose_sp + ".png",
                      b"\x00\x00\x00\x00" * (png_size * png_size),
                      png_size, png_size)
            write_tga(multipurpose_sp + ".tga",
                      b"\x00\x00\x00\x00" * (small_size * small_size),
                      small_size, small_size)
            write_tiff(multipurpose_sp + ".tif",
                       b"\x00\x00\x00\x00" * (small_size * small_size),
                       small_size, small_size)
            record["multipurpose_sp"] = {
                "png": "%s multipurpose sp.png" % stem,
                "tga": "%s multipurpose sp.tga" % stem,
                "tif": "%s multipurpose sp.tif" % stem,
                "meaning": "no masks: the item keeps its own colour",
                "use": "a single-player build; valid in either channel order",
            }

            # Every item says what its colours are: a chip card and a hex list
            # when the container carries a table, and a note when it does not.
            tables = facts.get("colours") or []
            sheets = []
            for index, table in enumerate(tables):
                colours = table_colours(table)
                if not colours:
                    continue
                name = "colour_%02d.png" % index
                write_swatches(os.path.join(out, name), swatch_colours(table))
                sheets.append(name)
            text_name = "%s_colours.txt" % stem
            write_colours(os.path.join(out, text_name), stem,
                          os.path.basename(path), tables)
            record["colours"] = {
                "png": sheets,
                "txt": text_name,
                "tables": [
                    {"count": table["count"],
                     "palette": bool(table["colours"]),
                     "hex": ["#%02X%02X%02X" % tuple(rgb)
                             for rgb in swatch_colours(table)]}
                    for table in tables],
            }
            colour_tables += len(tables)

            # Every block is read. The model and the colour table become files;
            # the metadata and shape blocks become facts, in the report and the
            # catalogue; a block this build does not know is named there with
            # its size. None of them is dumped as a file - a bag of raw bytes is
            # not something anyone opening the item can use, and it was never
            # anything but a copy of bytes the container still has.
            for ident, body, _count in facts.get("block_data") or []:
                if ident in (3, 7):
                    continue
                why = "no reader for this block"
                try:
                    if ident in (6, 8):
                        facts["metadata"] = mesh.read_metadata(
                            body, versioned=(ident == 8))
                        record["metadata"] = facts["metadata"]
                        continue
                    if ident == 4:
                        facts["shape"] = mesh.read_shape_overrides(body)
                        record["shape"] = facts["shape"]
                        continue
                    if ident == 5:
                        facts["skeleton"] = mesh.read_skeleton(body)
                        record["skeleton"] = facts["skeleton"]
                        continue
                except Exception as exc:
                    why = str(exc)
                facts.setdefault("unread", []).append(
                    {"block": ident,
                     "name": mesh.BLOCK_NAMES.get(ident, "unknown"),
                     "bytes": len(body), "why": why})

            write_report(os.path.join(out, "report.txt"), stem,
                         os.path.basename(path), facts.get("bytes") or 0,
                         facts, batches, texture, tables)
            records.append(record)
            if len(records) % 500 == 0:
                print("  %d items..." % len(records))

    # One pass at the end: every file exists by now, so the item's folder can be
    # sorted for the program the person opening it uses, and the catalogue can
    # say where each file actually is.
    organise(out)
    for record in records:
        for key in ("obj", "mtl"):
            if record.get(key):
                record[key] = MAX_DIR + "/" + record[key]
        for key in ("multipurpose", "multipurpose_xbox", "multipurpose_sp",
                    "change_colour"):
            paths = record.get(key)
            if not isinstance(paths, dict):
                continue
            for kind in ("png", "tga"):
                if paths.get(kind):
                    paths[kind] = MAX_DIR + "/" + paths[kind]
            tif = paths.get("tif")
            if tif:
                orders = mask_orders(tif)
                paths["tif"] = HEK_DIR + "/%s/data/%s" % (orders[0], tif)
                for order in orders[1:]:
                    paths["tif_%s" % order] = HEK_DIR + "/%s/data/%s" % (order, tif)

    out = titled_out(out, records)
    catalogue = {
        "searched": searched,
        "sources": [os.path.abspath(source) for source in sources],
        "items": records,
    }
    target = os.path.join(out, "catalogue.json")
    with open(target, "w", encoding="utf-8") as handle:
        json.dump(catalogue, handle, indent=1)

    print("")
    print("%d items written to %s" % (len(records), target))
    print("  folder: %s" % os.path.abspath(out))
    print("  %d models parse, %d icons copied, %d .obj files, %d base maps, "
          "%d colour tables" % (parsed, icons, obj_files, textures, colour_tables))
    if skipped:
        print("  %d duplicates skipped (same id or same model)" % skipped)
    swatches = sum(record.get("colour_table", {}).get("swatches", 0)
                   for record in records)
    if records:
        print("  colour tables are not classified: every item gets a texture for")
        print("  a fixed colour and a mask for a team colour, %d swatch(es) found"
              % swatches)
    if failures:
        print("  %d did not parse:" % len(failures))
        for item_id, reason in failures[:10]:
            print("    %s  %s" % (item_id, reason))
        if len(failures) > 10:
            print("    ... and %d more" % (len(failures) - 10))
    if not parsed and failures and not_avatar == len(failures):
        print("")
        print(NOT_AVATAR)
    # The .bat asks where the files ended up, so it can rig them there.
    state = globals().get("__state__")
    if isinstance(state, dict):
        state["out"] = os.path.abspath(out)
    return 0 if parsed else 3


if __name__ == "__main__":
    sys.exit(main())
