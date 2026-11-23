#!/usr/bin/env python3
"""Prove a mask painted in one UV set is carried into the one the shader uses.

Halo's shader samples the multipurpose map with the base map's UV set. The Marine
armour's mask lives in UV set 2 and its base map in set 0, and the two share no
vertex - every one of the 5,284 vertices has different coordinates in each - so a
mask read as though it were in set 0 tints whatever happens to sit at the same
place in the other layout, not the parts the artist tinted.

Six things are checked:

  * a mask that runs the other way across the surface lands on the base map's
    side after baking, not where the raw texture put it
  * a triangle one tile over paints the same atlas region as one at zero -
    texture coordinates are tiles, so the canvas wraps
  * which set a mask belongs to is decided by where its pixels cover the body,
    so a mask painted in the base map's layout is read where it is and one
    painted elsewhere is carried across
  * no UV set named means nothing to carry, so the mask is read as before
  * a texture with no pixels is refused instead of masking everything

The seam column is not asserted on: a canvas holds one tile with its first and
last column a texel apart, so which of two neighbouring triangles writes the last
column is arbitrary, and the item's own UV space does not put geometry there.

    python3 tools/test_mask_bake.py
    MESH_MODULES=/tmp/unpacked python3 tools/test_mask_bake.py   # any build
"""

import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODULES = os.environ.get("MESH_MODULES") or os.path.join(
    os.path.dirname(HERE), "src")

sys.path.insert(0, MODULES)


def load(name, filename):
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(MODULES, filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


mesh = load("avatar_mesh", "avatar_mesh.py")
items = load("extract_items", "extract_items.py")

failures = []


def check(label, got, want):
    print("  %-46s %r" % (label, got))
    if got != want:
        failures.append("%s: %r, expected %r" % (label, got, want))


def quad(uv0, mask_uv):
    """One square split into two triangles, with the two UV sets given."""
    uvs = [[uv0[i], uv0[i], mask_uv[i]] for i in range(4)]
    return {"uvs": uvs, "indices": [0, 1, 2, 0, 2, 3]}


corners = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]

# Two-texel masks: one white on its right, one white on its left.
right = {"width": 2, "height": 1, "uv_set": 2,
         "rgba": bytes([0, 0, 0, 0, 0, 0, 0, 255])}
left = {"width": 2, "height": 1, "uv_set": 2,
        "rgba": bytes([0, 0, 0, 255, 0, 0, 0, 0])}

# 1. The mask's layout runs the other way across the same surface: u climbs where
#    the base map's falls. Read raw, the white lands on the right of the atlas;
#    baked, it has to land on the left, because that is the same cloth.
backwards = [(0.9 - 0.6 * u, v) for u, v in corners]
batches = [quad(corners, backwards)]
baked = mesh.bake_mask(batches, right, 3, 8, 2, 0)
raw = items.mask_from_texture(right, 8, 3)
check("baked: white on the left", baked[1:5], bytes([255] * 4))
check("baked: black on the right", baked[5:7], bytes([0, 0]))
check("raw would have been right", raw[4:7], bytes([255] * 3))
check("raw would have been left", raw[1:4], bytes([0] * 3))

# 2. A quad one tile over still paints the atlas at zero, because the coordinates
#    are tiles and the atlas repeats. Without wrapping nothing would be painted.
tiled = [(1.0, 0.0), (1.4, 0.0), (1.4, 1.0), (1.0, 1.0)]
near = [(0.0, 0.0), (0.4, 0.0), (0.4, 1.0), (0.0, 1.0)]
over = mesh.bake_mask([quad(tiled, tiled)], left, 3, 8, 2, 0)
plain = mesh.bake_mask([quad(near, near)], left, 3, 8, 2, 0)
check("one tile over == no offset", over, plain)
check("and it is not empty", any(over), True)

# 3. Which set a mask belongs to is decided by which set its pixels cover, not
#    by the field its material carries. A mask that paints the base map's own
#    layout is read where it is; one that paints the other set is carried.
band = {"width": 8, "height": 1, "uv_set": 2,
        "rgba": bytes([0, 0, 0, 0] * 2 + [0, 0, 0, 255] * 2 + [0, 0, 0, 0] * 4)}
middle = {"width": 8, "height": 1, "uv_set": 2,
          "rgba": bytes([0, 0, 0, 0] * 3 + [0, 0, 0, 255] * 5)}
here = items.mask_reach(batches, band, 3, 0)
there = items.mask_reach(batches, band, 3, 2)
print("  %-46s here %.2f, in its own set %.2f" % ("mask painted for set 0", here, there))
if not here > there:
    failures.append("a mask painted for set 0 does not cover set 0 better")
check("painted for set 0: read where it is",
      items.mask_bytes(mesh, batches, band, 3, 8, 0),
      items.mask_from_texture(band, 8, 3))
here = items.mask_reach(batches, middle, 3, 0)
there = items.mask_reach(batches, middle, 3, 2)
print("  %-46s here %.2f, in its own set %.2f" % ("mask painted for set 2", here, there))
check("painted for set 2: carried across",
      items.mask_bytes(mesh, batches, middle, 3, 8, 0),
      mesh.bake_mask(batches, middle, 3, 8, 2, 0))

# Same set named twice: nothing to carry, so the mask is the texture's channel.
same = dict(right, uv_set=0)
check("same set: resampled raw",
      items.mask_bytes(mesh, batches, same, 3, 8, 0), raw)

# 4. No UV set named: nothing to carry, so the mask is read as before.
unknown = {"width": 2, "height": 1, "rgba": right["rgba"]}
check("no uv set given", items.mask_bytes(mesh, [], unknown, 3, 8, 0), raw)

# 5. A texture with no pixels cannot be baked, and says so rather than masking
#    the whole item, which is what a silent zero-size read would do.
empty = {"width": 0, "height": 0, "rgba": b"", "uv_set": 2}
check("no pixels", mesh.bake_mask(batches, empty, 3, 8, 2, 0), None)

print("")
if failures:
    for failure in failures:
        print("FAIL: %s" % failure)
    raise SystemExit(1)
print("PASS: a mask in another UV set is carried into the base map's")
