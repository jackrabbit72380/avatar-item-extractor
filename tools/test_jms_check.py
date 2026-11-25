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

from jms_check import check_jms  # noqa: E402

NODES = 3


def good_file():
    """A minimal well-formed .jms: three nodes, one material, one triangle."""
    lines = ["8200\t3251\t%d" % NODES]
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


def check_mutation(name, change, expect):
    lines = good_file()
    change(lines)
    handle, path = tempfile.mkstemp(suffix=".jms")
    with os.fdopen(handle, "w", encoding="ascii", newline="") as out:
        out.write("\n".join(lines) + "\n")
    try:
        errors, _notes, _stats = check_jms(path)
    finally:
        os.remove(path)
    hit = [problem for problem in errors if expect in problem]
    if hit:
        print("  caught  %-38s %s" % (name, hit[0][:60]))
        return True
    print("  MISSED  %-38s expected %r, got %s"
          % (name, expect, errors[:2] or "no errors at all"))
    return False


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

    # Locate the blocks the way the checker does - by their shape - rather than
    # by counting lines, so a change to the fixture cannot silently point a
    # mutation at the wrong line.
    vertex = next(index for index, line in enumerate(lines)
                  if len(line.split("\t")) == 12)
    face = max(index for index, line in enumerate(lines) if line.count("\t") == 4)
    marker = next(index for index, line in enumerate(lines) if line.count("\t") == 10)

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
    ]

    caught = sum(1 for result in results if result)
    if caught != len(results):
        print("FAIL: %d of %d faults caught" % (caught, len(results)))
        return 1
    print("PASS: the checker accepts a good .jms and catches all %d faults" % caught)
    return 0


if __name__ == "__main__":
    sys.exit(main())
