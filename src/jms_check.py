#!/usr/bin/env python3
"""Structural check for a Halo CE ``.jms``.

The file is positional, with no section markers, so a single wrong count shifts
everything after it and the file still looks like text. This reads it the way
``tool.exe`` has to - by the counts - and reports what a compiler would trip on:
the header, the node block and the hierarchy it describes, the vertex block and
each corner's two node slots and weights, the texture coordinate slot, and the
faces against the vertex and material counts.

It proves the file is well formed. It cannot prove ``tool.exe`` accepts the
result - only the compiler can - but everything that can be checked by reading
the file is checked here.

    python3 jms_check.py <file.jms> [...]
"""

import math
import sys

# The header line is ``8200 <node list checksum> <node count>``. The middle
# field is the checksum tool.exe copies into the gbxmodel, not a version and not
# a constant: BlueStreak writes 3251 there, and a model carrying it does not
# match Halo's own animation graph even when its node list is exactly Halo's.
HEADER = "8200"

# Halo's own biped skeleton, in the order the retail animation graph stores it:
# (name, first child, next sibling, parent), node 0 first. This is the node list
# of ``characters\cyborg\cyborg`` - 19 nodes, node list checksum 1828349080, the
# value ``tool model`` writes into the gbxmodel built from it. The order is not
# cosmetic: an animation addresses a node by its index, and the engine refuses a
# model whose checksum or node count differs from the graph's with "the model
# ... and the animation graph ... don't match". The same 19 names in another
# order are a different node list, so the exporter writes this one and the
# checker below rejects any other.
BIPED_NODES = (
    ("bip01 pelvis", 2, -1, -1),
    ("bip01 l thigh", 4, 3, 0),
    ("bip01 r thigh", 5, 1, 0),
    ("bip01 spine", 6, -1, 0),
    ("bip01 l calf", 8, -1, 1),
    ("bip01 r calf", 11, -1, 2),
    ("bip01 spine1", 10, -1, 3),
    ("bip01 l clavicle", 13, 9, 6),
    ("bip01 l foot", -1, -1, 4),
    ("bip01 neck", 12, -1, 6),
    ("bip01 r clavicle", 14, 7, 6),
    ("bip01 r foot", -1, -1, 5),
    ("bip01 head", -1, -1, 9),
    ("bip01 l upperarm", 15, -1, 7),
    ("bip01 r upperarm", 16, -1, 10),
    ("bip01 l forearm", 17, -1, 13),
    ("bip01 r forearm", 18, -1, 14),
    ("bip01 l hand", -1, -1, 15),
    ("bip01 r hand", -1, -1, 16),
)
BIPED_NODE_ORDER = tuple(row[0] for row in BIPED_NODES)
BIPED_NODE_CHECKSUM = 1828349080

# Where Halo's own biped puts each node in model space, read from Halo's own
# ``spartan.jms`` - the cyborg the retail animation graph drives. These are the
# positions the rig the exporter ships carries (pelvis 39.44, spine 43.18,
# spine1 50.58, neck 59.19, head 60.91, hands +-13.32 at 35.23, feet 6.88), so a
# node block that composes to anything else does not describe Halo's skeleton.
BIPED_POSITIONS = (
    (-0.8210, 0.0000, 39.4385),      #  0 bip01 pelvis
    (-0.8210, 4.2186, 39.4385),      #  1 bip01 l thigh
    (-0.8210, -4.2186, 39.4385),     #  2 bip01 r thigh
    (-0.8269, 0.0000, 43.1751),      #  3 bip01 spine
    (-1.3984, 5.3125, 22.2705),      #  4 bip01 l calf
    (-1.3422, -5.2305, 22.2637),     #  5 bip01 r calf
    (-0.8278, 0.0000, 50.5751),      #  6 bip01 spine1
    (-0.8210, 5.9803, 56.9244),      #  7 bip01 l clavicle
    (-3.9018, 6.2993, 6.8779),       #  8 bip01 l foot
    (-0.8223, 0.0000, 59.1878),      #  9 bip01 neck
    (-0.8210, -5.9803, 56.9244),     # 10 bip01 r clavicle
    (-3.9115, -6.1430, 6.8774),      # 11 bip01 r foot
    (-0.7175, 0.0000, 60.9093),      # 12 bip01 head
    (-0.8210, 9.0228, 56.9244),      # 13 bip01 l upperarm
    (-0.8210, -9.0228, 56.9244),     # 14 bip01 r upperarm
    (-0.7272, 11.1376, 46.2730),     # 15 bip01 l forearm
    (-0.7271, -11.1376, 46.2730),    # 16 bip01 r forearm
    (0.9459, 13.3155, 35.2294),      # 17 bip01 l hand
    (0.9459, -13.3156, 35.2294),     # 18 bip01 r hand
)

