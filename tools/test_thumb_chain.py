#!/usr/bin/env python3
"""Check that a glove's thumb is weighted from its base, not from its tip.

The thumb is the one finger whose glove is a plate standing off the bones, so
"which bone is nearest" is not the same question as "where along the finger is
this vertex". Measured on the Marine glove, nearest-bone weighting put 7% of the
thumb on `thumb low`, 39% on `thumb mid` and 54% on `thumb tip` - and because a
.jms carries two weights per vertex, the base bone was dropped from every vertex
it had and drove nothing at all. A thumb weighted that way bends from its tip
instead of folding from its base, which is the kink a player sees.

So this test does not ask the module whether it is happy. It builds a plate the
way the Marine's guard is built - running along the thumb's chain but standing
1.5 units off it - and checks the weights it comes back with against the shape
it was given:

  * the plate's base is `thumb low`'s and its tip is `thumb tip`'s, by at least
    0.8 each, and the point nearest `thumb mid` is `thumb mid`'s;
  * the base bone's share only falls as the plate runs out to its tip, and the
    tip's only rises;
  * no vertex is spread over more than two bones, so the .jms keeps all of it;
  * over the whole plate the base bone holds at least a quarter of the weight,
    where nearest-bone weighting held 7%;
  * a plate standing off the chain is still found as the thumb by finger_split,
    and gets the same weights.

    python3 tools/test_thumb_chain.py

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
WRIST = ((21.14, 9.4, 0.0), (24.52, 9.4, 0.0))
MIDDLE = (("frame l middle low", (24.78, 10.12, 0.33), (26.71, 10.12, 0.33)),
          ("frame l middle mid", (26.71, 10.12, 0.33), (27.92, 10.07, 0.33)),
          ("frame l middle tip", (27.92, 10.07, 0.33), (29.12, 9.89, 0.33)))


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
    spec = importlib.util.spec_from_file_location("rig_items_thumb_test", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def entries():
    """The chain the module reads, in the order it sorts them: low, mid, tip."""
    return [(name, head, tail, name.split(" ", 2)[2].replace(" ", ""))
            for name, head, tail in THUMB]


def plate(steps=9, offset=1.5):
    """A guard: along the thumb's chain, standing `offset` units off it.

    This is the shape that broke nearest-bone weighting - every point of it is
    about as far from all three bones, so the nearest one is decided by which
    end of the chain the point leans towards.
    """
    first, last = THUMB[0][1], THUMB[-1][2]
    length = math.dist(first, last)
    axis = [(last[i] - first[i]) / length for i in range(3)]
    aside = [-axis[2], 0.0, axis[0]]
    size = math.sqrt(sum(value * value for value in aside))
    aside = [value / size for value in aside]
    return [tuple(first[i] + (last[i] - first[i]) * (step / (steps - 1.0))
                  + aside[i] * offset for i in range(3))
            for step in range(steps)]


def rig():
    bones = {"frame l wriste": types.SimpleNamespace(
        head_local=Vec(*WRIST[0]), tail_local=Vec(*WRIST[1]))}
    for name, head, tail in list(THUMB) + list(MIDDLE):
        bones[name] = types.SimpleNamespace(head_local=Vec(*head),
                                            tail_local=Vec(*tail))

    class Shift:
        def __matmul__(self, other):
            return other

    return types.SimpleNamespace(matrix_world=Shift(),
                                 data=types.SimpleNamespace(bones=bones))


def main():
    module = load()
    chain = entries()
    points = plate()
    failures = []

    def fail(message):
        failures.append(message)
        print("  FAIL %s" % message)

    def weight_on(per, bone):
        for weight, name in per:
            if name == bone:
                return weight
        return 0.0

    shares = [module.chain_along(point, chain) for point in points]
    for index, per in enumerate(shares):
        total = sum(weight for weight, _name in per)
        print("  plate %d -> %s (%.3f)"
              % (index, ", ".join("%s %.2f" % (n.split(" ", 2)[2], w)
                                  for w, n in per), total))
        if not per or abs(total - 1.0) > 1e-6:
            fail("plate %d came back with weights summing to %r"
                 % (index, total))
        if len([1 for weight, _name in per if weight > 1e-6]) > 2:
            fail("plate %d rides %d bones, and a .jms keeps two"
                 % (index, len(per)))

    base, tip = points[0], points[-1]
    if weight_on(module.chain_along(base, chain), THUMB[0][0]) < 0.8:
        fail("the plate's base is not on thumb low: %r"
             % (module.chain_along(base, chain),))
    if weight_on(module.chain_along(tip, chain), THUMB[2][0]) < 0.8:
        fail("the plate's tip is not on thumb tip: %r"
             % (module.chain_along(tip, chain),))

    # The middle bone is the shortest, so the plate's own midpoint is not its
    # midpoint: ask the point that lies over the middle bone's own centre.
    centre = [(THUMB[1][1][k] + THUMB[1][2][k]) / 2.0 for k in range(3)]
    over_mid = min(range(len(points)),
                   key=lambda index: math.dist(points[index], centre))
    print("  the plate's point over thumb mid is %d" % over_mid)
    if weight_on(shares[over_mid], THUMB[1][0]) < 0.8:
        fail("the point over thumb mid is not thumb mid's: %r"
             % (shares[over_mid],))

    # Base to tip, the base bone can only give way and the tip bone only gain.
    base_share = [weight_on(per, THUMB[0][0]) for per in shares]
    tip_share = [weight_on(per, THUMB[2][0]) for per in shares]
    if any(first < second - 1e-6
           for first, second in zip(base_share, base_share[1:])):
        fail("thumb low's share rises again towards the tip: %r"
             % ([round(value, 2) for value in base_share],))
    if any(first > second + 1e-6
           for first, second in zip(tip_share, tip_share[1:])):
        fail("thumb tip's share falls towards the tip: %r"
             % ([round(value, 2) for value in tip_share],))

    # The regression itself: nearest-bone weighting gave the base bone 7% of a
    # plate like this. Measured over the plate, its share has to be real.
    held = sum(base_share) / len(base_share)
    print("  thumb low holds %.0f%% of the plate (nearest-bone weighting: 7%%)"
          % (held * 100.0))
    if held < 0.25:
        fail("thumb low holds only %.0f%% of a plate along its chain"
             % (held * 100.0))

    # And the plate has to be found as the thumb in the first place, even
    # standing off the chain: a vertex the hand bone is nearer than the chain
    # gets no grip at all, so this uses one the chain is nearer than the wrist.
    split = module.finger_split(Vec(*points[over_mid]), rig(), "l")
    print("  finger_split on that point -> %r"
          % ((None if split is None else (round(split[0], 2),
                                          sorted(split[1]))),))
    if split is None or split[0] <= 0.0:
        fail("a plate standing off the thumb chain was not found as a finger")
    elif any("thumb" not in name for name in split[1]):
        fail("the plate's point rides another finger: %r" % (split[1],))
    elif weight_on(module.chain_along(points[over_mid], chain),
                   THUMB[1][0]) < 0.8:
        fail("finger_split gave the plate's point a different bone")

    print("")
    if failures:
        print("FAILED: %d check(s)" % len(failures))
        return 1
    print("PASSED: the thumb is weighted from its base along its own chain")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
