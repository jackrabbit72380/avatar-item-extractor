#!/usr/bin/env python3
"""Prove the one-click build asks for the body fit, and cannot lose it again.

The fit that carries a whole body's joints onto Halo's bones is the only thing
that brings its arms down onto a skeleton whose arms hang. It was added in
d9babf0 on 2026-11-23, and the next day dbcb26c made ``MyAvatar.glb`` beside
the .bat set ``--keep-shape`` as well - a flag that skips the fit - so every
double-click build after that shipped the armour in the avatar's T pose and the
game drew its sleeves flung out and torn. Nothing caught it, because the flag
was set in the batch half of the carrier and no test read that half.

So this reads the batch half of the shipped .bat and checks:

  * an avatar beside the .bat is passed as --port and nothing else;
  * keep_shape.txt still asks for the scale-only pass, on purpose;
  * the command line still forwards both, so neither can be dropped silently.

    python3 tools/test_flags.py

Exits 0 only when the carrier asks for the fit.
"""

import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(HERE)
BAT = max(glob.glob(os.path.join(ROOT_DIR, "Extract*v*.bat")))

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def batch_half(path):
    """The lines cmd.exe reads, which stop at the payload marker."""
    with open(path, encoding="utf-8", newline="") as handle:
        text = handle.read()
    marker = "###PAYLOAD###"
    at = text.rfind(marker)
    return text[:at] if at >= 0 else text


def main():
    head = batch_half(BAT)
    lines = [line.strip() for line in head.splitlines()]

    avatar_shape = [line for line in lines
                    if "MyAvatar.glb" in line and "SHAPE" in line
                    and "--keep-shape" in line]
    check(not avatar_shape,
          "the avatar file still turns the body fit off: %s"
          % (avatar_shape[0] if avatar_shape else ""))

    avatar_port = [line for line in lines
                   if "MyAvatar.glb" in line and "PORT" in line
                   and "--port" in line]
    check(avatar_port, "an avatar beside the .bat is no longer passed as --port")

    wanted = [line for line in lines
              if "keep_shape.txt" in line and "--keep-shape" in line]
    check(wanted, "keep_shape.txt no longer asks for the scale-only pass")

    run = [line for line in lines if "%SHAPE%" in line and "%PY%" in line]
    check(run, "the command line no longer forwards %SHAPE%")
    check(any("%PORT%" in line for line in run),
          "the command line no longer forwards %PORT%")

    print("carrier: %s" % os.path.basename(BAT))
    if failures:
        for problem in failures:
            print("  FAIL  %s" % problem)
        return 1
    print("  ok    an avatar is passed as --port, and the body fit is left on")
    print("  ok    keep_shape.txt alone asks for the scale-only pass")
    print("PASS: the one-click build carries the body onto Halo's bones")
    return 0


if __name__ == "__main__":
    sys.exit(main())
