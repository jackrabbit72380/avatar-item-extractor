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
import shutil
import sys

import bpy
from mathutils import Quaternion, Vector

# The .jms is positional and carries no section markers, so one wrong count shifts
# everything after it and the file still reads as text. It is checked as it is
# written, by the same reading tool.exe has to do, so a broken export is caught
# here instead of at compile time.
try:
    from jms_check import check_jms
except ImportError:  # run from somewhere that has not put this folder on the path
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from jms_check import check_jms

# The biped is authored in Halo units: 100 units is a metre (0.03048 m each),
# so a 1.83 m figure stands 60 units tall with its feet on z = 0.
HALO_UNITS_PER_METRE = 100.0 / 3.048

# The biped's arms. They are the seam the first-person set is cut on: Halo's
# in-game hands are their own model, and the fingers exist nowhere else.
# The arms proper: shoulder to hand. The clavicles are deliberately not here -
# a pauldron weighted to one is shoulder armour, and carrying it onto the arm
# would swing a plate off the shoulder the moment the arm moves.
ARM_BONES = (
    "bip01 l upperarm", "bip01 l forearm", "bip01 l hand",
    "bip01 r upperarm", "bip01 r forearm", "bip01 r hand",
)

# How much of a vertex has to belong to the arms before it is part of them. The
# body is skinned by distance, so every plate near a shoulder carries some arm
# weight; without a floor, one arm bone's 15% share dragged whole torso plates
# into the first-person set, where they hung scattered around the arm.
ARM_SHARE = 0.5

# Stamped into the log, report.txt and every READ ME block, so a file on disk
# can say which build made it instead of being guessed at from its contents.
VERSION = "v21"
BUILD = "2026-11-22 fp-arms-retarget"

# Which bones deform what, by Blender bone name. Used for the fallback skin.
DEFORM_BONES = (
    "bip01 pelvis", "bip01 spine", "bip01 spine1", "bip01 neck", "bip01 head",
    "bip01 l clavicle", "bip01 l upperarm", "bip01 l forearm", "bip01 l hand",
    "bip01 r clavicle", "bip01 r upperarm", "bip01 r forearm", "bip01 r hand",
    "bip01 l thigh", "bip01 l calf", "bip01 l foot",
    "bip01 r thigh", "bip01 r calf", "bip01 r foot",
)


# The NXE avatar skeleton, the 71 joints the 2008 editor's executable carries
# (its SKELETON_NXE table, decoded). Each entry is
# (parent, x, y, z, quaternion x, y, z, w): model space, y up, metres, in the
# bind pose - a T-pose whose arms run out along x. Feet sit at y = 0.0185.
NXE_JOINTS = (
    (255, 0.0000, 0.7552, -0.0087, 0.0000, 0.0000, 0.0000, 1.0000),  # 0
    (0, 0.0000, 0.7552, -0.0087, 0.0000, 0.0000, 0.0000, 1.0000),  # 1
    (0, 0.0901, 0.6479, 0.0000, 0.0000, 0.0000, 0.0000, 1.0000),  # 2
    (0, -0.0901, 0.6479, 0.0000, 0.0000, 0.0000, 0.0000, 1.0000),  # 3
    (0, 0.0000, 0.7858, -0.0087, 0.0000, 0.0000, 0.0000, 1.0000),  # 4
    (1, 0.0000, 0.8470, -0.0164, 0.0000, 0.0000, 0.0000, 1.0000),  # 5
    (2, 0.0901, 0.3792, -0.0130, 0.0000, 0.0000, 0.0000, 1.0000),  # 6
    (2, 0.0901, 0.5136, -0.0065, 0.0000, 0.0000, 0.0000, 1.0000),  # 7
    (3, -0.0901, 0.3792, -0.0130, 0.0000, 0.0000, 0.0000, 1.0000),  # 8
    (3, -0.0901, 0.5136, -0.0065, 0.0000, 0.0000, 0.0000, 1.0000),  # 9
    (1, 0.0000, 0.8164, -0.0138, 0.0000, 0.0000, 0.0000, 1.0000),  # 10
    (6, 0.0959, 0.1195, -0.0384, 0.0000, 0.0000, 0.0000, 1.0000),  # 11
    (5, 0.0074, 0.9694, -0.0021, 0.0000, 0.0000, 0.0000, 1.0000),  # 12
    (6, 0.0930, 0.2494, -0.0257, 0.0000, 0.0000, 0.0000, 1.0000),  # 13
    (5, 0.0000, 1.0208, -0.0352, 0.0000, 0.0000, 0.0000, 1.0000),  # 14
    (8, -0.0959, 0.1195, -0.0384, 0.0000, 0.0000, 0.0000, 1.0000),  # 15
    (5, -0.0074, 0.9694, -0.0021, 0.0000, 0.0000, 0.0000, 1.0000),  # 16
    (8, -0.0930, 0.2494, -0.0257, 0.0000, 0.0000, 0.0000, 1.0000),  # 17
    (5, 0.0000, 0.8904, -0.0211, 0.0000, 0.0000, 0.0000, 1.0000),  # 18
    (14, -0.0000, 1.1391, -0.0124, 0.0000, 0.0000, 0.0000, 1.0000),  # 19
    (12, 0.1250, 0.9695, -0.0300, 0.0000, 0.0000, 0.0000, 1.0000),  # 20
    (11, 0.1037, 0.0185, 0.0959, 0.0000, 0.0000, 0.0000, 1.0000),  # 21
    (16, -0.1250, 0.9695, -0.0300, 0.0000, 0.0000, 0.0000, 1.0000),  # 22
    (15, -0.1037, 0.0185, 0.0959, 0.0000, 0.0000, 0.0000, 1.0000),  # 23
    (14, -0.0000, 1.0602, -0.0276, 0.0000, 0.0000, 0.0000, 1.0000),  # 24
    (20, 0.2946, 0.9655, -0.0294, 0.0000, 0.0000, 0.0000, 1.0000),  # 25
    (20, 0.2098, 0.9675, -0.0297, 0.0000, 0.0000, 0.0000, 1.0000),  # 26
    (20, 0.1250, 0.9695, -0.0300, 0.0000, 0.0000, 0.0000, 1.0000),  # 27
    (22, -0.2946, 0.9655, -0.0294, 0.0000, 0.0000, 0.0000, 1.0000),  # 28
    (22, -0.2098, 0.9675, -0.0297, 0.0000, 0.0000, 0.0000, 1.0000),  # 29
    (22, -0.1250, 0.9695, -0.0300, 0.0000, 0.0000, 0.0000, 1.0000),  # 30
    (25, 0.3974, 0.9631, -0.0279, 0.0000, 0.0000, 0.0000, 1.0000),  # 31
    (25, 0.3717, 0.9637, -0.0283, 0.0000, 0.0000, 0.0000, 1.0000),  # 32
    (25, 0.4488, 0.9618, -0.0271, 0.0000, 0.0000, 0.0000, 1.0000),  # 33
    (28, -0.3974, 0.9631, -0.0279, 0.0000, 0.0000, 0.0000, 1.0000),  # 34
    (28, -0.3717, 0.9637, -0.0283, 0.0000, 0.0000, 0.0000, 1.0000),  # 35
    (28, -0.4488, 0.9618, -0.0271, 0.0000, 0.0000, 0.0000, 1.0000),  # 36
    (33, 0.5572, 0.9332, 0.0153, 0.0000, 0.0000, 0.0000, 1.0000),  # 37
    (33, 0.5590, 0.9343, -0.0159, 0.0000, 0.0000, 0.0000, 1.0000),  # 38
    (33, 0.5523, 0.9312, -0.0457, 0.0000, 0.0000, 0.0000, 1.0000),  # 39
    (33, 0.5391, 0.9268, -0.0737, 0.0000, 0.0000, 0.0000, 1.0000),  # 40
    (33, 0.5228, 0.7769, -0.0271, 0.0000, 0.0000, 0.0000, 1.0000),  # 41
    (33, 0.5598, 0.8508, -0.0271, 0.0000, 0.0000, 0.0000, 1.0000),  # 42
    (33, 0.4488, 0.9618, -0.0172, 0.0000, 0.0000, 0.0000, 1.0000),  # 43
    (36, -0.5572, 0.9332, 0.0153, 0.0000, 0.0000, 0.0000, 1.0000),  # 44
    (36, -0.5590, 0.9343, -0.0159, 0.0000, 0.0000, 0.0000, 1.0000),  # 45
    (36, -0.5523, 0.9312, -0.0457, 0.0000, 0.0000, 0.0000, 1.0000),  # 46
    (36, -0.5391, 0.9268, -0.0737, 0.0000, 0.0000, 0.0000, 1.0000),  # 47
    (36, -0.5228, 0.7769, -0.0271, 0.0000, 0.0000, 0.0000, 1.0000),  # 48
    (36, -0.5598, 0.8508, -0.0271, 0.0000, 0.0000, 0.0000, 1.0000),  # 49
    (36, -0.4488, 0.9618, -0.0172, 0.0000, 0.0000, 0.0000, 1.0000),  # 50
    (37, 0.6041, 0.9332, 0.0157, 0.0000, 0.0000, 0.0000, 1.0000),  # 51
    (38, 0.6087, 0.9343, -0.0160, 0.0000, 0.0000, 0.0000, 1.0000),  # 52
    (39, 0.6000, 0.9312, -0.0461, 0.0000, 0.0000, 0.0000, 1.0000),  # 53
    (40, 0.5794, 0.9268, -0.0741, 0.0000, 0.0000, 0.0000, 1.0000),  # 54
    (43, 0.5142, 0.9246, 0.0323, 0.0000, 0.0000, 0.0000, 1.0000),  # 55
    (44, -0.6041, 0.9332, 0.0157, 0.0000, 0.0000, 0.0000, 1.0000),  # 56
    (45, -0.6087, 0.9343, -0.0160, 0.0000, 0.0000, 0.0000, 1.0000),  # 57
    (46, -0.6000, 0.9312, -0.0461, 0.0000, 0.0000, 0.0000, 1.0000),  # 58
    (47, -0.5794, 0.9268, -0.0741, 0.0000, 0.0000, 0.0000, 1.0000),  # 59
    (50, -0.5142, 0.9246, 0.0323, 0.0000, 0.0000, 0.0000, 1.0000),  # 60
    (51, 0.6379, 0.9332, 0.0157, 0.0000, 0.0000, 0.0000, 1.0000),  # 61
    (52, 0.6439, 0.9343, -0.0160, 0.0000, 0.0000, 0.0000, 1.0000),  # 62
    (53, 0.6345, 0.9312, -0.0461, 0.0000, 0.0000, 0.0000, 1.0000),  # 63
    (54, 0.6090, 0.9268, -0.0741, 0.0000, 0.0000, 0.0000, 1.0000),  # 64
    (55, 0.5463, 0.9072, 0.0518, 0.0000, 0.0000, 0.0000, 1.0000),  # 65
    (56, -0.6379, 0.9332, 0.0157, 0.0000, 0.0000, 0.0000, 1.0000),  # 66
    (57, -0.6439, 0.9343, -0.0160, 0.0000, 0.0000, 0.0000, 1.0000),  # 67
    (58, -0.6345, 0.9312, -0.0461, 0.0000, 0.0000, 0.0000, 1.0000),  # 68
    (59, -0.6090, 0.9268, -0.0741, 0.0000, 0.0000, 0.0000, 1.0000),  # 69
    (60, -0.5463, 0.9072, 0.0518, 0.0000, 0.0000, 0.0000, 1.0000),  # 70
)


