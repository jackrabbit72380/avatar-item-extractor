"""Say why a surface draws white, from the tags that are actually on disk.

Usage: py -3 check_shaders.py [output-folder] [kit-folder]

tool.exe matches a .jms material name against the *name* of a shader tag
anywhere under tags\\, and a material nothing answers is not an error: Tool
writes an empty shader under that name and bakes the reference into the model,
and an empty shader has no base map, so the surface draws white. That white
surface is never the texture and never the mesh - the .jms names the material,
the faces ride a node, the UVs cover the sheet and the sheet compiles. It is one
of three things, and this says which:

  * no shader_model tag answers the material's name (or one answers only
    under another shader type, or with a different spelling);
  * the tag answers but has no base map set in it, or its base map names a
    bitmap tag that is not there;
  * the tags are right but the model tag or the .map was built before them.

Nothing here writes anything.
"""
import os
import re
import sys

SHADER_MODEL = "shader_model"


def find_kit(out):
    """The folder holding tool.exe: saved beside the output, or one near it."""
    saved = os.path.join(out, "hek_path.txt")
    if os.path.exists(saved):
        kit = read_text(saved).strip()
        if kit and os.path.exists(os.path.join(kit, "tool.exe")):
            return kit
    bases = [out, os.path.dirname(out), os.path.dirname(os.path.dirname(out))]
    for base in bases:
        if os.path.exists(os.path.join(base, "tool.exe")):
            return base
    for base in bases:
        try:
            names = sorted(os.listdir(base))
        except OSError:
            continue
        for name in names:
            path = os.path.join(base, name)
            if os.path.isdir(path) and os.path.exists(os.path.join(path, "tool.exe")):
                return path
    return None


def read_text(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read()


def wanted(out):
    """(item, material name, bitmap tag) for every shader the build asks for."""
    rows = []
    path = os.path.join(out, "shaders to make.txt")
    if not os.path.exists(path):
        return rows
    for line in read_text(path).splitlines():
        parts = [part.strip() for part in line.split("|")]
        if len(parts) == 3 and parts[0] and parts[1]:
            rows.append(tuple(parts))
    return rows


def shader_tags(tags):
    """Every shader tag under tags\\, by lower-case name: [(type, path)]."""
    found = {}
    for root, folders, files in os.walk(tags):
        folders[:] = [name for name in folders if not name.startswith(".")]
        for name in files:
            if ".shader_" not in name.lower():
                continue
            stem, _, kind = name.rpartition(".")
            found.setdefault(stem.lower(), []).append(
                (kind.lower(), os.path.join(root, name)))
    return found


def bitmap_tags(tags):
    """Every bitmap under tags\\, by lower-case file name: {name: [path, ...]}.

    The same rule as a shader: the name is what is looked up, and the folder a
    player keeps it in - Halo's ``characters\\<name>\\bitmaps``, their own
    ``<name>\\characters\\...``, a mod folder - is theirs to choose.
    """
    found = {}
    for root, folders, files in os.walk(tags):
        folders[:] = [name for name in folders if not name.startswith(".")]
        for name in files:
            if not name.lower().endswith(".bitmap"):
                continue
            found.setdefault(name[: -len(".bitmap")].lower(), []).append(
                os.path.join(root, name))
    return found


def model_tags(tags):
    """Every model tag under tags\\, by lower-case name: {name: [path, ...]}.

    A tag path is not one folder deep. Halo's own live in tagged folders -
    ``characters\\cyborg\\cyborg.gbxmodel`` - so a model compiled into
    ``tags\\characters\\<item>\\`` is a model that exists, and looking only in
    ``tags\\<item>\\`` calls it missing. That mistake is the one that made a
    build say "nothing was compiled, on purpose" over a good model.
    """
    found = {}
    for root, folders, files in os.walk(tags):
        folders[:] = [name for name in folders if not name.startswith(".")]
        for name in files:
            if not name.lower().endswith(".gbxmodel"):
                continue
            found.setdefault(name[: -len(".gbxmodel")].lower(), []).append(
                os.path.join(root, name))
    return found


def paths_in(path):
    """Printable runs in a binary tag that look like tag paths in it."""
    with open(path, "rb") as handle:
        data = handle.read()
    seen = []
    # A tag path is a 256-byte field, and a user's own prefix makes it long:
    # "jackrabbit72380\characters\UNSC Marine Armor\bitmaps\UNSC Marine Armor face"
    # is 72 characters, so a 64-character read cut the tail off and called a base
    # map that is there missing. Read the field, not the first line of it.
    for run in re.findall(rb"[\x20-\x7e]{4,255}", data):
        text = run.decode("latin-1").strip()
        if "\\" not in text and "/" not in text:
            continue
        for ext in (".shader_model", ".bitmap", ".gbxmodel"):
            if text.lower().endswith(ext):
                text = text[: -len(ext)]
        text = text.strip("\\ ")
        if text and text not in seen:
            seen.append(text)
    return seen


def newest(folder, suffix, deep=True):
    """The newest file with that suffix under folder, or None."""
    best = None
    if not os.path.isdir(folder):
        return None
    if deep:
        walker = ((root, name) for root, _, files in os.walk(folder) for name in files)
    else:
        walker = ((folder, name) for name in os.listdir(folder))
    for root, name in walker:
        if not name.lower().endswith(suffix):
            continue
        path = os.path.join(root, name)
        try:
            stamp = os.path.getmtime(path)
        except OSError:
            continue
        if best is None or stamp > best[0]:
            best = (stamp, path)
    return best


def when(stamp):
    import time
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(stamp))


