#!/usr/bin/env python3
"""Prove a whole body is fitted to Halo's biped, joint by joint.

A garment is put on the biped by its own edge and one uniform scale, which is
right for a hat: it only has to reach the same part of the body. A body is not
that. The armour carries the avatar's own skeleton, and every joint of it has to
end up on the matching bone - the shoulders on the upper arms, the elbows on the
forearms, the knees on the calves - or Halo's animations bend something the
armour is not. The mesh is what moves: Halo's animations carry a node transform
for every frame, so a skeleton shrunk to a short item would be put straight back
by the first frame of the game's own animation.

This test builds a body the way the Marine's is built - a vertex at each of the
avatar's joints, a helmet above the head, a glove past the hand, a boot under
the ankle, all in the item's own pose - fits it the way the pipeline does, and
checks:

  * every joint lands on its bone, not merely near it;
  * every bone between two joints ends up the length of Halo's bone, which is
    what carries a short avatar's elbow onto Halo's elbow rather than short of
    it;
  * the arm comes down out of the item's pose onto Halo's arm, which hangs;
  * the helmet rides the head and not the neck above it;
  * the soles end on the floor and nothing sinks through it;
  * and each of those checks fails on a fit that drops the thing it measures -
    no turn, no length, no leaf cap - so a check that passes means something.

    python3 tools/test_body_fit.py

Exits 0 only when every check passes.
"""

import importlib.util
import math
import os
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))
MODULES = os.environ.get("RIG_MODULES") or os.path.join(
    os.path.dirname(HERE), "src")

# Halo CE's own 19-bone biped, from the rig file the pipeline ships: bone heads
# in Halo units, the space the item is fitted in.
BONES = {
    "bip01 pelvis": (-0.82, 0.00, 39.44),
    "bip01 spine": (-0.83, 0.00, 43.18),
    "bip01 spine1": (-0.83, 0.00, 50.58),
    "bip01 neck": (-0.82, 0.00, 59.19),
    "bip01 head": (-0.72, 0.00, 60.91),
    "bip01 l clavicle": (-0.82, 5.98, 56.92),
    "bip01 l upperarm": (-0.82, 9.02, 56.92),
    "bip01 l forearm": (-0.73, 11.14, 46.27),
    "bip01 l hand": (0.95, 13.32, 35.23),
    "bip01 r clavicle": (-0.82, -5.98, 56.92),
    "bip01 r upperarm": (-0.82, -9.02, 56.92),
    "bip01 r forearm": (-0.73, -11.14, 46.27),
    "bip01 r hand": (0.95, -13.32, 35.23),
    "bip01 l thigh": (-0.82, 4.22, 39.44),
    "bip01 l calf": (-1.40, 5.31, 22.27),
    "bip01 l foot": (-3.90, 6.30, 6.88),
    "bip01 r thigh": (-0.82, -4.22, 39.44),
    "bip01 r calf": (-1.34, -5.23, 22.26),
    "bip01 r foot": (-3.91, -6.14, 6.88),
}

IDENTITY = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))


class Vec:
    """Just enough of mathutils.Vector for the module's import and helpers."""

    def __init__(self, x=0.0, y=0.0, z=0.0):
        if not isinstance(x, (int, float)):
            x, y, z = x[0], x[1], x[2]
        self.x, self.y, self.z = float(x), float(y), float(z)

    def __getitem__(self, index):
        return (self.x, self.y, self.z)[index]

    def __sub__(self, other):
        return Vec(self.x - other[0], self.y - other[1], self.z - other[2])

    def __add__(self, other):
        return Vec(self.x + other[0], self.y + other[1], self.z + other[2])

    def __mul__(self, amount):
        return Vec(self.x * amount, self.y * amount, self.z * amount)

    __rmul__ = __mul__

    def dot(self, other):
        return self.x * other[0] + self.y * other[1] + self.z * other[2]

    @property
    def length_squared(self):
        return self.dot(self)

    @property
    def length(self):
        return math.sqrt(self.dot(self))


class Identity:
    def __matmul__(self, other):
        return tuple(other)


class Bone:
    def __init__(self, head):
        self.head_local = head


class Body:
    """The smallest mesh object the fit reads: points, edges, and writing back."""

    class Vertex:
        def __init__(self, co):
            self.co = co

    class Edge:
        def __init__(self, first, second):
            self.vertices = (first, second)

    def __init__(self, points, edges):
        self.vertices = [Body.Vertex(point) for point in points]
        self.edges = [Body.Edge(first, second) for first, second in edges]
        self.updated = 0

    def update(self):
        self.updated += 1


