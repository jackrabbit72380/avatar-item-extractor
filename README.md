# Extract Avatar Item

One file, one double-click. `Extract-AvatarItem-v20.bat` finds retail Xbox 360
avatar items on your PC, reads them, and writes a catalogue, a model file per
item, and the item icons.

Nothing to install. Nothing to configure. Nothing to choose.

---

## What you need

| | |
| --- | --- |
| **Windows** | 10 or 11. The tool is a `.bat` file. |
| **Python 3** | 3.8 or newer, from [python.org](https://www.python.org/downloads/). During setup tick **"Add python.exe to PATH"**. If `python` already works in a Command Prompt, you have it. |
| **Internet, first run only** | Two reader modules are downloaded once. After that the tool runs offline. |

---

## How to use it

1. Open the repo page and click **`Extract-AvatarItem-v20.bat`**, then the
   **Download raw file** button (the arrow next to the copy icon).
2. Put the file wherever you like — Desktop is fine. It works from any folder.
3. **Double-click it.**

That's the whole procedure. A console window opens, says what it is doing, and
then the results folder opens by itself.

### What happens on the first run

- The extractor is unpacked out of the `.bat` into
  `%LOCALAPPDATA%\AvatarItemExtractor`.
- `avatar_mesh.py` and `lzx.py` — the two modules that read the item format —
  are downloaded into the same folder.
- Then it searches for items and extracts them.

Later runs skip the first two steps and start working immediately, offline.

---

## Where it looks for items

You do not tell it where your files are. It checks this list every run, three
folders deep, and takes **every** source it finds:

1. the folder the `.bat` sits in, and the folder above it
2. `..\UniKron\src_archive` (where the UniKron project keeps the dump)
3. `%USERPROFILE%\Downloads`
4. `%USERPROFILE%\Desktop`
5. `%USERPROFILE%\Documents`
6. `%USERPROFILE%\OneDrive\Downloads` and `OneDrive\Desktop`

It skips `.git`, `node_modules`, `vendor`, `__pycache__`, `$RECYCLE.BIN` and
`System Volume Information`, and it does not descend into a folder it has
already accepted as a source.

A **source** is either:

- a **closet folder** — `closet_index.tsv`, `<guid>.bin` files, and an `icons/`
  folder, the layout the retail dump ships; or
- a **folder of loose items** — any folder containing `.bin` or `.asset` files.

The console prints what it searched and what it found before it starts, for
example:

```
Looking for avatar items in:
  C:\Users\you\Desktop
  C:\Users\you\Downloads
Found 2 item sources:
  C:\Users\you\Downloads\closet  (20349 items in the index)
  C:\Users\you\Desktop\items     (14 item files)
```

---

## What it writes

Everything goes into an `extracted` folder **next to the `.bat`**, which opens
when the run finishes.

| output | contents |
| --- | --- |
| `extracted\catalogue.json` | one record per item: name, category and body masks, container block table, geometry summary, which folder it came from, paths to its icon and model |
| `extracted\items\<id>.obj` | the item's model, ready to open in Blender, MeshLab or any 3D viewer |
| `extracted\icons\<id>.png` | the item's icon, copied when the source folder has one |

A catalogue record looks like this:

```json
{
 "id": "00000008-001f-62f1-c10d-7afc354107d4",
 "name": "2014 Colombia Home Jersey",
 "categories": 8,
 "bodies": 3,
 "file": "00000008-001f-62f1-c10d-7afc354107d4.bin",
 "source": "C:\\Users\\you\\Downloads\\closet",
 "bytes": 9532,
 "blocks": [{"id": 1, "size": 412}, {"id": 3, "size": 9120}],
 "model": {
  "parses": true,
  "batches": 1,
  "vertices": 1450,
  "triangles": 2402,
  "uv_sets": 1,
  "textures": 0,
  "shader_ids": [6],
  "bounds": [[-0.31, 0.31], [0.0, 0.21], [-0.18, 0.87]]
 },
 "icon": "icons/00000008-001f-62f1-c10d-7afc354107d4.png",
 "obj": "items/00000008-001f-62f1-c10d-7afc354107d4.obj"
}
```

If a file cannot be read, it is **not** skipped silently: `model.parses` is
`false`, `model.error` says which stage failed, the rest of the run continues,
and the console lists every failure at the end.

### In a closet folder

`closet_index.tsv` has four tab-separated columns:

```
id                                    categories  bodies  name
00000008-001f-62f1-c10d-7afc354107d4  00000008    3       2014 Colombia Home Jersey
```

- **categories** is the category bitmask, and it is a restatement of the GUID's
  first four bytes — the LIVE avatar service kept the categories inside the id.
  A loose file gets its mask the same way.
- **bodies** is `avatarBodyType`: `3` means male and female, `1` and `2` mean one
  body each.

---

## How an item is read

An item asset is a `STRB` container. Block 3 is the model, and in retail assets
that block is LZX-framed *inside* the container — where the editor's own asset
pack stores its blocks plain — so it is decompressed first and then parsed:
vertices, `u16` triangle indices, half-float UV sets, material records,
per-vertex joints and weights, and the shader ids.

Items are pre-placed in a body space of their own and **up is `y`**: feet sit at
`y = 0`, a hat tops out near `1.6`. That is why the `.obj` export applies no
rotation.

Retail items carry no textures. Colour comes from the material records and the
avatar body they are placed on.

---

## When something goes wrong

The console always ends with one of these. Here is what each one means.

| message | what to do |
| --- | --- |
| **No avatar items were found** (the folders are listed above it) | None of the searched folders holds a `closet_index.tsv` or any `.bin`/`.asset` file. Put your item folder in `Downloads`, or pass the folder yourself — see *Arguments* below. |
| **Items were found but none could be read**, and the failures say `not a STRB container` | Those files are not retail avatar items. The tool reads `YTGR`/`STRB` assets only, not XML, JSON, `.png` or renamed archives. |
| **Python was not found** | Install Python 3 from [python.org](https://www.python.org/downloads/) and tick **"Add python.exe to PATH"**. Close the window, then double-click the `.bat` again. |
| **Could not get the avatar readers** | The download was blocked. On a working machine, copy `avatar_mesh.py` and `lzx.py` from `UniKron\avatar\avatar_tools` into `%LOCALAPPDATA%\AvatarItemExtractor`, then run the `.bat` again. |
| **The LZX reader is missing** | Same as above: `lzx.py` needs to be in `%LOCALAPPDATA%\AvatarItemExtractor`. |
| **Could not unpack the extractor from this file** | The file was truncated (an interrupted download) or sits somewhere unusual. Download it again, or move it to a simple path such as `C:\Tools`, and rerun. |

### Arguments (optional)

The `.bat` passes anything you give it straight through to the extractor, so all
of these work:

```bat
Extract-AvatarItem-v20.bat --root D:\dump
Extract-AvatarItem-v20.bat --root D:\dump --only "Spartan"
Extract-AvatarItem-v20.bat --limit 20
Extract-AvatarItem-v20.bat --root D:\dump --out D:\extracted-items
```

| argument | effect |
| --- | --- |
| `--root FOLDER` | search this folder instead of the built-in list. Repeatable. |
| `--out FOLDER` | write here instead of `extracted` beside the `.bat`. |
| `--only TEXT` | extract only ids or names containing this text. Repeatable. |
| `--limit N` | stop after N items. |
| `--no-icons` | do not copy icons. |

The easiest way to use an argument regularly: make a shortcut to the `.bat`,
open its properties, and add the arguments to the end of the **Target** field.

### Exit codes

| code | meaning |
| --- | --- |
| `0` | at least one item was read and written |
| `3` | sources were found, but nothing in them could be read |
| `4` | nothing was found to read |

---

## Clearing it out

The tool keeps only three files, all in one place:

- delete `%LOCALAPPDATA%\AvatarItemExtractor` to reset it (the next run
  unpacks and downloads again);
- delete the `extracted` folder next to the `.bat` to remove results;
- the `.bat` itself is the whole program — deleting it uninstalls everything.

---

## Where the code is

All of it is inside the `.bat`, below the `###PAYLOAD###` line — the batch part
starts at the top and ends with `exit /b`, and the rest is Python that the file
unpacks and runs. Open the file in Notepad or VS Code to read it; nothing is
compiled, packed or hidden.

---

## Limits worth knowing

- **No field states a garment type.** The item id does not carry one, every
  garment binds to the same joints, and vertex positions are normalised. The
  catalogue records the category mask and the geometry, and claims no category.
- **Retail items have no textures of their own**, so `.obj` files carry geometry
  and UVs but no image maps.
- **A few retail models** end their LZX chain with trailing bytes that read as an
  oversized header, and a single batch can exceed eight thousand vertices; both
  are handled by the reader.
- **Items are not rigged for animation** in the `.obj` output — joints and
  weights are recorded in the catalogue, but the export is a static mesh.
