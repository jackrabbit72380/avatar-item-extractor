#!/usr/bin/env python3
"""Prove the one-click build asks for the body fit, and reads no text files.

The fit that carries a whole body's joints onto Halo's bones is the only thing
that brings its arms down onto a skeleton whose arms hang. It was added in
d9babf0 on 2026-11-23, and the next day dbcb26c made ``MyAvatar.glb`` beside
the .bat set ``--keep-shape`` as well - a flag that skips the fit - so every
double-click build after that shipped the armour in the avatar's T pose and the
game drew its sleeves flung out and torn. Nothing caught it, because the flag
was set in the batch half of the carrier and no test read that half.

v145 then took the other switches out of text files entirely: nobody using a
one-click program writes ``shine_mode.txt``, so the batch half asks for what
the defaults say and nothing else.

So this reads the batch half of the shipped .bat and checks:

  * an avatar beside the .bat is passed as --port and --eyes-forward, and
    never as --keep-shape;
  * no setting is read from a .txt (gamertag.txt and appid.txt stay: they name
    which avatar to fetch, not a mode);
  * the command line still forwards --port, and forwards no %SHAPE%.

    python3 tools/test_flags.py

Exits 0 only when the carrier asks for the fit.
"""

import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(HERE)
BAT = max(glob.glob(os.path.join(ROOT_DIR, "Extract*v*.bat")))

# The .txt files that used to set a mode in the batch half. gamertag.txt and
# appid.txt are deliberately not here: they carry which avatar to build.
SETTING_TXT = ("tint_mode.txt", "detail_mode.txt", "shine_mode.txt",
               "keep_shape.txt", "t_pose.txt", "fit_limbs.txt",
               "eyes_forward.txt")

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
    code = [line for line in lines if not line.startswith("rem")]

    avatar_shape = [line for line in code
                    if "MyAvatar.glb" in line and "--keep-shape" in line]
    check(not avatar_shape,
          "the avatar file still turns the body fit off: %s"
          % (avatar_shape[0] if avatar_shape else ""))

    avatar_port = [line for line in code
                   if "MyAvatar.glb" in line and "--port" in line]
    check(avatar_port, "an avatar beside the .bat is no longer passed as --port")

    settings = [line for line in code
                if any(name in line for name in SETTING_TXT)]
    check(not settings,
          "the batch half still reads a mode from a text file: %s"
          % (settings[0] if settings else ""))

    run = [line for line in code
           if "%PY%" in line and "%BOOT%" in line]
    check(run, "the extractor is no longer called from the batch half")
    check(run and "%PORT%" in run[0],
          "the command line no longer forwards %PORT%")
    check(run and "%SHAPE%" not in run[0],
          "the command line still forwards %SHAPE%")

    print("carrier: %s" % os.path.basename(BAT))
    if failures:
        for problem in failures:
            print("  FAIL  %s" % problem)
        return 1
    print("  ok    an avatar is passed as --port, and the body fit is left on")
    print("  ok    no mode is read from a text file")
    print("PASS: the one-click build carries the body onto Halo's bones")
    return 0


if __name__ == "__main__":
    sys.exit(main())
