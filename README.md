# Avatar Item Extractor

Double-click `Extract-AvatarItem-v20.bat`. It finds Xbox 360 avatar items in
Downloads, Desktop, Documents or beside the `.bat`, extracts their models and
textures, labels each one MP or SP, and rigs them onto Halo CE's biped and
first-person arms.

Results land in the folder the `.bat` sits in.

Needs Python 3.8+. Blender 4.x renders the rigs, with `master chief skeleton.blend`
and `fp arms.blend` in a `rig\` folder beside the `.bat`.

## Output

```
UNSC Marine Armor\
    catalogue.json
    UNSC Marine Armor base map.png  also .tga and .tif
    items\UNSC Marine Armor.obj  plus .mtl
    icons\UNSC Marine Armor.png
    rigged\avatar_rigged.blend, .jms, .fbx
```

Folder and file names are the item's title; several items at once go to
`extracted\`. In `catalogue.json`, `mp` means the item takes your team colour and
`sp` means its colours are baked in.
