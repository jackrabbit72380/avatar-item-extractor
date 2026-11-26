#!/usr/bin/env python3
"""Render a .jms so it can be LOOKED at instead of argued about.

Every claim this pipeline makes about a pose - arms down, feet on the floor,
plates on the body - is a claim about how the exported mesh looks. Measuring the
vertex band of an arm proves the band moved; it does not prove the model looks
like a person. This draws the file the game will draw, with a floor at z = 0 so
the soles are visible against it, and writes a PNG.

    blender -b --factory-startup --python tools/render_jms.py -- <model.jms> <out.png> [side]

``side`` is ``front`` (default), ``left`` or ``three-quarter``.
"""

import sys

import bpy
from mathutils import Vector

ARGUMENTS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if not ARGUMENTS:
    print("usage: render_jms.py -- <model.jms> <out.png> [front|left|three-quarter]")
    raise SystemExit(2)
MODEL = ARGUMENTS[0]
OUT = ARGUMENTS[1] if len(ARGUMENTS) > 1 else "/tmp/model.png"
SIDE = ARGUMENTS[2] if len(ARGUMENTS) > 2 else "front"


def read(path):
    """The parts of a Halo CE .jms this needs: vertices, faces, materials."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        lines = [line for line in handle.read().splitlines() if line.strip()]
    nodes = int(lines[0].split("\t")[2])
    position = 1 + nodes
    materials = int(lines[position])
    names = [lines[position + 1 + index].split("\t")[0]
             for index in range(materials)]
    position += 1 + materials
    markers = int(lines[position])
    position += 1 + markers
    regions = int(lines[position])
    position += 1 + regions
    vertices = int(lines[position])
    position += 1
    points, normals, uvs = [], [], []
    for number in range(vertices):
        row = lines[position + number].split("\t")
        points.append((float(row[1]), float(row[2]), float(row[3])))
        normals.append((float(row[4]), float(row[5]), float(row[6])))
        uvs.append((float(row[9]), float(row[10])))
    position += vertices
    faces = int(lines[position])
    position += 1
    triangles = []
    for number in range(faces):
        row = lines[position + number].split("\t")
        triangles.append((int(row[1]),
                          (int(row[2]), int(row[3]), int(row[4]))))
    return names, points, normals, uvs, triangles


def material(name, number):
    """A flat colour per material, so different parts are told apart."""
    palette = [(0.30, 0.34, 0.24), (0.62, 0.55, 0.45), (0.20, 0.20, 0.22),
               (0.85, 0.80, 0.72)]
    made = bpy.data.materials.new(name or ("material %d" % number))
    made.use_nodes = True
    basic = made.node_tree.nodes.get("Principled BSDF")
    if basic:
        basic.inputs["Base Color"].default_value = tuple(
            list(palette[number % len(palette)]) + [1.0])
        basic.inputs["Roughness"].default_value = 0.75
    return made


def main():
    names, points, normals, uvs, triangles = read(MODEL)
    mesh = bpy.data.meshes.new("model")
    mesh.from_pydata(points, [], [face for _, face in triangles])
    mesh.update()
    for number, name in enumerate(names):
        mesh.materials.append(material(name, number))
    # Halo culls a back face; the render draws both sides so a hole in the model
    # shows as nothing at all rather than as a false solid.
    mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
    for polygon, (material_index, _) in zip(mesh.polygons, triangles):
        polygon.material_index = material_index
    body = bpy.data.objects.new("model", mesh)
    bpy.context.scene.collection.objects.link(body)

    # A floor at exactly z = 0: the soles are either on it or they are not.
    bpy.ops.mesh.primitive_plane_add(size=400, location=(0, 0, 0))
    floor = bpy.context.active_object
    floor.data.materials.append(material("floor", 1))

    height = max(point[2] for point in points)
    middle = height / 2.0
    # A zoom pair lets a close-up be checked: fraction of the frame to fill, and
    # the height to centre on.
    zoom = float(ARGUMENTS[3]) if len(ARGUMENTS) > 3 else 1.35
    if len(ARGUMENTS) > 4:
        middle = float(ARGUMENTS[4])
    camera_data = bpy.data.cameras.new("camera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = height * zoom
    camera = bpy.data.objects.new("camera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    if SIDE == "left":
        camera.location = Vector((0.0, -260.0, middle))
    elif SIDE == "three-quarter":
        camera.location = Vector((190.0, -190.0, middle + 30.0))
    else:
        camera.location = Vector((260.0, 0.0, middle))
    target = Vector((0.0, 0.0, middle))
    direction = target - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera

    sun_data = bpy.data.lights.new("sun", type="SUN")
    sun_data.energy = 3.0
    sun = bpy.data.objects.new("sun", sun_data)
    sun.rotation_euler = (0.9, 0.2, 0.7)
    bpy.context.scene.collection.objects.link(sun)
    bpy.context.scene.world.use_nodes = True
    background = bpy.context.scene.world.node_tree.nodes.get("Background")
    if background:
        background.inputs[0].default_value = (0.35, 0.45, 0.65, 1.0)
        background.inputs[1].default_value = 1.2

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.render.resolution_x = 620
    scene.render.resolution_y = 900
    scene.render.filepath = OUT
    scene.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
    print("rendered %s from the %s (%d triangles, %d materials)"
          % (OUT, SIDE, len(triangles), len(names)))


main()
