@echo off
REM ===============================================================
REM  Extract Avatar Items - single file (v20)
REM  Double-click this file. Nothing to install, nothing to choose.
REM
REM  Everything is inside this one file. The marker line further down marks
REM  where; on first run the extractor is unpacked to
REM  %LOCALAPPDATA%\AvatarItemExtractor and the two readers it needs
REM  are downloaded into the same folder. After that it runs offline.
REM ===============================================================
setlocal EnableExtensions
cd /d "%~dp0"
title Extract Avatar Items

set "CACHE=%LOCALAPPDATA%\AvatarItemExtractor"
if not exist "%CACHE%" mkdir "%CACHE%" >nul 2>nul
set "PYFILE=%CACHE%\extract_items.py"
set "OUT=%~dp0extracted"

REM ---- 1. unpack the extractor carried in this file ----------------
if exist "%PYFILE%" goto :havepayload
echo Preparing the extractor ^(first run only^)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='%~f0'; $t=[IO.File]::ReadAllText($p); $m='###PAYLOAD###'; $i=$t.LastIndexOf($m); if($i -lt 0){exit 1}; $b=$t.Substring($i+$m.Length).TrimStart([char]13,[char]10); [IO.File]::WriteAllText('%PYFILE%',$b,(New-Object Text.UTF8Encoding($false)))"
if not exist "%PYFILE%" goto :unpackfail

:havepayload
REM ---- 2. the readers it needs, downloaded once --------------------
if not exist "%CACHE%\avatar_mesh.py" call :readers
if not exist "%CACHE%\avatar_mesh.py" (
    echo.
    echo Could not get the avatar readers.
    echo Check the internet connection and run this file again.
    echo If that keeps failing, copy avatar_mesh.py and lzx.py from a
    echo UniKron avatar_tools folder into this folder:
    echo   %CACHE%
    echo then run this file again.
    echo.
    pause
    exit /b 1
)
if not exist "%CACHE%\lzx.py" (
    echo.
    echo The LZX reader is missing. Copy lzx.py from a UniKron
    echo avatar_tools folder into this folder:
    echo   %CACHE%
    echo then run this file again.
    echo.
    pause
    exit /b 1
)

REM ---- 3. python ---------------------------------------------------
set "PY="
where py >nul 2>nul && set "PY=py -3"
if not defined PY where python >nul 2>nul && set "PY=python"
if not defined PY (
    echo.
    echo Python was not found.
    echo Install it from https://www.python.org/downloads/ , tick
    echo "Add python.exe to PATH" during setup, then run this file again.
    echo.
    pause
    exit /b 1
)

REM ---- 4. find the items and extract them --------------------------
%PY% "%PYFILE%" %* --obj --out "%OUT%" --mesh-dir "%CACHE%"
set "RESULT=%errorlevel%"

if "%RESULT%"=="0" (
    echo.
    echo Done. Opening the results...
    start "" "%OUT%"
    echo.
    echo  catalogue.json  - every item: name, masks, geometry, where it came from
    echo  items\*.obj     - the models, ready to open in Blender
    echo  icons\*.png     - the item icons
    echo.
    pause
    exit /b 0
)

echo.
if "%RESULT%"=="4" (
    echo No avatar items were found. The folders listed above were searched
    echo and none of them holds a closet_index.tsv or any .bin/.asset files.
) else (
    echo Items were found but none could be read - see the lines above.
    echo If they say "not a STRB container", those files are not retail
    echo avatar items and this tool cannot read them.
)
echo.
pause
exit /b %RESULT%

:unpackfail
echo.
echo Could not unpack the extractor from this file.
echo Copy the file somewhere like C:\Tools and run it from there.
echo.
pause
exit /b 1

:readers
set "BASE=https://raw.githubusercontent.com/jackrabbit72380/UniKron/main/avatar/avatar_tools"
echo Downloading the avatar readers ^(once^)...
powershell -NoProfile -Command "try { Invoke-WebRequest -UseBasicParsing '%BASE%/avatar_mesh.py' -OutFile '%CACHE%\avatar_mesh.py'; Invoke-WebRequest -UseBasicParsing '%BASE%/lzx.py' -OutFile '%CACHE%\lzx.py' } catch { exit 1 }"
exit /b 0
###PAYLOAD###
#!/usr/bin/env python3
"""Extract retail Xbox 360 avatar items into a catalogue and per-item files.

Carried inside Extract-AvatarItem-v20.bat, which unpacks it on first run.
Written in plain ASCII on purpose: the batch file copies these bytes verbatim.

You do not tell it where the items are. It checks a fixed list of places, takes
every item source it finds, and extracts all of them. Nothing is asked, nothing
is picked by hand:

    1. this folder and the folder above it
    2. ..\\UniKron\\src_archive          (where the project keeps the dump)
    3. %USERPROFILE%\\Downloads
    4. %USERPROFILE%\\Desktop
    5. %USERPROFILE%\\Documents
    6. %USERPROFILE%\\OneDrive\\Downloads

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
    --obj            also write each parsed model as <out>/items/<id>.obj
    --only ID|NAME   extract only matching ids or names (repeatable)
    --limit N        stop after N items
    --no-icons       do not copy icons
    --root DIR       search this folder instead of the default list (repeatable)
    --mesh-dir DIR   where avatar_mesh.py lives (default: ./vendor)

Writes:
    <out>/catalogue.json     one record per item: name, masks, blocks, geometry
    <out>/icons/<id>.png     copied when present
    <out>/items/<id>.obj     with --obj

Exit status: 0 something parsed, 3 sources found but nothing parsed, 4 nothing
found. Requires Python 3.8+. No third-party packages.
"""

