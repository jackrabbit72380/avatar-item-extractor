#!/usr/bin/env python3
"""Prove a kept-shape model is put onto Halo's scale without changing shape.

Halo cannot rescale a biped: a model's nodes are the skeleton its animation graph
drives by name, and the weapon in the hand, the pickup and the collision capsule
are all placed from them. So --keep-shape brings the model onto Halo's scale -
the avatar to the biped's own height, the item by biped / 1.40 - and it does it
with ONE uniform factor per part. A factor applied to one axis, or one part
measured from the other's bounds, is exactly how a mesh loses its shape or an
avatar comes out a midget, so both are checked here.

The test builds an avatar and an item the size of the ones measured in Blender (a
1.850 m avatar body with a 0.248 m head, a 1.509 m item 0.417 x 1.424 across) and
checks:

  * the item's height is reported as the ITEM's, not the merged model's - the
    bug that printed "its 1.850 m" for a 1.509 m armour;
  * the avatar ends exactly on the biped's height;
  * the item ends at its own height x the biped / 1.40 fit;
  * every width:height and depth:height ratio is unchanged in both parts, to
    1e-12, so nothing is squashed;
  * every avatar vertex moved by exactly one factor and every item vertex by
    exactly the other, with no vertex left behind;
  * a model with no avatar, or an avatar with no item, is left untouched and
    reports None instead of guessing;
  * and a fit of 1.0 leaves everything where it was.

    python3 tools/test_keep_shape.py

Exits 0 only when every check passes.
"""

import importlib.util
import os
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))
MODULES = os.environ.get("RIG_MODULES") or os.path.join(
    os.path.dirname(HERE), "src")

FAILURES = []


def check(claim, message):
    if not claim:
        FAILURES.append(message)


