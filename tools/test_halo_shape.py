#!/usr/bin/env python3
"""Check the finished model is still the item's own surface, not a distortion.

The measurement file next door counts whether the skinning tears. This asks a
different question - whether the thing that is being skinned is still the model
that was asked for - because a rig can be perfect on a mesh that has been
squashed into a different shape, and that still looks wrong in game.

    python3 tools/test_halo_shape.py "model superhigh.jms" "item.obj"

Three checks, each of which can fail:

    the model is the item's own surface   every triangle keeps its shape: its
                                          three side lengths, divided by the
                                          longest, must match some triangle of
                                          the item. Scaling - which fitting an
                                          armour to someone's proportions does -
                                          leaves that ratio alone; warping,
                                          shearing and collapsing do not.
    no new slivers                        the worst thin triangle is no worse
                                          than the item already had, so nothing
                                          has been dragged into a spike.
    every vertex rides one or two bones   Halo CE reads two influences per
                                          vertex; a third is silently dropped
                                          by tool.exe, and a missing one draws
                                          that vertex at the origin.

It is deliberately independent of Blender and of the build: it reads the two
files that exist afterwards, the .jms tool.exe compiles and the .obj that was
asked for.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_halo_skin as H


def read_obj(path):
    points, triangles = [], []
    for line in open(path, encoding="latin-1", errors="replace"):
        if line.startswith("v "):
            points.append(tuple(float(a) for a in line.split()[1:4]))
        elif line.startswith("f "):
            at = [int(a.split("/")[0]) - 1 for a in line.split()[1:4]]
            if len(at) == 3:
                triangles.append(tuple(at))
    return points, triangles


def shape(a, b, c):
    """Three sides over the longest: scale-free, so a fit may resize freely."""
    sides = sorted((math.dist(a, b), math.dist(b, c), math.dist(c, a)))
    longest = sides[2]
    if longest < 1e-9:
        return None
    return (sides[0] / longest, sides[1] / longest)


def slivers(points, triangles):
    worst = 0.0
    count = 0
    for triangle in triangles:
        a, b, c = points[triangle[0]], points[triangle[1]], points[triangle[2]]
        sides = sorted((math.dist(a, b), math.dist(b, c), math.dist(c, a)))
        if sides[2] < 1e-9:
            count += 1
            worst = float("inf")
            continue
        worst = max(worst, sides[2] / max(sides[0], 1e-9))
    return worst, count


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    model, item = sys.argv[1], sys.argv[2]
    names, _first, _sib, _turns, _spots, points, weights, triangles = H.parse(model)
    item_points, item_triangles = read_obj(item)
    print("shape: %s" % os.path.basename(model))

    known = {shape(item_points[t[0]], item_points[t[1]], item_points[t[2]])
             for t in item_triangles}
    known.discard(None)
    kept = 0
    same = 0
    for triangle in triangles:
        a, b, c = points[triangle[0]], points[triangle[1]], points[triangle[2]]
        here = shape(a, b, c)
        if here is None:
            continue
        kept += 1
        if any(abs(here[0] - other[0]) < 0.03 and abs(here[1] - other[1]) < 0.03
               for other in known):
            same += 1
    share = same / max(kept, 1)

    worst, flat = slivers(points, triangles)
    item_worst, item_flat = slivers(item_points, item_triangles)

    riding = set()
    spread = 0.0
    for ride in weights:
        riding.add(len(ride))
        spread = max(spread, abs(sum(ride.values()) - 1.0))

    ok = True
    if share < 0.97:
        print("  FAIL the model is the item's own surface - only %.1f%% of %d "
              "triangles keep the item's shape" % (share * 100.0, kept))
        ok = False
    else:
        print("  PASS the model is the item's own surface - %.1f%% of %d triangles "
              "keep the item's shape" % (share * 100.0, kept))
    if worst > max(item_worst * 1.3, item_worst + 2.0) or flat:
        print("  FAIL no new slivers - worst thin triangle x%.0f against the "
              "item's x%.0f, %d with no area" % (worst, item_worst, flat))
        ok = False
    else:
        print("  PASS no new slivers - worst thin triangle x%.0f against the "
              "item's x%.0f" % (worst, item_worst))
    if riding - {1, 2} or spread > 1e-3:
        print("  FAIL every vertex rides one or two bones - %s influences seen, "
              "weights off by %.4f" % (sorted(riding), spread))
        ok = False
    else:
        print("  PASS every vertex rides one or two bones - %s influences, "
              "weights add up to %.4f" % (sorted(riding), spread))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