def nxe_armature(name="NXE skeleton"):
    """Build the 71-joint NXE skeleton, its soles on the avatar floor (y = 0)."""
    data = bpy.data.armatures.new(name)
    rig = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    sole = min(joint[2] for joint in NXE_JOINTS)
    bones = []
    for index, (parent, x, y, z, qx, qy, qz, qw) in enumerate(NXE_JOINTS):
        bone = data.edit_bones.new("nxe %02d" % index)
        bone.head = (x, y - sole, z)
        # Every bind rotation in this table is the identity, so the tail comes
        # from the first child that is not sitting on the joint.
        bone.tail = bone.head + (Quaternion((qw, qx, qy, qz))
                                 @ Vector((0.0, 0.04, 0.0)))
        bones.append(bone)
    for index, (parent, _x, _y, _z, _qx, _qy, _qz, _qw) in enumerate(NXE_JOINTS):
        if 0 <= parent < len(bones):
            bones[index].parent = bones[parent]
            bones[index].use_connect = False
    for index, entry in enumerate(NXE_JOINTS):
        head = bones[index].head
        children = [bones[child].head for child, other in enumerate(NXE_JOINTS)
                    if other[0] == index]
        if not children:
            continue
        farthest = max(children, key=lambda point: (point - head).length)
        if (farthest - head).length > 0.005:
            bones[index].tail = farthest
    bpy.ops.object.mode_set(mode="OBJECT")
    log("NXE skeleton: %d joints" % len(rig.data.bones))
    return rig


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


def prepare(object_data):
    """Make the item open correctly: smooth shading, images inside the file.

    The OBJ carries per-vertex normals and `s 1`, but an importer can still bring
    the faces in flat, and a faceted garment reads as a shading bug rather than
    as the item. Shading is therefore set here as well.

    The colour image is packed into the .blend for the same reason: an unpacked
    image is a broken link the moment the file is moved on its own, and the item
    then opens white with no colour at all.
    """
    mesh_data = object_data.data
    for polygon in mesh_data.polygons:
        polygon.use_smooth = True
    packed = 0
    for material in mesh_data.materials:
        if material is None or not getattr(material, "use_nodes", False):
            continue
        tree = getattr(material, "node_tree", None)
        if not tree:
            continue
        for node in tree.nodes:
            image = getattr(node, "image", None)
            if image is None or getattr(image, "packed_file", None):
                continue
            try:
                image.pack()
                packed += 1
            except (RuntimeError, AttributeError):
                pass
    log("prepared %s: smooth shading, %d image(s) packed"
        % (object_data.name, packed))


def apply_uv_sets(object_data, record):
    """Every UV set the item declares, as a named layer on the mesh.

    An OBJ carries one texture coordinate per corner, so the import brings in
    only the set the item binds its first texture slot to. The extractor writes
    the remaining sets into the catalogue, and they become real UV layers here -
    uv0, uv1, uv2 - so a map that belongs on a later set has somewhere to go.
    """
    layers = object_data.data.uv_layers
    if layers.active:
        layers.active.name = "uv0"
    added = 0
    for index, pairs in enumerate(record.get("uv_sets") or [], 1):
        layer = layers.new(name="uv%d" % index)
        data = layer.data
        for position, pair in enumerate(pairs):
            if position >= len(data):
                break
            data[position].uv = (pair[0], pair[1])
        added += 1
    if added:
        log("%s: %d UV set(s) added (%s)"
            % (object_data.name, added,
               ", ".join(layer.name for layer in layers)))


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


AUTHORED_BODY_HEIGHT = 1.4


def body_fit(armature, authored=AUTHORED_BODY_HEIGHT):
    """How much bigger the Halo biped is than the body the items are authored for.

    Items are modelled on a small avatar body - a beret at 1.40 m, a tee at 0.91 m
    - while the Halo biped is a 2.1 m Spartan. Left alone, the beret hangs at chest
    height and the tee wraps the thighs. One uniform factor per item, measured from
    the biped itself rather than typed in, lifts the whole item so its heights land
    on the same parts of the taller body. It is a fit, not a normalisation to a
    fixed height: the item keeps its own proportions.
    """
    if not armature or not armature.data.bones:
        return 1.0
    matrix = armature.matrix_world
    heights = []
    for bone in armature.data.bones:
        heights.extend([(matrix @ bone.head_local).z, (matrix @ bone.tail_local).z])
    # Floor to the top of the head. Measuring the bare span counts a foot bone
    # whose tail sits below the floor and reports a body 0.27 m taller than the
    # one the garments have to land on.
    metres = max(heights) / HALO_UNITS_PER_METRE
    if metres <= 0.0:
        return 1.0
    return metres / authored


def biped_landmarks(armature):
    """Head, shoulder and waist heights of the biped, in metres."""
    if not armature:
        return {}
    matrix = armature.matrix_world

    def height(*names):
        for name in names:
            bone = armature.data.bones.get(name)
            if bone:
                return (matrix @ bone.head_local).z / HALO_UNITS_PER_METRE
        return None

    return {
        "head": height("bip01 head"),
        "shoulder": height("bip01 l clavicle", "bip01 spine1"),
        "waist": height("bip01 pelvis", "bip01 spine"),
    }


def garment_anchor(object_data, armature, authored=AUTHORED_BODY_HEIGHT):
    """Which edge of a garment goes where, so it hangs off the body it is on.

    Body height alone puts a tee's top at the sternum and leaves its hem around
    the thighs, because the avatar's torso is proportionally longer than the
    Spartan's. What fixes a garment's fit is the edge it is supported by: a top
    hangs from its shoulder seam, so its top edge goes on the shoulders; anything
    worn lower hangs from its waistband, so that edge goes at the waist. A hat is
    left alone - it already lands on the head - and so is a full suit, which is
    the whole body and grows from the floor.

    Returns (edge, height in metres) or None to leave the item to the body fit.
    """
    ys = [vertex.co.y for vertex in object_data.data.vertices]
    if not ys:
        return None
    low, high = min(ys), max(ys)
    if high - low >= 0.8 * authored:
        return None  # the whole body: no single edge to hang it from
    marks = biped_landmarks(armature)
    shoulder, waist = marks.get("shoulder"), marks.get("waist")
    if shoulder is None or waist is None:
        return None
    # Which part of the body this is has to be judged in the avatar's own frame -
    # the metres the item was modelled in - because the biped is a different,
    # taller body and its waist sits above a tee's middle.
    avatar_head = max(joint[2] for joint in NXE_JOINTS)
    avatar_waist = NXE_JOINTS[0][2]
    middle = (low + high) / 2.0
    if middle >= avatar_head:
        return None  # a hat: the body fit already puts it on the head
    if middle >= avatar_waist:
        return ("high", shoulder, "top edge on the shoulders")
    return ("high", waist, "waistband at the waist")


