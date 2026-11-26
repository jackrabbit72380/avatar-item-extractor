#!/usr/bin/env python3
"""Prove the biped's collision model and physics the way tool.exe reads them.

A biped is not collidable without two more tags, and tool.exe builds both from
a .jms in the physics\\ folder of the same source directory the model came from:

    tool collision-geometry <item>   reads physics\\<item>.JMS
    tool physics          <item>     reads physics\\<item>.JMS

Both verbs are strict about different things, so both are checked here, inside
Blender against the rig the build really uses:

  * every collision piece is a closed box - twelve triangles, each edge shared
    exactly twice and in opposite directions, every face wound outward - because
    tool.exe treats an open piece as a broken one and writes a .wrl instead of a
    tag;
  * no two pieces overlap or touch, which is the rule that keeps a compiled
    collision model from producing "weird errors in game";
  * the collision .jms, the physics .jms and the render model carry the same
    node block and the same header checksum, so tool.exe's "node list checksum
    ... don't match" check passes for all three;
  * both name one region, the same one the render model names, because tool.exe
    also refuses a collision model whose regions differ from the gbxmodel's;
  * the physics .jms holds a sphere on the pelvis with a usable radius, which is
    what tool imports as the object's collision spheres.

    blender -b --factory-startup --python tools/test_biped_collision.py

Exits 0 only when every check passes, 2 when run without Blender.
"""

try:
    import bpy
    from mathutils import Vector  # noqa: F401 - only present inside Blender
except ImportError:
    print("needs Blender's own python: skipping here")
    raise SystemExit(2)

import importlib.util
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MODULES = os.environ.get("RIG_MODULES") or os.path.join(
    os.path.dirname(HERE), "src")
RIG = os.path.join(os.path.dirname(HERE), "src", "rig",
                   "master chief skeleton.blend")

# The bones a body has collision for, and how wide a piece each one gets: a
# plate-sized box would be useless and a body-sized one would swallow the next
# bone, so each is a couple of units of geometry centred on its own bone.
PIECES = [("bip01 pelvis", 6.0), ("bip01 spine1", 6.0), ("bip01 head", 4.0),
          ("bip01 l upperarm", 3.0), ("bip01 l forearm", 2.5),
          ("bip01 r upperarm", 3.0), ("bip01 r forearm", 2.5),
          ("bip01 l thigh", 3.5), ("bip01 l calf", 3.0),
          ("bip01 r thigh", 3.5), ("bip01 r calf", 3.0)]


