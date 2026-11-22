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

    # What belongs in the first-person set: whole shells picked by the bones
    # they are mostly weighted to, and carried across rigidly so no piece can be
    # stretched or torn off the arm.
    for name in ("arm_share", "ARM_SHARE", "arm_pieces", "arm_axis",
                 "alignment", "place_point", "side_carry", "hand_share",
                 "place_pad", "principal_axes", "hand_plane", "turn_about",
                 "turn_product", "turn_point", "hand_twist", "hand_fit",
                 "halo_hand", "HAND_FINGERS", "hand_span", "finger_bones",
                 "finger_split"):
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
            if not 0.75 - 1e-9 <= ratios[0] <= 1.25 + 1e-9:
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
            # Shoulder armour rides the shoulder, upright, instead of turning
            # with the arm: a pad sits above the joint the arm hangs from, so
            # the arm's quarter turn swings that height round into a plate
            # standing across the arm - the fins the Marine set came out with.
            if not hasattr(module, "place_pad"):
                fail("no place_pad: shoulder armour would turn with the arm")
            else:
                # a pad worn above the shoulder joint: 1 and 3 units over it
                pad = [Vec(-2.0, 9.0, 57.0), Vec(2.0, 9.0, 57.0),
                       Vec(-2.0, 9.0, 59.0), Vec(2.0, 9.0, 59.0)]
                pad_now = [module.place_pad(place, point) for point in pad]
                turned = [module.place_arm(place, point) for point in pad]
                height = sum(point[2] for point in pad_now) / len(pad_now)
                turned_height = sum(point[2] for point in turned) / len(turned)
                print("  place_pad          -> pad height %.2f (turned %.2f) "
                      "from %r / %r"
                      % (height, turned_height, tuple(pad_now[0]),
                         tuple(turned[0])))
                if height < 0.5 or height <= turned_height:
                    fail("a pad above the shoulder came out at z %.2f, turned "
                         "with the arm (%.2f)" % (height, turned_height))
                ratios = []
                for i in range(len(pad)):
                    for j in range(i + 1, len(pad)):
                        was = math.dist(tuple(pad[i]), tuple(pad[j]))
                        now = math.dist(tuple(pad_now[i]), tuple(pad_now[j]))
                        ratios.append(now / was)
                if max(ratios) - min(ratios) > 1e-9:
                    fail("the pad carry distorted the pad: %r" % (ratios,))
                # A pad weighted to the upper arm is the item's shoulder plate,
                # not part of its skin: it must not drag the side's centre off
                # the bone.
                padded = arm + pad
                padded_weights = per_bone + [{"bip01 l upperarm": 1.0}] * len(pad)
                with_pad = module.side_carry(biped_rig, fp_rig, "l", padded,
                                             padded_weights, middle=arm)
                if with_pad is None:
                    fail("an arm with a pad was not placed")
                elif max(abs(with_pad["to"][axis] - place["to"][axis])
                         for axis in range(3)) > 1e-6:
                    fail("a shoulder pad moved the arm's own centre to %r"
                         % (with_pad["to"],))
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

        # The shoulder rule, exercised: a pad that hugs a clavicle is kept and
        # rides the upper arm, and a chest plate carrying the same clavicle
        # weight stays on the body because it never comes near the shoulder.
        # Halo's own first-person arms wear their pads, so this is the rule that
        # has to hold - it was assumed before, not tested.
        if not hasattr(module, "near_shoulder"):
            fail("no near_shoulder: a chest plate would ride in with the pads")
        else:
            class Bone:
                def __init__(self, head, tail):
                    self.head_local = head
                    self.tail_local = tail

            shoulder_rig = types.SimpleNamespace(
                matrix_world=Shift((0.0, 0.0, 0.0)),
                data=types.SimpleNamespace(bones={
                    "bip01 l clavicle": Bone(Vec(0.0, 0.0, 0.0), Vec(0.0, 10.0, 0.0)),
                    "bip01 r clavicle": Bone(Vec(0.0, 0.0, 0.0), Vec(0.0, -10.0, 0.0)),
                }))
            rule_groups = [Group(0, "bip01 l clavicle"), Group(1, "bip01 l upperarm"),
                           Group(2, "bip01 spine1")]

            class Spotty:
                def __init__(self, index, per, co):
                    self.index = index
                    self.co = co
                    self.groups = [Entry(group, weight) for group, weight in per]

            body = [
                # a pad sitting on the clavicle: within a few units of it
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
            rule = module.arm_pieces(rule_object, armature=shoulder_rig)
            shoulder_kept = [sorted(piece["indices"]) for piece in rule]
            print("  shoulder rule       -> %r" % (shoulder_kept,))
            if shoulder_kept != [[0, 1, 2], [6, 7, 8]]:
                fail("the shoulder rule kept %r, expected the pad and the sleeve"
                     % (shoulder_kept,))
            pad = [piece for piece in rule if sorted(piece["indices"]) == [0, 1, 2]]
            if pad and pad[0]["bone"] != "bip01 l upperarm":
                fail("the pad rides %r, not the upper arm" % (pad[0]["bone"],))
            if module.near_shoulder(rule_object, {3, 4, 5}, shoulder_rig):
                fail("a chest plate was judged to sit on the shoulder")
            if not module.near_shoulder(rule_object, {0, 1, 2}, shoulder_rig):
                fail("a pad on the clavicle was judged not to sit on it")
            # Without the rig there is nothing to measure, so no shoulder shell
            # is guessed at: the pad stays on the body rather than a chest plate
            # coming into the arms uninvited.
            loose = module.arm_pieces(rule_object)
            if [sorted(piece["indices"]) for piece in loose] != [[6, 7, 8]]:
                fail("with no armature the shoulder rule kept %r, expected only "
                     "the sleeve" % ([sorted(p["indices"]) for p in loose],))

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
