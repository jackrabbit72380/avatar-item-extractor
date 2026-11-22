#!/usr/bin/env python3
"""Prove the STRB block walk lands on the right bytes.

Each block's payload is ``data_size * entry_size`` bytes. Advancing by
``data_size`` alone is correct only while every entry is one byte wide; as soon
as an entry is wider, the next block is read from the middle of the previous
payload and everything after it is nonsense - which shows up as a texture and a
colour table that are simply "not there".

This builds a container with entries wider than one byte and checks the walk
finds both blocks with their payloads intact.

    python3 tools/test_strb.py
    MESH_MODULES=/tmp/unpacked python3 tools/test_strb.py   # any build
"""

import importlib.util
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODULES = os.environ.get("MESH_MODULES") or os.path.join(
    os.path.dirname(os.path.dirname(HERE)), "recovered")


def container():
    """A STRB with two blocks, the first holding entries four bytes wide."""
    head = bytearray(26)
    head[0:4] = b"STRB"
    head[4] = 0   # no alignment
    head[5] = 1   # little endian
    head[22] = 1  # id width
    head[23] = 4  # size width
    out = bytes(head)
    # id 3: two entries of four bytes each -> eight bytes of payload
    out += bytes([3]) + struct.pack("<II", 2, 4) + b"AAAABBBB"
    # id 7: one entry of nine bytes -> the colour table shape
    out += bytes([7]) + struct.pack("<II", 1, 9) + b"CCCCCCCCC"
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

    try:
        blocks = mesh.strb_blocks(container())
    except Exception as exc:
        print("FAIL: strb_blocks raised %s: %s" % (type(exc).__name__, exc))
        return 1

    ids = [block[0] for block in blocks]
    sizes = [len(block[3]) for block in blocks]
    counts = [block[1] for block in blocks]
    print("  blocks found : %r" % (ids,))
    print("  payload sizes: %r" % (sizes,))
    print("  entry counts : %r" % (counts,))

    if ids != [3, 7]:
        failures.append("block ids are %r, expected [3, 7]" % (ids,))
    if sizes != [8, 9]:
        failures.append("payload sizes are %r, expected [8, 9]" % (sizes,))
    if counts != [2, 1]:
        failures.append("entry counts are %r, expected [2, 1]" % (counts,))
    if blocks and blocks[0][3][:4] != b"AAAA":
        failures.append("the first payload does not start where it should")
    if len(blocks) > 1 and blocks[1][3] != b"CCCCCCCCC":
        failures.append("the second payload is not the colour table's bytes")

    if failures:
        print("")
        for line in failures:
            print("FAIL: " + line)
        return 1
    print("")
    print("PASS: every block is read from its own payload, not the middle of one")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
