#!/usr/bin/env python3
"""Check the arm angle fit against a target the test picks, not one it reports.

The fit used to be judged by its own measurement: it was asked for an angle and
then asked how close it had got, which is no test at all - a fit that measures
itself reports whatever it optimised and says nothing about the arm. So the
target here is a direction this file chooses (+X), and the answer is measured
with a different estimator entirely: a coarse scan of the sphere refined to
tenths of a degree, finding the direction the fitted cloud is widest in. No
eigen decomposition, nothing the fit computed, is reused.

  * a sleeve leaning 9.5 degrees is turned onto +X to within 0.2 degrees;
  * a sleeve already on +X is left where it is;
  * the size is never touched, and no single pass turns more than the cap;
  * too few points, or no target, leave the side alone instead of guessing.

    python3 tools/test_arms_fit.py

Exits 0 only when every check passes.
"""
try:
    import bmesh  # noqa: F401 - Blender's own module, present only inside Blender
except ImportError:
    print("needs Blender's own python (bmesh): skipping here")
    raise SystemExit(2)


import importlib.util
import math
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
    spec = importlib.util.spec_from_file_location("rig_items_fit_test", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sleeve(axis, length=24.0, radius=1.1, rings=40, around=8):
    """A cylinder of points along `axis`, like a sleeve on its arm."""
    length_of = math.sqrt(sum(value * value for value in axis))
    axis = [value / length_of for value in axis]
    # Any two directions across the axis will do.
    seed = [1.0, 0.0, 0.0] if abs(axis[0]) < 0.9 else [0.0, 1.0, 0.0]
    across = [seed[1] * axis[2] - seed[2] * axis[1],
              seed[2] * axis[0] - seed[0] * axis[2],
              seed[0] * axis[1] - seed[1] * axis[0]]
    size = math.sqrt(sum(value * value for value in across))
    across = [value / size for value in across]
    other = [axis[1] * across[2] - axis[2] * across[1],
             axis[2] * across[0] - axis[0] * across[2],
             axis[0] * across[1] - axis[1] * across[0]]
    points = []
    for ring in range(rings):
        along = (ring / (rings - 1.0) - 0.5) * length
        for step in range(around):
            angle = 2.0 * math.pi * step / around
            offset = (radius * math.cos(angle), radius * math.sin(angle))
            points.append([axis[i] * along + across[i] * offset[0]
                           + other[i] * offset[1] for i in range(3)])
    return points


def widest(points):
    """The direction a cloud is widest in, by scanning the sphere - not by eigen."""
    centre = [sum(point[i] for point in points) / len(points) for i in range(3)]
    deltas = [[point[i] - centre[i] for i in range(3)] for point in points]

    def spread(theta, phi):
        direction = (math.sin(theta) * math.cos(phi),
                     math.sin(theta) * math.sin(phi),
                     math.cos(theta))
        return sum((delta[0] * direction[0] + delta[1] * direction[1]
                    + delta[2] * direction[2]) ** 2 for delta in deltas)

    best = None
    for step_theta in range(13):
        theta = math.pi * step_theta / 12.0
        for step_phi in range(24):
            phi = 2.0 * math.pi * step_phi / 24.0
            value = spread(theta, phi)
            if best is None or value > best[0]:
                best = (value, theta, phi)
    _value, theta, phi = best
    step = 0.15
    while step > 1e-7:
        moved = False
        for dtheta, dphi in ((step, 0.0), (-step, 0.0), (0.0, step), (0.0, -step)):
            value = spread(theta + dtheta, phi + dphi)
            if value > best[0]:
                best = (value, theta + dtheta, phi + dphi)
                moved = True
                break
        _value, theta, phi = best
        if not moved:
            step *= 0.5
    return [math.sin(theta) * math.cos(phi),
            math.sin(theta) * math.sin(phi),
            math.cos(theta)]


def angle_between(first, second):
    size_a = math.sqrt(sum(value * value for value in first))
    size_b = math.sqrt(sum(value * value for value in second))
    cosine = sum(a * b for a, b in zip(first, second)) / (size_a * size_b)
    return math.degrees(math.acos(max(-1.0, min(1.0, abs(cosine)))))


def turn_angle(turn):
    """How far a 3x3 turn turns things, in degrees."""
    cosine = max(-1.0, min(1.0, (turn[0] + turn[4] + turn[8] - 1.0) / 2.0))
    return math.degrees(math.acos(cosine))


IDENTITY = (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)


def main():
    module = load()
    failures = []

    def check(condition, message):
        if not condition:
            failures.append(message)

    def place(turn, scale):
        return {"turn": turn, "scale": scale, "twist": 0.0, "glove": "none"}

    def rebuild(turn, scale):
        return place(turn, scale)

    want = [1.0, 0.0, 0.0]

    # 1. A sleeve leaning 9.5 degrees is turned onto the target the test chose.
    leaning = [1.0, 0.16, -0.05]
    points = sleeve(leaning)
    before = angle_between(widest(points), want)
    check(before > 8.0,
          "the test sleeve only leans %.2f deg, too little to prove anything" % before)

    fitted = module.carry_onto(place(IDENTITY, 1.0), points, want, rebuild)
    check(fitted is not None, "the fit refused a sleeve it should have turned")
    if fitted is not None:
        moved = [module.turn_point(fitted["turn"], point) for point in points]
        after = angle_between(widest(moved), want)
        check(after < 0.2,
              "the fitted sleeve still leans %.2f deg off the target the test "
              "chose (was %.2f)" % (after, before))
        check(abs(fitted["scale"] - 1.0) < 1e-9,
              "the fit changed the size (%.6f) - the glove would leave Halo's hand"
              % fitted["scale"])
        check(turn_angle(fitted["turn"]) <= 36.0 + 1e-6,
              "the fit turned the sleeve %.1f deg, past its own cap"
              % turn_angle(fitted["turn"]))
        # Measured the same way, the arm is straighter than it was: the point of
        # the fit is the angle a player sees, and this is that angle, not the
        # number the fit worked to.
        check(after < before, "the fitted sleeve is not straighter than before")

    # 2. A sleeve already on the target is left alone.
    steady = sleeve([1.0, 0.0, 0.0])
    kept = module.carry_onto(place(IDENTITY, 1.0), steady, want, rebuild)
    check(kept is not None, "the fit refused an already-aligned sleeve")
    if kept is not None:
        check(turn_angle(kept["turn"]) < 0.05,
              "an aligned sleeve was turned %.2f deg for nothing"
              % turn_angle(kept["turn"]))

    # 3. A single pass is capped, so a far-off sleeve settles instead of swinging.
    far = sleeve([0.0, 1.0, 0.0])
    turned = module.carry_onto(place(IDENTITY, 1.0), far, want, rebuild, rounds=1)
    check(turned is not None, "the fit refused a sleeve a quarter turn away")
    if turned is not None:
        check(turn_angle(turned["turn"]) <= 20.0 + 1e-6,
              "one pass turned %.1f deg, past the 20 deg cap"
              % turn_angle(turned["turn"]))

    # 4. The cap is a step size, not a limit on what can be corrected. This is
    #    the bug a real item found: three passes of twelve left a sleeve 49
    #    degrees out stopped at 13, and nothing in the report said so.
    out_far = [1.0, 1.2, 0.0]           # about 50 degrees off the target
    steep = sleeve(out_far)
    steep_before = angle_between(widest(steep), want)
    check(steep_before > 45.0,
          "the steep test sleeve is only %.1f deg out" % steep_before)
    brought = module.carry_onto(place(IDENTITY, 1.0), steep, want, rebuild)
    check(brought is not None, "the fit refused a sleeve 50 deg out")
    if brought is not None:
        moved = [module.turn_point(brought["turn"], point) for point in steep]
        steep_after = angle_between(widest(moved), want)
        check(steep_after < 0.5,
              "a sleeve %.1f deg out was only brought to %.1f deg - the fit "
              "cannot reach past its own cap" % (steep_before, steep_after))

    # 4. Nothing to fit means nothing is moved.
    check(module.carry_onto(place(IDENTITY, 1.0), sleeve(want)[:5], want,
                            rebuild) is None,
          "a 5-point cloud was fitted instead of left alone")
    check(module.carry_onto(place(IDENTITY, 1.0), sleeve(want), None,
                            rebuild) is None,
          "a side with no target was turned anyway")
    check(module.carry_onto(None, sleeve(want), want, rebuild) is None,
          "a side that was never placed was turned anyway")

    # 5. The one-turn helper is exact, since the whole fit rests on it.
    turn = module.alignment([1.0, 0.2, 0.0], want)
    check(turn is not None, "alignment() refused a plain direction")
    if turn is not None:
        held = module.turn_point(turn, [1.0, 0.2, 0.0])
        check(angle_between(held, want) < 1e-6,
              "alignment() landed %.6f deg off" % angle_between(held, want))

    if failures:
        print("FAIL: %d check(s)" % len(failures))
        for message in failures:
            print("  - %s" % message)
        return 1
    print("PASSED: arm angle fit reaches a target chosen by the test (%.2f deg "
          "-> under 0.2), keeps the size, respects its cap, and leaves what it "
          "cannot fit alone" % before)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
