#!/usr/bin/env python3
"""Prove the colour-change mask comes from the slot that carries one.

An item states its mask in one of two places: a small tint map painted red, or a
full map whose alpha is the mask - the channel Halo CE reads. Taking the tint
slot whenever it exists is what went wrong for the Marine armour: its 32x32 tint
slot is blank (every value 0 or 1), so all four mask files came out black and the
armour took no team colour at all, while the 256x128 map beside it had the mask
in alpha the whole time.

Four things are checked:

  * a blank slot is passed over, and the slot with a mask is used
  * the tint mask still wins when it has one, so items painted red keep that mask
  * a table with no mask anywhere says so instead of inventing a blanket fill
  * the mask is the channel asked for, resampled - not a flat colour

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


# The Marine's two shapes, side by side. The tint slot is blank - 32x32, every
# channel 0 or 1 - and the map next to it is 256x128 with a real mask in alpha.
blank_tint = texture(4, 4, [(0, 0, 0, 1)] * 8 + [(1, 0, 0, 0)] * 8)
mask_map = texture(4, 2, [(90, 90, 90, 255), (90, 90, 90, 255),
                          (90, 90, 90, 0), (90, 90, 90, 0)] * 2)
red_tint = texture(2, 1, [(255, 0, 0, 255), (0, 0, 0, 255)])

check("blank slot carries no mask", items.mask_channel(blank_tint), None)
check("a map with alpha does", items.mask_channel(mask_map), 3)
check("a tint painted red does", items.mask_channel(red_tint), 0)

role, found, channel = items.mask_source([(2, blank_tint), (3, mask_map)])
check("blank tint falls through to the map", (role, found is mask_map, channel),
      (3, True, 3))

role, found, channel = items.mask_source([(2, red_tint), (3, mask_map)])
check("a real tint mask still wins", (role, found is red_tint, channel),
      (2, True, 0))

role, found, channel = items.mask_source([(2, blank_tint), (3, None)])
check("nothing to mask anywhere", (role, found, channel), (None, None, None))

role, found, channel = items.mask_source([(2, None), (3, None)])
check("empty roles", (role, found, channel), (None, None, None))

# The mask is the channel that was asked for, resampled to the size written.
check("alpha channel", items.mask_from_texture(mask_map, 2, 3),
      bytes([255, 0, 255, 0]))
check("red channel", items.mask_from_texture(red_tint, 2, 0), bytes([255, 0, 255, 0]))
check("red channel by default", items.mask_from_texture(red_tint, 2),
      bytes([255, 0, 255, 0]))

# A mask that is 3/4 lit must not arrive as a blanket fill: that is the failure
# this test exists for, and a flat channel passes a size check.
wide = texture(4, 1, [(0, 0, 0, 255), (0, 0, 0, 255), (0, 0, 0, 255),
                      (0, 0, 0, 0)])
mask = items.mask_from_texture(wide, 4, 3)
check("three of four lit", mask, bytes([255, 255, 255, 0]) * 4)
if mask == b"\xff" * 16:
    failures.append("a partial mask came back as a blanket fill")

# A stray lit texel is not a mask: one in a thousand would tint one speck.
speck = bytearray(1000 * 4)
speck[400:404] = b"\xff\xff\xff\xff"
check("one lit texel in a thousand", items.mask_channel(
    {"width": 1000, "height": 1, "rgba": bytes(speck)}), None)

print("")
if failures:
    for failure in failures:
        print("FAIL: %s" % failure)
    raise SystemExit(1)
print("PASS: the colour-change mask comes from the slot that has one")
