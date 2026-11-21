# Avatar Item Extractor

Double-click `Extract-AvatarItem-v20.bat` with your Xbox 360 avatar items in the
same folder. It extracts their models and textures, labels each one MP or SP,
and rigs them onto Halo CE's biped and first-person arms.

It reads only the folder the `.bat` sits in, and writes its results there too.

Needs Python 3.8+. Blender 4.x renders the rigs, with `master chief skeleton.blend`
and `fp arms.blend` in a `rig\` folder beside the `.bat`.

## Output

```
Test Item\
    Test Item.obj  plus .mtl
    Test Item base map.png  also .tga and .tif
    Test Item.png  the item's icon, when the package has one
    card_art.png
    Test Item.fbx, Test Item.jms  rigged to the biped and arms
    avatar_rigged.blend
    Test Item - unrigged.blend, .fbx, .glb
    Test Item - NXE.blend, .fbx, .glb
    preview.png, thumbnail.png
    report.txt, scene.json, skeleton.json, blender.log
    catalogue.json
```

"Test Item" is whatever your item is titled. Folder and file names are the
item's title; several items at once go to `extracted\`, and the rigging files
are only made when Blender and the `rig\` folder are both there.

`unrigged` is the item fitted to the biped with no skeleton; `NXE` is the same
model in its own avatar space, y-up metres, as the package stores it. In
`catalogue.json`, `mp` means the item takes your team colour and `sp` means its
colours are baked in.
