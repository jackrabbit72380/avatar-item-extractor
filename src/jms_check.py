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

HEADER = ("8200", "3251")

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


def _numbers(fields, where, errors):
    try:
        return [float(field) for field in fields]
    except ValueError:
        errors.append("%s: not all numbers (%s)" % (where, " ".join(fields)))
        return None


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
    if len(fields) != 3 or (fields[0], fields[1]) != HEADER:
        errors.append("header is %r, expected %s %s <nodes>"
                      % (header[:40], HEADER[0], HEADER[1]))
        return errors, notes, stats
    node_count = int(fields[2])
    stats["nodes"] = node_count
    if node_count < 1:
        errors.append("node count is %d" % node_count)
        return errors, notes, stats

    # ----------------------------------------------------------------- nodes
    first_child, next_sibling, names = [], [], []
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
        if _numbers(parts[7:10], "node %d position" % index, errors) is None:
            return errors, notes, stats

    # Halo's own biped: its node list is fixed, and only this order is the one
    # the retail animation graph matches. A same-named skeleton written in any
    # other order carries a different node list checksum and animates the wrong
    # bones, so it is an error rather than a note.
    if node_count == len(BIPED_NODES):
        if tuple(names) == BIPED_NODE_ORDER:
            stats["biped"] = True
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
    print("PASS %s  nodes %d, faces %d, verts %d, materials %d, two-weight verts %d"
          % (path, stats.get("nodes", 0), stats.get("faces", 0),
             stats.get("vertices", 0), stats.get("materials", 0),
             stats.get("two_weight_vertices", 0)))
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
