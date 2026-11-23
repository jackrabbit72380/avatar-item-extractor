#!/usr/bin/env python3
"""Prove a team colour comes from the item's tint mask and never its decal.

The avatar shader colours an item as
lerp(base, red*C1 + green*C2 + blue*C3, alpha): the material's parameter id 2 is
the tint mask, its red, green and blue pick which of the player's three custom
colours a texel takes, and its alpha is how much of it shows. Parameter id 3 is a
decal - artwork blended over the base map by its own alpha, a tee's logo.

The Marine armour's tint slot is a blank 32x32 (one texel at 1, the rest 0) while
the decal beside it carries an alpha blend over two thirds of its canvas. Reading
that decal alpha as a colour-change mask tinted most of the suit on no evidence at
all, which is the failure this test exists for.

Five things are checked:

  * a blank tint slot is not a mask, and an item with one is untinted
  * only the tint mask is ever consulted - a decal with a strong alpha is not
  * the amount is alpha when alpha varies, colour weights when it is flat
  * the mask is resampled to the size written, not flattened
  * a texture holding one value everywhere is recognised as an unused slot

    python3 tools/test_mask_source.py
    MESH_MODULES=/tmp/unpacked python3 tools/test_mask_source.py   # any build
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


items = load("extract_items", "extract_items.py")

failures = []


def check(label, got, want):
    print("  %-44s %r" % (label, got))
    if got != want:
        failures.append("%s: %r, expected %r" % (label, got, want))


def texture(width, height, pixels):
    """A decoded slot in the shape the extractor passes around."""
    rgba = bytearray()
    for r, g, b, a in pixels:
        rgba += bytes((r, g, b, a))
    return {"width": width, "height": height, "rgba": bytes(rgba)}


# The Marine armour's two shapes, side by side: a blank 32x32 tint slot, and a
# decal whose alpha covers most of its canvas.
blank_tint = texture(4, 4, [(0, 0, 0, 0)] * 15 + [(0, 0, 0, 1)])
decal = texture(4, 2, [(90, 90, 90, 255), (90, 90, 90, 255),
                       (90, 90, 90, 0), (90, 90, 90, 0)] * 2)
alpha_tint = texture(2, 1, [(255, 0, 0, 255), (0, 0, 0, 0)])
weight_tint = texture(2, 1, [(0, 255, 0, 255), (0, 0, 0, 255)])

check("a blank tint slot is no mask", items.mask_source(blank_tint), None)
check("no tint slot at all", items.mask_source(None), None)
check("a tint with content is a mask",
      items.mask_source(alpha_tint) is alpha_tint, True)

# The decal is the trap: strong alpha, and never a tint source. item_tint reads
# the tint slot alone, so an item whose only texture with an alpha is its decal
# comes out untinted.
check("a decal is never the tint",
      items.item_tint({"decal_texture": decal}), None)
check("a decal does not outrank a tint",
      items.item_tint({"tint_texture": alpha_tint,
                       "decal_texture": decal}) is alpha_tint, True)
check("a blank tint beside a decal is untinted",
      items.item_tint({"tint_texture": blank_tint,
                       "decal_texture": decal}), None)

# Which channel carries the amount.
check("varying alpha carries it", items.tint_channel(alpha_tint), 3)
check("a flat alpha means colour weights", items.tint_channel(weight_tint), 0)
check("weights tint where they are set",
      items.tint_amount(weight_tint, 2), bytes([255, 0, 255, 0]))

# A mask that is half lit must not arrive as a blanket fill: a flat channel
# passes a size check and still tints the whole item.
check("amount resampled, not filled",
      items.mask_from_texture(alpha_tint, 2, 3), bytes([255, 0, 255, 0]))
if items.mask_from_texture(alpha_tint, 2, 3) == b"\xff" * 4:
    failures.append("a half-lit mask came back as a blanket fill")

# An unused slot is one value everywhere, even when one texel is at 1.
check("blank slot recognised", items.texture_flat(blank_tint), True)
check("painted slot recognised", items.texture_flat(decal), False)

print("")
if failures:
    for failure in failures:
        print("FAIL: %s" % failure)
    raise SystemExit(1)
print("PASS: the team colour comes from the tint mask, and a decal is not one")
