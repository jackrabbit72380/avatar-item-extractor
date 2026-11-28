#!/usr/bin/env python3
"""The white face must be caught before a model is written, not in game.

The face reaches the game white when its material is laid out for the avatar's
face sheet and that sheet was never written: every face then lands on the item's
own blank padding. A .jms that names such a material is a model tool.exe will
happily compile and bake - the shader exists, its base map is blank, and the
surface draws white for good.

So the run refuses to write the model. These are the cases that decide it.

    python3 tools/test_shader_guard.py
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODULES = os.environ.get("RIG_MODULES") or os.path.join(
    os.path.dirname(HERE), "src")
sys.path.insert(0, MODULES)

import shader_guard  # noqa: E402


def main():
    painted = 1106
    cases = (
        ("a face material with no image at all",
         shader_guard.gap("unsc marine armor face", False, 0), "no bitmap bound"),
        ("an image with no pixels",
         shader_guard.gap("unsc marine armor face", True, 0), "no pixels"),
        ("the white face: a face material on one flat colour",
         shader_guard.gap("unsc marine armor face", True, 1), "one flat colour"),
        ("a face material whose sheet is painted",
         shader_guard.gap("unsc marine armor face", True, painted), None),
        ("a body material on one flat colour - the item's own paint",
         shader_guard.gap("unsc marine armor body", True, 1), None),
        ("the armour's own map",
         shader_guard.gap("unsc marine armor base map", True, painted), None),
    )
    bad = []
    for label, got, want in cases:
        if want is None:
            if got is not None:
                bad.append((label, got, "no complaint"))
        elif got is None or want not in got:
            bad.append((label, got, want))
    if bad:
        for label, got, want in bad:
            print("FAIL: %s\n      said %r\n      wanted %r"
                  % (label, got, want))
        return 1
    line = shader_guard.refusal([("unsc marine armor face",
                                  "one flat colour under every face")],
                                "UNSC Marine Armor")
    if "unsc marine armor face" not in line or "no .jms is written" not in line:
        print("FAIL: the refusal does not name the material and say the model was "
              "not written:\n      %r" % line)
        return 1
    print("PASS: %d case(s) - a model that names a shader its bitmap cannot draw "
          "is refused, and a flat body sheet is left alone" % len(cases))
    return 0


if __name__ == "__main__":
    sys.exit(main())
