#!/usr/bin/env python3
"""Check that a glove's thumb guard is seated in the palm, not hung off the thumb.

The guard is a plate standing about 1.5 units off Halo's thumb chain, and Halo's
thumb bone runs outside it. Weighted wholly to the thumb, the plate swings clear
of the palm as soon as the thumb bends and the gap underneath opens - measured
posed at 30/25/20 on the Marine, the worst edge went to x2.49. Weighted wholly to
the hand, the plate never moves and the thumb is dead.

So the share of the hand bone falls off along the thumb, from THUMB_SEATED at the
guard's base to THUMB_FREE at its tip. That is a claim about behaviour, and this
test measures it rather than trusting it:

  * every vertex of the plate is seated, and its weights still sum to one;
  * the base rides THUMB_SEATED of the hand bone and the tip THUMB_FREE, with
    the share only falling from base to tip;
  * the thumb's own share is scaled by what is left, so nothing is invented or
    lost;
  * a vertex that is not on the thumb - an index finger, a palm - is not touched;
  * a vertex on the other hand is not touched either;
  * and posed, the guard's base moves by (1 - share) of what it moved before,
    which is the whole point: the plate stays with the palm while the tip still
    follows the thumb.

    python3 tools/test_thumb_seated.py

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

# Halo's own left thumb, from the first-person rig, in Halo units.
THUMB = [
    ("frame l thumb low", (22.00, 8.99, 1.47), (23.19, 8.59, 2.38)),
    ("frame l thumb mid", (23.19, 8.59, 2.38), (24.12, 8.42, 2.94)),
    ("frame l thumb tip", (24.12, 8.42, 2.94), (25.09, 8.26, 3.41)),
]
HAND = "frame l wriste"
OTHER_HAND = "frame r wriste"


class Vec:
    """Just enough of mathutils.Vector for the module's distance helpers."""

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
    spec = importlib.util.spec_from_file_location("rig_items_seated_test", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def entries():
    """The chain the module reads, in the order it sorts them: low, mid, tip."""
    return [(name, head, tail, name.split(" ", 2)[2].replace(" ", ""))
            for name, head, tail in THUMB]


def plate(steps=9, offset=1.5):
    """A guard: along the thumb's chain, standing `offset` units off it."""
    first, last = THUMB[0][1], THUMB[-1][2]
    length = math.dist(first, last)
    axis = [(last[i] - first[i]) / length for i in range(3)]
    aside = [-axis[2], 0.0, axis[0]]
    size = math.sqrt(sum(value * value for value in aside))
    aside = [value / size for value in aside]
    return [tuple(first[i] + (last[i] - first[i]) * (step / (steps - 1.0))
                  + aside[i] * offset for i in range(3))
            for step in range(steps)]


def turned(point, head, axis, degrees):
    """Rotate `point` about the line through `head` along `axis`."""
    radians = math.radians(degrees)
    cosine, sine = math.cos(radians), math.sin(radians)
    relative = [point[i] - head[i] for i in range(3)]
    cross = [axis[1] * relative[2] - axis[2] * relative[1],
             axis[2] * relative[0] - axis[0] * relative[2],
             axis[0] * relative[1] - axis[1] * relative[0]]
    along = sum(axis[i] * relative[i] for i in range(3))
    return [head[i] + relative[i] * cosine + cross[i] * sine
            + axis[i] * along * (1.0 - cosine) for i in range(3)]


def main():
    module = load()
    chain = entries()
    points = plate()
    base, tip = points[0], points[-1]
    failures = []

    def fail(message):
        failures.append(message)
        print("  FAIL %s" % message)

    seated_share = module.THUMB_SEATED
    free_share = module.THUMB_FREE
    print("  the module seats %.0f%% at the base and %.0f%% at the tip"
          % (seated_share * 100.0, free_share * 100.0))
    if not 0.0 < free_share < seated_share < 1.0:
        fail("the seating shares are not a fall-off: base %r, tip %r"
             % (seated_share, free_share))

    # Weight the plate the way the pipeline does, then seat it.
    weights = {}
    position = {}
    for index, point in enumerate(points):
        weights[index] = {name: weight
                          for weight, name in module.chain_along(point, chain)}
        position[index] = point
    untouched = {"frame l index low": 1.0}
    weights[100] = dict(untouched)
    position[100] = (24.6, 10.1, 0.4)
    weights[101] = {"frame r thumb mid": 1.0}
    position[101] = (24.6, 10.1, 0.4)
    side_of = {index: "l" for index in range(len(points))}
    side_of[100] = "l"
    side_of[101] = "r"

    returned = module.seat_thumb(weights, position, list(THUMB[0][1]),
                                 list(THUMB[-1][2]), HAND,
                                 side="l", side_of=side_of)
    print("  seated %d of %d plate vertices" % (len(returned), len(points)))
    if sorted(returned) != list(range(len(points))):
        fail("the plate was not seated whole: %r" % (sorted(returned),))

    for index in range(len(points)):
        total = sum(weights[index].values())
        if abs(total - 1.0) > 1e-6:
            fail("plate vertex %d sums to %r, so weight was invented or lost"
                 % (index, total))
        if weights[index].get(HAND, 0.0) <= 0.0:
            fail("plate vertex %d got no hand bone at all" % index)

    # Nothing off the thumb may move: the index vertex keeps exactly its weights,
    # and the other hand's thumb vertex is not touched.
    if weights[100] != untouched:
        fail("a vertex off the thumb was changed: %r" % (weights[100],))
    if weights[101] != {"frame r thumb mid": 1.0}:
        fail("a vertex on the other hand was changed: %r" % (weights[101],))

    # Base to tip, the hand's share can only fall, and it must reach both ends.
    hand = [weights[index].get(HAND, 0.0) for index in range(len(points))]
    print("  hand share base %.2f .. tip %.2f" % (hand[0], hand[-1]))
    if abs(hand[0] - seated_share) > 0.02:
        fail("the base rides %.3f of the hand, not the %.3f it should"
             % (hand[0], seated_share))
    if abs(hand[-1] - free_share) > 0.02:
        fail("the tip rides %.3f of the hand, not the %.3f it should"
             % (hand[-1], free_share))
    if any(first < second - 1e-6 for first, second in zip(hand, hand[1:])):
        fail("the hand's share rises again towards the tip: %r"
             % ([round(value, 2) for value in hand],))

    # The thumb's own share is scaled by what the hand leaves it.
    for index in (0, len(points) // 2, len(points) - 1):
        thumb_total = sum(weight for name, weight in weights[index].items()
                          if module.finger_of(name) == "thumb")
        expected = 1.0 - hand[index]
        if abs(thumb_total - expected) > 1e-6:
            fail("plate vertex %d keeps %.3f on the thumb, not %.3f"
                 % (index, thumb_total, expected))

    # Posed: the whole reason for the share. Turning the thumb's base bone 30
    # degrees has to move the guard's base by (1 - share) of what it moved with
    # all of the weight on the thumb, so the plate stays with the palm.
    head = THUMB[0][1]
    bone = [THUMB[0][2][i] - head[i] for i in range(3)]
    size = math.sqrt(sum(value * value for value in bone))
    bone = [value / size for value in bone]
    # Turn about the axis square to both the bone and the plate's stand-off, so
    # the bend swings the plate rather than spinning it in place.
    offset = [base[i] - head[i] for i in range(3)]
    turn_axis = [bone[1] * offset[2] - bone[2] * offset[1],
                 bone[2] * offset[0] - bone[0] * offset[2],
                 bone[0] * offset[1] - bone[1] * offset[0]]
    size = math.sqrt(sum(value * value for value in turn_axis))
    turn_axis = [value / size for value in turn_axis]
    moved = turned(base, head, turn_axis, 30.0)
    rigid = math.dist(moved, base)
    kept = rigid * (1.0 - hand[0])
    print("  posed 30 degrees: the base moved %.3f of the %.3f it would have"
          % (kept, rigid))
    if rigid <= 0.1:
        fail("the test's own pose barely moves the base (%.3f), so it proves "
             "nothing" % rigid)
    if abs(kept - rigid * (1.0 - seated_share)) > 1e-6:
        fail("the base does not move by (1 - share) of the rigid move")
    if kept >= rigid * 0.75:
        fail("the base still moves %.0f%% of the way, so the plate is not "
             "seated" % (100.0 * kept / rigid))

    print()
    if failures:
        print("FAILED: %d check(s)" % len(failures))
        return 1
    print("PASSED: the guard is seated in the palm and stays there when the "
          "thumb bends")
    return 0


if __name__ == "__main__":
    sys.exit(main())
