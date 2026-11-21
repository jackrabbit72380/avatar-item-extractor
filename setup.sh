#!/bin/sh
# Vendors avatar_mesh.py and lzx.py into ./vendor
#   From a local UniKron checkout if one is next to this repo,
#   otherwise from GitHub raw.
#
#   ./setup.sh [path/to/UniKron/avatar/avatar_tools]
set -e
cd "$(dirname "$0")"

SRC="${1:-../UniKron/avatar/avatar_tools}"
mkdir -p vendor

if [ -f "$SRC/avatar_mesh.py" ]; then
    echo "Copying readers from $SRC"
    cp "$SRC/avatar_mesh.py" "$SRC/lzx.py" vendor/
else
    echo "No local UniKron checkout at $SRC - downloading from GitHub"
    BASE="https://raw.githubusercontent.com/jackrabbit72380/UniKron/main/avatar/avatar_tools"
    curl -fsSL "$BASE/avatar_mesh.py" -o vendor/avatar_mesh.py
    curl -fsSL "$BASE/lzx.py" -o vendor/lzx.py
fi

if [ ! -f vendor/avatar_mesh.py ]; then
    echo "Could not get avatar_mesh.py. Clone UniKron and run:" >&2
    echo "  ./setup.sh path/to/UniKron/avatar/avatar_tools" >&2
    exit 1
fi

echo "Done. avatar_mesh.py and lzx.py are in vendor/"
