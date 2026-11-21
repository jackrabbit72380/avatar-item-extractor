# Avatar Item Extractor v20

**One file. One double-click.** `Extract-AvatarItem-v20.bat` finds every retail
Xbox 360 avatar item it can reach on your computer, turns each one into a 3D
model, and — when Blender and Halo's rig files are present — rigs every item
onto Halo CE's own biped and first-person arms.

There is nothing to install beside it, no folder picker, no drag and drop, and
nothing is downloaded while it runs. The extractor, its two readers and the
rigging pass are all carried inside the `.bat` and unpacked into
`%LOCALAPPDATA%\AvatarItemExtractor` the first time you run it.

---

## What you need

* **Windows** — anything that still runs `.bat` files and PowerShell.
* **Python 3.8 or newer** — <https://www.python.org/downloads/windows/>; during
  install, tick **"Add python.exe to PATH"**.
* **Blender 4.x** — only for rigging, from <https://www.blender.org/download/>.
  Its installer puts it in `%ProgramFiles%\Blender Foundation`, which is where
  the tool looks. Without Blender the run still extracts everything.
* **Halo CE's two rig files** — only for rigging, in a folder called `rig`
  beside the `.bat`:

  ```
  rig\master chief skeleton.blend     19-bone bip01 biped, z-up
  rig\fp arms.blend                   37-bone frame FP arms + skinned hands
  ```

  These are game data, so they are not shipped here. Put them there yourself.

Check Python quickly in Command Prompt:

```
py -3 --version
```

---

## How to use it

1. Download **`Extract-AvatarItem-v20.bat`**. One file is the whole tool.
2. **Double-click it.**
3. Read the console: it lists where it looked, every item source it found,
   every item it wrote, and whether it rigged.

It does not ask a single question. It looks in a fixed list of places, takes
everything it finds, extracts all of it, and rigs all of it when it can. At the
end it waits for a key press so the report stays on screen.

### Results land next to the `.bat`

```
extracted\
    catalogue.json          one record per item
    items\<id>.obj          the 3D model, one file per item
    icons\<id>.png          the item's icon, when there is one
rigged\                     only when rigging ran
    avatar_rigged.blend     whole scene: biped, FP arms, every rigged item
    <id>.fbx                one rigged model per item, armature included
    <id>.jms                Halo 1 Jointed Model Skeleton for tool.exe
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
   "file": "3a1f0001-1111-2222-3333-444455556666.bin",
   "source": "C:\\Users\\you\\Downloads\\closet",
   "bytes": 41024,
   "blocks": [{"id": 2, "size": 3}, {"id": 3, "size": 1}],
   "avatar_content": true,
   "shading": "mp",
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

* `categories` — the bitmask in the item GUID's first four bytes; the index
  repeats it in column two.
* `bodies` — `avatarBodyType` from column three: `3` fits both bodies, `1` / `2`
  one body only.
* `blocks` — the item's `STRB` container blocks and their entry counts. Block
  `3` is the model, `5` the skeleton, `7` the custom colour table, `8` the
  asset metadata.
* `avatar_content` — `false` when the file is not an avatar item at all. Those
  files are listed and skipped.
* `shading` — **`mp`** when the container carries block 7, the CustomColorTable
  that lets the game apply your team colour, and **`sp`** when it does not, so
  the colours are baked into the texture. `null` when the item did not parse.
  The texture files themselves are not exported yet; when they are, this field
  is what names them `_mp` / `_sp`.
* `model.bounds` — `[min, max]` per axis, **y up**: feet at `y = 0`, head near
  `1.6`.
* `model.parses` is `false` with an `error` string when an item could not be
  read.

### `items\<id>.obj`

Wavefront OBJ, one `o batch_<shader>` group per triangle batch, positions and
triangles only, written y-up.

### `icons\<id>.png`

Copied from the source `icons` folder when the item has one.

---

## Rigging

When `rig\master chief skeleton.blend` and `rig\fp arms.blend` are beside the
`.bat` and Blender is installed, the same double-click goes on to rig every
item that was extracted:

1. **Fits it to the biped.** Items are y-up metres with the feet at `y = 0`.
   Halo is z-up in game units, where 1.83 m is 60 units, so every point is
   remapped `(x, y, z) -> (z, x, y)`, scaled to exactly 60 units tall, centred
   and stood on `z = 0`.
2. **Merges missing body parts.** An item that stops below 1.45 m — a hat,
   boots, a shirt — is joined with the catalogue's own full-body item
   (`MaleBody`, `FemaleBody`, anything with "body" in its id or name), so a
   whole figure is rigged rather than a piece floating in space.
3. **Skins it.** Every vertex is weighted to the two nearest deform bones of
   the biped, inverse-square by distance to each bone's head-tail segment and
   normalised to sum to 1. Distance weighting is used instead of Blender's
   bone-heat solver because most avatar items are single-sided shells, which
   bone heat refuses to solve. The same item always gets the same weights.
4. **Parents it** to the biped with an armature modifier, so it poses in the
   `.blend` immediately.
5. **Adds the first-person arms** — Halo's own 37-bone `frame` armature and its
   1495-vertex hand mesh — to the same scene.

JMS node names are written with underscores (`bip01_pelvis`) because JMS is
whitespace-delimited and a space would cut the name short; the `.blend` keeps
Halo's original spaced names.

If either the `rig` folder or Blender is missing, the run prints which one and
stops after extracting. Nothing is half-rigged.

---

## Console messages and exit codes

| Exit | Console says | Meaning |
| ---- | ------------ | ------- |
| `0` | `Done. Everything is in:` | At least one model parsed. |
| `3` | `Error: this container does not contain Avatar Item Content. Please try another.` | The files found are not avatar items. |
| `4` | `No item sources were found` | No searched folder held a `closet_index.tsv` or any `.bin` / `.asset` file. |
| `5` | `The reader modules ... are missing` | Should not happen: both readers travel inside the `.bat`. If it does, the file was edited after downloading. |
| `1` | `Could not unpack the code carried inside this file` | The `.bat` was truncated. Download it again. |
| `2` | `Python 3.8 or newer was not found` | Install Python and add it to PATH. |

Exit `3` is not a crash: the files found are not item assets, or are a kind the
reader does not know yet.

---

## Running the pieces by hand

The first run unpacks the tool to `%LOCALAPPDATA%\AvatarItemExtractor`. After
that you can drive the parts directly, which is handy for odd folders:

```
py -3 "%LOCALAPPDATA%\AvatarItemExtractor\extract_items.py" --root "D:\dump"
```

Extractor options:

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

Rigging by hand, with Blender on PATH:

```
blender -b --factory-startup --python "%LOCALAPPDATA%\AvatarItemExtractor\rig_items.py" ^
  -- --items extracted --rig "rig\master chief skeleton.blend" ^
  --fp "rig\fp arms.blend" --out rigged
