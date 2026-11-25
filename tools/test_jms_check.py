#!/usr/bin/env python3
"""Check that jms_check.py accepts a good .jms and catches the ways it goes bad.

A validator that says "ok" for everything is worse than none, so every fault the
checker claims to find is injected here into a file that otherwise passes, and
the checker has to name it.

    python3 tools/test_jms_check.py
"""

import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MODULES = os.environ.get("RIG_MODULES") or os.path.join(
    os.path.dirname(HERE), "src")
sys.path.insert(0, MODULES)

from jms_check import (BIPED_NODES, BIPED_NODE_CHECKSUM,  # noqa: E402
                       FP_ARMS_BLOCK, FP_ARMS_NODE_SET, check_jms)

NODES = 3

# Halo's own biped node block, exactly as ``characters\cyborg`` carries it in
# Halo's ``spartan.jms``: (rotation, translation against the parent) per node,
# in BIPED_NODES order. Composing these reproduces the cyborg's bone positions
# only because each turn is the INVERSE of the node's own turn - which is what
# the exporter has to write and what the checker now verifies.
STANDING = (
    ((0.499999, 0.500000, 0.499999, 0.500001), (-0.82100, 0.00000, 39.43850)),
    ((0.016813, -0.999353, 0.000994, -0.031779), (-0.00001, 0.00001, 4.21865)),
    ((0.015175, -0.999452, -0.000967, 0.029396), (0.00001, -0.00001, -4.21865)),
    ((0.000002, 0.000001, -0.000398, 1.000000), (3.73659, -0.00589, 0.00000)),
    ((-0.000000, 0.000000, 0.063633, 0.997973), (17.21253, 0.00000, -0.00000)),
    ((-0.000000, 0.000000, 0.067397, 0.997726), (17.21253, -0.00000, -0.00000)),
    ((0.000000, -0.000000, -0.000000, 1.000000), (7.39999, -0.00686, -0.00000)),
    ((-0.707107, 0.000282, -0.707107, 0.000281), (6.34932, 0.00179, 5.98027)),
    ((-0.001031, 0.031779, -0.080371, 0.996258), (15.62605, -0.00000, -0.00000)),
    ((0.000000, 0.000000, -0.029996, 0.999550), (8.61271, -0.00137, -0.00000)),
    ((0.707107, -0.000281, -0.707107, 0.000283), (6.34932, 0.00182, -5.98027)),
    ((0.001016, -0.029394, -0.082501, 0.996157), (15.62605, 0.00000, -0.00000)),
    ((0.000000, -0.000000, 0.030394, 0.999538), (1.72475, -0.00000, 0.00000)),
    ((-0.000778, -0.634504, 0.006228, 0.772894), (3.04257, -0.00000, 0.00000)),
    ((0.000778, 0.634504, 0.006228, 0.772894), (3.04257, 0.00000, 0.00000)),
    ((0.000000, -0.000000, 0.069403, 0.997589), (10.85973, 0.00000, -0.00000)),
    ((-0.000000, -0.000000, 0.069403, 0.997589), (10.85973, 0.00000, -0.00000)),
    ((0.701751, -0.130519, -0.126017, 0.688934), (11.37995, -0.00000, -0.00000)),
    ((-0.701751, 0.130519, -0.126017, 0.688934), (11.37995, -0.00000, -0.00000)),
)


def good_file():
    """A minimal well-formed .jms: three nodes, one material, one triangle."""
    lines = ["8200\t0\t%d" % NODES]
    for index in range(NODES):
        # name, first child, next sibling, rotation (identity), position
        child = index + 1 if index + 1 < NODES else -1
        lines.append("node%d\t%d\t-1\t0.000000\t0.000000\t0.000000\t1.000000\t"
                     "0.000000\t0.000000\t%.6f" % (index, child, float(index)))
    lines.append("1")                    # materials
    lines.append("shirt\t<none>")
    lines.append("1")                    # markers
    lines.append("head\t-1\t1\t0.000000\t0.000000\t0.000000\t1.000000\t"
                 "0.000000\t0.000000\t0.000000\t0.000000")
    lines.append("1")                    # regions
    lines.append("unnamed")
    lines.append("3")                    # vertices: three per face
    for index in range(3):
        lines.append("0\t0.000000\t0.000000\t0.000000\t0.000000\t1.000000\t"
                     "0.000000\t1\t0.500000\t0.100000\t0.200000\t0.000000")
    lines.append("1")                    # faces
    lines.append("0\t0\t0\t1\t2")
    return lines


