#!/usr/bin/env python3
"""Prove the metadata and shape-override blocks are read, not just listed.

Blocks 6 and 8 are the item's metadata: gender, asset type, component mask and
subcategory, and (in the versioned one) the skeleton it was made for. Block 4 is
its shape overrides: the body triangles it hides and the vertices it moves.

Both layouts are checked here against containers built byte by byte in the
order the format stores them - a tee's own block 6 (male, component, 0x08 shirt,
0xC9 tee) and a body shape block whose triangle numbers are read back as
written. A reserved word that is not zero must be refused, because that is the
sign the bytes were not a shape block at all.

    python3 tools/test_blocks.py
    MESH_MODULES=/tmp/unpacked python3 tools/test_blocks.py   # any build
"""

import importlib.util
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODULES = os.environ.get("MESH_MODULES") or os.path.join(
    os.path.dirname(os.path.dirname(HERE)), "recovered")

STOCK_TAIL = bytes.fromhex("c1c8f109a19cb2e0")


def metadata_unversioned():
    """Block 6 as a retail tee carries it: male, component, shirt, 0xC9."""
    return struct.pack("<BIII", 1, 1, 0x08, 0xC9)


def metadata_versioned():
    """Block 8: version 2, then the same fields, then the skeleton byte."""
    return struct.pack("<B", 2) + struct.pack("<BIII", 2, 1, 0x40, 0x1F8) + struct.pack("<B", 2)


def pack_bits(values, width):
    """LSB-first bit packing, the way both sections store their numbers."""
    out = bytearray()
    acc = 0
    bits = 0
    for value in values:
        acc |= value << bits
        bits += width
        while bits >= 8:
            out.append(acc & 0xFF)
            acc >>= 8
            bits -= 8
    if bits:
        out.append(acc & 0xFF)
    return bytes(out)


def shape_block(triangles, width=12, overrides=2, reserved=0):
    """Block 4: hide `triangles` of MaleBody, then move `overrides` vertices."""
    target = 0x3510  # the header word of MaleBody
    stock = struct.pack("<IHH", 0x02, 0, 1) + STOCK_TAIL
    out = struct.pack("<II", len(triangles), target) + stock
    out += struct.pack("<II", reserved, width)
    out += pack_bits(triangles, width)
    out += struct.pack("<II", overrides, 0xB200) + stock
    out += struct.pack("<II", 0, 16)
    out += struct.pack("<ffff", 7.0710678e-06, -0.2363, 0.0427, -0.0758)
    return out


def load():
    sys.path.insert(0, MODULES)
    path = os.path.join(MODULES, "avatar_mesh.py")
    spec = importlib.util.spec_from_file_location("avatar_mesh_under_test", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    mesh = load()
    failures = []

    meta = mesh.read_metadata(metadata_unversioned())
    print("  block 6 : %s" % (meta,))
    if meta["gender"] != "male":
        failures.append("block 6 gender is %r, expected male" % (meta["gender"],))
    if meta["asset_type"] != "component":
        failures.append("block 6 asset type is %r, expected component" % (meta["asset_type"],))
    if meta["component"] != "shirt" or meta["component_mask"] != "0x08":
        failures.append("block 6 component is %r/%r, expected shirt/0x08"
                        % (meta["component"], meta["component_mask"]))
    if meta["subcategory"] != "0xC9":
        failures.append("block 6 subcategory is %r, expected 0xC9" % (meta["subcategory"],))

    versioned = mesh.read_metadata(metadata_versioned(), versioned=True)
    print("  block 8 : %s" % (versioned,))
    if versioned["version"] != 2 or versioned["skeleton"] != "Natal":
        failures.append("block 8 is version %r/%r, expected 2/Natal"
                        % (versioned["version"], versioned["skeleton"]))
    if versioned["gender"] != "female" or versioned["component"] != "hat":
        failures.append("block 8 reads %r/%r, expected female/hat"
                        % (versioned["gender"], versioned["component"]))

    shape = mesh.read_shape_overrides(shape_block([1, 2, 3]))
    print("  block 4 : %s" % (shape,))
    if shape["triangles"] != 3 or shape["first_triangles"] != [1, 2, 3]:
        failures.append("triangle list is %r, expected [1, 2, 3]" % (shape["first_triangles"],))
    if shape["target"] != "MaleBody":
        failures.append("shape target is %r, expected MaleBody" % (shape["target"],))
    if shape["vertex_overrides"] != 2:
        failures.append("vertex overrides are %r, expected 2" % (shape["vertex_overrides"],))
    if abs(shape.get("vertex_step", 0) - 7.0710678e-06) > 1e-12:
        failures.append("vertex step is %r, expected the mesh step"
                        % (shape.get("vertex_step"),))

    # A shape block's reserved word is zero; anything else is a misread.
    try:
        mesh.read_metadata(metadata_unversioned()[:5])
    except mesh.Malformed:
        pass
    else:
        failures.append("a truncated metadata block was accepted")
    try:
        mesh.read_shape_overrides(shape_block([1, 2, 3], reserved=7))
    except mesh.Malformed:
        pass
    else:
        failures.append("a shape block with a non-zero reserved word was accepted")

    if failures:
        for failure in failures:
            print("FAIL: %s" % failure)
        return 1
    print("PASSED: metadata and shape blocks read as the format stores them")
    return 0


if __name__ == "__main__":
    sys.exit(main())
