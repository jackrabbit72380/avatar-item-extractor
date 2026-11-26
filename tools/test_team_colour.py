#!/usr/bin/env python3
"""Prove the detail and team-colour maps are built the way Halo CE reads them.

Halo CE's shader_model packs four masks into the multipurpose map in Gearbox
order - red detail, green self-illumination, blue specular, alpha colour change -
and Guerilla still labels the detail slot "alpha" because the Xbox kept the
detail mask there. Two things follow, and this test exists for both:

  * a detail map is invisible unless the multipurpose map's RED channel is
    painted, so the red channel is the mask and it has to be written;
  * the base map is MULTIPLIED by the change colour, so the team colour only
    reads clean where the base map is white - hence the team-colour copy of the
    base map, whitened by the mask, not a recoloured suit.

    python3 tools/test_team_colour.py
    MESH_MODULES=/tmp/unpacked python3 tools/test_team_colour.py   # any build
"""

import importlib.util
import os
import shutil
import struct
import sys
import tempfile

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
    print("  %-52s %r" % (label, got))
    if got != want:
        failures.append("%s: %r, expected %r" % (label, got, want))


def read_tiff(path):
    data = open(path, "rb").read()
    count = struct.unpack("<H", data[struct.unpack("<I", data[4:8])[0]:
                                    struct.unpack("<I", data[4:8])[0] + 2])[0]
    where = struct.unpack("<I", data[4:8])[0]
    found = {}
    for i in range(count):
        at = where + 2 + i * 12
        tag, kind, number = struct.unpack("<HHI", data[at:at + 8])
        size = {3: 2, 4: 4}[kind] * number
        raw = (data[at + 8:at + 8 + size] if size <= 4 else
               data[struct.unpack("<I", data[at + 8:at + 12])[0]:][:size])
        found[tag] = struct.unpack("<" + ("H" if kind == 3 else "I") * number,
                                   raw)
    return (found[256][0], found[257][0], found[277][0],
            data[found[273][0]:found[273][0] + found[279][0]])


print("the four masks go in their Halo CE channels")
size = 4
detail = bytes([255] * (size * size))
tint = bytes([0, 64, 128, 255] * size)
packed = items.packed_multipurpose(detail, tint, size)
check("red is the detail mask", list(packed[0::4][:4]), [255, 255, 255, 255])
check("green is self-illumination, unpainted", set(packed[1::4]), {0})
check("blue is specular, unpainted", set(packed[2::4]), {0})
check("alpha is the colour change", list(packed[3::4][:4]), [0, 64, 128, 255])

print("shine and glow take blue and green, and nothing overrides the detail")
shine = bytes([0, 64, 128, 255] * 4)
glow = bytes([10, 20, 30, 40] * 4)
packed_all = items.packed_multipurpose(detail, tint, 4, glow, shine)
check("green is self-illumination", list(packed_all[1::4][:4]), [10, 20, 30, 40])
check("blue is the specular mask", list(packed_all[2::4][:4]), [0, 64, 128, 255])
check("red and alpha are untouched by them",
      (list(packed_all[0::4][:2]), list(packed_all[3::4][:2])),
      ([255, 255], [0, 64]))

print("the derived specular mask shines on dark neutral plate, not warm cloth")
plate = {"rgba": bytes([60, 66, 55, 255] * 4), "width": 2, "height": 2}
cloth = {"rgba": bytes([123, 109, 88, 255] * 4), "width": 2, "height": 2}
bright = {"rgba": bytes([235, 235, 235, 255] * 4), "width": 2, "height": 2}
check("plate shines", set(items.derived_shine(plate, 2)), {255})
check("cloth does not", max(items.derived_shine(cloth, 2)) < 60, True)
check("bright paint does not", max(items.derived_shine(bright, 2)), 0)

print("the team-colour base map is whitened by the mask, not recoloured")
rgba = bytes([0, 128, 255, 200] * 4)
mask = bytes([0, 255, 128, 64])
team = items.team_colour_base(rgba, 4, 1, mask, 4)
check("black mask leaves the texel alone", list(team[0:3]), [0, 128, 255])
check("white mask takes it to white", list(team[4:7]), [255, 255, 255])
check("half mask is the two mixed", list(team[8:11]), [128, 191, 255])
check("alpha is kept", [team[3], team[7]], [200, 200])

print("a derived detail map is grey detail on the texels the item paints")
picture = {"rgba": bytes([40, 40, 40, 255] * 8 + [200, 200, 200, 255] * 8),
           "width": 4, "height": 4}
art, mask = items.derived_detail(picture, 4)
check("art is 4x4 RGBA", len(art), 4 * 4 * 4)
check("art is grey and opaque", (set(art[0::4]) == set(art[1::4]) == set(art[2::4]),
                                 set(art[3::4])), (True, {255}))
check("mask paints where the map is painted", set(mask), {255})
picture_padded = {"rgba": bytes([40, 40, 40, 255] * 4 + [0, 0, 0, 0] * 4),
                  "width": 2, "height": 4}
_, padded_mask = items.derived_detail(picture_padded, 4)
check("padding is not painted", (padded_mask[0], padded_mask[-1]), (255, 0))

print("the masks survive the file formats tool.exe reads")
folder = tempfile.mkdtemp()
try:
    small = os.path.join(folder, "detail")
    items.write_tiff(small + ".tif", art, 4, 4)
    width, height, channels, pixels = read_tiff(small + ".tif")
    check("detail .tif is 4x4 RGBA", (width, height, channels), (4, 4, 4))
    check("detail .tif keeps its grey", pixels[0], art[0])
    multi = os.path.join(folder, "multipurpose")
    items.write_tiff(multi + ".tif", packed, 4, 4)
    width, height, channels, pixels = read_tiff(multi + ".tif")
    check("multipurpose .tif keeps red", set(pixels[0::4]), {255})
    check("multipurpose .tif keeps alpha", list(pixels[3::4][:4]),
          [0, 64, 128, 255])
    items.write_png(multi + ".png", packed, 4, 4)
    back = items.read_png(open(multi + ".png", "rb").read())
    check("multipurpose .png round trip", list(back[0][3::4][:4]),
          [0, 64, 128, 255])
    art_path = os.path.join(folder, "art.png")
    items.write_png(art_path, art, 4, 4)
    got = items.detail_image(art_path, 4)
    check("an authored detail map reads back", got[0] == art, True)
finally:
    shutil.rmtree(folder)

print("")
if failures:
    for line in failures:
        print("FAIL: " + line)
    print("FAILED: %d" % len(failures))
    sys.exit(1)
print("PASS: detail in red, colour change in alpha, and a base map taken to white")
