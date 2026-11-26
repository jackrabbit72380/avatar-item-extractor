#!/usr/bin/env python3
"""Skin a .jms the way Halo does, and measure what the game would draw.

Halo does not deform the way Blender does. `objects/models.c`:

    matrix4x3_multiply(&node_matrices[i], &node->runtime_default_inverse_matrix,
                       &relative_node_matrices[i]);

so each vertex is moved by `node_matrix(posed) x inverse(node_matrix(bind))`,
where the bind matrix is the model's OWN node block. That is why a bind that
is wrong shows in the game and never in Blender, and it is why this reads the
exported file instead of the .blend: it is the same numbers tool.exe compiles.

    python3 tools/test_halo_skin.py "path/to/model superhigh.jms"

Every vertex rides two nodes (`node0`, or `node0`+`node1` weighted), exactly as
a Halo CE gbxmodel does. The pose is applied as a rotation about a bone's head,
in its parent's frame, which is what an animation's node rotation is.
"""

# Checked before use, by two controls that are arithmetic, not judgement:
#   1. no pose at all - node x inverse(bind) is then the identity for every
#      node, so every edge must measure exactly 1.000. It does.
#   2. bind every vertex to one node, then every edge whose two ends ride that
#      same node must keep its length exactly, however the pose turns. It does,
#      over 19,132 edges. A control that tests 0 edges is a FAILURE, not a
#      pass - that is written into controls().
# The bug this caught: the posed frames were composed from each node's WORLD
# rotation instead of its own local turn, so the parent's rotation was applied
# twice and the deformer invented motion from nothing (x44.96 at zero pose).
# Every torn count printed before this fix was an artefact and is void.

import math
import sys

POSES = ((45.0, 45.0), (80.0, 60.0), (10.0, 10.0), (20.0, 20.0))


def parse(path):
    lines = [line.rstrip("\r\n") for line in open(path, encoding="latin-1")]
    head = lines[0].split("\t")
    if len(head) < 3:
        head = lines[0].split()
    count = int(head[2])
    first, sib, turns, spots, names = [], [], [], [], []
    for k in range(count):
        field = lines[1 + k].split("\t")
        if len(field) < 10:
            field = lines[1 + k].split()
        names.append(field[0])
        first.append(int(field[1]))
        sib.append(int(field[2]))
        turns.append(tuple(float(x) for x in field[3:7]))
        spots.append(tuple(float(x) for x in field[7:10]))
    at = 1 + count
    at += 1 + int(lines[at])          # materials
    at += 1 + int(lines[at])          # markers
    at += 1 + int(lines[at])          # regions
    verts = int(lines[at])
    at += 1
    points, weights = [], []
    for k in range(verts):
        field = lines[at + k].split("\t")
        if len(field) < 9:
            field = lines[at + k].split()
        points.append((float(field[1]), float(field[2]), float(field[3])))
        second = int(field[7])
        share = float(field[8])
        if second >= 0 and share > 0.0:
            weights.append({int(field[0]): 1.0 - share, second: share})
        else:
            weights.append({int(field[0]): 1.0})
    at += verts
    faces = int(lines[at])
    at += 1
    triangles = []
    for k in range(faces):
        field = lines[at + k].split("\t")
        if len(field) < 5:
            field = lines[at + k].split()
        triangles.append((int(field[2]), int(field[3]), int(field[4])))
    return names, first, sib, turns, spots, points, weights, triangles


def turn_matrix(turn):
    x, y, z, w = turn
    return ((1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)),
            (2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)),
            (2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)))


def transposed(m):
    return tuple(tuple(m[c][r] for c in range(3)) for r in range(3))


def product(a, b):
    return tuple(tuple(sum(a[r][k] * b[k][c] for k in range(3)) for c in range(3))
                 for r in range(3))


def carried(m, p):
    return tuple(sum(m[r][k] * p[k] for k in range(3)) for r in range(3))


def axis_rotation(axis, degrees):
    x, y, z = axis
    length = math.sqrt(x * x + y * y + z * z) or 1.0
    x, y, z = x / length, y / length, z / length
    angle = math.radians(degrees)
    c, s = math.cos(angle), math.sin(angle)
    t = 1.0 - c
    return ((t * x * x + c, t * x * y - s * z, t * x * z + s * y),
            (t * x * y + s * z, t * y * y + c, t * y * z - s * x),
            (t * x * z - s * y, t * y * z + s * x, t * z * z + c))


def levels(parent, count):
    """Every node's depth, so a parent is always composed before its child."""
    depth = {}

    def level(index):
        if index in depth:
            return depth[index]
        up = parent.get(index)
        depth[index] = 0 if up is None else level(up) + 1
        return depth[index]

    for index in range(count):
        level(index)
    return sorted(range(count), key=lambda index: depth[index])


