#!/usr/bin/env python3
"""Prove each option writes what it promises, and that failures reach the .bat.

Three things can go wrong and all look identical to the player:

  * the pass crashes, and Blender reports 0 unless it is given
    --python-exit-code, so the failure never reaches the .bat;
  * the pass exits 0 and quietly writes nothing, which is what a missing
    .fbx/.glb/.blend actually is;
  * the option asked for the Halo rig but its two files are not there.

The stand-in below reproduces all three. It follows Blender's documented rule
for exceptions, honours --sets the way rig_items does, and can be told to write
the files a working pass would produce, or none of them.

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

# Halo's two rig files. The halo option cannot work without them.
RIGS = ("master chief skeleton.blend", "fp arms.blend")

# A stand-in for blender.exe. Modes:
#   crash   - the script raises; exit --python-exit-code if given, else 0
#   ok      - write exactly what the requested --sets produce, exit 0
#   silent  - exit 0 and write nothing
#   partial - write the NXE files only, whatever was asked for
FAKE_BLENDER = """#!/bin/sh
echo "$@" > "$FAKE_BLENDER_LOG"
pec=""; items=""; target=""; sets="halo nxe unrigged"; prev=""
for a in "$@"; do
  if [ "$prev" = "--python-exit-code" ]; then pec="$a"; fi
  if [ "$prev" = "--items" ]; then items="$a"; fi
  if [ "$prev" = "--out" ]; then target="$a"; fi
  if [ "$prev" = "--sets" ]; then sets=$(echo "$a" | tr ',' ' '); fi
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
if [ "$mode" = "partial" ]; then sets="nxe"; fi
for obj in "$items"/*.obj; do
  [ -e "$obj" ] || continue
  base=$(basename "$obj" .obj)
  for s in $sets; do
    case "$s" in
      halo) : > "$target/$base.blend"; : > "$target/$base.fbx"; : > "$target/$base.jms" ;;
      nxe) for k in fbx glb blend; do : > "$target/$base - NXE.$k"; done ;;
      unrigged) for k in blend fbx; do : > "$target/$base - unrigged.$k"; done ;;
    esac
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


def run_case(boot, tmp, mode="crash", rigs=False, profile="halo", item=True):
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

    # Halo: the item on the biped, as a .blend to open and export from.
    argv = check("halo: .blend, .fbx and .jms written", 0,
                 tempfile.mkdtemp(prefix="rig-halo-"), mode="ok", rigs=True)
    if "--python-exit-code" not in argv:
        failures.append("the blender command has no --python-exit-code, so a "
                        "crashed pass reports 0 and the failure is invisible")
    if "--sets halo" not in argv:
        failures.append("the halo option did not ask for the halo set: %r" % (argv,))

    # The halo option is the one that cannot fall back.
    check("halo: rig files absent", 6,
          tempfile.mkdtemp(prefix="rig-halo-miss-"), mode="ok")

    # A crash must reach the .bat as a failure.
    check("halo: crashed pass", 7,
          tempfile.mkdtemp(prefix="rig-crash-"), mode="crash", rigs=True)

    # The reported symptom: exits 0, writes nothing.
    check("nxe: exit 0 but wrote no files", 7,
          tempfile.mkdtemp(prefix="rig-silent-"), mode="silent", profile="nxe")

    # An option that asks for one thing and gets another is a failure.
    check("halo: only NXE files written", 7,
          tempfile.mkdtemp(prefix="rig-partial-"), mode="partial", rigs=True)

    # The two options that need nothing but Blender.
    check("nxe: .blend/.fbx/.glb", 0,
          tempfile.mkdtemp(prefix="rig-nxe-"), mode="ok", profile="nxe")
    check("unrigged: .blend and .fbx", 0,
          tempfile.mkdtemp(prefix="rig-unrigged-"), mode="ok", profile="unrigged")

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
    print("PASS: each option writes its own set, and failure is judged by files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