def to_halo_space(object_data, fit=1.0, keep_position=False, anchor=None):
    """Avatar items are y-up metres; the biped is z-up Halo units.

    Items face -z with y up; the biped faces -x with z up. So the point map is
    (x, y, z) -> (z, x, y), and a metre is HALO_UNITS_PER_METRE units.

    The item is left exactly where the file puts it: an item is authored at the
    place it is worn, so a tee sits at torso height and a ring out where a hand
    is. Sliding an item onto the centre line used to erase that.

    ``fit`` grows the item for a taller body. Cloth grows from the floor, so its
    heights land on the same parts of the biped. A solid prop grows where it
    stands instead: its position belongs to the hand wearing it, and scaling its
    height about the ground would push it sideways, off the hand and onto an arm.
    """
    object_data.matrix_world = object_data.matrix_world.Identity(4)
    mesh = object_data.data
    points = [(vertex.co.z, vertex.co.x, vertex.co.y) for vertex in mesh.vertices]
    if not points:
        return
    scale = HALO_UNITS_PER_METRE * fit
    for vertex, point in zip(mesh.vertices, points):
        vertex.co = (point[0] * scale, point[1] * scale, point[2] * scale)
    if keep_position:
        shift = []
        for axis in range(3):
            middle = (max(point[axis] for point in points)
                      + min(point[axis] for point in points)) / 2.0
            shift.append(middle * HALO_UNITS_PER_METRE - middle * scale)
        for vertex in mesh.vertices:
            vertex.co = (vertex.co[0] + shift[0], vertex.co[1] + shift[1],
                         vertex.co[2] + shift[2])
    if anchor:
        # Put the edge the garment hangs from onto the body part that carries it.
        edge, height = anchor[0], anchor[1]
        heights = [vertex.co[2] for vertex in mesh.vertices]
        current = min(heights) if edge == "low" else max(heights)
        move = height * HALO_UNITS_PER_METRE - current
        for vertex in mesh.vertices:
            vertex.co = (vertex.co[0], vertex.co[1], vertex.co[2] + move)
        log("%s anchored: its %s edge onto %.2f m, moved %.1f units"
            % (object_data.name, "lower" if edge == "low" else "upper",
               height, move))
    mesh.update()
    placed = [vertex.co for vertex in mesh.vertices]
    lowest = min(point[2] for point in placed)
    tallest = max(point[2] for point in placed)
    log("%s in Halo units: %.1f tall, from %.1f to %.1f (scale %.3f, fit %.2f)"
        % (object_data.name, tallest - lowest, lowest, tallest, scale, fit))

# ------------------------------------------------------------------- skinning

def bone_segments(armature):
    """Deform bone name -> (head, tail) in world space.

    head_local is armature space, and an armature can sit under a transform - the
    NXE skeleton is built y-up while the imported item is displayed z-up, so the
    two only line up once the armature's own matrix is applied. Comparing world
    points to armature-space bones silently bound every NXE item to the joints
    nearest the floor.
    """
    matrix = armature.matrix_world
    segments = {}
    for bone in armature.data.bones:
        if bone.name in DEFORM_BONES:
            segments[bone.name] = (matrix @ bone.head_local,
                                   matrix @ bone.tail_local)
    if not segments:  # a differently named skeleton: use every bone
        for bone in armature.data.bones:
            segments[bone.name] = (matrix @ bone.head_local,
                                   matrix @ bone.tail_local)
    return segments


FP_BONES = {
    "bip01 l hand": "frame l wriste",
    "bip01 r hand": "frame r wriste",
    "bip01 l forearm": "frame l forearm",
    "bip01 r forearm": "frame r forearm",
    "bip01 l upperarm": "frame l upperarm",
    "bip01 r upperarm": "frame r upperarm",
}


def hand_bone(binding):
    """The biped bone an item rides, if the first-person arms carry it too.

    Halo's body and hands are separate models: the biped ends at a hand bone with
    no fingers, and the fingers exist only on the first-person arms. A ring on a
    finger therefore has to be bound to the arms, or it has nothing to ride.
    """
    for name in FP_BONES:
        if binding == name or binding.startswith(name + " "):
            return name
    return None


def place_on_arms(item, biped, arms, bone_name):
    """Move the item into the arms' space, onto the same joint.

    The arms are their own model with their own rest pose - a straight chain
    along x at the shoulder's height - while the biped's arm hangs down its side.
    The item crosses over on the one transform that maps the biped bone's frame
    onto the arms' matching bone, so it keeps its place on the hand and its
    orientation relative to it.
    """
    target = FP_BONES[bone_name]
    source = biped.matrix_world @ biped.data.bones[bone_name].matrix_local
    destination = arms.matrix_world @ arms.data.bones[target].matrix_local
    transform = destination @ source.inverted()
    for vertex in item.data.vertices:
        vertex.co = transform @ vertex.co
    item.data.update()
    log("moved %s to %s of the first-person arms (from %s)"
        % (item.name, target, bone_name))


def weights_summary(object_data, limit=4):
    """The bones a mesh actually rides, as a report line."""
    totals = {}
    for vertex in object_data.data.vertices:
        for entry in vertex.groups:
            name = object_data.vertex_groups[entry.group].name
            totals[name] = totals.get(name, 0.0) + entry.weight
    total = sum(totals.values())
    if not total:
        return "no bone weights"
    top = sorted(totals.items(), key=lambda pair: -pair[1])[:limit]
    return ", ".join("%s %.0f%%" % (name, weight * 100.0 / total)
                     for name, weight in top)


def arm_share(weights, names=ARM_BONES):
    """How much of one vertex belongs to the arms, 0 to 1."""
    arm = sum(weight for name, weight in weights.items() if name in names)
    total = sum(weights.values())
    return arm / total if total > 0.0 else 0.0


def bone_frame(armature, armature_fp, source, target):
    """The transform carrying one bone's rest frame onto the first-person bone
    of the same job: the same point on the bone, the same way round.

    The bone's rest matrix holds its direction *and* its roll, which is the only
    way round the question can be answered here: Halo's first-person arm chain
    is exactly collinear, so there is no bend in it to read a roll from.
    """
    was = armature.data.bones.get(source)
    now = armature_fp.data.bones.get(target)
    if was is None or now is None:
        return None
    return ((armature_fp.matrix_world @ now.matrix_local)
            @ (armature.matrix_world @ was.matrix_local).inverted())


def nearest_arm(point, armature, names):
    """The arm bone whose segment passes closest to a point, in world space."""
    best, best_gap = None, None
    for name in names:
        bone = armature.data.bones.get(name) if armature is not None else None
        if bone is None:
            continue
        gap = point_segment_distance(point,
                                     armature.matrix_world @ bone.head_local,
                                     armature.matrix_world @ bone.tail_local)
        if best_gap is None or gap < best_gap:
            best, best_gap = name, gap
    return best


def arm_frames(armature, armature_fp, names=ARM_BONES):
    """Item bone name -> its frame on Halo's first-person rig."""
    frames = {}
    for source in names:
        target = FP_BONES.get(source)
        if target is None:
            continue
        frame = bone_frame(armature, armature_fp, source, target)
        if frame is not None:
            frames[source] = frame
    return frames


def carry_point(frames, weights, point, home=None):
    """Move one point onto Halo's first-person arms, weighted as it is bound.

    Every bone the vertex rides pulls it into that bone's frame and the pulls are
    averaged by the weights, so the arm bends at the elbow where its skin does.
    Swinging the whole limb on one bone put it at the wrong angle; moving each
    vertex on only its heaviest bone tore the shells apart. Blending the bones
    the vertex actually rides does neither.

    Returns None when the vertex rides none of the bones with a frame.
    """
    pulled = None
    total = 0.0
    for name, weight in weights.items():
        frame = frames.get(name)
        if frame is None or weight <= 0.0:
            continue
        moved = frame @ point
        pulled = moved * weight if pulled is None else pulled + moved * weight
        total += weight
    if total <= 0.0:
        fallback = frames.get(home) if home else None
        return fallback @ point if fallback is not None else None
    return pulled / total


def shell_faces(mesh):
    """The model's own pieces: faces joined to each other through shared verts.

    An avatar mesh is a bag of separate shells - a sleeve, a bracer, a pauldron
    - so a shell is the smallest thing that can be taken or left whole.
    """
    parent = {}

    def find(index):
        root = index
        while parent.setdefault(root, root) != root:
            root = parent[root]
        while parent[index] != root:
            parent[index], index = root, parent[index]
        return root

    for polygon in mesh.polygons:
        first = find(polygon.vertices[0])
        for other in polygon.vertices[1:]:
            root = find(other)
            if root != first:
                parent[root] = first
    pieces = {}
    for polygon in mesh.polygons:
        pieces.setdefault(find(polygon.vertices[0]), []).append(polygon)
    return list(pieces.values())


