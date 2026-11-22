#!/usr/bin/env python3
"""Prove the rigging outcome is judged by files, not by Blender's exit status.

Two things can go wrong and both look identical to the player:

  * the pass crashes, and Blender reports 0 unless it is given
    --python-exit-code, so the failure never reaches the .bat;
  * the pass exits 0 and quietly writes nothing, which is what a missing
    .fbx/.glb/.blend actually is.

The stand-in below reproduces both. It follows Blender's documented rule for
exceptions, and it can be told to write the files a working pass would produce,
or to write none of them.

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

# Halo's two rig files. With these present the biped is expected as well.
RIGS = ("master chief skeleton.blend", "fp arms.blend")

# A stand-in for blender.exe. Modes:
#   crash  - the script raises; exit --python-exit-code if given, else 0
#   ok     - write the files a working pass produces, exit 0
#   silent - exit 0 and write nothing
FAKE_BLENDER = """#!/bin/sh
echo "$@" > "$FAKE_BLENDER_LOG"
pec=""; items=""; target=""; kinds="fbx glb blend"; biped=1; prev=""
for a in "$@"; do
  if [ "$prev" = "--python-exit-code" ]; then pec="$a"; fi
  if [ "$prev" = "--items" ]; then items="$a"; fi
  if [ "$prev" = "--out" ]; then target="$a"; fi
  if [ "$prev" = "--kinds" ]; then kinds=$(echo "$a" | tr ',' ' '); fi
  if [ "$a" = "--no-biped" ]; then biped=0; fi
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
# partial: write the NXE copies only, even when the biped was asked for.
if [ "$mode" = "partial" ]; then biped=0; fi
for obj in "$items"/*.obj; do
  [ -e "$obj" ] || continue
  base=$(basename "$obj" .obj)
  for k in $kinds; do
    : > "$target/$base - NXE.$k"
    if [ "$biped" = "1" ]; then
      : > "$target/$base - unrigged.$k"
    fi
  done
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


def run_case(boot, tmp, mode="crash", rigs=False, profile="all", item=True):
    """One rig() pass against the stand-in. Returns (code, argv, out)."""
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
        rig_dir = os.path.join(bat_dir, "rig")
        os.makedirs(rig_dir, exist_ok=True)
        for name in RIGS:
            open(os.path.join(rig_dir, name), "w").close()

    out = os.path.join(tmp, "out")
    os.makedirs(out, exist_ok=True)
    if item:
        # The extractor writes this before the rigging pass runs.
        open(os.path.join(out, "UNSC Marine Armor.obj"), "w").close()

    log = os.path.join(tmp, "argv.log")
    old = dict(os.environ)
    os.environ["PATH"] = bin_dir + os.pathsep + old.get("PATH", "")
    os.environ["FAKE_BLENDER_LOG"] = log
    os.environ["FAKE_PYTHON"] = sys.executable
    os.environ["FAKE_BLENDER_MODE"] = mode
    try:
        code = boot.rig(cache, bat_dir, out, profile=profile)
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
    results = []

    def check(label, expected, tmp, **kwargs):
        try:
            code, argv, out = run_case(boot, tmp, **kwargs)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        ok = code == expected
        results.append("  %-46s -> code %r %s"
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

    # A crash must reach the .bat as a failure.
    argv = check("crashed pass", 7,
                 tempfile.mkdtemp(prefix="rig-crash-"), mode="crash")
    if "--python-exit-code" not in argv:
        failures.append("the blender command has no --python-exit-code, so a "
                        "crashed pass reports 0 and the failure is invisible")

    # A pass that writes what it should is the only success.
    check("all: clean pass", 0,
          tempfile.mkdtemp(prefix="rig-ok-"), mode="ok")

    # The reported symptom: exits 0, writes nothing.
    check("exit 0 but wrote no files", 7,
          tempfile.mkdtemp(prefix="rig-silent-"), mode="silent")

    # With Halo's rigs present the biped copies are expected too.
    check("all + rigs: unrigged missing", 7,
          tempfile.mkdtemp(prefix="rig-biped-miss-"), mode="partial", rigs=True)
    check("all + rigs: unrigged written", 0,
          tempfile.mkdtemp(prefix="rig-biped-ok-"), mode="ok", rigs=True)

    # Each profile expects exactly the set it asks Blender for.
    check("profile blender: .blend only", 0,
          tempfile.mkdtemp(prefix="rig-p-blender-"), mode="ok", profile="blender")
    check("profile max: .fbx only", 0,
          tempfile.mkdtemp(prefix="rig-p-max-"), mode="ok", profile="max")
    check("profile nxe: no biped copies", 0,
          tempfile.mkdtemp(prefix="rig-p-nxe-"), mode="ok", profile="nxe", rigs=True)
    check("profile halo: biped .fbx", 0,
          tempfile.mkdtemp(prefix="rig-p-halo-"), mode="ok", profile="halo", rigs=True)
    check("profile halo: falls back without rigs", 0,
          tempfile.mkdtemp(prefix="rig-p-halo-miss-"), mode="ok", profile="halo")

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
    print("PASS: success is judged by the files written, not by the exit status")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
