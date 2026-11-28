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
        [--port "MyAvatar.glb"] [--keep-shape] [--eyes-forward]

``--port`` takes an avatar exported by 360sona and puts its body under the item:
the head, the face and the patch of neck an item like the Marine armour leaves
bare. The item itself is untouched - its geometry, UVs, masks and decal are the
ones its container gave, and the export's own copy of the item is left out.
"""

import json
import math
import os
import shutil
import sys

import bmesh
import bpy

# Blender does not put the script's folder on the path, and the pose maths lives
# next to this file because the carrier ships src/ and nothing else.
_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
import halo_pose
from mathutils import Matrix, Quaternion, Vector, kdtree

# The .jms is positional and carries no section markers, so one wrong count shifts
# everything after it and the file still reads as text. It is checked as it is
# written, by the same reading tool.exe has to do, so a broken export is caught
# here instead of at compile time.
try:
    from jms_check import (BIPED_NODE_CHECKSUM, BIPED_NODES,
                           BIPED_NODE_ORDER, check_jms, fp_arm_node_problem)
except ImportError:  # run from somewhere that has not put this folder on the path
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from jms_check import (BIPED_NODE_CHECKSUM, BIPED_NODES,
                           BIPED_NODE_ORDER, check_jms, fp_arm_node_problem)

# The avatar's own body comes from a .glb, read without bpy so the reading and
# the choosing can be tested on their own. The TIFF writer is extraction's own,
# because Blender's Python has no Pillow and the HEK maps are the same format.
try:
    import face_eyes
    import glb_model
    from extract_items import organise, tiff_bytes
except ImportError:  # run from somewhere that has not put this folder on the path
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import face_eyes
    import glb_model
    from extract_items import organise, tiff_bytes

# The biped is authored in Halo units: 100 units is a metre (0.03048 m each),
# so a 1.83 m figure stands 60 units tall with its feet on z = 0.
HALO_UNITS_PER_METRE = 100.0 / 3.048

# The biped's arms. They are the seam the first-person set is cut on: Halo's
# in-game hands are their own model, and the fingers exist nowhere else.
# The arms proper: shoulder to hand, the bones Halo's first-person rig has.
ARM_BONES = (
    "bip01 l upperarm", "bip01 l forearm", "bip01 l hand",
    "bip01 r upperarm", "bip01 r forearm", "bip01 r hand",
)

# Shoulder armour hangs off the clavicles, and Halo's own first-person arms
# carry their shoulder pads, so a shell that is mostly on a clavicle is arm
# armour too. Halo's rig has no clavicle to give it, so it rides the upper arm -
# the bone that moves the shoulder - and stays on the shoulder where it belongs.
SHOULDER_BONES = {
    "bip01 l clavicle": "bip01 l upperarm",
    "bip01 r clavicle": "bip01 r upperarm",
}
ARM_WEIGHTS = ARM_BONES + tuple(SHOULDER_BONES)

# How much of a vertex has to belong to the arms before it is part of them. The
# body is skinned by distance, so every plate near a shoulder carries some arm
# weight; without a floor, one arm bone's 15% share dragged whole torso plates
# into the first-person set, where they hung scattered around the arm.
ARM_SHARE = 0.5
# Stamped into the log, report.txt and every READ ME block, so a file on disk
# can say which build made it instead of being guessed at from its contents.
VERSION = "v200"
BUILD = "one turn, one pivot"

# Tool reads a model's LOD from the last word of the .jms file name, and only
# the superhigh LOD's markers reach the compiled gbxmodel. A name with no LOD
# word leaves that to Tool's own default, which nothing documents as superhigh,
# so the word is always written. Tool takes it back off, and the permutation
# keeps the name in front of it ("UNSC Marine Armor", "UNSC Marine Armor - fp
# arms") - the tag is still named after the source folder.
MODEL_LOD = "superhigh"

# How far the thumb guard's chain is carried back into the palm, in Halo units -
# about the length of the thumb's own base bone. The guard sits proud of the
# palm and Halo's thumb bone runs outside it, so a guard weighted wholly to the
# thumb swings off the hand when the thumb bends, and one weighted wholly to the
# hand leaves the thumb dead. Carrying the chain back lets the palm own the
# guard's root, and because it is one chain the guard still takes two weights a
# vertex - a .jms carries two, and dropping one of a pair is what tore the plate.
SEAT_REACH = 1.2

# How far past Halo's own fingertips an arm's end is laid, in Halo units. A
# glove that stops exactly at a finger bone's tip leaves that tip standing out
# of the end of the finger, so the glove gets a little room to enclose it.
FINGER_MARGIN = 0.6

# Which bones deform what, by Blender bone name. Used for the fallback skin.
DEFORM_BONES = (
    "bip01 pelvis", "bip01 spine", "bip01 spine1", "bip01 neck", "bip01 head",
    "bip01 l clavicle", "bip01 l upperarm", "bip01 l forearm", "bip01 l hand",
    "bip01 r clavicle", "bip01 r upperarm", "bip01 r forearm", "bip01 r hand",
    "bip01 l thigh", "bip01 l calf", "bip01 l foot",
    "bip01 r thigh", "bip01 r calf", "bip01 r foot",
)

# A Halo biped's model must carry two markers or the engine will not take the
# character: it prints "the biped '<path>' has no 'head' marker" and then the
# same for the body. Neither is a per-item decoration - they are where Halo
# looks for the character's head and torso - so both sit on the biped's own
# bones, at the bone's own pivot and with its own orientation. Nothing is
# invented: the marker is the joint.
BIPED_MARKERS = (
    ("head", "bip01 head"),
    ("body", "bip01 spine1"),
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
              "fbx": True, "jms": True, "name": None, "port": None,
              "keep_shape": False, "eyes_forward": True, "stand": True,
              "limbs": False, "tag_prefix": True}
    index = 0
    while index < len(argv):
        word = argv[index]
        if word in ("--items", "--rig", "--fp", "--out", "--name", "--port"):
            parsed[word[2:]] = argv[index + 1]
            index += 2
        elif word == "--no-fbx":
            parsed["fbx"] = False
            index += 1
        elif word == "--no-jms":
            parsed["jms"] = False
            index += 1
        elif word == "--keep-shape":
            parsed["keep_shape"] = True
            index += 1
        elif word == "--stand":
            parsed["stand"] = True
            index += 1
        elif word == "--t-pose":
            parsed["stand"] = False
            index += 1
        elif word == "--fit-limbs":
            parsed["limbs"] = True
            index += 1
        elif word == "--eyes-forward":
            parsed["eyes_forward"] = True
            index += 1
        elif word == "--tag-prefix":
            parsed["tag_prefix"] = True
            index += 1
        elif word == "--plain-tags":
            parsed["tag_prefix"] = False
            index += 1
        else:
            index += 1
    return parsed


# Whether a shader tag is asked for by its bare name or with the item in front.
# tool.exe matches the name character for character against a tag's own name, so
# the two spellings are two different tags: an item that asks for "<item> body"
# draws WHITE where only a tag called "body" exists, and the other way round.
# The item's name in front is the default, because it is unique across a tags
# folder that may hold several items; --plain-tags asks for "body" and "face"
# alone, for a set of tags already named that way.
TAG_PREFIX = [True]


def tag_name(stem, part):
    """The name this model asks tool.exe for: "face", or "<item> face".

    Lower case, always: a Halo tag path carries none - the HEK's own guide says
    "always use lower-case names" - and this string is a tag's name, not a
    label. tool.exe looks the shader up by the name the .jms spells, so a model
    that asks for "UNSC Marine Armor face" is asking for a tag with capitals in
    it, and a tags folder holding "unsc marine armor face.shader_model" answers
    that with the empty shader - the white surface. The item's title keeps its
    capitals everywhere else (folders, files, the .blend); only the shader name
    drops them.
    """
    if TAG_PREFIX[0]:
        return ("%s %s" % (stem, part)).lower()
    return part.lower()


# The carrier .bat streams every [rig] line as Blender writes it, so the
# percentage below is what a player watches while a body is skinned. Python
# buffers a pipe in blocks, so without the flush the numbers would arrive all at
# once at the end - a counter that only counts after the wait is over.
_PROGRESS = [0.0]


def log(message):
    print("[rig] %s" % message, flush=True)


def progress(share, message):
    """Where the run has got to, for the window that is waiting on it.

    Every item's rigging is one share of the whole pass, so a folder of twenty
    items counts through 0-100 once rather than twenty times, and the same
    number says the same thing however many items there are. The skinning is
    most of the time - the tear search runs thirteen whole-body poses - so it
    owns the middle of each item's share and the number moves while it works.
    """
    _PROGRESS[0] = max(0.0, min(1.0, share))
    print("[rig] %3d%%  %s" % (int(round(_PROGRESS[0] * 100.0)), message),
          flush=True)


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
            # Halo's own biped, kept at Halo's own proportions - its bones must
            # stay where the animation expects them. On a 360sona body, whose
            # head is large and whose legs are short, that leaves some bones
            # outside the silhouette: opened in Blender they drew as solid
            # octahedra over the armour, which reads as broken geometry rather
            # than a skeleton. Drawn as sticks and not in front, the body covers
            # the bones that are inside it and the rest reads as the rig it is.
            object_data.data.display_type = "STICK"
            object_data.show_in_front = False
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


def bind_decal(object_data):
    """Show the item with its decal in Blender: bind the blended map.

    Extraction writes `<item> base map + decal.png` beside the item's own map:
    the base map with the decal blended over it by its own alpha, which is the
    form Halo CE can show - shader_model has one colour layer and no second
    texture to blend at run time. The .obj names the plain map, because the OBJ
    carries what the pack stores; the blend is what puts the decal on the item a
    person opens, and the plain map stays beside it untouched. Both files are in
    every folder - Blender, Max and both HEK bitmaps folders - so the shader can
    be pointed at either.
    """
    bound = 0
    for material in object_data.data.materials:
        if material is None or not getattr(material, "use_nodes", False):
            continue
        tree = getattr(material, "node_tree", None)
        if not tree:
            continue
        for node in tree.nodes:
            image = getattr(node, "image", None)
            if image is None:
                continue
            path = bpy.path.abspath(image.filepath) if image.filepath else ""
            if not path.lower().endswith(" base map.png"):
                continue
            candidate = path[:-len("base map.png")] + "base map + decal.png"
            if not os.path.exists(candidate):
                continue
            fresher = bpy.data.images.load(candidate, check_existing=True)
            if fresher is image:
                continue
            node.image = fresher
            bound += 1
    if bound:
        log("decal: bound <item> base map + decal.png in %d material(s)"
            % bound)
    return bound


def prepare(object_data):
    """Make the item open correctly: smooth shading, images inside the file.

    The OBJ carries per-vertex normals and `s 1`, but an importer can still bring
    the faces in flat, and a faceted garment reads as a shading bug rather than
    as the item. Shading is therefore set here as well.

    The colour image is packed into the .blend for the same reason: an unpacked
    image is a broken link the moment the file is moved on its own, and the item
    then opens white with no colour at all.
    """
    bind_decal(object_data)
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


def name_item_materials(meshes, bitmap):
    r"""The item's own materials carry the name of the bitmap they wrap.

    The .mtl the extractor writes names one material per triangle batch -
    ``batch_0``, ``batch_1`` - because that is what those triangles are in the
    file. A .jms carries no other link to a shader: tool.exe reads a material
    name and looks for a ``shader_model`` called after it, so a material left as
    ``batch_0`` asks for a shader named after the importer's batch number, and
    the empty one tool offers to make for it lands in the root of ``tags\``
    under that name. Named after its own bitmap, the shader a user makes is
    called what the map it wraps is called: `<item> base map` for the item's
    surface, `<item> face` and `<item> body` for the ported sheets. The spaces
    stay in the name - a .jms material is a tab-separated field, and Halo's own
    materials carry spaces (`ring dusk` in the HEK's own skybox guide) - so the
    name in the .jms is the name of the .bitmap. An item in several batches
    keeps them apart with the batch number, `<bitmap> 0` and `<bitmap> 1`,
    because each material still needs a shader of its own.
    """
    batches = []
    for object_data in meshes:
        for slot in object_data.material_slots:
            material = slot.material
            if material is None or any(material is seen for _, seen in batches):
                continue
            tail = material.name[len("batch_"):]
            if material.name.startswith("batch_") and tail.isdigit():
                batches.append((int(tail), material))
    if not batches:
        return []
    batches.sort(key=lambda pair: pair[0])
    several = len(batches) > 1
    named = []
    for index, material in batches:
        was = material.name
        # Lower case, because this name is the shader tag's name: tool.exe
        # finds the tag by the spelling in the .jms, and a tag path carries no
        # capitals.
        material.name = (("%s %d" % (bitmap, index) if several else bitmap)
                         .lower())
        named.append("%s (was %s)" % (material.name, was))
    log("item material %s" % ", ".join(named))
    return [material for _, material in batches]


def item_stem(record):
    """The one name this item is written under, in every folder.

    Extraction names it once - its title, or extractedN when nothing titles it -
    and the .obj's own name is the fallback for a catalogue written by a build
    that did not record it.
    """
    return record.get("stem") or os.path.splitext(
        os.path.basename(record.get("obj") or record["id"]))[0]


def uv_tris(mesh):
    """A mesh's triangles as (u, v) triples, skipping any a short uv list lacks."""
    uvs = mesh.get("uvs") or []
    out = []
    for triangle in mesh["triangles"]:
        if any(index >= len(uvs) for index in triangle):
            continue
        out.append(tuple(tuple(uvs[index]) for index in triangle))
    return out


def skull_uvs(mesh, pixels, width, height):
    """The UV triangles of the skull - the part of a head no sheet paints.

    A 360sona head is painted where a face is and left bare everywhere else:
    white padding, the exporter's flat grey, and the inside of a skull whose
    faces are wound the other way. Two rules find those places, and both are
    needed. A triangle whose face points forward is the face and is left out
    whole, which keeps the eyes and everything painted on them. Some of the
    skull is wound the other way and points forward by its normal, so a triangle
    also counts when the sheet has nothing painted where it reads AND its
    position is behind the head's middle: the colour says it is bare, the
    position says it is not the face.

    Not every bare texel of the head, which was tried and which stamped flat
    skin across the forehead of an avatar whose sheet is pale there as part of
    its own face paint.
    """
    points = mesh["positions"]
    uvs = mesh["uvs"]
    used = {int(index) for triangle in mesh["triangles"] for index in triangle}
    if not used or not uvs:
        return []
    depths = [points[index][2] for index in used if index < len(points)]
    middle = (min(depths) + max(depths)) / 2.0 if depths else 0.0
    skull = []
    for triangle in mesh["triangles"]:
        if any(index >= len(uvs) or index >= len(points) for index in triangle):
            continue
        one, two, three = (points[int(index)] for index in triangle)
        edge_one = [two[axis] - one[axis] for axis in range(3)]
        edge_two = [three[axis] - one[axis] for axis in range(3)]
        cross = (edge_one[1] * edge_two[2] - edge_one[2] * edge_two[1],
                 edge_one[2] * edge_two[0] - edge_one[0] * edge_two[2],
                 edge_one[0] * edge_two[1] - edge_one[1] * edge_two[0])
        length = (cross[0] ** 2 + cross[1] ** 2 + cross[2] ** 2) ** 0.5
        if length <= 0:
            continue
        behind = (one[2] + two[2] + three[2]) / 3.0 <= middle
        take = (cross[2] / length) <= 0.3
        if not take and behind and pixels is not None:
            corners = [uvs[int(index)] for index in triangle]
            x = min(width - 1, max(0, int(sum(corner[0] for corner in corners)
                                      / 3.0 * width)))
            y = min(height - 1, max(0, int(sum(corner[1] for corner in corners)
                                       / 3.0 * height)))
            at = (y * width + x) * 4
            red, green, blue = pixels[at], pixels[at + 1], pixels[at + 2]
            take = (max(red, green, blue) >= 100 and max(red, green, blue)
                    - min(red, green, blue) <= 30)
        if take:
            skull.append(tuple(tuple(uvs[int(index)]) for index in triangle))
    return skull


def port_material(mesh, stem, out, model, eyes_forward=False, tone=None,
                  hair_tone=None, scalp_uvs=None, scalp_tone=None,
                  tone_mask=None, outside_mask=None):
    """A Blender material for one ported mesh, and the pixels it needs.

    The image is written beside the item as `<stem> <material>.png` so the .blend
    can pack it like every other texture, and the same pixels are handed back as
    raw RGBA for the `.tif` that tool.exe compiles. They are the same image the
    export carried: nothing is resampled, and its size is reported when it is not
    a power of two, because a bitmap compiler cannot take one that is not.
    """
    name = mesh["material"]
    source = mesh.get("image")
    if source is None or source >= len(model["images"]):
        log("port: %s carries no image, so its material is a flat colour" % name)
        return bpy.data.materials.new("%s %s" % (stem, name)), None
    image = model["images"][source]
    rgba, width, height = glb_model.decode_png(image["data"])
    picture = os.path.join(out, "%s %s.png" % (stem, name))
    written = image["data"]
    # A painted face keeps its gaze wherever the artist left it, and these faces
    # are drawn with the pupil at one end of the eye: under Halo's helmet the
    # avatar then looks off to one side in every frame. --eyes-forward draws the
    # painted eye again, finer: one smooth lash at the weight it was painted with
    # and one pupil in the middle of it. That is opt-in because it changes art.
    if eyes_forward and "face" in name.lower():
        rgba, notes = face_eyes.centre_pupils(rgba, width, height, force=True)
        for line in notes:
            log("port: %s" % line)
        written = face_eyes.png_bytes(rgba, width, height)
    # The halves of one face are painted on two sheets and the two are not
    # graded alike, so the head came out two colours: warm and bright on one
    # side, dull and grey on the other. Both are brought to the one tone.
    #
    # This runs BEFORE the holes are filled, and the order is the whole of it.
    # match_tone measures the sheet it is given, and a filled sheet is mostly
    # fill: the grey it paints over is 40% of the picture and every filled texel
    # is seeded from the paint next to it, so the median the gain is worked out
    # from is the smear and not the face. Measured on the two halves of this
    # head, filling first left the join at 28 levels of colour either side
    # (221,145,79 against 197,149,107) where the file itself has 6 - the pass
    # meant to make one tone was drawing the two-tone line it was added to
    # remove. Measuring the painted sheet first and filling afterwards, from the
    # skin the gain has just matched, leaves 8: the file's own difference.
    if "face" in name.lower() and tone:
        rgba, gain = glb_model.match_tone(rgba, width, height, tone, mask=tone_mask)
        if gain:
            log("port: %s painted x%.2f x%.2f x%.2f on to %s, the skin tone "
                "of the whole face" % ((name,) + gain + (tone,)))
            written = face_eyes.png_bytes(rgba, width, height)
    # A face sheet arrives with holes in it: the exporter leaves flat grey where
    # it painted nothing, and 41% of the pieces of a head read that grey, so the
    # face shows blank patches. The holes are filled from the skin around them -
    # nothing is drawn that was not painted somewhere on the same face. After
    # the eye pass, not before: on a filled sheet the eye pass reads the smooth
    # skin next to the cheek as an eye and stamps one on to the chin.
    if "face" in name.lower():
        rgba, filled = glb_model.fill_unpainted(rgba, width, height)
        if filled:
            log("port: %s had %d unpainted texels of %d, filled from the skin "
                "around them" % (name, filled, width * height))
            written = face_eyes.png_bytes(rgba, width, height)
    # Hair is handed over flat grey. Its colour is not lost from the file, it was
    # never in it: the site mixes the hair colour when it draws the avatar, and
    # the sheet it shares is the value a normal map is stored on. Left alone the
    # hair - which is the whole back of the head under a helmet - draws as a
    # white blob. The same hair IS painted on the face, as brows and beard, so
    # the grey is painted in the colour those are drawn in.
    if hair_tone and "hair" in name.lower():
        rgba, hair_gain = glb_model.tint_base(rgba, width, height, hair_tone)
        if hair_gain:
            log("port: %s is painted in the site's untinted hair base - the "
                "hair's own colour is mixed in when the avatar is drawn, and "
                "never baked into the file - so the sheet is brought "
                "x%.2f x%.2f x%.2f on to %s, the colour its own brows and beard "
                "are drawn in" % ((name,) + hair_gain + (hair_tone,)))
            written = face_eyes.png_bytes(rgba, width, height)
        else:
            rgba, painted = glb_model.paint_blank(rgba, width, height, hair_tone)
            if painted:
                log("port: %s arrived unpainted - the hair colour is the site's, "
                    "not the file's - so its %d flat grey texels are painted in "
                    "%s, the colour the face's own brows and beard are drawn in"
                    % (name, painted, hair_tone))
                written = face_eyes.png_bytes(rgba, width, height)
    # The back of the head. Nothing paints it and nothing covers it: the white
    # there is the sheet's padding, not paint, and only the geometry says which
    # texels are the skull - so the rear triangles' texels are painted in the
    # face's own skin. It is skin, not hair: the hair the export carries is
    # dropped with the costume, and a bare head under a helmet is the head.
    if scalp_uvs and scalp_tone:
        rgba, dashed = glb_model.paint_uv_patch(rgba, width, height, scalp_uvs,
                                                scalp_tone, bare_spread=34)
        if dashed:
            log("port: %s carries bare texels - the padding's white and the "
                "exporter's flat grey, where no sheet paints anything - so the "
                "%d of them the head reads are painted in %s, the face's own "
                "skin"
                % (name, dashed, scalp_tone))
            written = face_eyes.png_bytes(rgba, width, height)
    # The last of the two-tone: each half's UVs run to its island's edge, so the
    # join is one texel of skin and then padding - a pale line down the nose
    # however well the two sheets are matched. The paint is grown into the
    # padding so the edge a mesh samples is paint.
    if "face" in name.lower():
        rgba, bled = glb_model.bleed_padding(rgba, width, height)
        if bled:
            log("port: %s grew its paint %d texels out into the sheet's padding, "
                "so the edge of the head samples paint instead of padding"
                % (name, bled))
            written = face_eyes.png_bytes(rgba, width, height)
    # Everything the head's own triangles do not read is padding, and a welded
    # seam can leave a corner reading it: laid down in skin, no stray corner can
    # show white on the head.
    # The skin sheets alike, not the face alone: a face padded in skin and a
    # body padded in the exporter's own pale fill are two files that read as two
    # skin tones in a bitmaps folder, even though the texels either mesh reads
    # are the same colour in both. Every sheet that is skin - the face, the body
    # under it - is laid down in the skin it is painted in, measured on its own
    # texels, so opening the two side by side shows one skin.
    skin_sheet = "face" in name.lower() or "body" in name.lower()
    if skin_sheet and outside_mask is not None:
        own = glb_model.skin_tones(rgba, width, height, outside_mask)
        own = own or scalp_tone
        if own:
            unread = sum(1 for texel in outside_mask if not texel)
            rgba = glb_model.paint_outside(rgba, width, height, outside_mask, own)
            log("port: %s laid the %d texels its own triangles do not read down "
                "in %s, the skin it is painted in" % (name, unread, own))
            written = face_eyes.png_bytes(rgba, width, height)
    with open(picture, "wb") as handle:
        handle.write(written)
    if not (glb_model.power_of_two(width) and glb_model.power_of_two(height)):
        log("port: %s is %dx%d, which tool.exe cannot compile: a bitmap has to "
            "be a power of two a side" % (os.path.basename(picture), width, height))
    # Loaded fresh and packed: with check_existing Blender hands back the copy
    # of this sheet it read earlier in the session, and every paint pass after
    # that - the tone, the fill, the skin on the bare skull - stayed on disk and
    # out of the .blend, which is why a head kept a bare patch the sheet no
    # longer had. A reload before packing makes the blend carry what was
    # actually painted.
    loaded = bpy.data.images.load(picture, check_existing=False)
    loaded.reload()
    loaded.pack()
    # The bitmap this material wraps is `<item> <name>.png` / `.tif`, so the
    # material, its shader and that map all answer to one name.
    material = bpy.data.materials.new("%s %s" % (stem, name))
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = loaded
    texture.location = (-320, 0)
    surface = next((node for node in nodes if node.type == "BSDF_PRINCIPLED"), None)
    if surface is not None:
        links.new(texture.outputs["Color"], surface.inputs["Base Color"])
        # The avatar's face and body are painted, not plastic: the export stores
        # one colour per texel and no roughness, metalness or specular at all.
        # A default Principled BSDF still gives it a 0.5 roughness sheen and a
        # half-strength specular highlight, which is what made a ported face read
        # as a shiny mask under Blender's lights. Halo's shader_model has no
        # roughness channel either - it lights the base map and nothing else - so
        # the material is set to match: fully rough, no metal, no specular.
        for socket_name, value in (("Metallic", 0.0), ("Roughness", 1.0),
                                   ("Specular IOR Level", 0.0),
                                   ("Specular", 0.0)):
            socket = surface.inputs.get(socket_name)
            if socket is not None:
                socket.default_value = value
    else:
        output = next((node for node in nodes
                       if node.type == "OUTPUT_MATERIAL"), None)
        if output is not None:
            links.new(texture.outputs["Color"], output.inputs["Surface"])
    log("port: %s binds %s (%dx%d)"
        % (name, os.path.basename(picture), width, height))
    return material, (name, rgba, width, height)


def mesh_box_of(objects):
    """(low, high) per axis over every vertex of these objects, or None.

    Read from the vertices themselves, not through the object's matrix: this is
    the same space ``tallest`` above is read in, and the avatar's export is in
    it too. The comparison that uses it is by extents, so a rotation the
    importer put on the object does not matter.
    """
    points = [vertex.co for obj in objects for vertex in obj.data.vertices]
    if not points:
        return None
    return ([min(point[axis] for point in points) for axis in range(3)],
            [max(point[axis] for point in points) for axis in range(3)])


def shared_tone(pixels, width, height, other, ref):
    """Bring the second half to the first half's tone when both share one sheet.

    Two islands on one picture, painted at different brightness, read as a
    two-tone face exactly as two sheets do - and there is no sheet-to-sheet gain
    that can touch it, because scaling the image scales both halves together.
    The halves are two meshes over the same pixels, so the correction is the one
    used across two sheets, with the same image on both sides: the second half's
    island is measured against what the first half paints at the same place on
    the head, in bands of 32 texels, and scaled to it. The first half's island is
    not touched.

    Returns (pixels or None, sentence or None): the pixels to write back when the
    correction ran, and the line to log.
    """
    result = glb_model.tone_bands(pixels, width, height, other, pixels,
                                  width, height, ref)
    if not result:
        gap = glb_model.join_difference(pixels, width, height, other, pixels,
                                        width, height, ref)
        if not gap:
            return None, None
        return None, ("the two halves differ by %.1f level(s) in bands where the "
                      "eye reads a join, and the correction could not run on "
                      "this sheet" % gap[0])
    out_pixels, was, now, bands = result
    if now > 6.0:
        return out_pixels, ("%d band(s) of 32 texels: the two halves differ by "
                            "%.1f level(s) from %.1f, and the correction could "
                            "not close it - the join will show"
                            % (bands, now, was))
    return out_pixels, ("%d band(s) of 32 texels: the two halves differ by %.1f "
                        "level(s) from %.1f on the one sheet they share - one "
                        "tone" % (bands, now, was))


def import_port(path, stem, out, eyes_forward=False, item_box=None,
                item_head=False):
    """The avatar's own head and neck, as meshes to join under the item.

    The export is in the space the items are authored in - y-up metres, the
    avatar's own T-pose - so nothing is scaled or moved here: the head lands
    where the avatar's head is, which is where the item's collar expects it. The
    meshes come back unskinned; ``skin`` binds them to the biped and to the NXE
    skeleton with everything else, so a body under an item needs no name map and
    no weights carried across from the file.
    """
    model = glb_model.read(path)
    for note in model.get("broken") or []:
        log("the .glb is not a body: %s - a mesh that thin is a broken export, "
            "and the avatar it stands for cannot be measured or trusted" % note)
    # Is the item worn over the whole body, rather than on one part of it? Its
    # own box answers that: a costume reaches as far up and down the avatar as
    # the avatar does, where a hat or a pair of boots covers a fraction of it.
    # Both are in the same metres - the item as its container authored it, the
    # avatar as it exported itself - so the two heights compare directly.
    heights = [point[1] for mesh in model["meshes"] for point in mesh["positions"]]
    avatar_height = (max(heights) - min(heights)) if heights else 0.0
    item_height = ((item_box[1][1] - item_box[0][1]) if item_box else 0.0)
    costume = avatar_height > 0.0 and item_height >= 0.90 * avatar_height
    if costume:
        log("port: the item is a costume (%.2f m over a %.2f m avatar), so it is "
            "worn instead of clothes" % (item_height, avatar_height))
    kept, skipped = glb_model.choose(model, stem, item_box=item_box,
                                     costume=costume,
                                     also_skip=("head",) if item_head else ())
    if item_head:
        # The item has a head and a face of its own - a costume's export carries
        # both. The avatar's head is then a SECOND head inside the first: a
        # slightly different size and angle, so the armour's helmet perches on
        # it and reads as crooked from every side. Measured on this armour, the
        # port added 876 triangles above the collar and 2,058 head points that
        # the item already had.
        log("port: the item carries its own head and face, so the avatar's head "
            "is not added - one head inside another is a helmet that sits askew")
    # The exporter's slot index off every name the port writes. A 360sona
    # material is the mesh it paints plus the index it holds in the file - the
    # body's first one is ``body_0`` - and that name is what the sheet, its
    # ``.tif``, the Blender material and the ``.jms`` material line carry, so
    # the index went into the shader a user has to make: ``UNSC Marine Armor
    # body_0`` for a sheet nothing in it is index 0 of. Dropped once, here, and
    # everything downstream follows; the face stays ``face``, which is the name
    # the exporter gives it and never numbers.
    for mesh in kept:
        mesh["material"] = glb_model.plain_material(mesh["material"])
    if costume:
        gone = sorted({glb_model.flatten(mesh["name"]) for mesh in skipped
                       if glb_model.flatten(mesh["name"]) in glb_model.REPLACED_BY_COSTUME})
        covered = sorted({glb_model.flatten(mesh["name"]) for mesh in skipped
                          if glb_model.flatten(mesh["name"]) in glb_model.COVERED_BY_COSTUME})
        log("port: left out of the avatar what the costume replaces (%s)"
            % (", ".join(gone) or "nothing"))
        if covered:
            log("port: the export draws %s on its own body, not on the suit - a "
                "ring and a watch hang beside the armour's glove, and a pair of "
                "glasses is the pair that avatar wore, not the one being worn "
                "now - so they are left out" % ", ".join(covered))
    copies = [glb_model.flatten(mesh["name"]) for mesh in skipped
              if mesh.get("duplicate")]
    if copies:
        log("port: the export writes %s more than once at the same place, so "
            "one copy of each is kept - two heads in one spot is a head with a "
            "pale band down it, and two pairs of glasses is neither pair"
            % ", ".join(sorted(set(copies))))
    made = {}
    used_names = set()
    textures = []
    # A costume's export carries the head and the face, and that face is painted
    # by the AVATAR's own face sheet when the game draws it - which is why the
    # costume's own face UVs land on painted skin in that sheet and on blank
    # padding in the item's base map. The head is skipped (the item brings its
    # own, the one the helmet was modelled round), so the sheet is prepared here
    # for the item's face materials instead of for a second head.
    face_sheet = None
    if item_head:
        sheet = next((mesh for mesh in model["meshes"]
                      if "face" in mesh["material"].lower()
                      and mesh.get("image") is not None), None)
        if sheet is not None:
            spare, written = port_material(sheet, stem, out, model,
                                           eyes_forward=eyes_forward)
            # The sheet is what is wanted here, not a material for a mesh that
            # is not being added; left behind it took the name the item's own
            # face material needs, and Blender answered with `<item> face.001`
            # - a shader name with a suffix nothing would look for.
            if spare is not None and not spare.users:
                bpy.data.materials.remove(spare)
            if written:
                face_sheet = written
                textures.append(written)
    # One tone for the whole face. The export paints the two halves of a head on
    # two sheets, and the two are graded differently - a warm bright side and a
    # dull grey one on the same head - so the target is the average of what each
    # sheet is painted in, and every sheet is brought to it.
    tone = None
    measured = []
    sheet_tone = {}
    tone = None
    tone_masks = {}
    decoded = {}
    sheets = [mesh for mesh in kept
              if "face" in mesh["material"].lower() and mesh.get("image") is not None]
    if len(sheets) > 1:
        counted = set()
        for mesh in sheets:
            # Two halves painted on ONE sheet are one painting, not two. An
            # export that gives both halves the same image (a 512x512 face, on
            # one avatar) has nothing to match, and averaging a tone with itself
            # would only let the log claim a difference that is not there.
            if mesh["image"] in counted:
                continue
            counted.add(mesh["image"])
            pixels, width, height = glb_model.decode_png(
                model["images"][mesh["image"]]["data"])
            decoded[mesh["image"]] = (pixels, width, height)
            # Measured over the texels THIS half's triangles read. A sheet is
            # much bigger than the part of it a half shows, and the two sheets'
            # whole-sheet medians can agree while the skin each half draws with
            # does not: that is a face that still reads as two colours after
            # the tone was "matched".
            mask = glb_model.uv_coverage(width, height, uv_tris(mesh))
            painted = glb_model.skin_tones(pixels, width, height, mask)
            if painted:
                measured.append(painted)
                tone_masks[mesh["image"]] = mask
                sheet_tone[mesh["image"]] = painted
        if len(measured) > 1 and len(set(measured)) > 1:
            tone = tuple(sum(each[channel] for each in measured) // len(measured)
                         for channel in range(3))
            log("port: the face is painted on %d sheets at different brightness "
                "(%s), so each is brought to %s - one face, one colour"
                % (len(measured), ", ".join(str(each) for each in measured), tone))
    # The two halves of the head are painted on two sheets that were graded
    # differently, and the whole-sheet gain in port_material brings both to one
    # tone: it measures each sheet's paint and scales it to the mean of the two,
    # so both halves end at the same measured tone by construction. Copying one
    # half's paint across, or baking a per-point gain field, both resample two
    # different texel grids at the resolution of the head's vertices - an eye is
    # 30x15 texels with 1-3 texel lashes, and it came back as a dash. A gain that
    # is one number per sheet cannot do that: it moves every texel by the same
    # factor. What is measured here is the join itself, so a build that ships a
    # two-tone face says so in the log and in report.txt instead of being found
    # in game.
    # The gain port_material is about to apply to each sheet, so the join can be
    # measured as it will ship rather than as the files arrived.
    sheet_gain = {}
    for image, tone_here in sheet_tone.items():
        if tone:
            sheet_gain[image] = tuple(
                tone[channel] / float(tone_here[channel])
                if tone_here[channel] else 1.0 for channel in range(3))
    halves = [mesh for mesh in sheets if mesh["image"] in decoded]
    joins = []
    # False for the avatars whose two halves share ONE sheet: there is no second
    # sheet to bring across, so the whole-sheet gain still does the work. This was
    # read before it was set on exactly those avatars, and the build died before
    # it wrote anything - the avatar had no rig because there was no file.
    toned = False
    if len(halves) > 1:
        ref = halves[0]
        ref_pixels, ref_w, ref_h = decoded[ref["image"]]
        for other in halves[1:]:
            # An avatar that paints BOTH halves on one sheet has no second sheet
            # to bring across - but its two islands can still be painted at
            # different brightness, and that is the same two-tone face. There is
            # nothing to compare sheet to sheet, so the second half is compared
            # with the first INSIDE the one image: same pixels, the other half's
            # triangles, and its island is scaled to match.
            if other["image"] == ref["image"]:
                pixels, width, height = decoded[other["image"]]
                toned_pixels, text = shared_tone(pixels, width, height, other,
                                                 ref)
                if text:
                    joins.append(text)
                    log("port: %s" % text)
                if toned_pixels:
                    model["images"][other["image"]]["data"] = \
                        face_eyes.png_bytes(toned_pixels, width, height)
                    decoded[other["image"]] = (toned_pixels, width, height)
                    toned = True
                continue
            pixels, width, height = decoded[other["image"]]
            result = glb_model.tone_bands(
                pixels, width, height, other, ref_pixels, ref_w, ref_h, ref)
            if result:
                out_pixels, was, now, bands = result
                model["images"][other["image"]]["data"] = face_eyes.png_bytes(
                    out_pixels, width, height)
                decoded[other["image"]] = (out_pixels, width, height)
                toned = True
                join = ("%d band(s) of 32 texels: the two halves differ by %.1f "
                        "level(s) where the eye reads a join, from %.1f before "
                        "the correction" % (bands, now, was))
                joins.append(join)
                if now > 6.0:
                    log("port: %s - the correction could not close it, so the "
                        "join will show" % join)
                else:
                    log("port: %s - one tone" % join)
                continue
            gap = glb_model.join_difference(
                pixels, width, height, other, ref_pixels, ref_w, ref_h, ref,
                gain=sheet_gain.get(other["image"]),
                ref_gain=sheet_gain.get(ref["image"]))
            if not gap:
                continue
            middle, ninety, samples = gap
            join = ("after the gain the two halves differ by %.1f level(s) at "
                    "the median across %d point(s) (%0.f at the 90th) where the "
                    "eye reads a join" % (middle, samples, ninety))
            joins.append(join)
            if middle > 12.0:
                log("port: %s - that is two paint jobs, not one graded twice, so "
                    "the join will show; a gain cannot fix it without erasing one "
                    "half's art" % join)
            else:
                log("port: %s - one tone" % join)
    # What every mesh on a sheet reads, added up: a head painted on one sheet
    # for both halves has two islands, and laying skin over "everything this
    # half does not read" would paint the other half's face out - one eye, the
    # rest flat skin, which is exactly what one avatar came back with.
    outside = {}
    for mesh in kept:
        source = mesh.get("image")
        if source is None or source >= len(model["images"]):
            continue
        size = decoded.get(source)
        if size is None:
            size = glb_model.decode_png(model["images"][source]["data"])
            decoded[source] = size
        width, height = size[1], size[2]
        mask = outside.get(source)
        if mask is None:
            mask = bytearray(width * height)
            outside[source] = mask
        glb_model.uv_coverage(width, height, uv_tris(mesh), into=mask)
    # The hair's colour, read off the face before anything is written: see the
    # note in port_material, where the grey hair sheet is painted with it.
    # A bare head: with the hair gone there is nothing for the hair colour to
    # paint, so the scalp takes the skin the face is drawn in.
    scalp_tone = tone or (measured[0] if measured else None)
    hair_tone = None
    inks = []
    seen_sheets = set()
    for mesh in kept:
        if ("hair" not in mesh["name"].lower()
                or mesh["image"] is None or mesh["image"] in seen_sheets):
            continue
        seen_sheets.add(mesh["image"])
        pixels, width, height = glb_model.decode_png(
            model["images"][mesh["image"]]["data"])
        found = glb_model.ink_tones(pixels, width, height)
        if found:
            inks.append(found)
    if inks:
        hair_tone = tuple(sum(each[channel] for each in inks) // len(inks)
                          for channel in range(3))
        log("port: the hair is drawn in the site's colour, not painted in the "
            "file; the face's brows and beard are, at %s, so that is the colour "
            "the hair is given" % (hair_tone,))
    objects = []
    for mesh in kept:
        label = "%s - %s" % (stem, mesh["material"])
        data = bpy.data.meshes.new(label)
        data.from_pydata([tuple(point) for point in mesh["positions"]], [],
                         [tuple(face) for face in mesh["triangles"]])
        data.update()
        layer = data.uv_layers.new(name="uv0")
        # glTF stores v running down the picture and every other texture in this
        # pipeline is bottom-up, so it is flipped once, here - the same flip the
        # .obj writer makes when it reads the pack's own textures.
        for loop in data.loops:
            if loop.vertex_index < len(mesh["uvs"]):
                u, v = mesh["uvs"][loop.vertex_index]
                layer.data[loop.index].uv = (u, 1.0 - v)
        for polygon in data.polygons:
            polygon.use_smooth = True
        # Two primitives can carry one material name and two different pictures.
        # This export splits the face either side of the nose and each half has
        # its own sheet. Keyed by the name alone they became a single material,
        # so both halves were painted with whichever sheet came last: the half
        # left on the other sheet landed on blank pixels and drew as a pale,
        # featureless panel - half a face with nothing on it.
        key = (mesh["material"], mesh.get("image"))
        material = made.get(key)
        if material is None:
            shot = mesh
            if key[0] in used_names:
                # A space, not the exporter's underscore: a second sheet for one
                # slot (the two halves of a face painted on two files) still
                # needs a material of its own, and this is the only number left
                # in a ported name - kept in the form an item in several batches
                # uses, `<bitmap> 2`, so no ported shader ends in `_<digit>` and
                # none can be read as the exporter's index.
                unique = "%s %d" % (key[0], key[1] if key[1] is not None
                                    else len(used_names))
                while unique in used_names:
                    unique += "x"
                shot = dict(mesh, material=unique)
            used_names.add(shot["material"])
            scalp = None
            if scalp_tone and "face" in mesh["material"].lower():
                half = decoded.get(mesh["image"])
                if half is None:
                    half = glb_model.decode_png(
                        model["images"][mesh["image"]]["data"])
                scalp = skull_uvs(mesh, half[0], half[1], half[2])
            face = "face" in mesh["material"].lower()
            material, written = port_material(
                shot, stem, out, model, eyes_forward=eyes_forward,
                tone=(None if toned and face else tone),
                hair_tone=hair_tone, scalp_uvs=scalp, scalp_tone=scalp_tone,
                tone_mask=tone_masks.get(mesh.get("image")),
                outside_mask=outside.get(mesh.get("image")))
            made[key] = material
            if written:
                textures.append(written)
        data.materials.append(material)
        object_data = bpy.data.objects.new(label, data)
        bpy.context.scene.collection.objects.link(object_data)
        objects.append(object_data)
        log("ported %s: %d verts, %d triangles"
            % (mesh["name"], len(mesh["positions"]), len(mesh["triangles"])))
    lines = glb_model.report(model, kept, skipped)
    for line in lines:
        log(line.strip())
    # The head's own box, so it can be given back its proportions once the fit
    # has been over it. It is taken from the vertices the triangles actually
    # use: an export can carry one vertex buffer for the whole avatar and index
    # a few faces out of it, so the head's mesh holds the arms and feet as well,
    # unreferenced and enormous.
    # The head can arrive as several primitives sharing one material - the
    # avatar's splits either side of the face - so the box is the union of every
    # mesh that material covers, not of the largest one, which is half a head.
    heads = [mesh for mesh in kept
             if glb_model.flatten(mesh["name"]) == "head"]
    if not heads:
        counts = {}
        for mesh in kept:
            counts[mesh["material"]] = (counts.get(mesh["material"], 0)
                                        + len(mesh["triangles"]))
        biggest = max(counts, key=counts.get) if counts else None
        heads = [mesh for mesh in kept if mesh["material"] == biggest]
    box = None
    points = []
    for mesh in heads:
        used = {index for triangle in mesh["triangles"] for index in triangle}
        points.extend(mesh["positions"][index] for index in used)
    if points:
        box = ([min(point[axis] for point in points) for axis in range(3)],
               [max(point[axis] for point in points) for axis in range(3)])
    head_materials = [made[(mesh["material"], mesh.get("image"))]
                      for mesh in heads
                      if (mesh["material"], mesh.get("image")) in made]
    body_mesh = next((mesh for mesh in kept
                      if glb_model.flatten(mesh["name"]) == glb_model.BODY_SLOT), None)
    return {"objects": objects, "textures": textures, "lines": lines,
            "join": joins,
            "material_objects": list(made.values()), "box": box,
            "costume": costume,
            "body_material": (made.get((body_mesh["material"], body_mesh.get("image")))
                              if body_mesh else None),
            "head_material": head_materials or None,
            "face_sheet": face_sheet}


def name_remaining_materials(object_data, bitmap, stem):
    """Name the materials an export labelled itself, after the maps they wrap.

    ``name_item_materials`` renames the exporter's ``batch_N`` batches, and an
    export can just as well label them itself - this armour arrives as
    ``hair_6``, ``body_0`` and ``face``. A .jms material name is the shader
    tool.exe looks for, so a suit left as ``hair_6`` asks for a shader nobody
    would think to make, and tool.exe offers to create one called that, which is
    a white suit. The material covering the most triangles is the item's own
    surface and takes its bitmap's name; the face and the neck have already been
    named for their own sheet by then, so they are left alone.
    """
    mesh = object_data.data
    counts = {}
    for polygon in mesh.polygons:
        counts[polygon.material_index] = counts.get(polygon.material_index, 0) + 1
    if not counts:
        return []
    bitmap = bitmap.lower()
    taken = {bitmap, tag_name(stem, "face"), tag_name(stem, "body")}
    biggest = max(counts, key=counts.get)
    named = []
    spare = 2
    for index in sorted(counts, key=lambda slot: -counts[slot]):
        material = mesh.materials[index] if index < len(mesh.materials) else None
        if material is None or material.name in taken:
            continue
        was = material.name
        material.name = bitmap if index == biggest else "%s %d" % (bitmap, spare)
        if index != biggest:
            spare += 1
        named.append("%s (was %s)" % (material.name, was))
    if named:
        log("item material %s" % ", ".join(named))
    return named


# Where the avatar's own face sits on its face sheet, measured from the image:
# chin at the bottom of the painted face, forehead at the top.
FACE_BAND = (0.08, 0.95)


def project_face_uvs(mesh):
    """Lay the painted face onto the sheet from where the head actually is.

    The item's own face coordinates were laid out for the item's own sheet: on
    this armour they sit inside one texel of it, which is why the game showed a
    blank mask. Pointing them at the avatar's sheet without moving them put skin
    under every triangle but the features in the wrong places - eyes out on a
    cheek, nose across the middle.

    So the face is projected: u across the head, v up it from the chin, into the band of the sheet the
    avatar's own face occupies. It runs again at export because the join with
    the ported head merges UV layers, and the coordinates written before that
    are not the ones the .jms gets.
    """
    slots = [slot for slot, material in enumerate(mesh.materials)
             if material is not None and (material.name or "").lower().endswith(" face")]
    if not slots:
        return 0
    wanted = set(slots)
    face = [polygon for polygon in mesh.polygons if polygon.material_index in wanted]
    if not face:
        return 0
    corners = [mesh.vertices[mesh.loops[index].vertex_index].co
               for polygon in face for index in polygon.loop_indices]
    # The head looks along +x, so the face runs across y and up z. Using x for
    # the across direction left every triangle on one texel column.
    left = min(point.y for point in corners); right = max(point.y for point in corners)
    chin = min(point.z for point in corners); crown = max(point.z for point in corners)
    if mesh.uv_layers.active is None:
        mesh.uv_layers.new(name="UVMap")
    layers = list(mesh.uv_layers)
    across = max(right - left, 1e-6)
    tall = max(crown - chin, 1e-6)
    for polygon in face:
        for index in polygon.loop_indices:
            point = mesh.vertices[mesh.loops[index].vertex_index].co
            u = 0.5 + (point.y - (left + right) / 2.0) / (across * 1.10)
            v = FACE_BAND[0] + (point.z - chin) / tall * (FACE_BAND[1] - FACE_BAND[0])
            placed = (min(max(u, 0.02), 0.98), min(max(v, 0.02), 0.98))
            for layer in layers:
                layer.data[index].uv = placed
    return len(face)


def bind_item_map(object_data, folder):
    """Give every material that arrived with no image the item's own map.

    The .obj's .mtl names a map beside it, but the importer does not always
    resolve that name, and a material with no image node draws one flat colour
    in Blender whatever its UVs say. Measured on this armour, the surface that
    covers 5,700 triangles was the one left without a map, so the suit opened
    grey in Blender while its atlas sat unread beside it. The planes of that
    atlas are what every other material here samples, so the largest image in
    the item's own folder is the one to bind.
    """
    best = None
    try:
        names = os.listdir(folder)
    except OSError:
        return 0
    for name in names:
        if not name.lower().endswith((".png", ".tif", ".tiff", ".tga", ".jpg")):
            continue
        path = os.path.join(folder, name)
        size = os.path.getsize(path)
        if best is None or size > best[1]:
            best = (path, size)
    if best is None or best[1] < 4096:
        return 0
    image = bpy.data.images.load(best[0], check_existing=True)
    bound = 0
    for material in object_data.data.materials:
        if material is None or "face" in (material.name or "").lower():
            continue
        material.use_nodes = True
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        if any(node.type == "TEX_IMAGE" and node.image for node in nodes):
            continue
        nodes.clear()
        texture = nodes.new("ShaderNodeTexImage")
        texture.image = image
        surface = nodes.new("ShaderNodeBsdfPrincipled")
        for socket_name, value in (("Metallic", 0.0), ("Roughness", 0.8),
                                   ("Specular IOR Level", 0.2)):
            socket = surface.inputs.get(socket_name)
            if socket is not None:
                socket.default_value = value
        out = nodes.new("ShaderNodeOutputMaterial")
        links.new(texture.outputs["Color"], surface.inputs["Base Color"])
        links.new(surface.outputs[0], out.inputs[0])
        bound += 1
    if bound:
        try:
            image.pack()
        except RuntimeError:
            pass
        log("%s: bound %s into %d material(s) that had no image - the suit "
            "shows its map in Blender instead of one flat colour"
            % (object_data.name, os.path.basename(best[0]), bound))
    return bound


def bind_face_sheet(object_data, sheet, path, stem):
    """Paint a costume's own face with the avatar's own face sheet.

    The export's head is left out when a costume brings its own, but the face
    still comes from the player's avatar: the costume's face materials are laid
    out for that sheet, not for the item's base map. Measured on this armour,
    100% of the face's triangles land on painted skin in the avatar's sheet, and
    the item's own map has nothing but blank padding where they read - which is
    the white, eyeless mask under the helmet the game showed.

    So the sheet is bound over the item's face materials, and they become ONE
    material, `<item> face`: one sheet is one shader, and the .jms material name
    is the shader tool.exe looks for. Nothing is re-modelled - the head keeps
    the shape the helmet was built round, only its paint changes.
    """
    name, _rgba, width, height = sheet
    if not os.path.exists(path):
        log("port: %s was not written, so the face keeps the item's own map"
            % os.path.basename(path))
        return 0
    mesh = object_data.data
    wanted = set()
    for index, slot in enumerate(mesh.materials):
        if slot is None:
            continue
        flat = glb_model.flatten(slot.name or "")
        if flat.startswith("face") or flat.startswith("body"):
            wanted.add(index)
    if not wanted:
        return 0
    image = bpy.data.images.load(path, check_existing=False)
    image.reload()
    image.pack()
    material = bpy.data.materials.new(tag_name(stem, "face"))
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    surface = next((node for node in nodes if node.type == "BSDF_PRINCIPLED"), None)
    if surface is not None:
        links.new(texture.outputs["Color"], surface.inputs["Base Color"])
        for socket_name, value in (("Metallic", 0.0), ("Roughness", 1.0),
                                   ("Specular IOR Level", 0.0),
                                   ("Specular", 0.0)):
            socket = surface.inputs.get(socket_name)
            if socket is not None:
                socket.default_value = value
    mesh.materials.append(material)
    target = len(mesh.materials) - 1
    moved = 0
    was_face = set()
    for polygon in mesh.polygons:
        if polygon.material_index in wanted:
            polygon.material_index = target
            was_face.add(polygon.index)
            moved += 1
    # The item's own face coordinates are kept exactly as its container wrote
    # them. They were laid out on the avatar's face sheet, which is the sheet
    # bound over them here, so eyes, brows, nose and mouth land where the
    # artist drew them. Re-projecting the face into a hand-tuned band of the
    # sheet (which this pass used to do) threw that away: measured on the sheet
    # the avatar is painted on, a band from v 0.08 to 0.95 lifts the mouth into
    # the beard at the chin and drops the brows on to the eyes.
    for index in range(len(mesh.materials) - 1, -1, -1):
        if any(polygon.material_index == index for polygon in mesh.polygons):
            continue
        mesh.materials.pop(index=index)
    log("port: the item's own face is painted with %s (%dx%d) - the sheet its "
        "UVs were laid out for, which is the avatar's, not the item's base map; "
        "%d face/neck face(s) became the one material %r"
        % (os.path.basename(path), width, height, moved, material.name))
    # A material of its own means a shader of its own, and the engine does not
    # invent one: with no tag of that name it draws the head in its stock white
    # shader, which reads exactly like a blank face texture.
    log("port: the head needs a shader_model whose tag name is exactly %r, with "
        "that sheet as its base map (%s in bitmaps\\, HEK copy) - without it the "
        "engine draws the head white"
        % (material.name, os.path.splitext(os.path.basename(path))[0]))
    return moved


def refit_ported(object_data, materials, head_materials, box):
    """Give the ported head back the proportions the export authored.

    A whole body is fitted joint by joint, and the head straddles two of those
    joints - the neck and the head - whose bones the fit scales and turns by
    different amounts. A face blended between the two comes out stretched: on
    the first real export it arrived 6.7% wider and 3.5% shorter than the file's
    own head, which reads as a squashed face and a brow that covers the eyes.
    Halo's animations move the bones, not the mesh, so the shape has to be right
    before the bones carry it.

    The export's own proportions are restored, at the height the fit gave the
    head, about the head's own centre - and only the ported vertices move, so
    the item's geometry is exactly what it was.
    """
    if head_materials is None:
        return None
    if not isinstance(head_materials, (list, tuple, set)):
        head_materials = [head_materials]
    if not box or not materials or not head_materials:
        return None
    mesh = object_data.data
    head_slots = {index for index, slot in enumerate(object_data.material_slots)
                  if slot.material in head_materials}
    every_slot = {index for index, slot in enumerate(object_data.material_slots)
                  if slot.material in materials}
    moved = set()
    head_used = set()
    for polygon in mesh.polygons:
        if polygon.material_index in every_slot:
            moved.update(polygon.vertices)
            if polygon.material_index in head_slots:
                head_used.update(polygon.vertices)
    if not head_used or not moved:
        return None
    points = [mesh.vertices[index].co for index in head_used]
    low = [min(point[axis] for point in points) for axis in range(3)]
    high = [max(point[axis] for point in points) for axis in range(3)]
    now = [high[axis] - low[axis] for axis in range(3)]
    # Halo space is (depth, width, height); the export is (width, height, depth).
    # The same three extents, turned once by to_halo_space.
    want = [box[1][2] - box[0][2], box[1][0] - box[0][0], box[1][1] - box[0][1]]
    if min(now) <= 0 or min(want) <= 0:
        return None
    # The height the fit gave the head is kept; width and depth are brought back
    # into the export's own ratio to it.
    scale = now[2] / want[2]
    factors = [(want[axis] * scale) / now[axis] for axis in range(3)]
    if not all(0.5 <= factor <= 2.0 for factor in factors):
        log("port: the head's proportions are off by %s of the export's own - "
            "too far to correct, left as the fit put it"
            % ", ".join("x%.2f" % factor for factor in factors))
        return None
    centre = [(low[axis] + high[axis]) / 2.0 for axis in range(3)]
    for index in moved:
        point = mesh.vertices[index].co
        mesh.vertices[index].co = tuple(
            centre[axis] + (point[axis] - centre[axis]) * factors[axis]
            for axis in range(3))
    mesh.update()
    return factors


# How much neck to keep under the chin, as a share of the head's own height.
# A collar sits below the jaw and the suit's own neck hole is narrower than the
# head, so the band between the two is the avatar's neck and it is meant to be
# skin. Cutting the whole body away took it with the torso and left the chin
# resting on the collar - no neck at all - on every avatar whose body is whole.
NECK_KEPT = 0.22

# How wide the neck is, as a share of the narrower half-width of the head. The
# cut keeps the band under the chin and nothing else, and the head's own box is
# what says where the chin is, so the band is a cylinder up the head's axis. A
# body is wider than this at the shoulders: on the avatar this was measured on
# the head is 0.161 m either side of the nose and the T-pose arms reach 0.711 m,
# so half the head's half-width keeps the neck and takes the rest.
NECK_RADIUS = 0.5


def cut_body(object_data, material, head_materials=None, neck=NECK_KEPT):
    """Take the avatar's own body out from under a costume, once it is scaled.

    A costume is the whole figure: the site draws the suit instead of a body,
    and the export still carries the body underneath it. Left in, that body is
    not hidden - it is a centimetre proud of the armour's sleeve in places - so
    bare arms show through the suit and the skin fights the shell in the game.

    It cannot simply be left out of the port, because it is what the fit
    measures the avatar against: a head alone measures 0.55 m, the fit reads
    that as a broken export, and the model came out 2.5 m tall. So the body
    comes through the fit and is cut away here, after every scale is settled.

    The neck stays. The body mesh is where the neck is, and the band under the
    chin - from the jaw down about a fifth of the head's height - is what shows
    between the head and the suit's collar. Cutting the material wholesale took
    the neck with it and left the chin sitting on the armour; keeping this band
    puts skin back where the suit's neck hole is, with the rest of the band
    hidden inside the collar. Everything else - torso, arms, legs - goes, and
    the arms are what need saying twice: they are held out at shoulder height,
    so a cut drawn by height alone lets them through (see the axis measured
    below), and a body left under a sleeve shows bare skin between the strips
    of it. A face goes if it is below the floor OR away from the head's axis.
    """
    mesh = object_data.data
    slots = {index for index, slot in enumerate(object_data.material_slots)
             if slot.material is material}
    if not slots:
        return 0
    # Where the jaw is, so the band can be measured from the head itself rather
    # than from a number guessed per avatar. The mesh is still y-up here: the
    # turn into Halo's axes happens after every scale is settled.
    floor = None
    axis = None
    radius = None
    head_slots = {index for index, slot in enumerate(object_data.material_slots)
                  if head_materials and slot.material in head_materials}
    if head_slots:
        points = [mesh.vertices[index].co for polygon in mesh.polygons
                  if polygon.material_index in head_slots
                  for index in polygon.vertices]
        if points:
            low = min(point.y for point in points)
            high = max(point.y for point in points)
            floor = low - neck * (high - low)
            # The head's axis, so the neck can be told from the shoulders. A
            # height alone cannot do it: this avatar is 1.167 m tall at the top
            # of the body and its T-pose arms sit at 1.05..1.17 m, which is
            # ABOVE the head's bottom (1.129 m) - so a floor drawn below the
            # head, which is what a share of the head's height below its lowest
            # point is, leaves every one of those arm faces above the cut and
            # they show through the sleeve. Distance from the head's axis does
            # not care where the arms are held.
            axis = ((min(point.x for point in points) + max(point.x for point in points)) / 2.0,
                    (min(point.z for point in points) + max(point.z for point in points)) / 2.0)
            radius = NECK_RADIUS * min(
                (max(point.x for point in points) - min(point.x for point in points)) / 2.0,
                (max(point.z for point in points) - min(point.z for point in points)) / 2.0)
    working = bmesh.new()
    working.from_mesh(mesh)
    faces = []
    for face in working.faces:
        if face.material_index not in slots:
            continue
        verts = list(face.verts)
        if floor is not None and max(vert.co.y for vert in verts) < floor:
            faces.append(face)
            continue
        if axis is not None:
            centre_x = sum(vert.co.x for vert in verts) / len(verts)
            centre_z = sum(vert.co.z for vert in verts) / len(verts)
            if ((centre_x - axis[0]) ** 2 + (centre_z - axis[1]) ** 2) ** 0.5 > radius:
                faces.append(face)
    bmesh.ops.delete(working, geom=faces, context="FACES")
    working.to_mesh(mesh)
    working.free()
    mesh.update()
    return len(faces)


def join_meshes(meshes, name):
    if not meshes:
        return None
    if len(meshes) > 1:
        # The OBJ importer leaves its axis matrix on the object and the item's
        # points in the item's own space; join converts each object's points
        # into the active object's space, so a mesh this tool built (matrix
        # identity) would be turned by that axis matrix while the item was not,
        # and to_halo_space would then turn the turned one again. Every object
        # is given the item's matrix first, so the join is a straight copy and
        # the whole model reaches to_halo_space in one space.
        matrix = meshes[0].matrix_world.copy()
        # The same goes for texture coordinates. Join merges a layer by name,
        # and the .obj importer calls its own UVMap while a mesh built here
        # calls its uv0 - so the head's coordinates would land in a second layer
        # while its faces read the item's, which is empty for them, and the
        # painted face would sample one texel. One name, one layer.
        wanted = (meshes[0].data.uv_layers[0].name
                  if meshes[0].data.uv_layers else None)
        for object_data in meshes[1:]:
            object_data.matrix_world = matrix
            layers = object_data.data.uv_layers
            if wanted and len(layers):
                layers[0].name = wanted
        bpy.context.view_layer.update()
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


# How close two ported vertices have to be to be the same point on the surface.
# A 360sona export cuts the face into a left half and a right half that meet
# down the nose, and the two halves do not share a vertex: the halves' centreline
# vertices were measured 5.1 micrometres apart, max, on this avatar. That is the
# same point split across two objects, not a gap, so 20 micrometres welds it and
# is far too small to touch anything the artist modelled.
SEAM_WELD = 2e-5

AUTHORED_BODY_HEIGHT = 1.4

def weld_seam(object_data, materials, distance=SEAM_WELD):
    """Weld the vertices an export splits where one surface meets itself.

    The face arrives as two meshes, one holding the triangles right of the nose
    and one the triangles left of it, and no vertex is shared between them. Blender
    smooth-shades a vertex from the faces that use it, so at the join each half
    averages only its own side: measured either side of this head's centreline,
    the two normals differed by a median 24 degrees and up to 55. A surface with
    a 24 degree kink down the middle of it draws exactly that - a crease along
    the nose and forehead - whatever colour the two halves are painted.

    Welding the coincident vertices makes the join one vertex with both halves'
    faces around it, so one normal is computed for it and the surface shades as
    the one continuous surface it is. Only the ported avatar's own vertices are
    welded, so the item is left exactly as its container authored it. Returns
    how many vertices were merged away.
    """
    if not materials:
        return 0
    mesh = object_data.data
    slots = {index for index, slot in enumerate(object_data.material_slots)
             if slot.material in materials}
    if not slots:
        return 0
    wanted = set()
    for polygon in mesh.polygons:
        if polygon.material_index in slots:
            wanted.update(polygon.vertices)
    if not wanted:
        return 0
    working = bmesh.new()
    working.from_mesh(mesh)
    working.verts.ensure_lookup_table()
    before = len(working.verts)
    bmesh.ops.remove_doubles(working, verts=[working.verts[index]
                                           for index in sorted(wanted)],
                             dist=distance)
    merged = before - len(working.verts)
    working.to_mesh(mesh)
    working.free()
    mesh.update()
    return merged


# Two vertices closer than this are the same point. The exported item carries
# exact copies - 5,023 vertices standing on 1,987 positions, 3,036 spare copies -
# so a seam is two surfaces that happen to touch rather than one surface. The
# copies are at the same coordinates, so merging them moves nothing.
SURFACE_WELD = 1e-4


def weld_surface(object_data, distance=SURFACE_WELD):
    """Make the copies of a point one vertex, so the surface is joined up.

    Skin weights are per vertex. Wherever two copies of a point sit on each other
    they are weighted apart, and the game draws the seam as a split - the plates
    read as detached, the shading breaks into facets at every join, and a tear
    search cannot see the edge it should repair because the edge does not exist.
    Measured on the item as it arrives: 5,023 vertices on 1,987 positions, all of
    them exact copies. Merging them changes no coordinate; it makes one surface
    out of two that were touching. Returns how many copies went away.
    """
    mesh = object_data.data
    working = bmesh.new()
    working.from_mesh(mesh)
    working.verts.ensure_lookup_table()
    before = len(working.verts)
    bmesh.ops.remove_doubles(working, verts=list(working.verts), dist=distance)
    merged = before - len(working.verts)
    if merged:
        working.to_mesh(mesh)
        mesh.update()
    working.free()
    return merged


def close_borders(object_data):
    """Put a face across every open border, so no edge of the model is open.

    The item is a costume of thin shells: sleeves and trouser legs are open
    tubes, and every armour plate is a wafer whose rim has no face on it. Halo
    draws one side of a triangle, so an open rim is something to see through -
    the background shows at the edges of the armour, and looking down an arm
    shows the inside of the sleeve. The mirrored copy of every triangle in the
    .jms answers the single-sided triangles, but it cannot answer a hole: there
    is nothing there to draw.

    So each border loop is closed with one face of its own. Nothing moves and
    nothing is added outside the outline the model already has - the cap lies
    across the opening the rim already describes. Returns (loops closed, faces
    added, borders left open).
    """
    mesh = object_data.data
    working = bmesh.new()
    working.from_mesh(mesh)
    working.verts.ensure_lookup_table()
    border = [edge for edge in working.edges if len(edge.link_faces) == 1]
    if not border:
        working.free()
        return 0, 0, 0
    around = {}
    for edge in border:
        one, two = edge.verts
        around.setdefault(one, []).append(two)
        around.setdefault(two, []).append(one)
    walked = set()
    closed = 0
    added = 0
    left = 0
    for edge in border:
        one, two = edge.verts
        if (one, two) in walked or (two, one) in walked:
            continue
        ring = [one, two]
        walked.add((one, two))
        walked.add((two, one))
        while True:
            last = ring[-1]
            step = None
            for other in around.get(last, ()):
                if (last, other) in walked:
                    continue
                step = other
                break
            if step is None:
                break
            walked.add((last, step))
            walked.add((step, last))
            ring.append(step)
            if step is ring[0]:
                break
        if len(ring) < 4 or ring[-1] is not ring[0]:
            # A border that does not come back to where it started is not a
            # hole with an outline; there is no face to put across it.
            left += 1
            continue
        corners = [vertex for vertex in ring[:-1]]
        if len(corners) > 3 and len({vertex.index for vertex in corners}) != len(corners):
            left += 1
            continue
        try:
            working.faces.new(corners)
        except ValueError:
            left += 1
            continue
        closed += 1
        added += 1
    if added:
        working.to_mesh(mesh)
        mesh.update()
    working.free()
    return closed, added, left


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


def stand_axis(mesh, avatar, low=0.60, high=3.00):
    """Which axis the model stands up along.

    Neither the item's file nor the avatar's is reliably y-up: an .obj arrives
    z-up, a .glb y-up, and the port rotates one into the other's space. Reading
    height off a fixed axis therefore measures whatever happens to lie along it
    - on the 360sona avatar that was 0.417 m of depth, and the avatar was then
    scaled x4.578 into a 6.9 m giant. The tallest span of the avatar itself is
    its height, which is true of any standing figure, so that is the axis used.
    """
    points = mesh.data.vertices
    spans = []
    for axis in range(3):
        values = [points[index].co[axis] for index in avatar]
        if values:
            spans.append(max(values) - min(values))
        else:
            spans.append(0.0)
    order = sorted(range(3), key=lambda axis: -spans[axis])
    for axis in order:
        if low <= spans[axis] <= high:
            return axis
    return order[0]


def keep_shape_scale(mesh, avatar, fit, authored=AUTHORED_BODY_HEIGHT, axis=None):
    """Bring a kept-shape model onto Halo's scale, one factor a part.

    Halo cannot rescale a biped: the model's nodes are the skeleton its animation
    graph drives by name, and the weapon in the hand, the pickup and the collision
    capsule are all placed from them. So the model comes onto Halo's scale, and it
    comes there by ONE uniform factor per part - never by stretching an axis,
    which is what changes a mesh's shape:

      * the avatar is scaled to the biped's height, fit x the 1.40 m body items
        are authored for, so it ends exactly as tall as Halo's biped;
      * the item, authored for that same 1.40 m body, is scaled by fit, so it
        still covers the body it was made for.

    `avatar` is the set of vertex indices belonging to the ported avatar; the
    rest is the item. Returns the measurements that were applied, or None when
    there is no avatar under the item to measure (nothing is moved then).
    """
    points = mesh.data.vertices
    if axis is None:
        axis = stand_axis(mesh, avatar)
    item = [vertex.co[axis] for index, vertex in enumerate(points)
            if index not in avatar]
    head = [points[index].co[axis] for index in avatar]
    item_height = (max(item) - min(item)) if item else 0.0
    avatar_height = (max(head) - min(head)) if head else 0.0
    biped_height = fit * authored
    if avatar_height <= 0.0 or item_height <= 0.0 or biped_height <= 0.0:
        return None
    if avatar_height < 0.60:
        # No avatar is 0.6 m tall. A height this small means the mesh it was
        # measured from is not the body - a broken export, or a sliver of one -
        # and scaling it to the biped would multiply the whole model into a
        # giant: measured on a 360sona export carrying a 34-triangle body, the
        # avatar went x4.578 and the model came out 6.9 m tall.
        return None
    to_biped = biped_height / avatar_height
    for index, vertex in enumerate(points):
        grow = to_biped if index in avatar else fit
        vertex.co = (vertex.co.x * grow, vertex.co.y * grow, vertex.co.z * grow)
    mesh.data.update()
    return {"avatar_height": avatar_height,
            "avatar_scale": to_biped,
            "avatar_after": avatar_height * to_biped,
            "item_height": item_height,
            "item_scale": fit,
            "item_after": item_height * fit,
            "biped_height": biped_height,
            "axis": axis}


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


def whole_body(object_data, authored=AUTHORED_BODY_HEIGHT):
    """Is this item a body of its own, rather than a garment or a prop?

    A body spans the avatar from its feet to its helmet, so there is no edge to
    hang it from and no single scale that lands its joints on the bones. A hat,
    a tee or a pair of boots is not that: it is worn on a body, and the fit above
    is what puts it on the right part of one.
    """
    ys = [vertex.co.y for vertex in object_data.data.vertices]
    if not ys:
        return False
    return max(ys) - min(ys) >= 0.8 * authored


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

# ------------------------------------------------------------ fitting a body

# Which of the avatar's joints each part of Halo's biped is, and the joint that
# lies beyond it on the same bone. Avatar items are authored on the NXE skeleton
# in metres, so its joints are where the item's own joints are; Halo's biped is
# where the game's animations put them.
#
# Which way the fit goes is decided by the game, not by taste. Halo's animations
# carry a node transform for every frame, so a skeleton scaled down to a short
# item would be put back the moment the biped animates: the bones cannot be
# fitted to the mesh. The mesh is fitted to the bones instead - every joint is
# carried onto its bone, the bone between two joints turns the mesh with it, and
# the item keeps its own size everywhere else.
BODY_JOINTS = (
    (0, "bip01 pelvis", 1),
    (1, "bip01 spine", 5),
    (5, "bip01 spine1", 14),
    (14, "bip01 neck", 19),
    (19, "bip01 head", None),
    (12, "bip01 l clavicle", 20),
    (20, "bip01 l upperarm", 25),
    (25, "bip01 l forearm", 33),
    (33, "bip01 l hand", None),
    (16, "bip01 r clavicle", 22),
    (22, "bip01 r upperarm", 28),
    (28, "bip01 r forearm", 36),
    (36, "bip01 r hand", None),
    (2, "bip01 l thigh", 6),
    (6, "bip01 l calf", 11),
    (11, "bip01 l foot", None),
    (3, "bip01 r thigh", 8),
    (8, "bip01 r calf", 15),
    (15, "bip01 r foot", None),
)

# A leaf joint - the head, a hand, a foot - has no joint beyond it, so its own
# geometry would fall to the bone above it and the helmet would ride the neck.
# Each leaf carries a cap along its own bone, as long as the geometry nearest
# that joint actually reaches: measured from the mesh, not guessed.
BODY_FIT_INFLUENCES = 4

# A shell bigger than this is skin, not a plate: the avatar's own body mesh is
# one shell and has to fold at its joints. Everything smaller - a pauldron, a
# bracer, a boot - is one piece of armour, and one piece of armour rides one
# bone whole, so it cannot bend, tear or shear.
SHELL_SINGLE_BONE_MAX = 600

# Plates closer together than this touch: they are one piece of armour in two
# shells, a pad and the strap under it. Touching plates move together, so the
# one that picked the wrong bone is the one that changes, not the many.
PLATE_TOUCH = 3.0

# Rounds of neighbour averaging the FABRIC's own blend gets before the bind pose
# is applied. A cliff between two vertices of one sleeve - one at 0.85 collar and
# its neighbour at 0.85 arm - tears the edge between them when the arms come
# down. Two rounds inside each shell remove the cliff. Plates are not averaged:
# a plate rides one bone, so its vertices have nothing to average.
FABRIC_SMOOTHING = 4

# The joints whose geometry is a limb: an upper arm, a forearm, a hand, a
# thigh, a calf, a foot. These are scaled by their own stretch so the limb keeps
# its girth when the bone has to reach further than the item's does.
LIMB_UNIFORM = {2, 3, 6, 8, 11, 15, 20, 22, 25, 28, 33, 36}

# The range a joint's geometry may be stretched about its anchor. The anchors
# are exact, so this only softens the shear between a short Halo bone and the
# longer item bone beside it.
FIT_STRETCH_MIN = 0.8
FIT_STRETCH_MAX = 1.6


def halo_point(joint, fit=1.0):
    """One of the avatar's joints, in Halo's axes and units.

    ``to_halo_space`` maps (x, y, z) to (z, x, y) and scales by the fit, and the
    source joints have to be carried the same way or the fit would compare two
    different spaces - the same mistake that once bound every NXE item to the
    joints nearest the floor.
    """
    _parent, x, y, z = joint[:4]
    scale = HALO_UNITS_PER_METRE * fit
    return (z * scale, x * scale, y * scale)


def fit_unit(vector):
    size = math.sqrt(sum(value * value for value in vector))
    if size <= 1e-9:
        return None
    return tuple(value / size for value in vector)


def fit_length(vector):
    return math.sqrt(sum(value * value for value in vector))


def fit_between(first, second):
    return tuple(second[i] - first[i] for i in range(3))


def fit_shift(point, offset):
    return tuple(point[i] + offset[i] for i in range(3))


def fit_turn(first, second):
    """The 3x3 turn that carries one direction onto another."""
    a, b = fit_unit(first), fit_unit(second)
    if a is None or b is None:
        return ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
    dot = max(-1.0, min(1.0, sum(a[i] * b[i] for i in range(3))))
    if dot > 1.0 - 1e-9:
        return ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
    if dot < -1.0 + 1e-9:
        # Opposite directions: any axis square to `a` gives the same half turn.
        helper = (1.0, 0.0, 0.0) if abs(a[0]) < 0.9 else (0.0, 1.0, 0.0)
        axis = fit_unit((a[1] * helper[2] - a[2] * helper[1],
                         a[2] * helper[0] - a[0] * helper[2],
                         a[0] * helper[1] - a[1] * helper[0]))
        angle = math.pi
    else:
        axis = fit_unit((a[1] * b[2] - a[2] * b[1],
                         a[2] * b[0] - a[0] * b[2],
                         a[0] * b[1] - a[1] * b[0]))
        angle = math.acos(dot)
    x, y, z = axis
    cosine, sine = math.cos(angle), math.sin(angle)
    other = 1.0 - cosine
    return ((other * x * x + cosine, other * x * y - sine * z,
             other * x * z + sine * y),
            (other * x * y + sine * z, other * y * y + cosine,
             other * y * z - sine * x),
            (other * x * z - sine * y, other * y * z + sine * x,
             other * z * z + cosine))


def fit_turned(turn, point):
    return tuple(sum(turn[row][column] * point[column] for column in range(3))
                 for row in range(3))


def fit_gap(point, first, second):
    """Distance from a point to a segment, in plain numbers."""
    along = fit_between(first, second)
    length_sq = sum(value * value for value in along)
    if length_sq < 1e-9:
        return fit_length(fit_between(first, point))
    offset = fit_between(first, point)
    factor = max(0.0, min(1.0, sum(offset[i] * along[i] for i in range(3)) / length_sq))
    return fit_length(fit_between(
        point, fit_shift(first, tuple(value * factor for value in along))))


def fit_average_turn(pairs):
    """The one rotation a weighted set of rotations averages to.

    Averaging the turned *points* of two bones is what drags a shoulder inside
    out: two positions 79 degrees apart average to a point off the surface, and
    the band between them tears. Rotations average properly through their
    quaternions, so the result is a real rotation - an orthonormal turn - and the
    vertex that rides it keeps its own distance from the joint.
    """
    total = sum(weight for _turn, weight in pairs) or 1.0
    mixed = [0.0, 0.0, 0.0, 0.0]
    for turn, weight in pairs:
        quat = Matrix(turn).to_quaternion()
        value = [quat.w, quat.x, quat.y, quat.z]
        # q and -q are the same rotation, so each one has to be put in the same
        # hemisphere before they are added. Aligning to the first of the pair
        # instead made the answer depend on the order the bones happened to be
        # in: two vertices of one shoulder, weighted the same, could average to
        # opposite turns and tear the edge between them nine times its length.
        if value[0] < 0.0:
            value = [-part for part in value]
        for step in range(4):
            mixed[step] += (weight / total) * value[step]
    length = math.sqrt(sum(part * part for part in mixed))
    if length < 1e-9:
        return ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
    quat = Quaternion([part / length for part in mixed])
    matrix = quat.to_matrix()
    return tuple(tuple(matrix[row][column] for column in range(3))
                 for row in range(3))


def body_fit_plan(armature, fit=1.0, points=None):
    """Where each joint is now, where its bone is, and the turn between them.

    ``points`` are the mesh's own vertices, in the same space; they are only
    used to measure how far a leaf joint's geometry reaches, so a head can own
    its helmet instead of handing it to the neck.
    """
    if not armature or not armature.data.bones:
        return []
    matrix = armature.matrix_world
    plan = []
    for nxe, bone_name, beyond in BODY_JOINTS:
        bone = armature.data.bones.get(bone_name)
        if bone is None:
            return []
        plan.append({"joint": nxe, "bone": bone_name, "beyond": beyond,
                     "source": halo_point(NXE_JOINTS[nxe], fit),
                     "target": tuple(matrix @ bone.head_local), "turn": None,
                     "axis": None, "axial": None, "cap": 0.0})
    by_joint = {entry["joint"]: entry for entry in plan}
    for entry in plan:
        beyond = entry["beyond"]
        if beyond is None or beyond not in by_joint:
            continue
        first = fit_between(entry["source"], by_joint[beyond]["source"])
        second = fit_between(entry["target"], by_joint[beyond]["target"])
        entry["turn"] = fit_turn(first, second)
        entry["axis"] = fit_unit(first)
        if entry["axis"] is not None and fit_length(first) > 1e-9:
            # How much longer Halo's bone is than the item's. This is what
            # carries a joint onto the *next* joint's bone rather than only onto
            # its own, and it is why a short avatar's elbows and knees land on
            # Halo's: without it every joint stops at its own bone and the one
            # past it misses by the difference in length.
            entry["axial"] = fit_length(second) / fit_length(first)
    # A leaf follows the bone it ends, so a glove or a boot keeps the angle it
    # was modelled at instead of being stood on end by its own bone's direction.
    for leaf, above in ((33, 25), (36, 28), (11, 6), (15, 8)):
        if leaf in by_joint and above in by_joint:
            by_joint[leaf]["turn"] = by_joint[above]["turn"]
    # The forearm follows the upper arm, and only the upper arm's turn is used
    # for the pair. Halo's arms hang straight in its bind pose, so the mesh's do
    # too: each bone turned by its own direction would bend the elbow by however
    # much the avatar's forearm and Halo's forearm disagree, and that kink is
    # baked in for good. The elbow then bends only when an animation bends it,
    # which is the only place an elbow may bend.
    for forearm, upper in ((25, 20), (28, 22)):
        if forearm in by_joint and upper in by_joint:
            by_joint[forearm]["turn"] = by_joint[upper]["turn"]
    # The same for the leg: a leg bends at the knee, and only there. A calf
    # turned by its own direction against Halo's bends the knee in the bind pose
    # by however much the two disagree, and the bend is baked in. The foot
    # already follows the calf, so the whole leg then comes down in one piece
    # from the hip and the knee stays as straight as the item drew it.
    for calf, thigh in ((6, 2), (8, 3)):
        if calf in by_joint and thigh in by_joint:
            by_joint[calf]["turn"] = by_joint[thigh]["turn"]
    # A turn that is inherited has to be taken about the joint it belongs to.
    # The same rotation about a different pivot is not the same movement: it is
    # that rotation plus a slide of (R - I) times the distance between the two
    # pivots, which for this arm is 1.25 times an 10.9-unit upper arm - 13 units
    # of jump at the elbow, and that jump is what a kinked elbow looks like in
    # the mesh. So a joint that rides its parent's turn also rides its parent's
    # pivot, and the whole limb comes down as one rigid piece about the shoulder
    # or the hip, exactly as it was modelled.
    for entry in plan:
        entry["pivot"] = entry["source"]
    for below, above in ((25, 20), (28, 22), (6, 2), (8, 3),
                         (33, 25), (36, 28), (11, 6), (15, 8)):
        if below in by_joint and above in by_joint:
            by_joint[below]["pivot"] = by_joint[above]["source"]
    if 19 in by_joint:
        by_joint[19]["turn"] = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
    for entry in plan:
        if entry["turn"] is None:
            entry["turn"] = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
    leaves = [entry for entry in plan if entry["beyond"] is None]
    for entry in leaves:
        entry["cap"] = 0.0
    for point in points or []:
        nearest = min(plan, key=lambda entry: fit_length(
            fit_between(entry["source"], point)))
        if nearest["beyond"] is None:
            nearest["cap"] = max(nearest["cap"], fit_length(
                fit_between(nearest["source"], point)))
    return plan


def fit_body_points(points, edges, plan):
    """Carry every point onto the plan's bones. Returns (points, scale, worst).

    Each point is shared between the four nearest joints rather than split at
    the nearest one, so the mesh between two joints bends instead of stepping
    from one bone's frame to another's - which is what a shoulder does when the
    arm comes down from the item's pose into Halo's.
    """
    by_joint = {entry["joint"]: entry for entry in plan}
    head = by_joint.get(19)
    scale = 1.0
    if head and abs(head["source"][2]) > 1e-9:
        # The item's own head joint goes on Halo's head node. That is the one
        # size the two skeletons share - one body's head on another's - so the
        # armour keeps the scale it was drawn at while its joints are moved.
        scale = head["target"][2] / head["source"][2]
    segments = {}
    for entry in plan:
        if entry["beyond"] is not None and entry["beyond"] in by_joint:
            segments[entry["joint"]] = (entry["source"],
                                        by_joint[entry["beyond"]]["source"])
            continue
        parent = NXE_JOINTS[entry["joint"]][0]
        direction = None
        if 0 <= parent < len(NXE_JOINTS):
            direction = fit_unit(fit_between(halo_point(NXE_JOINTS[parent]),
                                             entry["source"]))
        if direction is None:
            direction = (0.0, 0.0, 1.0)
        length = max(entry["cap"], 1e-3)
        segments[entry["joint"]] = (
            entry["source"],
            fit_shift(entry["source"], tuple(value * length
                                             for value in direction)))

    def weights_of(point):
        scored = sorted(((fit_gap(point, first, second), joint)
                         for joint, (first, second) in segments.items()),
                        key=lambda pair: pair[0])[:BODY_FIT_INFLUENCES]
        shares = [(joint, 1.0 / max(gap, 1e-4) ** 2) for gap, joint in scored]
        total = sum(share for _joint, share in shares) or 1.0
        return [(joint, share / total) for joint, share in shares]

    placed = []
    for point in points:
        moved = [0.0, 0.0, 0.0]
        for joint, share in weights_of(point):
            entry = by_joint[joint]
            offset = fit_between(entry["source"], point)
            bone_axis = entry["axis"] or (0.0, 0.0, 1.0)
            axial = entry["axial"] if entry["axial"] is not None else scale
            along = sum(offset[i] * bone_axis[i] for i in range(3))
            stretched = tuple(bone_axis[i] * along * axial
                              + (offset[i] - bone_axis[i] * along) * scale
                              for i in range(3))
            turned = fit_turned(entry["turn"], stretched)
            for axis in range(3):
                moved[axis] += share * (entry["target"][axis] + turned[axis])
        placed.append(tuple(moved))
    # The soles belong on the floor. A joint is placed on its bone and the boot
    # hangs below the ankle, so the lowest vertex can land a centimetre under.
    low = min(point[2] for point in placed)
    if low < 0.0:
        placed = [(x, y, z - low) for x, y, z in placed]
    worst = 1.0
    for first, second in edges:
        was = fit_length(fit_between(points[first], points[second]))
        if was <= 1e-6:
            continue
        now = fit_length(fit_between(placed[first], placed[second]))
        worst = max(worst, now / was, was / max(now, 1e-6))
    return placed, scale, worst


def shell_direction(points):
    """The direction a plate is longest in, by variance, or None if it is round.

    A sleeve is long one way and thin the other two, so the axis of the plate's
    own geometry is the arm's axis in whatever pose the item was drawn in. That
    is the only way to know an arm is out to the side without trusting a plan
    computed from the skeleton the arm has to end up on - the plan's turn, on a
    rig that is already Halo's, is the identity, which is how a "standing" build
    kept its arms in the air.
    """
    if len(points) < 8:
        return None
    middle = [sum(point[axis] for point in points) / len(points)
              for axis in range(3)]
    spread = [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
    for point in points:
        offset = [point[axis] - middle[axis] for axis in range(3)]
        for row in range(3):
            for column in range(3):
                spread[row][column] += offset[row] * offset[column]
    direction = [1.0, 0.0, 0.0]
    for _ in range(12):
        moved = [sum(spread[row][column] * direction[column]
                     for column in range(3)) for row in range(3)]
        length = sum(value * value for value in moved) ** 0.5
        if length < 1e-9:
            return None
        direction = [value / length for value in moved]
    longest = sum(direction[row] * spread[row][column] * direction[column]
                  for row in range(3) for column in range(3))
    other = max(sum(spread[row][column] for column in range(3)) - longest, 1e-9)
    # A plate as wide as it is long has no axis worth turning by.
    if longest < other * 1.4:
        return None
    return tuple(direction)


def segment_distance(point, start_point, end_point):
    """How far a point is from a bone's own segment, not from its infinite line."""
    span = fit_between(start_point, end_point)
    length = fit_length(span)
    if length < 1e-9:
        return fit_length(fit_between(start_point, point))
    step = fit_unit(span)
    offset = fit_between(start_point, point)
    along = sum(offset[axis] * step[axis] for axis in range(3))
    along = max(0.0, min(length, along))
    nearest = tuple(start_point[axis] + step[axis] * along for axis in range(3))
    return fit_length(fit_between(nearest, point))


def shift_of(matrix, anchor, centre):
    """The shift that goes with a 3x3 map: p -> matrix * (p - centre) + anchor."""
    return tuple(anchor[row] - sum(matrix[row][column] * centre[column]
                                   for column in range(3)) for row in range(3))


def stand_in_halo_pose(object_data, armature, fit=1.0, limbs=False,
                       avatar=None, avatar_fit=None):
    """Stand a whole body in the pose Halo's own skeleton holds - HEK's bind.

    A Halo CE gbxmodel has no bind pose in it. ``tool.exe`` bakes every vertex
    into the frame of the node it rides, using the .jms's own node block, and
    the engine then draws it with whatever pose its animation graph gives that
    node. So the mesh and the node block have to be the same pose, and only one
    of the two is free: Halo's 19-node block is the one the retail graph drives
    and the one this rig ships, with its arms hanging 79 degrees down from the
    avatar's T-pose. The mesh is what has to move, and this is the pass that
    moves it. Left as authored the suit is a T-pose bound to arms-down bones:
    in game the arms stay out at the sides and the boots sit under the origin,
    which is the biped standing in the ground with its arms out.

    Every vertex is carried by the weights it rides - the same blend the game
    will use on it - so a plate that the weighting splits between the collar and
    the arm bends with both instead of being flung by one. Those weights are
    averaged over each shell's own edges first: a cliff between two vertices of
    one plate, one at 0.85 collar and its neighbour at 0.85 arm, is what smears
    a pad across two bones, and smoothing inside a shell removes the cliff
    without mixing one plate's weights into another's.

    Each bone's transform is a turn about the item's own joint, from the item's
    segment to the bone's: limb lengths, girth and proportions stay the
    avatar's, and nothing is stretched along a bone unless ``limbs`` asks for
    it. The head's own turn is the identity, so the helmet, the face and the
    neck keep exactly the place the file drew them in.

    ``avatar`` and ``avatar_fit`` are the ported avatar's own vertices and the
    factor that part was scaled by: the item is scaled by ``fit`` and the avatar
    by the factor that makes it exactly Halo's height, so each part has its own
    joint table in its own space and gets its own plan. Without that the avatar
    would be turned about joints at the item's scale and land off its own body.

    Returns a report dict, or None when the rig is not the biped this table is
    written for.
    """
    mesh = object_data.data
    points = [tuple(vertex.co) for vertex in mesh.vertices]
    if not points:
        return None
    avatar = set(avatar or ())
    item_points = [point for index, point in enumerate(points) if index not in avatar]
    plan = body_fit_plan(armature, fit, item_points)
    if not plan:
        return None
    plans = {fit: {entry["bone"]: entry for entry in plan}}
    if avatar and avatar_fit and abs(avatar_fit - fit) > 1e-9:
        theirs = body_fit_plan(armature, avatar_fit,
                               [points[index] for index in sorted(avatar)])
        if theirs:
            plans[avatar_fit] = {entry["bone"]: entry for entry in theirs}
    by_bone = plans[fit]
    # One bone per vertex - the same rides the shipped weights will carry, so the
    # pose this pass bakes is exactly the pose the game will stand the model in.
    # Turning a plate whole means no edge inside it changes length: the mesh does
    # not change shape when the arms come down. Blending two bones here instead
    # (the old pass did, twice-smoothed) is what folded the elbows.
    rides = single_bone_rides(object_data, armature)
    # Fabric folds, but only where the skeleton has a joint to fold at: a blend
    # along the middle of a forearm would bend the mesh where no animation ever
    # expects it, and no weapon pose could look right.
    weights = band_weights(object_data, armature)

    def turned_point(entry, point):
        """One bone's turn of one point, about the item's own joint."""
        if limbs:
            # The joint itself also goes onto the bone, and the limb is
            # lengthened along it: the hand at Halo's fingertips, paid for in
            # limb length. Not shipped; --fit-limbs asks for it.
            anchor = tuple(entry["target"])
            offset = fit_between(entry["source"], point)
            axis = entry.get("axis")
            if axis is not None:
                axial = entry.get("axial") or 1.0
                axial = max(FIT_STRETCH_MIN, min(FIT_STRETCH_MAX, axial))
                along = sum(offset[step] * axis[step] for step in range(3))
                offset = tuple(offset[step] + axis[step] * along * (axial - 1.0)
                               for step in range(3))
        else:
            # Turned about the item's own joint, which stays where the avatar
            # put it: that is what leaves every limb its own length. A joint
            # that inherited its parent's turn turns about the parent's joint
            # instead, so the limb is one rigid piece and no seam jumps.
            anchor = tuple(entry.get("pivot") or entry["source"])
            offset = fit_between(anchor, point)
        turned = fit_turned(entry["turn"], offset)
        return tuple(anchor[step] + turned[step] for step in range(3))

    # Fabric keeps a blend, and a blend needs no cliff in it: two neighbouring
    # vertices of one sleeve at 0.85 collar and 0.85 arm turn completely
    # differently, and the edge between them tears. Averaging the blend over
    # each vertex's neighbours first removes the cliff before the turn is taken.
    # Plates are not in this map at all - they are rigid, so there is nothing to
    # smooth and no way to smear one plate's weights into another's.
    fabric = {}
    for index, share in weights.items():
        if rides.get(index) != "":
            continue
        kept = {name: weight for name, weight in share.items()
                if name in by_bone and weight > 0.0}
        total = sum(kept.values())
        if total > 0.0:
            fabric[index] = {name: weight / total
                             for name, weight in kept.items()}
    neighbours = [[] for _ in points]
    for edge in mesh.edges:
        first, second = edge.vertices
        neighbours[first].append(second)
        neighbours[second].append(first)
    for _ in range(FABRIC_SMOOTHING):
        smoothed = {}
        for index, share in fabric.items():
            mixed = dict(share)
            for other in neighbours[index]:
                if other in fabric:
                    for name, weight in fabric[other].items():
                        mixed[name] = mixed.get(name, 0.0) + weight
            total = sum(mixed.values()) or 1.0
            smoothed[index] = {name: weight / total
                               for name, weight in mixed.items()}
        fabric = smoothed

    placed = []
    plate_verts = 0
    for index, point in enumerate(points):
        where = (plans.get(avatar_fit) or by_bone) if index in avatar else by_bone
        bone = rides.get(index)
        if bone:
            # A plate: one bone, one rigid turn. Every edge inside it keeps its
            # length exactly - the plate cannot bend, tear or shear.
            entry = where.get(bone)
            placed.append(turned_point(entry, point) if entry else point)
            plate_verts += 1
            continue
        # Fabric: it folds, so it keeps its blend - the one place two bones
        # meet on a vertex, and the only place a joint can bend. Only bones
        # whose own joint is near the vertex are blended, though: a chest point
        # carrying a tenth of the hand would be swung about the wrist's joint
        # and tear the chest in half. The nearest bone is always kept, so a
        # vertex on the surface of a limb still follows that limb.
        # Which bones carry it is the skinning's answer, not a distance guess:
        # keeping only the bones whose joint happens to be nearest threw away
        # the upper arm on a shoulder vertex whose forearm joint was nearer, and
        # the edge to its neighbour tore nine times its length. Only weights too
        # small to matter are dropped.
        share = {name: weight for name, weight in (fabric.get(index) or {}).items()
                 if name in where and weight >= 0.02}
        total = sum(share.values())
        if total <= 0.0:
            # Every bone this vertex was skinned to is outside the pose's plan.
            # Leaving it where it is would leave it in the T-pose while the
            # surface beside it comes down - a tear many times its own length -
            # so the nearest joint in the plan carries it, rigidly.
            near = min(where.values(),
                       key=lambda entry: fit_length(
                           fit_between(entry["source"], point))) if where else None
            placed.append(turned_point(near, point) if near else point)
            continue
        # Blending the blended *positions* is what crushed the shoulder: two
        # turns 79 degrees apart average into a point pulled off the surface, and
        # a band of them tears x13. The turns are averaged instead - one real
        # rotation, taken about one anchor - so the vertex still moves rigidly
        # and its neighbours move almost the same way. The band then folds
        # instead of tearing, and every plate around it keeps its exact shape.
        # A blended vertex has to turn about the pivot of the turn it is given.
        # A forearm that inherited the upper arm's turn turns about the
        # shoulder, so a sleeve vertex weighted half to the forearm and half to
        # the upper arm must turn about the shoulder too - otherwise it is the
        # same angle about a point half way down the upper arm, which is a
        # different movement, and the sleeve steps away from the plates that
        # ride the arm at the seam between them.
        anchor = [0.0, 0.0, 0.0]
        for name, weight in share.items():
            source = where[name].get("pivot") or where[name]["source"]
            for step in range(3):
                anchor[step] += (weight / total) * source[step]
        turn = fit_average_turn([(where[name]["turn"], weight / total)
                                 for name, weight in share.items()])
        turned = fit_turned(turn, fit_between(tuple(anchor), point))
        placed.append(tuple(anchor[step] + turned[step] for step in range(3)))
    worst = 1.0
    worst_plate = 1.0
    worst_long = 1.0
    worst_same = 1.0
    plate_edges = 0
    for edge in mesh.edges:
        first, second = edge.vertices
        was = fit_length(fit_between(points[first], points[second]))
        if was <= 1e-6:
            continue
        now = fit_length(fit_between(placed[first], placed[second]))
        if now <= 1e-6:
            continue
        ratio = max(now / was, was / now)
        worst = max(worst, ratio)
        # A sliver of a triangle can read x26 on a change no eye could see, so
        # the number that matters is the one over a centimetre of edge.
        if was >= 0.01:
            worst_long = max(worst_long, ratio)
            # Two parts of this model were scaled by different factors - the
            # avatar to the biped's height, the item by the factor it was
            # authored for - so an edge crossing between them carries that
            # difference however well it is posed. Measuring inside one part
            # separates the pose's own tearing from that seam.
            if (first in avatar) == (second in avatar):
                worst_same = max(worst_same, ratio)

        # An edge with both ends on the same plate rides one bone at both ends,
        # so its length cannot change. Measuring it separately is the proof: this
        # number must be 1.00 to two decimals, and it is the shape guarantee.
        if rides.get(first) and rides.get(first) == rides.get(second):
            plate_edges += 1
            worst_plate = max(worst_plate, ratio)
    # Does the arm come down as one piece? The arm is one rigid turn about the
    # shoulder, so every vertex on it - plate or fabric - must land where that
    # turn puts it. This measures each one against that single answer and names
    # the worst, so a kink becomes a number about a named bone instead of a look.
    for side in ("l", "r"):
        root = by_bone.get("bip01 %s upperarm" % side)
        if root is None:
            continue
        chain = set(["bip01 %s %s" % (side, part)
                     for part in ("upperarm", "forearm", "hand")])
        pivot = Vector(root.get("pivot") or root["source"])
        turn = root["turn"]
        far = {}
        count = {}
        for index, point in enumerate(points):
            mine = rides.get(index)
            if mine:
                if mine not in chain:
                    continue
            else:
                share = weights.get(index) or {}
                if not share or set(share) - chain:
                    continue
                mine, weight = max(share.items(), key=lambda pair: pair[1])
                if weight < 0.9:
                    continue
            offset = fit_between(tuple(pivot), point)
            want = Vector(tuple(pivot)) + Vector(fit_turned(turn, offset))
            away = (Vector(placed[index]) - want).length
            far[mine] = max(far.get(mine, 0.0), away)
            count[mine] = count.get(mine, 0) + 1
        if far:
            log("%s: arm %s, how far the armour sits from the arm's own rigid "
                "turn about the shoulder - %s"
                % (object_data.name, side,
                   ", ".join("%s %.1f over %d"
                             % (name.replace("bip01 %s " % side, "").replace(
                                 "bip01 ", ""), far[name], count[name])
                             for name in sorted(far))))

    # Is every joint inside the mesh? Bone *lengths* are Blender's business - a
    # Halo model stores where a node is, never how long its bone is, so a long
    # foot bone drawn below a boot moves nothing in game. What does matter is
    # where the joints are: a weapon hangs off the hand node, the boot stands on
    # the foot node, and a joint outside its own armour is a part that will be
    # placed from the wrong place. So each joint is measured to the nearest
    # surface of the mesh that rides it.
    matrix = armature.matrix_world
    world = object_data.matrix_world
    skin = [world @ Vector(point) for point in placed]
    joints = []
    for side in ("l", "r"):
        for part in ("upperarm", "forearm", "hand",
                     "thigh", "calf", "foot"):
            name = "bip01 %s %s" % (side, part)
            bone = armature.data.bones.get(name)
            if bone is None:
                continue
            joint = matrix @ bone.head_local
            nearest = min((point - joint).length for point in skin) if skin else 0.0
            joints.append((name, nearest))
    for name, nearest in joints:
        if nearest > 6.0:
            log("%s: %s has no surface within %.1f units - that joint is outside "
                "the mesh" % (object_data.name, name, nearest))
    if joints:
        log("%s: every joint has mesh around it - %s"
            % (object_data.name,
               ", ".join("%s %.1f" % (name.replace("bip01 ", ""), nearest)
                         for name, nearest in joints)))

    # A plate the pose left behind shows up as a gap that was not there: two
    # plates that touched now do not. That is measured from the model's own
    # geometry, not supposed, and it is the one number that says whether a pad
    # came down with the arm it belongs to.
    shells = []
    for piece in shell_faces(mesh):
        indexes = set()
        for polygon in piece:
            indexes.update(polygon.vertices)
        if not indexes:
            continue
        before = Vector((0.0, 0.0, 0.0))
        after = Vector((0.0, 0.0, 0.0))
        for index in indexes:
            before += Vector(points[index])
            after += Vector(placed[index])
        shells.append((before / len(indexes), after / len(indexes)))
    worst_was = worst_now = None
    if len(shells) > 1:
        tree = kdtree.KDTree(len(shells))
        for number, (before, _after) in enumerate(shells):
            tree.insert(before, number)
        tree.balance()
        touching = set()
        for number, (before, _after) in enumerate(shells):
            _co, near, _gap = tree.find(before)
            if near != number:
                touching.add((min(number, near), max(number, near)))
        for one, two in touching:
            was = (shells[one][0] - shells[two][0]).length
            now = (shells[one][1] - shells[two][1]).length
            if was > PLATE_TOUCH:
                continue
            if worst_now is None or now - was > worst_now - worst_was:
                worst_was, worst_now = was, now
    if worst_now is not None and worst_now - worst_was > 0.5:
        log("%s: a gap opened between two plates that touched - %.2f units "
            "became %.2f. One of them did not move with the other."
            % (object_data.name, worst_was, worst_now))
    if worst_now is not None:
        log("%s: worst gap between two touching plates: %.2f units before, "
            "%.2f after" % (object_data.name, worst_was, worst_now))

    span_before = max(abs(point[1]) for point in points)
    span_after = max(abs(point[1]) for point in placed)
    for vertex, point in zip(mesh.vertices, placed):
        vertex.co = point
    mesh.update()
    # The soles belong on the floor before this returns: the pose turns the feet
    # with their segment, and a boot that stood on z = 0 in the avatar's pose can
    # end under it once it is stood in Halo's. The model is placed by its origin,
    # so a mesh below that origin is drawn in the ground.
    lowest = min(point[2] for point in placed)
    if abs(lowest) > 0.01:
        for vertex in object_data.data.vertices:
            vertex.co.z -= lowest
        object_data.data.update()
        placed = [(x, y, z - lowest) for x, y, z in placed]
        log("soles lifted %.2f units onto the floor after the pose" % -lowest)
        lowest = 0.0
    tallest = max(point[2] for point in placed)
    line = ("%d joints, %d plate vertex(es) on one bone each, worst plate edge "
            "x%.2f over %d edge(s), worst edge within one part over 1 cm x%.2f "
            "(anywhere x%.2f), arms in from %.1f to %.1f on y, %.2f m tall, "
            "soles at %.2f"
            % (len(plan), plate_verts, worst_plate, plate_edges, worst_same,
               worst_long, span_before, span_after,
               tallest / HALO_UNITS_PER_METRE, lowest))
    log("stood %s in Halo's rest pose: %s" % (object_data.name, line))
    return {"worst": worst, "worst_plate": worst_plate,
            "height": tallest / HALO_UNITS_PER_METRE,
            "arms_before": span_before, "arms_after": span_after,
            "lines": ["biped pose : " + line]}


def retarget_body(object_data, armature, fit=1.0):
    """Fit a whole body's mesh onto the biped, joint by joint.

    A garment is placed by its own edge and grown by one uniform factor, which
    is right for a hat or a tee: it is worn on a body and only has to reach the
    same part of it. A body is different. The armour has the avatar's skeleton
    inside it, and every joint of that skeleton has to end up on the matching
    bone, or the bones animate something the armour is not.

    Returns a report dict, or None when the rig is not the biped this table is
    written for.
    """
    mesh = object_data.data
    points = [tuple(vertex.co) for vertex in mesh.vertices]
    if not points:
        return None
    plan = body_fit_plan(armature, fit, points)
    if not plan:
        return None
    edges = [tuple(edge.vertices) for edge in mesh.edges]
    placed, scale, worst = fit_body_points(points, edges, plan)
    for vertex, point in zip(mesh.vertices, placed):
        vertex.co = point
    mesh.update()
    tallest = max(point[2] for point in placed)
    line = ("%d joints carried onto their bones, x%.3f, %.2f m tall, "
            "worst edge x%.2f" % (len(plan), scale,
                                  tallest / HALO_UNITS_PER_METRE, worst))
    log("fitted %s to the biped's bones: %s" % (object_data.name, line))
    return {"scale": scale, "height": tallest / HALO_UNITS_PER_METRE,
            "worst": worst, "joints": len(plan), "lines": ["biped fit : " + line]}


def rig_audit(object_data, armature):
    """Check that every vertex rides a bone, and say so in the report.

    A model that ships with a vertex no bone claims is unrigged in Halo however
    good it looks in Blender: tool.exe writes the weights it is given, and a
    vertex with none collapses to the model's origin the moment the biped moves.
    The check is cheap, so every item gets it, and it is written where the user
    can read it rather than left to be discovered in game.
    """
    bones = {bone.name for bone in armature.data.bones} if armature else set()
    groups = {group.index: group.name for group in object_data.vertex_groups}
    total = len(object_data.data.vertices)
    loose = 0
    weakest = 1.0
    on_bone = set()
    for vertex in object_data.data.vertices:
        ride = 0.0
        for entry in vertex.groups:
            name = groups.get(entry.group)
            if name in bones and entry.weight > 0.0:
                ride += entry.weight
                on_bone.add(name)
        if ride <= 0.0001:
            loose += 1
        weakest = min(weakest, ride)
    line = ("%d vertices on %d bone(s), %d unweighted, lightest weight sum "
            "%.3f" % (total, len(on_bone), loose, weakest if total else 0.0))
    if loose:
        log("rig: %s - %d of %d vertices ride no bone, so the model would be "
            "unrigged in Halo" % (object_data.name, loose, total))
    else:
        log("rig: %s - %s" % (object_data.name, line))
    return line


def rebind(object_data, armature, rigid=False):
    """Skin again from scratch, so a re-fitted mesh does not keep old weights."""
    for group in list(object_data.vertex_groups):
        object_data.vertex_groups.remove(group)
    for modifier in list(object_data.modifiers):
        if modifier.type == "ARMATURE":
            object_data.modifiers.remove(modifier)
    return skin(object_data, armature, rigid=rigid)


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


def hand_item(prop, binding):
    """The biped bone a hand item rides, or None when it is not a hand item.

    Only a prop rides one bone. Deciding this from the binding line alone takes
    any garment whose top-weighted bone happens to be an arm - a tee's shoulders
    are on the upper arms - and puts the whole shirt on the first-person hand,
    rigid, as if it were a ring.
    """
    if not prop:
        return None
    return hand_bone(binding or "")


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


def arm_share(weights):
    """How much of one vertex belongs to the arms proper, 0 to 1.

    Shoulder armour is judged apart from this, in arm_pieces: a pauldron's
    weight is on a clavicle, and counting that here would count a chest plate's
    corners too, which is how a torso shell got taken for an arm.
    """
    arm = sum(weight for name, weight in weights.items() if name in ARM_BONES)
    total = sum(weights.values())
    return arm / total if total > 0.0 else 0.0


def principal_axes(points):
    """A cloud's own three directions, widest first, and its middle.

    Each direction is found by power iteration on the covariance and then taken
    out of it before the next, which is what keeps them apart: an arm modelled
    exactly along an axis is an eigenvector of its own covariance, so starting
    each search from the widest direction left - not from +X - is the only way
    to find the second and third at all.

    Returns (axes, middle), where axes is a list of (spread, unit direction)
    pairs in descending order, or (None, middle) for a cloud too small or too
    round to have a direction.
    """
    count = len(points)
    if count < 3:
        return None, None
    centre = [0.0, 0.0, 0.0]
    for point in points:
        for axis in range(3):
            centre[axis] += point[axis]
    centre = [value / count for value in centre]
    left = [[0.0] * 3 for _ in range(3)]
    for point in points:
        delta = [point[axis] - centre[axis] for axis in range(3)]
        for row in range(3):
            for col in range(3):
                left[row][col] += delta[row] * delta[col]
    axes = []
    for _ in range(3):
        best = max(range(3), key=lambda i: left[i][i])
        axis = [0.0, 0.0, 0.0]
        axis[best] = 1.0
        for _step in range(64):
            out = [sum(left[row][col] * axis[col] for col in range(3))
                   for row in range(3)]
            length = math.sqrt(sum(value * value for value in out))
            if length < 1e-9:
                return (axes or None), centre
            axis = [value / length for value in out]
        spread = sum(axis[row] * sum(left[row][col] * axis[col]
                                     for col in range(3))
                     for row in range(3))
        axes.append((spread, axis))
        for row in range(3):
            for col in range(3):
                left[row][col] -= spread * axis[row] * axis[col]
    return axes, centre


def arm_axis(points):
    """Which way one of the item's arms runs, judged from the mesh itself.

    The bones cannot answer this. An avatar item is modelled in the avatar's own
    pose, while the skeleton it is bound to can hold its arms somewhere else -
    the biped's arms hang, and Halo's first-person arms are held straight out.
    Asking the bones turned the sleeves to suit the bones rather than the body,
    which is what left the arms at the wrong angle. The mesh is what has to land
    on Halo's arm, so its own longest axis is the one to use: the sleeve's length
    dominates every other direction it has.
    """
    axes, centre = principal_axes(points)
    if not axes:
        return None, centre
    return axes[0][1], centre


def arm_direction(points):
    """Which way a sleeve points, from the middles of its two ends.

    The cloud's widest direction (arm_axis) is a sleeve's lean, but it is pulled
    by wherever the geometry is thickest: a flared cuff, a rolled sleeve or a
    shoulder pad swings it a degree or two off the line the arm runs, and a fit
    onto it stops that far short of Halo's arm - measured, 2.5 degrees, while
    reporting nothing left to do. The line from the middle of one end to the
    middle of the other is the arm's direction as a player sees it, and it does
    not care how the sleeve is shaped along the way, so that is what is fitted.
    """
    if len(points) < 12:
        return None
    # Bands taken along the sleeve's own length. Ordering them by distance from
    # the joint instead was tried and is not stable: an item's arm does not sit
    # where Halo's does, so "furthest from Halo's shoulder" is not the cuff, and
    # the direction it gave turned one side a quarter turn and left the sleeve
    # inside out.
    axis, _centre = arm_axis(points)
    if axis is None:
        return None
    along = [sum(point[i] * axis[i] for i in range(3)) for point in points]
    order = sorted(range(len(points)), key=lambda index: along[index])
    band = max(3, len(points) // 5)

    def middle(group):
        return [sum(points[index][axis_] for index in group) / len(group)
                for axis_ in range(3)]

    near = middle(order[:band])
    far = middle(order[-band:])
    direction = [far[i] - near[i] for i in range(3)]
    size = math.sqrt(sum(value * value for value in direction))
    if size < 1e-9:
        return None
    return [value / size for value in direction]


def hand_plane(points, axis):
    """Which way round a hand's flat lies: its palm's normal, across its arm.

    A hand is a flat thing, so its thinnest way is the palm's normal - and that
    is what a turn about the arm moves, so it is the whole answer to how far
    round the glove is worn. It has to be measured across the arm and not from
    the cloud as a whole: a thumb sticks out sideways from the fingers, and on
    a glove that thumb alone can tilt the cloud's own longest direction half a
    right angle away from the arm it hangs from. Everything along the arm is
    taken out first, leaving a flat cross-section whose narrow way is the palm's.

    Answers None for anything too round to have a flat - a mitten on a fist, or
    the end of a bare sleeve - because turning noise onto Halo's hand is worse
    than leaving the item's own roll alone.
    """
    if axis is None or len(points) < 8:
        return None
    across = []
    for point in points:
        along = sum(point[i] * axis[i] for i in range(3))
        across.append([point[i] - axis[i] * along for i in range(3)])
    axes, _centre = principal_axes(across)
    if not axes or len(axes) < 2:
        return None
    thin, wide = axes[1], axes[0]
    if thin[0] > 0.6 * wide[0]:
        return None
    return thin[1]


def alignment(axis, target):
    """The shortest turn taking one direction onto another, as a 3x3, row-major.

    A turn and nothing else: no twist is invented, so the arm keeps the way
    round it was modelled and only its direction changes. Bone rolls cannot be
    trusted for this - the biped's left hand is rolled a half turn against its
    forearm, so a frame built from the bone's rest matrix turned the glove inside
    out against the sleeve and tore the two apart.
    """
    def unit(values):
        length = math.sqrt(sum(value * value for value in values))
        if length < 1e-9:
            return None
        return [value / length for value in values]

    here, there = unit(axis), unit(target)
    if here is None or there is None:
        return None
    across = [here[1] * there[2] - here[2] * there[1],
              here[2] * there[0] - here[0] * there[2],
              here[0] * there[1] - here[1] * there[0]]
    facing = sum(left * right for left, right in zip(here, there))
    sine = math.sqrt(sum(value * value for value in across))
    if sine < 1e-9:
        if facing > 0.0:
            return (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)
        # Opposed: half a turn about any axis across them.
        aside = unit([1.0, 0.0, 0.0] if abs(here[0]) < 0.9 else [0.0, 1.0, 0.0])
        across = unit([here[1] * aside[2] - here[2] * aside[1],
                       here[2] * aside[0] - here[0] * aside[2],
                       here[0] * aside[1] - here[1] * aside[0]])
        x, y, z = across
        return (2 * x * x - 1, 2 * x * y, 2 * x * z,
                2 * y * x, 2 * y * y - 1, 2 * y * z,
                2 * z * x, 2 * z * y, 2 * z * z - 1)
    across = [value / sine for value in across]
    cross_product = [[0.0, -across[2], across[1]],
                     [across[2], 0.0, -across[0]],
                     [-across[1], across[0], 0.0]]
    turn = []
    for row in range(3):
        for col in range(3):
            square = sum(cross_product[row][mid] * cross_product[mid][col]
                         for mid in range(3))
            # `across` is a unit axis and `sine` its length, so the turn is
            # sin*K + (1-cos)*K*K. Dividing by sine twice as well as scaling by
            # it squared the error instead of cancelling it, and blew the arms up
            # to 1e15 units on an item whose arms were already straight out.
            turn.append((1.0 if row == col else 0.0)
                        + cross_product[row][col] * sine
                        + square * (1.0 - facing))
    return tuple(turn)


def turn_about(axis, angle):
    """A turn of `angle` radians about a unit axis, as a 3x3, row-major."""
    x, y, z = axis
    cosine, sine = math.cos(angle), math.sin(angle)
    rest = 1.0 - cosine
    return (cosine + x * x * rest, x * y * rest - z * sine,
            x * z * rest + y * sine,
            y * x * rest + z * sine, cosine + y * y * rest,
            y * z * rest - x * sine,
            z * x * rest - y * sine, z * y * rest + x * sine,
            cosine + z * z * rest)


def turn_product(left, right):
    """`left` applied after `right`, as a 3x3, row-major."""
    return tuple(sum(left[row * 3 + mid] * right[mid * 3 + col]
                     for mid in range(3))
                 for row in range(3) for col in range(3))


def turn_point(turn, point):
    """One turn applied to a direction."""
    return tuple(sum(turn[row * 3 + col] * point[col] for col in range(3))
                 for row in range(3))


def hand_twist(turn, axis, here, there):
    """How far a glove has to turn about its arm to lie in Halo's own hand.

    Both directions are taken across the arm, because that is all a turn about
    the arm can move: `here` is the glove's palm normal as the carry has already
    turned it, `there` is Halo's own hand's. The signed angle between them is
    the whole answer, and it moves nothing off the arm's line.
    """
    def across(vector):
        along = sum(vector[i] * axis[i] for i in range(3))
        value = [vector[i] - axis[i] * along for i in range(3)]
        length = math.sqrt(sum(entry * entry for entry in value))
        if length < 1e-9:
            return None
        return [entry / length for entry in value]

    held, want = across(turn_point(turn, here)), across(there)
    if held is None or want is None:
        return None
    cosine = sum(held[i] * want[i] for i in range(3))
    sine = sum(axis[i] * (held[(i + 1) % 3] * want[(i + 2) % 3]
                          - held[(i + 2) % 3] * want[(i + 1) % 3])
               for i in range(3))
    return math.atan2(sine, cosine)


def place_point(turn, start, finish, point):
    """Turn one point about `start`, then shift it so `start` lands on
    `finish`."""
    delta = [point[axis] - start[axis] for axis in range(3)]
    return tuple(turn[row * 3] * delta[0] + turn[row * 3 + 1] * delta[1]
                 + turn[row * 3 + 2] * delta[2] + finish[row]
                 for row in range(3))


def arm_joint(points, along, weights, first, second, fallback):
    """Where one arm bone hands over to the next, measured along the arm.

    A vertex the two bones share is skin at the joint, so the middle of those
    vertices is the joint. With hard weights - each vertex on one bone, as
    avatar items often are - there is no shared skin, and the middle of the gap
    between the two bones' vertices stands in.
    """
    shared = []
    nearer_first, nearer_second = [], []
    for t, per in zip(along, weights):
        one = per.get(first, 0.0)
        two = per.get(second, 0.0)
        if one > 0.0 and two > 0.0 and abs(one - two) <= 0.25 * (one + two):
            shared.append(t)
        elif one > 0.0 and two <= 0.0:
            nearer_first.append(t)
        elif two > 0.0 and one <= 0.0:
            nearer_second.append(t)
    if shared:
        return sum(shared) / len(shared)
    if nearer_first and nearer_second:
        return (max(nearer_first) + min(nearer_second)) / 2.0
    return fallback


def arm_centre(points, weights, side):
    """The middle of the side's own skin, leaving shoulder armour out.

    A pauldron rides the arm but stands well off it, so counting its vertices
    here would pull the whole arm inward by half a pad. This is the fallback for
    a caller that cannot say which shell is the arm itself; arm_region names the
    arm's own shell instead, which also leaves out a pad weighted to the upper
    arm - the weighting most avatar items give their shoulder plates.
    """
    proper = ("bip01 %s upperarm" % side, "bip01 %s forearm" % side,
              "bip01 %s hand" % side)
    held = []
    for point, per in zip(points, weights):
        total = sum(per.values())
        if total <= 0.0:
            continue
        if sum(per.get(name, 0.0) for name in proper) / total >= 0.5:
            held.append(point)
    return held or list(points)


def side_carry(armature, armature_fp, side, points, weights, middle=None,
               hand_flat=None, hand_cloud=None):
    """How one side's arm, as the mesh holds it, gets onto Halo's arm.

    One similarity for the whole side: the arm's own axis is turned onto Halo's
    arm, its length is laid along Halo's arm bones, and its own middle is shifted
    onto Halo's bone. Rotating, scaling by one number and shifting is the only
    carry that cannot tear anything: a similarity multiplies every edge of the
    side by the same factor, so no vertex can be pulled away from the ones
    beside it.

    Turning parts of an arm by different amounts was tried twice - once per
    bone frame, once per elbow and wrist - and tore the mesh both times. A
    sleeve crossing a joint is one piece of skin, and no blend of two different
    turns can hold it together where they meet; the wider the blend, the more
    of the sleeve is smeared instead of torn. The price of no distortion is
    that an arm modelled bent keeps its bend, so its glove stands off Halo's
    straight arm by as much as the elbow was bent.

    One thing is still free inside that one turn: how far round the arm the
    side is. The shortest turn from the item's arm to Halo's leaves the roll
    wherever the model happened to have it, and a glove authored palm-down
    therefore lands flat across Halo's hand instead of lying in it - aligned
    with the bone and visibly a twist. The glove's own flat is measured from
    the glove, laid in Halo's hand's flat by one more turn about the same arm,
    and that is still one turn: the roll moves nothing off the arm's line.

    Returns None when the bones or the geometry cannot answer.
    """
    if armature is None or armature_fp is None or len(points) < 4:
        return None
    was = armature.data.bones.get("bip01 %s upperarm" % side)
    head_bone = armature_fp.data.bones.get("frame %s upperarm" % side)
    hand_bone = armature_fp.data.bones.get("frame %s wriste" % side)
    if was is None or head_bone is None or hand_bone is None:
        return None
    # Where Halo's arm actually ends. Its bones go one step past the wrist - the
    # wriste bone finishes at the knuckles - while the hand the game draws goes
    # on to the fingertips, and the item's arm does too. Laying the item's arm
    # end on the knuckles alone left every glove sitting over the palm with its
    # fingers stopping dead at Halo's wrist, which is most of why an arm could
    # be lined up with the bones and still not look like it was wearing the
    # hand.
    tip_bone = (armature_fp.data.bones.get("frame %s middle tip" % side)
                or armature_fp.data.bones.get("frame %s index tip" % side))
    if tip_bone is None:
        tip_bone = hand_bone
    # The arm's own shell answers which way the arm runs. Shoulder armour is
    # bolted across the shoulder, not along the arm, and a big pad would tilt the
    # axis the whole side is turned by.
    held = middle if middle else arm_centre(points, weights, side)
    axis, _centre = arm_axis(held if held else points)
    if axis is None:
        return None
    shoulder = armature.matrix_world @ was.head_local
    # Point the axis away from the body: an arm leaves the shoulder. The vertex
    # farthest from the shoulder joint decides which end is the hand.
    far = max(points, key=lambda point: sum(
        (point[i] - shoulder[i]) ** 2 for i in range(3)))
    if sum((far[i] - shoulder[i]) * axis[i] for i in range(3)) < 0.0:
        axis = [-value for value in axis]
    along = [sum((point[i] - shoulder[i]) * axis[i] for i in range(3))
             for point in points]
    low, high = min(along), max(along)
    span = high - low
    if span <= 1e-6:
        return None
    head = armature_fp.matrix_world @ head_bone.head_local
    tip = armature_fp.matrix_world @ tip_bone.tail_local
    reach = (tip - head).length
    if reach <= 1e-6:
        return None
    turn = alignment(axis, [tip[i] - head[i] for i in range(3)])
    if turn is None:
        return None
    # The arm's own reach from its shoulder is laid along Halo's arm bones to
    # just past the end of Halo's fingers, so a glove encloses them.
    # Measured from the shoulder, not from the arm's far end: every vertex is
    # scaled by its distance from the shoulder, so dividing by the span instead
    # of the reach put the glove on past Halo's fingertips. The margin is what
    # keeps a finger bone from ending flush with the glove's own tip, where it
    # would stand out of the finger; the clamp only stops a part-sleeve being
    # stretched out to fill bones it was never made to reach.
    scale = max(0.5, min(1.6, (reach + FINGER_MARGIN) / max(high, 1e-6)))
    bones = ("bip01 %s upperarm" % side, "bip01 %s forearm" % side,
             "bip01 %s hand" % side)
    wrist = arm_joint(points, along, weights, bones[0], bones[1], low + 0.72 * span)
    reach_axis = [tip[i] - head[i] for i in range(3)]
    length = math.sqrt(sum(value * value for value in reach_axis))
    if length <= 1e-6:
        return None
    reach_axis = [value / length for value in reach_axis]
    # The glove is what is past the wrist, not past the elbow: the hand's own
    # bone hands over there when the item has one, and an item that weights its
    # glove to the forearm still stops being a sleeve down at the wrist.
    cuff = arm_joint(points, along, weights, bones[1], bones[2],
                     low + 0.82 * span)
    glove = [point for point, t in zip(points, along) if t > cuff]
    glove_thin = hand_plane(glove, axis) if len(glove) >= 8 else None
    # What the side is shifted by. An arm with a glove is lined up by that glove
    # on Halo's own hand - the hand is what a player watches hold a weapon, and
    # the fingers are only on the finger bones when they are over them - while a
    # bare sleeve is lined up by its own middle on the bone, which is all there
    # is to measure. Either way the shift only moves the side across Halo's arm,
    # never along it, so the reach stays where the scale put it.
    anchor, target = held if held else points, head
    if glove and hand_cloud:
        anchor = glove
        target = [sum(point[i] for point in hand_cloud) / len(hand_cloud)
                  for i in range(3)]

    def placed(turn, amount=None):
        """The side's carry for one turn, shifted onto Halo's bone.

        The arm's own middle belongs on Halo's bone. Pinning only the shoulder
        joint left an arm modelled off its own bone - bulky armour sits outboard
        of a slim skeleton - hanging that far out on Halo's, which is why the
        arms stood 6.3 units from Halo's own on a sleeve 3 units out. Shifting
        the whole side by the same amount changes no length, so it cannot tear
        what it moves; this is the one placement error a similarity is still
        free to fix. `middle` is the arm's own shell when the caller knows it,
        so a pauldron weighted to the upper arm cannot drag the whole side off
        the bone. The shift is worked out after the turn, so a rolled side still
        lands its middle on the bone rather than beside it.
        """
        step = scale if amount is None else amount
        centre = [sum(point[i] for point in anchor) / len(anchor)
                  for i in range(3)]
        delta = [centre[i] - shoulder[i] for i in range(3)]
        moved = [step * sum(turn[row * 3 + col] * delta[col]
                            for col in range(3)) for row in range(3)]
        across = sum(moved[i] * reach_axis[i] for i in range(3))
        shift = [moved[i] - reach_axis[i] * across for i in range(3)]
        # Where the target itself sits off the bone, across the arm only: the
        # along-arm distance is already carried by the scale, and adding it
        # again here put the glove on past Halo's fingers by its own length.
        want = [target[i] - head[i] for i in range(3)]
        along_target = sum(want[i] * reach_axis[i] for i in range(3))
        want = [want[i] - reach_axis[i] * along_target for i in range(3)]
        return {"axis": axis, "shoulder": tuple(shoulder), "turn": turn,
                "scale": step, "from": tuple(shoulder),
                "to": tuple(head[i] + want[i] - shift[i] for i in range(3)),
                "low": low, "high": high, "span": span, "twist": 0.0,
                "glove": "none", "wrist": min(max(wrist, low), high),
                "cuff": min(max(cuff, low), high),
                "anchor": "hand" if glove and hand_cloud else "bone"}

    place = placed(turn)
    # How far round the arm the item's own hand goes. The carry so far lines the
    # arm up and leaves the roll as the model had it; a glove authored with its
    # palm facing the floor is then a quarter turn out of Halo's hand, which is
    # exactly what a twist looks like. The glove answers which way its flat
    # lies, Halo's own hand answers where that flat belongs, and one turn about
    # the same arm takes one to the other.
    if glove_thin is not None and hand_flat is not None:
        angle = hand_twist(turn, reach_axis, glove_thin, hand_flat)
        if angle is not None:
            # Half a turn from a glove's flat is the same flat, so two answers
            # lie it in Halo's hand and the glove's own shape cannot say which.
            # Halo's own hand can: it is the model the game draws, so the one
            # whose glove stands closer to it is the one the game wears. With
            # no hand to measure against, the smaller turn keeps more of the
            # item's own authoring.
            near = angle + math.pi if angle <= -0.5 * math.pi else \
                angle - math.pi if angle > 0.5 * math.pi else angle
            options = []
            for value in (near, near + math.pi):
                # Half a turn either way is the same turn, so the one that comes
                # back inside a half turn reads as the angle a person would say.
                value = value - 2.0 * math.pi if value > math.pi else value
                candidate = placed(turn_product(turn_about(reach_axis, value),
                                                turn))
                candidate["twist"] = math.degrees(value)
                options.append(candidate)
            place = options[0]
            if hand_cloud:
                fits = [hand_fit(option, glove, hand_cloud) for option in options]
                if None not in fits and fits[1] < fits[0]:
                    place = options[1]
            place["glove"] = "flat"
    elif len(glove) >= 8 and hand_flat is not None:
        # A fist, or a mitten on one: every way across it is as wide as the
        # next, so there is no flat to line up and no answer to give. Saying so
        # is better than rolling it onto a guess.
        place["glove"] = "round"
    # The bones say where an arm is; the mesh the game draws says what it looks
    # like, and the two do not quite agree - a gauntlet leans a degree or two
    # off its own bone, and an item's sleeve can lean the other way by more. So
    # the side, already placed, is fitted onto Halo's own arm mesh: its nearest
    # point on that arm for each of its own, the one turn and one size that
    # bring them together, repeated until it stops moving. Still one
    # similarity, so nothing tears, and the shift is worked out again after
    # each pass, so the glove stays on Halo's hand while the sleeve finds the
    # arm the game wears.
    want = halo_arm_axis(armature_fp, side)
    # Measured by the same rule as Halo's own arm: the skin the arm's bones
    # hold at full weight. `arm_centre` was used here first and stopped a
    # degree short, because it counts a vertex the arm bones share with the
    # chest as the arm's and Halo's side does not - one measurement on both
    # sides is what makes the angle between them the angle a player sees.
    own_bones = ("bip01 %s upperarm" % side, "bip01 %s forearm" % side)
    sleeve = [point for point, per in zip(points, weights)
              if max(per.get(name, 0.0) for name in own_bones) > 0.5]
    if len(sleeve) < 12:
        sleeve = [point for point, t in zip(points, along) if t <= cuff]
    if want is not None and len(sleeve) >= 12:
        kept = {"twist": place.get("twist", 0.0),
                "glove": place.get("glove", "none")}
        fitted = carry_onto(place, sleeve, want, placed)
        if fitted is not None:
            place = fitted
            place["twist"], place["glove"] = kept["twist"], kept["glove"]
            own = arm_axis(sleeve)[0]
            if own is not None:
                held = turn_point(place["turn"], own)
                if sum(held[i] * want[i] for i in range(3)) < 0.0:
                    held = [-value for value in held]
                place["fit_left"] = math.degrees(math.acos(
                    max(-1.0, min(1.0, sum(held[i] * want[i] for i in range(3))))))
    return place


def limit_turn(turn, most=10.0):
    """A turn cut back to `most` degrees, keeping the axis it turns about."""
    cosine = max(-1.0, min(1.0, (turn[0] + turn[4] + turn[8] - 1.0) / 2.0))
    angle = math.acos(cosine)
    if angle <= math.radians(most) or angle <= 1e-9:
        return turn
    axis = [turn[7] - turn[5], turn[2] - turn[6], turn[3] - turn[1]]
    length = math.sqrt(sum(value * value for value in axis))
    if length < 1e-9:
        return turn
    return turn_about([value / length for value in axis], math.radians(most))


def carry_onto(place, points, want, rebuild, rounds=8, most=20.0):
    """Turn a placed side until its sleeve runs the way Halo's own does.

    The bones say where an arm is jointed; the arm mesh the game draws says
    which way its sleeve actually runs, and the two do not agree - Halo's own
    sleeve leans a degree or two off its bone line, and an item's can lean the
    other way by ten, which is what a player sees as an arm at the wrong angle.
    The item's sleeve axis is measured the way Halo's is, carried into the world
    by the turn already chosen, and turned onto Halo's about the shoulder; the
    shift is worked out again afterwards, so the glove stays on Halo's hand
    while the sleeve finds the arm.

    Only the turn moves, never the size - the size is what puts the glove past
    Halo's fingertips - and each pass is capped, so a side settles onto the
    angle instead of swinging past it. The cap is a step size, not a limit on
    what can be corrected: every pass is measured and thrown away unless it
    really is closer, so a side 50 degrees out is walked in over several passes
    instead of being left there. Three passes of twelve were too few - a real
    item 49 degrees out stopped at 13 and nothing in the report said so. Fitting the whole arm cloud by nearest
    point was tried first and was worse at this: it closes the distance by
    rolling a fat sleeve without ever pointing it the right way.
    """
    if place is None or want is None or len(points) < 12:
        return None

    def angle_of(candidate):
        own = arm_axis(points)[0]
        if own is None:
            return None
        held = turn_point(candidate["turn"], own)
        if sum(held[i] * want[i] for i in range(3)) < 0.0:
            held = [-value for value in held]
        cosine = max(-1.0, min(1.0, sum(held[i] * want[i] for i in range(3))))
        return math.degrees(math.acos(cosine))

    best = place
    best_angle = angle_of(best)
    if best_angle is None:
        return None
    for _round in range(rounds):
        if best_angle < 0.05:
            break
        own, _centre = arm_axis(points)
        if own is None:
            break
        held = turn_point(best["turn"], own)
        if sum(held[i] * want[i] for i in range(3)) < 0.0:
            held = [-value for value in held]
        spin = alignment(held, want)
        if spin is None:
            break
        candidate = rebuild(turn_product(limit_turn(spin, most), best["turn"]),
                            best["scale"])
        candidate_angle = angle_of(candidate)
        if candidate_angle is None or candidate_angle >= best_angle:
            break
        best, best_angle = candidate, candidate_angle
    return best


def sleeve_points(object_data, side):
    """The skin one side's upper arm and forearm hold at full weight."""
    names = {"frame %s upperarm" % side, "frame %s forearm" % side}
    groups = {group.name: group.index
              for group in getattr(object_data, "vertex_groups", []) or []}
    keep = {groups[name] for name in names if name in groups}
    if not keep:
        return []
    points = []
    for vertex in getattr(object_data.data, "vertices", []) or []:
        for weight in vertex.groups:
            if weight.group in keep and weight.weight > 0.5:
                points.append(object_data.matrix_world @ vertex.co)
                break
    return points


def sleeve_angle(arms, armature_fp, rule="wide"):
    """How far the carried sleeves sit from Halo's, judged a different way.

    The fit turns each side until the line between the middles of its two ends
    points where Halo's does. A fit graded by the measurement it optimises
    always reports success - it was asked for an angle and then asked how close
    it got - so this asks the same question with an estimator the fit never
    uses: the widest direction of the carried sleeve's skin against the widest
    direction of Halo's own. Two estimators agreeing is evidence; one agreeing
    with itself is not. Both sides are reported, because a side can be left
    alone and the other fitted.
    """
    if arms is None or armature_fp is None:
        return None
    halo = {}
    for item in halo_arms(armature_fp):
        for side in ("l", "r"):
            halo.setdefault(side, []).extend(sleeve_points(item, side))
    angles = {}
    for side in ("l", "r"):
        mine = sleeve_points(arms, side)
        theirs = halo.get(side) or []
        if len(mine) < 12 or len(theirs) < 12:
            continue
        if rule == "ends":
            here, there = arm_direction(mine), arm_direction(theirs)
        else:
            here, _centre = arm_axis(mine)
            there, _centre = arm_axis(theirs)
        if here is None or there is None:
            continue
        cosine = abs(sum(here[i] * there[i] for i in range(3)))
        angles[side] = math.degrees(math.acos(max(-1.0, min(1.0, cosine))))
    return angles or None


def halo_arm_axis(armature_fp, side):
    """Which way Halo's own sleeve runs, measured the way the item's is.

    From the arm mesh the rig file ships: the vertices weighted to that side's
    upper arm and forearm, and the line through them. That is the arm the game
    draws, so it is the angle an item's arm has to match to look worn rather
    than pinned on - and it is not quite the bone line, which is why lining up
    with the bones alone left the arms visibly tilted.
    """
    # Upper arm and forearm, never the hand: the glove is weighted onto the
    # finger bones once it is carried, so a hand counted here would be in
    # Halo's measure and out of the item's, and the two axes would never be the
    # same measurement. The sleeve is what leans, and it is what a player sees.
    points = []
    for item in halo_arms(armature_fp):
        points.extend(sleeve_points(item, side))
    if len(points) < 12:
        return None
    # The same rule the item's sleeve is measured by: the line between the
    # middles of its two ends. One rule on both sides is what makes the angle
    # between them the angle a player sees, instead of two numbers that nearly
    # agree.
    return arm_direction(points)


def place_arm(place, point):
    """Where one arm vertex goes: the side's one turn, scale and shift."""
    if place is None:
        return tuple(point)
    turn, scale = place["turn"], place["scale"]
    delta = [point[axis] - place["from"][axis] for axis in range(3)]
    return tuple(place["to"][row] + scale * (
        turn[row * 3] * delta[0] + turn[row * 3 + 1] * delta[1]
        + turn[row * 3 + 2] * delta[2]) for row in range(3))


def hand_fit(place, points, cloud, sample=80):
    """How far a glove stands from Halo's own hand, as a mean in units.

    The one question a glove's flat cannot answer is which of two half-turn
    twins Halo wears, so the answer is measured: carry the glove both ways and
    keep the one that stands closer to the hand the game actually draws.
    """
    if place is None or not points or not cloud:
        return None
    step = max(1, len(points) // sample)
    total, seen = 0.0, 0
    for point in points[::step]:
        moved = place_arm(place, point)
        total += min(math.sqrt(sum((moved[i] - other[i]) ** 2
                                  for i in range(3)))
                     for other in cloud)
        seen += 1
    return total / seen if seen else None


def hand_share(place, point):
    """How much of the glove a vertex is, for a side with no hand weights.

    An avatar's glove is often weighted to the forearm - the avatar skeleton has
    no fingers to drive - so on Halo's arm it would swing from the elbow and its
    fingers would leave Halo's hand. This turns position along the arm into
    hand weight: nothing at the cuff, all of it at the fingertips. Weights
    alone cannot tear a shell apart; the geometry has already been carried.
    """
    if place is None:
        return 0.0
    t = sum((point[i] - place["shoulder"][i]) * place["axis"][i]
            for i in range(3))
    start, end = place["wrist"], place["high"]
    if t <= start or end - start <= 1e-6:
        return 0.0
    share = min(1.0, (t - start) / (end - start))
    return share * share * (3.0 - 2.0 * share)


# The fingers Halo's own first-person hands close with. Its palm is not one.
HAND_FINGERS = ("index", "middle", "ring", "pinky", "thumb")


def hand_span(armature_fp, side):
    """Halo's own hand: where it starts, which way it runs, how long it is and
    where its knuckles are."""
    bones = getattr(getattr(armature_fp, "data", None), "bones", None)
    if bones is None:
        return None
    wrist = bones.get("frame %s wriste" % side)
    tip = bones.get("frame %s middle tip" % side)
    if tip is None:
        tip = bones.get("frame %s index tip" % side)
    if wrist is None or tip is None:
        return None
    head = armature_fp.matrix_world @ wrist.head_local
    knuckles = armature_fp.matrix_world @ wrist.tail_local
    end = armature_fp.matrix_world @ tip.tail_local
    reach = [end[i] - head[i] for i in range(3)]
    length = math.sqrt(sum(value * value for value in reach))
    if length <= 1e-6:
        return None
    knuckle = math.sqrt(sum((knuckles[i] - head[i]) ** 2 for i in range(3)))
    return head, [value / length for value in reach], length, knuckle


def finger_bones(armature_fp, side):
    """Halo's own finger bones on one side, as (name, head, tail) in world space."""
    bones = getattr(getattr(armature_fp, "data", None), "bones", None)
    if bones is None:
        return []
    prefix = "frame %s " % side
    found = []
    for entry in bones:
        name = entry if isinstance(entry, str) else getattr(entry, "name", "")
        if not name.startswith(prefix):
            continue
        if not name[len(prefix):].startswith(HAND_FINGERS):
            continue
        bone = bones.get(name)
        if bone is None:
            continue
        found.append((name, armature_fp.matrix_world @ bone.head_local,
                      armature_fp.matrix_world @ bone.tail_local))
    return found


def finger_chains(armature_fp, side):
    """Halo's finger bones split by finger, each chain from knuckle to tip.

    A glove's vertex belongs to one modelled finger, so the weights it takes
    should come from that finger's own bones; the two nearest bones of the whole
    hand can be one on each side of the finger next door, which is a weight that
    drags skin across the gap between fingers. Keyed by `HAND_FINGERS`, ordered
    low, mid, tip - `middlelow` is the one bone whose name has no space.
    """
    chains = {}
    for name, head, tail in finger_bones(armature_fp, side):
        flat = name[len("frame %s " % side):].replace(" ", "")
        for key in HAND_FINGERS:
            if flat.startswith(key):
                chains.setdefault(key, []).append((name, head, tail, flat))
                break
    for entries in chains.values():
        entries.sort(key=lambda entry: 0 if entry[3].endswith("low")
                     else 1 if entry[3].endswith("mid") else 2)
    return chains


def finger_of(name):
    """Which of Halo's fingers a bone belongs to, or None for any other bone."""
    if not name.startswith("frame ") or name.count(" ") < 2:
        return None
    flat = name.split(" ", 2)[2].replace(" ", "")
    for key in HAND_FINGERS:
        if flat.startswith(key):
            return key
    return None


def chain_along(point, entries):
    """Where a vertex sits *along* a finger's chain, as (weight, bone) pairs.

    Distance to a bone's segment is the right measure for a finger and the wrong
    one for a thumb. Halo's fingers run almost straight and a glove's finger is
    slim, so the nearest bone is the one the vertex is on. A glove's thumb is a
    plate standing well off its chain: every vertex of it is roughly as far from
    all three thumb bones, so "the two nearest" fell to whichever end the plate
    leans towards. Measured on the Marine glove that gave 7% of the thumb to
    `thumb low`, 39% to `thumb mid` and 54% to `thumb tip`, against Halo's own
    hand's 38/30/32 - and the .jms writes two weights a vertex, so the base bone
    ended up driving no vertex at all. A thumb then bends from its tip instead
    of folding from its base, which is the kink that reads as a wrong thumb.

    A vertex's place along the chain does not care how far the plate stands off
    it, so each bone owns its own length along the chain and hands over across a
    short band at each joint. The band is a fraction of the shorter bone either
    side, not the whole bone: a band as wide as the bones themselves let the
    long bone's share reach a third of the way down the next one, which is how
    the middle bone ended up with 0.71 of a point sitting over its own centre.
    Two bones on a vertex is all that is left, which is exactly what the .jms
    can carry.
    """
    joints = [entries[0][1]] + [entry[2] for entry in entries]
    spans = [math.dist(joints[index], joints[index + 1])
             for index in range(len(entries))]
    total = sum(spans)
    if total <= 1e-6:
        return []
    best, walked = None, 0.0
    for index in range(len(entries)):
        first, second = joints[index], joints[index + 1]
        length = spans[index]
        if length > 1e-9:
            step = [second[k] - first[k] for k in range(3)]
            along = sum((point[k] - first[k]) * step[k] for k in range(3))
            along = min(1.0, max(0.0, along / (length * length)))
            nearest = [first[k] + step[k] * along for k in range(3)]
            gap = math.dist(point, nearest)
            if best is None or gap < best[0]:
                best = (gap, walked + along * length)
        walked += length
    if best is None:
        return []
    here = best[1]
    bounds, walked = [], 0.0
    for span in spans:
        bounds.append((walked, walked + span))
        walked += span
    weights = []
    for index, (name, _head, _tail, _flat) in enumerate(entries):
        first, second = bounds[index]
        band = 0.3 * min(spans[index],
                         spans[index - 1] if index > 0 else spans[index],
                         spans[index + 1] if index + 1 < len(spans)
                         else spans[index])
        band = max(band, 1e-6)
        if here < first - band or here > second + band:
            continue
        weight = 1.0
        if index > 0 and here < first + band:
            weight = 0.5 + (here - first) / (2.0 * band)
        elif index + 1 < len(entries) and here > second - band:
            weight = 0.5 + (second - here) / (2.0 * band)
        weight = min(1.0, max(0.0, weight))
        if weight > 1e-6:
            weights.append((weight, name))
    total = sum(weight for weight, _name in weights)
    if total <= 0.0:
        return []
    shares = [(weight / total, name) for weight, name in weights]
    # Two weights a vertex is what a .jms carries, and a share under a fiftieth
    # moves the skin by less than the mesh's own tolerance - the same rule the
    # finger shares are kept by. Without it a plate just past a joint rode
    # three bones, and the third was thrown away by the export anyway.
    kept = [(weight, name) for weight, name in shares if weight >= 0.02]
    total = sum(weight for weight, _name in kept)
    if total <= 0.0:
        return shares
    return [(weight / total, name) for weight, name in kept]


def ride_chain(per, point, armature_fp, side, key, influences=2, power=4.0):
    """Move every finger share of a piece's weight onto one finger's bones.

    A glove's finger is often one piece with the finger beside it, so a piece
    that ends up split between two fingers pulls itself in two the moment they
    curl apart. This takes all of the finger weight a piece holds and gives it
    to the one finger that piece mostly is, divided along that finger as usual;
    the cuff, forearm and hand weights it already had are left alone.
    """
    chains = finger_chains(armature_fp, side)
    entries = chains.get(key)
    if not entries:
        return per
    names = {name for chain in chains.values()
             for name, _head, _tail, _flat in chain}
    total = 0.0
    for name in list(per):
        if name in names:
            total += per.pop(name)
    if total <= 0.0:
        return per
    weights = chain_along(point, entries) if key == "thumb" else None
    if not weights:
        near = sorted((point_segment_distance(point, head, tail), name)
                      for name, head, tail, _flat in entries)[:influences]
        weights = [(1.0 / ((gap + 0.3) ** power), name) for gap, name in near]
    scale = sum(weight for weight, _name in weights)
    if scale <= 0.0:
        return per
    for weight, name in weights:
        per[name] = per.get(name, 0.0) + total * weight / scale
    return per


def seat_thumb(weights, position, chain, hand_bone, side=None, side_of=None,
               reach=SEAT_REACH, only=None):
    """Seat a glove's thumb guard in the palm by carrying its chain into the hand.

    The guard is a plate standing proud of the glove, and Halo's thumb bone runs
    outside it, so a guard weighted wholly to the thumb swings off the palm the
    moment the thumb bends and opens the gap underneath; one weighted wholly to
    the hand never moves and the thumb is dead.

    The fix is not a share bolted onto the thumb's weights. A .jms carries two
    weights a vertex, and a third share means the export drops one of the pair
    the guard was using - measured posed at 30/25/20, that tore the plate to
    x5.84. So the chain itself is carried back past the thumb's base by `reach`
    and named for the hand bone: the guard's root lands in the palm's own
    segment and its tip still lands on the thumb's. Every vertex then takes the
    two bones that straddle it, as it always did, so neighbours keep sharing a
    bone and the plate cannot tear.

    `weights` maps a vertex index to {bone: weight} and is changed in place;
    `position` gives each vertex's carried position; `chain` is the thumb's
    (name, head, tail, flat) entries; `only` limits it to whole shells - a palm
    vertex that merely brushes the thumb must not be re-seated away from the
    vertices beside it in its own shell, or the palm tears. Returns the indices
    it seated.
    """
    if not chain:
        return []
    base = list(chain[0][1])
    tip = list(chain[-1][2])
    span = [base[k] - tip[k] for k in range(3)]
    size = math.sqrt(sum(value * value for value in span)) or 1.0
    span = [value / size for value in span]
    behind = [base[k] + span[k] * reach for k in range(3)]
    extended = [(hand_bone, tuple(behind), tuple(base), "hand")] + list(chain)
    seated = []
    for index in sorted(weights):
        if side is not None and side_of is not None:
            try:
                owner = side_of[index]
            except (KeyError, IndexError):
                continue
            if owner != side:
                continue
        if only is not None and index not in only:
            continue
        per = weights[index]
        held = sum(weight for name, weight in per.items()
                   if finger_of(name) == "thumb")
        if held <= 0.05:
            continue
        shares = chain_along(position[index], extended)
        total = sum(weight for weight, _name in shares)
        if total <= 0.0:
            continue
        per.clear()
        for weight, name in shares:
            per[name] = weight / total
        seated.append(index)
    return seated


def finger_split(point, armature_fp, side, influences=2, power=4.0):
    """How much of a glove vertex rides Halo's fingers, and on which of them.

    Halo's own first-person hands close with their finger bones, so a glove that
    rides the hand bone alone cannot hold anything the way the game does: its
    fingers go wherever a wrist goes and never close round a weapon. A glove
    vertex is given to the two nearest bones of *its own* finger, so the weight
    changes smoothly along that finger instead of reaching across to the one
    beside it.

    The measure is the vertex's own finger, not Halo's hand. A glove's fingers do
    not reach as far along Halo's arm as Halo's own do, so a measure taken from
    the wrist left the half of every glove finger nearest the knuckle on the hand
    bone while the rest curled: the bend collected in a single loop and the
    knuckles creased. Measured along the finger itself, the weight rises from the
    knuckle outwards over the first part of the finger, and the palm - which lies
    behind the knuckle - stays on the hand bone. That is also how the thumb is
    found, which is why it no longer needs a rule of its own: it sits beside the
    wrist and never crosses the knuckle line, so a hand-long measure put its whole
    guard behind that line and it did not move with the thumb at all.

    The weight fades out where the finger is no nearer than the hand bone, which
    keeps the palm and a knuckle plate where they belong, and a glove that is one
    surface across two fingers shares the weight between both there instead of
    picking one and tearing the joining skin.

    Returns (grip, shares): `grip` is how much of the vertex belongs to the
    fingers at all and `shares` divides that between its finger's bones. None
    when the rig has no hand to measure.
    """
    span = hand_span(armature_fp, side)
    chains = finger_chains(armature_fp, side)
    if span is None or not chains:
        return None
    near_chain = []
    for key, entries in chains.items():
        gap = min(point_segment_distance(point, first, second)
                  for _name, first, second, _flat in entries)
        near_chain.append((gap, key))
    near_chain.sort()
    gap, key = near_chain[0]
    entries = chains[key]
    # A glove is often one surface across two fingers rather than two separate
    # ones: the Marine's whole glove is a single 226-vertex skin, and the skin
    # between its index and middle fingertips belongs to both. Choosing one
    # finger there tore that joining web in two when the fingers curled apart,
    # so the weight is shared between the two nearest fingers in proportion to
    # how close it is to each. The fall-off with distance is steep enough that a
    # vertex in the middle of a finger is its own finger's, and a switch at a
    # distance would itself be a step in the weight, so there is no switch.
    reached = near_chain[:2]
    shares = {}
    for chain_gap, chain_key in reached:
        if chain_key == "thumb":
            # A thumb plate is weighted by where it lies along its chain, not by
            # which bone happens to be nearest - see chain_along.
            weights = chain_along(point, chains["thumb"])
        else:
            near = sorted((point_segment_distance(point, first, second), name)
                          for name, first, second, _flat in chains[chain_key])
            weights = [(1.0 / ((reach + 0.3) ** power), name)
                       for reach, name in near[:influences]]
        total = sum(weight for weight, _name in weights)
        if total <= 0.0:
            continue
        # No cutoff between fingers, only a fall-off: a switch at a distance
        # would itself be a step in the weight, and the skin joining two
        # fingers has to pass smoothly from one to the other.
        pull = 1.0 / ((chain_gap + 0.3) ** power)
        for weight, name in weights:
            shares[name] = shares.get(name, 0.0) + pull * weight / total
    total = sum(shares.values())
    if total <= 0.0:
        return None
    shares = {name: weight / total for name, weight in shares.items()}
    # A finger's own bones are all that is left worth writing once the next
    # finger's share is under a fiftieth: it moves the skin by less than the
    # mesh's own tolerance and only clutters the groups.
    kept = {name: weight for name, weight in shares.items() if weight >= 0.02}
    if kept:
        total = sum(kept.values())
        shares = {name: weight / total for name, weight in kept.items()}
    wrist = getattr(getattr(armature_fp, "data", None), "bones", None)
    wrist = wrist.get("frame %s wriste" % side) if wrist is not None else None
    if wrist is None:
        return None
    hand_gap = point_segment_distance(
        point, armature_fp.matrix_world @ wrist.head_local,
        armature_fp.matrix_world @ wrist.tail_local)
    if gap >= hand_gap:
        return 0.0, shares
    base = entries[0][1]
    tip = entries[-1][2]
    stretch = [tip[i] - base[i] for i in range(3)]
    reach = math.sqrt(sum(value * value for value in stretch))
    if reach <= 1e-6:
        return None
    along = sum((point[i] - base[i]) * stretch[i]
                for i in range(3)) / (reach * reach)
    ease = min(1.0, max(0.0, along / 0.45))
    won = (hand_gap - gap) / max(hand_gap, 1e-6)
    hold = min(1.0, max(0.0, won / 0.5))
    grip = (ease * ease * (3.0 - 2.0 * ease)
            * hold * hold * (3.0 - 2.0 * hold))
    return grip, shares


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


def band_weights(object_data, armature, band=None):
    """Which bones may bend a vertex: only the pair across a joint it stands at.

    An arm bends at the shoulder, the elbow and the wrist, and nowhere else. A
    vertex that blends two bones while standing well away from the joint those
    bones share is a vertex that bends the mesh mid-limb, and no animation and no
    weapon pose can look right when the mesh bends where the skeleton has no
    joint. So a vertex like that is given the one bone it rides most.

    A vertex standing at the joint keeps both bones, because that is where a bend
    belongs - and only bones that actually meet at a joint may share it, so a
    chest point can never carry a share of the hand.

    Weights only; no vertex moves.
    """
    if band is None:
        band = PLATE_BAND          # one band for the whole tool, see hold_the_plates
    segments = bone_segments(armature)
    names = list(segments)
    raw = vertex_weights(object_data)
    if not names:
        return raw
    family = bone_family(armature, names)
    world = object_data.matrix_world
    joints = {}

    def shared(one, two):
        """The joint two bones have in common, or None when they do not meet."""
        key = (one, two) if one < two else (two, one)
        if key not in joints:
            gap, joint = min(((a - b).length, (a + b) / 2.0)
                             for a in segments[one] for b in segments[two])
            joints[key] = (joint, gap)
        return joints[key]

    kept = {}
    for index, per in raw.items():
        ranked = sorted(per.items(), key=lambda pair: -pair[1])
        if len(ranked) < 2:
            kept[index] = per
            continue
        point = world @ object_data.data.vertices[index].co
        mine = {ranked[0][0]: ranked[0][1]}
        for name, weight in ranked[1:]:
            if name not in (family.get(ranked[0][0]) or ()):
                continue                  # not the far side of a joint
            joint, gap = shared(ranked[0][0], name)
            if gap > 1e-3:
                continue                  # the bones do not meet at all
            if (point - joint).length <= band:
                mine[name] = weight
        total = sum(mine.values()) or 1.0
        kept[index] = {name: weight / total for name, weight in mine.items()}
    return kept


def plate_bone(object_data, segments, children, indexes, tally):
    """Which bone carries one plate: the bone its own middle hangs on.

    A plate is one piece of armour and rides one bone, and which bone is a
    question about where the plate *is*, not about how its vertices happened to
    be counted. Counting them is what put a mirrored pair of pads on different
    bones - a left arm that came down beside a right arm that stayed out.

    The middle of the plate answers it - and it answers for the arm the plate is
    strapped to, not for the girdle bone beside it: a pauldron wraps around the
    shoulder, so it is about as near the clavicle as the upper arm, and the
    clavicle barely turns. A plate lying along the next bone up the chain is
    given that bone, so it comes down with the arm it is part of. Only bones the
    plate already rides, or the bones they carry, are candidates - so a chest
    plate can never be handed to a hand.
    """
    if not segments:
        return max(sorted(tally.items()), key=lambda pair: pair[1])[0]
    matrix = object_data.matrix_world
    points = object_data.data.vertices
    middle = Vector((0.0, 0.0, 0.0))
    for index in indexes:
        middle += matrix @ points[index].co
    middle /= max(len(indexes), 1)
    candidates = set(name for name in tally if name in segments)
    for name in list(candidates):
        candidates.update(child for child in children.get(name) or () if child in segments)
    if not candidates:
        return max(sorted(tally.items()), key=lambda pair: pair[1])[0]

    def gap(name):
        head, tail = segments[name]
        return point_segment_distance(middle, head, tail)

    ridden = min(sorted(candidates), key=gap)
    # A shoulder pad wraps *around* the joint, so its middle is about as near the
    # clavicle as it is the upper arm - and the clavicle barely turns, so the pad
    # is left standing out sideways while the arm comes down under it. A plate
    # that lies along the bone past this one belongs to that bone: it is the arm
    # it is strapped to. Only a plate that sits off the end of the next bone, or
    # much further from it, stays where the nearest bone put it.
    for _step in range(2):
        best = None
        for child in sorted(children.get(ridden) or ()):
            if child not in candidates or child not in segments:
                continue
            head, tail = segments[child]
            axis = tail - head
            if axis.length_squared < 1e-12:
                continue
            how_far = (middle - head).dot(axis) / axis.length_squared
            if how_far < -0.10 or how_far > 1.05:
                continue
            distance = gap(child)
            if distance > max(gap(ridden) * 1.6, gap(ridden) + 0.5):
                continue
            if best is None or distance < best[0]:
                best = (distance, child)
        if best is None:
            break
        ridden = best[1]
    return ridden


def single_bone_rides(object_data, armature):
    """Which bone each vertex rides on its own, and which must keep its blend.

    A gbxmodel vertex may ride two nodes and Halo blends them linearly. That is
    right for fabric and wrong for metal: the seventy-nine degrees between the
    avatar's arms-out pose and Halo's arms-down one is far too much for a linear
    blend, which at that angle does not bend the joint, it crushes it - the elbow
    that looked deformed. The same blend is what twists a sleeve the moment the
    game plays an animation.

    So every PLATE rides exactly one bone. A shell small enough to be one piece
    of armour takes the bone most of it already rides, and the whole plate then
    travels rigidly: not one edge inside it can change length, in this pose or in
    any animation Halo plays. A plate is metal; it does not bend.

    A skin shell is too big to be one plate, and it is the fabric under and
    between the plates, which is meant to fold where a joint is. Its vertices
    keep the blend the skinning gave them and are reported as "" here.

    Returns {vertex index: bone name}, "" for skin, and None for a vertex no
    bone claimed - the caller gives those the bone whose segment is nearest.
    """
    if not armature or not armature.data.bones:
        return {}
    known = {bone.name for bone in armature.data.bones}
    rides = {}
    for index, per in vertex_weights(object_data).items():
        best, best_weight = None, -1.0
        for name, weight in per.items():
            if name in known and weight > best_weight:
                best, best_weight = name, weight
        rides[index] = best
    matrix = armature.matrix_world
    segments = {bone.name: (matrix @ bone.head_local, matrix @ bone.tail_local)
                for bone in armature.data.bones if bone.name in known}
    _parent, children = bone_tree(armature, list(segments))
    plates = {}
    pieces = []
    shells = 0
    for piece in shell_faces(object_data.data):
        if not piece:
            continue
        indexes = set()
        for polygon in piece:
            indexes.update(polygon.vertices)
        if len(indexes) > SHELL_SINGLE_BONE_MAX:
            continue          # fabric, not a plate: it folds at its joints
        tally = {}
        for index in indexes:
            name = rides.get(index)
            if name:
                tally[name] = tally.get(name, 0) + 1
        if not tally:
            continue
        bone = plate_bone(object_data, segments, children, indexes, tally)
        middle = matrix @ (sum((object_data.data.vertices[index].co
                                for index in indexes), Vector((0.0, 0.0, 0.0)))
                           / max(len(indexes), 1))
        pieces.append((indexes, bone, middle))
        shells += 1
    # Plates that touch each other move together. A pad whose neighbours all ride
    # the arm is a pad the arm carries, whatever its own middle happens to be
    # nearest - and a pad left on the girdle while the arm goes down is exactly
    # the plate that hangs out sideways. Only a child bone may be adopted this
    # way, so the pull is outward along a limb and never up one.
    for _round in range(2):
        adopt = {}
        for indexes, bone, middle in pieces:
            votes = {}
            for _other, their_bone, their_middle in pieces:
                if their_bone == bone:
                    continue
                if (their_middle - middle).length > PLATE_TOUCH:
                    continue
                votes[their_bone] = votes.get(their_bone, 0) + 1
            onward = [(count, name) for name, count in votes.items()
                      if name in (children.get(bone) or ())
                      and count >= max(votes.get(bone, 0) + 2, 2)]
            if onward:
                adopt[id(indexes)] = max(onward)[1]
        if not adopt:
            break
        pieces = [(indexes, adopt.get(id(indexes), bone), middle)
                  for indexes, bone, middle in pieces]
    for indexes, bone, _middle in pieces:
        for index in indexes:
            plates[index] = bone
    missing = [index for index, name in rides.items() if name is None]
    if missing:
        matrix = armature.matrix_world
        segments = {bone.name: (tuple(matrix @ bone.head_local),
                                tuple(matrix @ bone.tail_local))
                    for bone in armature.data.bones}
        points = object_data.data.vertices
        for index in missing:
            point = tuple(points[index].co)
            rides[index] = min(segments, key=lambda name: segment_distance(
                point, segments[name][0], segments[name][1]))
        log("%s: %d vertex(es) rode no bone - the nearest bone carries each of "
            "them" % (object_data.name, len(missing)))
    for index in rides:
        if index in plates:
            rides[index] = plates[index]
        elif rides[index]:
            rides[index] = ""          # skin: keep the blend
    # How many plates were given one bone, for the report line.
    object_data["whole_pieces"] = shells
    return rides


def single_bone_weights(object_data, armature):
    """Make every plate ride one node at weight 1.0, and leave the skin alone.

    This is the shape guarantee, and it is a guarantee rather than a hope: a
    plate with one node on every vertex has nothing for the engine to blend, so
    no animation it can play has a way to bend, shear or twist that plate. The
    skin keeps its blend, because fabric is meant to fold where a joint is.
    """
    rides = single_bone_rides(object_data, armature)
    if not rides:
        return None
    # The shipped skin too: two bones only across a joint the vertex stands at.
    weights = band_weights(object_data, armature)
    for group in list(object_data.vertex_groups):
        object_data.vertex_groups.remove(group)
    made = {}

    def give(index, name, weight):
        group = made.get(name)
        if group is None:
            group = object_data.vertex_groups.new(name=name)
            made[name] = group
        group.add([index], weight, "REPLACE")

    plates = 0
    skin = 0
    for index, bone in sorted(rides.items()):
        if bone:
            give(index, bone, 1.0)
            plates += 1
        else:
            skin += 1
            per = weights.get(index) or {}
            total = sum(per.values()) or 1.0
            for name, weight in sorted(per.items()):
                give(index, name, weight / total)
    # What rides what, bone by bone, because a plate on the wrong bone looks
    # exactly like a broken arm - and a mirrored pair that disagrees is the one
    # thing a number can show that a picture cannot.
    counts = {}
    for bone in rides.values():
        if bone:
            counts[bone] = counts.get(bone, 0) + 1
    chain = sorted((name, count) for name, count in counts.items()
                   if "arm" in name.lower() or "hand" in name.lower()
                   or "clavicle" in name.lower())
    if chain:
        log("%s: plates on the arm chain - %s"
            % (object_data.name, ", ".join("%s %d" % pair for pair in chain)))
    return ("%d plate vertex(es) on one node each (%d plate(s) over %d bone(s)); "
            "%d fabric vertex(es) blend only across a joint they stand at - a "
            "plate cannot bend or twist in any pose, and the mesh cannot fold "
            "where the skeleton has no joint"
            % (plates, object_data.get("whole_pieces") or 0, len(made),
               skin))


def inside_out(faces, coords, slot):
    """Whether a shell's faces turn their backs on the shell's own middle.

    A sleeve or a glove that is inside out shows its own backfaces to the world,
    which read as blank, and lighting falls on it from the inside. Its faces
    point at the middle of the piece instead of away from it, and that is what
    this measures: a shell the item had the right way round is left exactly as
    it was. A flat plate has no middle to point at or away from - every face
    sits square to the middle, neither in nor out - so it is never flipped on a
    guess, which would hide the side a person is meant to see.
    """
    total = [0.0, 0.0, 0.0]
    seen = 0
    for polygon in faces:
        for index in polygon.vertices:
            point = coords[slot[index]]
            for axis in range(3):
                total[axis] += point[axis]
            seen += 1
    if not seen:
        return False
    middle = [value / seen for value in total]
    inward = counted = 0
    for polygon in faces:
        loop = [coords[slot[index]] for index in polygon.vertices]
        if len(loop) < 3:
            continue
        first = [loop[0][axis] - loop[1][axis] for axis in range(3)]
        second = [loop[0][axis] - loop[2][axis] for axis in range(3)]
        normal = [first[1] * second[2] - first[2] * second[1],
                  first[2] * second[0] - first[0] * second[2],
                  first[0] * second[1] - first[1] * second[0]]
        centre = [sum(point[axis] for point in loop) / len(loop)
                  for axis in range(3)]
        out = [centre[axis] - middle[axis] for axis in range(3)]
        scale = (math.sqrt(sum(value * value for value in normal))
                 * math.sqrt(sum(value * value for value in out)))
        if scale < 1e-9:
            continue
        counted += 1
        if sum(normal[axis] * out[axis] for axis in range(3)) < -0.3 * scale:
            inward += 1
    return counted >= 4 and inward >= 0.8 * counted


def glove_of(place, point):
    """Whether a vertex of one side is part of its glove: past the wrist.

    `side_carry` already finds the line where the sleeve stops and the hand
    starts, because it measures and places the glove from there. The finger
    check draws its line in the same place rather than guessing a second one.
    """
    if place is None or place.get("cuff") is None:
        return False
    return sum((point[axis] - place["shoulder"][axis]) * place["axis"][axis]
               for axis in range(3)) > place["cuff"]


def finger_room(coords, slot, gloves, armature_fp):
    """How far Halo's finger bones end inside the carried gloves, in units.

    A glove's fingers ride Halo's own finger bones, so those bones have to be
    inside the glove: a glove whose end stops short of a bone tip leaves the
    bone standing out of the end of a finger, which reads as a hand that does
    not line up with the rig however well the arm was carried.

    `gloves` holds the glove's own vertices per side - what `glove_of` says is
    past the wrist - and never the whole arm. A sleeve, a cuff or a bracer runs
    further along the arm than the hand does, so measured over the whole side a
    long bracer would report room the glove does not have, and a glove that
    stopped short of Halo's fingers would look covered by the sleeve behind it.
    Answers (worst gap, how many tips stand past the glove, how many tips were
    seen, how many glove verts were measured), where a negative gap is a tip
    outside the glove, or None when there is no glove to measure.
    """
    worst, outside, seen, held = None, 0, 0, 0
    for side in ("l", "r"):
        span = hand_span(armature_fp, side)
        indices = gloves.get(side) or []
        if span is None or not indices:
            continue
        points = [Vector(coords[slot[index]]) for index in indices]
        head, axis, _length, _knuckle = span
        far = max(sum((point[i] - head[i]) * axis[i] for i in range(3))
                  for point in points)
        for _name, _first, tail in finger_bones(armature_fp, side):
            tip = sum((tail[i] - head[i]) * axis[i] for i in range(3))
            gap = far - tip
            seen += 1
            if gap < 0.0:
                outside += 1
            worst = gap if worst is None else min(worst, gap)
        held += len(points)
    if not seen:
        return None
    return worst, outside, seen, held


def _cross_dot(first, second, third):
    """(first x second) . third, without needing vector objects."""
    return ((first[1] * second[2] - first[2] * second[1]) * third[0]
            + (first[2] * second[0] - first[0] * second[2]) * third[1]
            + (first[0] * second[1] - first[1] * second[0]) * third[2])


def glove_surface(coords, slot, glove, faces):
    """The glove's own skin as triangles, each shell facing outward.

    A face belongs to the glove when all its corners are glove vertices, so a
    face reaching back up into the sleeve is left out.

    Which way a shell faces is decided for the shell as a whole, by whether most
    of its skin looks away from the shell's own middle - the reading `inside_out`
    uses. That matters here because the sign of a distance is what says inside
    or outside: a glove the item wound backwards would otherwise read every bone
    in it as outside. Deciding per triangle would be worse - the skin between
    two fingers faces across the glove rather than away from its middle, and
    flipping those faces would invent gaps in the crotches. A flat plate has no
    middle to look away from, so it keeps the winding the item gave it.
    """
    members = set(glove)
    parent = {}

    def find(index):
        root = index
        while parent.setdefault(root, root) != root:
            root = parent[root]
        while parent[index] != root:
            parent[index], index = root, parent[index]
        return root

    kept = []
    for polygon in faces:
        loop = list(polygon.vertices)
        if len(loop) < 3 or any(index not in members for index in loop):
            continue
        home = find(loop[0])
        for index in loop[1:]:
            other = find(index)
            if other != home:
                parent[other] = home
                home = find(home)
        points = [tuple(float(value) for value in coords[slot[index]])
                  for index in loop]
        triangles = [(points[0], points[first], points[first + 1])
                     for first in range(1, len(points) - 1)]
        kept.append((triangles, points, loop))
    # Grouped only once every face has been joined: a face stored under the
    # root it had at the time leaves a shell in pieces, and each piece then
    # votes on its own middle and can flip the wrong way.
    shells = {}
    for triangles, points, loop in kept:
        shells.setdefault(find(loop[0]), []).append((triangles, points))

    surface = []
    for root in sorted(shells, key=lambda key: min(
            point[0] for entry in shells[key] for point in entry[1])):
        entries = shells[root]
        triangles = [triangle for entry in entries for triangle in entry[0]]
        points = [point for entry in entries for point in entry[1]]
        middle = [sum(point[axis] for point in points) / len(points)
                  for axis in range(3)]
        facing = []
        vote = 0.0
        for a, b, c in triangles:
            side = [b[axis] - a[axis] for axis in range(3)]
            other = [c[axis] - a[axis] for axis in range(3)]
            normal = [side[1] * other[2] - side[2] * other[1],
                      side[2] * other[0] - side[0] * other[2],
                      side[0] * other[1] - side[1] * other[0]]
            centre = [(a[axis] + b[axis] + c[axis]) / 3.0 for axis in range(3)]
            reach = sum(normal[axis] * (centre[axis] - middle[axis])
                        for axis in range(3))
            vote += reach
            facing.append((a, b, c, normal, centre))
        flip = vote < 0.0
        for a, b, c, normal, centre in facing:
            length = math.sqrt(sum(value * value for value in normal))
            if length <= 1e-9:
                continue
            normal = [value / length for value in normal]
            if flip:
                normal = [-value for value in normal]
            radius = max(math.sqrt(sum((corner[axis] - centre[axis]) ** 2
                                       for axis in range(3)))
                         for corner in (a, b, c))
            surface.append((a, b, c, normal, centre, radius))
    return surface


def _segment_nearest(point, head, tail):
    """The point of one segment nearest `point`."""
    along = [tail[axis] - head[axis] for axis in range(3)]
    length_sq = sum(value * value for value in along)
    if length_sq <= 1e-12:
        return list(head)
    factor = sum((point[axis] - head[axis]) * along[axis]
                 for axis in range(3)) / length_sq
    factor = max(0.0, min(1.0, factor))
    return [head[axis] + along[axis] * factor for axis in range(3)]


def skin_gap(point, surface):
    """How far a point is from the glove's skin: outside positive, in units.

    The nearest triangle is found, not just the nearest vertex, so a coarse
    glove does not report gaps its surface does not have. The sign comes from
    that triangle's normal, which `glove_surface` turned away from the glove, so
    a bone behind the skin reads as inside however the item wound its faces.
    """
    best = None
    for a, b, c, normal, centre, radius in surface:
        reach = math.sqrt(sum((point[axis] - centre[axis]) ** 2
                              for axis in range(3))) - radius
        if best is not None and reach > best[2]:
            continue
        offset = sum((point[axis] - a[axis]) * normal[axis]
                     for axis in range(3))
        flat = [point[axis] - normal[axis] * offset for axis in range(3)]
        # Whether the projected point lands over this triangle has to be read
        # without caring which way round its corners go: a glove whose shell
        # had to be turned to face outward keeps its corners in the order it
        # was authored, and a one-sided test then calls every face a miss and
        # measures to its edges instead.
        sides = [_cross_dot([second[axis] - first[axis] for axis in range(3)],
                            [flat[axis] - first[axis] for axis in range(3)],
                            normal)
                 for first, second in ((a, b), (b, c), (c, a))]
        over = all(value >= -1e-9 for value in sides) \
            or all(value <= 1e-9 for value in sides)
        if over:
            nearest = flat
            distance = abs(offset)
        else:
            distance, nearest = None, None
            for first, second in ((a, b), (b, c), (c, a)):
                candidate = _segment_nearest(point, first, second)
                gap = math.sqrt(sum((point[axis] - candidate[axis]) ** 2
                                    for axis in range(3)))
                if distance is None or gap < distance:
                    distance, nearest = gap, candidate
        toward = [point[axis] - nearest[axis] for axis in range(3)]
        signed = distance if sum(toward[axis] * normal[axis]
                                 for axis in range(3)) >= 0.0 else -distance
        if best is None or abs(signed) < best[2]:
            best = (signed, nearest, abs(signed))
    if best is None:
        return None, None
    return best[0], best[1]


def finger_gaps(coords, slot, gloves, faces, armature_fp):
    """How far each of Halo's finger bones sits from the glove's own skin.

    One number per finger bone, in units: positive means the bone stands outside
    the glove by that much, negative means it sits inside, that far from the
    skin. Each bone is measured at its head, middle and tail and reported at the
    point that stands furthest out - the point a pose cannot hide.

    A hand-wide number cannot answer this. "The glove reaches past the farthest
    fingertip" stays true when the thumb's own bones lie outside the glove's
    thumb, because another finger reached furthest, and the thumb is the finger
    a rest pose hides. Measuring every bone against the glove's own surface
    names the thumb instead of averaging it away.

    Returns a list of {side, bone, gap} or None when there is no glove.
    """
    gaps = []
    for side in ("l", "r"):
        indices = gloves.get(side) or []
        if not indices:
            continue
        surface = glove_surface(coords, slot, indices, faces)
        if not surface:
            continue
        for name, head, tail in finger_bones(armature_fp, side):
            worst = None
            for factor in (0.0, 0.5, 1.0):
                point = [head[axis] + (tail[axis] - head[axis]) * factor
                         for axis in range(3)]
                gap, _nearest = skin_gap(point, surface)
                if gap is None:
                    continue
                worst = gap if worst is None else max(worst, gap)
            if worst is None:
                continue
            gaps.append({"side": side,
                         "bone": name[len("frame %s " % side):],
                         "gap": worst})
    return gaps or None


def arm_pieces(object_data, names=ARM_WEIGHTS, share=ARM_SHARE):
    """The item's shells that are arms, with the side and bone each rides.

    A piece joins the first-person set when most of its weight is on an upper
    arm, forearm or hand bone. Shoulder plates do not: a pauldron is worn over
    the shoulder rather than on the arm, so carried with an arm that turns about
    the joint it leaves its place on the body and stands across the arm as a
    plate that belongs to nothing. It stays on the item's body, where it is worn.
    The rule is decided per shell rather than per vertex because a vertex on
    either side of a seam would tear its piece in half; keeping shells whole also
    keeps torso plates out, since by their own weighting those are mostly on the
    spine.
    """
    weights = vertex_weights(object_data)
    pieces = []
    for faces in shell_faces(object_data.data):
        indices = {index for polygon in faces for index in polygon.vertices}
        total = sum(sum(weights[index].values()) for index in indices)
        if total <= 0.0:
            continue
        arm = sum(arm_share(weights[index]) * sum(weights[index].values())
                  for index in indices)
        if arm / total < share:
            continue
        tally = {"l": 0.0, "r": 0.0}
        bones = {}
        for index in indices:
            for name, weight in weights[index].items():
                if name in names:
                    tally["l" if " l " in name else "r"] += weight
                    ridden = SHOULDER_BONES.get(name, name)
                    bones[ridden] = bones.get(ridden, 0.0) + weight
        pieces.append({"faces": faces, "indices": indices,
                       "side": "l" if tally["l"] >= tally["r"] else "r",
                       "bone": max(bones, key=bones.get) if bones else None})
    return pieces


def arm_region(object_data, armature=None, armature_fp=None, names=ARM_WEIGHTS):
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
    straight out in its rest pose. The carry is one similarity per side,
    measured from the arm's own mesh: its long axis onto Halo's arm bones, its
    length laid along them, and its own glove shifted onto Halo's own hand. The
    whole side moves as one - sleeve, glove and every plate worn on them - so it
    keeps its shape exactly and cannot tear, and its groups are renamed to that
    rig's bones with its own weights travelling across. Nothing is re-modelled
    and nothing is re-skinned.
    A hand item never gets here - it rides its hand bone whole.

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

    world = object_data.matrix_world
    # Each side's own arm, as the mesh holds it, then the turn that lays it on
    # Halo's arm. Measured from the mesh rather than from the bones: the item is
    # modelled in the avatar's pose and the bones are Halo's, so the two can
    # disagree about which way an arm points.
    side_points = {"l": [], "r": []}
    side_weights = {"l": [], "r": []}
    # The arm itself is the side's biggest shell - a sleeve, or the body's own
    # arm. A pad is measured from that, not the other way round.
    sleeve = {}
    for piece in pieces:
        for index in piece["indices"]:
            side_points[piece["side"]].append(world @ mesh.vertices[index].co)
            side_weights[piece["side"]].append(weights[index])
        if (piece["side"] not in sleeve
                or len(piece["indices"]) > len(sleeve[piece["side"]]["indices"])):
            sleeve[piece["side"]] = piece
    # Which way Halo's own hand lies on each side, and its own hand's skin.
    # Measured once per side, from the arm mesh the rig file ships.
    flat, hands = {}, {}
    for side in ("l", "r"):
        flat[side], hands[side] = halo_hand(armature_fp, side)
    carry = {side: side_carry(armature, armature_fp, side, points,
                              side_weights[side],
                              middle=[world @ mesh.vertices[index].co
                                      for index in sleeve[side]["indices"]],
                              hand_flat=flat[side],
                              hand_cloud=hands[side])
             for side, points in side_points.items() if points}
    if not any(carry.values()):
        log("no arm axis could be measured: the arms keep the biped's placement")
    left = [value.get("fit_left") for value in carry.values()
            if value and value.get("fit_left") is not None]
    fit_left = max(left) if left else None

    mapping = {}
    if armature_fp is not None:
        for source in ARM_BONES:
            target = FP_BONES.get(source)
            if target and armature_fp.data.bones.get(target) is not None:
                mapping[source] = target

    home, side_of = {}, {}
    # Only the glove's own vertices are measured against Halo's fingers, so
    # they are collected here, from the same wrist line the carry placed the
    # glove by. The sleeve and a bracer are left out of that check.
    gloves = {"l": [], "r": []}
    for piece in pieces:
        for index in piece["indices"]:
            home[index] = piece["bone"]
            side_of[index] = piece["side"]
    order = sorted(home)
    slot = {index: position for position, index in enumerate(order)}
    coords = []
    carried = {}
    # Which sides the item gave no hand weights of its own. Those gloves are the
    # ones that need the wrist to drive them once they are on Halo's rig.
    held_side = {"l": 0.0, "r": 0.0}
    hand_side = {"l": 0.0, "r": 0.0}
    for index in order:
        side = side_of[index]
        for name, weight in weights[index].items():
            held_side[side] += weight
            if name == "bip01 %s hand" % side:
                hand_side[side] += weight
    needs_hand = {side: held_side[side] > 0.0 and
                  hand_side[side] < 0.05 * held_side[side]
                  for side in ("l", "r")}
    filled = set()
    fingered = set()
    finals = {}
    moved_points = {}
    moved_verts = 0
    moved_worst = 0.0
    for index in order:
        point = world @ mesh.vertices[index].co
        moved = point
        place = carry.get(side_of[index])
        if place is None:
            coords.append((float(point[0]), float(point[1]), float(point[2])))
        else:
            moved = place_arm(place, point)
            coords.append(moved)
            if glove_of(place, point):
                gloves[side_of[index]].append(index)
            step = math.sqrt(sum((moved[axis] - point[axis]) ** 2
                                 for axis in range(3)))
            if step > 1e-6:
                moved_verts += 1
                moved_worst = max(moved_worst, step)
        # The item's own weights, renamed to Halo's bones. Its shoulder weight
        # goes on the upper arm, the bone Halo carries a shoulder with. A vertex
        # that is mostly body but came along inside a kept shell rides that
        # shell's own bone rather than being flung at the nearest arm.
        per = {}
        for name, weight in weights[index].items():
            if weight <= 0.0:
                continue
            source = name if name in mapping else SHOULDER_BONES.get(name)
            if source in mapping:
                per[mapping[source]] = per.get(mapping[source], 0.0) + weight
        held = sum(weights[index].values())
        if sum(per.values()) < 0.5 * held and home[index] in mapping:
            per = {mapping[home[index]]: 1.0}
        if not per and home[index] is not None:
            per = {mapping.get(home[index], home[index]): 1.0}
        if per and needs_hand.get(side_of[index]):
            wriste = "frame %s wriste" % side_of[index]
            if wriste in mapping.values():
                share = hand_share(carry.get(side_of[index]), point)
                if share > 0.0:
                    held = sum(per.values())
                    per = {name: weight * (1.0 - share)
                           for name, weight in per.items()}
                    per[wriste] = per.get(wriste, 0.0) + share * held
                    filled.add(side_of[index])
        # The fingers go onto Halo's own finger bones, where the carried glove
        # now lies, so it closes round a weapon the way the game's hands do
        # instead of moving as one lump with the wrist. Only the hand bone's own
        # share is divided: the cuff and the forearm still blend as they did,
        # and the knuckles keep the hand bone, which is where a knuckle plate
        # belongs. A weight can be split without tearing anything - it is the
        # geometry that would tear, and that is already carried whole.
        side = side_of[index]
        if per and side in ("l", "r"):
            wriste = "frame %s wriste" % side
            hand_weight = per.get(wriste, 0.0)
            if hand_weight > 0.0:
                split = finger_split(Vector(moved), armature_fp, side)
                if split is not None and split[0] > 0.0:
                    grip, shares = split
                    # A finger is hand, not forearm. The item gives its glove
                    # no hand bone at all, so the glove's weight runs up the
                    # forearm and only the part `hand_share` faded in can be
                    # given to the fingers - which left the Marine's thumb tip
                    # 42% on the forearm and upper arm. Halo's own fingers carry
                    # no forearm weight, and an elbow bend dragged that 42% out
                    # of the thumb, so the finger's share of the arm bones is
                    # handed over with the hand's, by the same grip fade.
                    arm = ("frame %s forearm" % side,
                           "frame %s upperarm" % side)
                    held = hand_weight + sum(per.get(name, 0.0) for name in arm)
                    for name in arm:
                        if name in per:
                            per[name] *= 1.0 - grip
                    per[wriste] = held * (1.0 - grip)
                    for name, share in shares.items():
                        per[name] = (per.get(name, 0.0)
                                     + held * grip * share)
                    fingered.add(side)
        if sum(per.values()) <= 0.0:
            continue
        finals[index] = per
        moved_points[index] = moved

    # A glove's finger is often one piece with the finger beside it - on the
    # Marine the middle and index share a 30-vertex shell, ring and middle a
    # 25-vertex one, ring and pinky a 28-vertex one - so choosing a finger per
    # vertex tore every shared piece in half as soon as the fingers curled apart:
    # two neighbouring vertices were pulled twelve times apart. A small piece now
    # commits to the one finger most of its weight is on and rides it whole, so
    # the piece stays the shape it was modelled in. The glove's own 226-vertex
    # palm is not a finger and is left to choose per vertex, where it barely
    # reaches past the knuckles anyway.
    if armature_fp is not None and finals:
        finger_names = {name for side in ("l", "r")
                        for chain in finger_chains(armature_fp, side).values()
                        for name, _head, _tail, _flat in chain}
        for piece in pieces:
            indices = [index for index in piece["indices"] if index in finals]
            if not indices or len(indices) > 60:
                continue
            side = side_of[indices[0]]
            if side not in ("l", "r"):
                continue
            tally = {}
            for index in indices:
                for name, weight in finals[index].items():
                    if name in finger_names:
                        key = finger_of(name)
                        if key is not None:
                            tally[key] = tally.get(key, 0.0) + weight
            if len(tally) < 2:
                continue
            key = max(tally, key=tally.get)
            for index in indices:
                finals[index] = ride_chain(finals[index], Vector(moved_points[index]),
                                           armature_fp, side, key)

    # Seat the glove's thumb guard in the palm. The guard sits proud of the
    # glove and Halo's thumb bone runs outside it, so weighting all of it to the
    # thumb swings the plate off the hand when the thumb bends, and weighting it
    # all to the hand leaves the thumb dead. The share of the hand bone therefore
    # falls off along the thumb: most of it at the base, little at the tip.
    seated = {}
    thumb_members = {}
    if armature_fp is not None and finals:
        for side in ("l", "r"):
            entries = finger_chains(armature_fp, side).get("thumb")
            if not entries:
                continue
            # Only a shell that is the guard itself is re-seated. A palm vertex
            # that merely brushes the thumb belongs to the palm's shell, and
            # moving it away from the vertices beside it tears the palm.
            thumb_members[side] = [index for index in order
                                   if index in finals and side_of[index] == side
                                   and sum(weight for name, weight
                                           in finals[index].items()
                                           if finger_of(name) == "thumb") > 0.05]
            guard_shell = set()
            for piece in pieces:
                indices = [index for index in piece["indices"]
                           if index in finals and side_of[index] == side]
                if not indices:
                    continue
                held = sum(1 for index in indices
                           if sum(weight for name, weight in finals[index].items()
                                  if finger_of(name) == "thumb") >= 0.5)
                if held * 2 >= len(indices):
                    guard_shell.update(indices)
            seated[side] = seat_thumb(finals, moved_points, entries,
                                      "frame %s wriste" % side,
                                      side=side, side_of=side_of,
                                      only=guard_shell)

    for index in order:
        per = finals.get(index)
        if not per:
            continue
        total = sum(per.values())
        if total <= 0.0:
            continue
        for name, weight in per.items():
            carried.setdefault(name, []).append((slot[index], weight / total))

    if filled:
        log("hand weights: the item gave %s side(s) no hand bone, so the glove "
            "runs from the forearm to Halo's hand along the arm"
            % "".join(sorted(filled)))
    if fingered:
        log("finger weights: the glove's fingers ride Halo's own finger bones "
            "on %s side(s), so it closes round a weapon as the game's hands do"
            % "".join(sorted(fingered)))
    for side in sorted(carry):
        place = carry[side]
        if place is not None:
            log("%s arm: one turn, scaled x%.2f, %s"
                % (side, place["scale"],
                   "its glove centred on Halo's own hand"
                   if place.get("anchor") == "hand"
                   else "its sleeve centred on Halo's bone"))
            if place.get("glove") == "flat":
                log("%s arm: its glove turned %.0f degrees about the arm, so its "
                    "own flat lies in Halo's hand" % (side, place["twist"]))
            elif place.get("glove") == "round":
                log("%s arm: its glove is too round to say which way round it "
                    "goes, so it keeps the roll the item gave it" % side)

    # The glove's thumb is the item's own guard, and it does not sit where
    # Halo's thumb does: measured on the Marine it runs 31-36 degrees off
    # Halo's thumb chain and its middle stands 1.5 units past the chain's end,
    # which is why it reads as a fat finger lying along the index. That is the
    # item's shape, and it is reported rather than moved. Turning the guard onto
    # the chain was tried both ways and is worse both times: about the chain's
    # joint it swung the whole guard off the bones (all three thumb bones 1.5
    # units outside it), and about its own base, re-centred on the chain, it tore
    # the glove where the guard joins it (24 edges past x3) and still left the
    # base bones outside. What makes a thumb read wrong in game is the weight it
    # deforms with, and that is fixed above: it is weighted along its own chain,
    # so its base moves with its base bone, and none of it rides the forearm.
    #
    # The guard also sits proud of the glove, and Halo's thumb bone runs outside
    # it, so bending the thumb swings the plate off the palm and opens the gap
    # underneath. Weighting all of it to the thumb bone does exactly that (posed
    # 30/25/20 it lifts clear and stretches its edges x2.65); weighting all of it
    # to the hand leaves it rigid and the thumb dead. So it is shared: most of
    # the hand at the base, most of the thumb at the tip. Posed the same way that
    # keeps the plate on the palm and halves the stretch to x1.86, and a full
    # grip stays under x2.5 with no edge past x3.
    if armature_fp is not None:
        for side in ("l", "r"):
            entries = finger_chains(armature_fp, side).get("thumb")
            if not entries:
                continue
            points = []
            for _name, head, tail, _flat in entries:
                for step in range(5):
                    part = step / 4.0
                    points.append([head[k] + (tail[k] - head[k]) * part
                                   for k in range(3)])
            mine = [(index, 1.0) for index in thumb_members.get(side, [])]
            if len(mine) < 8:
                continue
            gaps = [min(math.dist(point, coords[slot[index]])
                        for index, _weight in mine) for point in points]
            solid = [index for index, _weight in mine]
            lying = (arm_direction([tuple(coords[slot[index]]) for index in solid])
                     if len(solid) >= 12 else None)
            base = points[0]
            want = [points[-1][k] - base[k] for k in range(3)]
            reach = math.sqrt(sum(value * value for value in want))
            off = 0.0
            if lying is not None and reach > 1e-6:
                want = [value / reach for value in want]
                off = math.degrees(math.acos(max(-1.0, min(1.0, sum(
                    lying[k] * want[k] for k in range(3))))))
                # A guard is nearly a line, so its own direction can come out
                # either way round; report the angle between the lines.
                off = min(off, 180.0 - off)
            log("%s thumb: %d vert(s) weighted along its own chain, %d of them "
                "the guard, carried %.1f units back into the palm so its root "
                "rides the hand; guard %.1f degrees off Halo's thumb chain, "
                "worst bone gap %.2f units - left where the item put it"
                % (side, len(mine), len(seated.get(side, [])), SEAT_REACH,
                   off, max(gaps)))

    faces, flips = [], []
    turned_out = 0
    for piece in pieces:
        flip = inside_out(piece["faces"], coords, slot)
        if flip:
            turned_out += 1
        faces.extend(piece["faces"])
        flips.extend([flip] * len(piece["faces"]))
    if turned_out:
        log("%d shell(s) of %s were inside out and are written the right way "
            "round, so their backs are not blank" % (turned_out, object_data.name))
    copy = bpy.data.meshes.new("%s arms" % mesh.name)
    copy.from_pydata(coords, [],
                     [tuple(slot[index] for index in
                            (reversed(polygon.vertices) if flip
                             else polygon.vertices))
                      for polygon, flip in zip(faces, flips)])
    copy.update()
    for material in mesh.materials:
        copy.materials.append(material)
    for position, polygon in enumerate(faces):
        copy.polygons[position].material_index = polygon.material_index
        copy.polygons[position].use_smooth = polygon.use_smooth
    # from_pydata builds its loops in face order and each face's vertex order,
    # which is the same order the source polygons' loop_indices are in.
    old_loops = [index for polygon, flip in zip(faces, flips)
                 for index in (reversed(polygon.loop_indices) if flip
                               else polygon.loop_indices)]
    for layer in mesh.uv_layers:
        target = copy.uv_layers.new(name=layer.name)
        for position, loop_index in enumerate(old_loops):
            target.data[position].uv = layer.data[loop_index].uv
    arms = bpy.data.objects.new("%s arms" % object_data.name, copy)
    if fit_left is not None:
        arms["fit_angle"] = fit_left
        log("the fit left %.2f deg on the sleeve, by its own measure" % fit_left)
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
    # A vertex carried by the wrong bone tears the shell it belongs to. Distance
    # from the bones is no use for that - a pauldron is legitimately far from
    # them - so this compares every edge with the length it had before, which
    # only a torn or flung shell changes.
    torn, torn_worst, seen = 0, 1.0, 0
    for piece in pieces:
        for polygon in piece["faces"]:
            loop = list(polygon.vertices)
            for first, second in zip(loop, loop[1:] + loop[:1]):
                if first not in slot or second not in slot:
                    continue
                was = (object_data.matrix_world @ mesh.vertices[first].co
                       - object_data.matrix_world @ mesh.vertices[second].co).length
                if was <= 1e-6:
                    continue
                now = (Vector(coords[slot[first]])
                       - Vector(coords[slot[second]])).length
                seen += 1
                ratio = max(now / was, was / max(now, 1e-6))
                torn_worst = max(torn_worst, ratio)
                if ratio > 3.0:
                    torn += 1
    arms["torn_edges"] = torn
    arms["torn_worst"] = torn_worst
    if torn:
        log("%d of %d edge(s) stretched more than 3x (worst x%.1f) - the shell "
            "was torn by the carry" % (torn, seen, torn_worst))
    fit = arm_fit([Vector(point) for point in coords], armature_fp, arms)
    if fit is not None:
        arms["fit_mean"] = fit[0]
        arms["fit_worst"] = fit[1]
        log("fit to Halo's own arms: mean %.2f, worst %.2f units" % fit)
    # The angle, measured by a rule the fit does not use, so a run says what
    # the arm actually looks like instead of what the fit aimed at.
    angles = sleeve_angle(arms, armature_fp)
    if angles:
        arms["sleeve_angles"] = ", ".join(
            "%s %.2f" % (side, value) for side, value in sorted(angles.items()))
        arms["sleeve_angle_worst"] = max(angles.values())
        log("sleeve angle vs Halo's own arm (widest direction, not the fit's "
            "rule): %s deg" % arms["sleeve_angles"])
    ends = sleeve_angle(arms, armature_fp, rule="ends")
    if ends:
        arms["sleeve_ends"] = ", ".join(
            "%s %.2f" % (side, value) for side, value in sorted(ends.items()))
        log("sleeve angle vs Halo's own arm (line between the ends): %s deg"
            % arms["sleeve_ends"])
    # The glove's fingers ride Halo's finger bones, so those bones have to be
    # inside the glove. This is the check a person makes in the viewport: bones
    # standing out of the fingertips mean the arm stopped short of the hand.
    room = finger_room(coords, slot, gloves, armature_fp) \
        if armature_fp is not None else None
    if room is not None:
        arms["finger_room"] = room[0]
        arms["finger_outside"] = room[1]
        arms["finger_glove"] = room[3]
        if room[1]:
            log("fingers: %d of Halo's %d finger bone tip(s) stand past the "
                "glove (%.2f units short) - the glove is shorter than the hand"
                % (room[1], room[2], -room[0]))
        else:
            log("fingers: the glove reaches %.2f units past Halo's farthest "
                "finger bone tip (%d glove vert(s), measured on the glove "
                "only)" % (room[0], room[3]))
    elif armature_fp is not None:
        # Nothing past the wrist means nothing to check: saying so is better
        # than reporting the sleeve's reach as if it were a hand.
        arms["finger_glove"] = 0
        log("fingers: no glove past the wrist to measure, so the finger bones "
            "were not checked")
    # Every finger bone against the glove's own skin. The line above answers
    # "does the glove reach past Halo's fingers"; this answers "is each finger
    # of Halo's skeleton inside its own finger of the glove", which is the one
    # a thumb sitting outside its glove can fail while the other passes.
    gaps = finger_gaps(coords, slot, gloves,
                       [polygon for piece in pieces
                        for polygon in piece["faces"]], armature_fp) \
        if armature_fp is not None else None
    if gaps:
        outside = [entry for entry in gaps if entry["gap"] > 0.0]
        worst = max(gaps, key=lambda entry: entry["gap"])
        arms["finger_bones_checked"] = len(gaps)
        arms["finger_bones_outside"] = len(outside)
        arms["finger_worst_name"] = "%s %s" % (worst["side"], worst["bone"])
        arms["finger_worst"] = worst["gap"]
        arms["finger_lines"] = "\n".join(
            "%s %-12s %+.2f %s"
            % (entry["side"], entry["bone"], entry["gap"],
               "OUTSIDE" if entry["gap"] > 0.0 else "inside")
            for entry in gaps)
        if outside:
            log("fingers: %d of Halo's %d finger bone(s) stand outside the "
                "glove - %s"
                % (len(outside), len(gaps),
                   ", ".join("%s %s %+.2f" % (entry["side"], entry["bone"],
                                               entry["gap"])
                             for entry in outside[:4])))
        else:
            log("fingers: all %d of Halo's finger bones sit inside the glove, "
                "the nearest to the skin %s at %.2f units"
                % (len(gaps), arms["finger_worst_name"],
                   abs(arms["finger_worst"])))
    if any(carry.values()) and not moved_verts:
        log("%s: every arm weight sits on a bone with no first-person frame, so "
            "nothing was carried - report.txt and the file's own note say so"
            % arms.name)
    log("cut %s: %d of %d vert(s), %d face(s) in %d shell(s), %s, on %s"
        % (arms.name, len(order), len(mesh.vertices), len(faces), len(pieces),
           ("%d side(s) turned onto Halo's fp rig, moved %d vert(s) up to "
            "%.2f units" % (sum(1 for place in carry.values() if place),
                            moved_verts, moved_worst))
           if any(carry.values()) else "kept in place",
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
            # The copy came off the body, so it carries the body's biped
            # groups. Those bones are not on the first-person rig: left in
            # place every vertex keeps a second weight on a node the arms'
            # .jms does not have, and tool.exe is handed a model with every
            # one of its weights on no node. A rigid bind is one bone, so the
            # slate is cleared first.
            for group in list(arms.vertex_groups):
                arms.vertex_groups.remove(group)
            record["arms_binding"] = skin(arms, armature_fp, rigid=True)
            return arms, armature_fp
        arms, rig = arm_region(merged, armature, armature_fp)
        if arms is not None:
            worst = meta(arms, "carried_units")
            if meta(arms, "torn_edges"):
                record["arms_torn"] = (
                    "%d edge(s) stretched more than 3x (worst x%.1f) - the shell "
                    "was torn by the carry"
                    % (meta(arms, "torn_edges"), meta(arms, "torn_worst")))
            if meta(arms, "sleeve_angles"):
                record["arms_angle"] = (
                    "sleeve angle vs Halo's own arm: %s deg (widest direction, "
                    "not the rule the fit optimised)" % meta(arms, "sleeve_angles"))
            else:
                # Better a line that says nothing could be measured than a
                # report that is silent about the angle it was asked for.
                record["arms_angle"] = (
                    "sleeve angle vs Halo's own arm: not measured - the arms do "
                    "not carry the upper arm and forearm skin Halo's arm does")
            if meta(arms, "fit_angle") is not None:
                record["arms_fit_angle"] = (
                    "the fit left %.2f deg on the sleeve, by its own measure"
                    % meta(arms, "fit_angle"))
            if meta(arms, "fit_worst") is not None:
                record["arms_fit"] = ("stands in Halo's own arms to within "
                                      "%.2f units (mean %.2f)"
                                      % (meta(arms, "fit_worst"),
                                         meta(arms, "fit_mean")))
            glove = meta(arms, "finger_glove")
            if glove is not None:
                if not glove:
                    record["arms_fingers"] = (
                        "no glove past the wrist, so the finger bones were not "
                        "measured")
                elif meta(arms, "finger_outside"):
                    record["arms_fingers"] = (
                        "%d of Halo's finger bone tips stand past the glove "
                        "(%.2f units short of them, %d glove vert(s)) - the "
                        "glove is shorter than the hand"
                        % (meta(arms, "finger_outside"),
                           -meta(arms, "finger_room"), glove))
                else:
                    record["arms_fingers"] = (
                        "the glove reaches %.2f units past Halo's farthest "
                        "finger bone tip (%d glove vert(s))"
                        % (meta(arms, "finger_room"), glove))
            # One line per finger bone, plus a summary: whether each of Halo's
            # finger bones is inside the glove's own finger, or how far outside.
            lines = meta(arms, "finger_lines")
            if lines:
                record["arms_finger_bones"] = lines.split("\n")
                checked = meta(arms, "finger_bones_checked") or 0
                outside = meta(arms, "finger_bones_outside") or 0
                name = meta(arms, "finger_worst_name") or ""
                gap = meta(arms, "finger_worst") or 0.0
                if outside:
                    record["arms_fingers_bones"] = (
                        "%d of Halo's %d finger bone(s) stand outside the glove "
                        "- worst %s at %+.2f units"
                        % (outside, checked, name, gap))
                else:
                    record["arms_fingers_bones"] = (
                        "all %d of Halo's finger bones sit inside the glove - "
                        "nearest the skin %s at %.2f units"
                        % (checked, name, abs(gap)))
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


# How far a vertex's weights are pulled toward its neighbours', and for how
# many passes. Distance weighting alone gives every vertex the bones nearest
# to it and nothing else, so two vertices either side of a sleeve's ring can
# end up on different bones. Blender hides that when the armature is left at
# rest, and Halo does not: posing the arms tears the sleeve into bands and
# drags its edges into spikes. Measured on this item's own armour, a 45 degree
# shoulder and elbow bend stretched 128 of 12232 edges more than 3x, worst
# x11.33 - which is the banded sleeve in the game. Averaging each vertex with
# the vertices its edges reach makes a shell share its influences across the
# joint instead, so the same pose bends it rather than ripping it.
SMOOTH_PASSES = 4
SMOOTH_OWN = 0.5


def smooth_weights(weights, mesh, passes=SMOOTH_PASSES, keep=2):
    """Average each vertex's bone weights with its edge neighbours'.

    ``weights`` is one {bone_name: weight} per vertex, in mesh order. A pass
    keeps half of a vertex's own weights and takes half from the vertices an
    edge away, then Halo's two-influence limit is applied by keeping each
    vertex's two heaviest bones and renormalising them to 1. Edges only exist
    inside a shell, so no weight crosses the gap between an item's parts.
    """
    inside = [[] for _ in mesh.vertices]
    for edge in mesh.edges:
        first, second = edge.vertices
        inside[first].append(second)
        inside[second].append(first)
    for _ in range(passes):
        blended = []
        for index, own in enumerate(weights):
            shared = {name: value * SMOOTH_OWN for name, value in own.items()}
            near = inside[index]
            if near:
                share = (1.0 - SMOOTH_OWN) / len(near)
                for other in near:
                    for name, value in weights[other].items():
                        shared[name] = shared.get(name, 0.0) + value * share
            blended.append(shared)
        weights = blended
    trimmed = []
    for own in weights:
        top = sorted(own.items(), key=lambda pair: -pair[1])[:keep]
        total = sum(value for _, value in top) or 1.0
        trimmed.append({name: value / total for name, value in top})
    return trimmed


def smooth_by_position(weights, mesh, passes=SMOOTH_PASSES, keep=2, kin=None):
    """Average bone weights over positions, not over vertex indices.

    The export splits every face off its neighbours - 5,756 triangles carry
    17,268 vertices, three each - so there is no edge between one triangle and
    the next. An edge-based pass therefore sees every triangle as an island and
    lets neighbours drift apart: that is the crack in the armour you can see
    straight through. Coincident vertices are one point of the real surface and
    have to ride one blend, so the weights are averaged where the surface is,
    not where the exporter split it.
    """
    spots = {}
    where = []
    for vertex in mesh.vertices:
        co = vertex.co
        where.append(spots.setdefault((round(co.x, 5), round(co.y, 5),
                                       round(co.z, 5)), len(spots)))
    ring = [set() for _ in range(len(spots))]
    for edge in mesh.edges:
        a, b = where[edge.vertices[0]], where[edge.vertices[1]]
        if a != b:
            ring[a].add(b)
            ring[b].add(a)
    field = [{} for _ in range(len(spots))]
    count = [0] * len(spots)
    for slot, own in zip(where, weights):
        for name, value in own.items():
            field[slot][name] = field[slot].get(name, 0.0) + value
        count[slot] += 1
    for slot in range(len(spots)):
        total = count[slot] or 1
        field[slot] = {name: value / total for name, value in field[slot].items()}
    for _ in range(passes):
        blended = []
        for slot, own in enumerate(field):
            shared = {name: value * SMOOTH_OWN for name, value in own.items()}
            near = ring[slot]
            if near:
                share = (1.0 - SMOOTH_OWN) / len(near)
                for other in near:
                    for name, value in field[other].items():
                        shared[name] = shared.get(name, 0.0) + value * share
            blended.append(shared)
        field = blended
    # One entry per vertex, not one per position: several vertices share a
    # position, and every one of them must come back with that position's blend.
    out = []
    for slot in where:
        ranked = sorted(field[slot].items(), key=lambda pair: -pair[1])
        if kin and ranked:
            # Halo gives a vertex two bones, so wherever three meet one is
            # dropped - and two points a millimetre apart can drop different
            # ones, then travel with unrelated limbs. A real rig only ever
            # blends a bone with the one it hangs from or the ones hanging from
            # it, so the second influence is taken from that family first.
            family = kin.get(ranked[0][0]) or ()
            ranked = ([pair for pair in ranked if pair[0] in family]
                      + [pair for pair in ranked if pair[0] not in family])
        top = ranked[:keep]
        total = sum(value for _, value in top) or 1.0
        out.append({name: value / total for name, value in top})
    return out


def bone_tree(armature, names):
    """Which bone each bone hangs from, and which hang from it."""
    parent = {}
    children = {name: [] for name in names}
    for bone in armature.data.bones:
        if bone.name not in children:
            continue
        up = bone.parent
        while up is not None and up.name not in children:
            up = up.parent
        if up is not None:
            parent[bone.name] = up.name
            children[up.name].append(bone.name)
    return parent, children


def bone_family(armature, names):
    """Each deform bone with itself, the bone it hangs from, and its children."""
    family = {name: {name} for name in names}
    for bone in armature.data.bones:
        if bone.name not in family:
            continue
        if bone.parent and bone.parent.name in family:
            family[bone.name].add(bone.parent.name)
            family[bone.parent.name].add(bone.name)
    return family


def settle(weights, mesh, passes, chunk=None):
    """Smooth in short chunks, trimming to two bones after each one.

    Halo's vertices carry two influences, so wherever three bones meet - the
    shoulder is clavicle, neck and upperarm all within a millimetre of each
    other - the trim has to drop one, and two neighbouring points can drop
    different ones: one rides clavicle and neck, the next clavicle and
    upperarm, and at eighty degrees those two points go their separate ways.
    Trimming after every short chunk instead of once at the end lets each
    choice spread to its neighbour before the next trim, so the surface agrees
    on which pair it is riding and the join between them narrows to one band.
    """
    chunk = chunk or PLATE_SETTLE
    left = passes
    while left > 0:
        step = min(chunk, left)
        weights = smooth_by_position(weights, mesh, passes=step)
        left -= step
    return weights


# The group the ported body's own vertices are tagged with before the join.
# It is read once, at the first skinning, and removed again: it is not a bone
# and must never reach a .jms, where every vertex group above the node count
# would be a node the file does not declare.
PORT_GROUP = "ported_body"

# How many points of the avatar's body each armour vertex reads its weights
# from. One is a cliff: the blend jumps when the nearest body point changes,
# and that jump is a stretched plate. A few, weighted by distance, is the same
# rule with no cliff in it.
BODY_BLEND = 4

# How many points of the avatar's body are needed before it is a body at all.
# A costume exports its body cut away before the plates are bound - this item
# keeps 34 triangles of neck - and a patch that small is not a body to read
# weights off: every armour point takes its share from the same handful of neck
# points, and merged shares hand a thigh point a hand bone. Past this many points
# the avatar really is under the armour and the transfer is worth doing.
BODY_TRANSFER_MIN = 400

# How many smoothing passes run between each trim to two bones. Short chunks
# let the surface settle on one pair instead of flapping between three.
PLATE_SETTLE = 6

# How many times the transferred weights are averaged along each shell's own
# edges. A plate converges to one blend - a solid plate cannot tear itself -
# while the suit is long enough that its gradient survives.
PLATE_SMOOTH_PASSES = 300

# Poses the weighting is tested against, and what counts as being drawn apart.
# These are the angles tools/test_halo_skin.py measures the exported file at, so
# the build and the check are looking for the same thing from opposite ends.
TEAR_POSES = ((45.0, 45.0), (80.0, 60.0), (20.0, 20.0))
TEAR_LIMIT = 1.6
TEAR_ROUNDS = 30

# How a torn point's bones are chosen: one bone, or two in one of these shares.
# The share matters as much as the pair - a collar edge needs a little of the
# arm's swing, not half of it.
POLISH_FRACS = (0.85, 0.75, 0.6, 0.5, 0.4, 0.25, 0.15)

# What changing a point's riding costs, beyond what continuity needs. Without
# it the solver roams over pairs that fit equally well and the field loses the
# body it was transferred from; with it, a point that can stay put does.
POLISH_STIFF = 0.03

# Rings of points around a torn strip that may take part, so the change has
# somewhere to spread instead of stopping dead at the strip itself.
POLISH_RINGS = 1

# Folding an edge is as bad as stretching one - a folded triangle draws as a
# dark sliver - so the search must not buy a tear's fix with a fold.
POLISH_SQUASH = 3.0

# The surface's own zero-length duplicates, which the checker does not measure
# either. An edge this short says nothing about what a pose draws.
TEAR_FLOOR = 0.2


def posed_transforms(armature, shoulder, elbow, more=None):
    """posed x inverse(bind) for every node, which is what Halo applies.

    `objects/models.c` moves every vertex by that product, so shaping the
    weights against it is shaping them against the game rather than against
    Blender's own deform. The frames come from the node block the exporter
    writes, not from Blender's bones, because Halo turns a node about its
    parent's X while a bone's Euler turn is about its own axis: posed through
    Blender the build's own worst edge read x2.94 where the file it produced
    measured x3.56, and no single Euler channel matched.
    """
    order, _index_of, rows, _checksum = jms_node_rows(armature)
    labels = [row[0] for row in rows]
    frames = halo_pose.shifts([row[1] for row in rows], [row[2] for row in rows],
                              [row[3] for row in rows], [row[4] for row in rows],
                              labels, shoulder, elbow, more)
    out = {}
    for index, (rotation, shift) in frames.items():
        out[labels[index]] = Matrix((
            (rotation[0][0], rotation[0][1], rotation[0][2], shift[0]),
            (rotation[1][0], rotation[1][1], rotation[1][2], shift[1]),
            (rotation[2][0], rotation[2][1], rotation[2][2], shift[2]),
            (0.0, 0.0, 0.0, 1.0)))
    return out


def skin_point_graph(weights, mesh, armature, world, names):
    """The surface as points: coincident vertices share one blend and one graph.

    Returned as the slot of every vertex, each slot's rest position, its blend,
    the slots an edge joins it to, and the game's own pose matrices.

    The graph is the export's own triangles, not Blender's mesh edges, because
    the export fans every polygon from its first corner: a quad therefore
    carries a diagonal that ``mesh.edges`` does not have, and the export is what
    the game and the checker see. Searching a graph without those diagonals
    fixes what it can see and walks away from the tear it cannot - measured,
    thirty rounds took the worst edge from x4.81 back to x7.58 and folded
    fourteen edges doing it.
    """
    into = armature.matrix_world.inverted()
    spots = {}
    where = []
    for vertex in mesh.vertices:
        co = vertex.co
        where.append(spots.setdefault((round(co.x, 5), round(co.y, 5),
                                       round(co.z, 5)), len(spots)))
    rest = [None] * len(spots)
    field = [None] * len(spots)
    for vertex, slot, own in zip(mesh.vertices, where, weights):
        if rest[slot] is None:
            rest[slot] = into @ (world @ vertex.co)
            field[slot] = dict(own)
    ring = [[] for _ in range(len(spots))]
    for polygon in mesh.polygons:
        corners = list(polygon.vertices)
        for at in range(1, len(corners) - 1):
            for a, b in ((corners[0], corners[at]),
                         (corners[at], corners[at + 1]),
                         (corners[at + 1], corners[0])):
                first, second = where[a], where[b]
                if first != second and second not in ring[first]:
                    ring[first].append(second)
                    ring[second].append(first)
    # The whole body, not just the arms: the shapes the run, walk, crouch and
    # turn animations put a model through are hips, knees, ankles, spine and
    # neck, and none of those was ever measured before.
    _order, _index_of, rows, _checksum = jms_node_rows(armature)
    labels = [row[0] for row in rows]
    moves = [posed_transforms(armature, 0.0, 0.0,
                              more=halo_pose.pose_nodes(labels, pose))
             for pose in halo_pose.BODY_POSES]
    return where, rest, field, ring, moves


def settle_tears(weights, mesh, armature, world, names, family):
    """Average the ends of every edge the game would draw stretched.

    A first pass only. It carries a torn strip towards a single blend, which is
    what lets the pair search below find a clean surface: started from the raw
    transfer instead, that search ended with 28 edges still past x3 at forty
    five degrees, and from this field with none.

    It cannot finish the job on its own. Halo gives a vertex two bones, so
    wherever four meet the trim has to drop two, and it drops them differently
    on each side: the averaged blend is snapped back to the same two blocks every
    round, which is why this used to plateau with the collar still torn.
    """
    where, rest, field, ring, moves = skin_point_graph(
        weights, mesh, armature, world, names)
    pairs = sorted({(a, b) if a < b else (b, a)
                    for a in range(len(rest)) for b in ring[a]})
    rounds = 0
    for _round in range(TEAR_ROUNDS):
        torn = set()
        for move in moves:
            placed = []
            for point, ride in zip(rest, field):
                total = Vector((0.0, 0.0, 0.0))
                for name, share in ride.items():
                    moved = move.get(name)
                    if moved is not None:
                        total += (moved @ point) * share
                placed.append(total)
            for a, b in pairs:
                was = (rest[a] - rest[b]).length
                if was < TEAR_FLOOR:
                    continue
                if (placed[a] - placed[b]).length / was > TEAR_LIMIT:
                    torn.add(a)
                    torn.add(b)
        if not torn:
            break
        rounds += 1
        settled = {}
        for slot in torn:
            blend = dict(field[slot])
            near = [other for other in ring[slot] if other in torn]
            for other in near:
                for name, value in field[other].items():
                    blend[name] = blend.get(name, 0.0) + value / (1 + len(near))
            ranked = sorted(blend.items(), key=lambda pair: -pair[1])
            kin = family.get(ranked[0][0]) or ()
            # Only bones this point is jointed to may carry it. Keeping the
            # others behind the jointed ones still let a second bone through
            # when only one was jointed, which is how a calf came to blend with
            # a hand: two bones no joint connects move far apart and the edge
            # between them is drawn as a blade.
            jointed = [pair for pair in ranked if pair[0] in kin]
            top = (jointed or ranked[:1])[:2]
            total = sum(value for _, value in top) or 1.0
            settled[slot] = {name: value / total for name, value in top}
        for slot, own in settled.items():
            field[slot] = own
    return [field[slot] for slot in where], rounds


def relax_tears(weights, mesh, armature, world, names):
    """Choose each torn point's bones so the game's own pose draws it unbroken.

    Smoothing makes a field continuous; it does not make it continuous *as a
    pose moves it*. Two points a millimetre apart can hold nearly the same two
    weights and still be pulled apart, because the second weight leans to a bone
    the first does not ride. That is what the collar does: the yoke's rim rides
    neck and head, the pad hanging off the shoulder rides clavicle and upperarm,
    and they meet along a strip half a unit wide - so half the arm's swing lands
    across that one edge. Measured at eighty degrees it stretched x11.14.

    Averaging the two ends cannot fix it. Halo gives a vertex two bones, so
    wherever four meet the trim has to drop two, and it drops them differently
    on each side; the averaged blend is snapped back to the same two blocks
    every round, which is why this used to plateau. So instead of averaging,
    each point of the torn strip (and one ring around it) is given the bone pair
    - one bone, or two in the shares POLISH_FRACS - that leaves the edges around
    it closest to their rest length at the poses the checker uses, with a small
    charge for changing what the body transfer gave it. A point outside that
    strip is never touched, which is what keeps the shape and the arm's follow.

    It works on positions, not vertices: the export splits every triangle off
    its neighbours, so three copies of one point could take three different
    answers and the surface would come apart - 1,107 seams, measured, when this
    was done by vertex index.

    Measured on this item's armour, worst edge at 45/45 fell x6.74 to x2.06 and
    at 80/60 x11.14 to x2.72, with no edge past x3 at any pose and no seam.
    """
    where, rest, field, ring, moves = skin_point_graph(
        weights, mesh, armature, world, names)

    def placed(slot, ride, move):
        """Where one point lands, riding `ride`, at one pose."""
        total = Vector((0.0, 0.0, 0.0))
        point = rest[slot]
        for name, share in ride.items():
            moved = move.get(name)
            if moved is not None:
                total += (moved @ point) * share
        return total

    def charge(ratio):
        """What an edge costs the search: long is bad, and folded is too."""
        if ratio >= 1.0:
            return (ratio - 1.0) ** 2
        return POLISH_SQUASH * (1.0 / max(ratio, 1e-6) - 1.0) ** 2

    def torn_edges():
        """Every edge the game would draw pulled or folded, and the worst."""
        worst = 0.0
        found = set()
        for move in moves:
            land = [placed(slot, field[slot], move) for slot in range(len(rest))]
            for a in range(len(rest)):
                for b in ring[a]:
                    if b <= a:
                        continue
                    was = (rest[a] - rest[b]).length
                    if was < TEAR_FLOOR:
                        continue
                    ratio = (land[a] - land[b]).length / was
                    # A fold is as visible as a tear - a triangle turned inside
                    # out draws as a dark sliver - so both directions count.
                    if max(ratio, 1.0 / ratio) > worst:
                        worst = max(ratio, 1.0 / ratio)
                    if ratio > TEAR_LIMIT or ratio < 1.0 / TEAR_LIMIT:
                        found.add(a)
                        found.add(b)
        # Scored by the worst edge first, not by how many edges are over the
        # strip limit. Flattening one x11 tear into a band that peaks at x2.9 is
        # the fix, and the second score preferred leaving the x11 standing
        # because it touched fewer edges - measured, that rejected the very
        # field this search had just found and handed back the tear.
        return found, (round(worst, 3), len(found))

    torn, state = torn_edges()
    # The field the search starts from is the one to beat. Every round is scored
    # and the best-scoring field is what comes out, because one point's better
    # pair can be its neighbour's worse one, and without this the search returns
    # whatever the last round happened to leave behind rather than its best.
    best = (state, [dict(ride) for ride in field])
    band = set()
    rounds = 0
    while torn and rounds < TEAR_ROUNDS:
        rounds += 1
        band |= torn
        for _ in range(POLISH_RINGS):
            band |= {other for slot in list(band) for other in ring[slot]}
        changed = 0
        for slot in sorted(band):
            near = set(field[slot])
            for other in ring[slot]:
                near |= set(field[other])
            bones = sorted(near)
            choices = [{one: 1.0} for one in bones]
            for at, one in enumerate(bones):
                for two in bones[at + 1:]:
                    for share in POLISH_FRACS:
                        choices.append({one: share, two: 1.0 - share})
            own = field[slot]
            pick = None
            for ride in choices:
                cost = 0.0
                for move in moves:
                    here = placed(slot, ride, move)
                    for other in ring[slot]:
                        was = (rest[slot] - rest[other]).length
                        if was < TEAR_FLOOR:
                            continue
                        arrived = placed(other, field[other], move)
                        cost += charge((here - arrived).length / was)
                cost += POLISH_STIFF * sum(
                    abs(ride.get(name, 0.0) - own.get(name, 0.0))
                    for name in set(ride) | set(own))
                if pick is None or cost < pick[0]:
                    pick = (cost, ride)
            if pick[1] != own:
                field[slot] = pick[1]
                changed += 1
        if not changed:
            break
        torn, state = torn_edges()
        if state < best[0]:
            best = (state, [dict(ride) for ride in field])
    field = best[1]
    log("worst edge after the search: x%.2f (%d points past x%.1f)"
        % (best[0][0], best[0][1], TEAR_LIMIT))
    return [field[slot] for slot in where], rounds


def take_port_tag(object_data, mesh):
    """Which vertices came from the avatar's own body, then drop the tag.

    The tag survives the join (Blender merges vertex groups by name) and is kept
    on the object as a plain list, because rebind() deletes every vertex group
    before it skins again and the fit runs between the two skinning passes.
    """
    kept = object_data.get(PORT_GROUP)
    if kept is not None:
        return [int(index) for index in kept]
    group = object_data.vertex_groups.get(PORT_GROUP)
    if group is None:
        return []
    kept = [vertex.index for vertex in mesh.vertices
            if any(entry.group == group.index for entry in vertex.groups)]
    object_data[PORT_GROUP] = kept
    object_data.vertex_groups.remove(group)
    return kept


def transfer_from_body(weights, mesh, ported, world):
    """Give every vertex the weights of the nearest point on the avatar's body.

    The armour is sculpted to sit on that body, so the skin under it is the
    only thing that can say which bones a plate belongs to. Distance weighting
    cannot: a pauldron vertex 40 mm from the forearm's bone and 50 mm from the
    clavicle's gets both, and those two bones turn about axes a metre apart, so
    the plate is drawn as a spike. Whatever the flesh underneath does, the plate
    over it must do exactly - and where the armour has no body under it, the
    nearest point on the body is still the surface it was built to cover.
    """
    if not ported:
        return weights, 0
    tree = kdtree.KDTree(len(ported))
    for slot, index in enumerate(ported):
        tree.insert(world @ mesh.vertices[index].co, slot)
    tree.balance()
    covered = set(ported)
    copied = 0
    for vertex in mesh.vertices:
        if vertex.index in covered:
            continue
        point = world @ vertex.co
        # Snap to the single nearest body vertex and the blend changes the
        # moment the nearest one changes, which on a coarse proxy is a cliff -
        # two armour points a millimetre apart end up on different bones and
        # the plate between them stretches. Taking the few nearest and letting
        # distance decide between them is the same rule, continuous.
        near = tree.find_n(point, BODY_BLEND)
        total = 0.0
        blend = {}
        for _spot, slot, away in near:
            if slot is None:
                continue
            share = 1.0 / max(away, 1e-4) ** 2
            total += share
            for name, value in weights[ported[slot]].items():
                blend[name] = blend.get(name, 0.0) + value * share
        if not total:
            continue
        weights[vertex.index] = {name: value / total for name, value in blend.items()}
        copied += 1
    return weights, copied


ARM_CHAIN = ("upperarm", "forearm", "hand")
CLAVICLES = ("bip01 l clavicle", "bip01 r clavicle")


def hold_the_arms(object_data, armature):
    """A plate that hangs out along the arm rides the arm, not the shoulder.

    Distance alone hands the sleeve to the clavicle: Halo's clavicle runs from
    y 5.98 to 9.02 at the shoulder, and the plates covering the deltoid are
    nearer that short segment than the upper arm's, which starts where the
    clavicle ends. It is the wrong answer for a plate that sits past the joint -
    the clavicle barely turns, so in game the arm swings out of its own sleeve.

    So the shells are looked at one at a time, after the body is stood in Halo's
    pose: a shell out past the clavicle's tail whose weight is its clavicle's is
    handed, whole, to the arm bone nearest it. Whole shells, never vertices - a
    cut across a continuous sleeve is a tear, and a shell with its own edge
    cannot tear from anything.

    It runs only for a body that keeps the pose it authored. A body stood in
    Halo's pose has its sleeve on the arm bone already, so nothing swings out
    from under the pad in game; and a pad built for a horizontal arm, turned
    with the arm into Halo's pose, stands on edge as a spike with the shoulder
    bare behind it. So a stood body leaves its pads on the shoulder cap, where
    the item authored them.
    """
    segments = bone_segments(armature)
    if not all(name in segments for name in CLAVICLES):
        return 0
    chains = {}
    for side in ("l", "r"):
        names = ["bip01 %s %s" % (side, part) for part in ARM_CHAIN]
        if all(name in segments for name in names):
            chains[side] = names
    if not chains:
        return 0
    mesh = object_data.data
    world = object_data.matrix_world
    group_names = {group.index: group.name for group in object_data.vertex_groups}
    root = list(range(len(mesh.vertices)))

    def shell_of(index):
        while root[index] != index:
            root[index] = root[root[index]]
            index = root[index]
        return index

    for edge in mesh.edges:
        one, two = edge.vertices
        first, second = shell_of(one), shell_of(two)
        if first != second:
            root[first] = second
    shells = {}
    for vertex in mesh.vertices:
        shells.setdefault(shell_of(vertex.index), []).append(vertex.index)
    moved = 0
    for indices in shells.values():
        if len(indices) > 2000:
            continue
        owning = {}
        for index in indices:
            for entry in mesh.vertices[index].groups:
                name = group_names.get(entry.group)
                if name:
                    owning[name] = owning.get(name, 0.0) + entry.weight
        if not owning:
            continue
        shoulder = max(owning, key=owning.get)
        if shoulder not in CLAVICLES:
            continue
        centre = sum((world @ mesh.vertices[index].co for index in indices),
                     Vector()) / len(indices)
        if abs(centre.y) < abs(segments[shoulder][1].y) - 0.5:
            continue
        chain = chains.get("l" if centre.y > 0 else "r")
        if not chain:
            continue
        arm = min(chain, key=lambda name: point_segment_distance(
            centre, *segments[name]))
        group = (object_data.vertex_groups.get(arm)
                 or object_data.vertex_groups.new(name=arm))
        for other in object_data.vertex_groups:
            if other.name != arm:
                other.remove(indices)
        group.add(indices, 1.0, "REPLACE")
        moved += 1
    return moved


# How far from a shoulder joint, in Halo units, a plate can sit and still be
# shoulder armour: the pad and the cap of the sleeve, not the collar or the
# chest, whose plates reach the joint too but belong to the spine.
SHOULDER_HOOD = 6.0


def hold_the_shoulders(object_data, armature):
    """Every plate sitting on a shoulder joint is given, whole, to its arm.

    A pad wraps the outside of the joint, and the nearest bone to a point out
    there is no guide: measured on this armour, the plates over BOTH shoulders
    came out of the skin with ``bip01 l thigh`` and ``bip01 r thigh`` as the
    bone most of their vertices rode, with the pelvis under that. Nothing near
    a shoulder is a leg, so that is not a distance that can be tuned - the
    weighting had no part map and the body it was copying from has none either,
    because a costume's body is cut away before the pads are bound.

    So the shells are looked at one at a time, after the pose and after
    ``hold_the_arms``: a shell whose middle sits within SHOULDER_HOOD of a
    shoulder joint, out past the clavicle's tail, and whose bone is neither the
    clavicle nor an arm bone, is shoulder armour that was handed to the torso
    or the leg by accident. It is given, whole, to the upper arm of that side -
    the bone the shoulder turns with - and nothing else about it changes. Whole
    shells only: a plate whose weights are split is a plate that tears.
    """
    segments = bone_segments(armature)
    if not all(name in segments for name in CLAVICLES):
        return 0
    chains = {}
    for side in ("l", "r"):
        names = ["bip01 %s %s" % (side, part) for part in ARM_CHAIN]
        if all(name in segments for name in names):
            chains[side] = names
    if not chains:
        return 0
    mesh = object_data.data
    world = object_data.matrix_world
    group_names = {group.index: group.name for group in object_data.vertex_groups}
    root = list(range(len(mesh.vertices)))

    def shell_of(index):
        while root[index] != index:
            root[index] = root[root[index]]
            index = root[index]
        return index

    for edge in mesh.edges:
        one, two = edge.vertices
        first, second = shell_of(one), shell_of(two)
        if first != second:
            root[first] = second
    shells = {}
    for vertex in mesh.vertices:
        shells.setdefault(shell_of(vertex.index), []).append(vertex.index)
    settled = 0
    for indices in shells.values():
        if len(indices) > 2000:
            continue
        centre = sum((world @ mesh.vertices[index].co for index in indices),
                     Vector()) / len(indices)
        side = "l" if centre.y > 0 else "r"
        chain = chains.get(side)
        if not chain:
            continue
        joint = segments[chain[0]][0]
        if (centre - joint).length > SHOULDER_HOOD:
            continue
        # Outboard of the clavicle's tail: the joint's own cap. Anything inboard
        # of that is the chest and neck, which the spine already holds.
        if abs(centre.y) < abs(segments[CLAVICLES[0 if side == "l" else 1]][1].y) - 1.5:
            continue
        owning = {}
        for index in indices:
            for entry in mesh.vertices[index].groups:
                name = group_names.get(entry.group)
                if name:
                    owning[name] = owning.get(name, 0.0) + entry.weight
        if not owning:
            continue
        shoulder = max(owning, key=owning.get)
        if shoulder in chain or shoulder in CLAVICLES:
            continue
        arm = min(chain, key=lambda name: point_segment_distance(
            centre, *segments[name]))
        group = (object_data.vertex_groups.get(arm)
                 or object_data.vertex_groups.new(name=arm))
        for other in object_data.vertex_groups:
            if other.name != arm:
                other.remove(indices)
        group.add(indices, 1.0, "REPLACE")
        settled += 1
    return settled


# A gap the eye can see, in Halo units. The tear search scores edges by how far
# they stretch as a RATIO, and a ratio hides a long edge's whole gap: an edge
# 1.35 units long drawn to 2.8 times its length opens 3.8 units of hole, and
# x2.8 reads as a pass. 1.0 unit is about 11 mm on a 1.83 m biped.
GAP_LIMIT = 1.0
GAP_ROUNDS = 10


def settle_gaps(weights, mesh, armature, world, names, family):
    """Average the weights across every edge whose pose opens a visible gap.

    The same point graph, the same game poses, the same rule as settle_tears,
    with the thing the eye measures in place of the ratio: the distance the two
    ends of an edge come apart by. Measured on the shipped file, the waist edge
    between a pelvis plate and the spine above it drew 3.8 units apart at a
    twenty degree spine bend while its ratio was only x2.8 - a number the tear
    search was content with. Blending that boundary turns a hole into a crease.
    """
    where, rest, field, ring, moves = skin_point_graph(
        weights, mesh, armature, world, names)
    rounds = 0
    for _round in range(GAP_ROUNDS):
        torn = set()
        for move in moves:
            placed = []
            for point, ride in zip(rest, field):
                total = Vector((0.0, 0.0, 0.0))
                for name, share in ride.items():
                    moved = move.get(name)
                    if moved is not None:
                        total += (moved @ point) * share
                placed.append(total)
            for slot in range(len(rest)):
                for other in ring[slot]:
                    if other <= slot:
                        continue
                    was = (rest[slot] - rest[other]).length
                    if was < 1e-5:
                        continue
                    if abs((placed[slot] - placed[other]).length - was) > GAP_LIMIT:
                        torn.add(slot)
                        torn.add(other)
        if not torn:
            break
        rounds += 1
        settled = {}
        for slot in torn:
            blend = dict(field[slot])
            near = [other for other in ring[slot] if other in torn] or ring[slot]
            for other in near:
                for name, value in field[other].items():
                    blend[name] = blend.get(name, 0.0) + value / (1 + len(near))
            ranked = sorted(blend.items(), key=lambda pair: -pair[1])
            kin = family.get(ranked[0][0]) or ()
            # Only bones this point is jointed to may carry it. Keeping the
            # others behind the jointed ones still let a second bone through
            # when only one was jointed, which is how a calf came to blend with
            # a hand: two bones no joint connects move far apart and the edge
            # between them is drawn as a blade.
            jointed = [pair for pair in ranked if pair[0] in kin]
            top = (jointed or ranked[:1])[:2]
            total = sum(value for _name, value in top) or 1.0
            settled[slot] = {name: value / total for name, value in top}
        for slot, own in settled.items():
            field[slot] = own
    return [field[slot] for slot in where], rounds


# How near a joint a point has to be before it is allowed to blend two bones.
# Everything further out is a plate riding one bone and nothing else: a pauldron
# that is half upperarm and half clavicle is a pauldron that bends, and armour
# does not bend. In Halo units, so 1.5 is about 3 cm on the biped.
PLATE_BAND = 1.5


def hold_the_plates(object_data, armature):
    """Rigid away from the joints, blended only in the band across them.

    The item is armour over a suit. The plates are metal and must not deform; the
    fabric under and between them is what folds, and it only folds where a joint
    is. So a point that blends two jointed bones and stands further than
    PLATE_BAND from the joint they share is given its dominant bone outright,
    and a point inside the band keeps its blend.

    Measured, this is what stops the chest and shoulder plates being drawn bent:
    a plate whose points spread 60/40 and 90/10 across the spine and the clavicle
    is a plate that shears when the spine turns, and it is the fabric's job to
    shear, not the plate's.

    Weights only - no vertex moves, so the shape is untouched.
    """
    segments = bone_segments(armature)
    names = list(segments)
    if not names:
        return 0
    family = bone_family(armature, names)
    mesh = object_data.data
    world = object_data.matrix_world
    group_names = {group.index: group.name for group in object_data.vertex_groups}
    groups = {name: object_data.vertex_groups[name]
              for name in names if object_data.vertex_groups.get(name)}
    snapped = 0
    for vertex in mesh.vertices:
        rides = sorted(((entry.weight, group_names[entry.group])
                        for entry in vertex.groups
                        if entry.group in group_names and entry.weight > 1e-4),
                       reverse=True)
        if len(rides) < 2:
            continue
        one, two = rides[0][1], rides[1][1]
        if two not in (family.get(one) or ()) or one not in groups:
            continue
        # The joint the two bones share: the closest pair of their ends.
        gap, joint = min(((first - second).length, (first + second) / 2.0)
                         for first in segments[one]
                         for second in segments[two])
        if gap > 1e-3:
            continue
        if ((world @ vertex.co) - joint).length <= PLATE_BAND:
            continue
        for other in object_data.vertex_groups:
            if other.name != one:
                other.remove([vertex.index])
        groups[one].add([vertex.index], 1.0, "REPLACE")
        snapped += 1
    return snapped


def settle_outliers(object_data, armature, rounds=4):
    """A point whose neighbours all ride one bone rides that bone too.

    Measured on this armour, ten edges joined a point the weights had put on
    ``bip01 pelvis`` to a point on the clavicle - two bones no joint connects, on
    the side of the chest. The edge between them is drawn 3.8 units apart at a
    twenty degree spine bend: a hole in the chest, from ten stray points.

    Where two thirds of a point's neighbours ride one bone and it rides another,
    it is the odd one out and it takes its neighbours' bone. A point on a real
    boundary has neighbours on both sides and is left alone, and so is every
    point that already agrees with its surface. Weights only.
    """
    mesh = object_data.data
    names = {group.index: group.name for group in object_data.vertex_groups}
    around = [[] for _ in mesh.vertices]
    for edge in mesh.edges:
        one, two = edge.vertices
        around[one].append(two)
        around[two].append(one)
    groups = {group.name: group for group in object_data.vertex_groups}
    moved = 0
    for _round in range(rounds):
        rides = []
        for vertex in mesh.vertices:
            ranked = sorted(((entry.weight, names.get(entry.group))
                             for entry in vertex.groups if entry.group in names),
                            reverse=True)
            rides.append(ranked)
        changed = 0
        for index, ranked in enumerate(rides):
            if not ranked:
                continue
            mine = ranked[0][1]
            votes = {}
            for other in around[index]:
                theirs = rides[other][0][1] if rides[other] else None
                if theirs and theirs != mine:
                    votes[theirs] = votes.get(theirs, 0) + 1
            if not votes:
                continue
            best = max(votes, key=votes.get)
            if votes[best] < max(2, (2 * len(around[index])) // 3):
                continue
            group = groups.get(best)
            if group is None:
                continue
            for other in object_data.vertex_groups:
                if other.name != best:
                    other.remove([index])
            group.add([index], 1.0, "REPLACE")
            rides[index] = [(1.0, best)]
            changed += 1
        moved += changed
        if not changed:
            break
    return moved


def repair_tears(object_data, armature):
    """Run the game-pose tear search again, after the plates were re-hung.

    ``skin()`` shapes the weights against Halo's own poses, and then
    ``hold_the_arms()`` and ``hold_the_shoulders()`` hand whole plates to the arm
    bone. That is the right answer for the plate and a cliff for the surface
    beside it: the plate now turns eighty degrees with the arm while the sleeve
    it used to lie against stays on the clavicle, and the edge between them is
    drawn apart. Nothing measured it, so it shipped.

    Measured on this armour, the shipped .jms drew one edge x7.65 at the game's
    own eighty degree arm pose - a 2.5 unit gap at the shoulder, which is what
    the spikes in game are. So the same search that shaped the weights runs once
    more on the weights as they now stand, and blends the cliff into a gradient
    over the plates' own edges instead of leaving it at one edge.

    Weights only: no vertex moves, so the shape and the rig are untouched. This
    is the last thing done to the binding before the shape check.
    """
    segments = bone_segments(armature)
    names = list(segments)
    if not names:
        return 0
    family = bone_family(armature, names)
    mesh = object_data.data
    world = object_data.matrix_world
    group_names = {group.index: group.name for group in object_data.vertex_groups}
    weights = []
    for vertex in mesh.vertices:
        ride = {group_names[entry.group]: entry.weight for entry in vertex.groups
                if entry.group in group_names and entry.weight > 1e-4}
        weights.append(ride)
    if not any(weights):
        return 0
    weights, settled = settle_tears(weights, mesh, armature, world, names, family)
    weights, chosen = relax_tears(weights, mesh, armature, world, names)
    # The waist jumps from the pelvis to spine1 across three units of surface,
    # because no geometry there rides the spine in between. A blend of one joint
    # cannot close that - it may only lean on a directly jointed bone, and
    # spine1 is two joints from the pelvis - so the gap pass is allowed two.
    wide = {}
    parent, children = bone_tree(armature, names)
    for name in names:
        near = {name}
        for _step in range(2):
            near |= {parent.get(other) for other in near if parent.get(other)}
            near |= {kid for other in list(near) for kid in children.get(other, ())}
        wide[name] = near
    weights, gapped = settle_gaps(weights, mesh, armature, world, names, wide)
    groups = {}
    for name in names:
        groups[name] = (object_data.vertex_groups.get(name)
                        or object_data.vertex_groups.new(name=name))
    for vertex, ride in zip(mesh.vertices, weights):
        top = sorted(ride.items(), key=lambda pair: -pair[1])[:2]
        total = sum(value for _name, value in top) or 1.0
        keep = {name for name, _value in top}
        if not keep:
            continue
        for group in object_data.vertex_groups:
            if group.name not in keep:
                group.remove([vertex.index])
        for name, value in top:
            groups[name].add([vertex.index], value / total, "REPLACE")
    if gapped:
        log("%s: %d round(s) of the game's poses over the edges whose gap is "
            "over %.1f unit(s) - the waist seam was the last one"
            % (object_data.name, gapped, GAP_LIMIT))
    return settled + chosen


# A fragment is a plate of a single triangle. The item has dozens of them - a
# chipped edge, a rivet - and they are all of it that sits on the body. One that
# has been thrown clear is debris, and it is left out of the export.
FLOATER_GAP = 4.0


def name_materials_by_bitmap(object_data, stem):
    """Name every material after the bitmap it draws with.

    A .jms material name is not a label - it is the exact shader tag name
    tool.exe looks for, and a name no tag answers draws white in game. The item
    arrives with its own names (this one calls the armour "... colour"), and no
    texture or shader in the world is called that, so the model would be asking
    for a tag that cannot exist.

    So each material is named by the part of the body it covers, and the names
    are held in one place by `tag_name`: the suit takes `<item> base map`, the
    head `<item> face`, the neck `<item> body` - or `face`, `body` and the same
    two under `--plain-tags`. An item can bring more parts than those three, and
    two materials cannot share a name: Blender answers a taken name with `.001`,
    and that suffix would go into the .jms and become a tag nobody could make.
    The extras after the neck are therefore numbered - `body 2`, `body 3` - and
    each keeps a name only it holds.
    """
    mesh = object_data.data
    slots = object_data.material_slots
    counts = {}
    tall = {}
    for polygon in mesh.polygons:
        counts[polygon.material_index] = counts.get(polygon.material_index, 0) + 1
        for loop in polygon.loop_indices:
            point = mesh.vertices[mesh.loops[loop].vertex_index].co
            tall[polygon.material_index] = tall.get(polygon.material_index, 0.0) + point.z
    used = sorted(counts)
    if not used:
        return 0
    # Which material is which, from the mesh rather than from the names it
    # arrived with: the surface with the most faces is the suit, and of what is
    # left the one sitting highest is the head - the head is under the helmet and
    # the neck is below it. Reading this off the geometry matters because the
    # names are exactly what cannot be trusted here (an export calls the armour
    # "hair_6", and the ported head's own material is literally called "face").
    largest = max(used, key=lambda index: counts[index])
    rest = [index for index in used if index != largest]
    face_slot = None
    if rest:
        face_slot = max(rest, key=lambda index: tall[index] / counts[index])
    # Lower case: this name is the shader tag's name, and a tag path has none.
    wanted = {largest: ("%s base map" % stem).lower()}
    if face_slot is not None:
        wanted[face_slot] = tag_name(stem, "face")
    # Every other material is a part of the body the item also brought - a strap,
    # a second pair of gloves, a patch of cloth. They cannot all be the neck, and
    # a repeated name would come back as `.001`, so they are numbered in the
    # order they sit up the model: the neck first, then body 2, body 3.
    neck = tag_name(stem, "body")
    extra = 0
    others = [index for index in rest if index != face_slot]
    others.sort(key=lambda index: -(tall[index] / counts[index]))
    for index in others:
        extra += 1
        wanted[index] = neck if extra == 1 else "%s %d" % (neck, extra)
    # Blender's material names are one namespace for the whole file, and a name
    # already in use comes back with ".001" on it - which would become a shader
    # tag that does not exist, so the model would draw white. Anything that is
    # not one of ours is moved off the name first, and moved to a name that the
    # .jms never sees.
    mine = set()
    for index in used:
        material = slots[index].material if index < len(slots) else None
        if material is not None:
            mine.add(material.name)
    for want in set(wanted.values()):
        holder = bpy.data.materials.get(want)
        if holder is not None and holder.name not in mine:
            holder.name = "ported %s" % want
    changed = 0
    for index, want in wanted.items():
        material = slots[index].material if index < len(slots) else None
        if material is None or material.name == want:
            continue
        material.name = want
        changed += 1
    return changed


def merge_thin_materials(object_data, least=4):
    """Fold a material that carries almost no faces into the armour's own.

    Halo asks the game for one shader per material named in the model, and a
    shader that is missing is not an error - it draws white. The item comes with
    a second armour material on a couple of stray faces, which would mean a third
    shader tag to make by hand for no visible difference; those faces are given
    the armour material they belong on. The face keeps its own material.
    """
    mesh = object_data.data
    slots = [slot.material for slot in object_data.material_slots]
    if len(slots) < 3:
        return 0
    counts = [0] * len(slots)
    for polygon in mesh.polygons:
        counts[polygon.material_index] += 1
    face_slots = {index for index, material in enumerate(slots)
                  if material and "face" in material.name.lower()}
    keep = max((index for index in range(len(slots)) if index not in face_slots),
               key=lambda index: counts[index], default=None)
    if keep is None:
        return 0
    folded = 0
    for index in range(len(slots)):
        if index == keep or index in face_slots or counts[index] >= least:
            continue
        for polygon in mesh.polygons:
            if polygon.material_index == index:
                polygon.material_index = keep
        folded += 1
    return folded


def shape_audit(object_data, authored, scale=1.0):
    """How far the exported mesh's edges are from the ones it was imported with.

    The conversion is allowed to resize the item - one uniform factor - and it is
    not allowed to do anything else to it. This measures every edge of the file
    that ships against the same edge as it was imported, so "the model looks
    exactly like it did" is a number in the report and not a promise: after a
    uniform resize every edge is that one factor longer, and an edge that is not
    was stretched, turned by a pose, or squeezed by a fit.
    """
    mesh = object_data.data
    if not authored or len(authored) != len(mesh.vertices):
        return None
    ratios = []
    for edge in mesh.edges:
        first, second = edge.vertices
        was = fit_length(fit_between(authored[first], authored[second]))
        if was <= 1e-9:
            continue
        now = fit_length(fit_between(tuple(mesh.vertices[first].co),
                                     tuple(mesh.vertices[second].co)))
        if now <= 1e-9:
            continue
        ratios.append(now / was)
    if not ratios:
        return None
    # One uniform resize is the only change allowed, so the common factor is the
    # resize, and every edge has to share it exactly. The middle ratio is that
    # factor: a handful of stretched edges cannot move the middle of 11223.
    ordered = sorted(ratios)
    resize = ordered[len(ordered) // 2]
    moved, worst = 0, 1.0
    for ratio in ratios:
        off = max(ratio / resize, resize / ratio) if ratio > 0.0 else 1e9
        if off > 1.001:
            moved += 1
        worst = max(worst, off)
    line = ("shape check: %d edge(s), resize x%.4f, worst edge x%.5f of that, "
            "%d edge(s) stretched by more than 0.1%%"
            % (len(ratios), resize, worst, moved))
    return {"worst": worst, "moved": moved, "counted": len(ratios),
            "resize": resize, "line": line}


def face_the_world(object_data):
    """Turn any shell that shows the world its back out the right way round.

    Halo draws one side of a triangle. A face wound the wrong way is not dark
    and not clipped - it is simply not there, and the model reads as a hole
    exactly where the surface is complete. The item comes from a renderer that
    draws both sides, so a shell can arrive inside out and look right until it
    is in the game.

    Each shell is judged as a whole, from its own middle: a shell whose faces
    mostly point at that middle is inside out and is turned over. A flat plate
    has no middle worth speaking of - its faces sit square to it, neither in nor
    out - and is left exactly as the item wound it, so the side a person is
    meant to see is never hidden on a guess.
    """
    mesh = object_data.data
    if not mesh.polygons:
        return 0
    parent = list(range(len(mesh.vertices)))

    def find(index):
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    for polygon in mesh.polygons:
        corners = list(polygon.vertices)
        for other in corners[1:]:
            first, second = find(corners[0]), find(other)
            if first != second:
                parent[second] = first
    shells = {}
    for polygon in mesh.polygons:
        shells.setdefault(find(polygon.vertices[0]), []).append(polygon.index)
    turn_over = []
    for indices in shells.values():
        if len(indices) < 6:
            continue
        middle = [0.0, 0.0, 0.0]
        seen = 0
        for index in indices:
            for corner in mesh.polygons[index].vertices:
                point = mesh.vertices[corner].co
                for axis in range(3):
                    middle[axis] += point[axis]
                seen += 1
        if not seen:
            continue
        middle = [value / seen for value in middle]
        inward = counted = 0
        for index in indices:
            polygon = mesh.polygons[index]
            normal, centre = polygon.normal, polygon.center
            out = [centre[axis] - middle[axis] for axis in range(3)]
            reach = math.sqrt(sum(value * value for value in out))
            if reach < 1e-6:
                continue
            counted += 1
            if sum(normal[axis] * out[axis] for axis in range(3)) < -0.3 * reach:
                inward += 1
        if counted >= 6 and inward >= 0.8 * counted:
            turn_over.extend(indices)
    if not turn_over:
        return 0
    room = bmesh.new()
    room.from_mesh(mesh)
    room.faces.ensure_lookup_table()
    room.faces.index_update()
    bmesh.ops.reverse_faces(room, faces=[room.faces[index] for index in turn_over
                                        if index < len(room.faces)])
    room.to_mesh(mesh)
    room.free()
    mesh.update()
    return len(turn_over)


def drop_floaters(object_data):
    """Leave out a one-triangle fragment that ended up floating off the body.

    A swing is measured for a whole shell, and a shell that is one triangle has
    no shape for that measurement to read: on this armour one of them was
    carried 0.63 m out from the shoulder and hung in the air beside the chest.
    Measured against the rest of the mesh, the stray is the only fragment more
    than FLOATER_GAP from everything else, so that is the test - a fragment
    near the surface is a rivet and stays exactly where the item put it.
    """
    mesh = object_data.data
    world = object_data.matrix_world
    parent = list(range(len(mesh.vertices)))

    def find(index):
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    for polygon in mesh.polygons:
        corners = list(polygon.vertices)
        for other in corners[1:]:
            first, second = find(corners[0]), find(other)
            if first != second:
                parent[second] = first
    shells = {}
    for polygon in mesh.polygons:
        shells.setdefault(find(polygon.vertices[0]), []).append(polygon.index)
    points = [world @ vertex.co for vertex in mesh.vertices]
    drop = set()
    for root, faces in shells.items():
        if len(faces) > 1:
            continue
        corners = set(mesh.polygons[faces[0]].vertices)
        if len(corners) > 3:
            continue
        centre = sum((points[index] for index in corners), Vector()) / len(corners)
        near = min((points[index] - centre).length
                   for index in range(len(points)) if index not in corners)
        if near > FLOATER_GAP:
            drop.add(faces[0])
    if not drop:
        return 0
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[index] for index in sorted(drop)],
                     context="FACES")
    bm.to_mesh(mesh)
    bm.free()
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    mesh.update()
    log("%s: left out %d one-triangle fragment(s) that a swing had thrown clear "
        "of the body - a plate that small has no shape of its own, so it is "
        "bound like its neighbours but not carried by a swing"
        % (object_data.name, len(drop)))
    return len(drop)


def skin(object_data, armature, influences=2, rigid=False, given=None):
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
        # Inverse-square falloff first: nearest bone dominant, weights summing
        # to 1. Then the smoothing pass, which is what keeps a sleeve whole
        # when the joint under it turns.
        #
        # Only the nearest bone and the bones it is jointed to are candidates.
        # Taking the two nearest segments outright looked reasonable and was
        # not: the upperarm's segment passes within millimetres of the neck's
        # and the clavicle's at a shoulder, so a point there could be handed
        # 'neck and upperarm', which is a pair no joint connects and which tears
        # itself in half at eighty degrees. A vertex may blend with the bone it
        # rides and the ones that bone hangs from or carries - nothing else.
        family = bone_family(armature, names)
        parent, children = bone_tree(armature, names)
        nearest = []
        if given is not None:
            # Measured on the avatar's own skeleton before the mesh was posed
            # into Halo's rest pose (see stand_in_halo_pose). Which part a point
            # belongs to is its own joint's answer, not the nearest Halo bone's:
            # Halo's hand hangs beside this body's hip, so a hip point is nearer
            # a finger bone than its own thigh, and binding it there tore the
            # hip x17 apart the moment the game bent an elbow.
            nearest = [dict(ride) for ride in given]
        for vertex in (mesh.vertices if given is None else ()):
            point = world @ vertex.co
            ridden = min(names, key=lambda name: point_segment_distance(
                point, *segments[name]))
            # A point past the far end of a bone is not on that bone any more:
            # it is past the joint the bone ends in, which is where the next
            # bone takes over. Shaped armour makes this visible - a pauldron
            # sits outside the shoulder, so the clavicle's segment is the
            # nearest thing to it while the plate actually hangs off the arm -
            # and weighting it to the clavicle leaves the pad on the chest
            # while the arm swings out from under it. Same at the near end.
            for _step in range(2):
                head, tail = segments[ridden]
                axis = tail - head
                long_enough = axis.length_squared
                if long_enough < 1e-12:
                    break
                how_far = (point - head).dot(axis) / long_enough
                if how_far > 1.0 and children.get(ridden):
                    ridden = min(children[ridden],
                                 key=lambda name: (segments[name][0] - tail).length)
                elif how_far < 0.0 and parent.get(ridden):
                    ridden = parent[ridden]
                else:
                    break
            allowed = family[ridden]
            scored = sorted(
                ((point_segment_distance(point, head, tail), name)
                 for name, (head, tail) in segments.items()
                 if name in allowed),
                key=lambda pair: pair[0])[:influences]
            nearest.append({name: 1.0 / max(distance, 1e-4) ** 2
                            for distance, name in scored})
        weights = smooth_by_position(nearest, mesh, kin=family)
        ported = take_port_tag(object_data, mesh)
        if len(ported) >= BODY_TRANSFER_MIN:
            weights, copied = transfer_from_body(weights, mesh, ported, world)
        else:
            copied = 0
            if ported:
                log("%s: the avatar under this item is %d point(s) - the rest of "
                    "its body was cut away for the costume - so there is no body "
                    "to copy weights from and the item keeps the bones its own "
                    "distance to the skeleton gave it"
                    % (object_data.name, len(ported)))
        if copied:
            # A plate is one solid piece, so every vertex of it has to ride the
            # same blend: the average of what the body under the whole plate
            # rides. Smoothing along the shell's own edges is what makes that
            # happen - a pauldron reaches its own average in a few passes, while
            # the suit, spanning the waist and both hips, keeps its gradient.
            # Nothing is thresholded: the shell's size decides by itself.
            weights = smooth_by_position(weights, mesh,
                                         passes=PLATE_SMOOTH_PASSES, kin=family)
            log("%s: bound %d vertex/vertices to the weights of the avatar body "
                "under them, then smoothed each shell along its own edges (%d passes)"
                % (object_data.name, copied, PLATE_SMOOTH_PASSES))
        # The tear search exists to repair what distance weighting does to a
        # surface it has no part map for. A body that came with its own joints
        # does have one, and the search was then free to walk a chest point at
        # the centre line - two units from Halo's spine1 - on to an upper arm
        # because the arms had to swing past it. The weights are not torn up,
        # so nothing is asked to repair them.
        weights, settled = settle_tears(weights, mesh, armature, world, names,
                                        family)
        if settled:
            log("%s: settled the torn strip against the game's own deformation "
                "- %d round(s) at %s"
                % (object_data.name, settled,
                   "%d poses over the whole body" % len(halo_pose.BODY_POSES)))
        weights, chosen = relax_tears(weights, mesh, armature, world, names)
        if chosen:
            log("%s: chose each torn point's bones against the game's own "
                "deformation - %d round(s) over %d body poses, until no edge "
                "stretched past x%.1f"
                % (object_data.name, chosen, len(halo_pose.BODY_POSES), TEAR_LIMIT))
        groups = {name: object_data.vertex_groups.new(name=name) for name in names}
        tally = {}
        for index, own in enumerate(weights):
            total = sum(own.values()) or 1.0
            for name, weight in own.items():
                groups[name].add([index], weight / total, "REPLACE")
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

def jms_name(stem, suffix=""):
    """The .jms name tool.exe reads: <permutation> <lod>.JMS.

    The LOD word is not decoration: Tool builds a model's markers from the
    superhigh LOD only, so a model whose file name omits the word depends on
    Tool's default for it - and the docs promise nothing there. Writing it makes
    the marker import unconditional; Tool strips it off the permutation name.
    """
    return "%s%s %s.jms" % (stem, suffix, MODEL_LOD)


# Halo's node frames against Blender's bone frames.
#
# A node's turn is not free-form. Halo's animation graph writes each node's
# rotation into that node's own frame, so a block whose frames carry a fixed
# roll still composes to the right bone POSITIONS - the bind looks perfect in
# Blender, which deforms through the armature and never reads the block - while
# every animated joint turns about a wrongly rolled axis. Arms swing furthest
# from their bind, so they are where it shows first and worst: they fly out and
# the sleeve is drawn as stretched bands.
#
# Measured against Halo, not guessed. Exporting this rig and composing each
# node's frame the way ``jms_check`` composes them gives a frame that differs
# from Halo's own ``spartan.jms`` by the SAME 90 degree roll on all 19 nodes
# (worst deviation 0.000005 across the block), and stored translations that are
# that same roll of Halo's. The pelvis is the node whose frame is the model's,
# and Halo stores it as (0.5, 0.5, 0.5, 0.5); this rig gave (0, 0.7071, 0.7071,
# 0), the same rotation rolled 90 degrees about -z. Rolling here reproduces
# Halo's stored turn for every one of the 19 nodes, so what the engine reads is
# the cyborg's own skeleton rather than one that merely lands on its joints.
#
# The cause is Blender's bone space (a bone's length runs along its local Y)
# against the axes Halo's .jms files use, which is the same for every Blender
# rig, so this applies to the first-person arms model too.
NODE_FRAME_ROLL = (0.0, 0.0, -0.7071067811865476, 0.7071067811865476)


def _quaternion_product(first, second):
    ax, ay, az, aw = first
    bx, by, bz, bw = second
    return (aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)


def jms_node_rows(armature):
    """The node block a .jms writes, as numbers, for the exporter and the skin.

    One place decides a node's turn, its spot and its links, so the weights are
    shaped against the same frames tool.exe will bake.

    Halo's own biped is written in the one order its animation graph stores. The
    order here is the node index Tool bakes into the gbxmodel, and an animation
    addresses a bone by that index: the same 19 names in Blender's order make a
    different node list, which the engine answers with "the model '...' and the
    animation graph '...' don't match" - and, were the checksum forced to agree,
    would animate the wrong bones. The table's own child and sibling links go in
    with it, so the node block is exactly the retail cyborg's.

    A node is written in its PARENT's space, not the model's. Halo's own biped
    says so: the marine's calf sits 15.87 along its thigh's X axis, not at its
    model-space position, and tool builds every bone from its parent's frame plus
    this line. Written in model space instead, the skeleton piles up - every bone
    placed as if it hung off the origin.

    A .jms stores each node's turn INVERTED - the inverse of the node's rotation
    against its parent. Written the natural way round, every bind frame tool.exe
    bakes comes out inverted and the engine draws the mesh as a heap of stretched
    triangles, while the .blend, which deforms through the armature and never
    reads this block, still looks perfect. Halo's own spartan.jms is the proof:
    its node block only rebuilds the cyborg's bone positions (-0.82/0/39.44, head
    60.91, hands 35.23) when each stored turn is applied transposed, i.e.
    stored = the inverse of the node's own turn - the same inversion BlueStreak
    writes as "quat -rot.x -rot.y -rot.z rot.w".

    The header's second field is not a version or a constant: it is the model's
    node list checksum, and tool.exe copies it into the gbxmodel. The engine
    refuses a biped whose model and animation graph carry different nonzero
    values with "the model '...' and the animation graph '...' don't match" and
    then will not animate it - which is why BlueStreak's constant 3251 fails even
    with a correct skeleton. Halo's own cyborg .jms and graph both carry
    1828349080, and the biped's block is that same list in that same order. A
    model no graph drives (the arms) carries 0, which the engine reads as "do
    not compare checksums"; the arms must stay a globals model.

    Returns (order, index_of, rows, checksum), each row being
    (name, first_child, next_sibling, turn, spot).
    """
    bones = list(armature.data.bones)
    by_name = {bone.name: bone for bone in bones}
    names = [bone.name for bone in bones]
    biped = len(names) == len(BIPED_NODES) and set(names) == set(BIPED_NODE_ORDER)
    order = list(BIPED_NODE_ORDER) if biped else names
    index_of = {name: index for index, name in enumerate(order)}
    if biped:
        parent_of = {row[0]: (order[row[3]] if row[3] >= 0 else None)
                     for row in BIPED_NODES}
        first_child = {row[0]: row[1] for row in BIPED_NODES}
        next_sibling = {row[0]: row[2] for row in BIPED_NODES}
    else:
        parent_of = {bone.name: (bone.parent.name if bone.parent else None)
                     for bone in bones}
        children = {name: [] for name in order}
        for bone in bones:
            if bone.parent:
                children[bone.parent.name].append(bone.name)
        first_child = {name: -1 for name in order}
        next_sibling = {name: -1 for name in order}
        for bone in bones:
            own = bone.name
            kids = list(children[own])
            if kids:
                first_child[own] = index_of[kids[0]]
            for left, right in zip(kids, kids[1:]):
                next_sibling[left] = index_of[right]
    checksum = BIPED_NODE_CHECKSUM if biped else 0
    rows = []
    for own in order:
        bone = by_name[own]
        if parent_of[own]:
            frame = (by_name[parent_of[own]].matrix_local.inverted()
                     @ bone.matrix_local)
        else:
            frame = bone.matrix_local
        turn = frame.to_quaternion()
        # Conjugate it: negating the vector part of a unit quaternion is its
        # inverse, and mathutils exposes the components writable.
        turn.x, turn.y, turn.z = -turn.x, -turn.y, -turn.z
        spot = frame.translation
        head = [spot.x, spot.y, spot.z]
        if parent_of[own]:
            # Blender's axes into Halo's: a 90 degree roll about -z carries
            # (x, y, z) to (y, -x, z), and a node's turn is that axis change, so
            # the quaternion's vector part rolls with it while w stays put. The
            # translation is in the same parent frame, so it rolls too.
            turn.x, turn.y, turn.z, turn.w = (turn.y, -turn.x, turn.z, turn.w)
            head = [head[1], -head[0], head[2]]
        else:
            # A root has no parent frame to be relative to, so the roll is the
            # frame itself: q * roll rather than q rolled by it.
            turn.x, turn.y, turn.z, turn.w = _quaternion_product(
                NODE_FRAME_ROLL, (turn.x, turn.y, turn.z, turn.w))
        rows.append((own, first_child[own], next_sibling[own],
                     (turn.x, turn.y, turn.z, turn.w),
                     (head[0], head[1], head[2])))
    return order, index_of, rows, checksum


def export_jms(object_data, armature, path, arms=False, two_weights=True):
    """Halo CE's text model format, laid out the way tool.exe reads it.

    Positional, with no section markers, matching HaloCE's own exporter
    (BlueStreak 1.0.4, "Adapted for HaloCE"):

        8200 <node_list_checksum> <node_count>
        <name> <first_child> <next_sibling> <rx> <ry> <rz> <rw> <tx> <ty> <tz>
        <material_count>  then  <name> <none>  per material
        <marker_count>   then  <name> -1 <node> <rx> <ry> <rz> <rw>
                               <tx> <ty> <tz> <radius>  per marker
        <region_count>   then  <name>  per region
        <vertex_count>
        <node0> <x> <y> <z> <nx> <ny> <nz> <node1> <weight> <u> <v> <w>
        <face_count>
        <region> <shader> <v0> <v1> <v2>

    Vertices are per triangle corner - three per face - because JMS does not
    share them: each corner carries its own normal and its own texture
    coordinate. That is also why the UV has a slot at all: it is the u, v pair
    plus a w of zero, which is everything a Halo CE gbxmodel vertex stores.

    Node names keep their spaces (``bip01 pelvis``): Halo's own biped names its
    bones that way, and an animation graph binds by name, so an underscored
    ``bip01_pelvis`` is a skeleton Halo's animations cannot drive. The marker
    line is BlueStreak's too: a constant -1, the node the marker rides, its
    rotation, its translation in that node's space, and a radius a gbxmodel
    marker does not store.

    ``arms=True`` exports the first-person hands model, whose node block is
    not free-form: H1 matches its node names against every weapon's
    first-person graph, so a renamed or extra bone makes that match fail and
    the weapon stops drawing. The export raises instead of writing such a
    file.
    """
    mesh_data = object_data.data
    bones = list(armature.data.bones)
    by_name = {bone.name: bone for bone in bones}
    names = [bone.name for bone in bones]
    if arms:
        # Before anything is written: a bad rig must not leave behind a .jms
        # that looks fine in the folder and fails silently in Sapien.
        problem = fp_arm_node_problem(names)
        if problem:
            raise ValueError("%s: %s" % (os.path.basename(path), problem))
    # The node block, in the order Halo's animation graph stores it.
    # jms_node_rows() holds the why - the inverted turn, the roll from Blender's
    # axes into Halo's, the parent-space spot, the checksum the engine compares -
    # and the skinning reads the same rows, so what is written here is exactly
    # the block the weights were shaped against.
    biped = len(names) == len(BIPED_NODES) and set(names) == set(BIPED_NODE_ORDER)
    order, index_of, rows, checksum = jms_node_rows(armature)
    out = ["8200\t%d\t%d" % (checksum, len(order))]
    for own, first, sibling, turn, head in rows:
        out.append("%s\t%d\t%d\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f"
                   % (own, first, sibling, turn[0], turn[1], turn[2], turn[3],
                      head[0], head[1], head[2]))

    # Only a material that carries faces is named: Halo makes one shader per name
    # here, and a name with nothing on it is a shader tag to create by hand for a
    # surface that is not in the model. The face keeps its own name, because it
    # is a different picture.
    used = {polygon.material_index for polygon in object_data.data.polygons}
    order = [index for index in range(len(object_data.material_slots))
             if index in used]
    if not order:
        order = [0]
    renumber = {was: now for now, was in enumerate(order)}
    materials = [object_data.material_slots[index].material.name
                 if object_data.material_slots[index].material
                 else "material%d" % index for index in order]
    out.append("%d" % len(materials))
    for name in materials:
        # Spaces stay: the material name is how tool.exe finds the shader, and
        # the name it looks for is the name of the bitmap (`<item> base map`).
        # A tab would end the field early, so that is the one thing collapsed.
        clean = " ".join(str(name).split())
        stem_part, _, tail = clean.rpartition(".")
        if tail.isdigit() and len(tail) == 3 and stem_part:
            clean = stem_part
        out.append("%s\t<none>" % clean)

    # Halo's biped markers, on the bones the engine looks for them on. A model
    # without them is refused outright. Any skeleton that has those bones gets
    # them; the first-person arms ride the 37-bone frame, have neither, and get
    # none.
    markers = [(name, index_of[bone]) for name, bone in BIPED_MARKERS
               if bone in index_of]
    out.append("%d" % len(markers))
    for name, node in markers:
        # The marker takes its bone's own orientation, so the rotation is
        # identity and the translation (in that node's space) is zero. The
        # radius only matters to a collision model, and a gbxmodel drops it.
        out.append("%s\t-1\t%d\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f"
                   % (name, node, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0))
    out.append("1")          # one region
    out.append("unnamed")

    world = object_data.matrix_world
    inverse = armature.matrix_world.inverted()
    rotate = inverse.to_3x3()
    # No face re-projection here either: the .jms carries the item's own face
    # coordinates, the ones the avatar's face sheet was painted for. They were
    # already correct when the mesh came in, and the join with the ported head
    # keeps them - every layer merged by name carries the same numbers.
    uv_layer = mesh_data.uv_layers.active
    group_names = {group.index: group.name for group in object_data.vertex_groups}

    corners = []
    for polygon in mesh_data.polygons:
        loops = list(polygon.loop_indices)
        for corner in range(1, len(loops) - 1):
            corner_one, corner_two, corner_three = (loops[0], loops[corner],
                                                    loops[corner + 1])
            corners.append((corner_one, corner_two, corner_three,
                            renumber.get(polygon.material_index, 0)))
            # Every plate twice, wound the other way - a plate with two sides.
            # Halo culls a back face, and this armour is 2,165 separate plates
            # over nothing: at a plate's silhouette edge, and in every seam
            # between two plates, the game has nothing to draw and the
            # background comes through, which is what "I can see through the
            # edges of his armour" is. The reversed copy is the same triangle
            # in the same place with the opposite winding, so the plate reads
            # as solid from behind instead of vanishing. Halo has no
            # double-sided shader in CE; two windings is how a model gets one.
            corners.append((corner_one, corner_three, corner_two,
                            renumber.get(polygon.material_index, 0)))

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
            # A body rides one node per vertex (see single_bone_weights), so it
            # is written that way: a second weight here would hand the engine
            # two nodes to blend and the crush would come back.
            weighted = sorted(((group.weight, group_names[group.group])
                               for group in vertex.groups
                               if group.group in group_names),
                              reverse=True)[:2 if two_weights else 1]
            if not weighted:
                weighted = [(1.0, names[0])]
            node0 = index_of.get(weighted[0][1], 0)
            node1 = -1
            weight1 = 0.0
            if len(weighted) > 1:
                node1 = index_of.get(weighted[1][1], -1)
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
    if biped:
        log("node list : Halo's biped order, and its node list checksum %d in "
            "the .jms header - tool.exe copies that field into the gbxmodel, so "
            "it matches characters\\cyborg\\cyborg.model_animations"
            % BIPED_NODE_CHECKSUM)
    log("wrote %s (%d verts, %d tris, %d markers)"
        % (os.path.basename(path), len(corners) * 3, len(faces), len(markers)))
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


def _jms_header(armature):
    """The node block and index, written the way tool.exe reads a .jms.

    Shared by the collision and physics exports so both carry the session's own
    node list - the same order, the same header checksum - and a biped whose
    gbxmodel, collision model and physics all agree is one tool.exe will not
    refuse with "node list checksum ... don't match".
    """
    order, index_of, rows, checksum = jms_node_rows(armature)
    out = ["8200\t%d\t%d" % (checksum, len(order))]
    for own, first, sibling, turn, head in rows:
        out.append("%s\t%d\t%d\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f"
                   % (own, first, sibling, turn[0], turn[1], turn[2], turn[3],
                      head[0], head[1], head[2]))
    return out, index_of, rows


def _jms_write(path, lines):
    with open(path, "w", encoding="ascii", errors="replace", newline="") as handle:
        handle.write("\n".join(lines) + "\n")


# A plate is not a collision shape. A biped's collision model is a handful of
# closed convex pieces, one per body part, and the rules tool.exe enforces are
# strict: every face needs a material, every piece must be closed, and no two
# pieces may overlap or even touch. So the boxes below are built from the
# vertices that mostly ride each bone, then pulled apart until none of them
# intersects anything - which is why the split is done here and not hoped for.
COLLISION_SKIN = 0.05          # a hand's width of clearance, in Halo units
COLLISION_MIN_SIDE = 0.5       # a piece thinner than this is not worth a box


def collision_boxes(object_data, armature, index_of):
    """One closed box per bone, in Halo's space, none of them touching.

    Returns ``[(node, low, high), ...]``. The box a bone gets is the extent of
    the vertices that ride it at weight 0.5 or more, so an arm box is the arm
    and not part of the chest, and a joint's box stops where the plates it does
    not own begin.
    """
    inverse = armature.matrix_world.inverted()
    world = object_data.matrix_world
    names = {group.index: group.name for group in object_data.vertex_groups}
    spans = {}
    for vertex in object_data.data.vertices:
        riding = sorted(((group.weight, names.get(group.group))
                         for group in vertex.groups if group.group in names),
                        reverse=True)
        if not riding or riding[0][1] not in index_of:
            continue
        if riding[0][0] < 0.5:
            continue
        point = inverse @ (world @ vertex.co)
        node = index_of[riding[0][1]]
        low, high = spans.setdefault(
            node, ([point[axis] for axis in range(3)],
                   [point[axis] for axis in range(3)]))
        for axis in range(3):
            low[axis] = min(low[axis], point[axis])
            high[axis] = max(high[axis], point[axis])
    boxes = []
    for node in sorted(spans):
        low, high = spans[node]
        if min(high[axis] - low[axis] for axis in range(3)) < COLLISION_MIN_SIDE:
            continue
        boxes.append([node,
                      [low[axis] - COLLISION_SKIN for axis in range(3)],
                      [high[axis] + COLLISION_SKIN for axis in range(3)]])
    # Two parts of a body share space at every joint - the chest box and the
    # upper-arm box overlap at the shoulder - and overlapping collision pieces
    # are the thing tool.exe warns produces "weird errors in game". Split each
    # overlapping pair along the axis they overlap least, moving one face of
    # each to either side of the middle: a gap, never a touch.
    for _ in range(6):
        apart = True
        for first in range(len(boxes)):
            for second in range(first + 1, len(boxes)):
                one, two = boxes[first], boxes[second]
                overlap = [min(one[2][axis], two[2][axis])
                           - max(one[1][axis], two[1][axis])
                           for axis in range(3)]
                if min(overlap) <= 0.0:
                    continue
                apart = False
                axis = overlap.index(min(overlap))
                middle = (max(one[1][axis], two[1][axis])
                          + min(one[2][axis], two[2][axis])) / 2.0
                if (one[1][axis] + one[2][axis]) <= (two[1][axis] + two[2][axis]):
                    one[2][axis] = middle - COLLISION_SKIN / 2.0
                    two[1][axis] = middle + COLLISION_SKIN / 2.0
                else:
                    two[2][axis] = middle - COLLISION_SKIN / 2.0
                    one[1][axis] = middle + COLLISION_SKIN / 2.0
        if apart:
            break
    # A box that a split squeezed into nothing cannot be collision.
    return [(node, low, high) for node, low, high in boxes
            if min(high[axis] - low[axis] for axis in range(3)) >= COLLISION_MIN_SIDE]


def _box_triangles(low, high):
    """The twelve triangles of a closed box, wound outward."""
    corners = [(x, y, z) for x in (low[0], high[0])
               for y in (low[1], high[1]) for z in (low[2], high[2])]
    index = {corner: number for number, corner in enumerate(corners)}
    faces = []
    for axis in range(3):
        for side in (0, 1):
            plane = high[axis] if side else low[axis]
            ring = [corner for corner in corners if corner[axis] == plane]
            ring.sort(key=lambda corner: (corner[(axis + 1) % 3],
                                          corner[(axis + 2) % 3]))
            quad = [ring[0], ring[1], ring[3], ring[2]]
            if side:
                quad.reverse()
            faces.append((index[quad[0]], index[quad[1]], index[quad[2]]))
            faces.append((index[quad[0]], index[quad[2]], index[quad[3]]))
    # Wound outward, checked by arithmetic rather than by a convention this
    # build would have to be right about: a triangle whose normal points back
    # at the box's middle is inside out, so it is reversed. tool.exe reads a
    # collision piece as closed only when every face agrees which way is out.
    middle = [(low[axis] + high[axis]) / 2.0 for axis in range(3)]
    fixed = []
    for triangle in faces:
        one, two, three = (corners[number] for number in triangle)
        normal = ((two[1] - one[1]) * (three[2] - one[2])
                  - (two[2] - one[2]) * (three[1] - one[1]),
                  (two[2] - one[2]) * (three[0] - one[0])
                  - (two[0] - one[0]) * (three[2] - one[2]),
                  (two[0] - one[0]) * (three[1] - one[1])
                  - (two[1] - one[1]) * (three[0] - one[0]))
        outward = sum(normal[axis] * ((one[axis] + two[axis] + three[axis]) / 3.0
                                      - middle[axis]) for axis in range(3))
        fixed.append(triangle if outward >= 0.0 else (triangle[0], triangle[2], triangle[1]))
    return corners, fixed


def export_collision_jms(object_data, armature, path, material_name):
    """A collision model as tool.exe reads one: closed boxes, no overlap.

    ``tool collision-geometry <dir>`` looks for ``data\\<dir>\\physics\\<dir>.JMS``
    and writes a model_collision_geometry tag, and it refuses a model whose
    regions differ from the gbxmodel's - so this writes one region, named the
    same as the render model writes it, with the same node block and checksum.
    """
    out, index_of, _rows = _jms_header(armature)
    out.append("1")
    out.append("%s\t<none>" % " ".join(str(material_name).split()))
    out.append("0")                    # no markers: the engine's own is fine
    out.append("1")
    out.append("unnamed")              # the render model's own region
    boxes = collision_boxes(object_data, armature, index_of)
    corners = []
    faces = []
    for node, low, high in boxes:
        piece, triangles = _box_triangles(low, high)
        base = len(corners)
        corners.extend((node, point) for point in piece)
        faces.extend((node, tuple(vertex + base for vertex in triangle))
                     for triangle in triangles)
    out.append("%d" % (len(faces) * 3))
    for _, triangle in faces:
        for vertex in triangle:
            node, point = corners[vertex]
            out.append("%d\t%.6f\t%.6f\t%.6f\t0.000000\t1.000000\t0.000000"
                       "\t-1\t0.000000\t0.000000\t0.000000\t0.000000"
                       % (node, point[0], point[1], point[2]))
    out.append("%d" % len(faces))
    # Faces index the vertex block from its first entry, not from the line they
    # sit on: tool.exe reads these as indices, and a line number walks past the
    # end of the block. Every corner is its own vertex here, so the third face
    # starts at 9.
    for number in range(len(faces)):
        out.append("0\t0\t%d\t%d\t%d"
                   % (number * 3, number * 3 + 1, number * 3 + 2))
    _jms_write(path, out)
    log("collision: %d closed box(es), no two touching, one region named the "
        "same as the model's - tool.exe's region check is why"
        % len(boxes))
    log("wrote %s (%d tris)" % (os.path.basename(path), len(faces) * 2))
    return boxes


def export_physics_jms(object_data, armature, path, material_name, boxes):
    """A physics model as tool.exe reads one: spheres, linked to the pelvis.

    ``tool physics <dir>`` reads the same ``physics\\<dir>.JMS`` and imports the
    markers as collision spheres - a marker is a sphere to it and its radius is
    the radius the sphere gets. Physics does not animate, so every sphere rides
    the pelvis, and the pelvis sphere is the pill a biped stands on.
    """
    out, index_of, rows = _jms_header(armature)
    out.append("1")
    out.append("%s\t<none>" % " ".join(str(material_name).split()))
    # Spheres at each part's own node origin, with no offset: a marker's
    # translation is read in its node's frame, and those frames are turned -
    # the pelvis 120 degrees - so the one translation that cannot be misplaced
    # is zero. A biped needs them under the feet as well as at the hips: the
    # feet spheres are what it stands on, and without them the origin is the
    # only thing touching the floor and the character sinks into it.
    # A sphere's bottom is what the biped stands on, so its radius is measured
    # from the ankle down to the sole, not across the foot and not from the
    # boot's height. Half the foot's width made a sphere wider than the ankle is
    # high, its bottom sank below the ground and the engine lifted the whole
    # character to clear it - the floating feet. Half the boot's height is the
    # opposite mistake: the sphere then ends midway up the boot, so the engine
    # drops the biped until that midpoint is on the floor and the feet stand in
    # it. The sole is the lowest vertex of the body, and the ankle is the foot
    # node's own origin, so the radius is the distance between the two.
    inverse = armature.matrix_world.inverted()
    world = object_data.matrix_world
    soles = [inverse @ (world @ vertex.co)
             for vertex in object_data.data.vertices]
    ground = min(point[2] for point in soles) if soles else 0.0
    # The ankle is the foot bone's own head, in the same armature space the
    # sole was measured in. The node block's translation is parent-space, so it
    # is not the height wanted here.
    ankle = {bone.name: bone.head_local[2] for bone in armature.data.bones}
    wanted = [("bip01 pelvis", 0.5), ("bip01 l foot", 0.0), ("bip01 r foot", 0.0)]
    spheres = []
    for bone, share in wanted:
        node = index_of.get(bone)
        if node is None:
            continue
        for piece, low, high in boxes:
            if piece != node:
                continue
            if share:
                widest = max(high[0] - low[0], high[2] - low[2])
                spheres.append((node, max(widest * share, 1.0)))
            else:
                # The sphere is centred on the foot node (its marker offset is
                # zero), so a radius of ankle-minus-sole ends exactly on the
                # floor and the soles rest there.
                her = ankle.get(bone)
                if her is None:
                    her = high[2]
                spheres.append((node, max(her - ground, 1.0)))
    if not spheres:
        return []
    out.append("%d" % len(spheres))
    for number, (node, radius) in enumerate(spheres):
        out.append("physics%d\t-1\t%d\t0.000000\t0.000000\t0.000000"
                   "\t1.000000\t0.000000\t0.000000\t0.000000\t%.6f"
                   % (number, node, radius))
    out.append("1")
    out.append("unnamed")
    out.append("0")                    # no vertices
    out.append("0")                    # no faces
    _jms_write(path, out)
    log("physics: %d sphere(s) - pelvis %.2f units, each foot %.2f"
        % (len(spheres), spheres[0][1], spheres[-1][1]))
    log("wrote %s" % os.path.basename(path))
    return spheres


def face_camera(centre, tall):
    """A camera on the same front view, as scene data rather than workspace data.

    The saved viewport only survives if Blender loads the workspace saved with
    the file. A Blender set not to load one - or one a little older than the
    Blender that wrote the file - keeps its own default angle instead, and from
    there a standing biped looks tilted, seen from above, with one arm long and
    one short. Nothing on screen then says the model is straight, so the model
    gets blamed for the view. A camera is part of the scene: it cannot be left
    behind, and numpad 0 or F12 puts the model on its feet, upright and facing
    you, in any Blender.
    """
    from mathutils import Euler
    item = bpy.data.objects.get("front view")
    if item is None or item.type != "CAMERA":
        item = bpy.data.objects.new("front view", bpy.data.cameras.new("front view"))
        bpy.context.scene.collection.objects.link(item)
    data = item.data
    data.type = "ORTHO"
    # Portrait, so a standing character fills the frame without its arms being
    # cut off at the sides: ortho_scale is the frame's longer side.
    data.ortho_scale = tall * 1.35
    data.clip_start = max(tall * 0.01, 0.001)
    data.clip_end = tall * 10.0
    item.location = (centre[0] + tall * 2.5, centre[1], centre[2])
    item.rotation_mode = "QUATERNION"
    item.rotation_quaternion = Euler(
        (math.radians(90.0), 0.0, math.radians(90.0)), "XYZ").to_quaternion()
    scene = bpy.context.scene
    scene.camera = item
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 1250
    scene.render.resolution_percentage = 100
    return item


def open_ready(objects):
    """Save the scene the way it should be seen: shaded, and facing you.

    A .blend opens in whatever the viewport was left in, and a fresh viewport is
    Solid - one grey material, no maps at all. The point of this file is to look
    at the model, so every 3D view is put in Material Preview and turned to the
    side the character faces, which is +x in Halo's space. That is a view of the
    model, not a change to it: no coordinate and no object transform moves, so
    the file still holds the game's own axes.

    A viewport is also only half the job, because it is workspace and not every
    Blender loads the workspace in the file, so the same front view is left in
    the scene as a camera too - see face_camera. Returns that camera, so the
    caller can keep it in the file.
    """
    from mathutils import Euler
    meshes = [item for item in objects if item.type == "MESH"]
    if not meshes:
        return None
    low = [1e9] * 3
    high = [-1e9] * 3
    for item in meshes:
        for vertex in item.data.vertices:
            point = item.matrix_world @ vertex.co
            for axis in range(3):
                low[axis] = min(low[axis], point[axis])
                high[axis] = max(high[axis], point[axis])
    centre = [(low[axis] + high[axis]) / 2.0 for axis in range(3)]
    tall = max(high[2] - low[2], high[0] - low[0], high[1] - low[1], 1.0)
    empty = low[0] > 1e8
    # Looking from +x towards the model, level with its middle: the character
    # faces +x, so this is his face, upright and framed.
    look = Euler((math.radians(90.0), 0.0, math.radians(90.0)), "XYZ").to_quaternion()
    for screen in bpy.data.screens:
        for area in screen.areas:
            for space in area.spaces:
                if space.type != "VIEW_3D":
                    continue
                try:
                    space.shading.type = "MATERIAL"
                except TypeError:
                    pass
                view = space.region_3d
                view.view_location = centre
                view.view_rotation = look
                view.view_distance = tall * 1.45
                view.view_perspective = "ORTHO"
    if empty:
        return None
    return face_camera(centre, tall)


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
    camera = open_ready(objects)
    keep = set(objects)
    if camera is not None:
        keep.add(camera)
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


def halo_arms(armature_fp):
    """The arm mesh the rig file ships, which is Halo's own.

    One pass rigs several items and every one of their first-person sets stays
    parented to the same rig, so by the second item anything merely standing on
    that rig includes the first item's arms. Those are not the model to aim a
    glove at, nor to measure a fit against, so the file's own cyborg body is
    picked when it is there and our own `... arms` objects are left out.
    """
    meshes = reference_arms(armature_fp, None)
    own = [item for item in meshes if "cyborg" in item.name.lower()]
    if own:
        return own
    return [item for item in meshes
            if not item.name.lower().endswith("arms")]


def halo_hand(armature_fp, side, reach=3.6, limit=400):
    """Halo's own hand on one side: which way its flat lies, and its own skin.

    The rig file ships the arms the game draws, so its hand is what the item's
    glove has to lie in - a glove turned a quarter about the arm reads as a
    twist however well it is placed. A hand is a flat thing, so its thinnest
    direction is the palm's normal. The skin comes back with it because a glove
    laid flat can still be a half turn out, and only the model the game draws
    can say which way round it wears it. Both answers are None when the rig
    file brought no arm mesh to measure.
    """
    bones = getattr(getattr(armature_fp, "data", None), "bones", None)
    wrist = bones.get("frame %s wriste" % side) if bones is not None else None
    if wrist is None:
        return None, None
    head = armature_fp.matrix_world @ wrist.head_local
    tail = armature_fp.matrix_world @ wrist.tail_local
    seen = []
    for item in halo_arms(armature_fp):
        matrix = item.matrix_world
        vertices = list(getattr(item.data, "vertices", []) or [])
        step = max(1, len(vertices) // limit)
        for vertex in vertices[::step]:
            point = matrix @ vertex.co
            if point_segment_distance(point, head, tail) <= reach:
                seen.append(point)
    if len(seen) < 12:
        return None, seen or None
    heading = [tail[i] - head[i] for i in range(3)]
    length = math.sqrt(sum(value * value for value in heading))
    if length <= 1e-6:
        return None, seen
    thin = hand_plane(seen, [value / length for value in heading])
    if thin is None:
        return None, seen
    return thin, seen


def arm_fit(points, armature_fp, skip, sample=400):
    """How close the carried arms are to Halo's own, as (mean, worst) units.

    The rig file ships the arms the game actually uses, so they are the target
    the item's arms have to stand in - not just the bones, which the item's
    thicker or longer limbs can sit around and still be in the wrong place.
    """
    reference = [item for item in halo_arms(armature_fp) if item is not skip]
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
        "view      : straight on, from the side the character faces; the",
        "            'front view' camera looks along it - numpad 0 shows it",
        "            upright even if this Blender did not load the saved viewport",
        "export    : BlueStreak 1.0.4 .jms exporter on the mesh",
        "merge     : append another item's - halo.blend and join the meshes;",
        "            every item is skinned to the same biped",
        "version   : %s" % VERSION,
        "build     : %s" % BUILD,
    ]
    if not arms:
        fitted = meta(mesh, "biped_fit")
        if fitted:
            lines.insert(4, "fit       : %s" % fitted)
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
        # Where the name came from, so it is never invisible: a title the
        # container states, or the fallback when it states none.
        if record.get("title"):
            lines.append("  title     : %s (from %s)"
                         % (record["title"], record.get("title_source") or "the container"))
        else:
            lines.append("  title     : none in this container - named %s" % stem)
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
        if record.get("biped_fit"):
            for line in record["biped_fit"]["lines"]:
                lines.append("  %s" % line)
        lines.append("  nxe rig   : %s" % (record.get("nxe_binding") or "not skinned"))
        lines.append("  bound to  : %s" % (record.get("binding") or "not skinned"))
        if record.get("rig"):
            lines.append("  rig check : %s" % record["rig"])
        if record.get("join"):
            lines.append("  join      : %s" % record["join"])
        if record.get("halo_file"):
            lines.append("  halo file : %s" % record["halo_file"])
        lines.append("  hek build : data\\%s\\ - one build, team colour" % stem)
        # The head is a material of its own, so it needs a shader of its own.
        # Left unsaid, the engine has nothing to draw it with and falls back to
        # its stock white shader: that white face is the missing tag, not the
        # model's texture, and it looks identical to a blank map.
        lines.append("  shaders   : the model names %d material(s). tool.exe finds a"
                     " shader tag by NAME, anywhere under tags\\ - its own folder,"
                     " yours, a mod folder, it makes no difference - and a name with"
                     " no tag draws WHITE in game rather than an error, so make one"
                     " for each name below, wherever you keep your tags."
                     % len(record.get("materials") or []))
        for material in record.get("materials") or []:
            sheet = record.get("material_maps", {}).get(
                material, "%s base map.tif" % stem)
            lines.append("              - \"%s\"  ->  a shader_model called that"
                         " (e.g. tags\\%s.shader_model), base map = a bitmap"
                         " called %s"
                         % (material, material,
                            os.path.splitext(os.path.basename(sheet))[0]))
        if os.path.exists(os.path.join(options["out"], "%s face.png" % stem)):
            lines.append("  face      : the head is material \"%s\", bound to "
                         "%s face.tif" % (tag_name(stem, "face"), stem))
            lines.append("              Guerilla: a shader_model called \"%s\" (e.g."
                         " tags\\%s.shader_model, or beside your own tags),"
                         " base map = a bitmap called \"%s face\", assigned to"
                         " that material."
                         % (tag_name(stem, "face"), tag_name(stem, "face"), stem))
            lines.append("              With no tag of that name the engine draws the"
                         " head with its stock white shader.")
            lines.append("              So a white face means a missing or empty shader"
                         " tag, not a missing texture - and if")
            lines.append("              tool.exe has already made an empty one, delete it"
                         " before making the real one.")
        if record.get("arms_file"):
            lines.append("  fp arms   : %s" % record["arms_file"])
            lines.append("              %s" % (record.get("arms_binding")
                                               or "not skinned"))
            if record.get("arms_carried"):
                lines.append("              %s" % record["arms_carried"])
            if record.get("arms_angle"):
                lines.append("              %s" % record["arms_angle"])
            if record.get("arms_fit_angle"):
                lines.append("              %s" % record["arms_fit_angle"])
            if record.get("arms_fit"):
                lines.append("              %s" % record["arms_fit"])
            if record.get("arms_fingers"):
                lines.append("              %s" % record["arms_fingers"])
            if record.get("arms_fingers_bones"):
                lines.append("              %s" % record["arms_fingers_bones"])
            if record.get("arms_finger_bones"):
                lines.append("              per bone, from the glove's skin "
                             "(+ outside, - inside):")
                for entry in record["arms_finger_bones"]:
                    lines.append("                %s" % entry)
            if record.get("arms_torn"):
                lines.append("              %s" % record["arms_torn"])
        lines.append("  vertices  : %d" % (record.get("model", {}).get("vertices") or 0))
        # What an avatar's own export added under the item, and what it did not.
        lines.extend(record.get("port") or [])
        lines.append("")
    lines.extend(rig_scene_lines(armature, nxe))
    return "\n".join(lines)


MAX_DIR = "extracted for max users"
BLENDER_DIR = "extracted for blender users"
HEK_DIR = "extracted for hek users"
# The item's own folder. One build, the one that takes the team colour: only the
# multiplayer version uses it, so there is no sp/mp pair to choose between.
# Must match extract_items.PLAIN_SUFFIX.
PLAIN_SUFFIX = ""


def hek_folders(out, stem):
    r"""Make data\<item>\ for both channel orders and say where each part goes.

    tool.exe takes data\<item>\ as its source directory and looks inside it by
    name: models\ for the .jms it compiles, animations\ for animation data, and
    bitmaps\ for the textures. The first-person arms are a model of their own,
    so they get fp\models\ and fp\source\ rather than being left in with the
    body's - but no fp\bitmaps\: their .jms names the same materials as the
    body's, so Tool resolves both models to the one shader tag per material and
    the one bitmap tag per map in the item's own bitmaps\, and a second copy
    would be a folder of files no tag points at. Each model folder carries a
    source\ holding the file the model was exported from, which is where a HEK
    user looks for the thing to re-export.

    Both orders are made here, by the same code, so pc\ and xbox\ cannot come
    out with different folders - and each order's bitmaps hold that order's own
    maps, because the pc and xbox masks are not the same bytes.
    """
    made = {}
    for order in ("pc", "xbox"):
        item_dir = os.path.join(out, HEK_DIR, order, "data",
                                stem + PLAIN_SUFFIX)
        tree = {"item": item_dir,
                "bitmaps": os.path.join(item_dir, "bitmaps"),
                "models": os.path.join(item_dir, "models"),
                "animations": os.path.join(item_dir, "animations"),
                "physics": os.path.join(item_dir, "physics"),
                "source": os.path.join(item_dir, "source"),
                "fp": os.path.join(item_dir, "fp"),
                "fp_models": os.path.join(item_dir, "fp", "models"),
                "fp_source": os.path.join(item_dir, "fp", "source")}
        for path in tree.values():
            os.makedirs(path, exist_ok=True)
        made[order] = tree
    return made


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


def copy_file(source, target):
    """Copy a file, unless the two paths are the same file.

    The build that is the item's own folder is also the source of the copies,
    so its files are already where they belong.
    """
    if os.path.abspath(source) == os.path.abspath(target):
        return False
    shutil.copyfile(source, target)
    return True


def share_files(source, target, endings=None):
    r"""Copy the files of one folder into another, making the target.

    Halo's own data\<item>\ is a folder of folders, and the same file is wanted
    in more than one of them - the textures a model compiles against, the file
    it was exported from. `endings` keeps the copy to the kinds asked for.
    """
    if not os.path.isdir(source):
        return 0
    os.makedirs(target, exist_ok=True)
    copied = 0
    for name in sorted(os.listdir(source)):
        path = os.path.join(source, name)
        if not os.path.isfile(path):
            continue
        if endings is not None and not name.lower().endswith(
                tuple(ending.lower() for ending in endings)):
            continue
        if os.path.abspath(path) == os.path.abspath(os.path.join(target, name)):
            # The build that is the source folder itself shares its own files.
            continue
        shutil.copyfile(path, os.path.join(target, name))
        copied += 1
    return copied


def jms_material_names(text, suffix):
    r"""A .jms with `suffix` added to every material name.

    The material section is the one place a .jms names a shader: a count, then
    one '<name>\t<none>' a material, and the faces below refer to a material by
    index rather than by name. Renaming here renames what tool.exe looks for
    without touching the mesh, which is what lets one item become two builds
    whose shaders can sit beside each other.
    """
    newline = "\r\n" if "\r\n" in text else "\n"
    lines = text.split(newline)
    header = lines[0].split("\t")
    if len(header) < 3 or header[0].strip() != "8200":
        raise ValueError("not a .jms: %r" % lines[0][:40])
    nodes = int(header[2])
    at = 1 + nodes
    if at >= len(lines):
        raise ValueError("the .jms ends before its materials")
    count = int(lines[at].strip())
    out = lines[:at + 1]
    for index in range(count):
        parts = lines[at + 1 + index].split("\t")
        parts[0] = parts[0] + suffix
        out.append("\t".join(parts))
    out.extend(lines[at + 1 + count:])
    return newline.join(out)


def hek_builds(out, stems):
    r"""Finish each item's one build: decal in the base map, arms beside it.

    Halo CE ships an item as a tag built from data\<item>\, and only the
    multiplayer version uses team colour - so there is one build, in the item's
    own folder, carrying the team-colour mask in its multipurpose map. The decal
    is baked into the base map because CE's shader_model samples one colour
    layer: the bitmap holds it or it is not there at all.

    There used to be four folders per item (sp, sp-decals, mp, mp-decals) with
    the .jms renamed for each, because tool.exe names tags after files. One
    build needs none of that: the model keeps its own name, so the tag is the
    item.
    """
    made = []
    for stem in sorted(set(stems)):
        for order, tree in hek_folders(out, stem).items():
            # Both base maps stay: the item's own and the copy with its decal
            # blended in, which is the one a shader binds when the suit should
            # show the decal. Copying the blend over the plain map is what used
            # to leave the HEK folder holding a different texture from the
            # Blender folder, with nothing left to compare against. The arms
            # read these same maps: their .jms materials are the body's names,
            # so one shader tag per material serves both models and nothing is
            # copied into fp\.
            for source, home, name in (
                    (os.path.join(tree["source"], jms_name(stem)),
                     tree["models"], jms_name(stem)),
                    (os.path.join(tree["fp_source"], jms_name(stem, " - fp arms")),
                     tree["fp_models"], jms_name(stem, " - fp arms"))):
                if os.path.exists(source):
                    copy_file(source, os.path.join(home, name))
            # The model folder is the one people open the item from, so the
            # .blend goes here as well as in source\. It is not a second file
            # to maintain, and it is not a tidier layout: it is the difference
            # between the .blend someone double-clicks being this build's and
            # being one an earlier build left there. The name of an item's
            # .blend is fixed, so a stale one never looks stale - it opens fine
            # and shows a model from months ago, and every rebuild since has
            # left it untouched because it was not a file this build wrote.
            for source, home in ((tree["source"], tree["models"]),
                                 (tree["fp_source"], tree["fp_models"])):
                for name in sorted(os.listdir(source)):
                    if name.lower().endswith(".blend"):
                        copy_file(os.path.join(source, name),
                                  os.path.join(home, name))
            made.append(tree["item"])
    return made


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
        # models\ holds the body's .jms, fp\models\ the first-person set's, and
        # each has a source\ beside it holding the file it was exported from.
        for folder, endings in ((("models",), (".jms",)),
                                (("fp", "models"), (".jms",)),
                                (("source",), None),
                                (("fp", "source"), None)):
            plain = stem + PLAIN_SUFFIX
            source_dir = os.path.join(hek, "pc", "data", plain, *folder)
            target_dir = os.path.join(hek, "xbox", "data", plain, *folder)
            copied += share_files(source_dir, target_dir, endings)
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
    TAG_PREFIX[0] = bool(options.get("tag_prefix"))
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
    # Textures the ported body needs in the HEK tree, per item: they belong to a
    # model that only exists once this pass has joined and skinned it, so they
    # are written with the model rather than by extraction.
    port_textures = {}
    total_items = max(len(items), 1)
    for number, (record, path) in enumerate(items, 1):
        stage = 0.04 + 0.92 * (number - 1) / total_items
        progress(stage, "item %d of %d: reading %s"
                 % (number, len(items), item_stem(record)))
        meshes = import_obj(path)
        # Before anything names them: the .blend, .fbx, .glb and .jms all name
        # a material, and a .jms material name is the shader tool.exe looks for.
        # The bitmap it is named after is the one the material wraps - the item's
        # base map, or its flat colour when it carries no texture.
        stem = item_stem(record)
        bitmap = ("%s base map" % stem if record.get("texture")
                  else "%s colour" % stem)
        named_materials = name_item_materials(meshes, bitmap)
        # The item's own box, in the space the avatar's export is authored in.
        # 360sona names the item's copy in an export after the slot it fills -
        # the armour came back as plain "hair" - so the port recognises the item
        # by its geometry as well as by its name, and leaves out the duplicate.
        item_box = mesh_box_of(meshes)
        label = record.get("name") or record["id"]
        ported_materials = None
        ported_head_material = None
        ported_box = None
        is_body = body is not None and record is body[0]
        # Avatar space is y-up in metres, so anything stopping below 1.45 m is
        # missing its head and shoulders and needs the base body underneath.
        tallest = max((vertex.co.y for item in meshes for vertex in item.data.vertices),
                      default=0.0)
        if body and not is_body and tallest < 1.45:
            log("%s stops at %.2f m, merging the base body in" % (label, tallest))
            meshes = meshes + import_obj(body[1])
        # An avatar can be given as well: its own head, face and the patch of
        # neck the item leaves bare. Only a whole body has parts like that - a
        # hat or a tee is worn on the catalogue's body, which already brings a
        # head, and two bodies under one item is not a smaller mistake than none.
        ported = None
        if options["port"] and not is_body:
            if tallest >= 1.45:
                # Does the item bring its own head and face? A costume's export
                # carries a face sheet, and this armour paints one. When it does,
                # the avatar's head must not be added on top of it.
                item_head = any("face" in (slot.material.name or "").lower()
                                for part in meshes for slot in part.material_slots
                                if slot.material)
                ported = import_port(options["port"], item_stem(record),
                                     options["out"],
                                     eyes_forward=options["eyes_forward"],
                                     item_box=item_box, item_head=item_head)
                if ported["objects"]:
                    # Tag the avatar's own vertices before the join, so the
                    # armour beside them can copy the bones the flesh rides.
                    for part in ported["objects"]:
                        tag = part.vertex_groups.new(name=PORT_GROUP)
                        tag.add([vertex.index for vertex in part.data.vertices],
                                1.0, "REPLACE")
                    meshes = meshes + ported["objects"]
                    record["port"] = ported["lines"]
                    if ported.get("join"):
                        record["join"] = "; ".join(ported["join"])
                    port_textures[item_stem(record)] = ported["textures"]
                    ported_materials = ported["material_objects"]
                    ported_head_material = ported["head_material"]
                    ported_box = ported["box"]
            else:
                log("--port not used for %s: it stops at %.2f m, so it is worn on a "
                    "body - the catalogue's body fills what it leaves bare"
                    % (label, tallest))
        merged = join_meshes(meshes, options["name"] or label)
        if not merged:
            continue
        # The export's head is two half-meshes that meet at the nose without
        # sharing a vertex. Welding the pairs that coincide turns the join into
        # one surface, which is what gives it one shading normal instead of a
        # 24 degree kink down the middle of the face.
        if ported_materials:
            welded = weld_seam(merged, ported_materials)
            if welded:
                log("port: the export cuts the face into two meshes that meet at "
                    "the nose; welded %d vertex pair(s) along their join, so the "
                    "head shades as one surface" % welded)
        prepare(merged)
        apply_uv_sets(merged, record)
        # The maps the item shipped with, bound before anything is exported:
        # a material with no image draws one flat colour in Blender, and this
        # armour's largest surface arrived that way.
        bind_item_map(merged, os.path.dirname(path))
        # Before anything is weighted: the item ships exact copies of its own
        # points, so a seam is two surfaces touching rather than one surface,
        # and every open rim is a hole the engine draws the background through.
        welded = weld_surface(merged)
        if welded:
            log("%s: welded %d duplicate vertex/vertices - points the item ships "
                "twice, which read as detached faces and could not hold a seam"
                % (merged.name, welded))
        closed, added, left = close_borders(merged)
        if closed or left:
            log("%s: closed %d open border(s) with %d face(s) so no edge of the "
                "model is open%s"
                % (merged.name, closed, added,
                   " - %d border(s) did not close" % left if left else ""))
        # The costume's own face, painted by the avatar's sheet it was laid out
        # for. Before the copies are taken, so the .blend, the .fbx and the .jms
        # all carry one face.
        if ported and ported.get("face_sheet"):
            sheet = ported["face_sheet"]
            painted = bind_face_sheet(
                merged, sheet,
                os.path.join(options["out"], "%s %s.png" % (stem, sheet[0])),
                stem)
            if painted:
                port_textures.setdefault(stem, []).append(sheet)
        if not named_materials:
            name_remaining_materials(merged, bitmap, stem)
        progress(stage + 0.02 * 0.92, "item %d of %d: %s joined (%d verts)"
                 % (number, len(items), merged.name, len(merged.data.vertices)))
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
            body = bool(not prop and anchor is None and whole_body(merged))
            if prop:
                record["placement"] = "kept where the file puts it, grown in place"
            elif anchor:
                record["placement"] = anchor[2]
            elif body:
                record["placement"] = ("kept at the shape the file authored, "
                                       "brought onto the biped's height")
            else:
                record["placement"] = "body height, grown from the floor"
            # A whole body is scaled, never fitted. Carrying it joint by joint
            # lands its joints on Halo's bones and bends it to Halo's
            # proportions on the way - every axial in that fit is a stretch, so
            # the avatar's shape is what pays, and it showed: the sleeve came out
            # x1.4 longer and x1.2 thick, the glove a rake of spikes, the
            # shoulder plates fanned apart. Shape is not negotiable, so the only
            # transform a body gets now is ONE uniform factor, measured so the
            # model stands exactly as tall as the biped. The joints it does not
            # reach are the rig's business, not the mesh's.
            scale = fit
            body_grow = None
            # Which vertices are the ported avatar and the factor they were
            # scaled by, for a body whose parts were scaled separately.
            pose_avatar = None
            pose_avatar_fit = None
            if body:
                heights = [vertex.co.y for vertex in merged.data.vertices]
                authored = (max(heights) - min(heights)) if heights else 0.0
                if ported_materials is not None:
                    ported_slots = {index for index, slot in enumerate(merged.material_slots)
                                    if slot.material in ported_materials}
                    avatar = set()
                    for polygon in merged.data.polygons:
                        if polygon.material_index in ported_slots:
                            avatar.update(polygon.vertices)
                    placed = keep_shape_scale(merged, avatar, fit)
                    if placed is None:
                        # No body under the item. That is the normal shape of a
                        # 360sona export for a full suit: the avatar is WEARING
                        # the armour, so the armour is the body and the file
                        # carries only the head above it. The head was authored
                        # on the same body the item was, so the item is the body
                        # reference and the whole model takes the item's factor:
                        # one uniform scale, head and item together, exactly as
                        # the file drew them relative to each other.
                        # One factor for every part, so the shape cannot change.
                        # Which factor: the one that puts the avatar's own head
                        # joint on Halo's head bone. That is the most a uniform
                        # scale can do for the rig, and it does a lot - every
                        # other joint of this body lands within a few units of
                        # its bone, because the avatar's joints are consistent
                        # with Halo's measured from the floor. Scaling to the
                        # biped's height instead would leave the arms bound to
                        # the hips, and scaling joint by joint is what bent the
                        # avatar out of shape in the first place.
                        spans = []
                        for axis in range(3):
                            values = [vertex.co[axis]
                                      for vertex in merged.data.vertices]
                            spans.append((max(values) - min(values)) if values else 0.0)
                        tall = max(spans)
                        head_bone = armature.data.bones.get("bip01 head")
                        head_joint = NXE_JOINTS[19]
                        if head_bone is not None and abs(head_joint[2]) > 1e-6:
                            grow = ((armature.matrix_world @ head_bone.head_local).z
                                    / (head_joint[2] * HALO_UNITS_PER_METRE))
                        else:
                            grow = (fit * AUTHORED_BODY_HEIGHT / tall) if tall > 1e-6 else fit
                        body_grow = grow
                        for vertex in merged.data.vertices:
                            vertex.co = (vertex.co.x * grow, vertex.co.y * grow,
                                         vertex.co.z * grow)
                        merged.data.update()
                        log("%s: the .glb carries no body under this item - the "
                            "avatar is wearing the suit, so the armour IS the "
                            "body and only the head sits above it. The whole "
                            "model takes ONE uniform factor x%.3f, so its head "
                            "joint lands on Halo's head bone and it stands %.3f m "
                            "- the avatar's own proportions scaled, never bent"
                            % (merged.name, grow, tall * grow))
                    if placed is not None:
                        # Both parts were scaled here - the item by fit, the
                        # avatar by the factor that makes it exactly Halo's
                        # height - so the body is stood in Halo's pose from two
                        # joint tables, one per part. Leaving this path with
                        # body_grow unset is what skipped the pose for every
                        # item that carries its own avatar: the suit stayed in
                        # the avatar's T-pose while the bones hung arms-down, and
                        # in game that is arms out, elbows folded and the boots
                        # in the ground.
                        body_grow = fit
                        pose_avatar = avatar
                        pose_avatar_fit = placed["avatar_scale"]
                        # Each part's own height, not the model's: reporting the
                        # merged height as the item's is what made the log read
                        # "its 1.850 m" for a 1.509 m armour.
                        log("%s brought onto Halo's scale (up = %s): avatar "
                            "x%.3f, %.3f m to the biped's %.3f m; item x%.3f, "
                            "%.3f m to %.3f m (authored for a %.2f m body) - one "
                            "uniform factor each, so neither changes shape"
                            % (merged.name, "xyz"[placed["axis"]],
                               placed["avatar_scale"], placed["avatar_height"],
                               placed["biped_height"], placed["item_scale"],
                               placed["item_height"], placed["item_after"],
                               AUTHORED_BODY_HEIGHT))
                    else:
                        log("%s: no avatar under the item to measure, so it keeps "
                            "the size it was authored: %.3f m"
                            % (merged.name, authored))
                    scale = 1.0
                elif authored > 0:
                    # No avatar to be the reference, so the item is what has to
                    # reach the biped: it grows to the biped's height, keeping
                    # its own proportions on the way.
                    scale = fit * AUTHORED_BODY_HEIGHT / authored
                    log("%s kept as authored: %.3f m of its own on to %.3f m of "
                        "biped, x%.3f" % (merged.name, authored,
                                          fit * AUTHORED_BODY_HEIGHT,
                                          scale / fit))
            if ported and ported.get("costume") and ported.get("body_material"):
                cut = cut_body(merged, ported["body_material"],
                               ported_head_material)
                log("port: the costume replaces the body itself, so the avatar's "
                    "own body is cut away (%d faces) - the armour is the body "
                    "from here, and the head, face, the neck under the chin and "
                    "the accessories stay" % cut)
            authored = [tuple(vertex.co) for vertex in merged.data.vertices]
            to_halo_space(merged, scale, keep_position=prop, anchor=anchor)
            # A whole body is authored in the avatar's T-pose, and Halo's
            # skeleton is not: its arms hang and its legs stand under the hips.
            # tool.exe bakes every vertex into the frame of the node it rides
            # from the .jms's own node block, so a mesh left in one pose while
            # its nodes hold another is compiled as that mismatch - in game the
            # arms stay out, the boots drop under the origin and the character
            # stands in the ground, which is what the screenshots showed. Halo's
            # block cannot move: it is the one
            # characters\cyborg\cyborg.model_animations drives. So the body is
            # stood in Halo's pose before it is skinned, by its own weights
            # (stand_in_halo_pose): neighbours travel together, no plate leaves
            # the plate it lies against, and the head's own turn is nothing. The
            # cost of a bind HEK accepts is the band across each joint, which
            # bends the way the game would bend it; --t-pose keeps the old
            # behaviour for anyone who wants the raw item.
            stood = None
            progress(stage + 0.09 * 0.92,
                     "item %d of %d: skinning %s to Halo's %d bones - the "
                     "slow part, thirteen poses"
                     % (number, len(items), merged.name, len(armature.data.bones)))
            record["binding"] = skin(merged, armature, rigid=prop)
            # The body is fitted to the bones joint by joint, as one surface,
            # the way v74 did it. Turning it plate by plate into Halo's rest pose
            # was the mistake that broke the arms: a plate is rigid, so the
            # moment it turns it leaves the plate it used to lie against, and the
            # arm reads as disconnected with holes over the shoulder and elbow.
            # Fitting moves the whole surface, so neighbouring plates travel
            # together and nothing is left standing on its own.
            progress(stage + 0.88 * 0.92,
                     "item %d of %d: %s skinned"
                     % (number, len(items), merged.name))
            record["rig"] = rig_audit(merged, armature)
            # Only a prop rides one bone. Reading the binding line instead
            # takes any garment whose top-weighted bone happens to be an arm -
            # a tee's shoulders are on the upper arms - and puts the whole
            # shirt on the first-person hand, rigid, as if it were a ring.
            bone_name = hand_item(prop, record.get("binding") or "")
            if armature_fp:
                arms_item, arms_rig = arms_for(merged, armature, armature_fp,
                                               bone_name, record)
            # A whole body is fitted to the bones after its arms are cut, so the
            # first-person set keeps the geometry it was measured on: it is the
            # set that was tuned to Halo's fingers, and a re-fitted sleeve would
            # move every glove away from them.
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
            # The one thing the conversion may not do is change the shape. A
            # uniform resize puts the item on the biped's scale; anything else -
            # turning the arms down, stretching a limb onto a longer bone - moves
            # vertices against each other, and that is what a model looks wrong
            # from. So the mesh is only ever scaled and placed: the shape check
            # below measures every edge against the one it had when it was
            # imported, and reports it.
            # Weights first, geometry after. The plates over the shoulder joint
            # are on the clavicle, which barely turns, so the arm swings out of
            # its own sleeve and the pad is left standing where the T-pose put
            # it - the shoulder reads as missing. Handing those plates to the
            # upper arm moves no vertex; it only says which bone carries them
            # when the game poses it. It has to happen BEFORE the body is stood
            # in Halo's pose, because that pass moves the mesh by its weights: a
            # pad still on the clavicle stays out at the shoulder while the arm
            # comes down, and re-hanging it afterwards would leave it swinging
            # from the T-pose place in game instead of lying on the arm.
            standing = bool(body and body_grow and options.get("stand"))
            held = 0
            shoulders = 0
            if not standing:
                # Only for a body left in the pose it was authored: there the
                # arm swings out from under the pad in game, so the pad has to
                # follow the arm instead. A stood body has no swing to make up
                # for - the sleeve is already on the arm - and moving a pad
                # built for a horizontal arm onto it stands the pad on edge as
                # a spike with the shoulder bare behind it.
                held = hold_the_arms(merged, armature)
                if held:
                    log("%s: %d plate(s) out along the arm were riding the "
                        "clavicle and now ride the arm bone"
                        % (merged.name, held))
                shoulders = hold_the_shoulders(merged, armature)
                if shoulders:
                    log("%s: %d plate(s) on a shoulder joint were riding the "
                        "torso or a leg and now ride the upper arm of their side"
                        % (merged.name, shoulders))
            if standing:
                stood = stand_in_halo_pose(
                    merged, armature, body_grow, limbs=options.get("limbs", False),
                    avatar=pose_avatar, avatar_fit=pose_avatar_fit)
                if stood:
                    record["stand"] = stood["lines"][0]
                    log("%s stood in Halo's pose: worst edge x%.2f over the "
                        "whole body" % (merged.name, stood["worst"]))
                    # The weights were measured while the arms were still out,
                    # and from there the whole sleeve is nearest the upper arm:
                    # the forearm and the hand carried no vertex at all, so the
                    # glove was moved by the shoulder bone and the game's hand
                    # node - the one a weapon is placed from - moved nothing.
                    # The bones run through the limbs now, so the skin is
                    # measured again on the body as it stands.
                    rebound = rebind(merged, armature, rigid=prop)
                    if rebound:
                        record["binding"] = rebound
                        log("%s: re-skinned on the stood body - %s"
                            % (merged.name, rebound))
            plates = hold_the_plates(merged, armature)
            if plates:
                log("%s: %d point(s) away from a joint where they blend two "
                    "bones were given the one bone they ride - a plate does not "
                    "bend, only the fabric in the band across a joint does"
                    % (merged.name, plates))
            # The holds above leave a cliff where a re-hung plate meets the
            # surface that stayed behind, and the search that shaped these
            # weights ran before they existed. Re-run it on the weights as they
            # now stand, so the cliff is drawn apart as a gradient instead of at
            # one edge: weights only, no vertex moves.
            outliers = settle_outliers(merged, armature)
            if outliers:
                log("%s: %d stray point(s) rode a bone none of their neighbours "
                    "ride and were given theirs - ten of them were enough to "
                    "open the side of the chest" % (merged.name, outliers))
            if held or shoulders or plates or outliers:
                repaired = repair_tears(merged, armature)
                if repaired:
                    log("%s: repaired the seam the re-hung plates left - %d "
                        "round(s) of the game's own poses, weights only"
                        % (merged.name, repaired))
            # The last thing the weights get, and the reason the shape is safe:
            # one node per vertex, weight 1.0. A rig with two nodes on a vertex
            # is a rig the engine blends, and a blend of two rotations is a
            # crush at the elbow and a twist in every animation that moves the
            # limb. With one node each there is nothing to blend, so no pose
            # Halo plays can bend this mesh - it only moves it.
            if body:
                single = single_bone_weights(merged, armature)
                if single:
                    record["rig"] = (rig_audit(merged, armature) + " - " + single)
                    log("%s: plates ride one node - %s" % (merged.name, single))
            shape = shape_audit(merged, authored)
            if shape:
                record["shape"] = shape["line"]
                log("%s: %s" % (merged.name, shape["line"]))
            merged_materials = 0
            if merged_materials:
                log("%s: %d material(s) with almost no faces folded into the "
                    "armour's own, so the model asks the game for two shaders "
                    "instead of three" % (merged.name, merged_materials))
            renamed = name_materials_by_bitmap(merged, item_stem(record))
            if renamed:
                log("%s: %d material(s) named after the bitmap they draw with, "
                    "because the .jms name is the shader tag name"
                    % (merged.name, renamed))
            if arms_item is not None and arms_item.data.polygons:
                name_materials_by_bitmap(arms_item, item_stem(record))
            used_slots = sorted({polygon.material_index
                                 for polygon in merged.data.polygons})
            record["materials"] = [merged.material_slots[index].material.name
                                   for index in used_slots
                                   if merged.material_slots[index].material]
            stem_now = item_stem(record)
            record["material_maps"] = {
                name: ("%s face.tif" % stem_now if "face" in name.lower()
                       else "%s body.tif" % stem_now)
                for name in record["materials"]}
            turned = face_the_world(merged)
            if turned:
                record["faces"] = ("%d face(s) in shells the item wound inside "
                                   "out were turned over - Halo draws one side "
                                   "only, so those were invisible faces" % turned)
                log("%s: %d face(s) turned the right way round - a shell the item "
                    "shipped inside out draws as nothing in game"
                    % (merged.name, turned))
            drop_floaters(merged)
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
        # The one name extraction gave the item - its title, or extractedN when
        # nothing titles it - so this pass writes into the same data\<item>\
        # that holds the bitmaps. The .obj's own name is the fallback for a
        # catalogue written by a build that did not record it.
        stem = item_stem(record)
        stems.append(stem)
                # data\<item>\ is what tool.exe takes as its source directory, and it
        # looks inside models\ for the .jms and animations\ for animation data.
        # hek_folders() makes that tree for both orders, arms folder and all,
        # so the two cannot drift apart.
        folders = hek_folders(out, stem)
        # The ported body's textures go beside each build's other maps, in both
        # channel orders. One copy per order is enough for both models: the
        # arms' .jms carries the same material names, so Tool finds the same
        # shader and bitmap tags for them, and fp\ holds no maps of its own.
        for texture, pixels, width, height in port_textures.get(stem, []):
            name = "%s %s.tif" % (stem, texture)
            # The item's own key for a picture ("body") is not the name of the
            # shader that draws it ("base map"), so each map is written under the
            # name of every material that uses it as well. The three names the
            # model asks for and the three files beside it then match exactly.
            extra = ["%s %s.tif" % (stem, suffix) for suffix in
                     ("base map", "body", "face")
                     if any(slot.material and slot.material.use_nodes
                            and any(node.type == "TEX_IMAGE" and node.image
                                    and node.image.name.startswith("%s %s." % (stem, texture))
                                    for node in slot.material.node_tree.nodes)
                            and slot.material.name.lower()
                            == ("%s %s" % (stem, suffix)).lower()
                            for slot in merged.material_slots)]
            # tool.exe takes a power of two a side and the export is not built
            # to that rule - a 360sona face is 765x930 - so the HEK copy is
            # resampled up to one. UVs are normalised, so the face stays on the
            # face. The .blend keeps the sheet at its own size.
            wide, tall = glb_model.bitmap_side(width), glb_model.bitmap_side(height)
            hek_pixels, hek_width, hek_height = glb_model.stretch_bitmap(
                pixels, width, height, wide, tall)
            if (hek_width, hek_height) != (width, height):
                log("port: %s is %dx%d, which tool.exe cannot compile, so the "
                    "HEK copy is written %dx%d" % (texture, width, height,
                                                   hek_width, hek_height))
            for tree in folders.values():
                for write_name in [name] + extra:
                    with open(os.path.join(tree["bitmaps"], write_name), "wb") as handle:
                        handle.write(tiff_bytes(hek_pixels, hek_width, hek_height))
            log("wrote %s for both channel orders" % name)
        # The armour's own picture is the base map - the sheet the base map
        # shader draws - but it arrives under the item's key for it, so a copy is
        # written under the name the model and the shader both use. tool.exe
        # compiles it into the bitmap tag the base map shader points at.
        for tree in folders.values():
            source = os.path.join(tree["bitmaps"], "%s body.tif" % stem)
            target = os.path.join(tree["bitmaps"], "%s base map.tif" % stem)
            if os.path.exists(source) and not os.path.exists(target):
                shutil.copyfile(source, target)
                log("wrote %s base map.tif - the armour's map, under its shader's name"
                    % stem)
        models_dir = folders["pc"]["models"]
        item_dir = folders["pc"]["item"]
        source_dir = folders["pc"]["source"]
        fp_models = folders["pc"]["fp_models"]
        fp_source = folders["pc"]["fp_source"]
        # Halo rig: the item on the biped, arms loaded, as a .blend that opens
        # straight onto it so it can simply be exported from there. The .jms is
        # Halo's own text model, and the .fbx is the same thing for anything
        # that cannot read a .blend.
        if armature:
            if options["jms"]:
                # Into source\, not models\: data\<item>\ is also the
                # build, and tool.exe compiles every .jms in models\, so the
                # plain model would become a second tag beside the build's own.
                # It is the file the model was exported from, which is what a
                # source\ folder is for.
                record["jms_errors"] = export_jms(
                    merged, armature, os.path.join(source_dir, jms_name(stem)))
                # A biped is not collidable without these two, and tool.exe
                # reads both from physics\ in the same source folder its model
                # came from. Only the pc tree is built here; the compile script
                # copies the finished folder into the kit either way.
                physics_dir = folders["pc"]["physics"]
                material = (merged.material_slots[0].material.name
                            if merged.material_slots
                            and merged.material_slots[0].material
                            else "material")
                try:
                    boxes = export_collision_jms(
                        merged, armature,
                        os.path.join(physics_dir, "%s collision.jms" % stem),
                        material)
                    export_physics_jms(
                        merged, armature,
                        os.path.join(physics_dir, "%s physics.jms" % stem),
                        material, boxes)
                    record["collision"] = len(boxes)
                except Exception as problem:  # noqa: BLE001 - a biped can still render
                    record["collision_errors"] = ("%s: %s"
                                                  % (type(problem).__name__, problem))
                    log("collision: could not be written - %s: %s"
                        % (type(problem).__name__, problem))
            # The file is named for the game it is for, not for the program that
            # wrote it: "- halo" is the answer to "which of these do I open?"
            # when the folder also holds the NXE and unrigged copies.
            record["halo_file"] = "%s - halo.blend" % stem
            export_rigged(os.path.join(blend_dir, record["halo_file"]),
                          merged, armature, "blend",
                          halo_note(stem, merged, armature, False))
            export_rigged(os.path.join(blend_dir, "%s - halo.fbx" % stem),
                          merged, armature, "fbx")
            share_files(blend_dir, source_dir,
                        ("%s - halo.blend" % stem, "%s - halo.fbx" % stem))
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
                        os.path.join(fp_source, jms_name(stem, " - fp arms")),
                        arms=True)
                record["arms_file"] = "%s - halo fp arms.blend" % stem
                # The arms are carried onto Halo's own first-person rig, so
                # that rig is the one in the file - the game's animations drive
                # it as they are, with nothing to retarget first.
                export_rigged(os.path.join(blend_dir, record["arms_file"]),
                              arms_item, arms_rig, "blend",
                              halo_note(stem, arms_item, arms_rig, True))
                export_rigged(os.path.join(blend_dir, "%s - halo fp arms.fbx" % stem),
                              arms_item, arms_rig, "fbx")
                share_files(blend_dir, fp_source, (" - halo fp arms.blend",
                                                  " - halo fp arms.fbx"))
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

    built = hek_builds(out, stems)
    # The step after the data is the kit: tool.exe has to compile the .jms and
    # the .tif files into tags. The script that does it is carried in this
    # payload and written beside the builds, so it is never something to go and
    # find.
    beside = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "build-hek.bat")
    if built and os.path.exists(beside):
        data = open(beside, "rb").read()
        for stem in sorted(set(stems)):
            # Named after the item, because the item is what the player is
            # compiling: "Compile UNSC Marine Armor Avatar.bat" beside the
            # builds. The script is the same wherever it goes - it reads data\
            # - so the only thing that carries the item is its name.
            name = "Compile %s Avatar.bat" % stem
            target = os.path.join(out, name)
            if not os.path.exists(target) or open(target, "rb").read() != data:
                with open(target, "wb") as handle:
                    handle.write(data)
                log("wrote %s beside the builds: run it to compile the .jms "
                    "and .tif files into tags with tool.exe" % name)
        # The answer to "the shaders exist, why is the face still white?". It
        # reads this computer's own tags - what answers each material name, what
        # base map each one holds, and whether the model tag or the .map was
        # built before them - and nothing else can know that.
        for name, source in (("Check the shaders.bat", "check-shaders.bat"),
                             ("check_shaders.py", "check_shaders.py")):
            beside = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                  source)
            if not os.path.exists(beside):
                continue
            data = open(beside, "rb").read()
            target = os.path.join(out, name)
            if not os.path.exists(target) or open(target, "rb").read() != data:
                with open(target, "wb") as handle:
                    handle.write(data)
                log("wrote %s beside the builds: it says which shader tag a "
                    "white surface is missing" % name)
    if built:
        log("wrote %d HEK build(s), one per channel order" % len(built))

    shipped = ship_source_rigs(out, options, armature)
    if shipped:
        log("kept the source rigs for repair: %s" % ", ".join(shipped))

    # card_art.png used to be a copy of the item's own picture under a second
    # name - the same bytes twice in the folder, and the icon already says which
    # item it is. Nothing read it back, so it is not written at all.

    # Sorted again, because the extractor sorted the folder before this pass ran.
    # Everything the rigging pass writes - the avatar's own face and body sheets
    # and their .tif twins, the .jms, the .blend and its .fbx - was written after
    # that one pass, so it stayed in the item's own folder: a Max user opened
    # their folder and found a model with no textures beside it, and a Blender
    # user the same, while the two sheets sat at the top looking like leftovers.
    organise(out, stems)
    log("sorted every file into the folder of the program that opens it")

    # What the compile script checks before it lets tool.exe build a model.
    # A material with no shader tag is not an error to tool.exe: it asks which
    # type to make, writes an EMPTY tag under that name and bakes the reference
    # into the .gbxmodel, and an empty shader has no base map - so that surface
    # draws white in game and compiling the model again cannot undo it. Written
    # after organise(), because the sorter does not know this file and would
    # carry it away from the script that reads it.
    wanted = []
    for row in rigged:
        record = row[0]
        stem_now = item_stem(record)
        for material in record.get("materials") or []:
            sheet = record.get("material_maps", {}).get(
                material, "%s base map.tif" % stem_now)
            bitmap = os.path.splitext(os.path.basename(sheet))[0]
            wanted.append("%s|%s|%s\\bitmaps\\%s"
                          % (stem_now, material, stem_now, bitmap))
    if wanted:
        with open(os.path.join(out, "shaders to make.txt"),
                  "w", encoding="utf-8", newline="\r\n") as handle:
            for line in wanted:
                handle.write(line + "\n")
        log("wrote \"shaders to make.txt\": %d shader tag(s), checked by the "
            "compile script before tool.exe builds a model" % len(wanted))
    return 0


if __name__ == "__main__":
    # Blender reports a failed script only when the script raises: with
    # --python-exit-code a raised exception becomes Blender's own exit code,
    # while sys.exit() is swallowed and the pass still looks successful.
    status = main()
    if status:
        raise RuntimeError("rigging stopped with code %d" % status)
