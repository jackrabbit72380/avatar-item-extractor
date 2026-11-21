# Avatar Item Extractor

Reads retail Xbox 360 avatar items — the `YTGR`/`STRB` assets the LIVE avatar
service served and the `Clean Slate NXE` dump ships — and writes a catalogue
plus one file per item, with names, category masks, geometry and icons.

This repo is the extractor only. The binary readers it depends on
(`avatar_mesh.py`, `lzx.py`) are part of the
[UniKron](https://github.com/jackrabbit72380/UniKron) avatar tools; `setup.bat`
copies them into `vendor/` so this repo stays readable.

## Quick start (Windows)

1. Put your closet folder next to this one and name it `_closet`, or drop the
   path onto the `.bat` file.
2. Double-click **`setup.bat`** once — it vendors the two reader modules.
3. Double-click **`avatar-item-extractor.bat`**.

Results land in `extracted\`.

## Quick start (any OS)

```sh
./setup.sh                                  # vendors avatar_mesh.py + lzx.py
python3 extract_items.py _closet extracted --obj
```

If the readers live in a UniKron checkout, skip setup entirely:

```sh
python3 extract_items.py _closet extracted --obj \
  --mesh-dir ../UniKron/avatar/avatar_tools
```

## What the input looks like

A retail closet folder holds three things:

| file | what it is |
| --- | --- |
| `<guid>.bin` | one item asset, a `STRB` container |
| `icons/<guid>.png` | the item's icon |
| `closet_index.tsv` | `id ⇥ categories ⇥ bodies ⇥ name` |

Column two is the category bitmask and is a restatement of the GUID's first four
bytes — the LIVE service put the categories inside the id. Column three is
`avatarBodyType`: `3` is male + female, `1` and `2` are one body each.

## What it writes

| output | contents |
| --- | --- |
| `extracted/catalogue.json` | one record per item: name, category and body masks, STRB block table, geometry summary, icon and `.obj` paths |
| `extracted/icons/<id>.png` | the item's icon, copied |
| `extracted/items/<id>.obj` | the model, with `--obj` |

A geometry record looks like this:

```json
"model": {
  "parses": true,
  "batches": 1, "vertices": 1450, "triangles": 2402,
  "uv_sets": 1, "textures": 0, "shader_ids": [6],
  "bounds": [[-0.31, 0.31], [0.0, 0.21], [-0.18, 0.87]]
}
```

When an item does not parse, `model.parses` is `false` and `model.error` says
why — the run continues and reports the count at the end.

## How an item is read

Block 3 of the `STRB` container is the model, and a *retail* block is LZX-framed
inside the container where the editor's own asset pack stores its blocks plain.
So the payload is decompressed first, then parsed: vertices, `u16` triangle
indices, half-float UV sets, material records, per-vertex joints and weights,
and the shader ids. Retail items carry no textures of their own.

Items are pre-placed in a body space of their own and **up is y**: feet at
`y = 0`, a hat topping out near `1.6`. That is why `.obj` export passes
`up_axis="y"` — the coordinates need no rotation.

## Limits worth knowing

- **No field states a garment type.** The item id does not carry one, every
  garment binds to the same joints, and vertex positions are normalised. The
  catalogue records the category mask and geometry and claims no category.
- A few retail models end their LZX chain with trailing bytes that read as an
  oversized header, and one batch can exceed eight thousand vertices; the
  reader in `avatar_mesh.py` handles both by skipping the tail and bounding a
  batch by the `u16` index range.
- Icons are copied, not generated. An item with no icon in `icons/` gets
  `"icon": null`.

## Options

```
--obj            write each model as <out>/items/<id>.obj
--only ID|NAME   extract only ids or names containing this (repeatable)
--limit N        stop after N selected items
--no-icons       do not copy icons
--mesh-dir DIR   where avatar_mesh.py lives (default: ./vendor)
```