def bind_worlds(first, sib, turns, spots):
    """Each node's bind frame, composed the way Halo's own files compose."""
    parent = {}
    for index in range(len(turns)):
        child = first[index]
        while 0 <= child < len(turns) and child not in parent:
            parent[child] = index
            child = sib[child]
    worlds = {}
    for index in levels(parent, len(turns)):
        local = transposed(turn_matrix(turns[index]))
        up = parent.get(index)
        if up is None:
            worlds[index] = (local, spots[index])
        else:
            above, where = worlds[up]
            moved = carried(above, spots[index])
            worlds[index] = (product(above, local),
                             tuple(where[a] + moved[a] for a in range(3)))
    return worlds, parent


def posed_worlds(worlds, parent, turns, spots, names, shoulder, elbow):
    """The same frames, with the arms turned, as an animation turns them."""
    bent = {}
    for index, name in enumerate(names):
        if name.endswith("upperarm"):
            bent[index] = shoulder
        elif name.endswith("forearm"):
            bent[index] = elbow
    posed = {}
    for index in levels(parent, len(names)):
        base_r, base_t = transposed(turn_matrix(turns[index])), spots[index]
        if index in bent:
            base_r = product(axis_rotation((1, 0, 0), bent[index]), base_r)
        up = parent.get(index)
        if up is None:
            posed[index] = (base_r, base_t)
        else:
            above, where = posed[up]
            moved = carried(above, base_t)
            posed[index] = (product(above, base_r),
                            tuple(where[a] + moved[a] for a in range(3)))
    return posed


def inverse(frame):
    rotation, spot = frame
    back = transposed(rotation)
    moved = carried(back, spot)
    return back, (-moved[0], -moved[1], -moved[2])


def measure(path, shoulder, elbow, limit=0.2):
    names, first, sib, turns, spots, points, weights, triangles = parse(path)
    worlds, parent = bind_worlds(first, sib, turns, spots)
    global first_of, sibling_of
    first_of, sibling_of = first, sib
    posed = posed_worlds(worlds, parent, turns, spots, names, shoulder, elbow)
    relative = [product(posed[i][0], inverse(worlds[i])[0]) for i in range(len(names))]
    shift = []
    for index in range(len(names)):
        posed_r, posed_t = posed[index]
        bind_r, bind_t = worlds[index]
        back = inverse((bind_r, bind_t))
        # relative = posed x inverse(bind), applied to the vertex
        shift.append((product(posed_r, back[0]),
                      tuple(posed_t[a] + carried(posed_r, back[1])[a]
                            for a in range(3))))
    moved = []
    for point, ride in zip(points, weights):
        total = (0.0, 0.0, 0.0)
        for node, share in ride.items():
            rotation, spot = shift[node]
            turned = carried(rotation, point)
            total = tuple(total[a] + share * (turned[a] + spot[a]) for a in range(3))
        moved.append(total)
    worst_stretch = 0.0
    worst_squash = 0.0
    torn = 0
    squashed = 0
    edges = set()
    for triangle in triangles:
        for a, b in ((triangle[0], triangle[1]), (triangle[1], triangle[2]),
                     (triangle[2], triangle[0])):
            edges.add((a, b) if a < b else (b, a))
    for a, b in edges:
        was = math.dist(points[a], points[b])
        if was < limit:
            continue
        now = math.dist(moved[a], moved[b])
        if now / was > worst_stretch:
            worst_stretch = now / was
        if now / was > 3.0:
            torn += 1
        if was / max(now, 1e-9) > worst_squash:
            worst_squash = was / max(now, 1e-9)
        if was / max(now, 1e-9) > 3.0:
            squashed += 1
    seam = {}
    for index, point in enumerate(points):
        seam.setdefault((round(point[0], 4), round(point[1], 4),
                         round(point[2], 4)), []).append(index)
    gaps = 0
    widest = 0.0
    for group in seam.values():
        if len(group) < 2:
            continue
        for x in range(len(group)):
            for y in range(x + 1, len(group)):
                apart = math.dist(moved[group[x]], moved[group[y]])
                widest = max(widest, apart)
                if apart > 1e-4:
                    gaps += 1
    return (worst_stretch, torn, worst_squash, squashed, len(edges),
            gaps, widest)


