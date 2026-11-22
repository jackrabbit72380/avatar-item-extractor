#!/usr/bin/env python3
"""Prove the .blend files are saved scenes, not empty datablock libraries.

bpy.data.libraries.write() writes datablocks without a scene, so the file opens
on nothing - which is why the .blend looked broken. rig_items.save_blend() saves
the scene instead, with the other objects unlinked for the moment.

There is no Blender here, so this drives the real functions through a stand-in
bpy that records what it was asked to do: which file, whether copy=True was
used, what was in the scene at the moment of saving, and whether the library
writer was called at all.

    python3 tools/test_blend.py
"""

import importlib.util
import os
import sys
import tempfile
import types

HERE = os.path.dirname(os.path.abspath(__file__))
# Any build can be checked: point RIG_MODULES at an unpacked payload.
MODULES = os.environ.get("RIG_MODULES") or os.path.join(
    os.path.dirname(os.path.dirname(HERE)), "recovered")


class Objs:
    """A collection's object list: iterable, with link and unlink."""

    def __init__(self):
        self._items = []

    def __iter__(self):
        return iter(list(self._items))

    def __len__(self):
        return len(self._items)

    def link(self, item):
        if item not in self._items:
            self._items.append(item)

    def unlink(self, item):
        self._items.remove(item)


class Scene:
    def __init__(self):
        self.name = "Scene"
        self.collection = types.SimpleNamespace(objects=Objs())


class Obj:
    def __init__(self, name, kind="MESH"):
        self.name = name
        self.type = kind
        self.selected = False

    def select_set(self, value):
        self.selected = value


def build_stub():
    """A bpy just real enough to run the export functions."""
    calls = []
    scene = Scene()

    class Texts:
        """The text datablocks save_blend writes the Halo note into."""

        def __init__(self):
            self.items = []

        def new(self, name):
            item = types.SimpleNamespace(name=name, body="")
            item.write = lambda text: setattr(item, "body", item.body + text)
            self.items.append(item)
            return item

        def remove(self, item):
            self.items.remove(item)

    texts = Texts()

    def save_as_mainfile(filepath=None, copy=False):
        calls.append({"path": filepath, "copy": copy,
                      "at_save": [item.name for item in scene.collection.objects],
                      "texts": [item.name for item in texts.items],
                      "text_body": [item.body for item in texts.items]})

    def refuse(*_args, **_kwargs):
        raise AssertionError("bpy.data.libraries.write() must not be used for .blend")

    bpy = types.ModuleType("bpy")
    bpy.context = types.SimpleNamespace(
        scene=scene,
        view_layer=types.SimpleNamespace(objects=types.SimpleNamespace(active=None)))
    bpy.ops = types.SimpleNamespace(
        wm=types.SimpleNamespace(save_as_mainfile=save_as_mainfile),
        object=types.SimpleNamespace(select_all=lambda action=None: None))
    # The save also drops images that are broken links (0x0) and materials left
    # with no users, so the stub has to offer those lists.
    bpy.data = types.SimpleNamespace(
        libraries=types.SimpleNamespace(write=refuse), images=[], materials=[],
        texts=texts)
    bpy.app = types.SimpleNamespace(version_string="stub")
    return bpy, scene, calls


