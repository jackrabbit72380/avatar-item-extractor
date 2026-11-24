#!/usr/bin/env python3
"""Check the .jms the tool writes against the layout Halo CE's tool reads.

The reference is HaloCE's own exporter (BlueStreak 1.0.4, "Adapted for HaloCE"),
which writes, positionally and with no section markers:

    8200 <3251> <node_count>
    <name> <first_child> <next_sibling> <rx> <ry> <rz> <rw> <tx> <ty> <tz>
    <material_count>  then  <name> <none>  per material
    <marker_count>
    <region_count>   then  <name>  per region
    <vertex_count>
    <node0> <x> <y> <z> <nx> <ny> <nz> <node1> <weight> <u> <v> <w>
    <face_count>
    <region> <shader> <v0> <v1> <v2>

The important part for texturing is the vertex line: twelve fields, with the
texture coordinate on the same line as the position - one u, one v, one w - and
three vertices per triangle, because JMS does not share vertices between faces.

rig_items.py is run here against a stand-in bpy and mathutils, with identity
transforms so the arithmetic is checkable by hand.

    python3 tools/test_jms.py
"""

import importlib.util
import os
import sys
import tempfile
import types

HERE = os.path.dirname(os.path.abspath(__file__))
MODULES = os.environ.get("RIG_MODULES") or os.path.join(
    os.path.dirname(HERE), "src")


# --------------------------------------------------------------- stand-in bpy

class Vector:
    def __init__(self, x=0.0, y=0.0, z=0.0):
        self.x, self.y, self.z = float(x), float(y), float(z)

    def normalize(self):
        length = (self.x ** 2 + self.y ** 2 + self.z ** 2) ** 0.5
        if length > 1e-12:
            self.x, self.y, self.z = self.x / length, self.y / length, self.z / length
        return self


class Quaternion:
    def __init__(self, x=0.0, y=0.0, z=0.0, w=1.0):
        self.x, self.y, self.z, self.w = x, y, z, w


class Matrix:
    """A scale and a translation - enough to tell the model's space from the
    parent's, which is the one thing a node line can get wrong."""

    def __init__(self, scale=1.0, translate=(0.0, 0.0, 0.0)):
        self.scale = scale
        self.translate = tuple(float(value) for value in translate)

    def inverted(self):
        scale = 1.0 / self.scale
        return Matrix(scale, tuple(-value * scale for value in self.translate))

    def to_3x3(self):
        return Matrix(self.scale)

    def __matmul__(self, other):
        if isinstance(other, Vector):
            return Vector(self.translate[0] + other.x * self.scale,
                          self.translate[1] + other.y * self.scale,
                          self.translate[2] + other.z * self.scale)
        return Matrix(self.scale * other.scale,
                      tuple(self.translate[axis] + self.scale * other.translate[axis]
                            for axis in range(3)))

    @property
    def translation(self):
        return Vector(*self.translate)

    def to_quaternion(self):
        return Quaternion()


def install_stubs():
    mathutils = types.ModuleType("mathutils")
    mathutils.Vector = Vector
    mathutils.Quaternion = Quaternion
    mathutils.Matrix = Matrix
    sys.modules["mathutils"] = mathutils
    sys.modules["bpy"] = types.ModuleType("bpy")


# ------------------------------------------------------------------ fake scene

class UV:
    def __init__(self, x, y):
        self.x, self.y = x, y


class Loop:
    def __init__(self, vertex_index):
        self.vertex_index = vertex_index


class Group:
    def __init__(self, index, name):
        self.index, self.name = index, name


class VertexGroup:
    def __init__(self, group, weight):
        self.group, self.weight = group, weight


class Vertex:
    def __init__(self, index, co, normal, groups):
        self.index = index
        self.co = co
        self.normal = normal
        self.groups = groups


class Polygon:
    def __init__(self, loop_indices, material_index):
        self.loop_indices = loop_indices
        self.material_index = material_index


class Mesh:
    def __init__(self, vertices, loops, polygons, uvs):
        self.vertices = vertices
        self.loops = loops
        self.polygons = polygons
        self.uv_layers = types.SimpleNamespace(
            active=types.SimpleNamespace(data=[types.SimpleNamespace(uv=uv) for uv in uvs]))


class Slot:
    def __init__(self, name):
        self.material = types.SimpleNamespace(name=name) if name else None


class Bone:
    def __init__(self, name, parent, head):
        self.name = name
        self.parent = parent
        self.head_local = head
        # A bone's matrix_local puts its head where it is in the armature, so a
        # bone away from the origin is what makes parent space and model space
        # give different numbers.
        self.matrix_local = Matrix(translate=(head.x, head.y, head.z))


def build():
    """Two triangles, four vertices, two bones, one material."""
    groups = [Group(0, "bip01 pelvis"), Group(1, "bip01 spine")]
    vertices = [
        Vertex(0, Vector(0, 0, 0), Vector(0, 0, 1), [VertexGroup(0, 0.75), VertexGroup(1, 0.25)]),
        Vertex(1, Vector(1, 0, 0), Vector(0, 0, 1), [VertexGroup(0, 1.0)]),
        Vertex(2, Vector(1, 1, 0), Vector(0, 0, 1), [VertexGroup(1, 1.0)]),
        Vertex(3, Vector(0, 1, 0), Vector(0, 0, 1), [VertexGroup(0, 0.5), VertexGroup(1, 0.5)]),
    ]
    # A quad as two triangles: 0-1-2 and 0-2-3, six corners.
    loops = [Loop(0), Loop(1), Loop(2), Loop(3)]
    uvs = [UV(0.0, 0.0), UV(1.0, 0.0), UV(1.0, 1.0), UV(0.0, 1.0)]
    polygons = [Polygon([0, 1, 2], 0), Polygon([0, 2, 3], 0)]

    mesh = Mesh(vertices, loops, polygons, uvs)
    object_data = types.SimpleNamespace(
        data=mesh,
        matrix_world=Matrix(),
        material_slots=[Slot("item_material")],
        vertex_groups=[Group(0, "bip01 pelvis"), Group(1, "bip01 spine")],
    )

    pelvis = Bone("bip01 pelvis", None, Vector(0, 0, 5.0))
    spine = Bone("bip01 spine", pelvis, Vector(0, 0, 6.5))
    armature = types.SimpleNamespace(
        data=types.SimpleNamespace(bones=[pelvis, spine]),
        matrix_world=Matrix(),
    )
    return object_data, armature


