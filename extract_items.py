#!/usr/bin/env python3
"""Extract retail Xbox 360 avatar items into a catalogue and per-item files.

A retail closet folder (as shipped in the `Clean Slate NXE` dump and served by
the LIVE avatar service) holds three things:

    00000008-001f-62f1-c10d-7afc354107d4.bin      the item asset, YTGR/STRB
    icons/00000008-001f-62f1-c10d-7afc354107d4.png
    closet_index.tsv                              id, categories, bodies, name

Each item asset is a `STRB` container. Block 3 is the model, and in retail
assets that block is LZX-framed *inside* the container, where the editor's own
asset pack stores its blocks plain. So the model is:

    blocks = strb_blocks(data)
    payload = block 3
    batches = read_model(decompress(payload))

which yields, per batch: vertices, u16 triangle indices, UV sets, material
records, per-vertex joints and weights, shaders ids, and the item's bounds.

Usage:
    python extract_items.py <closet_dir> <out_dir> [options]

Options:
    --obj            also write each parsed model as <out>/items/<id>.obj
    --only ID|NAME   extract only matching ids or names (repeatable)
    --limit N        stop after N selected items
    --no-icons       do not copy icons
    --mesh-dir DIR   where avatar_mesh.py lives (default: ./vendor)

Writes:
    <out>/catalogue.json     one record per item: name, masks, blocks, geometry
    <out>/icons/<id>.png     copied when present
    <out>/items/<id>.obj     with --obj

Requires Python 3.8+. No third-party packages.
"""

import argparse
import json
import os
import shutil
import sys

INDEX = "closet_index.tsv"


# --------------------------------------------------------------- mesh reader

def load_mesh(explicit_dir=None):
    """Import avatar_mesh.py, which carries the STRB/LZX/model readers.

    It is not vendored here to keep this repo readable, so it is looked for in
    a few known places before giving up with instructions.
    """
    candidates = []
    if explicit_dir:
        candidates.append(explicit_dir)
    here = os.path.dirname(os.path.abspath(__file__))
    candidates += [
        os.path.join(here, "vendor"),
        here,
        os.path.join(here, "..", "UniKron", "avatar", "avatar_tools"),
        os.path.join(here, "..", "..", "avatar", "avatar_tools"),
        os.path.join(here, "..", "avatar", "avatar_tools"),
    ]
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
        "avatar_mesh.py not found (it holds the STRB/LZX/model readers).\n"
        "Run setup.bat (Windows) or setup.sh once, or pass --mesh-dir "
        "<path to a UniKron/avatar/avatar_tools checkout>."
    )


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


# ------------------------------------------------------------------ the item

