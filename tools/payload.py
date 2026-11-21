#!/usr/bin/env python3
"""Unpack and repack the code the .bat carries.

The .bat is deliberately one file: the player double-clicks it and nothing else
is needed. The tool itself travels inside it as base85 of zlib of a JSON map of
module name to source, between the last ``###BOOTSTRAP###`` and the last
``###PAYLOAD###`` marker. cmd.exe never executes those lines because the batch
half ends with ``exit /b 0``.

Unpack before editing, repack after:

    python3 tools/payload.py unpack Extract-AvatarItem-v20.bat src/
    # edit src/extract_items.py ...
    python3 tools/payload.py pack Extract-AvatarItem-v20.bat src/

``pack`` decodes its own output and refuses to write unless it matches the
files it was given, so a half-written rebuild cannot be shipped.
"""

import argparse
import base64
import json
import os
import zlib

BOOTSTRAP = "###BOOTSTRAP###"
PAYLOAD = "###PAYLOAD###"
WRAP = 76


def _split(text):
    at = text.rfind(PAYLOAD)
    if at < 0:
        raise SystemExit("no %s marker: this is not a carrier .bat" % PAYLOAD)
    return text[:at + len(PAYLOAD)], text[at + len(PAYLOAD):]


def read_modules(text):
    """The module map carried in a .bat."""
    _head, payload = _split(text)
    blob = "".join(payload.split())
    if not blob:
        raise SystemExit("the payload is empty")
    raw = zlib.decompress(base64.b85decode(blob.encode("ascii")))
    modules = json.loads(raw.decode("utf-8"))
    if not isinstance(modules, dict) or not modules:
        raise SystemExit("the payload is not a module map")
    return modules


def encode_modules(modules):
    """The payload text for a module map, wrapped the way the .bat carries it."""
    raw = json.dumps(modules, sort_keys=True).encode("utf-8")
    blob = base64.b85encode(zlib.compress(raw, 9)).decode("ascii")
    lines = [blob[at:at + WRAP] for at in range(0, len(blob), WRAP)]
    return "\n" + "\n".join(lines) + "\n"


def unpack(bat, out):
    text = open(bat, encoding="utf-8", newline="").read()
    modules = read_modules(text)
    os.makedirs(out, exist_ok=True)
    for name, source in sorted(modules.items()):
        path = os.path.join(out, name)
        parent = os.path.dirname(path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="") as handle:
            handle.write(source)
        print("  %-28s %5d lines" % (name, source.count("\n")))
    print("%d modules written to %s" % (len(modules), out))


def collect(src):
    """Every .py under src, keyed by its path relative to src."""
    modules = {}
    for root, _dirs, files in os.walk(src):
        for name in sorted(files):
            if not name.endswith(".py"):
                continue
            path = os.path.join(root, name)
            key = os.path.relpath(path, src).replace(os.sep, "/")
            with open(path, encoding="utf-8", newline="") as handle:
                modules[key] = handle.read().replace("\r\n", "\n")
    if not modules:
        raise SystemExit("no .py files under %s" % src)
    return modules


def pack(bat, src):
    text = open(bat, encoding="utf-8", newline="").read()
    head, _payload = _split(text)
    modules = collect(src)
    rebuilt = head + encode_modules(modules)
    # Prove the new payload before writing: it must decode to the same files.
    if read_modules(rebuilt) != modules:
        raise SystemExit("repack check failed; %s was not written" % bat)
    with open(bat, "w", encoding="utf-8", newline="") as handle:
        handle.write(rebuilt)
    print("%d modules packed into %s (%d bytes)"
          % (len(modules), bat, len(rebuilt)))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("action", choices=("unpack", "pack"))
    parser.add_argument("bat", help="the carrier .bat")
    parser.add_argument("src", help="folder to write to, or read .py files from")
    args = parser.parse_args(argv)
    if args.action == "unpack":
        unpack(args.bat, args.src)
    else:
        pack(args.bat, args.src)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
