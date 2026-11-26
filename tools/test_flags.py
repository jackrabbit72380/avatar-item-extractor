#!/usr/bin/env python3
"""Prove the one-click build is one click, and reads nothing but the avatar.

The fit that carries a whole body's joints onto Halo's bones is the only thing
that brings its arms down onto a skeleton whose arms hang. It was added in
d9babf0 on 2026-11-23, and the next day dbcb26c made ``MyAvatar.glb`` beside
the .bat set ``--keep-shape`` as well - a flag that skips the fit - so every
double-click build after that shipped the armour in the avatar's T pose and the
game drew its sleeves flung out and torn. Nothing caught it, because the flag
was set in the batch half of the carrier and no test read that half.

v145 took the modes out of text files; v146 took the pictures and the gamertag
fetch out as well, so the only thing the carrier looks for beside itself is
``MyAvatar.glb``.

So this reads the batch half of the shipped .bat and checks:

  * an avatar beside the .bat is passed as --port and --eyes-forward, and
    never as --keep-shape;
  * nothing else beside the .bat is read - no .txt, no mask PNG;
  * the shine is still asked for, so the suit reflects by default;
  * the command line still forwards %PORT%.

    python3 tools/test_flags.py

Exits 0 only when the carrier asks for the fit and nothing else.
"""

import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(HERE)
BAT = max(glob.glob(os.path.join(ROOT_DIR, "Extract*v*.bat")))

# Every file the batch half must NOT look for. MyAvatar.glb is the exception.
BANNED = ("tint_mask.png", "detail.png", "detail_mask.png", "shine_mask.png",
          "glow_mask.png", "gamertag.txt", "appid.txt", "tint_mode.txt",
          "detail_mode.txt", "shine_mode.txt", "keep_shape.txt", "t_pose.txt",
          "fit_limbs.txt", "eyes_forward.txt")

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

    files = [line for line in code
             if any(name in line.lower() for name in BANNED)]
    check(not files,
          "the batch half still looks for a file beside itself: %s"
          % (files[0] if files else ""))

    run = [line for line in code if "%PY%" in line and "%BOOT%" in line]
    check(run, "the extractor is no longer called from the batch half")
    check(run and "%PORT%" in run[0],
          "the command line no longer forwards %PORT%")
    check(run and "%SHAPE%" not in run[0],
          "the command line still forwards %SHAPE%")
    stand = [line for line in code if line.strip() == 'set "STAND=--stand"']
    check(stand, "the carrier no longer asks for the limb pose pass")
    check("%STAND%" in "\n".join(run),
          "the command line no longer forwards %STAND%")
    check(any("SHINE=--shine derived" in line for line in code),
          "the armour no longer reflects by default")
    check(not re.search(r"--(tint|detail|glow|fit-limbs|t-pose|keep-shape)\b",
                        "\n".join(run)),
          "the command line passes an option the carrier is not meant to set")

    print("carrier: %s" % os.path.basename(BAT))
    if failures:
        for problem in failures:
            print("  FAIL  %s" % problem)
        return 1
    print("  ok    an avatar is passed as --port, and the body fit is left on")
    print("  ok    nothing but MyAvatar.glb is read from beside the .bat")
    print("  ok    the shine is asked for, and no other option is set")
    print("PASS: the one-click build carries the body onto Halo's bones")
    return 0


if __name__ == "__main__":
    sys.exit(main())