def summarise(mesh, data):
    """Read one item: block table plus geometry, or the reason it failed."""
    facts = {"bytes": len(data), "blocks": [], "model": {"parses": False}}
    try:
        blocks = mesh.strb_blocks(data)
    except mesh.Malformed as exc:
        facts["model"]["error"] = "not a STRB container: %s" % exc
        return facts, None
    facts["blocks"] = [{"id": block[0], "size": block[1]} for block in blocks]

    payload = next((block[3] for block in blocks if block[0] == 3), None)
    if payload is None:
        facts["model"]["error"] = "no block 3 (the model block)"
        return facts, None

    # Retail blocks are LZX-framed inside the STRB; the editor's pack stores
    # its blocks plain, so this step is what makes a retail item readable.
    try:
        batches = mesh.read_model(mesh.decompress(payload))
    except mesh.Malformed as exc:
        facts["model"]["error"] = str(exc)
        return facts, None
    if not batches:
        facts["model"]["error"] = "no triangle batches"
        return facts, None

    points = [point for batch in batches for point in batch["vertices"]]
    bounds = [
        [round(min(p[axis] for p in points), 4), round(max(p[axis] for p in points), 4)]
        for axis in range(3)
    ]
    facts["model"] = {
        "parses": True,
        "batches": len(batches),
        "vertices": len(points),
        "triangles": sum(len(batch["indices"]) // 3 for batch in batches),
        "uv_sets": max((len(uv) for batch in batches for uv in batch["uvs"]), default=0),
        "textures": len(batches[0].get("textures") or []),
        "shader_ids": [batch["shader_id"] for batch in batches],
        # Item space, y up: feet sit at y = 0 and the head tops out near 1.6.
        "bounds": bounds,
    }
    return facts, batches


def wanted(item_id, name, needles):
    if not needles:
        return True
    haystack = (item_id + " " + (name or "")).lower()
    return any(needle.lower() in haystack for needle in needles)


# --------------------------------------------------------------------- output

def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Extract avatar items from a retail closet folder.")
    parser.add_argument("folder", help="folder holding closet_index.tsv and <id>.bin files")
    parser.add_argument("out", help="output folder")
    parser.add_argument("--obj", action="store_true", help="write each model as .obj")
    parser.add_argument("--only", action="append", default=[], metavar="ID|NAME",
                        help="extract only ids or names containing this (repeatable)")
    parser.add_argument("--limit", type=int, default=0, help="stop after N items")
    parser.add_argument("--no-icons", action="store_true", help="do not copy icons")
    parser.add_argument("--mesh-dir", help="directory holding avatar_mesh.py")
    args = parser.parse_args(argv)

    if not os.path.exists(os.path.join(args.folder, INDEX)):
        raise SystemExit("no %s in %s" % (INDEX, args.folder))

    mesh = load_mesh(args.mesh_dir)
    index = read_index(args.folder)
    items_dir = os.path.join(args.out, "items")
    icons_dir = os.path.join(args.out, "icons")
    os.makedirs(args.out, exist_ok=True)
    if args.obj:
        os.makedirs(items_dir, exist_ok=True)
    if not args.no_icons:
        os.makedirs(icons_dir, exist_ok=True)

    records = []
    failures = []
    parsed = icons = obj_files = 0

    for count, (item_id, (categories, bodies, name)) in enumerate(sorted(index.items())):
        if not wanted(item_id, name, args.only):
            continue
        if args.limit and len(records) >= args.limit:
            break

        path = os.path.join(args.folder, item_id + ".bin")
        if not os.path.exists(path):
            failures.append((item_id, "no %s.bin" % item_id))
            continue
        with open(path, "rb") as handle:
            data = handle.read()

        facts, batches = summarise(mesh, data)
        record = {
            "id": item_id,
            "name": name,
            "categories": categories,
            "bodies": bodies,
            "bytes": facts["bytes"],
            "blocks": facts["blocks"],
            "model": facts["model"],
            "icon": None,
            "obj": None,
        }

        if batches:
            parsed += 1
            if args.obj:
                target = os.path.join(items_dir, item_id + ".obj")
                # Retail items are already y-up: feet at y = 0, head near 1.6.
                mesh.write_obj(target, batches, up_axis="y")
                record["obj"] = "items/%s.obj" % item_id
                obj_files += 1
        else:
            failures.append((item_id, facts["model"].get("error", "unknown")))

        if not args.no_icons:
            source = os.path.join(args.folder, "icons", item_id + ".png")
            if os.path.exists(source):
                shutil.copyfile(source, os.path.join(icons_dir, item_id + ".png"))
                record["icon"] = "icons/%s.png" % item_id
                icons += 1

        records.append(record)
        if len(records) % 500 == 0:
            print("  %d items..." % len(records))

    catalogue = {
        "source": os.path.abspath(args.folder),
        "index": INDEX,
        "items": records,
    }
    target = os.path.join(args.out, "catalogue.json")
    with open(target, "w", encoding="utf-8") as handle:
        json.dump(catalogue, handle, indent=1)

    print("%d items written to %s" % (len(records), target))
    print("  %d models parse, %d icons copied, %d .obj files"
          % (parsed, icons, obj_files))
    if failures:
        print("  %d did not parse:" % len(failures))
        for item_id, reason in failures[:10]:
            print("    %s  %s" % (item_id, reason))
        if len(failures) > 10:
            print("    ... and %d more" % (len(failures) - 10))
    return 0


if __name__ == "__main__":
    sys.exit(main())
