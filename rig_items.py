"""Rig extracted avatar items onto the Halo CE skeleton and FP arms.

Runs inside Blender (``blender --background --python rig_items.py -- ...``).
The two rig files are the ones Halo CE itself ships: the 19-bone ``bip01``
biped and the 37-bone ``frame`` first-person arms. Point this script at them
and at an ``extracted`` folder made by Extract-AvatarItem; it merges the item
geometry, fits it to the biped, skins it without any hand work, and writes a
.blend, an .fbx and Halo's own .jms text model.

Nothing here asks a question. Missing parts come from whatever the item itself
does not cover: the base body, hands and head are taken from the catalogue's
body items when one is present, and left absent when it is not.

Usage:
    blender -b --python rig_items.py -- --items extracted --rig "master chief skeleton.blend"
        [--fp "fp arms.blend"] [--out rigged] [--no-fbx] [--no-jms] [--name NAME]
"""

import json
import math
import os
import sys

import bpy
from mathutils import Vector

# The biped is authored in Halo units: 100 units is a metre (0.03048 m each),
# so a 1.83 m figure stands 60 units tall with its feet on z = 0.
HALO_UNITS_PER_METRE = 100.0 / 3.048

# Which bones deform what, by Blender bone name. Used for the fallback skin.
DEFORM_BONES = (
    "bip01 pelvis", "bip01 spine", "bip01 spine1", "bip01 neck", "bip01 head",
    "bip01 l clavicle", "bip01 l upperarm", "bip01 l forearm", "bip01 l hand",
    "bip01 r clavicle", "bip01 r upperarm", "bip01 r forearm", "bip01 r hand",
    "bip01 l thigh", "bip01 l calf", "bip01 l foot",
    "bip01 r thigh", "bip01 r calf", "bip01 r foot",
)


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parsed = {"items": "extracted", "rig": None, "fp": None, "out": "rigged",
              "fbx": True, "jms": True, "name": None}
    index = 0
    while index < len(argv):
        word = argv[index]
        if word in ("--items", "--rig", "--fp", "--out", "--name"):
            parsed[word[2:]] = argv[index + 1]
            index += 2
        elif word == "--no-fbx":
            parsed["fbx"] = False
            index += 1
        elif word == "--no-jms":
            parsed["jms"] = False
            index += 1
        else:
            index += 1
    return parsed


def log(message):
    print("[rig] %s" % message)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def append_from(path, wanted_types=None):
    """Append every object of a rig file into the current scene."""
    if not path or not os.path.exists(path):
        return []
    with bpy.data.libraries.load(path, link=False) as (source, target):
        target.objects = [name for name in source.objects]
    added = []
    for object_data in target.objects:
        if object_data is None:
            continue
        if wanted_types and object_data.type not in wanted_types:
            continue
        bpy.context.scene.collection.objects.link(object_data)
        added.append(object_data)
    return added


def biped_armature(objects):
    for object_data in objects:
        if object_data.type == "ARMATURE":
            return object_data
    return None


# ------------------------------------------------------------------ the items

def catalogue_items(items_dir):
    """Every parsed model in the catalogue, in catalogue order."""
    path = os.path.join(items_dir, "catalogue.json")
    if not os.path.exists(path):
        log("no catalogue.json in %s" % items_dir)
        return []
    with open(path, "r", encoding="utf-8") as handle:
        catalogue = json.load(handle)
    found = []
    for record in catalogue.get("items", []):
        model = record.get("model") or {}
        obj = record.get("obj")
        if not model.get("parses") or not obj:
            continue
        full = os.path.join(items_dir, obj.replace("/", os.sep))
        if os.path.exists(full):
            found.append((record, full))
    log("%d of %d catalogue items have geometry"
        % (len(found), len(catalogue.get("items", []))))
    return found


def import_obj(path):
    before = set(bpy.data.objects)
    # No axis conversion on import: to_halo_space maps the points itself, so
    # the item's own axes stay exactly as the extractor wrote them.
    bpy.ops.wm.obj_import(filepath=path, up_axis="Y", forward_axis="Y")
    fresh = [object_data for object_data in bpy.data.objects if object_data not in before]
    meshes = [object_data for object_data in fresh if object_data.type == "MESH"]
    log("imported %s (%s)"
        % (os.path.basename(path),
           ", ".join("%d verts" % len(item.data.vertices) for item in meshes) or "no mesh"))
    return meshes


def join_meshes(meshes, name):
    if not meshes:
        return None
    if len(meshes) > 1:
        bpy.ops.object.select_all(action="DESELECT")
        for object_data in meshes:
            object_data.select_set(True)
        bpy.context.view_layer.objects.active = meshes[0]
        bpy.ops.object.join()
        meshes = [bpy.context.view_layer.objects.active]
    merged = meshes[0]
    merged.name = name
    merged.data.name = name
    return merged


