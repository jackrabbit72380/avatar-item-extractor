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
  * the command line still forwards %PORT%;
  * the carrier's own command line gets past the extractor's parser. The batch
    half sets the RIGGING pass's flags in variables and forwards them on the
    same line as the extractor's; v146-v152 forwarded --stand with them, and
    argparse answers an unknown argument with exit 2, so every double-click
    stopped before one item was extracted. The check below runs the carrier's
    real command line, which is the only thing that would have caught it.

    python3 tools/test_flags.py

Exits 0 only when the carrier asks for the fit and nothing else.
"""

import glob
import os
import re
import subprocess
import sys
import tempfile

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


def bootstrap_half(path):
    """The Python the batch half writes out, exactly as it stands in the file."""
    with open(path, encoding="utf-8", newline="") as handle:
        text = handle.read()
    start = text.rfind("###BOOTSTRAP###") + len("###BOOTSTRAP###")
    end = text.rfind("###PAYLOAD###")
    return text[start:end].strip("\r\n")


def runs_past_the_parser(boot):
    """Run the carrier's own command line and see what the extractor says.

    Returns (returncode, output). Code 2 is argparse refusing an argument: the
    extractor never starts. Anything else means the line was understood - 4 is
    what it answers when the folder holds no items, which is this repository.
    """
    work = tempfile.mkdtemp(prefix="carrier-")
    path = os.path.join(work, "boot.py")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(boot + "\n")
    out = os.path.join(work, "extracted")
    os.makedirs(out, exist_ok=True)
    done = subprocess.run(
        [sys.executable, path, BAT, os.path.join(work, "cache"),
         "--obj", "--out", out, "--stand", "--shine", "derived"],
        capture_output=True, text=True)
    return done.returncode, done.stdout + done.stderr


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
    check(not stand,
          "the carrier sets STAND=--stand again, the pose pass that turns the "
          "suit 45 degrees off the head it was authored with")
    check("%STAND%" not in "\n".join(run),
          "the one-click command line asks for the pose pass again")
    check(any("SHINE=--shine derived" in line for line in code),
          "the armour no longer reflects by default")
    check(not re.search(r"--(tint|detail|glow|fit-limbs|t-pose|keep-shape)\b",
                        "\n".join(run)),
          "the command line passes an option the carrier is not meant to set")

    # The rigging half's flags travel on the extractor's command line, so the
    # bootstrap has to take them back out before the extractor parses it.
    boot = bootstrap_half(BAT)
    for word in ("--stand",):
        check(re.search(r"if word not in \([^)]*%s" % re.escape(word), boot),
              "the bootstrap no longer takes %s out of the extractor's"
              " arguments" % word)
    check('["--stand"]' in boot,
          "the bootstrap no longer hands --stand to the rigging pass")
    code_ran, output = runs_past_the_parser(boot)
    check("unrecognized arguments" not in output and code_ran != 2,
          "the one-click command line is refused by the extractor (code %r): %s"
          % (code_ran, output.strip().splitlines()[-1] if output.strip() else ""))

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