def biped_file():
    """A 19-node .jms whose node block is Halo's own biped, in its own order."""
    lines = ["8200\t%d\t%d" % (BIPED_NODE_CHECKSUM, len(BIPED_NODES))]
    for index, (name, child, sibling, _parent) in enumerate(BIPED_NODES):
        turn, spot = STANDING[index]
        lines.append("%s\t%d\t%d\t%.6f\t%.6f\t%.6f\t%.6f\t"
                     "%.6f\t%.6f\t%.6f"
                     % (name, child, sibling, turn[0], turn[1], turn[2],
                        turn[3], spot[0], spot[1], spot[2]))
    lines.append("1")                    # materials
    lines.append("shirt\t<none>")
    lines.append("0")                    # markers
    lines.append("1")                    # regions
    lines.append("unnamed")
    lines.append("3")                    # vertices: three per face
    for _index in range(3):
        lines.append("0\t0.000000\t0.000000\t0.000000\t0.000000\t1.000000\t"
                     "0.000000\t-1\t0.000000\t0.100000\t0.200000\t0.000000")
    lines.append("1")                    # faces
    lines.append("0\t0\t0\t1\t2")
    return lines


def arms_file():
    """A 37-node .jms whose node block is Halo's own first-person hands.

    ``FP_ARMS_BLOCK`` is the 42-node block from Digsite's plasma rifle ``fp``
    model: the 37 arm frames plus the weapon's five, whose sibling chain runs
    between them. A hands model carries the 37, so the weapon frames are dropped
    and the chains re-linked through them - the same block the shipped rig
    exports, which is 0.04 degrees and 0.000 units from Halo's own.
    """
    keep = [index for index, row in enumerate(FP_ARMS_BLOCK)
            if row[0] in FP_ARMS_NODE_SET]
    where = {old: new for new, old in enumerate(keep)}

    def next_kept(index):
        while index != -1 and index not in where:
            index = FP_ARMS_BLOCK[index][2]
        return where.get(index, -1)

    lines = ["8200\t0\t%d" % len(keep)]
    for old in keep:
        name, child, sibling, turn, spot = FP_ARMS_BLOCK[old]
        lines.append("%s\t%d\t%d\t%.6f\t%.6f\t%.6f\t%.6f\t"
                     "%.6f\t%.6f\t%.6f"
                     % (name, next_kept(child), next_kept(sibling),
                        turn[0], turn[1], turn[2], turn[3],
                        spot[0], spot[1], spot[2]))
    lines.append("1")                    # materials
    lines.append("shirt\t<none>")
    lines.append("0")                    # markers: the hands model carries none
    lines.append("1")                    # regions
    lines.append("unnamed")
    lines.append("3")                    # vertices: three per face
    for _index in range(3):
        lines.append("0\t0.000000\t0.000000\t0.000000\t0.000000\t1.000000\t"
                     "0.000000\t-1\t0.000000\t0.100000\t0.200000\t0.000000")
    lines.append("1")                    # faces
    lines.append("0\t0\t0\t1\t2")
    return lines


def accept_lines(name, lines):
    """Nothing wrong with this file, and the checker has to say so."""
    handle, path = tempfile.mkstemp(suffix=".jms")
    with os.fdopen(handle, "w", encoding="ascii", newline="") as out:
        out.write("\n".join(lines) + "\n")
    try:
        errors, _notes, _stats = check_jms(path)
    finally:
        os.remove(path)
    if errors:
        print("  REFUSED %-38s %s" % (name, errors[0][:60]))
        return False
    print("  accepts %-38s as Halo's own" % name)
    return True


def check_lines(name, lines, expect):
    handle, path = tempfile.mkstemp(suffix=".jms")
    with os.fdopen(handle, "w", encoding="ascii", newline="") as out:
        out.write("\n".join(lines) + "\n")
    try:
        errors, _notes, stats = check_jms(path)
    finally:
        os.remove(path)
    hit = [problem for problem in errors if expect in problem]
    if hit:
        print("  caught  %-38s %s" % (name, hit[0][:60]))
        return True
    print("  MISSED  %-38s expected %r, got %s"
          % (name, expect, errors[:2] or "no errors at all"))
    return False


def check_mutation(name, change, expect):
    lines = good_file()
    change(lines)
    return check_lines(name, lines, expect)