def load():
    bpy = types.ModuleType("bpy")
    bpy.context = types.SimpleNamespace()
    bpy.ops = types.SimpleNamespace()
    bpy.data = types.SimpleNamespace(images=[], materials=[], texts=[])
    bpy.app = types.SimpleNamespace(version_string="stub")
    mathutils = types.ModuleType("mathutils")
    mathutils.Vector = Vec
    mathutils.Quaternion = tuple
    sys.modules["bpy"] = bpy
    sys.modules["mathutils"] = mathutils
    path = os.path.join(MODULES, "rig_items.py")
    spec = importlib.util.spec_from_file_location("rig_items_body_test", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def armature():
    bones = {name: Bone(head) for name, head in BONES.items()}
    return types.SimpleNamespace(
        matrix_world=Identity(), data=types.SimpleNamespace(bones=bones))


def body(module, boot=-3.0):
    """A body standing where the item puts its own joints.

    The item's joints are the avatar's, in metres; ``halo_point`` carries them
    into the space the biped is in, which is what the pipeline's own fit reads.
    ``boot`` is how far below the ankle the sole is: a shallow boot leaves the
    body standing above the floor, a deep one dips under it.
    """
    order = [nxe for nxe, _bone, _beyond in module.BODY_JOINTS]
    slot = {nxe: position for position, nxe in enumerate(order)}
    points = [module.halo_point(module.NXE_JOINTS[nxe]) for nxe in order]
    edges = []
    for nxe, _bone, beyond in module.BODY_JOINTS:
        if beyond is not None and beyond in slot:
            edges.append((slot[nxe], slot[beyond]))
    # A helmet above the head joint, a glove past the hand, a boot below the
    # ankle: the three leaf regions the fit has to keep with their own joint.
    head = slot[19]
    helmet = len(points)
    points.append(tuple(points[head][axis] + (0.0, 0.0, 12.0)[axis]
                        for axis in range(3)))
    edges.append((head, helmet))
    for hand, out in ((slot[33], 1.0), (slot[36], -1.0)):
        points.append(tuple(points[hand][axis] + (0.0, 10.0 * out, 0.0)[axis]
                            for axis in range(3)))
        edges.append((hand, len(points) - 1))
    for ankle in (slot[11], slot[15]):
        points.append(tuple(points[ankle][axis] + (0.0, 0.0, boot)[axis]
                            for axis in range(3)))
        edges.append((ankle, len(points) - 1))
    return points, edges, slot, helmet


def gap(first, second):
    return math.dist(first, second)


def angle(first, second):
    a = [value / max(math.dist((0.0, 0.0, 0.0), first), 1e-9) for value in first]
    b = [value / max(math.dist((0.0, 0.0, 0.0), second), 1e-9) for value in second]
    dot = max(-1.0, min(1.0, sum(a[i] * b[i] for i in range(3))))
    return math.degrees(math.acos(dot))


# The avatar's pelvis and the joint above it sit on the same point, so one
# vertex there cannot be on both bones and the pair has no length to scale. That
# is the avatar skeleton's own shape, not something the fit can fix, so the two
# are left out of the checks that would ask for the impossible.
SHARED = (0, 1)


def worst_joint(placed, plan, slot, lift=0.0):
    """The worst distance from a joint of the item to its bone."""
    worst, name = 0.0, ""
    for entry in plan:
        if entry["joint"] in SHARED:
            continue
        moved = tuple(placed[slot[entry["joint"]]][axis] - (lift if axis == 2 else 0.0)
                      for axis in range(3))
        distance = gap(moved, entry["target"])
        if distance > worst:
            worst, name = distance, entry["bone"]
    return worst, name


def worst_bone(placed, plan, slot):
    """The worst difference between a bone's length and Halo's, as a fraction."""
    by_joint = {entry["joint"]: entry for entry in plan}
    worst, name = 0.0, ""
    for entry in plan:
        beyond = entry["beyond"]
        if beyond is None or beyond not in by_joint:
            continue
        if entry["joint"] in SHARED or beyond in SHARED:
            continue
        mine = gap(placed[slot[entry["joint"]]], placed[slot[beyond]])
        theirs = gap(entry["target"], by_joint[beyond]["target"])
        if theirs <= 1e-9:
            continue
        off = abs(mine - theirs) / theirs
        if off > worst:
            worst, name = off, entry["bone"]
    return worst, name


def arm_angle(placed, plan, slot, side):
    """How far the fitted arm is from the bone it has to lie along."""
    by_joint = {entry["joint"]: entry for entry in plan}
    shoulder, elbow, wrist = (20, 25, 33) if side == "l" else (22, 28, 36)
    mine = [placed[slot[elbow]][axis] - placed[slot[shoulder]][axis]
            for axis in range(3)]
    theirs = [by_joint[elbow]["target"][axis] - by_joint[shoulder]["target"][axis]
              for axis in range(3)]
    return angle(mine, theirs), (wrist, by_joint[wrist]["target"])


def main():
    module = load()
    rig = armature()
    failures = []

    def fail(message):
        failures.append(message)
        print("  FAIL %s" % message)

    points, edges, slot, helmet = body(module)
    plan = module.body_fit_plan(rig, 1.0, points)
    if len(plan) != len(module.BODY_JOINTS):
        fail("the plan holds %d joints, not %d"
             % (len(plan), len(module.BODY_JOINTS)))
        print("\nFAILED: %d check(s)" % len(failures))
        return 1
    print("  %d joints, %d points, %d edges" % (len(plan), len(points), len(edges)))

    placed, scale, worst = module.fit_body_points(points, edges, plan)
    expected = BONES["bip01 head"][2] / module.halo_point(module.NXE_JOINTS[19])[2]
    print("  the item's head joint on Halo's head node: x%.3f" % scale)
    if abs(scale - expected) > 1e-6:
        fail("the fit scaled x%.4f, not the head node's x%.4f" % (scale, expected))

    distance, name = worst_joint(placed, plan, slot)
    print("  worst joint: %s is %.3f units from its bone" % (name, distance))
    if distance > 0.5:
        fail("%s misses its bone by %.2f units, so the fit is not on the bones"
             % (name, distance))

    off, name = worst_bone(placed, plan, slot)
    print("  worst bone length: %s is %.1f%% off Halo's" % (name, off * 100.0))
    if off > 0.01:
        fail("%s ends up %.1f%% the wrong length, so the joint past it is off"
             % (name, off * 100.0))

    for side in ("l", "r"):
        turn, _rest = arm_angle(placed, plan, slot, side)
        print("  %s arm: %.1f deg off Halo's arm bone" % (side, turn))
        if turn > 2.0:
            fail("the %s arm is still %.1f deg off Halo's, so it was not turned "
                 "down into the biped's pose" % (side, turn))

    rise = placed[helmet][2] - BONES["bip01 head"][2]
    print("  helmet rides the head: %.1f units above the head node (%.1f "
          "expected)" % (rise, 12.0 * scale))
    if abs(rise - 12.0 * scale) > 0.5:
        fail("the helmet sits %.1f units above the head node, not the %.1f it "
             "would if it rode the head" % (rise, 12.0 * scale))

    # A body whose soles dip under the floor has to come back up onto it. The
    # shallow body above never dips, so this is the case that tests the lift.
    deep_points, deep_edges, _deep, _head = body(module, boot=-8.0)
    deep_plan = module.body_fit_plan(rig, 1.0, deep_points)
    deep_placed, _scale, _worst = module.fit_body_points(deep_points, deep_edges,
                                                         deep_plan)
    floor = min(point[2] for point in deep_placed)
    print("  soles that started %.1f units under the floor end at %.3f"
          % (8.0 * scale - BONES["bip01 l foot"][2], floor))
    if abs(floor) > 1e-6:
        fail("the soles end at %.3f units, not on the floor" % floor)

    # A check that cannot fail is not a check: each of the three is run again
    # against a fit that drops the thing it measures.
    flat = [dict(entry, turn=IDENTITY) for entry in plan]
    turned, _scale, _worst = module.fit_body_points(points, edges, flat)
    for side in ("l", "r"):
        turn, _rest = arm_angle(turned, flat, slot, side)
        if turn <= 2.0:
            fail("a fit with every turn removed still passes the arm check "
                 "(%s %.1f deg), so the check proves nothing" % (side, turn))
    short = [dict(entry, axial=None) for entry in plan]
    stretched, _scale, _worst = module.fit_body_points(points, edges, short)
    off, name = worst_bone(stretched, short, slot)
    if off <= 0.01:
        fail("a fit with no length stretch still passes the bone check "
             "(%s %.1f%%), so the check proves nothing" % (name, off * 100.0))
    bare = [dict(entry, cap=0.0) for entry in plan]
    capped, _scale, _worst = module.fit_body_points(points, edges, bare)
    rise = capped[helmet][2] - BONES["bip01 head"][2]
    if abs(rise - 12.0 * scale) <= 0.5:
        fail("a fit with the leaf caps removed still puts the helmet on the "
             "head, so the check proves nothing")

    print()
    if failures:
        print("FAILED: %d check(s)" % len(failures))
        return 1
    print("PASSED: every joint of the item is on its bone, every bone is Halo's "
          "length, the arms are down in Halo's pose and the helmet rides the head")
    return 0


if __name__ == "__main__":
    sys.exit(main())