def rigid_control(path, shoulder=45.0, elbow=60.0, floor=0.2):
    """Bind each vertex to one node, then hold that node's edges to their length.

    A vertex riding one node at 100% is moved by a single rigid transform, so
    any edge whose two ends ride the same node keeps its length to the last bit.
    This checks the matrices, the order they are composed in, and the vertex
    transform together, on the model's own numbers. It reports how many edges
    it actually tested, because a control that tests nothing has proved nothing.
    """
    names, first, sib, turns, spots, points, weights, triangles = parse(path)
    worlds, parent = bind_worlds(first, sib, turns, spots)
    global first_of, sibling_of
    first_of, sibling_of = first, sib
    posed = posed_worlds(worlds, parent, turns, spots, names, shoulder, elbow)
    shift = []
    for index in range(len(names)):
        posed_r, posed_t = posed[index]
        back = inverse(worlds[index])
        shift.append((product(posed_r, back[0]),
                      tuple(posed_t[a] + carried(posed_r, back[1])[a] for a in range(3))))
    ride = [next(iter(entry)) for entry in weights]
    moved = []
    for point, node in zip(points, ride):
        rotation, spot = shift[node]
        turned = carried(rotation, point)
        moved.append(tuple(turned[a] + spot[a] for a in range(3)))
    worst = 0.0
    seen = 0
    for a, b, c in triangles:
        for x, y in ((a, b), (b, c), (c, a)):
            if ride[x] != ride[y]:
                continue
            was = math.dist(points[x], points[y])
            if was < floor:
                continue
            seen += 1
            worst = max(worst, math.dist(moved[x], moved[y]) / was)
    return worst, seen


def follow_control(path, shoulder=45.0, elbow=60.0):
    """Do the arm's vertices actually travel with the arm?

    A weight field smoothed until it is the same everywhere cannot tear - and
    cannot bend either. This checks the other half of the story: vertices whose
    dominant node is an arm bone must move a good part of the way that bone
    moves. A model whose every vertex moves alike fails here.
    """
    names, first, sib, turns, spots, points, weights, triangles = parse(path)
    worlds, parent = bind_worlds(first, sib, turns, spots)
    global first_of, sibling_of
    first_of, sibling_of = first, sib
    posed = posed_worlds(worlds, parent, turns, spots, names, shoulder, elbow)
    head = []
    for index in range(len(names)):
        rotation, spot = posed[index]
        moved = carried(rotation, spots[index])
        moved = tuple(moved[a] + spot[a] for a in range(3))
        head.append(math.dist(moved, worlds[index][1]))
    total = [0.0] * len(names)
    count = [0] * len(names)
    for vertex, ride in zip(points, weights):
        node = max(ride, key=ride.get)
        rotation, spot = posed[node]
        back = inverse(worlds[node])
        turned = carried(product(rotation, back[0]), vertex)
        moved = tuple(turned[a] + (spot[a] + carried(rotation, back[1])[a])
                      for a in range(3))
        total[node] += math.dist(moved, vertex)
        count[node] += 1
    worst = None
    tested = 0
    for index, name in enumerate(names):
        if not (name.endswith("upperarm") or name.endswith("forearm")):
            continue
        if count[index] < 20 or head[index] < 0.5:
            continue
        tested += 1
        ratio = (total[index] / count[index]) / head[index]
        worst = ratio if worst is None else min(worst, ratio)
    return worst, tested


def controls(path, tolerance=1e-3):
    """Both checks, each one answering pass or fail - never "no data, so fine"."""
    found = []
    still, torn, _sq, _cs, _seen, open_at_rest, widest = measure(path, 0.0, 0.0)
    found.append(("no pose moves nothing", abs(still - 1.0) <= tolerance and torn == 0,
                  "worst x%.7f, %d torn (tolerance %.0e for the file's float32 quaternions)"
                  % (still, torn, tolerance)))
    follow, tested = follow_control(path)
    if follow is None or tested == 0:
        found.append(("the arm's vertices follow the arm", False,
                      "0 bones tested - the control could not run"))
    else:
        found.append(("the arm's vertices follow the arm", follow >= 0.5,
                      "worst bone carries x%.2f of its own travel over %d bones "
                      "(must be at least x0.50)" % (follow, tested)))
    worst, seen = rigid_control(path)
    if seen == 0:
        found.append(("rigid edges keep their length", False,
                      "0 edges tested - the control could not run, so it proves nothing"))
    else:
        found.append(("rigid edges keep their length", worst <= 1.0 + tolerance,
                      "worst x%.7f over %d edges" % (worst, seen)))
    return found


if __name__ == "__main__":
    path = sys.argv[1]
    print("halo skinning: %s" % path.split("/")[-1])
    failed = 0
    for name, ok, detail in controls(path):
        print("  %s %s - %s" % ("PASS" if ok else "FAIL", name, detail))
        failed += 0 if ok else 1
    if failed:
        print("  the deformer is not trustworthy: %d control(s) failed" % failed)
        raise SystemExit(1)
    for shoulder, elbow in POSES:
        stretch, torn, squash, squashed, count, gaps, widest = measure(path, shoulder, elbow)
        print("  shoulder %3d elbow %3d -> stretch worst x%.2f, %d torn; "
              "squash worst x%.2f, %d collapsed  (of %d edges); "
              "%d seams open, widest %.4f"
              % (shoulder, elbow, stretch, torn, squash, squashed, count,
                 gaps, widest))