def opposite_sense(lines):
    """The same skeleton with each node's turn written the natural way round.

    A .jms stores the inverse of a node's turn against its parent. Writing the
    turn itself is the export bug this checker was taught to catch: every bind
    frame comes out inverted, tool.exe compiles it without a word, and the game
    draws a heap while Blender still looks right.
    """
    for index in range(1, 1 + len(BIPED_NODES)):
        parts = lines[index].split("\t")
        for field in (3, 4, 5):
            parts[field] = "%.6f" % -float(parts[field])
        lines[index] = "\t".join(parts)
    return lines


def rolled_frames(lines):
    """Every node's frame rolled 90 degrees, translations rolled to match.

    This is the block that shipped before v114: it composes to Halo's own bone
    positions, so the bind is perfect and the .blend still looks right, but the
    frames the animation graph turns each joint by are 90 degrees out - which is
    what flung the arms out and drew the sleeves as stretched bands.
    """
    half = 0.7071067811865476

    def product(first, second):
        ax, ay, az, aw = first
        bx, by, bz, bw = second
        return (aw * bx + ax * bw + ay * bz - az * by,
                aw * by - ax * bz + ay * bw + az * bx,
                aw * bz + ax * by - ay * bx + az * bw,
                aw * bw - ax * bx - ay * by - az * bz)

    for index in range(1, 1 + len(BIPED_NODES)):
        parts = lines[index].split("\t")
        turn = tuple(float(parts[field]) for field in (3, 4, 5, 6))
        if index == 1:
            # the root's frame is the model's, so the roll is applied to it
            turn = product((0.0, 0.0, half, half), turn)
        else:
            x, y, z, w = turn
            turn = (-y, x, z, w)
            across, along = float(parts[7]), float(parts[8])
            parts[7], parts[8] = "%.6f" % -along, "%.6f" % across
        parts[3], parts[4], parts[5], parts[6] = ("%.6f" % v for v in turn)
        lines[index] = "\t".join(parts)
    return lines


def rolled_arms(lines):
    """Every first-person frame rolled 90 degrees, translations rolled to match.

    The arms block before v114: every joint in Halo's own place - so the
    position half of the check passes - and every frame 90 degrees out, which is
    what draws the hands twisted in first person.
    """
    count = int(lines[0].split("\t")[2])
    for index in range(1, 1 + count):
        parts = lines[index].split("\t")
        turn = tuple(float(parts[field]) for field in (3, 4, 5, 6))
        if index == 1:
            x, y, z, w = turn
            half = 0.7071067811865476
            turn = (w * 0.0 + 0.0 * w + 0.0 * z - half * y,
                    0.0 * 0.0 - 0.0 * z + 0.0 * w + half * x,
                    half * z + 0.0 * y - 0.0 * x + half * w,
                    half * w - 0.0 * x - 0.0 * y - half * z)
        else:
            x, y, z, w = turn
            turn = (-y, x, z, w)
            across, along = float(parts[7]), float(parts[8])
            parts[7], parts[8] = "%.6f" % -along, "%.6f" % across
        parts[3], parts[4], parts[5], parts[6] = ("%.6f" % v for v in turn)
        lines[index] = "\t".join(parts)
    return lines


def moved_node(lines):
    """One node slid ten units along x: well formed, but another skeleton."""
    parts = lines[13].split("\t")
    parts[7] = "%.6f" % (float(parts[7]) + 10.0)
    lines[13] = "\t".join(parts)
    return lines


def set_field(lines, index, field, value):
    parts = lines[index].split("\t")
    parts[field] = value
    lines[index] = "\t".join(parts)