def main():
    out = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.getcwd())
    rows = wanted(out)
    print("output : %s" % out)
    if not rows:
        print()
        print("There is no \"shaders to make.txt\" in that folder, so there is no")
        print("build to check. Run the extractor first - it writes that list.")
        return 2
    kit = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else find_kit(out)
    if not kit or not os.path.isdir(os.path.join(kit, "tags")):
        print()
        print("No editing kit found: no tool.exe beside the output, one folder up or")
        print("down, and nothing in hek_path.txt. Give the kit's folder as the second")
        print("argument - the one holding tool.exe, data\\ and tags\\:")
        print("  py -3 \"%s\" \"%s\" \"C:\\path\\to\\HCEEK\""
              % (os.path.basename(__file__), out))
        return 2
    tags = os.path.join(kit, "tags")
    print("kit    : %s" % kit)
    print("tags   : %s" % tags)

    found = shader_tags(tags)
    bitmaps = bitmap_tags(tags)
    print()
    print("%d shader tag(s) under tags\\" % sum(len(v) for v in found.values()))
    print("Names are looked up the way tool.exe looks them up: by name, in every")
    print("folder - tags\\, tags\\characters\\<item>\\, tags\\<your folder>\\...")

    worst = 0
    used = {}
    items = sorted({row[0] for row in rows})
    for item, name, bitmap in rows:
        print()
        print("material \"%s\"" % name)
        entries = found.get(name.lower()) or []
        model = None
        for kind, path in entries:
            if kind == SHADER_MODEL:
                model = path
        if model is None:
            worst = max(worst, 2)
            if entries:
                print("  NO shader_model answers it. A tag of that name exists, but as")
                for kind, path in entries:
                    print("    %s  (%s)" % (path, kind))
                print("  the model needs a shader_model, so this surface draws white.")
            else:
                print("  NO shader_model tag of that name exists, so this surface draws")
                print("  white whatever its texture is. Names are matched exactly - the")
                print("  spaces and the capitals - so a tag called \"%s\" or" % name.split()[-1])
                print("  \"%s\" does not answer it." % name.capitalize())
                near = [key for key in found
                        if key.endswith(name.split()[-1].lower())]
                if near:
                    print("  Tags with a similar name that ARE here:")
                    for key in sorted(near)[:8]:
                        for kind, path in found[key]:
                            print("    %s  (%s)" % (path, kind))
            continue
        print("  tag: %s" % model)
        # The name inside the tag file and the spelling of its file both answer
        # to the material - but tool.exe looks the shader up by the material
        # name as the .jms spells it, so a tag saved in capitals is a tag of a
        # different name to a kit that compares the spelling. Renaming the file
        # is the whole fix: same folder, same contents, lower case.
        on_disk = os.path.basename(model)
        if on_disk.lower().endswith(".shader_model"):
            on_disk = on_disk[: -len(".shader_model")]
        if on_disk != name:
            worst = max(worst, 2)
            print("  ... but its name on disk is %r, and the model asks for %r."
                  % (on_disk, name))
            print("  tool.exe finds a shader by the material name exactly as the .jms")
            print("  spells it, so a tag named in capitals can leave the model with the")
            print("  empty shader - the white surface. Rename it to")
            print("  %s.shader_model (same folder, same contents) and" % name)
            print("  compile the model again, then rebuild the map.")
        used.setdefault(item, []).append(model)
        paths = paths_in(model)
        leaf = bitmap.rsplit("\\", 1)[-1].lower()
        maps = [path for path in paths
                if "bitmaps" in path.lower() or leaf in path.lower()]
        if not maps:
            worst = max(worst, 2)
            print("  ... and it holds NO bitmap at all: it is the empty shader Tool")
            print("  wrote when the name was missing. Delete it, make the real one with")
            print("  base map = %s, and compile the model again." % bitmap)
        else:
            for path in maps[:4]:
                bitmap_tag = os.path.join(tags, path.replace("\\", os.sep) + ".bitmap")
                if os.path.exists(bitmap_tag):
                    print("  base map: %s  (there)" % path)
                    continue
                # A shader's base map is a tag PATH: the engine reads it from
                # tags\ exactly, so a bitmap of that name in the player's own
                # folder is not this tag's base map - the reference has to name
                # the folder the file is really in.
                leaf = path.rsplit("\\", 1)[-1].lower()
                found_elsewhere = bitmaps.get(leaf) or []
                worst = max(worst, 2)
                if found_elsewhere:
                    print("  base map: %s  (not at that path)" % path)
                    print("  a bitmap of that name is here: %s" % found_elsewhere[0])
                    print("  a base map is a tag path, so set it to that path - or"
                          " move the bitmap to tags\\%s." % path)
                else:
                    print("  base map: %s  (MISSING - no %s.bitmap anywhere under"
                          " tags\\)" % (path, path.rsplit("\\", 1)[-1]))
                    print("  a base map that is not there draws white, so this is it.")

    # The two things that are right but out of date, which no amount of making
    # tags fixes: a model tag compiled before the shaders existed still carries
    # the empty reference, and a .map built before them still carries the pixels
    # and the references of that moment.
    print()
    models = model_tags(tags)
    for item in items:
        entries = models.get(item.lower()) or []
        if not entries:
            print("model  : no %s.gbxmodel anywhere under tags\\ - it has not been"
                  % item)
            print("         compiled, so the game draws the model it was built with.")
            continue
        # The newest copy: a kit can hold the same name twice, and the one the
        # compile wrote last is the one the tags folder now answers with.
        model_tag = max(entries, key=os.path.getmtime)
        print("model  : %s" % model_tag)
        # Only the tags that answer this build's own materials: the tags\ folder
        # holds every stock shader in the game, and their dates say nothing
        # about when this item's tags were made.
        stamps = []
        for path in used.get(item, []):
            try:
                stamps.append(os.path.getmtime(path))
            except OSError:
                pass
        newest_shader = max(stamps) if stamps else 0
        if newest_shader and os.path.getmtime(model_tag) < newest_shader:
            worst = max(worst, 1)
            print("         built %s, before a shader tag made at %s"
                  % (when(os.path.getmtime(model_tag)), when(newest_shader)))
            print("         Compile the model again: it baked the shader reference of that")
            print("         moment, and an empty one stays empty however the tag looks now.")
    built_map = newest(os.path.join(kit, "maps"), ".map")
    if built_map:
        print("map    : %s" % built_map[1])
        print("         built %s - the tag references and the bitmap pixels are packed"
              % when(built_map[0]))
        print("         at that moment, so rebuild the map after the tags are right.")

    print()
    if worst >= 2:
        print("VERDICT: a surface draws white because of a shader tag problem above.")
    elif worst == 1:
        print("VERDICT: the tags look right - the model tag or the map is older than")
        print("         them. Recompile the model, then rebuild the map.")
    else:
        print("VERDICT: every material answers a shader_model with a base map, and the")
        print("         model tag is newer than them. If the surface is still white,")
        print("         the .map is stale: rebuild it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
