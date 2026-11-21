# Rigging onto the Halo CE skeleton

`rig_items.py` turns extracted items into rigged models. It runs inside
Blender, it is driven by `AvatarRig.bat`, and nothing in it asks a question.

The skeleton is Halo CE's own: a 19-bone `bip01` biped and the 37-bone `frame`
first-person arms. Those two `.blend` files are the input, so the output is a
model that stands in the same space, at the same scale, with the same node
names as a Halo character.

## Layout

```
<wherever you keep the tools>
    AvatarRig.bat                  double-click this
    Extract-AvatarItem-v20.bat     the extractor (unchanged)
    rig_items.py                   the rigging pass
    rig\
        master chief skeleton.blend    19-bone bip01 biped, z-up
        fp arms.blend                 37-bone frame FP arms + skinned hands
```

Double-click `AvatarRig.bat`. It extracts first (answering the extractor's
final key press itself), then finds Blender under
`%ProgramFiles%\Blender Foundation`, then rigs.

## What the pass does to each item

1. **Fits it to the biped.** Avatar items are y-up metres with the feet at
y = 0. Halo is z-up in game units where 1.83 m is 60 units, so every point is
remapped `(x, y, z) -> (z, x, y)`, scaled to exactly 60 units tall, centred on
the origin and stood on z = 0.
2. **Merges missing body parts.** An item that stops below 1.45 m — a hat,
boots, a shirt — is joined with the catalogue's own full-body item before
fitting, so what gets rigged is a whole figure rather than a piece floating in
space. The full-body item is found by name (`MaleBody`, `FemaleBody`, anything
with "body" in its id or name), and the item being rigged is never merged with
itself.
3. **Skins it.** Every vertex is weighted to the two nearest deform bones of the
biped, inverse-square by distance to each bone's head-tail segment, normalised
to sum to 1. Distance weighting is used instead of Blender's bone-heat solver
because most avatar items are single-sided shells, which bone heat refuses to
solve. The result is deterministic: the same item always gets the same weights.
4. **Parents it.** The mesh is parented to the biped with an armature modifier,
so it poses with the skeleton immediately in the .blend.
5. **Adds the first-person arms.** Halo's own FP arms armature and its 1495-vertex
hand mesh are appended to the same scene, so the viewmodel is there to work
with instead of being rebuilt.

## Output, next to the tools

| File | What it is |
| --- | --- |
| `rigged\avatar_rigged.blend` | whole scene: biped, FP arms, every rigged item |
| `rigged\<id>.fbx` | one rigged model per item, armature included |
| `rigged\<id>.jms` | Halo 1 Jointed Model Skeleton text for `tool.exe` |

The JMS carries all 19 nodes with their rest rotations and parent indices, two
influences per vertex with weights summing to 1, normals and UVs — what
`tool.exe` compiles into a `gbxmodel`. Node names are written with underscores
(`bip01_pelvis`) because JMS is whitespace-delimited text and a space would cut
the name short; the `.blend` keeps Halo's original names with spaces.

## Running it without the launcher

```
"C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" -b --factory-startup ^
  --python rig_items.py -- --items extracted --rig "rig\master chief skeleton.blend" ^
  --fp "rig\fp arms.blend" --out rigged
```

Options: `--no-fbx`, `--no-jms`, `--name NAME`, `--items DIR`, `--out DIR`.

Exit codes are the script's return value: 0 rigged, 2 no skeleton, 3 nothing to
rig.

## What it does not do

* **No recolouring.** Multiplayer armour colour is applied by the game's shader
against the item's DXT texture. This pass does not dye geometry or rewrite
textures, so an MP item keeps the colours baked into its texture.
* **No hand weighting for the head.** The biped has no jaw, eye or finger bones;
items rigged to it follow `bip01 head`, `bip01 l hand` and so on. The FP arms
mesh keeps its own 37-bone `frame` rig for the fingers.
* **No animation.** Only the rest pose is written. Animations come from Halo's
JMA files once the model is compiled.

## Note on the other README

`README.md` describes the extractor and its `.obj` output. Its line "No rigging
or posing" refers to those `.obj` files, which are plain geometry by design;
the rigged copies are the ones described here.
