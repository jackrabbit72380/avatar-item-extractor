# Avatar Item Extractor

**One file, one double-click.** `Extract-AvatarItem-v20.bat` finds Xbox 360 avatar
items on your PC, extracts the models and their textures, labels each item MP or
SP, and rigs them onto Halo CE's biped and first-person arms.

No install, no folder picker, no questions. Everything it needs travels inside
the `.bat`.

---

## What you need

| | |
|---|---|
| **Windows + Python 3.8 or newer** | Required. Tick "Add python.exe to PATH" when you install Python. |
| **Blender 4.x** | Only for rigging. Without it the items still extract. |
| **Halo CE's two rig files** | Only for rigging: put `master chief skeleton.blend` and `fp arms.blend` in a folder called `rig` beside the `.bat`. |

Folder layout for rigging:

```
whatever folder\
    Extract-AvatarItem-v20.bat
    rig\
        master chief skeleton.blend
        fp arms.blend
```

---

## How to use it

1. Put `Extract-AvatarItem-v20.bat` anywhere simple, such as `C:\Tools`, or in the
   folder you downloaded your items into.
2. Put your item files in **Downloads**, **Desktop**, **Documents** or beside the
   `.bat` — a closet folder (with `closet_index.tsv`) or loose `.bin` / `.asset`
   files both work, including a bare `asset.bin` with no container around it.
3. Double-click the `.bat`.
4. Read the console: it lists what it found, what it wrote, whether it rigged,
   and where everything went. It waits for a key press at the end.

Results land in the folder the `.bat` sits in.

---

## What it writes

The folder is named after the item's title — the same string on every file:

```
UNSC Marine Armor\
    catalogue.json                  one record per item
    UNSC Marine Armor base map.png  the item's texture, also .tga and .tif
    items\
        UNSC Marine Armor.obj       the model, with UVs
        UNSC Marine Armor.mtl       its material, pointing at the base map
    icons\
        UNSC Marine Armor.png       the item's icon, when there is one
    rigged\                         only when rigging ran
        avatar_rigged.blend         biped, FP arms, every rigged item
        UNSC Marine Armor.jms       Halo 1 Jointed Model Skeleton for tool.exe
        UNSC Marine Armor.fbx       for 3ds Max or Blender
```

* **Several items in one run** go into `extracted\` instead, because there is no
  single title, and `rigged\` sits beside it.
* **MP or SP** is in `catalogue.json` as `shading`, and counted in the console:
  `mp` means the item takes your team colour, `sp` means its colours are baked
  into the texture.
* Items with no texture block of their own get no base map — most clothing is
  coloured rather than textured.

---

## Console messages

| Message | What to do |
|---|---|
| `No item sources were found.` | Put the item folder in Downloads, Desktop, Documents or beside the `.bat`, then run it again. |
| `Error: this container does not contain Avatar Item Content. Please try another.` | The files it found are not avatar items. Point it at the folder holding `closet_index.tsv` or the item `.bin` files. |
| `Python 3.8 or newer was not found on this computer.` | Install Python from python.org and tick "Add python.exe to PATH". |
| `No rigging: master chief skeleton.blend, fp arms.blend not found in …` | Extracting worked. Put Halo's two rig files in `rig\` beside the `.bat` and run it again. |
| `No rigging: Blender was not found.` | Extracting worked. Install Blender 4.x and run it again. |

---

## Uninstalling

Delete the `.bat` and the folder it made. It also keeps its own copy of the code
in `%LOCALAPPDATA%\AvatarItemExtractor`; delete that too and nothing is left
behind.

---

## Licence

Free to use and modify for personal use. Halo and its assets belong to Microsoft;
the rig files are yours to supply from your own copy of the game.
