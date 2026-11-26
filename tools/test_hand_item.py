#!/usr/bin/env python3
"""Check which items are worn on the hand, and which only look like they are.

A tee's shoulders are weighted to the upper arms, so its binding line starts
with "bip01 r upperarm" - and reading that line alone put a whole shirt on the
first-person hand, rigidly, as if it were a ring. Only a prop rides one bone.
"""
try:
    import bmesh  # noqa: F401 - Blender's own module, present only inside Blender
except ImportError:
    print("needs Blender's own python (bmesh): skipping here")
    raise SystemExit(2)


import importlib.util
import os
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))
MODULES = os.environ.get("RIG_MODULES") or os.path.join(
    os.path.dirname(HERE), "src")


def load():
    bpy = types.ModuleType("bpy")
    bpy.context = types.SimpleNamespace()
    bpy.ops = types.SimpleNamespace()
    bpy.data = types.SimpleNamespace(images=[], materials=[], texts=[])
    bpy.app = types.SimpleNamespace(version_string="stub")
    mathutils = types.ModuleType("mathutils")
    mathutils.Vector = tuple
    mathutils.Quaternion = tuple
    sys.modules["bpy"] = bpy
    sys.modules["mathutils"] = mathutils
    path = os.path.join(MODULES, "rig_items.py")
    spec = importlib.util.spec_from_file_location("rig_items_hand_test", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    module = load()
    failures = []

    def check(got, want, what):
        if got != want:
            failures.append("%s: got %r, expected %r" % (what, got, want))

    # A ring: a prop, riding the right hand.
    check(module.hand_item(True, "bip01 r hand 100%"), "bip01 r hand",
          "a ring on the right hand")
    check(module.hand_item(True, "bip01 l forearm 100%"), "bip01 l forearm",
          "a bracer on the left forearm")

    # A tee: not a prop, even though its binding line names the upper arms.
    check(module.hand_item(False, "bip01 r upperarm 15%, bip01 l upperarm 15%, "
                                  "bip01 spine1 14%"), None,
          "a shirt whose shoulders ride the upper arms")

    # A prop that is not on an arm at all stays off the hand.
    check(module.hand_item(True, "bip01 spine1 100%"), None,
          "a prop on the spine")

    if failures:
        print("FAIL: %d check(s)" % len(failures))
        for message in failures:
            print("  - %s" % message)
        return 1
    print("PASSED: hand items are props only - a shirt on the upper arms is not "
          "put on the first-person hand")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