class Vec:
    """Just enough of mathutils.Vector for the scaling function."""

    def __init__(self, x=0.0, y=0.0, z=0.0):
        self.x, self.y, self.z = float(x), float(y), float(z)

    def __getitem__(self, index):
        return (self.x, self.y, self.z)[index]


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
    spec = importlib.util.spec_from_file_location("rig_items_keep_shape", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def box(vertices, indices, low, high):
    """Eight corners of an axis-aligned box, gathering its indices."""
    xs = (low[0], high[0])
    ys = (low[1], high[1])
    zs = (low[2], high[2])
    for x in xs:
        for y in ys:
            for z in zs:
                indices.append(len(vertices))
                vertices.append(types.SimpleNamespace(co=Vec(x, y, z)))


def model(avatar_box, item_box):
    """A mesh of two boxes: the ported avatar and the item it was ported onto."""
    vertices = []
    avatar = []
    box(vertices, avatar, *avatar_box)
    item = []
    box(vertices, item, *item_box)
    mesh = types.SimpleNamespace(
        data=types.SimpleNamespace(vertices=vertices,
                                   update=lambda: None))
    return mesh, set(avatar), set(item)


def sizes(vertices, indices):
    """Width, height and depth of a part, read off its vertices' co."""
    axes = [[vertices[index].co[axis] for index in indices] for axis in range(3)]
    return tuple(max(values) - min(values) for values in axes)


def main():
    module = load()

    # Measured in Blender: the avatar body with its head, and this armour.
    AVATAR = ((0.0, 0.0, 0.0), (0.248, 1.850, 0.815))
    ITEM = ((0.0, 0.0, 0.0), (0.569, 1.509, 1.941))
    FIT = 1.364
    BIPED = FIT * module.AUTHORED_BODY_HEIGHT

    mesh, avatar, item = model(AVATAR, ITEM)
    placed = module.keep_shape_scale(mesh, avatar, FIT)
    check(placed is not None, "keep_shape_scale reported nothing for a model "
                              "with both an avatar and an item")

    if placed:
        before = {index: tuple(mesh.data.vertices[index].co[axis]
                              for axis in range(3))
                  for index in range(len(mesh.data.vertices))}
        # Undo the scaling to read the measurements back out of the mesh.
        for index, vertex in enumerate(mesh.data.vertices):
            grow = placed["avatar_scale"] if index in avatar else placed["item_scale"]
            vertex.co = Vec(before[index][0] / grow, before[index][1] / grow,
                            before[index][2] / grow)

        check(abs(placed["item_height"] - 1.509) < 1e-9,
              "the item's height was reported as %.3f m, and the item is 1.509 m "
              "tall - this is the merged model's height, not the item's"
              % placed["item_height"])
        check(abs(placed["avatar_height"] - 1.850) < 1e-9,
              "the avatar's height was reported as %.3f m, not 1.850 m"
              % placed["avatar_height"])
        check(abs(placed["biped_height"] - BIPED) < 1e-9,
              "the biped's height came out %.3f m, not fit x 1.40 = %.3f m"
              % (placed["biped_height"], BIPED))
        check(abs(placed["avatar_after"] - BIPED) < 1e-9,
              "the avatar ends %.4f m tall, and the biped is %.4f m"
              % (placed["avatar_after"], BIPED))
        check(abs(placed["item_after"] - 1.509 * FIT) < 1e-9,
              "the item ends %.4f m tall, not 1.509 x %.3f = %.4f m"
              % (placed["item_after"], FIT, 1.509 * FIT))
        check(abs(placed["avatar_scale"] - BIPED / 1.850) < 1e-12,
              "the avatar's factor is %.6f, not the biped / 1.850 = %.6f"
              % (placed["avatar_scale"], BIPED / 1.850))
        check(abs(placed["item_scale"] - FIT) < 1e-12,
              "the item's factor is %.6f, not the fit %.6f"
              % (placed["item_scale"], FIT))

    # Rebuild and scale for real, then compare shapes.
    mesh, avatar, item = model(AVATAR, ITEM)
    avatar_sizes = sizes(mesh.data.vertices, avatar)
    item_sizes = sizes(mesh.data.vertices, item)
    module.keep_shape_scale(mesh, avatar, FIT)
    avatar_now = sizes(mesh.data.vertices, avatar)
    item_now = sizes(mesh.data.vertices, item)

    for name, was, now in (("avatar", avatar_sizes, avatar_now),
                           ("item", item_sizes, item_now)):
        for axis, other in ((0, 1), (2, 1)):
            check(abs(now[axis] / now[1] - was[axis] / was[1]) < 1e-12,
                  "%s %s:height changed from %.12f to %.12f - it was squashed"
                  % (name, "width" if axis == 0 else "depth",
                     was[axis] / was[1], now[axis] / now[1]))

    # One factor a part: every vertex moved by its own part's factor and no
    # other.
    mesh, avatar, item = model(AVATAR, ITEM)
    before = [tuple(vertex.co[axis] for axis in range(3))
              for vertex in mesh.data.vertices]
    placed = module.keep_shape_scale(mesh, avatar, FIT)
    for index, vertex in enumerate(mesh.data.vertices):
        grow = placed["avatar_scale"] if index in avatar else placed["item_scale"]
        moved = [abs(vertex.co[axis] - before[index][axis] * grow)
                 for axis in range(3)]
        check(max(moved) < 1e-12,
              "vertex %d did not move by its part's factor %.6f (off by %.2e)"
              % (index, grow, max(moved)))

    # Nothing to measure: an item with no avatar, and an avatar with no item.
    mesh, avatar, _item = model(AVATAR, ITEM)
    before = [tuple(vertex.co[axis] for axis in range(3))
              for vertex in mesh.data.vertices]
    check(module.keep_shape_scale(mesh, set(), FIT) is None,
          "an item on its own reported measurements, and it has no avatar to "
          "measure")
    after = [tuple(vertex.co[axis] for axis in range(3))
             for vertex in mesh.data.vertices]
    check(all(abs(after[i][axis] - before[i][axis]) < 1e-12
              for i in range(len(before)) for axis in range(3)),
          "an item on its own was moved, and there was no avatar to scale it to")
    check(module.keep_shape_scale(mesh, set(range(len(mesh.data.vertices))), FIT)
          is None,
          "an avatar with no item reported measurements, and there is no item to "
          "scale")

    # A fit of 1.0 is the identity, which is what "already on Halo's scale" means.
    mesh, avatar, _item = model(((0.0, 0.0, 0.0), (0.2, 1.4, 0.2)),
                                ((0.0, 0.0, 0.0), (0.4, 1.0, 0.4)))
    before = [tuple(vertex.co[axis] for axis in range(3))
              for vertex in mesh.data.vertices]
    placed = module.keep_shape_scale(mesh, avatar, 1.0)
    check(placed is not None and abs(placed["avatar_scale"] - 1.0) < 1e-12,
          "a fitted model (fit 1.0) was still scaled, by %.6f"
          % (placed["avatar_scale"] if placed else float("nan")))
    after = [tuple(vertex.co[axis] for axis in range(3))
             for vertex in mesh.data.vertices]
    check(all(abs(after[i][axis] - before[i][axis]) < 1e-12
              for i in range(len(before)) for axis in range(3)),
          "a fitted model (fit 1.0) was moved")

    # The same model standing up along z instead of y: .obj arrives z-up and
    # .glb y-up, and reading height off a fixed axis measured 0.417 m of depth on
    # a real 360sona avatar and scaled it x4.578 into a 6.9 m giant.
    mesh, avatar, _item = model(((0.0, 0.0, 0.0), (0.248, 0.815, 1.850)),
                                ((0.0, 0.0, 0.0), (0.569, 1.941, 1.509)))
    placed = module.keep_shape_scale(mesh, avatar, FIT)
    check(placed is not None, "a z-up model reported nothing")
    if placed:
        check(placed["axis"] == 2,
              "a z-up model was measured up axis %r, not z"
              % (placed["axis"],))
        check(abs(placed["avatar_height"] - 1.850) < 1e-9,
              "a z-up avatar's height came out %.3f m, not 1.850 m"
              % placed["avatar_height"])
        check(abs(placed["item_height"] - 1.509) < 1e-9,
              "a z-up item's height came out %.3f m, not 1.509 m"
              % placed["item_height"])
        check(abs(placed["avatar_after"] - BIPED) < 1e-9,
              "a z-up avatar ends %.4f m, and the biped is %.4f m"
              % (placed["avatar_after"], BIPED))

    # An avatar that measures 0.417 m tall is not a body: on the real 360sona
    # export it was a sliver, and scaling it to the biped multiplied the model
    # x4.578 into a 6.9 m giant. Nothing may be scaled, and nothing may move.
    # The sliver's own tallest span is the 0.417 m that fooled the measurement.
    mesh, avatar, _item = model(((0.0, 0.0, 0.0), (0.301, 0.417, 0.204)),
                                ((0.0, 0.0, 0.0), (1.424, 1.509, 0.417)))
    before = [tuple(vertex.co[axis] for axis in range(3))
              for vertex in mesh.data.vertices]
    check(module.keep_shape_scale(mesh, avatar, FIT) is None,
          "an avatar 0.417 m tall was scaled to the biped instead of refused")
    after = [tuple(vertex.co[axis] for axis in range(3))
             for vertex in mesh.data.vertices]
    check(all(abs(after[i][axis] - before[i][axis]) < 1e-12
              for i in range(len(before)) for axis in range(3)),
          "a model whose avatar is a sliver was moved")

    if FAILURES:
        for line in FAILURES:
            print("FAIL: " + line)
        return 1
    print("PASS: kept-shape scaling puts the avatar on the biped and the item on "
          "its authored body, one uniform factor each, and reports each part's "
          "own height")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