def vertex_weights(object_data):
    """Every vertex's bone weights, by bone name."""
    names = {group.index: group.name for group in object_data.vertex_groups}
    weights = {}
    for vertex in object_data.data.vertices:
        per = {}
        for entry in vertex.groups:
            if entry.weight > 0.0:
                name = names[entry.group]
                per[name] = per.get(name, 0.0) + entry.weight
        weights[vertex.index] = per
    return weights


def arm_pieces(object_data, names=ARM_BONES, share=ARM_SHARE):
    """The item's shells that are arms, with the side and bone each rides.

    A piece joins the first-person set when most of its weight is on an upper
    arm, forearm or hand bone. It is decided per shell rather than per vertex
    because a vertex on either side of a seam would tear its piece in half;
    keeping shells whole also keeps torso plates out, since by their own
    weighting those are mostly on the spine.
    """
    weights = vertex_weights(object_data)
    pieces = []
    for faces in shell_faces(object_data.data):
        indices = {index for polygon in faces for index in polygon.vertices}
        total = sum(sum(weights[index].values()) for index in indices)
        if total <= 0.0:
            continue
        arm = sum(arm_share(weights[index], names) * sum(weights[index].values())
                  for index in indices)
        if arm / total < share:
            continue
        tally = {"l": 0.0, "r": 0.0}
        bones = {}
        for index in indices:
            for name, weight in weights[index].items():
                if name in names:
                    tally["l" if " l " in name else "r"] += weight
                    bones[name] = bones.get(name, 0.0) + weight
        pieces.append({"faces": faces, "indices": indices,
                       "side": "l" if tally["l"] >= tally["r"] else "r",
                       "bone": max(bones, key=bones.get) if bones else None})
    return pieces


def arm_region(object_data, armature=None, armature_fp=None, names=ARM_BONES):
    """The item's own arms, as a separate object, for Halo's first-person set.

    Halo's first-person view is a different model from the body: the biped ends
    at a hand with no fingers, and the arms the player sees holding a weapon are
    their own mesh on their own skeleton. The item already carries arm geometry
    - sleeves, gauntlets, or the base body's bare arms - so the second set is
    cut from that mesh by the bones it is already bound to rather than modelled
    again. Positions, faces, UVs, materials and weights all travel across, so
    the arms keep the item's colours and shading and can be exported or merged
    as they stand.

    The arms are carried onto Halo's own first-person rig, which holds them
    straight out in its rest pose: every vertex is moved by the bones it rides
    (upper arm, forearm, hand to the wrist), blended by its own weights, and its
    groups are renamed to that rig's bones. Nothing is re-modelled and nothing
    is re-skinned - the weights are the item's own, only the frames they act in
    change. A hand item never gets here - it rides its hand bone whole.

    Returns (arms object, armature it rides), or (None, None) when the item has
    no geometry on an arm bone - a hat is not an arm, and inventing one would
    only be a second wrong file.
    """
    mesh = object_data.data
    if not mesh.polygons:
        return None, None
    weights = vertex_weights(object_data)
    pieces = arm_pieces(object_data, names)
    if not pieces:
        log("%s: no shell is mostly on the arms, so there is no arm to cut"
            % object_data.name)
        return None, None

    # Halo's own first-person rig, in its own rest pose: the arms are carried
    # onto it bone by bone, so the file the arms ship in is the rig the game's
    # first-person animations drive.
    frames = {}
    if armature is not None and armature_fp is not None:
        frames = arm_frames(armature, armature_fp, names)
    mapping = {source: FP_BONES[source] for source in frames
               if armature_fp.data.bones.get(FP_BONES[source]) is not None}
    if not frames:
        log("no matching arm bones on the first-person rig: the cut keeps the "
            "biped's placement")

    home = {}
    for piece in pieces:
        for index in piece["indices"]:
            home[index] = piece["bone"]
    order = sorted(home)
    slot = {index: position for position, index in enumerate(order)}
    coords = []
    carried = {}
    moved_verts = 0
    moved_worst = 0.0
    for index in order:
        point = object_data.matrix_world @ mesh.vertices[index].co
        # The item's weights also put some of a sleeve on the body - a clavicle,
        # the spine. Carrying only the arm share and dividing by it made a vertex
        # with 5% hand and 95% spine fly all the way to the hand while its
        # neighbour stayed on the upper arm: a step, and a torn shell. That body
        # weight belongs to the arm nearest the vertex, so it moves with it.
        carried_weights = {name: weight for name, weight in weights[index].items()
                           if name in frames and weight > 0.0}
        held = sum(carried_weights.values())
        total = sum(weights[index].values())
        if armature is not None and total - held > 1e-9:
            near = nearest_arm(point, armature, list(frames))
            if near is not None:
                carried_weights[near] = (carried_weights.get(near, 0.0)
                                         + total - held)
        moved = carry_point(frames, carried_weights, point, home[index])
        if moved is None:
            coords.append((float(point[0]), float(point[1]), float(point[2])))
        else:
            coords.append((float(moved[0]), float(moved[1]), float(moved[2])))
            step = (moved - point).length
            if step > 1e-6:
                moved_verts += 1
                moved_worst = max(moved_worst, step)
        per = {}
        for name, weight in carried_weights.items():
            renamed = mapping.get(name, name)
            per[renamed] = per.get(renamed, 0.0) + weight
        if not per and home[index] is not None:
            # A shell is kept whole, so a vertex of it that was weighted to the
            # body rides the piece's own arm bone rather than being left with no
            # group at all.
            per = {mapping.get(home[index], home[index]): 1.0}
        total = sum(per.values())
        if total <= 0.0:
            continue
        for name, weight in per.items():
            carried.setdefault(name, []).append((slot[index], weight / total))

    faces = [polygon for piece in pieces for polygon in piece["faces"]]
    copy = bpy.data.meshes.new("%s arms" % mesh.name)
    copy.from_pydata(coords, [],
                     [tuple(slot[index] for index in polygon.vertices)
                      for polygon in faces])
    copy.update()
    for material in mesh.materials:
        copy.materials.append(material)
    for position, polygon in enumerate(faces):
        copy.polygons[position].material_index = polygon.material_index
        copy.polygons[position].use_smooth = polygon.use_smooth
    # from_pydata builds its loops in face order and each face's vertex order,
    # which is the same order the source polygons' loop_indices are in.
    old_loops = [index for polygon in faces for index in polygon.loop_indices]
    for layer in mesh.uv_layers:
        target = copy.uv_layers.new(name=layer.name)
        for position, loop_index in enumerate(old_loops):
            target.data[position].uv = layer.data[loop_index].uv
    arms = bpy.data.objects.new("%s arms" % object_data.name, copy)
    bpy.context.scene.collection.objects.link(arms)
    for name, pairs in carried.items():
        group = arms.vertex_groups.new(name=name)
        for position, weight in pairs:
            group.add([position], weight, "REPLACE")
    # Carried onto the first-person rig when the frames exist, so the object
    # rides Halo's own arms skeleton; otherwise it stays on the biped, which is
    # where its weights already put it.
    holder = armature_fp if mapping else armature
    if holder is not None:
        arms.parent = holder
        arms.matrix_parent_inverse = holder.matrix_world.inverted()
        modifier = arms.modifiers.new(name="Armature", type="ARMATURE")
        modifier.object = holder
    # Written onto the object as well as the log: the .blend then says what was
    # done to it, and a file that was made by an older build has nothing here.
    arms["carried_verts"] = moved_verts
    arms["carried_units"] = moved_worst
    arms["build"] = BUILD
    arms["version"] = VERSION
    arms["on_rig"] = bool(moved_verts)
    # A vertex carried by the wrong bone ends up off the arms entirely. Count
    # them, so a run says "12 vertices are 40 units away" instead of leaving it
    # to be spotted in Blender later.
    stray, stray_worst = 0, 0.0
    if armature_fp is not None and coords:
        bones = [(armature_fp.matrix_world @ bone.head_local,
                  armature_fp.matrix_world @ bone.tail_local)
                 for bone in armature_fp.data.bones]
        for point in coords:
            spot = Vector(point)
            gap = min(point_segment_distance(spot, head, tail) for head, tail in bones)
            if gap > 5.0:
                stray += 1
            stray_worst = max(stray_worst, gap)
        arms["stray_verts"] = stray
        arms["stray_worst"] = stray_worst
        if stray:
            log("%d vert(s) of %d sit more than 5 units off the rig (worst %.1f)"
                % (stray, len(coords), stray_worst))
    fit = arm_fit([Vector(point) for point in coords], armature_fp, arms)
    if fit is not None:
        arms["fit_mean"] = fit[0]
        arms["fit_worst"] = fit[1]
        log("fit to Halo's own arms: mean %.2f, worst %.2f units" % fit)
    if frames and not moved_verts:
        log("%s: every arm weight sits on a bone with no first-person frame, so "
            "nothing was carried - report.txt and the file's own note say so"
            % arms.name)
    log("cut %s: %d of %d vert(s), %d face(s) in %d shell(s), %s, on %s"
        % (arms.name, len(order), len(mesh.vertices), len(faces), len(pieces),
           ("carried on %d bone frame(s) onto Halo's fp rig, moved %d vert(s) up "
            "to %.2f units" % (len(frames), moved_verts, moved_worst))
           if frames else "kept in place",
           ", ".join(sorted(carried)) or "no bone (the rig has none of them)"))
    return arms, holder


