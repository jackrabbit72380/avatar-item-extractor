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
    catalogue.json
    Test Item base map.png  also .tga and .tif
    items\Test Item.obj  plus .mtl
    icons\Test Item.png
    rigged\avatar_rigged.blend, .jms, .fbx
```

"Test Item" is whatever your item is titled. Folder and file names are the
item's title; several items at once go to `extracted\`. In `catalogue.json`, `mp`
means the item takes your team colour and `sp` means its colours are baked in.