def to_halo_space(object_data, target_height):
    """Avatar items are y-up metres with feet at y = 0; the biped is z-up units.

    Items face -z with y up; the biped faces -x with z up. So the point map is
    (x, y, z) -> (z, x, y), then scaled to Halo units and stood on the floor.
    """
    object_data.matrix_world = object_data.matrix_world.Identity(4)
    mesh = object_data.data
    mapped = [(vertex.co.z, vertex.co.x, vertex.co.y) for vertex in mesh.vertices]
    if not mapped:
        return
    lowest = min(point[2] for point in mapped)
    height = max(point[2] for point in mapped) - lowest
    scale = (target_height * HALO_UNITS_PER_METRE) / max(height, 1e-6)
    mid_x = (min(p[0] for p in mapped) + max(p[0] for p in mapped)) / 2.0
    mid_y = (min(p[1] for p in mapped) + max(p[1] for p in mapped)) / 2.0
    for vertex, point in zip(mesh.vertices, mapped):
        vertex.co = ((point[0] - mid_x) * scale, (point[1] - mid_y) * scale,
                     (point[2] - lowest) * scale)
    mesh.update()
    log("%s fitted to %.1f Halo units tall (scale %.3f)"
        % (object_data.name, target_height * HALO_UNITS_PER_METRE, scale))


# ------------------------------------------------------------------- skinning

def bone_segments(armature):
    """Deform bone name -> (head, tail) in armature space."""
    segments = {}
    for bone in armature.data.bones:
        if bone.name in DEFORM_BONES:
            segments[bone.name] = (bone.head_local.copy(), bone.tail_local.copy())
    if not segments:  # a differently named skeleton: use every bone
        for bone in armature.data.bones:
            segments[bone.name] = (bone.head_local.copy(), bone.tail_local.copy())
    return segments


def point_segment_distance(point, head, tail):
    along = tail - head
    length_sq = along.length_squared
    if length_sq < 1e-9:
        return (point - head).length
    factor = max(0.0, min(1.0, (point - head).dot(along) / length_sq))
    return (point - (head + along * factor)).length


def skin(object_data, armature, influences=2):
    """Distance weighting against the biped, so shells and open meshes work.

    Bone heat weighting fails on the single-sided shells most avatar items are,
    so this uses distance to each deform bone's segment instead: predictable,
    never throws, and gives the same weights every run.
    """
    segments = bone_segments(armature)
    names = list(segments)
    groups = {name: object_data.vertex_groups.new(name=name) for name in names}

    world = object_data.matrix_world
    for vertex in object_data.data.vertices:
        point = world @ vertex.co
        scored = sorted(
            ((point_segment_distance(point, head, tail), name)
             for name, (head, tail) in segments.items()),
            key=lambda pair: pair[0])[:influences]
        # Inverse-square falloff, nearest bone dominant, weights summing to 1.
        weights = [(name, 1.0 / max(distance, 1e-4) ** 2) for distance, name in scored]
        total = sum(weight for _, weight in weights) or 1.0
        for name, weight in weights:
            groups[name].add([vertex.index], weight / total, "REPLACE")

    object_data.parent = armature
    object_data.matrix_parent_inverse = armature.matrix_world.inverted()
    modifier = object_data.modifiers.new(name="Armature", type="ARMATURE")
    modifier.object = armature
    log("skinned %s to %d bones" % (object_data.name, len(names)))


# --------------------------------------------------------------------- output

