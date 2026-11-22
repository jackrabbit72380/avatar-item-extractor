# Avatar Item Extractor

Double-click `Extract-AvatarItem-v20.bat` with your Xbox 360 avatar items in the
same folder. It extracts their models, textures and colours, labels each one MP
or SP, and rigs them onto Halo CE's biped, first-person arms and the NXE avatar
skeleton.

It reads only the folder the `.bat` sits in, and writes its results there too.

Needs Python 3.8+. Blender 4.x makes the rigging files; `master chief skeleton.blend`
and `fp arms.blend` in a `rig\` folder beside the `.bat` add the biped, the arms
and the JMS.

## Output

```
Test Item\
    Test Item.obj  plus .mtl
    Test Item base map.png  also .tga and .tif
    Test Item.png  the item's icon, when the package has one
    colour_00.png  the item's own palette, when it carries one
    Test Item_colours.txt
    card_art.png
    Test Item.blend  the item on the biped with the FP arms, ready to export
    Test Item.fbx, Test Item.jms  the same rig, for tools that cannot read .blend
    Test Item - NXE.blend, .fbx, .glb  rigged to the 71-joint NXE skeleton
    Test Item - unrigged.blend, .fbx  the model with no skeleton
    report.txt, scene.json, skeleton.json, blender.log
    catalogue.json
```

## Choosing what to write

The tool asks once, then gets on with it. Pressing nothing picks the Halo rig
after 15 seconds, so a double-click and a walk away needs no input.

| | Option | Writes |
|---|---|---|
| 1 | Halo rig | `Test Item.blend`, `.fbx` and `.jms` - the item on the biped with the FP arms, ready to open and export |
| 2 | NXE rig | `Test Item - NXE.blend`, `.fbx`, `.glb` |
| 3 | Unrigged | `Test Item - unrigged.blend`, `.fbx` |

`.obj`, `.mtl`, the base maps, the colour cards and `catalogue.json` are written
by every option, because they need no Blender at all.

The Halo rig needs Halo's two `rig\*.blend` files. Without them it names the
files it is missing and stops rather than quietly writing something else. The
NXE and Unrigged options need nothing but Blender.

`--profile halo` works on the command line too, for scripting.

"Test Item" is whatever your item is titled. Folder and file names are the
item's title; several items at once go to `extracted\`.

The `NXE` files need only Blender, because that skeleton travels inside the
`.bat`. The biped, the arms and the `.jms` also need Halo's two `.blend` files
in `rig\`. If rigging cannot run at all, the reason is written to `blender.log`
in the output folder and the window stays open to say so.

A pass that finishes without writing the models it should is treated the same
way. Blender exits 0 when a pass quietly does nothing, so the extractor checks
the `.fbx`, `.glb` and `.blend` files it expects are actually there, names any
that are missing, and keeps the window open rather than reporting a clean run.

`unrigged` is the model with no skeleton in the file - fitted to the biped when
the rig files are there, and left exactly as the package stores it when they are
not. `NXE` is the same model bound to the NXE avatar skeleton in the package's
own space, y-up metres, so it drops into the 2008 editor's rig as the game
ships it.

Each `.blend` is a saved scene holding just that one model, so it opens straight
onto the item rather than onto the whole rigging session.

`colour_00.png` draws the item's colour table the way the editor pages it, three
chips across, and `_colours.txt` lists the same colours as hex. A container with
no colour table still gets the text file, saying so - there is no palette to draw.
In `catalogue.json`, `mp` means the item takes your team colour and `sp` means its
colours are baked in.

## Working on the extractor itself

Neither script is needed to run the tool.

```sh
python3 tools/payload.py unpack Extract-AvatarItem-v20.bat src/
# edit src/extract_items.py, then put it back:
python3 tools/payload.py pack Extract-AvatarItem-v20.bat src/
```

`pack` decodes its own output and refuses to write unless it matches the files it
was given, so a half-written rebuild cannot be shipped.

```sh
python3 tools/test_pipeline.py
```

Runs the modules the `.bat` actually ships against a synthetic container and
checks the eight files the extractor owns: `.obj`, `.mtl`, the base map in three
formats, `colour_00.png`, the hex list and `catalogue.json`.

```sh
python3 tools/test_rigging.py
```

Runs the real rigging pass against a stand-in Blender that obeys Blender's
documented exit rule. Six outcomes are checked: a crashed pass is 7, a pass that
exits 0 but writes no files is 7, missing biped copies are 7, a clean pass is 0,
a clean pass with the biped is 0, and no Blender at all is 6. It needs no
Blender installed, which is the point - the failure paths are what used to be
invisible.

```sh
python3 tools/test_blend.py
```

Drives the `.blend` export through a stand-in `bpy` and checks the save is a
scene holding only that item, made with `copy=True`, with the rest of the scene
put back afterwards - and that the datablock library writer is never used, since
that is what produced files that opened empty. `RIG_MODULES` points it at any
unpacked build to check a shipped version.
