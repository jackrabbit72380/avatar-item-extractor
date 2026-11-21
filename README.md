# Avatar Item Extractor

**Double-click `avatar-item-extractor.bat`.** That is the whole procedure.

It finds the item files itself, extracts every item it finds, and opens the
results folder. No folder picker, no drag-and-drop, no setup step, no prompts.

It reads retail Xbox 360 avatar items — the `YTGR`/`STRB` assets the LIVE avatar
service served and the `Clean Slate NXE` dump ships — and writes a catalogue
plus one model file and icon per item.

## Where it looks

A fixed list, checked every run, in this order:

1. its own folder, and the folder above it
2. `..\UniKron\src_archive` — where the project keeps the dump
3. `Downloads`
4. `Desktop`
5. `Documents`
6. `OneDrive\Downloads`, `OneDrive\Desktop`

It takes **every** source it finds, not the first one, and extracts them
together into one catalogue. A source is a folder with `closet_index.tsv` (the
retail layout) or one with `.bin` / `.asset` item files. It does not look deeper
than three folders down, and it skips `.git`, `node_modules`, `vendor`,
`extracted` and the recycle bin.

The run always says what it searched and what it found:

```
Looking for avatar items in:
  C:\Users\lands\avatar-item-extractor
  C:\Users\lands\UniKron\src_archive
  C:\Users\lands\Downloads
  ...
Found 2 item sources:
  C:\Users\lands\Downloads\closet  (20349 items in the index)
  C:\Users\lands\Desktop\items     (14 item files)
```

If nothing is found it names the folders it searched, exits with status 4, and
stops. It never asks a question.

## What it writes

| output | contents |
| --- | --- |
| `extracted/catalogue.json` | every item: name, category and body masks, STRB block table, geometry summary, where it came from, icon and `.obj` paths |
| `extracted/items/<id>.obj` | the model, ready for Blender |
| `extracted/icons/<id>.png` | the item's icon, copied when the folder has one |

A record looks like this:

```json
{
 "id": "00000008-001f-62f1-c10d-7afc354107d4",
 "name": "2014 Colombia Home Jersey",
 "categories": 8, "bodies": 3,
 "file": "00000008-001f-62f1-c10d-7afc354107d4.bin",
 "source": "C:\\Users\\lands\\Downloads\\closet",
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
which stage failed. The run continues; it never stops at the first bad file.

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
- A file that is not a `STRB` container is reported and skipped, so a folder of
  unrelated `.bin` files produces a catalogue of failures and nothing else.

Exit status: `0` something parsed, `3` sources found but nothing parsed, `4`
nothing found.

## Other OS, or a folder outside the list

```sh
./setup.sh                                     # vendors avatar_mesh.py + lzx.py
python3 extract_items.py                       # same fixed search list
python3 extract_items.py --root /data/dump     # search somewhere else
python3 extract_items.py /data/dump/closet     # or name one source directly
```

Options:

```
--out DIR        where to write (default: extracted)
--obj            write each model as <out>/items/<id>.obj
--only ID|NAME   extract only ids or names containing this (repeatable)
--limit N        stop after N items
--no-icons       do not copy icons
--root DIR       search this folder instead of the default list (repeatable)
--mesh-dir DIR   where avatar_mesh.py lives (default: ./vendor)
```