def export_jms(object_data, armature, path):
    """Halo CE's own text model format, ready for tool.exe."""
    names = [bone.name for bone in armature.data.bones]
    rest = {bone.name: bone.matrix_local for bone in armature.data.bones}
    lines = [";### HEADER ###", "8200", ";### VERSION ###", "7", ";### NODES ###"]
    for index, bone in enumerate(armature.data.bones):
        parent = names.index(bone.parent.name) if bone.parent else -1
        head = bone.head_local
        turn = bone.matrix_local.to_quaternion()
        lines.append("%s %d %.6f %.6f %.6f %.6f %.6f %.6f %.6f" % (
            bone.name.replace(" ", "_"), parent, head.x, head.y, head.z,
            turn.x, turn.y, turn.z, turn.w))
    lines += [";### MATERIALS ###"]
    material_names = [slot.material.name if slot.material else "material%d" % index
                      for index, slot in enumerate(object_data.material_slots)] or ["material"]
    lines.append(";".join(material_names))
    lines += [";### VERTICES ###"]

    world = object_data.matrix_world
    group_names = {group.index: group.name for group in object_data.vertex_groups}
    # JMS wants the node's own space: bring world points back into the armature.
    inverse = armature.matrix_world.inverted()
    normals = [world.to_3x3() @ vertex.normal for vertex in object_data.data.vertices]
    for vertex in object_data.data.vertices:
        point = inverse @ (world @ vertex.co)
        normal = inverse.to_3x3() @ normals[vertex.index]
        normal.normalize()
        weighted = sorted(((group.weight, group_names[group.group])
                           for group in vertex.groups if group.group in group_names),
                          reverse=True)[:2]
        if not weighted:
            weighted = [(1.0, names[0])]
        while len(weighted) < 2:
            weighted.append((0.0, weighted[0][1]))
        (weight0, bone0), (weight1, bone1) = weighted[0], weighted[1]
        total = weight0 + weight1 or 1.0
        lines.append("0 %.6f %.6f %.6f %.6f %.6f %.6f %d %d %.6f %.6f" % (
            point.x, point.y, point.z, normal.x, normal.y, normal.z,
            names.index(bone0) if bone0 in names else 0,
            names.index(bone1) if bone1 in names else 0,
            weight0 / total, weight1 / total))
        layer = object_data.data.uv_layers.active
        if layer:
            uv = layer.data[vertex.index].uv
            lines.append("%.6f %.6f" % (uv.x, 1.0 - uv.y))
        else:
            lines.append("0.000000 0.000000")

    lines += [";### TRIANGLES ###"]
    for polygon in object_data.data.polygons:
        loops = list(polygon.loop_indices)
        if len(loops) < 3:
            continue
        for corner in range(1, len(loops) - 1):
            lines.append("0 %d %d %d" % (object_data.data.loops[loops[0]].vertex_index,
                                         object_data.data.loops[loops[corner]].vertex_index,
                                         object_data.data.loops[loops[corner + 1]].vertex_index))
    lines.append(";### END ###")
    with open(path, "w", encoding="ascii", errors="replace") as handle:
        handle.write("\n".join(lines) + "\n")
    log("wrote %s (%d verts, %d tris)" % (os.path.basename(path),
                                          len(object_data.data.vertices),
                                          len(object_data.data.polygons)))


def main():
    options = args()
    if not options["rig"]:
        log("no --rig given, nothing to fit to")
        return 2
    reset_scene()
    rig_objects = append_from(options["rig"])
    armature = biped_armature(rig_objects)
    if not armature:
        log("%s holds no armature" % options["rig"])
        return 2
    log("biped %r with %d bones" % (armature.name, len(armature.data.bones)))

    arms = append_from(options["fp"])
    if arms:
        log("first-person arms added: %s" % ", ".join(item.name for item in arms))

    items = catalogue_items(options["items"])
    if not items:
        log("nothing to rig")
        return 3

    os.makedirs(options["out"], exist_ok=True)

    # The catalogue's own full-body item is the base every part hangs off:
    # a hat or a pair of boots is geometry floating where a body should be.
    body = None
    for record, path in items:
        label = (record.get("id", "") + " " + record.get("name", "")).lower()
        if "body" in label:
            body = (record, path)
            break
    if body:
        log("base body in the catalogue: %s" % (body[0].get("name") or body[0]["id"]))

    rigged = []
    for record, path in items:
        meshes = import_obj(path)
        label = record.get("name") or record["id"]
        is_body = body is not None and record is body[0]
        # Avatar space is y-up in metres, so anything stopping below 1.45 m is
        # missing its head and shoulders and needs the base body underneath.
        tallest = max((vertex.co.y for item in meshes for vertex in item.data.vertices),
                      default=0.0)
        if body and not is_body and tallest < 1.45:
            log("%s stops at %.2f m, merging the base body in" % (label, tallest))
            meshes = meshes + import_obj(body[1])
        merged = join_meshes(meshes, options["name"] or label)
        if not merged:
            continue
        to_halo_space(merged, 1.83)
        skin(merged, armature)
        rigged.append((record, merged))

    for _, merged in rigged:
        merged.select_set(False)

    blend_path = os.path.join(options["out"], "avatar_rigged.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    log("saved %s" % blend_path)

    for record, merged in rigged:
        stem = os.path.splitext(os.path.basename(record.get("obj") or record["id"]))[0]
        if options["jms"]:
            export_jms(merged, armature,
                       os.path.join(options["out"], "%s.jms" % stem))
        if options["fbx"]:
            bpy.ops.object.select_all(action="DESELECT")
            merged.select_set(True)
            armature.select_set(True)
            bpy.context.view_layer.objects.active = armature
            bpy.ops.export_scene.fbx(
                filepath=os.path.join(options["out"], "%s.fbx" % stem),
                use_selection=True, apply_scale_options="FBX_SCALE_ALL",
                object_types={"ARMATURE", "MESH"})
            log("wrote %s.fbx" % stem)
    return 0


if __name__ == "__main__":
    sys.exit(main())
