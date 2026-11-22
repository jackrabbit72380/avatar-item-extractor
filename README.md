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
    Test Item.fbx, Test Item.jms  rigged to the biped and arms
    avatar_rigged.blend
    Test Item - unrigged.blend, .fbx, .glb
    Test Item - NXE.blend, .fbx, .glb  rigged to the 71-joint NXE skeleton
    preview.png, thumbnail.png
    report.txt, scene.json, skeleton.json, blender.log
    catalogue.json
```

"Test Item" is whatever your item is titled. Folder and file names are the
item's title; several items at once go to `extracted\`.

The `NXE` files and the two previews need only Blender, because that skeleton
travels inside the `.bat`. The biped, the arms, `avatar_rigged.blend` and the
`.jms` also need Halo's two `.blend` files in `rig\`. If rigging cannot run at
all, the reason is written to `blender.log` in the output folder and the window
stays open to say so.

`unrigged` is the item fitted to the biped with no skeleton. `NXE` is the same
model bound to the NXE avatar skeleton in the package's own space, y-up metres,
so it drops into the 2008 editor's rig as the game ships it.

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
documented exit rule, and checks the three outcomes: a failed pass is code 7, a
clean pass is code 0, and no Blender at all is code 6. It needs no Blender
installed, which is the point - the failure path is what used to be invisible.