# ----------------------------------------------------------------------- test

def main():
    install_stubs()
    path = os.path.join(MODULES, "rig_items.py")
    spec = importlib.util.spec_from_file_location("rig_items_under_test", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    object_data, armature = build()
    work = tempfile.mkdtemp(prefix="avatar-jms-")
    target = os.path.join(work, "item.jms")
    try:
        module.export_jms(object_data, armature, target)
        with open(target, encoding="ascii") as handle:
            lines = [line.rstrip("\n") for line in handle]
    finally:
        import shutil
        shutil.rmtree(work, ignore_errors=True)

    failures = []

    def check(condition, message):
        if not condition:
            failures.append(message)

    if not lines:
        print("FAIL: the .jms is empty")
        return 1

    header = lines[0].split("\t")
    check(header[:2] == ["8200", "3251"], "header is %r, expected 8200 / 3251" % (header,))
    check(len(header) == 3 and header[2] == "2",
          "header does not carry the node count: %r" % (header,))

    node = lines[1].split("\t")
    check(len(node) == 10, "node line has %d fields, expected 10" % len(node))
    check(node[0] == "bip01_pelvis", "node name is %r" % node[0])
    check(node[1] == "1", "pelvis first child should be node 1, got %r" % node[1])
    check(node[2] == "-1", "pelvis next sibling should be -1, got %r" % node[2])
    # The root is the one node whose translation is where it sits in the model.
    check(abs(float(node[7])) < 1e-4 and abs(float(node[8])) < 1e-4
          and abs(float(node[9]) - 5.0) < 1e-4,
          "the root node should be where the armature puts it, got %r"
          % (node[7:10],))

    # Every other node is written in its PARENT's space. Halo builds the
    # skeleton by walking the tree and adding each node's translation in its
    # parent's frame, so a bone written in the model's space instead - 6.5 up
    # rather than 1.5 above the pelvis - is a bone in the wrong place, and a
    # skeleton of them is the pile a model viewer shows as garbage.
    child = lines[2].split("\t")
    check(abs(float(child[7])) < 1e-4 and abs(float(child[8])) < 1e-4
          and abs(float(child[9]) - 1.5) < 1e-4,
          "node 1 is not in its parent's space (expected 0 0 1.5): %r"
          % (child[7:10],))

    cursor = 1 + len(armature.data.bones)
    check(lines[cursor] == "1", "material count is %r, expected 1" % lines[cursor])
    check(lines[cursor + 1].split("\t")[-1] == "<none>",
          "material line should end in <none>: %r" % lines[cursor + 1])
    cursor += 2
    check(lines[cursor] == "0", "marker count is %r, expected 0" % lines[cursor])
    cursor += 1
    check(lines[cursor] == "1", "region count is %r, expected 1" % lines[cursor])
    cursor += 2  # region count + its name

    vertices = int(lines[cursor])
    check(vertices == 6, "vertex count is %d, expected 6 (two triangles, unshared)"
          % vertices)
    cursor += 1
    first_vertex = cursor
    for index in range(vertices):
        fields = lines[cursor + index].split("\t")
        if len(fields) != 12:
            failures.append("vertex %d has %d fields, expected 12: %r"
                            % (index, len(fields), fields))
            continue
        if fields[11] != "0.000000":
            failures.append("vertex %d w is %r, expected 0" % (index, fields[11]))
        try:
            [float(value) for value in fields[1:6]]
        except ValueError:
            failures.append("vertex %d position/normal is not numeric: %r" % (index, fields))
    cursor += vertices

    faces = int(lines[cursor])
    check(faces == 2, "face count is %d, expected 2" % faces)
    cursor += 1
    for index in range(faces):
        fields = lines[cursor + index].split("\t")
        if len(fields) != 5:
            failures.append("face %d has %d fields, expected 5: %r"
                            % (index, len(fields), fields))
            continue
        if fields[0] != "0":
            failures.append("face %d region is %r, expected 0" % (index, fields[0]))
        for value in fields[2:5]:
            if not (0 <= int(value) < vertices):
                failures.append("face %d points at vertex %s, out of range"
                                % (index, value))
    cursor += faces

    check(cursor == len(lines), "there are %d trailing lines after the faces"
          % (len(lines) - cursor))

    # The texture coordinate must be the one on the mesh, not zeros.
    uvs = [lines[first_vertex + index].split("\t")[9:11] for index in range(vertices)]
    if all(u == "0.000000" and v == "0.000000" for u, v in uvs):
        failures.append("every UV is 0,0 - the texture coordinate is not being written")

    print("  nodes    : %d" % len(armature.data.bones))
    print("  vertices : %d (%.0f per triangle, unshared)" % (vertices, vertices / max(1, faces)))
    print("  faces    : %d" % faces)
    print("  uv sample: %s" % (uvs[0],))
    print("")

    if failures:
        for line in failures:
            print("FAIL: " + line)
        return 1
    print("PASS: the .jms is laid out the way Halo CE's tool reads it")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
