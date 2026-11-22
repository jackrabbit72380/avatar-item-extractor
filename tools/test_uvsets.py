#!/usr/bin/env python3
"""Prove every UV set an item declares reaches the Blender file.

An OBJ holds one texture coordinate per face corner, so the import can only
bring in the set the item binds its first texture slot to. The rest are written
into the catalogue by the extractor and become named layers - uv0, uv1, uv2 - on
the mesh in Blender, which is where a map that belongs on a later set has to go.

Two halves are checked:

  * the extractor writes the extra sets, in the vertex order the OBJ uses
  * rig_items turns them into layers, with the values intact

    python3 tools/test_uvsets.py
"""

import base64
import importlib.util
import json
import os
import shutil
import struct
import sys
import tempfile
import types

HERE = os.path.dirname(os.path.abspath(__file__))
BAT = os.path.join(os.path.dirname(HERE), "Extract-AvatarItem-v20.bat")
MODULES = os.environ.get("RIG_MODULES") or os.path.join(
    os.path.dirname(os.path.dirname(HERE)), "recovered")


def batches():
    """One batch, three vertices, three UV sets with distinct values."""
    return [{
        "shader_id": 1,
        "vertices": [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)],
        # One entry per vertex, each holding that vertex's coordinate in every
        # set: (uv0, uv1, uv2).
        "uvs": [
            [(0.00, 0.00), (0.10, 0.20), (0.90, 0.80)],   # vertex 0
            [(0.50, 0.25), (0.30, 0.40), (0.70, 0.60)],   # vertex 1
            [(0.75, 0.10), (0.50, 0.60), (0.50, 0.40)],   # vertex 2
        ],
        "materials": [{"kind": "texture", "id": 1, "texture": 0, "uv_set": 0, "mode": 0}],
        "joints": [(0, 0, 0, 0)] * 3,
        "weights": [(1.0, 0.0, 0.0, 0.0)] * 3,
        "colours": [0, 0, 0],
        "indices": [0, 1, 2],
    }]


# ------------------------------------------------------------- stand-in bpy

class Vector:
    def __init__(self, x=0.0, y=0.0, z=0.0):
        self.x, self.y, self.z = float(x), float(y), float(z)

    def normalize(self):
        return self


class Quaternion:
    def __init__(self, x=0.0, y=0.0, z=0.0, w=1.0):
        self.x, self.y, self.z, self.w = x, y, z, w


class Matrix:
    def __init__(self, scale=1.0):
        self.scale = scale

    def inverted(self):
        return Matrix(1.0 / self.scale)

    def to_3x3(self):
        return self

    def __matmul__(self, other):
        if isinstance(other, Vector):
            return Vector(other.x * self.scale, other.y * self.scale, other.z * self.scale)
        return Matrix(self.scale * other.scale)

    def to_quaternion(self):
        return Quaternion()


def install_stubs():
    mathutils = types.ModuleType("mathutils")
    mathutils.Vector = Vector
    mathutils.Quaternion = Quaternion
    mathutils.Matrix = Matrix
    sys.modules["mathutils"] = mathutils
    sys.modules["bpy"] = types.ModuleType("bpy")


class UV:
    def __init__(self):
        self.uv = (0.0, 0.0)


class Layer:
    def __init__(self, name, count):
        self.name = name
        self.data = [UV() for _ in range(count)]


class Layers:
    def __init__(self, count):
        self.active = Layer("UVMap", count)
        self.all = [self.active]

    def new(self, name):
        layer = Layer(name, len(self.active.data))
        self.all.append(layer)
        return layer

    def __iter__(self):
        return iter(self.all)


def load_rig_items():
    install_stubs()
    path = os.path.join(MODULES, "rig_items.py")
    spec = importlib.util.spec_from_file_location("rig_items_under_test", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    work = tempfile.mkdtemp(prefix="avatar-uv-")
    failures = []
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

        avatar_mesh.strb_blocks = lambda data: [(3, 1, 0, b"model-payload")]
        avatar_mesh.decompress = lambda body: body
        avatar_mesh.read_model = lambda data: batches()

        inbox = os.path.join(work, "in")
        os.makedirs(inbox)
        with open(os.path.join(inbox, "Three Sets.bin"), "wb") as handle:
            handle.write(b"STRB" + b"\0" * 60)

        out = os.path.join(work, "out")
        code = extract_items.main(["--root", inbox, "--obj", "--out", out])
        if code not in (0, None):
            print("FAIL: the extractor returned %r" % (code,))
            return 1

        with open(os.path.join(out, "catalogue.json"), encoding="utf-8") as handle:
            record = json.load(handle)["items"][0]

        extra = record.get("uv_sets") or []
        print("  sets in the item   : 3")
        print("  sets carried beside: %d" % len(extra))
        if len(extra) != 2:
            failures.append("expected the 2 sets beyond uv0, got %d" % len(extra))
        elif extra[0][0] != [0.1, 0.2] or extra[1][2] != [0.5, 0.4]:
            failures.append("the carried values are wrong: %r / %r"
                            % (extra[0][0], extra[1][2]))

        # And now the Blender half: those become named layers on the mesh.
        rig = load_rig_items()
        layers = Layers(3)
        object_data = types.SimpleNamespace(
            name="Three Sets",
            data=types.SimpleNamespace(uv_layers=layers),
        )
        rig.apply_uv_sets(object_data, record)

        names = [layer.name for layer in layers.all]
        print("  layers on the mesh : %s" % names)
        if names != ["uv0", "uv1", "uv2"]:
            failures.append("layers are %r, expected uv0, uv1, uv2" % (names,))
        else:
            got = layers.all[1].data[0].uv
            print("  uv1 of vertex 0    : %r" % (got,))
            if list(got) != [0.1, 0.2]:
                failures.append("uv1 vertex 0 is %r, expected [0.1, 0.2]" % (got,))
            got = layers.all[2].data[2].uv
            if list(got) != [0.5, 0.4]:
                failures.append("uv2 vertex 2 is %r, expected [0.5, 0.4]" % (got,))

        # An item with one set must not grow empty layers.
        single = types.SimpleNamespace(name="One Set",
                                       data=types.SimpleNamespace(uv_layers=Layers(3)))
        rig.apply_uv_sets(single, {"uv_sets": []})
        if [layer.name for layer in single.data.uv_layers.all] != ["uv0"]:
            failures.append("an item with one UV set gained extra layers")

        print("")
        if failures:
            for line in failures:
                print("FAIL: " + line)
            return 1
        print("PASS: all three UV sets reach the mesh as uv0, uv1, uv2")
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
