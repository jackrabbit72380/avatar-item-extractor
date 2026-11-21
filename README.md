# Extract Avatar Item - one file

**Download `Extract-AvatarItem-v20.bat` and double-click it.** That is the whole
tool.

One file. It carries the extractor inside itself, unpacks it to
`%LOCALAPPDATA%\AvatarItemExtractor` on first run, downloads the two readers it
needs once, then finds your items and extracts them.

- No setup step, no folder picker, no drag-and-drop, nothing to install.
- It searches a fixed list: its own folder and the parent,
  `..\UniKron\src_archive`, `Downloads`, `Desktop`, `Documents`,
  `OneDrive\Downloads`, `OneDrive\Desktop` - three folders deep.
- It takes every source it finds and merges them into one catalogue.
- It writes `extracted\` next to the `.bat` and opens that folder.
- Nothing found is reported as such, with the list of folders searched.

Needs Python 3 (python.org; tick "Add python.exe to PATH" during setup).

## What it reads

Retail Xbox 360 avatar items: the `YTGR`/`STRB` assets the LIVE avatar service
served and the `Clean Slate NXE` dump ships. Block 3 of the `STRB` is the model
and in retail assets it is LZX-framed inside the container, so it is
decompressed before parsing: vertices, `u16` triangles, half-float UVs, material
records, per-vertex joints and weights. Items are y-up already, so `.obj` export
needs no rotation.

## What it writes

| output | contents |
| --- | --- |
| `extracted/catalogue.json` | every item: name, category and body masks, block table, geometry, source folder |
| `extracted/items/<id>.obj` | the model, ready for Blender |
| `extracted/icons/<id>.png` | the item icon, copied when present |

Exit status: `0` something parsed, `3` sources found but nothing parsed, `4`
nothing found.

## The other file

`extract_items.py` here is the same code the `.bat` carries, kept readable so it
can be read and diffed. The `.bat` is the thing you use.

Optional arguments are passed straight through, e.g.
`Extract-AvatarItem-v20.bat --root D:\dump`.
