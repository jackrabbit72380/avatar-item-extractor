#!/usr/bin/env python3
"""Prove the rigging-failure path actually fires.

The fix has two halves: Blender has to report a crashed pass, and the .bat has
to react to it. Neither needs real Blender to test - only a stand-in that obeys
Blender's documented exit contract:

    --python-exit-code <code>
        Set the exit-code in [0..255] to exit if a Python exception is raised
        (only for scripts executed from the command line), zero disables.

That default is the whole trap. Without the flag Blender exits 0 on a crashed
script, so any check of its exit status is dead code. The stand-in below
reproduces that exactly, and records the argv the bootstrap built so the flag
itself can be asserted.

    python3 tools/test_rigging.py
"""

import importlib.util
import os
import shutil
import stat
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BAT = os.path.join(ROOT, "Extract-AvatarItem-v20.bat")
MODULES = os.path.join(os.path.dirname(ROOT), "recovered")

# A stand-in for blender.exe. It applies Blender's documented rule: a script
# that raises exits with --python-exit-code when given, and 0 when not.
FAKE_BLENDER = """#!/bin/sh
log="$FAKE_BLENDER_LOG"
echo "$@" > "$log"
pec=""
prev=""
for a in "$@"; do
  if [ "$prev" = "--python-exit-code" ]; then pec="$a"; fi
  prev="$a"
done
# The script the bootstrap asked Blender to run. Crashes unless told not to.
if [ "$FAKE_BLENDER_CRASH" = "0" ]; then
  "$FAKE_PYTHON" -c 'pass' >/dev/null 2>&1
else
  "$FAKE_PYTHON" -c 'raise RuntimeError("simulated rig failure")' >/dev/null 2>&1
fi
rc=$?
if [ "$rc" -ne 0 ] && [ -n "$pec" ]; then
  exit "$pec"
fi
exit 0
"""


def load_bootstrap():
    """The bootstrap is the plain Python between the two markers."""
    with open(BAT, encoding="utf-8") as handle:
        text = handle.read()
    start = text.rfind("###BOOTSTRAP###") + len("###BOOTSTRAP###")
    end = text.rfind("###PAYLOAD###")
    source = text[start:end].strip("\n") + "\n"
    work = tempfile.mkdtemp(prefix="boot-")
    path = os.path.join(work, "boot.py")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(source)
    spec = importlib.util.spec_from_file_location("boot", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def make_fake_blender(bin_dir):
    path = os.path.join(bin_dir, "blender")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(FAKE_BLENDER)
    os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
    return path


def run_case(boot, tmp, succeed):
    """Run one rig() pass against the stand-in and return (code, argv)."""
    bin_dir = os.path.join(tmp, "bin")
    os.makedirs(bin_dir, exist_ok=True)
    make_fake_blender(bin_dir)

    cache = os.path.join(tmp, "cache")
    os.makedirs(cache, exist_ok=True)
    shutil.copyfile(os.path.join(MODULES, "rig_items.py"),
                    os.path.join(cache, "rig_items.py"))

    bat_dir = os.path.join(tmp, "bat")
    os.makedirs(bat_dir, exist_ok=True)
    out = os.path.join(tmp, "out")
    os.makedirs(out, exist_ok=True)

    log = os.path.join(tmp, "argv.log")
    old = dict(os.environ)
    os.environ["PATH"] = bin_dir + os.pathsep + old.get("PATH", "")
    os.environ["FAKE_BLENDER_LOG"] = log
    os.environ["FAKE_PYTHON"] = sys.executable
    os.environ["FAKE_BLENDER_CRASH"] = "0" if succeed else "1"
    try:
        code = boot.rig(cache, bat_dir, out)
    finally:
        os.environ.clear()
        os.environ.update(old)

    argv = ""
    if os.path.exists(log):
        with open(log, encoding="utf-8") as handle:
            argv = handle.read()
    return code, argv, out


def main():
    boot = load_bootstrap()
    failures = []

    # The harness itself must behave like Blender, or the test proves nothing.
    tmp = tempfile.mkdtemp(prefix="rig-harness-")
    try:
        bin_dir = os.path.join(tmp, "bin")
        os.makedirs(bin_dir, exist_ok=True)
        fake = make_fake_blender(bin_dir)
        os.environ["FAKE_BLENDER_LOG"] = os.path.join(tmp, "argv.log")
        os.environ["FAKE_PYTHON"] = sys.executable
        bare = os.system("%s -b --factory-startup --python x.py" % fake)
        flagged = os.system("%s -b --python-exit-code 1 --python x.py" % fake)
        if bare != 0:
            failures.append("stand-in exits %d without the flag; Blender exits 0" % bare)
        if flagged != 256:  # os.system packs the code: 1 -> 256
            failures.append("stand-in exits %d with --python-exit-code 1; expected 1" % (flagged >> 8))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # A crashed pass must reach the .bat as a failure, not as success.
    tmp = tempfile.mkdtemp(prefix="rig-fail-")
    try:
        code, argv, out = run_case(boot, tmp, succeed=False)
        if "--python-exit-code" not in argv:
            failures.append(
                "the blender command has no --python-exit-code, so Blender "
                "reports 0 on a crashed pass and the failure is invisible")
        if code != 7:
            failures.append("a failed rigging pass returned %r, expected 7" % (code,))
        if not os.path.exists(os.path.join(out, "blender.log")):
            failures.append("no blender.log was written beside the items")
        print("  failed pass -> code %r, flag %s"
              % (code, "present" if "--python-exit-code" in argv else "MISSING"))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # A pass that worked must still report success.
    tmp = tempfile.mkdtemp(prefix="rig-ok-")
    try:
        code, argv, _ = run_case(boot, tmp, succeed=True)
        if code != 0:
            failures.append("a clean rigging pass returned %r, expected 0" % (code,))
        print("  clean pass  -> code %r" % (code,))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # No Blender at all keeps its own code, so the two are never confused.
    tmp = tempfile.mkdtemp(prefix="rig-none-")
    try:
        cache = os.path.join(tmp, "cache")
        os.makedirs(cache, exist_ok=True)
        bat_dir = os.path.join(tmp, "bat")
        os.makedirs(bat_dir, exist_ok=True)
        out = os.path.join(tmp, "out")
        os.makedirs(out, exist_ok=True)
        old = dict(os.environ)
        os.environ["PATH"] = os.path.join(tmp, "empty")
        try:
            code = boot.rig(cache, bat_dir, out)
        finally:
            os.environ.clear()
            os.environ.update(old)
        if code != 6:
            failures.append("no Blender returned %r, expected 6" % (code,))
        print("  no blender  -> code %r" % (code,))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failures:
        print("")
        for line in failures:
            print("FAIL: " + line)
        return 1
    print("")
    print("PASS: failed pass is 7, clean pass is 0, no Blender is 6")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
