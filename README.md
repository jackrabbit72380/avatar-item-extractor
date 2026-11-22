# Avatar Item Extractor

Double-click `Extract-AvatarItem-v20.bat` with your Xbox 360 avatar items in the
same folder. It extracts their models, textures and colours, labels each one MP
or SP, and rigs them onto Halo CE's biped, first-person arms and the NXE avatar
skeleton.

An item can be given however you have it: loose `asset.bin` / `asset_v2.bin`, or
the marketplace package itself - the file named after the item's GUID, with no
extension. A package holds the same item more than once, and the newer copy is
the one read: the one carrying the versioned metadata block, checked by actually
parsing each copy rather than by position. The report says which copy was used.

It reads only the folder the `.bat` sits in, and writes its results there too.

Needs Python 3.8+. Blender 4.x makes the rigging files.

Halo CE's two rig files - `master chief skeleton.blend` and `fp arms.blend` -
travel inside the `.bat` and are unpacked to
`%LOCALAPPDATA%\AvatarItemExtractor\rig` on the first run, so there is nothing
to download or place beside it. Files you put in a `rig\` folder beside the
`.bat`, or beside the `.bat` itself, are used instead when they are there.

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

"Test Item" is whatever your item is titled. Folder and file names are the
item's title; several items at once go to `extracted\`.

The `NXE` files need only Blender, because that skeleton travels inside the
`.bat`. The biped, the arms, the `.jms` and `Test Item.blend` use Halo's two
`.blend` files, which travel inside the `.bat` as well. If they are somehow
missing, the NXE and unrigged copies are still written and the run says which
files it could not find. If rigging cannot run at all, the reason is written to
`blender.log` in the output folder and the window stays open to say so.

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

Every item also gets an image to bind, in `.png`, `.tga` and `.tif`: the decoded
base map when the container carries a texture, and otherwise its own colour as a
flat 64x64 image, `<stem> colour.*`. The `.mtl` names it with `map_Kd`, so the
colour survives import in Max and Blender rather than being dropped along with
`Kd`, and the `.tif` is a bitmap source for Halo CE's tool.

If a base map or a colour card is missing, `catalogue.json` records every block
the container held - its id, its size and its first eight bytes - and the run
prints the same list. That is the evidence of what the item actually contains,
so a missing texture can be looked at rather than guessed about.

The base map comes from the model block's own texture table first - the item
names its slots there and each slot states its size, format and whether it holds
anything - and only falls back to a texture kept in its own block when the model
has no table at all. A table of empty slots means there is no base map to write,
and the report says so.

`report.txt` says the same in plain text: the blocks, the mesh counts, the
texture slots the model declares, whether a base map and a colour table were
found, and each part's shader and texture bindings. The extractor writes it
before any Blender runs, so a run without Blender still describes the file;
the rigging section is added underneath it when Blender is there.

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
