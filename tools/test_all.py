#!/usr/bin/env python3
"""Run every test against the build the .bat actually ships.

Each test can be run on its own, but the ones that read modules need to be
pointed at an unpacked payload, and pointing them at a copy that has drifted
from the .bat tests nothing. This unpacks the shipped payload once into a
temporary folder, hands every test that folder, and runs them in order.

No Blender, no rig folder, no build beside the repository: only Python 3.8+.

    python3 tools/test_all.py

Exits 0 only when every test passes, and names the ones that did not.
"""

import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BAT = os.path.join(ROOT, "Extract-AvatarItem-v20.bat")


def shipped(work):
    """Unpack the payload the .bat carries, so the tests follow the artifact."""
    sys.path.insert(0, HERE)
    import payload

    os.makedirs(work, exist_ok=True)
    with open(BAT, encoding="utf-8", newline="") as handle:
        entries = payload.read_entries(handle.read())
    for name, value in entries.items():
        path = os.path.join(work, name.replace("/", os.sep))
        parent = os.path.dirname(path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        if isinstance(value, dict) and "b64" in value:
            import base64
            with open(path, "wb") as handle:
                handle.write(base64.b64decode(value["b64"].encode("ascii")))
        else:
            with open(path, "w", encoding="utf-8", newline="") as handle:
                handle.write(value)
    return len(entries)


def main():
    tests = sorted(name for name in os.listdir(HERE)
                   if name.startswith("test_") and name.endswith(".py")
                   and name != "test_all.py")
    if not tests:
        print("FAIL: no tests found beside %s" % os.path.basename(__file__))
        return 1

    work = tempfile.mkdtemp(prefix="avatar-tests-")
    try:
        count = shipped(work)
        print("Tests run against the %d entries the .bat ships (%d bytes)\n"
              % (count, os.path.getsize(BAT)))

        env = dict(os.environ)
        env["RIG_MODULES"] = work
        env["MESH_MODULES"] = work
        failed = []
        for name in tests:
            print("=" * 70)
            print(name)
            print("=" * 70)
            code = subprocess.call([sys.executable, os.path.join(HERE, name)],
                                   cwd=ROOT, env=env)
            if code != 0:
                failed.append((name, code))
            print("")

        print("=" * 70)
        if failed:
            print("FAILED: %d of %d" % (len(failed), len(tests)))
            for name, code in failed:
                print("  %s (exit %d)" % (name, code))
            return 1
        print("PASSED: %d of %d" % (len(tests), len(tests)))
        print("Not covered here: the Blender passes themselves. The rigging tests")
        print("use a stand-in blender.exe, so a real Blender run is still yours to do.")
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