# How far a node may sit from Halo's own before the block is a different
# skeleton. Six units is 18 cm: far more than any rig that is Halo's biped can
# drift, and far less than the tens of units writing the turns the wrong way
# round throws the skeleton by.
BIPED_PLACEMENT = 6.0

# Halo's own first-person arm set: the 37 node names every weapon's retail
# first-person animation graph carries for the arms, read from Halo's own
# ``fp arms.blend``. A weapon graph is bigger - the plasma rifle's is 42 nodes,
# these 37 plus ``frame gun``, ``frame rod_left``, ``frame rod_right``,
# ``frame wing_left`` and ``frame wing_right`` - and H1 does not compare the
# hands model's node count with it: the first-person renderer calls
# ``animation_get_node_orientations`` with no model at all and remaps the
# graph's nodes onto the hands model by name. A node name the graph does not
# have therefore breaks that match, and a weapon whose hands and weapon tables
# are not both valid is never set up - it silently stops drawing in first
# person. So the arms model may carry exactly these names, and the exporter
# refuses anything else rather than write it.
#
# The two spellings are Halo's own: ``frame l middlelow`` has no space and
# ``frame r middle low`` has one.
FP_ARMS_NODES = (
    "frame bone24",
    "frame l upperarm",
    "frame l forearm",
    "frame l wriste",
    "frame l thumb low",
    "frame l thumb mid",
    "frame l thumb tip",
    "frame l index low",
    "frame l index mid",
    "frame l index tip",
    "frame l middlelow",
    "frame l middle mid",
    "frame l middle tip",
    "frame l ring low",
    "frame l ring mid",
    "frame l ring tip",
    "frame l pinky low",
    "frame l pinky mid",
    "frame l pinky tip",
    "frame r upperarm",
    "frame r forearm",
    "frame r wriste",
    "frame r thumb low",
    "frame r thumb mid",
    "frame r thumb tip",
    "frame r index low",
    "frame r index mid",
    "frame r index tip",
    "frame r middle low",
    "frame r middle mid",
    "frame r middle tip",
    "frame r ring low",
    "frame r ring mid",
    "frame r ring tip",
    "frame r pinky low",
    "frame r pinky mid",
    "frame r pinky tip",
)
FP_ARMS_NODE_SET = frozenset(FP_ARMS_NODES)


def fp_arm_node_problem(names):
    """Why ``names`` cannot be the first-person arms' node list, or None.

    The hands model is the one model H1 poses by name: every weapon's
    first-person graph is matched against it with ``strcmp``. Its node block is
    therefore not free-form - a renamed or extra bone is a name no weapon graph
    has, and one is enough to stop that weapon drawing in first person.
    """
    names = list(names)
    if len(names) == len(FP_ARMS_NODES) and set(names) == FP_ARMS_NODE_SET:
        return None
    present = set(names)
    extra = [name for name in names if name not in FP_ARMS_NODE_SET]
    missing = [name for name in FP_ARMS_NODES if name not in present]
    problems = []
    if extra:
        problems.append("%d node name(s) no Halo first-person graph has: %s"
                        % (len(extra),
                           ", ".join(repr(name) for name in extra[:6])))
    if missing:
        problems.append("%d of Halo's 37 arm nodes missing: %s"
                        % (len(missing),
                           ", ".join(repr(name) for name in missing[:6])))
    if not problems:
        problems.append("%d nodes, but not Halo's 37 distinct arm names"
                        % len(names))
    return ("the fp arms rig is not Halo's own 37-bone set: %s. H1 matches the "
            "hands model to each weapon's first-person graph by node name, and "
            "a name that graph does not carry stops the weapon drawing in "
            "first person, so no arms .jms was written. Export from Halo's "
            "own 'fp arms.blend' with its bones unchanged."
            % "; ".join(problems))