def arms_for(merged, armature, armature_fp, bone_name, record):
    """Build the first-person set, never letting its failure reach the Halo set.

    The arm cut is the one step with no fallback worth failing the run over: it
    is a second set, and an item whose arms cannot be separated still has its
    body, its `.jms` and its textures. So this returns (None, None) instead of
    raising, and the pass carries on with the rest of the item.

    Otherwise it returns (the arms object, the armature the object rides).
    """
    arms = None
    try:
        if bone_name:
            # A hand item rides the one bone that carries it, whole.
            arms = merged.copy()
            arms.data = merged.data.copy()
            arms.name = "%s FP arms" % merged.name
            arms.data.name = arms.name
            bpy.context.scene.collection.objects.link(arms)
            place_on_arms(arms, armature, armature_fp, bone_name)
            record["arms_binding"] = skin(arms, armature_fp, rigid=True)
            return arms, armature_fp
        arms, rig = arm_region(merged, armature, armature_fp)
        if arms is not None:
            worst = meta(arms, "carried_units")
            if meta(arms, "stray_verts"):
                record["arms_stray"] = (
                    "%d of its vert(s) sit more than 5 units off the rig "
                    "(worst %.1f) - those are the misplaced ones"
                    % (meta(arms, "stray_verts"), meta(arms, "stray_worst")))
            if meta(arms, "fit_worst") is not None:
                record["arms_fit"] = ("stands in Halo's own arms to within "
                                      "%.2f units (mean %.2f)"
                                      % (meta(arms, "fit_worst"),
                                         meta(arms, "fit_mean")))
            if worst is None:
                record["arms_carried"] = "arms stayed where they were"
            elif not (meta(arms, "carried_verts") or 0):
                record["arms_carried"] = ("NOTHING CARRIED - these arms are not "
                                          "on Halo's rig, see the line above")
            else:
                record["arms_carried"] = (
                    "%d vert(s) carried onto Halo's fp bones, up to %.2f units"
                    % (meta(arms, "carried_verts") or 0, worst))
            # Already on its own bones and weighted by arm_region: a second,
            # distance-based bind here would re-guess weights that came across
            # exactly.
            record["arms_binding"] = weights_summary(arms)
        return arms, rig
    except Exception as problem:  # noqa: BLE001 - a bad cut must not end the pass
        log("could not build the first-person arms for %s (%s: %s)"
            % (merged.name, type(problem).__name__, problem))
        if arms is not None:
            try:
                bpy.data.objects.remove(arms, do_unlink=True)
            except Exception:
                pass
        record["arms_binding"] = ("failed - %s: %s"
                                  % (type(problem).__name__, problem))
        return None, None


def is_prop(object_data, limit=3.0):
    """A solid object rather than cloth, judged by its own size.

    A ring is about 1.3 Halo units across and a beret 7; nothing worn as cloth
    is anywhere near this small. Size is the only thing the file offers here, so
    it decides how the item is bound, not where it goes - that is still unknown.
    """
    mesh = object_data.data
    if not mesh.vertices:
        return False
    axes = ([vertex.co.x for vertex in mesh.vertices],
            [vertex.co.y for vertex in mesh.vertices],
            [vertex.co.z for vertex in mesh.vertices])
    longest = max(max(values) - min(values) for values in axes)
    return longest < limit


def point_segment_distance(point, head, tail):
    along = tail - head
    length_sq = along.length_squared
    if length_sq < 1e-9:
        return (point - head).length
    factor = max(0.0, min(1.0, (point - head).dot(along) / length_sq))
    return (point - (head + along * factor)).length


def skin(object_data, armature, influences=2, rigid=False):
    """Distance weighting against the biped, so shells and open meshes work.

    Bone heat weighting fails on the single-sided shells most avatar items are,
    so this uses distance to each deform bone's segment instead: predictable,
    never throws, and gives the same weights every run.

    ``rigid`` binds the whole object to one bone - the one nearest most of its
    vertices. A ring or a badge is a solid piece: spreading it over two bones only
    stretches it when they move apart, and giving each vertex its own nearest bone
    tears it in half down the middle.
    """
    segments = bone_segments(armature)
    names = list(segments)
    mesh = object_data.data
    world = object_data.matrix_world

    if rigid:
        votes = {}
        for vertex in mesh.vertices:
            point = world @ vertex.co
            nearest = min(names,
                          key=lambda name: point_segment_distance(point, *segments[name]))
            votes[nearest] = votes.get(nearest, 0) + 1
        chosen = max(votes, key=votes.get)
        object_data.vertex_groups.new(name=chosen).add(
            [vertex.index for vertex in mesh.vertices], 1.0, "REPLACE")
        tally = {chosen: float(len(mesh.vertices))}
    else:
        groups = {name: object_data.vertex_groups.new(name=name) for name in names}
        tally = {}
        for vertex in mesh.vertices:
            point = world @ vertex.co
            scored = sorted(
                ((point_segment_distance(point, head, tail), name)
                 for name, (head, tail) in segments.items()),
                key=lambda pair: pair[0])[:influences]
            # Inverse-square falloff, nearest bone dominant, weights summing to 1.
            weights = [(name, 1.0 / max(distance, 1e-4) ** 2)
                       for distance, name in scored]
            total = sum(weight for _, weight in weights) or 1.0
            for name, weight in weights:
                groups[name].add([vertex.index], weight / total, "REPLACE")
                tally[name] = tally.get(name, 0.0) + weight / total

    object_data.parent = armature
    object_data.matrix_parent_inverse = armature.matrix_world.inverted()
    modifier = object_data.modifiers.new(name="Armature", type="ARMATURE")
    modifier.object = armature
    total = sum(tally.values()) or 1.0
    top = sorted(tally.items(), key=lambda pair: -pair[1])[:3]
    bound = ", ".join("%s %.0f%%" % (name, weight * 100.0 / total)
                      for name, weight in top)
    if rigid:
        log("bound %s rigidly to %s" % (object_data.name, bound))
    else:
        log("skinned %s to %d bones (%s)" % (object_data.name, len(names), bound))
    return bound

# --------------------------------------------------------------------- output

