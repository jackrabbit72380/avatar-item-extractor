"""The transform Halo applies to a vertex, from a model's own node block.

``objects/models.c`` moves every vertex by

    node_matrix(posed) x inverse(node_matrix(bind))

where the bind matrix is the model's OWN node block - the one a .jms stores, not
Blender's bone matrices. That is why a bind that is wrong shows in the game and
never in the .blend: Blender deforms through the armature and never reads this
block, while tool.exe bakes it and the engine turns the mesh with it.

Everything here works on the numbers a .jms writes - a node's turn, its spot in
its parent's frame, and its first-child / next-sibling links - so the build, the
checker and the game are looking at the same transform rather than three
near-misses. No Blender types are used, so this runs under any Python 3.

A node's stored turn is the inverse of its own rotation, so the bind frame is
composed from the transpose of its turn matrix:

    bind_world = parent_world . transpose(turn) , with spot carried by parent

An animation's rotation is applied in the NODE's own frame, pre-multiplied, and
only the bones named here are turned: the shoulder bends an upperarm, the elbow
a forearm, and nothing else moves.
"""

import math


def turn_matrix(turn):
    """The rotation a stored turn stands for."""
    x, y, z, w = turn
    return ((1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)),
            (2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)),
            (2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)))


def transposed(rotation):
    return tuple(tuple(rotation[c][r] for c in range(3)) for r in range(3))


def product(first, second):
    return tuple(tuple(sum(first[r][k] * second[k][c] for k in range(3))
                       for c in range(3)) for r in range(3))


def carried(rotation, point):
    return tuple(sum(rotation[r][k] * point[k] for k in range(3)) for r in range(3))


def axis_rotation(axis, degrees):
    """A turn of `degrees` about `axis`, which is a node's own frame."""
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


def bind_worlds(first, sibling, turns, spots):
    """Each node's bind frame, composed the way Halo's own files compose."""
    parent = {}
    for index in range(len(turns)):
        child = first[index]
        while 0 <= child < len(turns) and child not in parent:
            parent[child] = index
            child = sibling[child]
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


def shifts(first, sibling, turns, spots, names, shoulder, elbow):
    """posed x inverse(bind) per node: what moves a vertex riding that node.

    Returned as (rotation, translation) pairs, indexed like the node list.
    """
    worlds, parent = bind_worlds(first, sibling, turns, spots)
    posed = posed_worlds(worlds, parent, turns, spots, names, shoulder, elbow)
    out = {}
    for index in range(len(turns)):
        posed_r, posed_t = posed[index]
        back = inverse(worlds[index])
        out[index] = (product(posed_r, back[0]),
                      tuple(posed_t[a] + carried(posed_r, back[1])[a]
                            for a in range(3)))
    return out