def _numbers(fields, where, errors):
    try:
        return [float(field) for field in fields]
    except ValueError:
        errors.append("%s: not all numbers (%s)" % (where, " ".join(fields)))
        return None


def _turn_matrix(turn):
    """The 3x3 that a stored node quaternion turns with."""
    x, y, z, w = turn
    return ((1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - z * w),
             2.0 * (x * z + y * w)),
            (2.0 * (x * y + z * w), 1.0 - 2.0 * (x * x + z * z),
             2.0 * (y * z - x * w)),
            (2.0 * (x * z - y * w), 2.0 * (y * z + x * w),
             1.0 - 2.0 * (x * x + y * y)))


def _multiplied(first, second):
    return tuple(tuple(sum(first[row][k] * second[k][column] for k in range(3))
                       for column in range(3)) for row in range(3))


def _transposed(turn):
    return tuple(tuple(turn[column][row] for column in range(3))
                 for row in range(3))


def _carried(turn, point):
    return tuple(sum(turn[row][k] * point[k] for k in range(3))
                 for row in range(3))


def _compose_node(index, parents, turns, spots, place, open_nodes):
    """One node's frame in model space, composed the way Halo's file composes.

    A stored turn is the INVERSE of the node's own turn against its parent:
    Halo's own ``spartan.jms`` only rebuilds the cyborg's bone positions when
    each stored turn goes in transposed, and its translation - in the parent's
    space - is carried by the parent's frame. Written the natural way round
    instead, every bind frame is inverted; tool.exe compiles that without a
    word, and the engine then draws the mesh as a heap.
    """
    if index in place:
        return place[index]
    open_nodes.add(index)
    stored = _transposed(_turn_matrix(turns[index]))
    parent = parents.get(index)
    if parent is None or parent in open_nodes:
        place[index] = (stored, spots[index])
    else:
        above, where = _compose_node(parent, parents, turns, spots, place,
                                     open_nodes)
        moved = _carried(above, spots[index])
        place[index] = (_multiplied(above, stored),
                        tuple(where[axis] + moved[axis] for axis in range(3)))
    open_nodes.discard(index)
    return place[index]


def _composed_nodes(first_child, next_sibling, turns, spots):
    """Every node's model-space position, from the block as it is written."""
    parents = {}
    for index in range(len(turns)):
        child = first_child[index]
        while 0 <= child < len(turns) and child not in parents:
            parents[child] = index
            child = next_sibling[child]
    place = {}
    for index in range(len(turns)):
        _compose_node(index, parents, turns, spots, place, set())
    return {index: entry[1] for index, entry in place.items()}


