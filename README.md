# Avatar Item Extractor v20

One click. It finds every retail Xbox 360 avatar item it can reach on your
computer and turns them into a catalogue plus one 3D model file per item.

Nothing to configure, no folder picker, no drag and drop, and nothing is
downloaded while it runs: the extractor is carried inside the `.bat` file
itself.

---

## What you need

* **Windows** - anything that still runs `.bat` files and PowerShell.
* **Python 3.8 or newer** - <https://www.python.org/downloads/windows/>; during
  install, tick **"Add python.exe to PATH"**.
* **The two reader modules, once.** `avatar_mesh.py` and `lzx.py` have to sit in
  the same folder as the `.bat` the first time you run it. It copies them into
  `%LOCALAPPDATA%\AvatarItemExtractor` and never asks again - after that the
  `.bat` works on its own.

Check Python quickly in Command Prompt:

```
py -3 --version
```

---

## How to use it

1. Put `Extract-AvatarItem-v20.bat` on your Desktop, in Downloads, in `C:\Tools`
   - anywhere. Next to it, put `avatar_mesh.py` and `lzx.py` the first time.
2. **Double-click the `.bat`.**
3. Read the console: it lists where it looked, every item source it found, and
   every item it wrote.

You do not choose a folder or type a path. It looks in a fixed list of places,
takes everything it finds, and extracts all of it. At the end it waits for a
key press so the report stays on screen.

### Results land next to the `.bat`

```
extracted\
    catalogue.json          one record per item
    items\<id>.obj          the 3D model, one file per item
    icons\<id>.png          the item's icon, when there is one
```

---

## Where it looks

In this order, and it stops descending once it has taken a folder:

1. the folder the `.bat` is in
2. the folder above that
3. `%USERPROFILE%\Downloads`
4. `%USERPROFILE%\Desktop`
5. `%USERPROFILE%\Documents`
6. `%USERPROFILE%\OneDrive\Downloads`
7. `%USERPROFILE%\OneDrive\Desktop`

It walks at most **3 levels deep** and skips `.git`, `node_modules`,
`__pycache__`, `vendor`, `extracted`, `$RECYCLE.BIN` and
`System Volume Information`.

