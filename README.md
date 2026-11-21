# Avatar Item Extractor v20

One file. One click. It finds every retail Xbox 360 avatar item it can reach on
your computer and turns them into a catalogue plus one 3D model file per item.

Nothing to install, nothing to configure, nothing to drag and drop, and nothing
to download at run time: the code that does the work is carried inside the
`.bat` file itself.

---

## What you need

* **Windows** (any version that still runs `.bat` files and PowerShell).
* **Python 3.8 or newer.** <https://www.python.org/downloads/windows/> - during
  install, tick **"Add python.exe to PATH"**.

That is all. The two reader modules, the parsers and the catalogue writer all
live inside the one file. There is no second file to keep beside it, no folder
to unpack by hand, and no internet connection needed while it runs.

Check Python quickly by opening Command Prompt and typing:

```
py -3 --version
```

If that prints something like `Python 3.11.5`, you are ready.

---

## How to use it

1. Put `Extract-AvatarItem-v20.bat` anywhere convenient - your Desktop, a
   downloads folder, `C:\Tools`. The path does not matter.
2. **Double-click it.**
3. Read the console window; it lists every place it looked, every item source it
   found, and every item it wrote.

You do not choose a folder. You do not type a path. You do not drag anything
onto the file. It looks in a fixed list of places, takes everything it finds
there, and extracts all of it.

When it finishes it says `Done` and points at the results, then waits for a key
press so you can read the report.

### Results land next to the `.bat`

```
extracted\
    catalogue.json          one record per item
    items\<id>.obj          the 3D model, one file per item
    icons\<id>.png          the item's icon, when there is one
```

