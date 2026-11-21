# Avatar Item Extractor

Double-click `Extract-AvatarItem-v20.bat` with your Xbox 360 avatar items in the
same folder. It extracts their models, textures and colours, labels each one MP
or SP, and rigs them onto Halo CE's biped, first-person arms and the NXE avatar
skeleton.

It reads only the folder the `.bat` sits in, and writes its results there too.

Needs Python 3.8+. Blender 4.x renders the rigs, with `master chief skeleton.blend`
and `fp arms.blend` in a `rig\` folder beside the `.bat`.

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
item's title; several items at once go to `extracted\`, and the rigging files
are only made when Blender and the `rig\` folder are both there.

`unrigged` is the item fitted to the biped with no skeleton. `NXE` is the same
model bound to the NXE avatar skeleton in the package's own space, y-up metres,
so it drops into the 2008 editor's rig as the game ships it.

`colour_00.png` draws the item's colour table the way the editor pages it, three
chips across, and `_colours.txt` lists the same colours as hex. An item with no
real palette still gets its placeholder colours, marked as such in the text file.
In `catalogue.json`, `mp` means the item takes your team colour and `sp` means its
colours are baked in.