A **source** is a folder holding `closet_index.tsv` (the retail closet layout:
the index, `<guid>.bin` per item, `icons\`) or one holding loose `.bin` /
`.asset` item files. Several sources are extracted into one catalogue, and
duplicate ids are counted and skipped.

---

## What it writes

### `catalogue.json`

One record per item:

```json
{
 "items": [
  {
   "id": "3a1f0001-1111-2222-3333-444455556666",
   "name": "Test Shirt",
   "categories": 975110145,
   "bodies": 3,
   "bytes": 41024,
   "blocks": [{"id": 3, "size": 1}, {"id": 5, "size": 1}],
   "model": {
    "parses": true,
    "batches": 1,
    "vertices": 1137,
    "triangles": 2264,
    "uv_sets": 2,
    "textures": 3,
    "shader_ids": [7],
    "bounds": [[-0.711, 0.711], [0.0, 1.6], [-0.17, 0.2]]
   },
   "icon": "icons/3a1f0001-1111-2222-3333-444455556666.png",
   "obj": "items/3a1f0001-1111-2222-3333-444455556666.obj"
  }
 ]
}
```

* `categories` - the bitmask in the item GUID's first four bytes; the index
  repeats it in column two.
* `bodies` - `avatarBodyType` from column three: `3` fits both bodies, `1` / `2`
  one body only.
* `blocks` - the item's `STRB` container blocks and their entry counts.
* `model.bounds` - `[min, max]` per axis, **y up**: feet at `y = 0`, head near
  `1.6`.
* `model.parses` is `false` with an `error` string when an item could not be
  read; the same reason is printed in the console.

### `items\<id>.obj`

Wavefront OBJ, one `o batch_<shader>` group per triangle batch, positions and
triangles only, written y-up.

### `icons\<id>.png`

Copied from the source `icons` folder when the item has one.

---

## Console messages and exit codes

| Exit | Console says | Meaning |
| ---- | ------------ | ------- |
| `0` | `Done. Everything is in:` | At least one model parsed. |
| `3` | `Item sources were found, but no model parsed` | The folder and index were fine; the item files held no readable model. Reasons printed per item. |
| `4` | `No item sources were found` | No searched folder held a `closet_index.tsv` or any `.bin` / `.asset` file. |
| `5` | `The reader modules ... are missing` | `avatar_mesh.py` and `lzx.py` are not in the `.bat`'s folder or its cache folder. |
| `1` | `Could not unpack the code carried inside this file` | The `.bat` was truncated. Download it again. |
| `2` | `Python 3.8 or newer was not found` | Install Python and add it to PATH. |

Exit code `3` is not a crash: the files found are not item assets, or are a
kind the reader does not know yet.

---

## Running the unpacked extractor by hand

The `.bat` unpacks itself to `%LOCALAPPDATA%\AvatarItemExtractor` and runs that
copy. For more control:

```
py -3 "%LOCALAPPDATA%\AvatarItemExtractor\extract_items.py"
```

Options:

```
  <folder-or-file>   extract that one source, skip the search
  --out DIR          where to write (default: extracted)
  --obj              write the .obj files (the .bat always does)
  --only TEXT        only ids or names containing TEXT (repeatable)
  --limit N          stop after N items
  --no-icons         do not copy icons
  --root DIR         search DIR instead of the default list (repeatable)
  --mesh-dir DIR     where the reader modules are (default: beside the script)
```

---

## What is inside the file

A batch header, a `###BOOTSTRAP###` marker, a short Python bootstrap, a
`###PAYLOAD###` marker, then the extractor compressed and base85-encoded.

Each run, a PowerShell one-liner that ships with Windows writes the bootstrap to
`%LOCALAPPDATA%\AvatarItemExtractor`, the bootstrap unpacks the extractor and
runs it. Nothing is fetched from the network at any point. The payload is base85
so the batch layer cannot mangle it - no quotes, no backslashes, no percent
signs.

---

## What it does not do

* **No textures in the meshes.** Textures are DXT-compressed and OBJ has nowhere
  to put them; the catalogue reports how many an item carries.
* **No materials or normals.** The export is flat-shaded geometry.
* **No rigging or posing.** Vertices are exported as stored. Body meshes are
  authored in bind space and posed by a skeleton at draw time, so a body part
  may look like a bent limb. Clothing, hats and shoes are not skinned and export
  normally.
* **No writing back.** It only reads. Nothing in your folders is changed, moved
  or deleted.

---

## Troubleshooting

**"The reader modules ... are missing."**
Copy `avatar_mesh.py` and `lzx.py` into the same folder as the `.bat` and run it
again. Or drop them straight into `%LOCALAPPDATA%\AvatarItemExtractor`, where
the tool keeps its own copies.

**"Python 3.8 or newer was not found on this computer."**
Install Python, tick **Add python.exe to PATH**, close the window, run the `.bat`
again. `py -3 --version` shows which Python will be used.

**"Could not unpack the code carried inside this file."**
The file was damaged on the way down. Download it again rather than copying it
out of a chat window, and run it from a simple path such as `C:\Tools`, not from
inside a `.zip`.

**"No item sources were found."**
Put the folder containing `closet_index.tsv` in your Downloads, Desktop or
Documents, or in the `.bat`'s own folder, and run it again. Somewhere else -
run the unpacked extractor with `--root "D:\wherever"`.

**"Item sources were found, but no model parsed out of them."**
The index was found, so the folder is right; the files behind it are not
readable item assets. `no block 3 (the model block)` means that file holds no
model at all.

**SmartScreen: "Windows protected your PC".**
An unsigned batch file triggers this. **More info -> Run anyway**.

**Windows hides the `.bat` extension.**
Normal. Right-click -> **Edit** shows the batch text if you want to read it.

---

## Uninstalling

Delete the `.bat`, the `extracted` folder beside it, and
`%LOCALAPPDATA%\AvatarItemExtractor`. Nothing else was installed and no registry
entries were made.

---

## Licence

The scripts here are provided as-is for reading item assets you already have on
your own machine. They ship no game data and download none.