So if the file is on your Desktop, the results appear in
`Desktop\extracted\`.

---

## Where it looks

It searches these, in this order, and stops descending once it has found an item
source (so it never re-walks a folder it has already taken):

1. the folder the `.bat` is in
2. the folder above that one
3. `%USERPROFILE%\Downloads`
4. `%USERPROFILE%\Desktop`
5. `%USERPROFILE%\Documents`
6. `%USERPROFILE%\OneDrive\Downloads`
7. `%USERPROFILE%\OneDrive\Desktop`

Inside those it walks at most **3 levels deep** and skips `.git`,
`node_modules`, `__pycache__`, `vendor`, `extracted`, `$RECYCLE.BIN` and
`System Volume Information`.

An **item source** is a folder that holds either:

* `closet_index.tsv` - the retail closet layout: the index, `<guid>.bin` per
  item, and an `icons\` folder; or
* loose item files (`.bin` / `.asset`) with no index next to them.

If several sources turn up, all of them are extracted into the same catalogue
and duplicate ids are counted and skipped.

---

## What it writes

### `catalogue.json`

```json
{
 "searched": ["C:\\Users\\you\\Desktop"],
 "sources": ["C:\\Users\\you\\Desktop\\closet"],
 "items": [
  {
   "id": "3a1f0001-1111-2222-3333-444455556666",
   "name": "Test Shirt",
   "categories": 975110145,
   "bodies": 3,
   "file": "3a1f0001-1111-2222-3333-444455556666.bin",
   "source": "C:\\Users\\you\\Desktop\\closet",
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

* `categories` is the bitmask in the item GUID's first four bytes; the index
  repeats it in column two.
* `bodies` is `avatarBodyType` from column three: `3` means the item fits the
  male and female body, `1` / `2` mean one body only.
* `blocks` lists the item's `STRB` container blocks and their sizes in entries.
* `model.bounds` is `[min, max]` per axis in item space, **y up**: feet sit at
  `y = 0`, a head tops out near `1.6`.
* `model.parses` is `false` with an `error` string when the item could not be
  read, and the reason is also printed in the console.

### `items\<id>.obj`

Wavefront OBJ, one `o batch_<shader>` group per triangle batch, positions and
triangles only. Vertices are written y-up, ready for Blender, Windows 3D Viewer,
or anything else that reads OBJ.

### `icons\<id>.png`

Copied straight from the source `icons` folder when the item has one.

---

## Console messages and exit codes

| Exit | Console says | Meaning |
| ---- | ------------ | ------- |
| `0` | `Done. Everything is in:` | At least one model parsed. Results are on disk. |
| `3` | `Item sources were found, but no model parsed` | The folders and the index were fine; the item files themselves did not contain a readable model. The reason is printed per item. |
| `4` | `No item sources were found` | None of the searched folders held a `closet_index.tsv` or any `.bin` / `.asset` item file. |
| `1` | `Could not unpack the code carried inside this file` | The `.bat` was truncated while downloading. Download it again. |
| `2` | `Python 3.8 or newer was not found` | Install Python and tick "Add python.exe to PATH". |

Exit code `3` is not a crash. It means the files that were found are not item
assets, or are a kind the reader does not know yet.

---

## Running the unpacked script by hand

The `.bat` unpacks itself to
`%LOCALAPPDATA%\AvatarItemExtractor\` on first run and runs that copy. If you
want more control, run the extractor there yourself:

```
py -3 "%LOCALAPPDATA%\AvatarItemExtractor\extract_items.py"
```

Options:

```
  <folder-or-file>   extract that one source and skip the search entirely
  --out DIR          where to write (default: extracted, relative to you)
  --obj              write the .obj files (the .bat always does)
  --only TEXT        only ids or names containing TEXT (repeatable)
  --limit N          stop after N items
  --no-icons         do not copy icons
  --root DIR         search DIR instead of the default list (repeatable)
  --mesh-dir DIR     where the reader modules are
                     (default: beside the script)
```

Examples:

```
py -3 extract_items.py C:\dump\closet --obj --out C:\dump\out
py -3 extract_items.py --root D:\extracted-from-console --only hat
```

It needs no arguments at all: with none, it searches and extracts everything.

---

## What is inside the file

`Extract-AvatarItem-v20.bat` is a batch header followed by two marker lines,
`###BOOTSTRAP###` and `###PAYLOAD###`.

* The **bootstrap** is a short Python program that unpacks the payload.
* The **payload** is the extractor plus its two reader modules, compressed and
  base64-encoded. Base64 is used on purpose: it contains no quotes, backslashes
  or batch metacharacters, so copying the file around cannot corrupt it.

On every run the batch part uses a PowerShell one-liner (already part of
Windows) to write the bootstrap to `%LOCALAPPDATA%\AvatarItemExtractor`, and the
bootstrap writes the payload files and runs the extractor. Nothing is fetched
from the network at any point.

---

## What it does not do

* **No textures in the meshes.** Item textures are DXT-compressed and the OBJ
  format has nothing to hold them. The catalogue tells you how many the item
  carries; the model files are geometry only.
* **No materials or normals.** Normals are lattice-packed in the source; the
  export is flat-shaded geometry.
* **No rigging or posing.** Vertices are exported as they are stored. Body
  meshes in the source are authored in bind space and are posed by a skeleton at
  draw time, so a body part may look like a bent limb rather than a standing
  figure. Clothing items, hats and shoes are not skinned and export normally.
* **No writing back.** It only reads. Nothing in your searched folders is
  changed, moved or deleted.
* **No icon generation.** Icons are copied only when the source already has
  them.

---

## Troubleshooting

**"Python 3.8 or newer was not found on this computer."**
Install Python from <https://www.python.org/downloads/windows/>, tick **Add
python.exe to PATH**, close the console window, and double-click the `.bat`
again. If you have several Python installs, `py -3 --version` in Command Prompt
shows the one that will be used.

**"Could not unpack the code carried inside this file."**
The file was damaged on the way down (a truncated or re-saved `.bat`). Download
it again rather than copying it out of a chat window, and run it from a simple
path such as `C:\Tools` rather than from inside a `.zip`.

**"No item sources were found."**
The items are not where it looks. Copy the closet folder - the one with
`closet_index.tsv` inside - into your Downloads, Desktop or Documents, or into
the same folder as the `.bat`, and run it again. If it lives somewhere else
entirely, run the unpacked script with `--root "D:\wherever"`.

**"Item sources were found, but no model parsed out of them."**
The index was found, so the folder is right, but the item files behind it are
not readable item assets. The console prints one reason per item; `no block 3
(the model block)` means that file has no model in it at all.

**Windows SmartScreen or "Windows protected your PC".**
The file is an unsigned batch script, so Windows warns about it. Choose **More
info -> Run anyway**.

**Windows hides the `.bat` extension.**
If you see `Extract-AvatarItem-v20` with no extension, that is normal; Windows
hides known extensions. Right-click -> **Edit** shows the batch text if you want
to read it first.

**A console window flashes and closes.**
It should always wait for a key press at the end. If it does not, run it from
Command Prompt instead: open the folder, type `Extract-AvatarItem-v20.bat`, and
press Enter - that leaves the output on screen and keeps the exit code.

**Antivirus quarantines it.**
The `.bat` writes a file to `%LOCALAPPDATA%` on each run, which some scanners
flag. The whole text is readable (right-click -> Edit). Allow the file once, or
run the unpacked script directly as shown above.

---

## Uninstalling

Delete the `.bat`, the `extracted` folder beside it, and
`%LOCALAPPDATA%\AvatarItemExtractor` if it exists. That folder holds only the
unpacked Python and the two reader modules; nothing else was installed and no
registry entries were made.

---

## Licence

The scripts in this repository are provided as-is for reading avatar item assets
you already have on your own machine. They ship no game data and download none.