```

Rigging options: `--no-fbx`, `--no-jms`, `--name NAME`, `--items DIR`,
`--out DIR`.

Two things `rig_items.py` cannot do from a script: it cannot use the item's own
skeleton (block 5 is not parsed, so items are fitted by geometry), and it
cannot write the preview picture into the `.blend` — Blender only draws that
when a file is saved from a window. Open the `.blend` once and press `Ctrl+S`
if you want the thumbnail to show the model instead of a box.

---

## What is inside the file

A batch header, a `###BOOTSTRAP###` marker, a short Python bootstrap, a
`###PAYLOAD###` marker, then four modules — `extract_items.py`,
`avatar_mesh.py`, `lzx.py`, `rig_items.py` — compressed and base85-encoded.

Each run, a PowerShell one-liner that ships with Windows writes the bootstrap
to `%LOCALAPPDATA%\AvatarItemExtractor`, the bootstrap unpacks the modules and
runs the extractor. The payload is base85 so the batch layer cannot mangle it —
no quotes, no backslashes, no percent signs — and the whole file is plain
ASCII, so right-click → **Edit** shows you every line of it.

---

## What it does not do

* **No textures in the meshes.** Textures are DXT-compressed and OBJ has nowhere
  to put them; the catalogue reports how many an item carries and whether the
  item is MP or SP.
* **No recolouring.** Multiplayer armour colour is applied by the game's shader
  against the item's texture. Fix it in your shaders; the pass does not dye
  geometry or rewrite textures.
* **No materials or normals.** The export is flat-shaded geometry.
* **No animation.** Only the rest pose is written; animations come from Halo's
  JMA files once the model is compiled.
* **No 3ds Max step.** The output is `.blend`, `.fbx` and `.jms`; Max opens the
  FBX, and `tool.exe` compiles the JMS.
* **No writing back.** It only reads. Nothing in your folders is changed,
  moved or deleted.

---

## Troubleshooting

**"Python 3.8 or newer was not found on this computer."**
Install Python, tick **Add python.exe to PATH**, close the window, run the
`.bat` again. `py -3 --version` shows which Python will be used.

**"Could not unpack the code carried inside this file."**
The file was damaged on the way down. Download it again rather than copying it
out of a chat window, and run it from a simple path such as `C:\Tools`, not from
inside a `.zip`.

**"No item sources were found."**
Put the folder containing `closet_index.tsv` in your Downloads, Desktop or
Documents, or in the `.bat`'s own folder, and run it again. Somewhere else — run
`extract_items.py` with `--root "D:\wherever"`.

**"Error: this container does not contain Avatar Item Content."**
The folder was found, so the search is fine; the files behind it are not avatar
items. Point the tool at the folder that holds `closet_index.tsv` and the
`<guid>.bin` files that go with it.

**"No rigging: ... not found in ...\rig"** or **"No rigging: Blender was not
found."**
Extraction succeeded; only the rigging step was skipped. Add the two `.blend`
files under `rig\` next to the `.bat`, install Blender, and run it again.

**Nothing at all happens, or the window closes instantly.**
Open Command Prompt, drag the `.bat` into it and press Enter, so the messages
stay visible.

**SmartScreen: "Windows protected your PC".**
An unsigned batch file triggers this. **More info → Run anyway**.

**Windows hides the `.bat` extension.**
Normal. Right-click → **Edit** shows the batch text if you want to read it.

---

## Uninstalling

Delete the `.bat`, the `extracted` and `rigged` folders beside it, and
`%LOCALAPPDATA%\AvatarItemExtractor`. Nothing else was installed and no registry
entries were made.

---

## Licence

The scripts here are provided as-is for reading item assets you already have on
your own machine. They ship no game data and download none.
