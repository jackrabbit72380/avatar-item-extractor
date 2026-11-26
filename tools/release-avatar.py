"""Bump the avatar carrier to a new version and rebuild it in place.

Usage: python3 tools/release-avatar.py v119 "<build note>" <banner-file>

The banner is the rem block that goes under the version line; it is kept in a
file because it is prose, not something to be quoted through a shell.
"""
import os
import re
import sys

version, note, banner = sys.argv[1], sys.argv[2], sys.argv[3]
bats = [name for name in os.listdir(".") if name.startswith("Extract UNSC Marine Armor Avatar-v")]

source = open("src/rig_items.py", encoding="utf-8", newline="").read()
source = re.sub(r'VERSION = "v\d+"', 'VERSION = "%s"' % version, source, count=1)
source = re.sub(r'BUILD = "[^"]*"', 'BUILD = "%s"' % note, source, count=1)
open("src/rig_items.py", "w", encoding="utf-8", newline="").write(source)

for name in bats:
    old = re.search(r"Avatar-(v\d+)\.bat$", name).group(1)
    text = open(name, encoding="utf-8", newline="").read()
    text = text.replace("Avatar %s" % old, "Avatar %s" % version)
    text = text.replace("unpack_%s.py" % old, "unpack_%s.py" % version)
    text = text.replace("rem  Version : %s   build" % old,
                        open(banner, encoding="utf-8").read()
                        + "rem  Version : %s   build" % old, 1)
    target = name.replace(old, version)
    open(target, "w", encoding="utf-8", newline="").write(text)
    if target != name:
        os.remove(name)
    print("carrier: %s (%d bytes)" % (target, os.path.getsize(target)))

readme = open("README.md", encoding="utf-8", newline="").read()
readme = re.sub(r"Avatar-v\d+\.bat", "Avatar-%s.bat" % version, readme)
open("README.md", "w", encoding="utf-8", newline="").write(readme)
