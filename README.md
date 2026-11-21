# Avatar Item Extractor

One click on Windows: **double-click `avatar-item-extractor.bat`**, pick the
folder holding your item files, and it opens the results for you.

It reads retail Xbox 360 avatar items — the `YTGR`/`STRB` assets the LIVE avatar
service served and the `Clean Slate NXE` dump ships — and writes a catalogue
plus one model file and icon per item.

## What it accepts

Anything holding item assets; it works out which of the three you gave it:

| you give it | it does |
| --- | --- |
| a **closet folder** (`closet_index.tsv`, `<guid>.bin`, `icons/`) | uses the index for names and category masks |
| a **folder of loose items** (`.bin` / `.asset`) | extracts every item file in it; names come from the ids |
| **one item file** | extracts that file — you can drag it straight onto the `.bat` |

If the file is not a `STRB` container the run says so and moves on; it never
stops at the first bad item.

## One click (Windows)

1. Double-click `avatar-item-extractor.bat`.
2. Choose the folder. (Skip this by putting a `_closet` folder beside the `.bat`,
   or by dragging a folder or `.bin` file onto the `.bat`.)
3. The results folder opens: `extracted\`.

On first run it fetches the two reader modules it needs into `vendor\` — from a
UniKron checkout if one sits next to this repo, otherwise from GitHub.

## Other OS

```sh
./setup.sh                                  # vendors avatar_mesh.py + lzx.py
python3 extract_items.py _closet extracted --obj
```

Or point straight at a UniKron checkout and skip setup:

```sh
python3 extract_items.py path/to/item.bin extracted --obj \
  --mesh-dir ../UniKron/avatar/avatar_tools
```

## What it writes

| output | contents |
| --- | --- |
| `extracted/catalogue.json` | one record per item: name, category and body masks, STRB block table, geometry summary, icon and `.obj` paths |
| `extracted/items/<id>.obj` | the model, ready for Blender |
| `extracted/icons/<id>.png` | the item's icon, copied when the folder has one |

A record looks like this:

```json
{
 "id": "00000008-001f-62f1-c10d-7afc354107d4",
 "name": "2014 Colombia Home Jersey",
 "categories": 8, "bodies": 3,
 "blocks": [{"id": 1, "size": 412}, {"id": 3, "size": 9120}],
 "model": {
  "parses": true,
  "batches": 1, "vertices": 1450, "triangles": 2402,
  "uv_sets": 1, "textures": 0, "shader_ids": [6],
  "bounds": [[-0.31, 0.31], [0.0, 0.21], [-0.18, 0.87]]
 }
}
```

When an item does not parse, `model.parses` is `false` and `model.error` says
which stage failed.

## How an item is read

Block 3 of the `STRB` container is the model, and a *retail* block is LZX-framed
inside the container where the editor's own asset pack stores its blocks plain.
So the payload is decompressed first, then parsed: vertices, `u16` triangle
indices, half-float UV sets, material records, per-vertex joints and weights,
and the shader ids. Retail items carry no textures of their own.

Items are pre-placed in a body space of their own and **up is y**: feet at
`y = 0`, a hat topping out near `1.6`. That is why `.obj` export passes
`up_axis="y"` — the coordinates need no rotation.

## In a closet folder

`closet_index.tsv` is `id ⇥ categories ⇥ bodies ⇥ name`. Column two is the
category bitmask and is a restatement of the GUID's first four bytes — the LIVE
service put the categories inside the id, so a loose file gets its mask the same
way. Column three is `avatarBodyType`: `3` is male + female, `1` and `2` are one
body each.

## Limits worth knowing

- **No field states a garment type.** The item id does not carry one, every
  garment binds to the same joints, and vertex positions are normalised. The
  catalogue records the category mask and geometry and claims no category.
- A few retail models end their LZX chain with trailing bytes that read as an
  oversized header, and one batch can exceed eight thousand vertices; the
  reader handles both.
- Icons are copied, not generated. No icon in the folder means `"icon": null`.
- Exit status is 3 when nothing parsed, so a script can tell.

## Command line

```
python extract_items.py <folder-or-file> <out> [options]

--obj            write each model as <out>/items/<id>.obj
--only ID|NAME   extract only ids or names containing this (repeatable)
--limit N        stop after N selected items
--no-icons       do not copy icons
--mesh-dir DIR   where avatar_mesh.py lives (default: ./vendor)
```
