#!/usr/bin/env python3
r"""Prove the HEK folder tree: data\<item>\ with an fp\ beside it, both orders.

The layout is what a HEK user navigates by - tool.exe is pointed at
data\<item>\ and looks inside it by name - so it is checked here rather than
trusted. The real functions are driven through a stand-in bpy, so this runs on
plain Python with no Blender and no rig files:

  * hek_folders() makes models\, animations\, source\ and fp\{models,bitmaps,
    source}\ for pc and xbox alike;
  * each order's fp\bitmaps\ holds that order's own maps, not a copy of pc's;
  * mirror_jms() carries the .jms and the source files into xbox\ and leaves
    anything else in models\ behind;
  * the name filters ignore case, so an item whose title is "UNSC Marine Armor"
    still gets its "UNSC Marine Armor - halo.blend" into source\.

    python3 tools/test_hek.py

Exits 0 only when every check passes. Point RIG_MODULES at an unpacked payload
to check the build the .bat actually ships.
"""

import importlib.util
import os
import sys
import tempfile
import types

HERE = os.path.dirname(os.path.abspath(__file__))
MODULES = os.environ.get("RIG_MODULES") or os.path.join(
    os.path.dirname(HERE), "src")


def load():
    """rig_items with a bpy that exists but is never used by these functions."""
    bpy = types.ModuleType("bpy")
    bpy.context = types.SimpleNamespace(
        scene=types.SimpleNamespace(collection=types.SimpleNamespace(
            objects=types.SimpleNamespace(link=lambda item: None))),
        view_layer=types.SimpleNamespace(objects=types.SimpleNamespace(active=None)))
    bpy.ops = types.SimpleNamespace()
    bpy.data = types.SimpleNamespace(images=[], materials=[], texts=[])
    bpy.app = types.SimpleNamespace(version_string="stub")
    mathutils = types.ModuleType("mathutils")
    mathutils.Vector = tuple
    mathutils.Quaternion = tuple
    sys.modules["bpy"] = bpy
    sys.modules["mathutils"] = mathutils

    path = os.path.join(MODULES, "rig_items.py")
    spec = importlib.util.spec_from_file_location("rig_items_hek_test", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write(path, body):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(body.encode("utf-8"))


def read(path):
    with open(path, "rb") as handle:
        return handle.read().decode("utf-8")


def main():
    module = load()
    failures = []

    def check(condition, message):
        if not condition:
            failures.append(message)

    stem = "UNSC Marine Armor"
    out = tempfile.mkdtemp(prefix="hek-layout-")
    hek = os.path.join(out, module.HEK_DIR)

    # The bitmaps extraction already left behind, one mask per order.
    for order in ("pc", "xbox"):
        write(os.path.join(hek, order, "data", stem, "bitmaps",
                           "%s base map.tif" % stem), order)

    tree = module.hek_folders(out, stem)

    # 1. Every folder a HEK user looks for exists, in both orders.
    wanted = ("models", "animations", "source", "fp", "fp_models", "fp_bitmaps",
              "fp_source")
    for order in ("pc", "xbox"):
        for name in wanted:
            path = tree[order][name]
            check(os.path.isdir(path),
                  "%s\\%s was not made (%s)" % (order, name, path))
            check(os.path.normpath(path).startswith(
                      os.path.normpath(os.path.join(hek, order))),
                  "%s\\%s landed outside %s\\" % (order, name, order))
        check(os.path.normpath(tree[order]["fp_models"]) ==
              os.path.normpath(os.path.join(hek, order, "data", stem, "fp", "models")),
              "%s arms are not in data\\<item>\\fp\\models\\" % order)

    # 2. The arms carry the maps of their own order, not a copy of pc's.
    for order in ("pc", "xbox"):
        map_path = os.path.join(tree[order]["fp_bitmaps"],
                                "%s base map.tif" % stem)
        check(os.path.exists(map_path),
              "%s arms folder has no maps" % order)
        if os.path.exists(map_path):
            check(read(map_path) == order,
                  "%s arms folder holds %r, not its own maps"
                  % (order, read(map_path)))

    # 3. The arms folder is the model's folder, not the body's.
    check(os.path.normpath(tree["pc"]["fp_models"]) !=
          os.path.normpath(tree["pc"]["models"]),
          "the arms were put in the body's models\\")

    # 4. mirror_jms carries the models and the sources into xbox, and only those.
    write(os.path.join(tree["pc"]["models"], "%s.jms" % stem), "body")
    write(os.path.join(tree["pc"]["fp_models"], "%s - fp arms.jms" % stem), "arms")
    write(os.path.join(tree["pc"]["source"], "%s - halo.blend" % stem), "blend")
    write(os.path.join(tree["pc"]["source"], "%s - halo.fbx" % stem), "fbx")
    write(os.path.join(tree["pc"]["fp_source"],
                       "%s - halo fp arms.blend" % stem), "fp blend")
    write(os.path.join(tree["pc"]["models"], "notes.txt"), "not a model")
    module.mirror_jms(out, [stem])
    for folder, name in ((("models",), "%s.jms" % stem),
                         (("fp", "models"), "%s - fp arms.jms" % stem),
                         (("source",), "%s - halo.blend" % stem),
                         (("source",), "%s - halo.fbx" % stem),
                         (("fp", "source"), "%s - halo fp arms.blend" % stem)):
        target = os.path.join(hek, "xbox", "data", stem, *folder, name)
        check(os.path.exists(target),
              "xbox is missing %s\\%s" % (os.sep.join(folder), name))
    check(not os.path.exists(os.path.join(hek, "xbox", "data", stem, "models",
                                         "notes.txt")),
          "mirror_jms copied a file that is not a model")

    # 5. The source folders fill with the files the item was exported from, and
    #    the filter matches whatever case the item's title is written in.
    blend = os.path.join(tree["pc"]["item"], "source")
    os.remove(os.path.join(blend, "%s - halo.blend" % stem))
    module.share_files(os.path.join(out, "elsewhere"), blend,
                       ("%s - halo.blend" % stem, "%s - halo.fbx" % stem))
    write(os.path.join(out, "elsewhere", "%s - halo.blend" % stem), "blend")
    write(os.path.join(out, "elsewhere", "%s - halo.fbx" % stem), "fbx")
    write(os.path.join(out, "elsewhere", "%s - NXE.fbx" % stem), "nxe")
    copied = module.share_files(os.path.join(out, "elsewhere"), blend,
                                ("%s - halo.blend" % stem,
                                 "%s - halo.fbx" % stem))
    check(copied == 2, "source\\ took %d files, expected 2" % copied)
    check(os.path.exists(os.path.join(blend, "%s - halo.blend" % stem)),
          "source\\ did not take the .blend the item was exported from")
    check(not os.path.exists(os.path.join(blend, "%s - NXE.fbx" % stem)),
          "source\\ took a file that is not the Halo export")

    # The same filter, written in the other case, still matches.
    write(os.path.join(out, "elsewhere2", "unsc marine armor - halo.blend"), "x")
    lower = module.share_files(os.path.join(out, "elsewhere2"),
                               os.path.join(out, "case"), ("%s - halo.blend" % stem,))
    check(lower == 1,
          "a lower-case file name did not match an item title in mixed case")

    if failures:
        print("FAIL: %d check(s)" % len(failures))
        for message in failures:
            print("  - %s" % message)
        return 1
    print("PASSED: HEK tree - data\\<item>\\{models,animations,source,fp\\{models,"
          "bitmaps,source}}, both orders, each with its own maps")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
