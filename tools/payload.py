#!/usr/bin/env python3
"""Unpack and repack the code the .bat carries.

The .bat is deliberately one file: the player double-clicks it and nothing else
is needed. The tool itself travels inside it as base85 of zlib of a JSON map of
name to content, between the last ``###BOOTSTRAP###`` and the last
``###PAYLOAD###`` marker. cmd.exe never executes those lines because the batch
half ends with ``exit /b 0``.

Python modules are stored as text. Halo's two rig ``.blend`` files are binary,
so they are carried as base64 under ``rig/`` and written back byte for byte -
that way the tool needs nothing beside it, not even a ``rig`` folder.

Unpack before editing, repack after:

    python3 tools/payload.py unpack Extract-AvatarItem-v26.bat src/
    # edit src/extract_items.py ...
    python3 tools/payload.py pack Extract-AvatarItem-v26.bat src/ --rigs src/rig

``pack`` decodes its own output and refuses to write unless it matches the files
it was given, so a half-written rebuild cannot be shipped.
"""

import argparse
import base64
import json
import os
import re
import zlib

BOOTSTRAP = "###BOOTSTRAP###"
PAYLOAD = "###PAYLOAD###"
WRAP = 76
RIG_PREFIX = "rig/"


def _split(text):
    at = text.rfind(PAYLOAD)
    if at < 0:
        raise SystemExit("no %s marker: this is not a carrier .bat" % PAYLOAD)
    return text[:at + len(PAYLOAD)], text[at + len(PAYLOAD):]


def read_entries(text):
    """The name -> content map carried in a .bat.

    Text entries are strings; binary entries are {"b64": ...}.
    """
    _head, payload = _split(text)
    blob = "".join(payload.split())
    if not blob:
        raise SystemExit("the payload is empty")
    raw = zlib.decompress(base64.b85decode(blob.encode("ascii")))
    entries = json.loads(raw.decode("utf-8"))
    if not isinstance(entries, dict) or not entries:
        raise SystemExit("the payload is not a name -> content map")
    return entries


def encode_entries(entries):
    """The payload text for a map, wrapped the way the .bat carries it."""
    raw = json.dumps(entries, sort_keys=True).encode("utf-8")
    blob = base64.b85encode(zlib.compress(raw, 9)).decode("ascii")
    lines = [blob[at:at + WRAP] for at in range(0, len(blob), WRAP)]
    return "\n" + "\n".join(lines) + "\n"


def unpack(bat, out):
    text = open(bat, encoding="utf-8", newline="").read()
    entries = read_entries(text)
    for name, value in sorted(entries.items()):
        path = os.path.join(out, name.replace("/", os.sep))
        parent = os.path.dirname(path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        if isinstance(value, dict) and "b64" in value:
            data = base64.b64decode(value["b64"].encode("ascii"))
            with open(path, "wb") as handle:
                handle.write(data)
            print("  %-34s %7d bytes" % (name, len(data)))
        else:
            with open(path, "w", encoding="utf-8", newline="") as handle:
                handle.write(value)
            print("  %-34s %5d lines" % (name, value.count("\n")))
    print("%d entries written to %s" % (len(entries), out))


def collect(src):
    """Every .py and .bat under src, keyed by its path relative to src.

    The .bat is the script that drives tool.exe after extraction, and it has to
    travel with the code: rig_items.py looks for build-hek.bat beside itself and
    writes it beside the builds, so a payload carrying only .py files left every
    player to go and find one. It is stored as the text it is, exactly as read.
    """
    modules = {}
    for root, _dirs, files in os.walk(src):
        for name in sorted(files):
            if not name.endswith((".py", ".bat")):
                continue
            path = os.path.join(root, name)
            key = os.path.relpath(path, src).replace(os.sep, "/")
            with open(path, encoding="utf-8", newline="") as handle:
                text = handle.read()
            modules[key] = text if name.endswith(".bat") else text.replace("\r\n", "\n")
    if not modules:
        raise SystemExit("no .py files under %s" % src)
    return modules


def collect_rigs(folder):
    """Halo's rig files, carried byte for byte under rig/."""
    entries = {}
    if not folder:
        return entries
    for name in sorted(os.listdir(folder)):
        path = os.path.join(folder, name)
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as handle:
            data = handle.read()
        entries[RIG_PREFIX + name] = {"b64": base64.b64encode(data).decode("ascii")}
    return entries


STAMP = re.compile(r'^VERSION = "([^"]+)"$', re.M)


def shipped_version(entries):
    """The VERSION the packaged rig_items.py reports."""
    for name, value in entries.items():
        if name.endswith("rig_items.py") and isinstance(value, str):
            found = STAMP.search(value)
            if found:
                return found.group(1)
    raise SystemExit("no VERSION = \"...\" in the rig_items.py being packed")


def check_version(bat, head, version):
    """Refuse a build whose name and banner disagree with the code inside.

    A version that only changes in the code is no use: the download is called
    the same thing, so an old copy looks like the new one. The name, the banner
    and the boot file all have to carry it.
    """
    problem = None
    if version not in os.path.basename(bat):
        problem = ("the file is called %s, but it carries VERSION %s - rename "
                   "it, e.g. git mv to Extract-AvatarItem-%s.bat"
                   % (os.path.basename(bat), version, version))
    elif ("Version : %s" % version) not in head:
        problem = ("its banner does not say 'Version : %s'" % version)
    elif ("unpack_%s.py" % version) not in head:
        problem = ("its boot file is not unpack_%s.py" % version)
    if problem:
        raise SystemExit("refusing to pack: %s\nBump VERSION, BUILD and the "
                         "banner together, or the old download looks new."
                         % problem)


def pack(bat, src, rigs=None):
    text = open(bat, encoding="utf-8", newline="").read()
    head, _old_payload = _split(text)
    entries = collect(src)
    entries.update(collect_rigs(rigs))
    # A rebuild must never lose what the shipped file already carries. Editing
    # src/ supplies .py files only, so a forgotten --rigs dropped Halo's two
    # .blend rigs and still passed the check below, because that check only
    # compares the rebuild against what it was handed.
    carried = read_entries(text)
    lost = sorted(set(carried) - set(entries))
    if lost:
        raise SystemExit(
            "refusing to pack: %s already carries %d entr%s that this rebuild "
            "would lose (%s).\nPass the folder holding them, e.g. --rigs %s"
            % (bat, len(lost), "y" if len(lost) == 1 else "ies",
               ", ".join(lost[:6]), "src/rig"))
    check_version(bat, head, shipped_version(entries))
    rebuilt = head + encode_entries(entries)
    # Prove the new payload before writing: it must decode to the same content.
    if read_entries(rebuilt) != entries:
        raise SystemExit("repack check failed; %s was not written" % bat)
    with open(bat, "w", encoding="utf-8", newline="") as handle:
        handle.write(rebuilt)
    print("%d entries packed into %s (%d bytes)"
          % (len(entries), bat, len(rebuilt)))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("action", choices=("unpack", "pack"))
    parser.add_argument("bat", help="the carrier .bat")
    parser.add_argument("src", help="folder to write to, or read .py files from")
    parser.add_argument("--rigs",
                        help="folder holding the .blend rig files to carry "
                             "(required: a rebuild that dropped them is refused)")
    args = parser.parse_args(argv)
    if args.action == "unpack":
        unpack(args.bat, args.src)
    else:
        pack(args.bat, args.src, args.rigs)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