import argparse
import json
import os
import re
import shutil
import sys

INDEX = "closet_index.tsv"
ITEM_EXTENSIONS = (".bin", ".asset")
SKIP_DIRS = {"node_modules", "__pycache__", ".git", "vendor", "extracted",
             "$RECYCLE.BIN", "System Volume Information"}
MAX_DEPTH = 3


# --------------------------------------------------------------- mesh reader

def load_mesh(explicit_dir=None):
    """Import avatar_mesh.py, which carries the STRB/LZX/model readers."""
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
        "It is downloaded next to this script on first run; if that failed, "
        "put a UniKron/avatar/avatar_tools checkout next to it or pass "
        "--mesh-dir."
    )


# ---------------------------------------------------------------- discovery

def default_roots():
    """The fixed search list. Order matters only for the report."""
    here = os.path.dirname(os.path.abspath(__file__))
    home = os.path.expanduser("~")
    roots = [
        here,
        os.path.dirname(here),
        os.path.join(os.path.dirname(here), "UniKron", "src_archive"),
        os.path.join(home, "Downloads"),
        os.path.join(home, "Desktop"),
        os.path.join(home, "Documents"),
        os.path.join(home, "OneDrive", "Downloads"),
        os.path.join(home, "OneDrive", "Desktop"),
    ]
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


def is_source(folder, files):
    if INDEX in files:
        return True
    return any(os.path.splitext(name)[1].lower() in ITEM_EXTENSIONS for name in files)


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


def collect(source):
    """Everything to extract from one source: (id, categories, bodies, name, path)."""
    entries = []
    if os.path.isfile(source):
        item_id = os.path.splitext(os.path.basename(source))[0]
        return [(item_id, guid_categories(item_id), None, "", source)]

    if os.path.exists(os.path.join(source, INDEX)):
        for item_id, (cats, bodies, name) in sorted(read_index(source).items()):
            entries.append((item_id, cats, bodies, name,
                            os.path.join(source, item_id + ".bin")))
        return entries

    for name in sorted(os.listdir(source)):
        base, extension = os.path.splitext(name)
        if extension.lower() not in ITEM_EXTENSIONS:
            continue
        entries.append((base, guid_categories(base), None, "",
                        os.path.join(source, name)))
    return entries


def describe_source(source):
    """A one-line account of what a source will give us."""
    if os.path.isfile(source):
        return "1 file, %d bytes" % os.path.getsize(source)
    if os.path.exists(os.path.join(source, INDEX)):
        return "%d items in the index" % len(read_index(source))
    count = sum(1 for name in os.listdir(source)
                if os.path.splitext(name)[1].lower() in ITEM_EXTENSIONS)
    return "%d item files" % count


# ------------------------------------------------------------------ the item

def summarise(mesh, data):
    """Read one item: block table plus geometry, or the reason it failed."""
    facts = {"bytes": len(data), "blocks": [], "model": {"parses": False}}
    try:
        blocks = mesh.strb_blocks(data)
    except mesh.Malformed as exc:
        facts["model"]["error"] = str(exc)
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
    parser.add_argument("--mesh-dir", help="directory holding avatar_mesh.py")
    args = parser.parse_args(argv)

    out = args.out_option or args.out or "extracted"

    if args.source:
        sources = [args.source]
        searched = []
    else:
        searched = [os.path.abspath(root) for root in (args.root or default_roots())]
        print("Looking for avatar items in:")
        for root in searched:
            print("  %s" % root)
        sources = find_sources(searched)
        if not sources:
            print("")
            print("Nothing found. None of the folders above holds a")
            print("closet_index.tsv or any .bin/.asset item files.")
            print("Put the closet folder in one of them and run again,")
            print("or pass --root <folder>.")
            return 4
        print("")
        print("Found %d item source%s:" % (len(sources), "" if len(sources) == 1 else "s"))
        for source in sources:
            print("  %s  (%s)" % (source, describe_source(source)))
        print("")

    mesh = load_mesh(args.mesh_dir)
    items_dir = os.path.join(out, "items")
    icons_dir = os.path.join(out, "icons")
    os.makedirs(out, exist_ok=True)
    if args.obj:
        os.makedirs(items_dir, exist_ok=True)
    if not args.no_icons:
        os.makedirs(icons_dir, exist_ok=True)

    records = []
    failures = []
    seen_ids = set()
    parsed = icons = obj_files = skipped = 0

    for source in sources:
        entries = collect(source)
        if not entries:
            print("  %s holds nothing to extract, skipping" % source)
            continue
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

            facts, batches = summarise(mesh, data)
            record = {
                "id": item_id,
                "name": name or "",
                "categories": categories,
                "bodies": bodies,
                "file": os.path.basename(path),
                "source": os.path.dirname(path) or ".",
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
                icon_source = os.path.join(os.path.dirname(path), "icons", item_id + ".png")
                if os.path.exists(icon_source):
                    shutil.copyfile(icon_source, os.path.join(icons_dir, item_id + ".png"))
                    record["icon"] = "icons/%s.png" % item_id
                    icons += 1

            records.append(record)
            if len(records) % 500 == 0:
                print("  %d items..." % len(records))

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
    print("  %d models parse, %d icons copied, %d .obj files"
          % (parsed, icons, obj_files))
    if skipped:
        print("  %d duplicate ids skipped" % skipped)
    if failures:
        print("  %d did not parse:" % len(failures))
        for item_id, reason in failures[:10]:
            print("    %s  %s" % (item_id, reason))
        if len(failures) > 10:
            print("    ... and %d more" % (len(failures) - 10))
    return 0 if parsed else 3


if __name__ == "__main__":
    sys.exit(main())
