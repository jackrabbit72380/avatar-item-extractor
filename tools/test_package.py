#!/usr/bin/env python3
"""Prove the extractor reads a marketplace package directly and takes the newer
revision out of it.

A marketplace item downloads as one file named after its GUID, with the STRB
assets buried in its data area - the same item twice, asset.bin and
asset_v2.bin. Pointing the extractor at that file must yield the item once, from
the newer copy: the one carrying the versioned metadata block (id 8).

This builds such a package with both revisions and checks three things:

  * the item comes out once, not twice
  * the blocks it was read from include id 8, so the newer copy won
  * report.txt says which copy was used

    python3 tools/test_package.py
"""

import base64
import json
import os
import shutil
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
BAT = os.path.join(os.path.dirname(HERE), "Extract-AvatarItem-v21.bat")
PACKAGE = "000000082C0C1281C54DAE304D5307E6"


def container(blocks):
    """A STRB container: 26-byte header, then (id, count, entry, payload)."""
    head = bytearray(26)
    head[0:4] = b"STRB"
    head[4] = 0   # no alignment
    head[5] = 1   # little endian
    head[22] = 1  # id width
    head[23] = 4  # size width
    out = bytes(head)
    for ident, payload in blocks:
        out += bytes([ident]) + struct.pack("<II", len(payload), 1) + payload
    return out


def colour_table():
    return struct.pack("<I", 2) + b"\x23\x23\x23\xff" + b"\x00" * 20 + b"\x23\x23\x23" * 2


def package():
    """LIVE header, then the older asset, then the newer one."""
    old = container([(3, b"OLD" * 20), (7, colour_table())])
    new = container([(8, b"\x0f" * 15), (7, colour_table()), (3, b"NEW" * 80)])
    body = b"LIVE" + b"\x00" * 0x300 + old + b"\x00" * 0x20 + new + b"\x00" * 0x20
    return body, old, new


def main():
    work = tempfile.mkdtemp(prefix="avatar-package-")
    try:
        sys.path.insert(0, HERE)
        import payload

        with open(BAT, encoding="utf-8", newline="") as handle:
            entries = payload.read_entries(handle.read())
        for name, value in entries.items():
            path = os.path.join(work, name.replace("/", os.sep))
            parent = os.path.dirname(path)
            if parent:
                os.makedirs(parent, exist_ok=True)
            if isinstance(value, dict):
                with open(path, "wb") as handle:
                    handle.write(base64.b64decode(value["b64"].encode("ascii")))
            else:
                with open(path, "w", encoding="utf-8", newline="") as handle:
                    handle.write(value)

        sys.path.insert(0, work)
        import avatar_mesh
        import extract_items

        body, old, new = package()
        inbox = os.path.join(work, "item")
        os.makedirs(inbox)
        # A package has no extension: it is recognised by its LIVE header.
        with open(os.path.join(inbox, PACKAGE), "wb") as handle:
            handle.write(body)

        avatar_mesh.decompress = lambda chunk: chunk

        def read_model(data):
            """Only a model payload parses - a package of them does not.

            The real parser rejects anything that is not a model, which is what
            sends a package down the package path instead of being read as a
            bare model block.
            """
            if data[:3] not in (b"OLD", b"NEW"):
                raise avatar_mesh.Malformed("not a model payload")
            return [{
                "shader_id": 1,
                "vertices": [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)],
                "uvs": [[(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)]],
                "materials": [],
                "joints": [(0, 0, 0, 0)] * 3,
                "weights": [(1.0, 0.0, 0.0, 0.0)] * 3,
                "colours": [0, 0, 0],
                "indices": [0, 1, 2],
            }]

        avatar_mesh.read_model = read_model

        out = os.path.join(work, "out")
        code = extract_items.main(["--root", inbox, "--obj", "--out", out])
        if code not in (0, None):
            print("FAIL: the extractor returned %r" % (code,))
            return 1

        models = os.path.join(out, "extracted for max users")
        objs = [name for name in os.listdir(models if os.path.isdir(models) else out)
                if name.endswith(".obj")]
        print("  .obj files : %d %s" % (len(objs), objs))
        if len(objs) != 1:
            print("FAIL: expected one model, got %d" % len(objs))
            return 1

        with open(os.path.join(out, "catalogue.json"), encoding="utf-8") as handle:
            catalogue = json.load(handle)
        items = catalogue["items"]
        if len(items) != 1:
            print("FAIL: expected one item, got %d" % len(items))
            return 1

        blocks = items[0].get("blocks") or []
        ids = [block["id"] for block in blocks]
        print("  blocks read: %s" % ids)
        if 8 not in ids:
            print("FAIL: the older copy was used - block 8 is what marks the newer one")
            return 1
        if 3 not in ids:
            print("FAIL: no model block in what was read")
            return 1

        with open(os.path.join(out, "report.txt"), encoding="utf-8") as handle:
            report = handle.read()
        if "the newest revision in the package" not in report:
            print("FAIL: report.txt does not say which copy was used")
            print(report)
            return 1
        print("  report     : %s"
              % next(line for line in report.splitlines()
                     if line.startswith("asset:")))

        print("")
        print("PASS: a package file is read directly, and the newer revision wins")

        # Second case: the same item as two loose files. Both must be supported,
        # and the newer one must still win - a folder with asset.bin and
        # asset_v2.bin side by side is the normal shape of an extract.
        loose = os.path.join(work, "loose")
        os.makedirs(loose)
        with open(os.path.join(loose, "asset.bin"), "wb") as handle:
            handle.write(old)
        with open(os.path.join(loose, "asset_v2.bin"), "wb") as handle:
            handle.write(new)

        out2 = os.path.join(work, "out2")
        code = extract_items.main(["--root", loose, "--obj", "--out", out2])
        if code not in (0, None):
            print("FAIL: the loose-file extractor returned %r" % (code,))
            return 1

        models2 = os.path.join(out2, "extracted for max users")
        objs2 = [name for name in os.listdir(models2 if os.path.isdir(models2) else out2)
                 if name.endswith(".obj")]
        print("  loose .obj : %d %s" % (len(objs2), objs2))
        if len(objs2) != 1:
            print("FAIL: two loose revisions produced %d models, expected 1" % len(objs2))
            return 1

        with open(os.path.join(out2, "catalogue.json"), encoding="utf-8") as handle:
            ids2 = [block["id"] for block in json.load(handle)["items"][0]["blocks"]]
        print("  loose blocks: %s" % ids2)
        if 8 not in ids2:
            print("FAIL: the loose path read asset.bin, the older revision")
            return 1

        print("")
        print("PASS: loose asset.bin + asset_v2.bin give one model, from the newer one")
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