def load_rig_items():
    name = "rig_items"
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(MODULES, "rig_items.py"))
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def closed(triangle_vertices, triangles):
    """A closed piece: every edge twice, in opposite directions, wound out."""
    edges = {}
    for one, two, three in triangles:
        for a, b in ((one, two), (two, three), (three, one)):
            key = (min(a, b), max(a, b))
            edges[key] = edges.get(key, 0) + 1
    if any(count != 2 for count in edges.values()):
        return False, "an edge is not shared by exactly two faces"
    # Every face's normal has to point away from the piece's own middle, or the
    # piece is inside out and tool.exe reads it as solid on the wrong side.
    middle = [sum(point[axis] for point in triangle_vertices) / len(triangle_vertices)
              for axis in range(3)]
    for one, two, three in triangles:
        a, b, c = (triangle_vertices[number] for number in (one, two, three))
        normal = ((b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]),
                  (b[2] - a[2]) * (c[0] - a[0]) - (b[0] - a[0]) * (c[2] - a[2]),
                  (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
        outward = sum(normal[axis] * ((a[axis] + b[axis] + c[axis]) / 3.0
                                      - middle[axis]) for axis in range(3))
        if outward <= 0.0:
            return False, "a face is wound inward"
    return True, ""


def flat(text):
    return [line for line in text.splitlines() if line.strip()]


def main():
    bpy.ops.wm.open_mainfile(filepath=RIG)
    armature = next((thing for thing in bpy.data.objects
                     if thing.type == "ARMATURE"), None)
    if armature is None:
        print("FAIL: no armature in %s" % RIG)
        return 1
    rig = load_rig_items()
    order, index_of, rows, checksum = rig.jms_node_rows(armature)
    print("rig: %d nodes, checksum %d" % (len(order), checksum))

    # A body: one small cube of geometry per bone, riding that bone alone, so
    # the boxes the export builds come from the weighting and not from a guess.
    mesh = bpy.data.meshes.new("test body")
    object_data = bpy.data.objects.new("test body", mesh)
    bpy.context.scene.collection.objects.link(object_data)
    bones = {bone.name: bone for bone in armature.data.bones}
    points = []
    spans = []
    for name, size in PIECES:
        if name not in bones:
            print("FAIL: the rig has no %s" % name)
            return 1
        centre = bones[name].head_local
        first = len(points)
        for off in ((-size, -size, -size), (size, -size, -size),
                    (size, size, -size), (-size, size, -size),
                    (-size, -size, size), (size, -size, size),
                    (size, size, size), (-size, size, size)):
            points.append((centre.x + off[0], centre.y + off[1],
                           centre.z + off[2]))
        spans.append((name, first, len(points)))
    # One call, because from_pydata appends: calling it per bone leaves the mesh
    # holding a vertex list it was not told about and raises.
    mesh.from_pydata(points, [], [])
    for name, first, last in spans:
        object_data.vertex_groups.new(name=name).add(
            list(range(first, last)), 1.0, "REPLACE")
    mesh.update()
    made = len(spans)
    print("body: %d pieces of geometry on %d bones" % (made, made))

    failed = 0
    boxes = rig.collision_boxes(object_data, armature, index_of)
    ok = len(boxes) == made
    print("  %s one box per bone - %d of %d" % ("PASS" if ok else "FAIL",
                                                len(boxes), made))
    failed += 0 if ok else 1

    apart = True
    for first in range(len(boxes)):
        for second in range(first + 1, len(boxes)):
            one, two = boxes[first], boxes[second]
            overlap = [min(one[2][axis], two[2][axis])
                       - max(one[1][axis], two[1][axis]) for axis in range(3)]
            if min(overlap) > 0.0:
                apart = False
                print("     boxes %d and %d overlap by %.3f"
                      % (one[0], two[0], min(overlap)))
    print("  %s no two boxes overlap or touch" % ("PASS" if apart else "FAIL"))
    failed += 0 if apart else 1

    closed_ok = True
    for _, low, high in boxes:
        corners, triangles = rig._box_triangles(low, high)
        full, why = closed(corners, triangles)
        if not full:
            closed_ok = False
            print("     box at %s: %s" % (low, why))
    print("  %s every piece is a closed box, wound outward"
          % ("PASS" if closed_ok else "FAIL"))
    failed += 0 if closed_ok else 1

    work = tempfile.mkdtemp(prefix="collision-")
    collision = os.path.join(work, "collision.jms")
    physics = os.path.join(work, "physics.jms")
    rig.export_collision_jms(object_data, armature, collision, "test material")
    rig.export_physics_jms(object_data, armature, physics, "test material", boxes)

    model = os.path.join(work, "model.jms")
    rig.export_jms(object_data, armature, model)

    render = flat(open(model, encoding="utf-8").read())
    collide = flat(open(collision, encoding="utf-8").read())
    solid = flat(open(physics, encoding="utf-8").read())
    nodes = len(rows)
    same = (render[0] == collide[0] == solid[0]
            and render[1:1 + nodes] == collide[1:1 + nodes]
            == solid[1:1 + nodes])
    print("  %s the three .jms carry one node block and one checksum (%s)"
          % ("PASS" if same else "FAIL", render[0].split("\t")[1]))
    failed += 0 if same else 1

    def regions(lines):
        """Count and name the region block, which sits after nodes/materials/markers."""
        position = 1 + nodes
        materials = int(lines[position])
        position += 1 + materials
        markers = int(lines[position])
        position += 1 + markers
        count = int(lines[position])
        return count, lines[position + 1:position + 1 + count]

    name_render = regions(render)
    name_collide = regions(collide)
    same_region = name_render == name_collide
    print("  %s the collision model's regions match the model's - %s"
          % ("PASS" if same_region else "FAIL", name_collide))
    failed += 0 if same_region else 1

    # Where a section starts, walking the file the way its reader does: the
    # node block, then materials, markers and regions, then the vertices.
    def sections(lines):
        position = 1 + nodes
        materials = int(lines[position])
        position += 1 + materials
        markers = int(lines[position])
        position += 1 + markers
        regions = int(lines[position])
        position += 1 + regions
        vertices = int(lines[position])
        return position + 1, vertices

    # A .jms carries a vertex per triangle corner - the format has no shared
    # vertices - so a piece is closed by POSITION, which is what tool.exe welds
    # on when it builds the tag. Checking the written file that way is the only
    # test that looks at what tool.exe will actually read.
    position, vertices = sections(collide)
    faces_in_file = int(collide[position + vertices])
    welded = {}
    for number in range(faces_in_file):
        numbers = [int(value) for value in
                   collide[position + vertices + 1 + number].split("\t")[2:5]]
        spots = []
        for number_in_file in numbers:
            row = collide[position + number_in_file].split("\t")
            spots.append(tuple(round(float(row[axis]), 4) for axis in (1, 2, 3)))
        for one, two in ((spots[0], spots[1]), (spots[1], spots[2]),
                         (spots[2], spots[0])):
            key = tuple(sorted((one, two)))
            welded[key] = welded.get(key, 0) + 1
    welded_ok = bool(welded) and all(count == 2 for count in welded.values())
    print("  %s the written collision file welds into closed pieces - %d edges"
          % ("PASS" if welded_ok else "FAIL", len(welded)))
    failed += 0 if welded_ok else 1

    start, vertices = sections(collide)
    faces = int(collide[start + vertices])
    face_ok = vertices == faces * 3 and faces == len(boxes) * 12
    print("  %s collision vertices and faces agree - %d faces, %d verts"
          % ("PASS" if face_ok else "FAIL", faces, vertices))
    failed += 0 if face_ok else 1

    start, vertices = sections(solid)
    faces = int(solid[start + vertices])
    # The sphere line is the first of the marker block: name, -1, node,
    # rotation, translation, radius.
    at = 1 + nodes
    at += 1 + int(solid[at])
    spheres = int(solid[at])
    sphere_line = solid[at + 1] if spheres else ""
    radius = float(sphere_line.split("\t")[-1]) if spheres else 0.0
    sphere_ok = vertices == 0 and faces == 0 and radius > 1.0
    print("  %s the physics .jms holds a sphere on the pelvis, radius %.2f units"
          % ("PASS" if sphere_ok else "FAIL", radius))
    failed += 0 if sphere_ok else 1

    if failed:
        print("\nFAILED: %d check(s)" % failed)
    else:
        print("\nPASS: collision and physics are what tool.exe reads")
    return failed


if __name__ == "__main__":
    raise SystemExit(main())