def check_jms(path):
    """Return (errors, notes, stats) for one .jms file."""
    errors, notes = [], []
    stats = {}
    try:
        with open(path, encoding="ascii", errors="replace") as handle:
            lines = [line.rstrip("\n") for line in handle]
    except OSError as error:
        return ["cannot read: %s" % error], notes, stats

    at = 0

    def take():
        nonlocal at
        if at >= len(lines):
            errors.append("file ends early, after line %d" % at)
            return None
        line = lines[at]
        at += 1
        return line

    def whole(where):
        line = take()
        if line is None:
            return None
        try:
            return int(line.split("\t")[0])
        except ValueError:
            errors.append("%s: expected a count, found %r" % (where, line[:40]))
            return None

    # ---------------------------------------------------------------- header
    header = take()
    if header is None:
        return errors, notes, stats
    fields = header.split("\t")
    if len(fields) != 3 or fields[0] != HEADER:
        errors.append("header is %r, expected 8200 <node list checksum> <nodes>"
                      % (header[:40],))
        return errors, notes, stats
    try:
        checksum, node_count = int(fields[1]), int(fields[2])
    except ValueError:
        errors.append("header is %r, expected 8200 <node list checksum> <nodes>"
                      % (header[:40],))
        return errors, notes, stats
    stats["checksum"] = checksum
    stats["nodes"] = node_count
    if node_count < 1:
        errors.append("node count is %d" % node_count)
        return errors, notes, stats

    # ----------------------------------------------------------------- nodes
    first_child, next_sibling, names, turns, spots = [], [], [], [], []
    for index in range(node_count):
        line = take()
        if line is None:
            return errors, notes, stats
        parts = line.split("\t")
        if len(parts) != 10:
            errors.append("node %d: %d fields, expected 10" % (index, len(parts)))
            return errors, notes, stats
        names.append(parts[0])
        try:
            child, sibling = int(parts[1]), int(parts[2])
        except ValueError:
            errors.append("node %d: child/sibling are not numbers" % index)
            return errors, notes, stats
        for label, value in (("first child", child), ("next sibling", sibling)):
            if value != -1 and not 0 <= value < node_count:
                errors.append("node %d (%s): %s %d is outside 0..%d"
                              % (index, parts[0], label, value, node_count - 1))
        first_child.append(child)
        next_sibling.append(sibling)
        turn = _numbers(parts[3:7], "node %d rotation" % index, errors)
        if turn:
            length = math.sqrt(sum(value * value for value in turn))
            if abs(length - 1.0) > 1e-3:
                errors.append("node %d (%s): rotation length %.4f, expected 1"
                              % (index, parts[0], length))
        position = _numbers(parts[7:10], "node %d position" % index, errors)
        if position is None:
            return errors, notes, stats
        turns.append(turn or (0.0, 0.0, 0.0, 1.0))
        spots.append(position)

    # Halo's own biped: its node list is fixed, and only this order is the one
    # the retail animation graph matches. A same-named skeleton written in any
    # other order carries a different node list checksum and animates the wrong
    # bones, so it is an error rather than a note.
    if node_count == len(BIPED_NODES):
        if tuple(names) == BIPED_NODE_ORDER:
            stats["biped"] = True
            # The node list is only half of the match. tool.exe copies the
            # header's checksum into the gbxmodel and the engine compares it
            # with the animation graph's, so Halo's own biped carries Halo's own
            # value; 3251 is BlueStreak's constant and 0 switches the comparison
            # off, leaving a model that cannot prove it belongs to its graph.
            if checksum != BIPED_NODE_CHECKSUM:
                errors.append(
                    "header node list checksum is %d, expected %d - tool.exe "
                    "copies it into the gbxmodel, and the engine refuses a biped "
                    "whose model and animation graph differ: \"the model '...' "
                    "and the animation graph '...' don't match\""
                    % (checksum, BIPED_NODE_CHECKSUM))
            for index, (name, child, sibling, _parent) in enumerate(BIPED_NODES):
                if first_child[index] != child or next_sibling[index] != sibling:
                    errors.append(
                        "node %d (%s): first child / next sibling are %d / %d, "
                        "expected %d / %d from Halo's own biped"
                        % (index, name, first_child[index], next_sibling[index],
                           child, sibling))
        elif set(names) == set(BIPED_NODE_ORDER):
            stats["biped"] = False
            errors.append(
                "the nodes are Halo's biped bones but not in its order: node 0 "
                "is %r, expected %r - an animation graph binds nodes by index, "
                "so this skeleton cannot be driven by "
                "characters\\cyborg\\cyborg"
                % (names[0], BIPED_NODE_ORDER[0]))

    # The hierarchy the child/sibling links describe.
    parent = {}
    roots = []
    for index in range(node_count):
        if first_child[index] == -1:
            continue
        child, seen = first_child[index], 0
        while child != -1:
            if not 0 <= child < node_count:
                break
            if child in parent:
                errors.append("node %d (%s) is a child of both %d and %d"
                              % (child, names[child], parent[child], index))
            parent[child] = index
            seen += 1
            if seen > node_count:
                errors.append("node %d (%s): sibling chain loops" % (index, names[index]))
                break
            child = next_sibling[child]
    for index in range(node_count):
        if index not in parent:
            roots.append(index)
    if roots != [0]:
        errors.append("roots are %s, expected exactly node 0" % roots)
    for index in sorted(parent):
        if parent[index] >= index:
            notes.append("node %d (%s) is written before its parent %d"
                         % (index, names[index], parent[index]))
    stats["roots"] = len(roots)

    # The node block is the skeleton tool.exe builds, and every vertex is baked
    # into the space of the node it rides: a block that describes another
    # skeleton compiles into a model that comes apart the moment the game poses
    # it. Halo's own biped is the only skeleton its animation graph drives, and
    # its node positions are known from spartan.jms, so the block is composed
    # and compared rather than trusted. This is the failure that looks perfect
    # in Blender - which deforms through the armature and never reads the
    # block - and is a pile of stretched triangles in game.
    if stats.get("biped"):
        placed = _composed_nodes(first_child, next_sibling, turns, spots)
        worst, worst_name = 0.0, ""
        for index, expected in enumerate(BIPED_POSITIONS):
            actual = placed.get(index)
            if actual is None:
                continue
            gap = math.sqrt(sum((actual[axis] - expected[axis]) ** 2
                                for axis in range(3)))
            if gap > worst:
                worst, worst_name = gap, names[index]
        if worst > BIPED_PLACEMENT:
            errors.append(
                "node block describes another skeleton: %s lands %.1f units "
                "from where Halo's own biped puts it - a .jms stores each "
                "node's turn inverted (BlueStreak writes it as \"quat -rot.x "
                "-rot.y -rot.z rot.w\"), and the natural turn written instead "
                "inverts every bind frame: tool.exe compiles it, Blender still "
                "looks right because it deforms through the armature, and the "
                "game draws the mesh as a heap of stretched triangles"
                % (worst_name, worst))

    # ------------------------------------------------------------- materials
    material_count = whole("material count")
    if material_count is None:
        return errors, notes, stats
    stats["materials"] = material_count
    for index in range(material_count):
        line = take()
        if line is None:
            return errors, notes, stats
        if len(line.split("\t")) < 2:
            errors.append("material %d: expected a name and a path" % index)

    # --------------------------------------------------------------- markers
    marker_count = whole("marker count")
    if marker_count is None:
        return errors, notes, stats
    stats["markers"] = marker_count
    marker_names = set()
    for index in range(marker_count):
        line = take()
        if line is None:
            return errors, notes, stats
        parts = line.split("\t")
        if len(parts) != 11:
            errors.append("marker %d: %d fields, expected 11" % (index, len(parts)))
            continue
        name = parts[0]
        if not name:
            errors.append("marker %d: no name" % index)
        elif name in marker_names:
            errors.append("marker %d (%s): the name is used twice" % (index, name))
        marker_names.add(name)
        try:
            node = int(parts[2])
        except ValueError:
            errors.append("marker %d (%s): node is not a number" % (index, name))
            continue
        if not 0 <= node < node_count:
            errors.append("marker %d (%s): node %d is outside 0..%d"
                          % (index, name, node, node_count - 1))
        turn = _numbers(parts[3:7], "marker %d (%s) rotation" % (index, name), errors)
        if turn:
            length = math.sqrt(sum(value * value for value in turn))
            if abs(length - 1.0) > 1e-3:
                errors.append("marker %d (%s): rotation length %.4f, expected 1"
                              % (index, name, length))
        _numbers(parts[7:10], "marker %d (%s) position" % (index, name), errors)
        try:
            float(parts[10])
        except ValueError:
            errors.append("marker %d (%s): radius is not a number" % (index, name))

    # --------------------------------------------------------------- regions
    region_count = whole("region count")
    if region_count is None:
        return errors, notes, stats
    stats["regions"] = region_count
    for index in range(region_count):
        if take() is None:
            return errors, notes, stats

    # --------------------------------------------------------------- vertices
    vertex_count = whole("vertex count")
    if vertex_count is None:
        return errors, notes, stats
    stats["vertices"] = vertex_count
    weight_splits = 0
    used_nodes = set()
    for index in range(vertex_count):
        line = take()
        if line is None:
            return errors, notes, stats
        parts = line.split("\t")
        if len(parts) != 12:
            errors.append("vertex %d: %d fields, expected 12" % (index, len(parts)))
            return errors, notes, stats
        try:
            node0, node1 = int(parts[0]), int(parts[7])
            weight1 = float(parts[8])
        except ValueError:
            errors.append("vertex %d: node or weight is not a number" % index)
            continue
        if not 0 <= node0 < node_count:
            errors.append("vertex %d: first node %d is outside 0..%d"
                          % (index, node0, node_count - 1))
        else:
            used_nodes.add(node0)
        if node1 != -1:
            if not 0 <= node1 < node_count:
                errors.append("vertex %d: second node %d is outside 0..%d"
                              % (index, node1, node_count - 1))
            elif node1 == node0:
                errors.append("vertex %d: both slots name node %d" % (index, node0))
            else:
                used_nodes.add(node1)
                weight_splits += 1
            if not 0.0 <= weight1 <= 1.0:
                errors.append("vertex %d: second weight %.4f is outside 0..1"
                              % (index, weight1))
        elif weight1 != 0.0:
            errors.append("vertex %d: weight %.4f on no node" % (index, weight1))
        if _numbers(parts[1:7], "vertex %d position/normal" % index, errors) is None:
            continue
        uv = _numbers(parts[9:12], "vertex %d texture coordinate" % index, errors)
        if uv is None:
            continue
        u, v, w = uv
        if w != 0.0:
            errors.append("vertex %d: texture coordinate w is %.6f, must be 0"
                          % (index, w))
        if not (math.isfinite(u) and math.isfinite(v)):
            errors.append("vertex %d: texture coordinate is not finite" % index)
        elif not (-8.0 <= u <= 8.0 and -8.0 <= v <= 8.0):
            notes.append("vertex %d: texture coordinate %.3f %.3f is far outside 0..1"
                         % (index, u, v))
    stats["two_weight_vertices"] = weight_splits
    stats["nodes_used"] = len(used_nodes)

    # ----------------------------------------------------------------- faces
    face_count = whole("face count")
    if face_count is None:
        return errors, notes, stats
    stats["faces"] = face_count
    if vertex_count != face_count * 3:
        errors.append("vertex count %d is not three per face for %d faces (%d)"
                      % (vertex_count, face_count, face_count * 3))
    for index in range(face_count):
        line = take()
        if line is None:
            return errors, notes, stats
        parts = line.split("\t")
        if len(parts) != 5:
            errors.append("face %d: %d fields, expected 5" % (index, len(parts)))
            return errors, notes, stats
        try:
            region, shader, corners = int(parts[0]), int(parts[1]), [int(p) for p in parts[2:]]
        except ValueError:
            errors.append("face %d: not all numbers" % index)
            continue
        if not 0 <= region < region_count:
            errors.append("face %d: region %d is outside 0..%d"
                          % (index, region, region_count - 1))
        if not 0 <= shader < material_count:
            errors.append("face %d: shader %d is outside 0..%d"
                          % (index, shader, material_count - 1))
        for corner in corners:
            if not 0 <= corner < vertex_count:
                errors.append("face %d: vertex %d is outside 0..%d"
                              % (index, corner, vertex_count - 1))
                break
        if len(set(corners)) != 3:
            errors.append("face %d: corners %s repeat a vertex" % (index, corners))

    if at < len(lines) and any(line.strip() for line in lines[at:]):
        errors.append("%d unexpected line(s) after the faces" % (len(lines) - at))

    unused = sorted(set(range(node_count)) - used_nodes)
    if unused:
        notes.append("%d node(s) carry no vertex: %s"
                     % (len(unused), ", ".join(names[index] for index in unused[:6])))
    return errors, notes, stats


def report(path, errors, notes, stats):
    if errors:
        print("FAIL %s" % path)
        for problem in errors[:12]:
            print("   %s" % problem)
        if len(errors) > 12:
            print("   ... and %d more" % (len(errors) - 12))
        return False
    print("PASS %s  nodes %d, checksum %d, faces %d, verts %d, materials %d, "
          "two-weight verts %d"
          % (path, stats.get("nodes", 0), stats.get("checksum", 0),
             stats.get("faces", 0), stats.get("vertices", 0),
             stats.get("materials", 0), stats.get("two_weight_vertices", 0)))
    for note in notes[:6]:
        print("   note: %s" % note)
    return True


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    ok = True
    for path in argv:
        errors, notes, stats = check_jms(path)
        ok = report(path, errors, notes, stats) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