def export_jms(object_data, armature, path):
    """Halo CE's text model format, laid out the way tool.exe reads it.

    Positional, with no section markers, matching HaloCE's own exporter
    (BlueStreak 1.0.4, "Adapted for HaloCE"):

        8200 <3251> <node_count>
        <name> <first_child> <next_sibling> <rx> <ry> <rz> <rw> <tx> <ty> <tz>
        <material_count>  then  <name> <none>  per material
        <marker_count>
        <region_count>   then  <name>  per region
        <vertex_count>
        <node0> <x> <y> <z> <nx> <ny> <nz> <node1> <weight> <u> <v> <w>
        <face_count>
        <region> <shader> <v0> <v1> <v2>

    Vertices are per triangle corner - three per face - because JMS does not
    share them: each corner carries its own normal and its own texture
    coordinate. That is also why the UV has a slot at all: it is the u, v pair
    plus a w of zero, which is everything a Halo CE gbxmodel vertex stores.
    """
    mesh_data = object_data.data
    bones = list(armature.data.bones)
    names = [bone.name.replace(" ", "_") for bone in bones]
    index_of = {name: index for index, name in enumerate(names)}

    children = {bone.name: [] for bone in bones}
    for bone in bones:
        if bone.parent:
            children[bone.parent.name].append(bone.name)
    first_child = {name: -1 for name in names}
    next_sibling = {name: -1 for name in names}
    for bone in bones:
        own = bone.name.replace(" ", "_")
        kids = [kid.replace(" ", "_") for kid in children[bone.name]]
        if kids:
            first_child[own] = index_of[kids[0]]
        for left, right in zip(kids, kids[1:]):
            next_sibling[left] = index_of[right]

    out = ["8200\t3251\t%d" % len(names)]
    for bone in bones:
        turn = bone.matrix_local.to_quaternion()
        head = bone.head_local
        own = bone.name.replace(" ", "_")
        out.append("%s\t%d\t%d\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f" % (
            own, first_child[own], next_sibling[own],
            turn.x, turn.y, turn.z, turn.w, head.x, head.y, head.z))

    materials = [slot.material.name if slot.material else "material%d" % index
                 for index, slot in enumerate(object_data.material_slots)] or ["material"]
    out.append("%d" % len(materials))
    for name in materials:
        out.append("%s\t<none>" % name.replace(" ", "_"))

    out.append("0")          # no markers
    out.append("1")          # one region
    out.append("unnamed")

    world = object_data.matrix_world
    inverse = armature.matrix_world.inverted()
    rotate = inverse.to_3x3()
    uv_layer = mesh_data.uv_layers.active
    group_names = {group.index: group.name for group in object_data.vertex_groups}

    corners = []
    for polygon in mesh_data.polygons:
        loops = list(polygon.loop_indices)
        for corner in range(1, len(loops) - 1):
            corners.append((loops[0], loops[corner], loops[corner + 1],
                            polygon.material_index))

    out.append("%d" % (len(corners) * 3))
    first = len(out)
    faces = []
    for triangle in corners:
        face = []
        for loop_index in triangle[:3]:
            vertex = mesh_data.vertices[mesh_data.loops[loop_index].vertex_index]
            # The node's own space: Halo wants the model in the skeleton's frame.
            point = inverse @ (world @ vertex.co)
            normal = rotate @ (world.to_3x3() @ vertex.normal)
            normal.normalize()
            weighted = sorted(((group.weight, group_names[group.group])
                               for group in vertex.groups
                               if group.group in group_names), reverse=True)[:2]
            if not weighted:
                weighted = [(1.0, names[0])]
            node0 = index_of.get(weighted[0][1].replace(" ", "_"), 0)
            node1 = -1
            weight1 = 0.0
            if len(weighted) > 1:
                node1 = index_of.get(weighted[1][1].replace(" ", "_"), -1)
                total = weighted[0][0] + weighted[1][0] or 1.0
                weight1 = weighted[1][0] / total
            if uv_layer:
                uv = uv_layer.data[loop_index].uv
                u, v = uv.x, uv.y
            else:
                u, v = 0.0, 0.0
            out.append("%d\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\t%d\t%.6f\t%.6f\t%.6f\t0.000000"
                       % (node0, point.x, point.y, point.z,
                          normal.x, normal.y, normal.z, node1, weight1, u, v))
            face.append(len(out) - 1 - first)
        faces.append((triangle[3], face))

    out.append("%d" % len(faces))
    for material, face in faces:
        # region 0 (the only region), then the shader this face uses
        out.append("0\t%d\t%d\t%d\t%d"
                   % (material, face[0], face[1], face[2]))

    with open(path, "w", encoding="ascii", errors="replace", newline="") as handle:
        handle.write("\n".join(out) + "\n")
    log("wrote %s (%d verts, %d tris)" % (os.path.basename(path),
                                          len(corners) * 3, len(faces)))
    errors, notes, stats = check_jms(path)
    if errors:
        log("jms check: %d problem(s) in %s"
            % (len(errors), os.path.basename(path)))
        for problem in errors[:5]:
            log("   %s" % problem)
    else:
        log("jms check: ok - %d nodes, %d faces, %d verts, %d with two weights"
            % (stats.get("nodes", 0), stats.get("faces", 0),
               stats.get("vertices", 0), stats.get("two_weight_vertices", 0)))
    for note in notes[:3]:
        log("   note: %s" % note)
    return errors


def save_blend(path, objects, note=None):
    """A .blend you can open: the scene, holding only these objects.

    bpy.data.libraries.write() writes a datablock library rather than a scene,
    so the file opens empty and looks broken. Save the scene itself instead,
    with everything else unlinked for the moment and put back afterwards.
    copy=True leaves the running session's own file alone.
    """
    scene = bpy.context.scene
    # The rigs name textures that are not shipped with them, so those images are
    # broken links: they load as 0x0 and would sit in the saved file as red
    # "missing texture" slots on the item. Nothing is lost by dropping them -
    # they could never have rendered - and the item's own images are packed, so
    # they are kept.
    for image in list(bpy.data.images):
        if image.packed_file or image.size[0] or image.size[1]:
            continue
        try:
            bpy.data.images.remove(image)
        except RuntimeError:
            pass
    for material in list(bpy.data.materials):
        if material.users:
            continue
        try:
            bpy.data.materials.remove(material)
        except RuntimeError:
            pass
    # A note datablock, so the file says what it is and what it is for when it
    # is opened on its own, long after the folder around it is gone.
    text = None
    if note:
        text = bpy.data.texts.new(note[0])
        text.write(note[1])
        # Nothing references a text block, and Blender drops datablocks with no
        # users when the file is saved and reopened. The fake user is what keeps
        # the note inside the file.
        text.use_fake_user = True
    keep = set(objects)
    aside = [item for item in list(scene.collection.objects) if item not in keep]
    for item in aside:
        scene.collection.objects.unlink(item)
    try:
        bpy.ops.wm.save_as_mainfile(filepath=path, copy=True)
    finally:
        for item in aside:
            scene.collection.objects.link(item)
        if text is not None:
            bpy.data.texts.remove(text)
    log("wrote %s" % os.path.basename(path))


def export_objects(path, objects, kind):
    """Write just these objects, with no armature."""
    bpy.ops.object.select_all(action="DESELECT")
    for item in objects:
        item.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if kind == "fbx":
        bpy.ops.export_scene.fbx(filepath=path, use_selection=True,
                                 apply_scale_options="FBX_SCALE_ALL",
                                 object_types={"MESH"})
    elif kind == "glb":
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB",
                                  use_selection=True)
    else:
        save_blend(path, objects)
        return
    log("wrote %s" % os.path.basename(path))


def export_rig(path, armature, kind):
    """Write the rig on its own, for someone re-binding an item by hand."""
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    if kind == "fbx":
        bpy.ops.export_scene.fbx(filepath=path, use_selection=True,
                                 apply_scale_options="FBX_SCALE_ALL",
                                 object_types={"ARMATURE"})
    log("wrote %s" % os.path.basename(path))


def export_rigged(path, mesh, armature, kind, note=None):
    """Write a mesh together with the armature it is skinned to."""
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    if kind == "fbx":
        bpy.ops.export_scene.fbx(filepath=path, use_selection=True,
                                 apply_scale_options="FBX_SCALE_ALL",
                                 object_types={"ARMATURE", "MESH"})
    elif kind == "glb":
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB",
                                  use_selection=True)
    else:
        save_blend(path, [mesh, armature], note)
        return
    log("wrote %s" % os.path.basename(path))


def reference_arms(armature_fp, skip):
    """Halo's own first-person arm mesh, when the rig file brought one along."""
    found = []
    for item in getattr(bpy.data, "objects", []) or []:
        if item is skip or getattr(item, "type", None) != "MESH":
            continue
        if item.parent is armature_fp or "cyborg" in item.name.lower():
            found.append(item)
    return found


