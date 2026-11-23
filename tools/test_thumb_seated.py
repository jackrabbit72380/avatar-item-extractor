#!/usr/bin/env python3
"""Check that a glove's thumb guard is seated in the palm, not hung off the thumb.

The guard is a plate standing about 1.5 units off Halo's thumb chain, and Halo's
thumb bone runs outside it. Weighted wholly to the thumb, the plate swings clear
of the palm as soon as the thumb bends and the gap underneath opens; weighted
wholly to the hand, it never moves and the thumb is dead.

A share added on top of the thumb's weights does not work either: a .jms carries
two weights a vertex, so the extra one makes the export drop a bone the plate was
using, and the plate tears - measured posed at 30/25/20, x5.84. So the chain
itself is carried back past the thumb's base into the palm and the guard takes
the two bones that straddle it, as any other skin does.

This test builds a plate the way the Marine's guard is built, weights it the way
the pipeline does, seats it, and checks:

  * every vertex of the plate is seated, and its weights still sum to one;
  * no vertex rides more than two bones, so the .jms can carry all of it;
  * the guard's base rides the hand bone and its tip does not, so the plate is
    seated at the root and still follows the thumb at the end;
  * neighbouring plate vertices always share a bone - the property whose absence
    is a tear;
  * a vertex that is not on the thumb, and a vertex on the other hand, are left
    alone;
  * and posed, the guard's base moves well under what it moved with all of its
    weight on the thumb.

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


def plate(steps=11, offset=1.5, behind=0.2):
    """A guard: along the thumb's chain, standing `offset` units off it.

    It starts `behind` units short of the thumb's base, because the Marine's
    guard does - its root sits back over the palm, which is exactly why the
    plate swings off the hand when the thumb bends.
    """
    first, last = THUMB[0][1], THUMB[-1][2]
    length = math.dist(first, last)
    axis = [(last[i] - first[i]) / length for i in range(3)]
    first = tuple(first[i] - axis[i] * behind for i in range(3))
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
    base = points[0]
    failures = []

    def fail(message):
        failures.append(message)
        print("  FAIL %s" % message)

    print("  the module carries the chain %.2f units into the palm"
          % module.SEAT_REACH)

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
    weights[102] = {"frame l thumb tip": 0.6, "frame l index low": 0.4}
    position[102] = points[0]
    side_of = {index: "l" for index in range(len(points))}
    side_of[100] = "l"
    side_of[101] = "r"
    side_of[102] = "l"

    returned = module.seat_thumb(weights, position, chain, HAND,
                                 side="l", side_of=side_of)
    print("  seated %d of %d plate vertices" % (len(returned), len(points)))
    if not set(range(len(points))) <= set(returned):
        fail("the plate was not seated whole: %r" % (sorted(returned),))

    for index in range(len(points)):
        total = sum(weights[index].values())
        if abs(total - 1.0) > 1e-6:
            fail("plate vertex %d sums to %r, so weight was invented or lost"
                 % (index, total))
        carried = [name for name, weight in weights[index].items()
                   if weight > 1e-6]
        if len(carried) > 2:
            fail("plate vertex %d rides %d bones and a .jms keeps two: %r"
                 % (index, len(carried), weights[index]))
        if not carried:
            fail("plate vertex %d ended with no bones at all" % index)

    # Nothing off the thumb may move.
    if weights[100] != untouched:
        fail("a vertex off the thumb was changed: %r" % (weights[100],))
    if weights[101] != {"frame r thumb mid": 1.0}:
        fail("a vertex on the other hand was changed: %r" % (weights[101],))

    hand = [weights[index].get(HAND, 0.0) for index in range(len(points))]
    print("  hand share base %.2f, middle %.2f, tip %.2f"
          % (hand[0], hand[len(hand) // 2], hand[-1]))
    if hand[0] < 0.3:
        fail("the guard's base rides only %.2f of the palm, so it is not seated"
             % hand[0])
    if hand[-1] > 0.05:
        fail("the guard's tip still rides %.2f of the palm, so it will not "
             "follow the thumb" % hand[-1])
    if max(hand) > hand[0] + 1e-6:
        fail("the palm's share peaks past the guard's base: %r"
             % ([round(value, 2) for value in hand],))

    # Neighbours must share a bone: a pair that shares none is a tear waiting for
    # the thumb to bend.
    for index in range(len(points) - 1):
        here = {name for name, weight in weights[index].items() if weight > 1e-6}
        next_one = {name for name, weight in weights[index + 1].items()
                    if weight > 1e-6}
        if not here & next_one:
            fail("plate vertices %d and %d share no bone: %r vs %r"
                 % (index, index + 1, sorted(here), sorted(next_one)))

    # A guard vertex that already held two bones is re-seated, not left alone.
    if HAND not in weights[102]:
        fail("a guard vertex holding two bones already kept its old weights: %r"
             % (weights[102],))
    print("  guard vertex holding two bones already -> %r" % (weights[102],))

    # Whole shells only: a vertex outside the set is not re-seated, so a palm
    # vertex that merely brushes the thumb cannot be pulled away from the
    # vertices beside it in its own shell. The omitted vertex has to be one the
    # seating would otherwise change, or the check proves nothing.
    would_move = [index for index in range(len(points))
                  if weights[index].get(HAND, 0.0) > 0.0]
    if len(would_move) < 2:
        fail("the seating only moves %d plate vertex/vertices, so the shell "
             "gate cannot be checked" % len(would_move))
    else:
        omitted = would_move[1]
        allowed = set(would_move) - {omitted}
        subset = {}
        subset_at = {}
        for index, point in enumerate(points):
            subset[index] = {name: weight
                             for weight, name in module.chain_along(point, chain)}
            subset_at[index] = point
        module.seat_thumb(subset, subset_at, chain, HAND, only=allowed)
        if subset[omitted].get(HAND, 0.0) > 0.0:
            fail("a vertex outside the shells asked for was re-seated: %r"
                 % (subset[omitted],))
        if subset[would_move[0]].get(HAND, 0.0) <= 0.0:
            fail("a vertex inside the shells asked for was not seated")
        print("  shell gate: %d of %d plate vertices would be seated, %d kept "
              "out" % (len(would_move), len(points), 1))

    # Posed: turning the thumb's base bone 30 degrees has to move the guard's base
    # well under the rigid move, which is what keeps the plate on the palm.
    head = THUMB[0][1]
    bone = [THUMB[0][2][i] - head[i] for i in range(3)]
    size = math.sqrt(sum(value * value for value in bone))
    bone = [value / size for value in bone]
    offset = [base[i] - head[i] for i in range(3)]
    turn_axis = [bone[1] * offset[2] - bone[2] * offset[1],
                 bone[2] * offset[0] - bone[0] * offset[2],
                 bone[0] * offset[1] - bone[1] * offset[0]]
    size = math.sqrt(sum(value * value for value in turn_axis))
    turn_axis = [value / size for value in turn_axis]
    moved = turned(base, head, turn_axis, 30.0)
    rigid = math.dist(moved, base)
    kept = rigid * (1.0 - hand[0])
    print("  posed 30 degrees: the base moves %.3f of the %.3f it would with "
          "all of its weight on the thumb" % (kept, rigid))
    if rigid <= 0.1:
        fail("the test's own pose barely moves the base (%.3f), so it proves "
             "nothing" % rigid)
    if kept >= rigid * 0.75:
        fail("the base still moves %.0f%% of the way, so the plate is not "
             "seated" % (100.0 * kept / rigid))

    print()
    if failures:
        print("FAILED: %d check(s)" % len(failures))
        return 1
    print("PASSED: the guard is seated in the palm, two weights a vertex, and "
          "no neighbouring pair is left without a bone to share")
    return 0


if __name__ == "__main__":
    sys.exit(main())
