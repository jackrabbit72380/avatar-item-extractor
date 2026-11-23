#!/usr/bin/env python3
"""Prove the rigging pass writes everything, and that failures reach the .bat.

Three things can go wrong and all look identical to the player:

  * the pass crashes, and Blender reports 0 unless it is given
    --python-exit-code, so the failure never reaches the .bat;
  * the pass exits 0 and quietly writes nothing, which is what a missing
    .fbx/.glb/.blend actually is;
  * the pass writes some of the sets and not the rest.

The stand-in below reproduces all three. It follows Blender's documented rule
for exceptions, writes the files a working pass produces (including Halo's rig
only when --rig was passed, as rig_items does), and can be told to write
nothing or only the NXE files.

    python3 tools/test_rigging.py
    RIG_MODULES=/tmp/unpacked python3 tools/test_rigging.py   # any build
"""

import importlib.util
import glob
import os
import shutil
import stat
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BAT = max(glob.glob(os.path.join(ROOT, "Extract-AvatarItem-v*.bat")))
MODULES = os.environ.get("RIG_MODULES") or os.path.join(ROOT, "src")

# Halo's two rig files. Without them there is no biped, so no halo set.
RIGS = ("master chief skeleton.blend", "fp arms.blend")

# A stand-in for blender.exe. Modes:
#   crash   - the script raises; exit --python-exit-code if given, else 0
#   ok      - write everything a working pass writes, exit 0
#   silent  - exit 0 and write nothing
#   partial - write the NXE files only
FAKE_BLENDER = """#!/bin/sh
echo "$@" > "$FAKE_BLENDER_LOG"
pec=""; items=""; target=""; prev=""; hasrig=0
for a in "$@"; do
  if [ "$prev" = "--python-exit-code" ]; then pec="$a"; fi
  if [ "$prev" = "--items" ]; then items="$a"; fi
  if [ "$prev" = "--out" ]; then target="$a"; fi
  if [ "$prev" = "--rig" ]; then hasrig=1; fi
  prev="$a"
done
mode="${FAKE_BLENDER_MODE:-crash}"
if [ "$mode" = "crash" ]; then
  "$FAKE_PYTHON" -c 'raise RuntimeError("simulated rig failure")' >/dev/null 2>&1
  rc=$?
  if [ "$rc" -ne 0 ] && [ -n "$pec" ]; then exit "$pec"; fi
  exit 0
fi
if [ "$mode" = "silent" ]; then exit 0; fi
mkdir -p "$target/extracted for blender users"
for obj in "$items/extracted for max users"/*.obj "$items"/*.obj; do
  [ -e "$obj" ] || continue
  base=$(basename "$obj" .obj)
  if [ "$mode" != "partial" ]; then
    if [ "$hasrig" = "1" ]; then
      : > "$target/extracted for blender users/$base - halo.blend"; : > "$target/extracted for blender users/$base - halo.fbx"
      : > "$target/extracted for blender users/$base - halo fp arms.blend"; : > "$target/extracted for blender users/$base - halo fp arms.fbx"
      mkdir -p "$target/extracted for hek users/pc/data/$base sp/models"
      : > "$target/extracted for hek users/pc/data/$base sp/models/$base.jms"
    fi
    for k in blend fbx; do : > "$target/extracted for blender users/$base - unrigged.$k"; done
  fi
  for k in fbx glb blend; do : > "$target/extracted for blender users/$base - NXE.$k"; done
done
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


def run_case(boot, tmp, mode="crash", rigs=True, item=True, rigs_in="rig"):
    """One rig() pass against the stand-in. Returns (code, argv)."""
    bin_dir = os.path.join(tmp, "bin")
    os.makedirs(bin_dir, exist_ok=True)
    if mode != "none":
        make_fake_blender(bin_dir)

    cache = os.path.join(tmp, "cache")
    os.makedirs(cache, exist_ok=True)
    shutil.copyfile(os.path.join(MODULES, "rig_items.py"),
                    os.path.join(cache, "rig_items.py"))

    bat_dir = os.path.join(tmp, "bat")
    os.makedirs(bat_dir, exist_ok=True)
    if rigs:
        # rig\ beside the .bat, beside the .bat itself, or the cache folder the
        # .bat unpacks its own copy into: all three must work.
        if rigs_in == "cache":
            rig_dir = os.path.join(cache, "rig")
        elif rigs_in == "beside":
            rig_dir = bat_dir
        else:
            rig_dir = os.path.join(bat_dir, "rig")
        os.makedirs(rig_dir, exist_ok=True)
        for name in RIGS:
            open(os.path.join(rig_dir, name), "w").close()

    out = os.path.join(tmp, "out")
    os.makedirs(out, exist_ok=True)
    if item:
        # The extractor writes this before the rigging pass runs.
        os.makedirs(os.path.join(out, "extracted for max users"), exist_ok=True)
        open(os.path.join(out, "extracted for max users", "UNSC Marine Armor.obj"), "w").close()

    log = os.path.join(tmp, "argv.log")
    old = dict(os.environ)
    os.environ["PATH"] = bin_dir + os.pathsep + old.get("PATH", "")
    os.environ["FAKE_BLENDER_LOG"] = log
    os.environ["FAKE_PYTHON"] = sys.executable
    os.environ["FAKE_BLENDER_MODE"] = mode
    try:
        code = boot.rig(cache, bat_dir, out)
    finally:
        os.environ.clear()
        os.environ.update(old)

    argv = ""
    if os.path.exists(log):
        with open(log, encoding="utf-8") as handle:
            argv = handle.read()
    return code, argv


def main():
    boot = load_bootstrap()
    failures = []
    results = []

    def check(label, expected, tmp, **kwargs):
        try:
            code, argv = run_case(boot, tmp, **kwargs)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        ok = code == expected
        results.append("  %-44s -> code %r %s"
                       % (label, code, "ok" if ok else "EXPECTED %r" % (expected,)))
        if not ok:
            failures.append("%s returned %r, expected %r" % (label, code, expected))
        return argv

    # The harness must behave like Blender, or nothing below means anything.
    tmp = tempfile.mkdtemp(prefix="rig-harness-")
    try:
        bin_dir = os.path.join(tmp, "bin")
        os.makedirs(bin_dir, exist_ok=True)
        fake = make_fake_blender(bin_dir)
        os.environ["FAKE_BLENDER_LOG"] = os.path.join(tmp, "argv.log")
        os.environ["FAKE_PYTHON"] = sys.executable
        os.environ["FAKE_BLENDER_MODE"] = "crash"
        bare = os.system("%s -b --factory-startup --python x.py" % fake)
        flagged = os.system("%s -b --python-exit-code 1 --python x.py" % fake)
        if bare != 0:
            failures.append("stand-in exits %d without the flag; Blender exits 0" % (bare >> 8))
        if flagged != 256:
            failures.append("stand-in exits %d with --python-exit-code 1; expected 1"
                            % (flagged >> 8))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # Everything, with Halo's rig: all three sets are expected.
    argv = check("everything, rig files present", 0,
                 tempfile.mkdtemp(prefix="rig-all-"), mode="ok")
    if "--python-exit-code" not in argv:
        failures.append("the blender command has no --python-exit-code, so a "
                        "crashed pass reports 0 and the failure is invisible")
    if "--rig" not in argv:
        failures.append("the rig files were found but never passed to Blender")

    # The same files dropped beside the .bat, instead of in rig\, must be found.
    argv = check("rig files beside the .bat", 0,
                 tempfile.mkdtemp(prefix="rig-beside-"), mode="ok", rigs_in="beside")
    if "--rig" not in argv:
        failures.append("rig files beside the .bat were not found")

    # And the copy the .bat unpacks for itself must be found too.
    argv = check("rig files in the cache", 0,
                 tempfile.mkdtemp(prefix="rig-cache-"), mode="ok", rigs_in="cache")
    if "--rig" not in argv:
        failures.append("the rig files the .bat unpacks into its cache were not found")

    # Without the rig files the biped cannot be made; the other two sets still
    # are, and that is a success, not a failure.
    check("rig files absent: NXE and unrigged", 0,
          tempfile.mkdtemp(prefix="rig-norig-"), mode="ok", rigs=False)

    # A crash must reach the .bat as a failure.
    check("crashed pass", 7,
          tempfile.mkdtemp(prefix="rig-crash-"), mode="crash")

    # The reported symptom: exits 0, writes nothing.
    check("exit 0 but wrote no files", 7,
          tempfile.mkdtemp(prefix="rig-silent-"), mode="silent")

    # Some of the sets written and not the rest is still a failure.
    check("only the NXE files written", 7,
          tempfile.mkdtemp(prefix="rig-partial-"), mode="partial")

    # No Blender at all keeps its own code, so it is never confused with this.
    check("no blender", 6,
          tempfile.mkdtemp(prefix="rig-none-"), mode="none")

    for line in results:
        print(line)
    if failures:
        print("")
        for line in failures:
            print("FAIL: " + line)
        return 1
    print("")
    print("PASS: every set is written, and failure is judged by the files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
