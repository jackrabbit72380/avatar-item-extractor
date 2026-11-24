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
import math
import os
import sys
import tempfile
import types

HERE = os.path.dirname(os.path.abspath(__file__))
# Any build can be checked: point RIG_MODULES at an unpacked payload.
MODULES = os.environ.get("RIG_MODULES") or os.path.join(
    os.path.dirname(HERE), "src")


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
    # One build per item, in the item's own folder: there has been no " sp"
    # suffix since the sp/mp pair was collapsed into the one that takes the team
    # colour.
    pc_item = os.path.join(jms_work, "extracted for hek users", "pc", "data", "Item")
    xbox_item = os.path.join(jms_work, "extracted for hek users", "xbox", "data",
                             "Item")
    folders = ((("models",), ("Item.jms", "Notes.txt")),
               (("fp", "models"), ("Item - fp arms.jms",)),
               (("source",), ("Item - halo.blend",)),
               (("fp", "source"), ("Item - halo fp arms.blend",)))
    for folder, names in folders:
        path = os.path.join(pc_item, *folder)
        os.makedirs(path, exist_ok=True)
        for name in names:
            open(os.path.join(path, name), "w").close()
    copied = module.mirror_jms(jms_work, ["Item", "Missing"])
    got = {folder: sorted(os.listdir(os.path.join(xbox_item, *folder)))
           for folder, _names in folders}
    print("  mirror_jms          -> %d copied, xbox\\data holds %r" % (copied, got))
    wanted = {(("models",)): ["Item.jms"],
              (("fp", "models")): ["Item - fp arms.jms"],
              (("source",)): ["Item - halo.blend"],
              (("fp", "source")): ["Item - halo fp arms.blend"]}
    if copied != 4 or got != wanted:
        fail("mirror_jms copied %d files (%r), expected 4 (%r)"
             % (copied, got, wanted))

    # The fp folder carries its own bitmaps and models, and both it and the
    # item's own folder carry a source\\ with the file the model came from.
    share_work = tempfile.mkdtemp(prefix="share-")
    maps = os.path.join(share_work, "maps")
    os.makedirs(maps, exist_ok=True)
    for name in ("Item base map.tif", "Item colour.png", "notes.txt"):
        open(os.path.join(maps, name), "w").close()
    target = os.path.join(share_work, "fp", "bitmaps")
    copied = module.share_files(maps, target, (".tif", ".png"))
    got = sorted(os.listdir(target))
    print("  share_files         -> %d copied, fp\\bitmaps holds %r" % (copied, got))
    if copied != 2 or got != ["Item base map.tif", "Item colour.png"]:
        fail("share_files copied %d files (%r), expected the two maps (%r)"
             % (copied, got, ["Item base map.tif", "Item colour.png"]))

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

    # The per-bone finger numbers reach report.txt, one line each, with the side
    # and whether the bone is inside the glove or how far outside.
    arm_record = {
        "id": "Item", "title": "Item",
        "arms_file": "Item - halo fp arms.blend",
        "arms_binding": "renamed to Halo's fp bones",
        "arms_fingers_bones": "all 7 of Halo's finger bones sit inside the glove",
        "arms_finger_bones": ["l middle tip  -0.40 inside",
                              "l thumb low   +0.62 OUTSIDE"],
    }
    arms_text = module.report_text({"rig": "rig.blend", "fp": None},
                                   [arm_record], ["Item"], fake_rig)
    wanted_fingers = ["per bone, from the glove's skin",
                      "l thumb low   +0.62 OUTSIDE",
                      "all 7 of Halo's finger bones"]
    print("  report finger bones -> %s"
          % ("present" if all(word in arms_text for word in wanted_fingers)
             else "MISSING"))
    if not all(word in arms_text for word in wanted_fingers):
        fail("report.txt does not list each finger bone: %r" % (arms_text[-300:],))

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

    # What belongs in the first-person set: whole shells picked by the bones
    # they are mostly weighted to, and carried across rigidly so no piece can be
    # stretched or torn off the arm.
    for name in ("arm_share", "ARM_SHARE", "arm_pieces", "arm_axis",
                 "alignment", "place_point", "side_carry", "hand_share",
                 "principal_axes", "hand_plane", "turn_about",
                 "turn_product", "turn_point", "hand_twist", "hand_fit",
                 "halo_hand", "HAND_FINGERS", "hand_span", "finger_bones",
                 "finger_split", "finger_chains", "finger_of", "ride_chain",
                 "glove_of", "finger_room", "glove_surface", "skin_gap",
                 "finger_gaps", "inside_out"):
        if not hasattr(module, name):
            fail("no %s: the arm cut cannot say what is an arm" % name)
    if hasattr(module, "arm_share"):
        cases = [
            ({"bip01 l forearm": 1.0}, 1.0),
            ({"bip01 l forearm": 0.9, "bip01 spine1": 0.1}, 0.9),
            ({"bip01 spine1": 1.0}, 0.0),
            ({"bip01 l upperarm": 0.2, "bip01 spine1": 0.8}, 0.2),
            # a clavicle is not an arm bone: shoulder armour is judged apart,
            # by arm_pieces, so a chest plate cannot ride in on its corners
            ({"bip01 l clavicle": 1.0}, 0.0),
            ({}, 0.0),
        ]
        for weights, wanted in cases:
            got = module.arm_share(weights)
            if abs(got - wanted) > 1e-9:
                fail("arm_share(%r) = %r, expected %r" % (weights, got, wanted))
        if abs(module.ARM_SHARE - 0.5) > 1e-9:
            fail("ARM_SHARE is %r, expected 0.5" % (module.ARM_SHARE,))
        # Whole shells, not loose vertices: a sleeve, a torso plate and a
        # pauldron are each taken or left whole. Cutting per vertex left half a
        # plate behind to be flung off the arm.
        class Poly:
            def __init__(self, *verts):
                self.vertices = verts

        class Group:
            def __init__(self, index, name):
                self.index = index
                self.name = name

        class Entry:
            def __init__(self, group, weight):
                self.group = group
                self.weight = weight

        class Vert:
            def __init__(self, index, per):
                self.index = index
                self.groups = [Entry(group, weight) for group, weight in per]

        groups = [Group(0, "bip01 spine1"), Group(1, "bip01 l clavicle"),
                  Group(2, "bip01 l upperarm"), Group(3, "bip01 l forearm")]
        shells = [
            # a sleeve, mostly forearm: kept
            [(0, ((3, 0.8), (0, 0.2))), (1, ((3, 1.0),)),
             (2, ((2, 0.7), (1, 0.3)))],
            # a torso plate, on the spine: left out
            [(3, ((0, 1.0),)), (4, ((0, 1.0),)), (5, ((0, 1.0),))],
            # a pauldron, on the clavicle: kept, riding the upper arm
            [(6, ((1, 1.0),)), (7, ((1, 1.0),)), (8, ((1, 1.0),))],
            # half an arm by weight: under the floor, left out
            [(9, ((2, 0.45), (0, 0.55))), (10, ((2, 0.45), (0, 0.55))),
             (11, ((2, 0.45), (0, 0.55)))],
        ]
        vertices = [Vert(index, per) for shell in shells for index, per in shell]
        polygons = [Poly(shell[0][0], shell[1][0], shell[2][0])
                    for shell in shells]
        cut = module.arm_pieces(types.SimpleNamespace(
            data=types.SimpleNamespace(vertices=vertices, polygons=polygons),
            vertex_groups=groups))
        kept = [sorted(piece["indices"]) for piece in cut]
        print("  arm_pieces          -> %r" % (kept,))
        # No armature here, so the shoulder rule declines to guess and the
        # pauldron stays on the body; the rule is exercised below, with one.
        if kept != [[0, 1, 2]]:
            fail("the cut kept %r, not just the sleeve" % (kept,))
        if cut and (cut[0]["side"] != "l"
                    or cut[0]["bone"] != "bip01 l forearm"):
            fail("the sleeve is not on the left forearm: %r" % (cut[0],))

        # The carry is one turn per side, measured from the arm's own mesh. The
        # item is modelled in the avatar's pose while the bones are Halo's, so
        # the arm's direction has to come from the geometry; and each bone's rest
        # frame cannot be used either, because the biped's left hand is rolled a
        # half turn against its forearm - that turned gloves inside out against
        # sleeves and tore them apart on a real item.
        class Vec:
            def __init__(self, *values):
                self.values = list(values)

            def __mul__(self, factor):
                return Vec(*(value * factor for value in self.values))

            def __truediv__(self, factor):
                return Vec(*(value / factor for value in self.values))

            def __add__(self, other):
                return Vec(*(a + b for a, b in zip(self.values, other.values)))

            def __sub__(self, other):
                return Vec(*(a - b for a, b in zip(self.values, other.values)))

            def __getitem__(self, index):
                return self.values[index]

            def __len__(self):
                return len(self.values)

            def dot(self, other):
                return sum(a * b for a, b in zip(self.values, other.values))

            @property
            def length_squared(self):
                return sum(value * value for value in self.values)

            @property
            def length(self):
                return self.length_squared ** 0.5

        class Shift:
            def __init__(self, offset):
                self.offset = offset

            def __matmul__(self, point):
                return Vec(*(point.values[i] + self.offset[i] for i in range(3)))

        if not hasattr(module, "arm_axis"):
            fail("no arm_axis: the carry cannot find which way the arm runs")

        def cloud(direction, spread=4.0, rings=8):
            """A sleeve-shaped cloud pointing the way the arm does."""
            step = list(direction)
            length = sum(value * value for value in step) ** 0.5
            step = [value / length for value in step]
            catch = [1.0, 0.0, 0.0] if abs(step[0]) < 0.9 else [0.0, 1.0, 0.0]
            across = [step[1] * catch[2] - step[2] * catch[1],
                      step[2] * catch[0] - step[0] * catch[2],
                      step[0] * catch[1] - step[1] * catch[0]]
            norm = sum(value * value for value in across) ** 0.5
            across = [value / norm for value in across]
            up = [step[1] * across[2] - step[2] * across[1],
                  step[2] * across[0] - step[0] * across[2],
                  step[0] * across[1] - step[1] * across[0]]
            points = []
            for ring in range(rings):
                t = ring / (rings - 1.0)
                centre = [step[i] * 22.0 * t for i in range(3)]
                for k in range(6):
                    a = 2 * math.pi * k / 6
                    points.append(Vec(*[
                        centre[i] + (across[i] * math.cos(a)
                                     + up[i] * math.sin(a)) * spread
                        for i in range(3)]))
            # a pauldron off to one side, as a real item has
            points.extend([Vec(6.0, 0.0, 2.0), Vec(-6.0, 0.0, 2.0),
                           Vec(*[step[i] * 3.0 for i in range(3)])])
            return points

        for label, direction in (("along x", (1.0, 0.0, 0.0)),
                                 ("hanging", (0.0, 0.1, -1.0))):
            axis, centre = module.arm_axis(cloud(direction))
            print("  arm_axis  %-10s -> %r" % (label, [round(v, 2) for v in axis]))
            along = sum(axis[i] * direction[i] for i in range(3))
            if abs(along) < 0.99:
                fail("the arm's axis came out %r for an arm %s" % (axis, label))

        turn = module.alignment((0.0, 0.0, -1.0), (1.0, 0.0, 0.0))
        aim = [-turn[2], -turn[5], -turn[8]]
        print("  alignment  hanging -> straight out: %r" % ([round(v, 3) for v in aim],))
        if max(abs(aim[0] - 1.0), abs(aim[1]), abs(aim[2])) > 1e-6:
            fail("a hanging arm was turned to %r, not straight out" % (aim,))
        flat = module.alignment((1.0, 0.0, 0.0), (1.0, 0.0, 0.0))
        if tuple(flat) != (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0):
            fail("an arm already straight out was turned: %r" % (flat,))
        back = module.alignment((1.0, 0.0, 0.0), (-1.0, 0.0, 0.0))
        sent = [back[0], back[3], back[6]]
        if max(abs(sent[0] + 1.0), abs(sent[1]), abs(sent[2])) > 1e-6:
            fail("a reversed arm was not turned by half a turn: %r" % (back,))

        moved = module.place_point(flat, (0.0, 0.0, 0.0), (0.0, 9.4, 0.0),
                                   (1.0, 2.0, 3.0))
        if [round(value, 6) for value in moved] != [1.0, 11.4, 3.0]:
            fail("a point was not shifted onto Halo's shoulder: %r" % (moved,))

        class Bone:
            def __init__(self, head, tail):
                self.head_local = Vec(*head)
                self.tail_local = Vec(*tail)

        biped_rig = types.SimpleNamespace(
            matrix_world=Shift((0.0, 0.0, 0.0)),
            data=types.SimpleNamespace(bones={
                "bip01 l upperarm": Bone((0.0, 9.0, 56.0), (0.0, 9.0, 45.0))}))
        fp_rig = types.SimpleNamespace(
            matrix_world=Shift((0.0, 0.0, 0.0)),
            data=types.SimpleNamespace(bones={
                "frame l upperarm": Bone((0.0, 9.4, 0.0), (10.25, 9.4, 0.0)),
                "frame l forearm": Bone((10.25, 9.4, 0.0), (21.14, 9.4, 0.0)),
                "frame l wriste": Bone((21.14, 9.4, 0.0), (24.52, 9.4, 0.0))}))
        arm = [Vec(0.0, 9.0, 50.0), Vec(3.0, 9.0, 40.0), Vec(-3.0, 9.0, 40.0),
               Vec(0.0, 9.0, 30.0), Vec(3.0, 9.0, 30.0), Vec(-3.0, 9.0, 30.0)]
        # avatar-style hard weights: each vertex on one bone, no shared skin
        per_bone = [{"bip01 l upperarm": 1.0}, {"bip01 l upperarm": 1.0},
                    {"bip01 l upperarm": 1.0}, {"bip01 l forearm": 1.0},
                    {"bip01 l forearm": 1.0}, {"bip01 l forearm": 1.0}]
        place = module.side_carry(biped_rig, fp_rig, "l", arm, per_bone)
        if place is None:
            fail("side_carry could not place an arm whose bones both exist")
        else:
            hand = module.place_arm(place, Vec(0.0, 9.0, 30.0))
            print("  side_carry hanging -> hand at %r"
                  % ([round(v, 2) for v in hand],))
            # Far down a hanging arm, so far out along Halo's: y is the arm's
            # own line, z is nothing.
            if abs(hand[1] - 9.4) > 0.5 or abs(hand[2]) > 0.5:
                fail("the hand left Halo's arm line: %r" % (hand,))
            if not 20.0 < hand[0] < 28.0:
                fail("the hand landed at %r, not out along Halo's arm" % (hand,))
            # One similarity per side: every edge of the arm is multiplied by
            # the same number. That is what makes a tear impossible, so it is
            # checked edge by edge rather than by "not too far off".
            ratios = []
            for i in range(len(arm)):
                for j in range(i + 1, len(arm)):
                    was = math.dist(tuple(arm[i]), tuple(arm[j]))
                    now = math.dist(tuple(module.place_arm(place, arm[i])),
                                    tuple(module.place_arm(place, arm[j])))
                    ratios.append(now / was)
            print("  side_carry edges   -> every edge x%.4f" % (ratios[0],))
            if max(ratios) - min(ratios) > 1e-9:
                fail("the carry stretched the arm unevenly, so it can tear: %r"
                     % (ratios,))
            if not 0.5 - 1e-9 <= ratios[0] <= 1.6 + 1e-9:
                fail("the arm was scaled x%.2f, outside the clamp" % (ratios[0],))
            # The hand weights an item does not have: none at the cuff, the
            # hand's own bone at the fingertips, so the glove follows Halo's
            # hand instead of swinging from the elbow.
            cuff = module.hand_share(place, Vec(0.0, 9.0, 40.0))
            tip = module.hand_share(place, Vec(0.0, 9.0, 30.0))
            print("  hand_share         -> cuff %.2f, fingertip %.2f" % (cuff, tip))
            if cuff != 0.0 or tip < 0.99:
                fail("the glove would not hand over to Halo's wrist: %r %r"
                     % (cuff, tip))
            # An arm modelled outboard of its own bone has to sit centred on
            # Halo's, not hang out by the same amount: pinning only the
            # shoulder joint left it 3 units out and 6.3 units away from
            # Halo's own arms.
            leaning = [Vec(point[0], point[1] + 3.0, point[2]) for point in arm]
            off_place = module.side_carry(biped_rig, fp_rig, "l", leaning, per_bone)
            if off_place is None:
                fail("an arm modelled off its own bone was not placed")
            else:
                moved_mid = [module.place_arm(off_place, point) for point in leaning]
                middle = sum(point[1] for point in moved_mid) / len(moved_mid)
                print("  side_carry offset  -> arm middle at y %.2f" % (middle,))
                if abs(middle - 9.4) > 0.6:
                    fail("an arm modelled 3 units out sat at y %.2f, off Halo's "
                         "bone" % (middle,))
            # A plate weighted to the upper arm joins the shell it is worn on,
            # but it is armour rather than skin: it must not drag the side's
            # own centre off the bone, which is what the sleeve is for.
            plate = [Vec(-2.0, 9.0, 57.0), Vec(2.0, 9.0, 57.0),
                     Vec(-2.0, 9.0, 59.0), Vec(2.0, 9.0, 59.0)]
            padded = arm + plate
            padded_weights = per_bone + [{"bip01 l upperarm": 1.0}] * len(plate)
            with_plate = module.side_carry(biped_rig, fp_rig, "l", padded,
                                           padded_weights, middle=arm)
            if with_plate is None:
                fail("an arm with a plate on it was not placed")
            elif max(abs(with_plate["to"][axis] - place["to"][axis])
                     for axis in range(3)) > 1e-6:
                fail("a plate on the arm moved the arm's own centre to %r"
                     % (with_plate["to"],))
        if module.side_carry(None, fp_rig, "l", arm, per_bone) is not None:
            fail("an arm was placed with no biped to measure from")
        if module.side_carry(biped_rig, fp_rig, "r", arm, per_bone) is not None:
            fail("a side with no first-person bone was placed anyway")

        # A bent arm keeps its bend - that is the price of not distorting it -
        # and still goes out along Halo's arm without a single edge changing
        # length against the others.
        if not hasattr(module, "arm_joint"):
            fail("no arm_joint: the glove's hand-over cannot find the wrist")
        bent = [Vec(0.0, 9.0, 56.0), Vec(0.0, 9.0, 46.0), Vec(2.9, 9.0, 39.0),
                Vec(4.9, 9.0, 36.0), Vec(4.9, 9.0, 33.0), Vec(5.6, 9.0, 31.0)]
        bent_weights = [{"bip01 l upperarm": 1.0}, {"bip01 l upperarm": 1.0},
                        {"bip01 l forearm": 1.0}, {"bip01 l forearm": 1.0},
                        {"bip01 l hand": 1.0}, {"bip01 l hand": 1.0}]
        place = module.side_carry(biped_rig, fp_rig, "l", bent, bent_weights)
        if place is None:
            fail("side_carry could not place a bent arm")
        else:
            end = module.place_arm(place, bent[-1])
            print("  side_carry bent    -> hand at %r"
                  % ([round(v, 2) for v in end],))
            if end[0] <= 15.0:
                fail("a bent arm was not carried out along Halo's arm: %r" % (end,))
            # Its bend stands it off the straight bone by as much as the elbow
            # was bent - 5.6 units here - which is the arm's own shape.
            if abs(end[1] - 9.4) > 8.0 or abs(end[2]) > 8.0:
                fail("a bent arm was carried off Halo's arm line: %r" % (end,))
            worst = 1.0
            for i in range(len(bent)):
                for j in range(i + 1, len(bent)):
                    was = math.dist(tuple(bent[i]), tuple(bent[j]))
                    now = math.dist(tuple(module.place_arm(place, bent[i])),
                                    tuple(module.place_arm(place, bent[j])))
                    worst = max(worst, now / was, was / max(now, 1e-9))
            if worst > 1.25 + 1e-9:
                fail("a bent arm was stretched on its way to Halo's rig: x%.2f"
                     % worst)

        # Which way round the glove goes. Lining the arm up with the bone leaves
        # the roll as the model had it, so a glove authored palm-down lands
        # across Halo's hand instead of in it - aligned with the bone and
        # visibly a twist. The glove's own flat has to be laid in Halo's.
        plate = [Vec(step * 1.2, 9.0 + thick, 20.0 + across_wide)
                 for step in range(6) for across_wide in (-2.0, 0.0, 2.0)
                 for thick in (-0.3, 0.3)]
        thin = module.hand_plane(plate, (1.0, 0.0, 0.0))
        print("  hand_plane         -> flat %r"
              % ([round(v, 2) for v in (thin or ())],))
        if thin is None:
            fail("a flat glove was judged too round to have a palm")
        elif abs(abs(thin[1]) - 1.0) > 1e-3:
            fail("the glove's flat came out %r, not across its arm" % (thin,))
        # A thumb sticking out sideways must not be mistaken for the palm's
        # normal: the flat is measured across the arm, so the thumb is only a
        # bit of width.
        thumbed = plate + [Vec(step * 1.2, 9.0 + thick, 22.0 + wide)
                          for step in (0, 1) for wide in (0.0, 1.0)
                          for thick in (-0.3, 0.3)]
        thumb_flat = module.hand_plane(thumbed, (1.0, 0.0, 0.0))
        print("  hand_plane (thumb) -> flat %r"
              % ([round(v, 2) for v in (thumb_flat or ())],))
        if thumb_flat is None or abs(abs(thumb_flat[1]) - 1.0) > 1e-2:
            fail("a glove's thumb tilted its palm's normal to %r" % (thumb_flat,))
        if module.hand_plane([Vec(x, y, z) for x in (0.0, 1.0)
                              for y in (0.0, 1.0) for z in (0.0, 1.0)],
                             (1.0, 0.0, 0.0)) is not None:
            fail("a round cloud was given a palm's normal")
        if module.halo_hand(None, "l") != (None, None):
            fail("halo_hand invented a hand with no rig or mesh to measure")

        flat_turn = (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)
        angle = module.hand_twist(flat_turn, (1.0, 0.0, 0.0),
                                  (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
        laid = module.turn_point(module.turn_about((1.0, 0.0, 0.0), angle),
                                 (0.0, 1.0, 0.0))
        print("  hand_twist         -> %.1f degrees, flat onto %r"
              % (math.degrees(angle), [round(v, 2) for v in laid]))
        if abs(angle - math.pi / 2) > 1e-6 or laid[2] < 0.999:
            fail("a glove a quarter turn out was not turned onto Halo's hand: "
                 "%.1f degrees, %r" % (math.degrees(angle), laid))

        # A hanging arm whose glove is authored with its palm through the x
        # axis - a quarter turn out of Halo's hand, which faces across y.
        hanging = [Vec(0.0, 9.0, 56.0), Vec(3.0, 9.0, 45.0),
                   Vec(-3.0, 9.0, 45.0), Vec(0.0, 9.0, 36.0)]
        hand_points = [Vec(thick, 9.0 + across_wide, 30.0 - step * 1.5)
                       for step in range(4) for across_wide in (-2.0, 0.0, 2.0)
                       for thick in (-0.3, 0.3)]
        # a thumb, so the glove is not the same object half a turn round
        hand_points += [Vec(thick, 9.0 + across_wide, 30.0 - step * 1.5)
                        for step in (0, 1) for across_wide in (3.0, 3.8)
                        for thick in (-0.3, 0.3)]
        hanging += hand_points
        hanging_weights = [{"bip01 l forearm": 1.0}] * len(hanging)
        rolled = module.side_carry(biped_rig, fp_rig, "l", hanging,
                                   hanging_weights, hand_flat=(0.0, 1.0, 0.0))
        if rolled is None:
            fail("a flat glove could not be rolled onto Halo's hand")
        else:
            palm = module.turn_point(rolled["turn"], (1.0, 0.0, 0.0))
            print("  side_carry roll    -> palm across %r, twist %.0f"
                  % ([round(v, 2) for v in palm], rolled["twist"]))
            if abs(abs(palm[1]) - 1.0) > 1e-6:
                fail("the glove's palm landed on %r, not across Halo's hand"
                     % (palm,))
            if abs(rolled["twist"]) < 45.0:
                fail("a glove a quarter turn out was left twisted: %.0f degrees"
                     % rolled["twist"])
            # One more turn about the same arm, so the side still keeps its own
            # shape and its middle still lands on Halo's bone.
            ratios = []
            for i in range(len(hanging)):
                for j in range(i + 1, len(hanging)):
                    was = math.dist(tuple(hanging[i]), tuple(hanging[j]))
                    now = math.dist(tuple(module.place_arm(rolled, hanging[i])),
                                    tuple(module.place_arm(rolled, hanging[j])))
                    ratios.append(now / was)
            if max(ratios) - min(ratios) > 1e-9:
                fail("the roll distorted the arm: %r" % (ratios,))
            moved = [module.place_arm(rolled, point) for point in hanging]
            middle = [sum(point[axis] for point in moved) / len(moved)
                      for axis in range(3)]
            if abs(middle[1] - 9.4) > 0.6 or abs(middle[2]) > 0.6:
                fail("the rolled side's middle sat at %r, off Halo's bone"
                     % (middle,))
            # Two answers lie a glove flat, half a turn apart, and Halo's own
            # hand decides between them: a hand hanging the other way round
            # must flip the choice.
            twin = dict(rolled)
            twin["turn"] = module.turn_product(
                module.turn_about((1.0, 0.0, 0.0), math.pi), rolled["turn"])
            cloud = [module.place_arm(twin, point) for point in hand_points]
            flipped = module.side_carry(biped_rig, fp_rig, "l", hanging,
                                        hanging_weights,
                                        hand_flat=(0.0, 1.0, 0.0),
                                        hand_cloud=cloud)
            other = (module.turn_point(flipped["turn"], (1.0, 0.0, 0.0))
                     if flipped else None)
            print("  side_carry palm    -> %r as worn, %r the other way"
                  % ([round(v, 2) for v in palm],
                     [round(v, 2) for v in (other or ())]))
            if other is None or sum(palm[i] * other[i]
                                    for i in range(3)) > -0.99:
                fail("Halo's own hand did not decide which way round the glove "
                     "goes: %r vs %r" % (palm, other))
        # A fist has no flat to line up: it keeps the item's own roll instead of
        # being turned onto a guess, and the report says so.
        fist_arm = [Vec(0.0, 9.0, 56.0), Vec(3.0, 9.0, 45.0),
                    Vec(-3.0, 9.0, 45.0)]
        fist_arm += [Vec(x, 9.0 + y, 27.0 - z) for x in (-1.6, 1.6)
                     for y in (-1.6, 1.6) for z in (0.0, 2.4)]
        fist = module.side_carry(biped_rig, fp_rig, "l", fist_arm,
                                 [{"bip01 l forearm": 1.0}] * len(fist_arm),
                                 hand_flat=(0.0, 1.0, 0.0))
        print("  side_carry fist   -> glove %r, twist %r"
              % (fist.get("glove") if fist else None,
                 fist.get("twist") if fist else None))
        if fist is None or fist.get("glove") != "round" or fist["twist"] != 0.0:
            fail("a fist was rolled onto a guess: %r" % (fist,))
        if fist is None or fist.get("cuff") is None:
            fail("the carry never said where the sleeve stops and the glove "
                 "starts, so the finger check cannot find the glove: %r"
                 % (fist,))

        # The glove's fingers ride Halo's own finger bones. Riding the hand bone
        # alone, the fingers went wherever a wrist went and never closed round a
        # weapon, which is not what a Marine's hand does holding a rifle.
        if module.HAND_FINGERS != ("index", "middle", "ring", "pinky", "thumb"):
            fail("HAND_FINGERS is %r" % (module.HAND_FINGERS,))
        hand_bones = {
            "frame l wriste": Bone((21.14, 9.40, 0.0), (24.52, 9.40, 0.0)),
            "frame l index low": Bone((24.61, 9.83, 1.52), (26.30, 9.89, 1.75)),
            "frame l index mid": Bone((26.30, 9.89, 1.75), (27.39, 9.86, 1.91)),
            "frame l index tip": Bone((27.39, 9.86, 1.91), (28.47, 9.71, 2.06)),
            "frame l middle low": Bone((24.78, 10.12, 0.33), (26.71, 10.12, 0.33)),
            "frame l middle mid": Bone((26.71, 10.12, 0.33), (27.92, 10.07, 0.33)),
            "frame l middle tip": Bone((27.92, 10.07, 0.33), (29.12, 9.89, 0.33)),
            "frame l thumb low": Bone((22.00, 8.99, 1.47), (23.19, 8.59, 2.38)),
            "frame bone24": Bone((0.0, 0.0, 0.0), (9.40, 0.0, 0.0)),
        }
        hand_rig = types.SimpleNamespace(
            matrix_world=Shift((0.0, 0.0, 0.0)),
            data=types.SimpleNamespace(bones=hand_bones))
        fingers = [name for name, _head, _tail in module.finger_bones(hand_rig, "l")]
        print("  finger_bones       -> %r" % (fingers,))
        if len(fingers) != 7 or "frame bone24" in fingers:
            fail("the finger bones came out %r" % (fingers,))
        span = module.hand_span(hand_rig, "l")
        if span is None:
            fail("Halo's hand could not be measured from its own bones")
        else:
            palm = module.finger_split(Vec(23.0, 9.6, 0.2), hand_rig, "l")
            tip = module.finger_split(Vec(28.9, 9.9, 0.33), hand_rig, "l")
            index = module.finger_split(Vec(28.4, 9.75, 2.0), hand_rig, "l")
            print("  finger_split       -> palm grip %.2f, middle tip grip %.2f on "
                  "%r, index tip on %r"
                  % (palm[0] if palm else -1.0, tip[0] if tip else -1.0,
                     max(tip[1], key=tip[1].get) if tip else None,
                     max(index[1], key=index[1].get) if index else None))
            if palm is None or palm[0] > 1e-9:
                fail("the palm was given finger weights: %r" % (palm,))
            if tip is None or tip[0] < 0.99:
                fail("a fingertip was not given to the finger bones: %r" % (tip,))
            if max(tip[1], key=tip[1].get).split()[2] != "middle":
                fail("the middle fingertip rides %r" % (tip[1],))
            if index is None or max(index[1], key=index[1].get).split()[2] != "index":
                fail("the index fingertip rides %r" % (index[1] if index else None,))
            if module.finger_split(Vec(23.0, 9.6, 0.2), fp_rig, "l") is not None:
                fail("finger weights were invented for a rig with no fingers")
            # A finger's weights come from its own chain, never a neighbour's:
            # the two nearest bones of the whole hand can sit either side of the
            # gap between two fingers and drag the skin across it.
            if any("middle" not in name for name in (tip[1] if tip else {})):
                fail("the middle fingertip takes a neighbour's bone: %r" % (tip[1],))
            # The thumb sits beside the wrist, behind the line the other fingers
            # cross, so a hand-long measure leaves its guard on the wriste bone
            # and it never moves with the thumb. It is found by its own chain.
            thumb = module.finger_split(Vec(23.4, 8.5, 2.5), hand_rig, "l")
            print("  finger_split thumb -> grip %.2f on %r"
                  % (thumb[0] if thumb else -1.0,
                     sorted(thumb[1]) if thumb else None))
            if thumb is None or thumb[0] < 0.9:
                fail("the thumb was left on the wriste bone: %r" % (thumb,))
            if thumb and any("thumb" not in name for name in thumb[1]):
                fail("the thumb skin rides another finger: %r" % (thumb[1],))
            # Where the thumb's skin meets the index's the thumb only just wins,
            # so the weight has to fade in there: at full strength it tore the
            # seam, a thumb-tip vertex pulling away from an index one beside it.
            # The measure is the finger's own length: a vertex just past the
            # knuckle must already be taking some of the finger, or the bend
            # collects in the one loop at the knuckle and creases it.
            knuckle_side = module.finger_split(Vec(25.6, 9.9, 1.5), hand_rig, "l")
            print("  finger_split near  -> grip %.2f on %r"
                  % (knuckle_side[0] if knuckle_side else -1.0,
                     max(knuckle_side[1], key=knuckle_side[1].get)
                     if knuckle_side else None))
            if knuckle_side is None or not 0.4 < knuckle_side[0] < 0.95:
                fail("the glove finger nearest its knuckle was left on the hand: %r"
                     % (knuckle_side,))
            # A glove finger is often one piece with the one beside it, and a
            # piece split between two fingers tears itself in two when they curl
            # apart. A shared piece rides the one finger it mostly is.
            shared = {"frame l index tip": 0.5, "frame l middle tip": 0.5,
                      "frame l wriste": 0.2}
            rode = module.ride_chain(dict(shared), Vec(28.9, 9.9, 0.33),
                                     hand_rig, "l", "middle")
            print("  ride_chain         -> %r" % (rode,))
            allowed = {"frame l middle tip", "frame l middle mid", "frame l wriste"}
            if set(rode) - allowed:
                fail("a shared piece kept another finger's bone: %r" % (rode,))
            if abs(sum(rode.values()) - sum(shared.values())) > 1e-6:
                fail("ride_chain changed the weight total: %r" % (rode,))
            if module.finger_of("frame l wriste") is not None:
                fail("the wrist was taken for a finger")
            # The skin where two fingers join is one piece on a glove modelled
            # as one surface, so a vertex there must take both fingers or the
            # joining web tears as they curl apart.
            web = module.finger_split(Vec(28.8, 9.8, 1.2), hand_rig, "l")
            print("  finger_split web   -> grip %.2f on %r"
                  % (web[0] if web else -1.0, sorted(web[1]) if web else None))
            if web is None or len({name.split()[2] for name in web[1]}) < 2:
                fail("the skin joining two fingers took only one of them: %r"
                     % (web[1] if web else None,))

        # Shoulder plates are not arms. A pauldron is worn over the shoulder
        # rather than on the arm, and carried with an arm that turns about the
        # joint it leaves its place on the body and stands across the arm as a
        # plate that belongs to nothing - which is what the Marine's pauldrons
        # did. It stays on the item's body, where it is worn; the sleeve beside
        # it is still cut.
        rule_groups = [Group(0, "bip01 l clavicle"), Group(1, "bip01 l upperarm"),
                       Group(2, "bip01 spine1")]

        class Spotty:
            def __init__(self, index, per, co):
                self.index = index
                self.co = co
                self.groups = [Entry(group, weight) for group, weight in per]

        body = [
            # a pauldron on the clavicle, sitting over the shoulder
            Spotty(0, ((0, 1.0),), Vec(0.0, 1.0, 0.0)),
            Spotty(1, ((0, 1.0),), Vec(1.0, 1.0, 0.0)),
            Spotty(2, ((0, 1.0),), Vec(0.0, 2.0, 0.0)),
            # a chest plate whose corners carry clavicle weight too
            Spotty(3, ((0, 0.6), (2, 0.4)), Vec(0.0, 20.0, 0.0)),
            Spotty(4, ((0, 0.6), (2, 0.4)), Vec(10.0, 20.0, 0.0)),
            Spotty(5, ((0, 0.6), (2, 0.4)), Vec(0.0, 25.0, 0.0)),
            # a sleeve on the upper arm, out at the arm
            Spotty(6, ((1, 1.0),), Vec(0.0, 40.0, 0.0)),
            Spotty(7, ((1, 1.0),), Vec(5.0, 40.0, 0.0)),
            Spotty(8, ((1, 1.0),), Vec(0.0, 41.0, 0.0)),
        ]
        rule_object = types.SimpleNamespace(
            data=types.SimpleNamespace(
                vertices=body,
                polygons=[Poly(0, 1, 2), Poly(3, 4, 5), Poly(6, 7, 8)]),
            vertex_groups=rule_groups,
            matrix_world=Shift((0.0, 0.0, 0.0)))
        kept = [sorted(piece["indices"]) for piece in module.arm_pieces(rule_object)]
        print("  arm cut plates      -> %r" % (kept,))
        if kept != [[6, 7, 8]]:
            fail("the arm cut kept %r, expected the sleeve alone - a pauldron "
                 "and a chest plate are the body's" % (kept,))
        # The plates stay whole and on the body: the cut never splits a shell,
        # so nothing is left half-carried.

        # The glove has to enclose Halo's finger bones, or their tips stand out
        # of the ends of the fingers and the hand reads as not lined up.
        glove_coords = [(30.0, 9.4, 0.0), (29.6, 9.9, 0.3), (30.2, 9.0, -0.3)]
        short_coords = [(27.0, 9.4, 0.0), (26.6, 9.9, 0.3), (27.2, 9.0, -0.3)]
        hand_slot = {0: 0, 1: 1, 2: 2}
        room = module.finger_room(
            glove_coords, hand_slot, {"l": [0, 1, 2]}, hand_rig)
        short = module.finger_room(
            short_coords, hand_slot, {"l": [0, 1, 2]}, hand_rig)
        print("  finger_room        -> glove %.2f units, short glove %d tip(s) "
              "out" % (room[0] if room else -1.0, short[1] if short else -1))
        if room is None or room[1] != 0 or room[0] <= 0.0 or room[3] != 3:
            fail("a glove past Halo's fingertips did not enclose them: %r"
                 % (room,))
        if short is None or short[1] == 0:
            fail("a glove stopping short of the fingertips was not noticed: %r"
                 % (short,))
        # The glove is what is past the wrist, and only that is measured. A
        # sleeve or a bracer runs further along the arm than the hand does, so
        # a whole-arm measurement reports room the glove does not have and
        # hides a glove that stopped short of Halo's fingers - which is what
        # the report used to do.
        sleeve = [(35.0, 9.4, 0.0)]
        with_sleeve = short_coords + sleeve
        four = {0: 0, 1: 1, 2: 2, 3: 3}
        whole = module.finger_room(with_sleeve, four,
                                   {"l": [0, 1, 2, 3]}, hand_rig)
        glove = module.finger_room(with_sleeve, four, {"l": [0, 1, 2]}, hand_rig)
        print("  finger_room sleeve -> whole arm %d tip(s) out, glove %d out"
              % (whole[1] if whole else -1, glove[1] if glove else -1))
        if whole is None or whole[1] != 0:
            fail("a sleeve past Halo's fingertips should look covered when the "
                 "whole arm is measured: %r" % (whole,))
        if glove is None or glove[1] == 0:
            fail("a glove stopping short was hidden by the sleeve behind it: "
                 "%r" % (glove,))
        # Which vertices are the glove is answered at the wrist, by the same
        # line the carry placed the glove by.
        place = {"shoulder": (0.0, 0.0, 0.0), "axis": (0.0, 1.0, 0.0),
                 "cuff": 30.0}
        print("  glove_of           -> sleeve %r, glove %r, no carry %r"
              % (module.glove_of(place, (0.0, 25.0, 0.0)),
                 module.glove_of(place, (0.0, 32.0, 0.0)),
                 module.glove_of(None, (0.0, 32.0, 0.0))))
        if (module.glove_of(place, (0.0, 25.0, 0.0))
                or not module.glove_of(place, (0.0, 32.0, 0.0))
                or module.glove_of(None, (0.0, 32.0, 0.0))):
            fail("the glove was not taken from the sleeve at the wrist")
        # Every finger bone is measured against the glove's own skin, so a thumb
        # outside its glove is named instead of being averaged away by whichever
        # finger reached furthest. The box is the glove: it holds the fingers,
        # and the thumb hangs below and above it.
        box = [(21.0, 9.5, -1.4), (21.0, 9.5, 2.2),
               (21.0, 10.6, -1.4), (21.0, 10.6, 2.2),
               (30.0, 9.5, -1.4), (30.0, 9.5, 2.2),
               (30.0, 10.6, -1.4), (30.0, 10.6, 2.2)]
        box_faces = [Poly(0, 1, 3), Poly(0, 3, 2), Poly(4, 6, 7),
                     Poly(4, 7, 5), Poly(0, 4, 5), Poly(0, 5, 1),
                     Poly(2, 3, 7), Poly(2, 7, 6), Poly(0, 2, 6),
                     Poly(0, 6, 4), Poly(1, 5, 7), Poly(1, 7, 3)]
        box_slot = {index: index for index in range(8)}
        gaps = module.finger_gaps(box, box_slot, {"l": list(range(8)), "r": []},
                                  box_faces, hand_rig)
        by_bone = {(entry["side"], entry["bone"]): entry["gap"]
                   for entry in gaps or []}
        middle = by_bone.get(("l", "middle tip"))
        thumb = by_bone.get(("l", "thumb low"))
        print("  finger_gaps        -> %d bone(s), middle tip %s, thumb %s"
              % (len(gaps or []),
                 "%+.2f" % middle if middle is not None else "none",
                 "%+.2f" % thumb if thumb is not None else "none"))
        if gaps is None or len(gaps) != 7:
            fail("the per-finger check measured %r bone(s), expected 7"
                 % (len(gaps or []),))
        elif middle is None or middle >= 0.0:
            fail("a finger inside the glove was not measured inside: %r"
                 % (middle,))
        elif thumb is None or thumb <= 0.0:
            fail("a thumb hanging outside the glove was not caught: %r"
                 % (thumb,))
        elif not 0.3 < thumb < 1.5:
            fail("the thumb's distance from the glove came out %r" % (thumb,))
        if module.finger_gaps(box, box_slot, {"l": [], "r": []},
                              box_faces, hand_rig) is not None:
            fail("a side with no glove was measured anyway")
        # A glove the item wound backwards must measure the same: the sign of
        # the distance is decided by the shell, not by the order of its corners.
        backwards = [Poly(*reversed(face.vertices)) for face in box_faces]
        reversed_gaps = module.finger_gaps(
            box, box_slot, {"l": list(range(8)), "r": []}, backwards, hand_rig)
        reversed_by_bone = {(entry["side"], entry["bone"]): entry["gap"]
                            for entry in reversed_gaps or []}
        print("  finger_gaps wound  -> middle tip %s, thumb %s"
              % ("%+.2f" % reversed_by_bone[("l", "middle tip")]
                 if ("l", "middle tip") in reversed_by_bone else "none",
                 "%+.2f" % reversed_by_bone[("l", "thumb low")]
                 if ("l", "thumb low") in reversed_by_bone else "none"))
        if (set(reversed_by_bone) != set(by_bone)
                or any(abs(reversed_by_bone[key] - by_bone[key]) > 1e-6
                       for key in by_bone)):
            fail("a glove wound backwards changed the measured gaps: %r vs %r"
                 % (reversed_by_bone, by_bone))

        # A closed shell the item itself had inside out is written the right way
        # round - from outside it shows its own blank back - while an open plate
        # is never flipped on a guess: that would hide the side a person sees.
        cube = [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (1.0, 1.0, 0.0),
                (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (1.0, 0.0, 1.0),
                (1.0, 1.0, 1.0), (0.0, 1.0, 1.0)]
        outward = [Poly(0, 3, 2, 1), Poly(4, 5, 6, 7), Poly(0, 1, 5, 4),
                   Poly(1, 2, 6, 5), Poly(2, 3, 7, 6), Poly(3, 0, 4, 7)]
        inward = [Poly(*reversed(face.vertices)) for face in outward]
        slots = {index: index for index in range(8)}
        print("  inside_out         -> outward %r, inward %r, open %r"
              % (module.inside_out(outward, cube, slots),
                 module.inside_out(inward, cube, slots),
                 module.inside_out(outward[1:], cube, slots)))
        if module.inside_out(outward, cube, slots):
            fail("a closed shell the right way round was called inside out")
        if not module.inside_out(inward, cube, slots):
            fail("a closed shell wound inward was not noticed")
        if module.inside_out(outward[1:], cube, slots):
            fail("an open plate was flipped on a guess")

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
            failed, failed_rig = module.arms_for(
                types.SimpleNamespace(name="UNSC Marine Armor"),
                types.SimpleNamespace(name="biped"),
                types.SimpleNamespace(name="arms rig"), None, record)
        finally:
            module.arm_region = original
        print("  arms_for (bad cut)  -> %r, %r, %r"
              % (failed, failed_rig, record.get("arms_binding")))
        if failed is not None or failed_rig is not None:
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