def arm_fit(points, armature_fp, skip, sample=400):
    """How close the carried arms are to Halo's own, as (mean, worst) units.

    The rig file ships the arms the game actually uses, so they are the target
    the item's arms have to stand in - not just the bones, which the item's
    thicker or longer limbs can sit around and still be in the wrong place.
    """
    reference = reference_arms(armature_fp, skip)
    if not reference or not points:
        return None
    cloud = []
    for item in reference:
        verts = list(item.data.vertices)
        step = max(1, len(verts) // 600)
        cloud.extend(item.matrix_world @ vert.co for vert in verts[::step])
    if not cloud:
        return None
    step = max(1, len(points) // sample)
    gaps = [min((point - other).length for other in cloud) for point in points[::step]]
    return sum(gaps) / len(gaps), max(gaps)


def meta(object_data, key, default=None):
    """A custom property off an object, tolerating anything that has none."""
    try:
        return object_data.get(key, default)
    except AttributeError:
        return default


def halo_note(stem, mesh, armature, arms=False):
    """The text block saved inside a Halo .blend, so the file says what it is.

    Copied out of the folder - mailed, dropped into another project - a .blend
    carries nothing that names the game its rig belongs to, or what to do with
    it next. The note travels with the file instead of living in a README beside
    it, and it is a datablock, not a file on disk.
    """
    if arms:
        title = "Halo CE first-person arms - %s" % stem
        what = ("the item's arms on Halo's first-person arms skeleton. Halo's "
                "in-game hands are a separate model from the body, so this is "
                "the set a player sees holding a weapon.")
    else:
        title = "Halo CE - %s" % stem
        what = ("the item on Halo CE's 19-bone biped, ready to export or to "
                "merge with other items.")
    lines = [
        title,
        "",
        "this file : " + what,
        "rig       : %s, %d bones, Halo units (100 units = 1 metre)"
        % ((armature.name, len(armature.data.bones)) if armature else ("none", 0)),
        "mesh      : %s, %d vert(s), %d material(s)"
        % (mesh.name, len(mesh.data.vertices), len(mesh.data.materials)),
        "textures  : packed into this file, so it opens with its colours",
        "export    : BlueStreak 1.0.4 .jms exporter on the mesh",
        "merge     : append another item's - halo.blend and join the meshes;",
        "            every item is skinned to the same biped",
        "version   : %s" % VERSION,
        "build     : %s" % BUILD,
    ]
    if arms:
        worst = meta(mesh, "carried_units")
        moved = meta(mesh, "carried_verts") or 0
        if worst is not None and moved:
            lines.insert(4, "carried   : %d vert(s) moved onto Halo's frame "
                            "bones, up to %.2f units" % (moved, worst))
        elif worst is not None:
            lines.insert(4, "carried   : NOTHING MOVED - this mesh is not on "
                            "Halo's rig, so the arms are still in the pose the "
                            "item was modelled in")
    return ("READ ME - %s.txt" % ("fp arms" if arms else "halo"),
            "\n".join(lines) + "\n")


def roots_of(rig):
    return [bone.name for bone in rig.data.bones if bone.parent is None]


def rig_scene_lines(armature, nxe=None):
    """The Blender scene and the rigs, as a short section of report.txt.

    These used to be scene.json and skeleton.json, two JSON dumps in every item
    folder that nothing read back. What is worth keeping when a rig comes out
    wrong is short: which Blender, at what scale, which meshes arrived with how
    many vertices and materials, and where each rig's bones start. All of that
    fits in a few lines beside the item it describes.
    """
    lines = ["", "scene", ""]
    version = getattr(bpy.app, "version_string", "unknown")
    units = getattr(getattr(bpy.context.scene, "unit_settings", None),
                    "scale_length", 1.0)
    lines.append("  blender      : %s, unit scale %g" % (version, units))
    meshes = 0
    for item in getattr(bpy.data, "objects", []):
        if getattr(item, "type", None) != "MESH":
            continue
        meshes += 1
        where = list(getattr(item, "location", []) or [])
        moved = ""
        if len(where) == 3 and any(abs(value) > 1e-6 for value in where):
            moved = ", at (%.3f, %.3f, %.3f)" % (where[0], where[1], where[2])
        lines.append("  mesh         : %s, %d vert(s), %d material(s)%s"
                     % (item.name, len(item.data.vertices),
                        len(item.data.materials), moved))
    lines.append("  meshes       : %d" % meshes)
    # The counts are already in the header; what the JSON dumps added on top of
    # them is where each rig starts, which is what a misplaced item looks like.
    for label, rig in (("armature", armature), ("NXE skeleton", nxe)):
        if not rig:
            continue
        roots = roots_of(rig)
        lines.append("  %-13s: root(s) %s" % (label, ", ".join(roots) or "none"))
        if roots:
            root = next((bone for bone in rig.data.bones
                         if bone.name == roots[0]), None)
            head = getattr(root, "head_local", None) if root else None
            if head is not None:
                lines.append("  %-13s  root at (%.3f, %.3f, %.3f)"
                             % ("", head[0], head[1], head[2]))
    return lines


def report_text(options, records, stems, armature, nxe=None):
    lines = ["Avatar item rig report", ""]
    lines.append("rig file      : %s" % os.path.basename(options["rig"] or ""))
    lines.append("version       : %s" % VERSION)
    lines.append("build         : %s" % BUILD)
    lines.append("arms file     : %s" % os.path.basename(options["fp"] or "(none)"))
    if armature:
        lines.append("armature      : %s (%d bones) from %s"
                     % (armature.name, len(armature.data.bones),
                        os.path.basename(options["rig"] or "")))
    elif options["rig"]:
        # The file was there but had no armature in it, which is the difference
        # between a missing rig and a rig that would not load - saying which is
        # the whole reason this line exists.
        lines.append("armature      : NOT loaded - %s holds no armature"
                     % os.path.basename(options["rig"]))
    else:
        lines.append("armature      : none - no rig file was given, NXE rig only")
    if nxe:
        lines.append("NXE skeleton  : %s (%d joints)"
                     % (nxe.name, len(nxe.data.bones)))
    lines.append("items         : %d" % len(stems))
    lines.append("")
    for record, stem in zip(records, stems):
        lines.append(stem)
        lines.append("  id        : %s" % record.get("id", ""))
        lines.append("  title     : %s" % (record.get("title") or ""))
        table = record.get("colour_table") or {}
        lines.append("  colours   : table %s, %d swatch(es)"
                     % ("yes" if table.get("present") else "no",
                        table.get("swatches") or 0))
        # Which bone it rides, because an item file never says where it is worn.
        if record.get("jms_errors") is not None:
            count = len(record["jms_errors"]) + len(record.get("jms_arms_errors") or [])
            lines.append("  jms check : %s" % ("ok" if not count else
                                               "%d problem(s)" % count))
        lines.append("  placement : %s" % (record.get("placement") or "as authored"))
        lines.append("  nxe rig   : %s" % (record.get("nxe_binding") or "not skinned"))
        lines.append("  bound to  : %s" % (record.get("binding") or "not skinned"))
        if record.get("halo_file"):
            lines.append("  halo file : %s" % record["halo_file"])
        if record.get("arms_file"):
            lines.append("  fp arms   : %s" % record["arms_file"])
            lines.append("              %s" % (record.get("arms_binding")
                                               or "not skinned"))
            if record.get("arms_carried"):
                lines.append("              %s" % record["arms_carried"])
            if record.get("arms_fit"):
                lines.append("              %s" % record["arms_fit"])
            if record.get("arms_stray"):
                lines.append("              %s" % record["arms_stray"])
        lines.append("  vertices  : %d" % (record.get("model", {}).get("vertices") or 0))
        lines.append("")
    lines.extend(rig_scene_lines(armature, nxe))
    return "\n".join(lines)


MAX_DIR = "extracted for max users"
BLENDER_DIR = "extracted for blender users"
HEK_DIR = "extracted for hek users"


def mirror_fbx(out, blend_dir, stems):
    r"""Copy every rigged .fbx into max\, where a Max user will look for it.

    3ds Max opens .fbx as well as .obj, and cannot open a .blend at all, so a
    Max user should not have to reach into blender\ for the rigged model. The
    .blend and .glb stay Blender's own: they are formats Blender writes for
    itself, not formats Max reads.
    """
    models_dir = os.path.join(out, MAX_DIR)
    os.makedirs(models_dir, exist_ok=True)
    copied = 0
    for stem in sorted(set(stems)):
        for suffix in (" - halo", " - halo fp arms", " - NXE", " - unrigged"):
            name = "%s%s.fbx" % (stem, suffix)
            source = os.path.join(blend_dir, name)
            if os.path.exists(source):
                shutil.copyfile(source, os.path.join(models_dir, name))
                copied += 1
    return copied


def mirror_jms(out, stems):
    r"""Copy each Halo text model into the xbox folder as well.

    tool.exe compiles the same .jms for either target - which one it builds is a
    flag to the compiler, not a difference in the file - so an xbox user should
    not have to reach into pc\ for the model when that target's bitmaps are
    already sitting in its own data\<item>\bitmaps\.
    """
    hek = os.path.join(out, HEK_DIR)
    copied = 0
    for stem in sorted(set(stems)):
        source_dir = os.path.join(hek, "pc", "data", stem, "models")
        target_dir = os.path.join(hek, "xbox", "data", stem, "models")
        os.makedirs(target_dir, exist_ok=True)
        for suffix in ("", " - fp arms"):
            name = "%s%s.jms" % (stem, suffix)
            source = os.path.join(source_dir, name)
            if os.path.exists(source):
                shutil.copyfile(source, os.path.join(target_dir, name))
                copied += 1
    return copied


def ship_source_rigs(out, options, armature):
    """Halo's own rig files, kept beside the items for repair.

    They are the base every item is skinned to, so they are not the item's file
    and they do not sit beside it: they go in their own "source rigs" folder,
    named as they came. Someone re-binding an item by hand, or checking a shape
    that came out wrong, then has the exact skeleton the pass used - and Max
    gets the biped as .fbx, because it cannot open a .blend at all.
    """
    folder = os.path.join(out, BLENDER_DIR, "source rigs")
    os.makedirs(folder, exist_ok=True)
    shipped = []
    for source in (options.get("rig"), options.get("fp")):
        if not source or not os.path.exists(source):
            continue
        name = os.path.basename(source)
        shutil.copyfile(source, os.path.join(folder, name))
        shipped.append(name)
    if armature and options.get("rig"):
        fbx = os.path.splitext(os.path.basename(options["rig"]))[0] + ".fbx"
        os.makedirs(os.path.join(out, MAX_DIR), exist_ok=True)
        export_rig(os.path.join(out, MAX_DIR, fbx), armature, "fbx")
        shipped.append(fbx)
    return shipped


def main():
    options = args()
    log("%s - build %s" % (VERSION, BUILD))
    reset_scene()
    # Halo's two rig files are optional: without them the item still gets its
    # NXE rig, which needs nothing but the skeleton carried in this script.
    armature = None
    armature_fp = None
    if options["rig"]:
        armature = biped_armature(append_from(options["rig"]))
        if not armature:
            log("%s holds no armature" % options["rig"])
        else:
            # Both rig files call their armature "Armature"; opened together
            # one becomes "Armature.001" and the item's notes stop saying
            # which skeleton the file is on.
            armature.name = "halo biped"
    else:
        log("no --rig given: writing the NXE rigs only")
    fit = 1.0
    if armature:
        log("biped %r with %d bones" % (armature.name, len(armature.data.bones)))
        fit = body_fit(armature)
        log("Halo fit x%.3f: the biped is %.2f m against the %.2f m body the items "
            "are authored for" % (fit, fit * AUTHORED_BODY_HEIGHT, AUTHORED_BODY_HEIGHT))
        arms = append_from(options["fp"])
        if arms:
            log("first-person arms added: %s" % ", ".join(item.name for item in arms))
            # The arms model is the only one with fingers, so hand items are
            # bound to it as well as to the biped.
            for object_data in arms:
                if object_data.type == "ARMATURE":
                    armature_fp = object_data
            if armature_fp:
                armature_fp.name = "fp arms (Halo's own)"
                log("first-person arms rig: %r with %d bones"
                    % (armature_fp.name, len(armature_fp.data.bones)))

    items = catalogue_items(options["items"])
    if not items:
        log("nothing to rig")
        return 3

    os.makedirs(options["out"], exist_ok=True)

    # The rig the item actually ships against: the NXE avatar skeleton. It is
    # built once, in avatar space, and every item's NXE copy is bound to it.
    nxe_rig = nxe_armature()

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
        prepare(merged)
        apply_uv_sets(merged, record)
        # The NXE copy stays in the item's own space - y-up metres, as the
        # package stores it - and is skinned to the NXE skeleton in that space,
        # so the NXE files carry the game's own rig and not a floating mesh.
        nxe = merged.copy()
        nxe.data = merged.data.copy()
        nxe.name = "%s NXE" % merged.name
        nxe.data.name = nxe.name
        bpy.context.scene.collection.objects.link(nxe)
        # The NXE copy is still in the item's own metres, so the size limit
        # has to be a metre limit too - 3 Halo units, not 3 metres.
        # The avatar skeleton is authored y-up; the imported item is displayed
        # z-up, so the skeleton is set to the item's transform and both stand
        # the same way. Without this the binding compares two different spaces.
        nxe_rig.matrix_world = nxe.matrix_world
        record["nxe_binding"] = skin(
            nxe, nxe_rig, rigid=is_prop(nxe, 3.0 / HALO_UNITS_PER_METRE))
        arms_item = None
        arms_rig = None
        if armature:
            prop = is_prop(merged, 3.0 / HALO_UNITS_PER_METRE)
            anchor = None if prop else garment_anchor(merged, armature)
            if prop:
                record["placement"] = "kept where the file puts it, grown in place"
            elif anchor:
                record["placement"] = anchor[2]
            else:
                record["placement"] = "body height, grown from the floor"
            to_halo_space(merged, fit, keep_position=prop, anchor=anchor)
            record["binding"] = skin(merged, armature, rigid=prop)
            bone_name = hand_bone(record.get("binding") or "")
            if armature_fp:
                arms_item, arms_rig = arms_for(merged, armature, armature_fp,
                                               bone_name, record)
            if arms_item is None and armature_fp:
                # Nothing on an arm bone (a hat, a badge). The second set still
                # exists so every item has the pair tool.exe users expect, and
                # it says why it is empty rather than looking like a bad run.
                empty = bpy.data.meshes.new("%s arms" % merged.name)
                arms_item = bpy.data.objects.new("%s arms" % merged.name, empty)
                bpy.context.scene.collection.objects.link(arms_item)
                arms_item.parent = armature_fp
                arms_rig = armature_fp
                if not (record.get("arms_binding") or "").startswith("failed"):
                    record["arms_binding"] = "none - this item has no arm geometry"
                    log("%s has no arm geometry: the fp arms set holds the rig only"
                        % merged.name)
                else:
                    log("%s: the fp arms set holds the rig only, because the cut "
                        "failed" % merged.name)
        rigged.append((record, merged, nxe, arms_item, arms_rig))

    for _, merged, _nxe, _arms, _rig in rigged:
        merged.select_set(False)

    out = options["out"]
    # The rigs go where the program that opens them looks, not beside the
    # .obj: a Blender user opens blender\ and finds the .blend already on the
    # item. The .jms is Halo's own model source, so it goes with the bitmaps
    # tool.exe compiles.
    blend_dir = os.path.join(out, BLENDER_DIR)
    hek_data = os.path.join(out, HEK_DIR, "pc", "data")
    os.makedirs(blend_dir, exist_ok=True)
    os.makedirs(hek_data, exist_ok=True)
    stems = []
    for record, merged, nxe, arms_item, arms_rig in rigged:
        stem = os.path.splitext(os.path.basename(record.get("obj") or record["id"]))[0]
        stems.append(stem)
        # data\<item>\ is what tool.exe takes as its source directory, and it
        # looks inside models\ for the .jms and animations\ for animation data.
        models_dir = os.path.join(hek_data, stem, "models")
        os.makedirs(models_dir, exist_ok=True)
        os.makedirs(os.path.join(hek_data, stem, "animations"), exist_ok=True)
        # Halo rig: the item on the biped, arms loaded, as a .blend that opens
        # straight onto it so it can simply be exported from there. The .jms is
        # Halo's own text model, and the .fbx is the same thing for anything
        # that cannot read a .blend.
        if armature:
            if options["jms"]:
                record["jms_errors"] = export_jms(
                    merged, armature, os.path.join(models_dir, "%s.jms" % stem))
            # The file is named for the game it is for, not for the program that
            # wrote it: "- halo" is the answer to "which of these do I open?"
            # when the folder also holds the NXE and unrigged copies.
            record["halo_file"] = "%s - halo.blend" % stem
            export_rigged(os.path.join(blend_dir, record["halo_file"]),
                          merged, armature, "blend",
                          halo_note(stem, merged, armature, False))
            export_rigged(os.path.join(blend_dir, "%s - halo.fbx" % stem),
                          merged, armature, "fbx")
        # First-person arms: Halo's in-game hands are a separate model, so every
        # item gets its own second set on that rig - the fingers exist nowhere
        # else, and the player sees these arms and not the body's.
        if arms_item is not None:
            # The second set is written separately, so a problem in it - a mesh
            # Blender will not export, a failed cut - cannot cost the item its
            # Halo body, its .jms or the rest of the run.
            if arms_rig is None:
                arms_rig = armature_fp
            try:
                if options["jms"] and arms_item.data.vertices:
                    record["jms_arms_errors"] = export_jms(
                        arms_item, arms_rig,
                        os.path.join(models_dir, "%s - fp arms.jms" % stem))
                record["arms_file"] = "%s - halo fp arms.blend" % stem
                # The arms are carried onto Halo's own first-person rig, so
                # that rig is the one in the file - the game's animations drive
                # it as they are, with nothing to retarget first.
                export_rigged(os.path.join(blend_dir, record["arms_file"]),
                              arms_item, arms_rig, "blend",
                              halo_note(stem, arms_item, arms_rig, True))
                export_rigged(os.path.join(blend_dir, "%s - halo fp arms.fbx" % stem),
                              arms_item, arms_rig, "fbx")
                log("wrote %s on the first-person arms" % stem)
            except Exception as problem:  # noqa: BLE001 - see above
                record.pop("arms_file", None)
                record["arms_binding"] = ("failed to write - %s: %s"
                                          % (type(problem).__name__, problem))
                log("the first-person arms files for %s failed (%s: %s); "
                    "the halo set is written anyway"
                    % (stem, type(problem).__name__, problem))
        # NXE rig: bound to the skeleton the package itself ships against.
        for kind in ("fbx", "glb", "blend"):
            export_rigged(os.path.join(blend_dir, "%s - NXE.%s" % (stem, kind)),
                          nxe, nxe_rig, kind)
        # Unrigged: the model as it stands, with no skeleton in the file.
        for kind in ("blend", "fbx"):
            export_objects(os.path.join(blend_dir, "%s - unrigged.%s" % (stem, kind)),
                           [merged], kind)

    # The extractor already wrote what the container held; add the rigging
    # section under it rather than replacing it.
    report_path = os.path.join(out, "report.txt")
    earlier = ""
    if os.path.exists(report_path):
        with open(report_path, encoding="utf-8") as handle:
            earlier = handle.read().rstrip("\n") + "\n\n"
    with open(report_path, "w", encoding="utf-8") as handle:
        handle.write(earlier + report_text(options,
                                           [row[0] for row in rigged],
                                           stems, armature, nxe_rig))
    log("wrote report.txt")

    copied = mirror_fbx(out, blend_dir, stems)
    if copied:
        log("copied %d .fbx into max" % copied)

    copied = mirror_jms(out, stems)
    if copied:
        log("copied %d .jms into the xbox folder" % copied)

    shipped = ship_source_rigs(out, options, armature)
    if shipped:
        log("kept the source rigs for repair: %s" % ", ".join(shipped))

    # card_art.png used to be a copy of the item's own picture under a second
    # name - the same bytes twice in the folder, and the icon already says which
    # item it is. Nothing read it back, so it is not written at all.
    return 0


if __name__ == "__main__":
    # Blender reports a failed script only when the script raises: with
    # --python-exit-code a raised exception becomes Blender's own exit code,
    # while sys.exit() is swallowed and the pass still looks successful.
    status = main()
    if status:
        raise RuntimeError("rigging stopped with code %d" % status)