def main():
    lines = good_file()
    handle, path = tempfile.mkstemp(suffix=".jms")
    with os.fdopen(handle, "w", encoding="ascii", newline="") as out:
        out.write("\n".join(lines) + "\n")
    errors, notes, stats = check_jms(path)
    os.remove(path)
    if errors:
        print("FAIL: a good file was rejected: %s" % errors[:2])
        return 1
    print("  accepted a good file: %d nodes, %d faces, %d verts"
          % (stats["nodes"], stats["faces"], stats["vertices"]))

    # Halo's biped has one acceptable node list: its own order. Tool's node list
    # checksum comes from it, and the retail animation graph addresses nodes by
    # index, so the same 19 names in another order are refused here rather than
    # failing in the engine with "the model ... and the animation graph ...
    # don't match".
    biped = biped_file()
    handle, path = tempfile.mkstemp(suffix=".jms")
    with os.fdopen(handle, "w", encoding="ascii", newline="") as out:
        out.write("\n".join(biped) + "\n")
    try:
        errors, _notes, biped_stats = check_jms(path)
    finally:
        os.remove(path)
    if errors:
        print("FAIL: a good biped .jms was rejected: %s" % errors[:2])
        return 1
    if not biped_stats.get("biped"):
        print("FAIL: the checker did not recognise Halo's biped node list")
        return 1
    print("  accepted a biped file: %d nodes in Halo's own order"
          % biped_stats["nodes"])

    swapped = biped_file()
    first, second = swapped[1].split("\t"), swapped[2].split("\t")
    first[0], second[0] = second[0], first[0]
    swapped[1], swapped[2] = "\t".join(first), "\t".join(second)
    broken = biped_file()
    set_field(broken, 2, 2, "-1")
    # Halo's own node list with another checksum is the failure this checker
    # exists to stop: tool.exe copies the header field into the gbxmodel, and a
    # model carrying BlueStreak's constant does not match the retail graph.
    wrong_checksum = biped_file()
    set_field(wrong_checksum, 0, 1, "3251")

    # Locate the blocks the way the checker does - by their shape - rather than
    # by counting lines, so a change to the fixture cannot silently point a
    # mutation at the wrong line.
    vertex = next(index for index, line in enumerate(lines)
                  if len(line.split("\t")) == 12)
    face = max(index for index, line in enumerate(lines) if line.count("\t") == 4)
    marker = next(index for index, line in enumerate(lines) if line.count("\t") == 10)

    if not accept_lines("Halo's own first-person arms", arms_file()):
        return 1

    results = [
        check_mutation("header node count wrong",
                       lambda work: set_field(work, 0, 2, "99"), "fields, expected 10"),
        check_mutation("first node index out of range",
                       lambda work: set_field(work, vertex, 0, "99"), "outside 0.."),
        check_mutation("second node index out of range",
                       lambda work: set_field(work, vertex, 7, "99"), "outside 0.."),
        check_mutation("both slots on one node",
                       lambda work: set_field(work, vertex, 7, "0"),
                       "both slots name node"),
        check_mutation("weight with no node",
                       lambda work: (set_field(work, vertex, 7, "-1"),
                                     set_field(work, vertex, 8, "0.400000")),
                       "on no node"),
        check_mutation("texture coordinate w not zero",
                       lambda work: set_field(work, vertex, 11, "0.500000"), "must be 0"),
        check_mutation("texture coordinate not a number",
                       lambda work: set_field(work, vertex, 9, "u"), "not all numbers"),
        check_mutation("rotation not unit length",
                       lambda work: set_field(work, 1, 3, "0.500000"), "rotation length"),
        check_mutation("child index out of range",
                       lambda work: set_field(work, 1, 1, "99"), "first child 99"),
        check_mutation("vertex count not three per face",
                       lambda work: set_field(work, face - 1, 0, "2"), "not three per face"),
        check_mutation("shader beyond the materials",
                       lambda work: set_field(work, face, 1, "7"), "shader 7"),
        check_mutation("region beyond the regions",
                       lambda work: set_field(work, face, 0, "3"), "region 3"),
        check_mutation("face vertex out of range",
                       lambda work: set_field(work, face, 4, "99"), "vertex 99"),
        check_mutation("face repeats a corner",
                       lambda work: set_field(work, face, 4, "0"), "repeat a vertex"),
        check_mutation("marker node out of range",
                       lambda work: set_field(work, marker, 2, "99"),
                       "outside 0.."),
        check_mutation("marker rotation not unit length",
                       lambda work: set_field(work, marker, 3, "0.500000"),
                       "rotation length"),
        check_mutation("file cut short",
                       lambda work: work.pop(), "file ends early"),
        check_lines("biped nodes not in Halo's order", swapped,
                    "not in its order"),
        check_lines("biped links not Halo's own", broken,
                    "from Halo's own biped"),
        check_lines("biped checksum is BlueStreak's constant", wrong_checksum,
                    "node list checksum is 3251"),
        check_lines("biped turns stored the natural way round",
                    opposite_sense(biped_file()), "describes another skeleton"),
        check_lines("biped node slid off its bone", moved_node(biped_file()),
                    "describes another skeleton"),
        check_lines("biped node frames rolled 90 degrees",
                    rolled_frames(biped_file()),
                    "degrees from where Halo's own biped has it"),
        check_lines("first-person frames rolled 90 degrees",
                    rolled_arms(arms_file()), "first-person node"),
    ]

    caught = sum(1 for result in results if result)
    if caught != len(results):
        print("FAIL: %d of %d faults caught" % (caught, len(results)))
        return 1
    print("PASS: the checker accepts a good .jms and catches all %d faults" % caught)
    return 0


if __name__ == "__main__":
    sys.exit(main())
