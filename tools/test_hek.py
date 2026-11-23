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
    # The item's own build folder carries the plain base map, so its name says
    # so: data\<item> no_decals. sp and mp copy from it.
    plain = stem + " no_decals"
    out = tempfile.mkdtemp(prefix="hek-layout-")
    hek = os.path.join(out, module.HEK_DIR)

    # The bitmaps extraction already left behind, one mask per order.
    for order in ("pc", "xbox"):
        write(os.path.join(hek, order, "data", plain, "bitmaps",
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
              os.path.normpath(os.path.join(hek, order, "data", plain, "fp", "models")),
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
        target = os.path.join(hek, "xbox", "data", plain, *folder, name)
        check(os.path.exists(target),
              "xbox is missing %s\\%s" % (os.sep.join(folder), name))
    check(not os.path.exists(os.path.join(hek, "xbox", "data", plain, "models",
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

    # 6. Two builds of the item: data\<item> sp and data\<item> mp, each a
    #    complete data\ folder with its own multipurpose map, its own model name
    #    and its own shader names, so the two can be compiled side by side.
    jms = "\n".join([
        "8200\t3251\t2",
        "root\t-1\t-1\t0\t0\t0\t1\t0\t0\t0",
        "bone1\t-1\t-1\t0\t0\t0\t1\t0\t1\t0",
        "2",
        "boot_shader\t<none>",
        "armor_shader\t<none>",
        "0", "1", "unnamed",
        "3",
        "0\t0\t0\t0\t0\t0\t0\t1\t0\t0\t0\t0",
        "0\t1\t0\t0\t0\t0\t0\t1\t0\t0\t0\t0",
        "0\t0\t1\t0\t0\t0\t0\t1\t0\t0\t0\t0",
        "1",
        "0\t0\t0\t1\t2",
    ]) + "\n"
    for order in ("pc", "xbox"):
        base = os.path.join(hek, order, "data", plain)
        write(os.path.join(base, "bitmaps", "%s multipurpose.tif" % stem),
              "team colour %s" % order)
        write(os.path.join(base, "bitmaps", "%s multipurpose xbox.tif" % stem),
              "team colour xbox")
        write(os.path.join(base, "bitmaps", "%s multipurpose sp.tif" % stem),
              "nothing masked %s" % order)
        write(os.path.join(base, "bitmaps", "%s change colour.tif" % stem), "change")
        write(os.path.join(base, "models", "%s.jms" % stem), jms)
        write(os.path.join(base, "fp", "models", "%s - fp arms.jms" % stem), jms)

    renamed = module.jms_material_names(jms, "_sp")
    check("boot_shader_sp\t<none>" in renamed
          and "armor_shader_sp\t<none>" in renamed,
          "jms_material_names did not rename both materials")
    check(renamed.count("<none>") == 2,
          "jms_material_names renamed something that is not a material")
    check(renamed.endswith("0\t0\t0\t1\t2\n"),
          "jms_material_names changed the faces below the materials")
    try:
        module.jms_material_names("not a jms", "_sp")
        check(False, "jms_material_names accepted a file that is not a .jms")
    except ValueError:
        pass

    built = module.hek_builds(out, [stem])
    check(len(built) == 4,
          "hek_builds made %d folders, expected 4 - sp and mp for both orders"
          % len(built))
    for order in ("pc", "xbox"):
        for build in ("sp", "mp"):
            target = os.path.join(hek, order, "data", "%s %s" % (stem, build))
            for sub in ("bitmaps", "models", "animations", "source",
                        os.path.join("fp", "bitmaps"),
                        os.path.join("fp", "models")):
                check(os.path.isdir(os.path.join(target, sub)),
                      "%s %s is missing %s\\" % (order, build, sub))
            want = ("nothing masked %s" % order if build == "sp"
                    else "team colour xbox" if order == "xbox"
                    else "team colour %s" % order)
            mask = os.path.join(target, "bitmaps", "%s multipurpose.tif" % stem)
            check(os.path.exists(mask) and read(mask) == want,
                  "%s %s\\bitmaps multipurpose is %r, expected %r"
                  % (order, build, read(mask) if os.path.exists(mask) else None,
                     want))
            arms = os.path.join(target, "fp", "bitmaps",
                                "%s multipurpose.tif" % stem)
            check(os.path.exists(arms) and read(arms) == want,
                  "%s %s's arms do not carry that build's own map" % (order, build))
            change = os.path.join(target, "bitmaps", "%s change colour.tif" % stem)
            check((build == "mp") == os.path.exists(change),
                  "%s %s %s a change-colour map"
                  % (order, build, "has" if os.path.exists(change) else "lacks"))
            model = os.path.join(target, "models", "%s %s.jms" % (stem, build))
            check(os.path.exists(model), "%s %s has no model" % (order, build))
            if os.path.exists(model):
                check("boot_shader_%s\t<none>" % build in read(model),
                      "%s %s's model does not rename its shader" % (order, build))
            arms_model = os.path.join(target, "fp", "models",
                                      "%s %s - fp arms.jms" % (stem, build))
            check(os.path.exists(arms_model),
                  "%s %s has no fp arms model" % (order, build))
            check(os.path.exists(os.path.join(target, "bitmaps",
                                              "%s base map.tif" % stem)),
                  "%s %s has no base map" % (order, build))

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