def load():
    bpy, scene, calls = build_stub()
    mathutils = types.ModuleType("mathutils")

    class Vector(tuple):
        pass

    class Quaternion(tuple):
        pass

    mathutils.Vector = Vector
    mathutils.Quaternion = Quaternion
    sys.modules["bpy"] = bpy
    sys.modules["mathutils"] = mathutils

    path = os.path.join(MODULES, "rig_items.py")
    spec = importlib.util.spec_from_file_location("rig_items_under_test", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module, scene, calls


def main():
    module, scene, calls = load()
    failures = []

    def fail(message):
        failures.append(message)

    if not hasattr(module, "save_blend"):
        print("FAIL: this build has no save_blend; it writes .blend files with")
        print("      bpy.data.libraries.write(), which opens on an empty scene")
        return 1

    # save_blend: only the wanted objects are in the scene when it is saved.
    a, b, c = Obj("UNSC Marine Armor NXE", "MESH"), Obj("NXE rig", "ARMATURE"), Obj("biped")
    for item in (a, b, c):
        scene.collection.objects.link(item)

    path = os.path.join(tempfile.mkdtemp(prefix="blend-"), "UNSC Marine Armor - NXE.blend")
    calls.clear()
    module.save_blend(path, [a, b])

    if len(calls) != 1:
        fail("save_blend saved %d times, expected 1" % len(calls))
    else:
        call = calls[0]
        if call["path"] != path:
            fail("saved to %r, expected %r" % (call["path"], path))
        if not call["copy"]:
            fail("save_as_mainfile was called without copy=True, which would "
                 "make the export the session's own file")
        if sorted(call["at_save"]) != sorted(["UNSC Marine Armor NXE", "NXE rig"]):
            fail("the scene held %r at save time, expected just the item and its rig"
                 % (call["at_save"],))

    after = sorted(item.name for item in scene.collection.objects)
    if after != sorted(["UNSC Marine Armor NXE", "NXE rig", "biped"]):
        fail("the scene was not restored after saving: %r" % (after,))

    # export_objects(..., "blend") must route through save_blend.
    calls.clear()
    solo = Obj("UNSC Marine Armor - unrigged")
    scene.collection.objects.link(solo)
    module.export_objects(os.path.join(os.path.dirname(path), "unrigged.blend"), [solo], "blend")
    if len(calls) != 1 or calls[0]["at_save"] != ["UNSC Marine Armor - unrigged"]:
        fail("export_objects('blend') did not save a scene holding just the mesh: %r"
             % ([c["at_save"] for c in calls],))

    # export_rigged(..., "blend") must keep the mesh and its armature together,
    # and the note must be a datablock in the file rather than a file beside it.
    calls.clear()
    mesh = Obj("rigged mesh")
    rig = Obj("rigged rig", "ARMATURE")
    scene.collection.objects.link(mesh)
    scene.collection.objects.link(rig)
    module.export_rigged(os.path.join(os.path.dirname(path), "nxe.blend"), mesh, rig,
                         "blend", ("READ ME - halo.txt", "Halo CE\n"))
    if len(calls) != 1 or sorted(calls[0]["at_save"]) != ["rigged mesh", "rigged rig"]:
        fail("export_rigged('blend') did not save the mesh with its armature: %r"
             % ([c["at_save"] for c in calls],))
    if calls and calls[0]["texts"] != ["READ ME - halo.txt"]:
        fail("the Halo note was not in the .blend at save time: %r"
             % (calls[0]["texts"],))

    # The rigged .fbx files are mirrored into max\: 3ds Max opens .fbx as well as
    # .obj and cannot open a .blend at all, so a Max user must not have to reach
    # into blender\ for the rigged model. Only .fbx travels; nothing else does.
    fbx_work = tempfile.mkdtemp(prefix="fbx-")
    fbx_dir = os.path.join(fbx_work, "extracted for blender users")
    os.makedirs(fbx_dir, exist_ok=True)
    for name in ("Item - halo.fbx", "Item - halo fp arms.fbx", "Item - NXE.fbx",
                 "Item - unrigged.fbx", "Item - halo.blend", "Item.glb"):
        open(os.path.join(fbx_dir, name), "w").close()
    copied = module.mirror_fbx(fbx_work, fbx_dir, ["Item", "Missing"])
    in_max = sorted(os.listdir(os.path.join(fbx_work, "extracted for max users")))
    expected = ["Item - halo fp arms.fbx", "Item - halo.fbx", "Item - NXE.fbx",
                "Item - unrigged.fbx"]
    print("  mirror_fbx          -> %d copied, max\\ holds %r" % (copied, in_max))
    if copied != 4 or in_max != sorted(expected):
        fail("mirror_fbx copied %d files (%r), expected %d (%r)"
             % (copied, in_max, len(expected), sorted(expected)))

    # The .jms is the same text model for either Halo target, so it is mirrored
    # into xbox\data as well: an xbox user should not have to reach into pc\
    # for the model when that target's bitmaps are already in its own folder.
    jms_work = tempfile.mkdtemp(prefix="jms-")
    jms_pc = os.path.join(jms_work, "extracted for hek users", "pc", "data",
                          "Item", "models")
    os.makedirs(jms_pc, exist_ok=True)
    for name in ("Item.jms", "Item - fp arms.jms", "Notes.txt"):
        open(os.path.join(jms_pc, name), "w").close()
    copied = module.mirror_jms(jms_work, ["Item", "Missing"])
    jms_xbox = sorted(os.listdir(os.path.join(jms_work, "extracted for hek users",
                                              "xbox", "data", "Item", "models")))
    print("  mirror_jms          -> %d copied, xbox\\data holds %r" % (copied, jms_xbox))
    if copied != 2 or jms_xbox != ["Item - fp arms.jms", "Item.jms"]:
        fail("mirror_jms copied %d files (%r), expected 2 (%r)"
             % (copied, jms_xbox, ["Item - fp arms.jms", "Item.jms"]))

    # The scene and the rigs go into report.txt as a short section: two JSON
    # dumps per item folder that nothing read back were clutter.
    fake_bone = types.SimpleNamespace(name="hip", parent=None,
                                      head_local=(0.0, 0.646, 0.001))
    fake_rig = types.SimpleNamespace(
        name="biped", data=types.SimpleNamespace(bones=[fake_bone]))
    text = module.report_text({"rig": "rig.blend", "fp": None}, [], [], fake_rig)
    wanted = ["scene", "root(s) hip", "root at (0.000, 0.646, 0.001)"]
    print("  report section      -> scene section %s"
          % ("present" if all(word in text for word in wanted) else "MISSING"))
    if not all(word in text for word in wanted):
        fail("report.txt has no scene section with the rig's root: %r" % (text[-300:],))

    # Halo's own rig files are inputs, not outputs: they travel inside the .bat
    # and every item is skinned to them. Copying them into the item folders put
    # a second, unskinned skeleton beside every item and left the player
    # guessing which of the two .blend files was the item's own.
    if hasattr(module, "ship_rigs"):
        fail("the module still ships the source rigs into the output folder")

    # The Halo .blend has to say which game it is for, in the file itself: the
    # filename says it outside, the note says it after the file is moved.
    if not hasattr(module, "halo_note"):
        fail("no halo_note: the Halo .blend does not say what it is for")
    else:
        note_mesh = types.SimpleNamespace(
            name="UNSC Marine Armor",
            data=types.SimpleNamespace(vertices=[1, 2, 3], materials=[1, 2]))
        note_rig = types.SimpleNamespace(
            name="biped", data=types.SimpleNamespace(bones=[1, 2, 3]))
        note = module.halo_note("UNSC Marine Armor", note_mesh, note_rig, False)
        body = note[1]
        wanted_note = ["Halo CE", "UNSC Marine Armor", "19-bone biped",
                       "packed into this file"]
        missing_note = [word for word in wanted_note if word not in body]
        print("  halo_note           -> %r, says %s"
              % (note[0], "ok" if not missing_note else "MISSING %r" % (missing_note,)))
        if missing_note:
            fail("the note in the Halo .blend does not say %r: %r"
                 % (missing_note, body))
        arms_note = module.halo_note("UNSC Marine Armor", note_mesh, note_rig, True)[1]
        if "first-person arms" not in arms_note:
            fail("the fp arms note does not say it is the first-person set: %r"
                 % (arms_note,))

    # What belongs in the first-person set: a vertex mostly on an arm bone, and
    # a face once most of it is arm. Anything looser dragged torso plates in;
    # anything tighter cut holes along the seam.
    for name in ("arm_share", "face_is_arm", "ARM_SHARE"):
        if not hasattr(module, name):
            fail("no %s: the arm cut cannot say what is an arm" % name)
    if hasattr(module, "arm_share"):
        cases = [
            ({"bip01 l forearm": 1.0}, 1.0),
            ({"bip01 l forearm": 0.9, "bip01 spine1": 0.1}, 0.9),
            ({"bip01 spine1": 1.0}, 0.0),
            ({"bip01 l upperarm": 0.2, "bip01 spine1": 0.8}, 0.2),
            ({"bip01 l clavicle": 1.0}, 0.0),
            ({}, 0.0),
        ]
        for weights, wanted in cases:
            got = module.arm_share(weights)
            if abs(got - wanted) > 1e-9:
                fail("arm_share(%r) = %r, expected %r" % (weights, got, wanted))
        if abs(module.ARM_SHARE - 0.5) > 1e-9:
            fail("ARM_SHARE is %r, expected 0.5" % (module.ARM_SHARE,))
        if hasattr(module, "face_is_arm"):
            for kept, total, wanted in ((3, 3, True), (2, 3, True), (1, 3, False),
                                        (0, 3, False), (2, 4, True), (1, 4, False)):
                if module.face_is_arm(kept, total) is not wanted:
                    fail("face_is_arm(%d, %d) is not %r" % (kept, total, wanted))
        # Every bone the cut keeps has to exist on the first-person rig, or the
        # carried weights name a bone that rig does not have.
        for bone in getattr(module, "ARM_BONES", ()):
            if bone not in module.FP_BONES:
                fail("ARM_BONES has %r, which has no first-person bone" % bone)
        print("  arm cut             -> share and face rules ok, %d arm bones"
              % len(getattr(module, "ARM_BONES", ())))

    # A failed cut is a second set lost, not a failed run: arms_for must report
    # it and return, so the Halo body, the .jms and the rest of the items are
    # still written. Before this, one exception in the cut ended the pass.
    if not hasattr(module, "arms_for"):
        fail("no arms_for: the arm cut is called with no guard, so a bad cut "
             "aborts the whole rigging pass")
    else:
        def explode(*_args, **_kwargs):
            raise RuntimeError("simulated bad cut")
        original = module.arm_region
        module.arm_region = explode
        record = {}
        try:
            failed = module.arms_for(
                types.SimpleNamespace(name="UNSC Marine Armor"),
                types.SimpleNamespace(name="biped"),
                types.SimpleNamespace(name="arms rig"), None, record)
        finally:
            module.arm_region = original
        print("  arms_for (bad cut)  -> %r, %r" % (failed, record.get("arms_binding")))
        if failed is not None:
            fail("arms_for returned an object after the cut raised")
        if not str(record.get("arms_binding", "")).startswith("failed"):
            fail("a failed cut leaves no trace in the report: %r" % (record,))

    # The source rigs are kept for repair, in their own folder, so they cannot
    # be mistaken for the item's own file.
    if not hasattr(module, "ship_source_rigs"):
        fail("no ship_source_rigs: the rigs a user repairs against are gone")
    else:
        rig_work = tempfile.mkdtemp(prefix="rigs-")
        source_dir = os.path.join(rig_work, "in")
        os.makedirs(source_dir, exist_ok=True)
        biped_file = os.path.join(source_dir, "master chief skeleton.blend")
        arms_file = os.path.join(source_dir, "fp arms.blend")
        for source in (biped_file, arms_file):
            open(source, "w").close()
        exported = []
        module.export_rig = lambda path, rig, kind: exported.append((path, kind))
        shipped = module.ship_source_rigs(
            os.path.join(rig_work, "out"),
            {"rig": biped_file, "fp": arms_file},
            types.SimpleNamespace(name="biped"))
        kept = sorted(os.listdir(os.path.join(
            rig_work, "out", "extracted for blender users", "source rigs")))
        print("  ship_source_rigs    -> %r, source rigs %r, exported %r"
              % (shipped, kept, [os.path.relpath(path, os.path.join(rig_work, "out"))
                                 for path, _kind in exported]))
        if kept != ["fp arms.blend", "master chief skeleton.blend"]:
            fail("the source rigs are not in their own folder: %r" % (kept,))
        wanted_fbx = os.path.join(rig_work, "out", "extracted for max users",
                                  "master chief skeleton.fbx")
        if exported != [(wanted_fbx, "fbx")]:
            fail("the biped was not exported as .fbx for Max: %r" % (exported,))

    print("  save_blend          -> %d save, copy=%r, scene %r"
          % (1, calls[0]["copy"] if calls else None,
             sorted(calls[0]["at_save"]) if calls else None))
    print("  libraries.write     -> never called")

    if failures:
        print("")
        for line in failures:
            print("FAIL: " + line)
        return 1
    print("")
    print("PASS: .blend files are saved scenes holding only the item")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
