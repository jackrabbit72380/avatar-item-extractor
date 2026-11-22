# Avatar Item Extractor

Put your Xbox 360 avatar items beside `Extract-AvatarItem-v20.bat` - one folder
per item, named after its container, as they arrive from a download - then
double-click it. That is the whole procedure: it finds the items itself and
writes everything each one needs - models, textures, masks, colours, rigs -
named after the item, beside the `.bat`. It also rigs them onto Halo CE's biped,
first-person arms and the NXE avatar skeleton.

An item can be given however you have it: loose `asset.bin` / `asset_v2.bin`, or
the marketplace package itself - the file named after the item's GUID, with no
extension. A package holds the same item more than once, and the newer copy is
the one read: the one carrying the versioned metadata block, checked by actually
parsing each copy rather than by position. The report says which copy was used.

A folder holding both `asset.bin` and `asset_v2.bin` gives one item, not two:
they are the same part in two formats, so the newer revision is the item and the
older copy is skipped before it is read.

It reads the folder the `.bat` sits in and the folders under it, three levels
deep, and writes everything to `extracted\` there.

You can give items as containers or as the bins inside them; both work. An
item's name comes from, in order: the closet index if there is one, the
package's own Title, then the folder it arrived in - which is the container's
name. `asset.bin` and `asset_v2.bin` say what format the bytes are, not which
item they are, so they never name the output. When the bins are on their own and
nothing else names the item, it becomes `extracted1`, `extracted2` and so on,
numbered across the run, so two items never share a name.

Needs Python 3.8+. Blender 4.x makes the rigging files.

Halo CE's two rig files - `master chief skeleton.blend` and `fp arms.blend` -
travel inside the `.bat` and are unpacked to
`%LOCALAPPDATA%\AvatarItemExtractor\rig` on the first run, so there is nothing
to download or place beside it. Files you put in a `rig\` folder beside the
`.bat`, or beside the `.bat` itself, are used instead when they are there.

## Output

```
Test Item\
    extracted for max users\
        Test Item.obj  plus .mtl
        Test Item.fbx  the rigged model, once Blender has run; also - fp arms,
                       - NXE and - unrigged, copied out of the Blender folder
        Test Item base map.png  also .tga  - the texture the model binds
        Test Item multipurpose.png  also .tga  Halo CE channel order
        Test Item multipurpose xbox.png  also .tga  Xbox channel order
        Test Item multipurpose sp.png  also .tga  nothing masked
        Test Item change colour.png  also .tga  the team-colour mask
    extracted for blender users\
        Test Item.blend  on the biped with the FP arms, ready to export
        Test Item.fbx  the same rig for tools that cannot read .blend
        Test Item - fp arms.blend, .fbx  hand items: the item on the arms
        Test Item - NXE.blend, .fbx, .glb  the 71-joint NXE skeleton
        Test Item - unrigged.blend, .fbx  the model with no skeleton
        the same textures as the Max folder, so a rig opens with its maps
    extracted for hek users\
        pc\data\    Test Item base map.tif, Test Item multipurpose.tif,
                    Test Item change colour.tif - Halo CE channel order
                    Test Item.jms  the model, for tool.exe
        pc\tags\    where tool.exe writes what it builds
        xbox\data\  the same bitmaps in the original Xbox channel order
        xbox\tags\
    Test Item.png  the item's icon, when the package has one
    colour_00.png  the item's own palette, when it carries one
    Test Item_colours.txt
    card_art.png
    report.txt, scene.json, skeleton.json, blender.log
    catalogue.json
```

"Test Item" is whatever your item is titled: the closet's name, the package's
Title, or the container folder it arrived in. One item gets a folder named after
it, next to `extracted\`; several items share `extracted\`, each file carrying
its item's name. Either way it is one double-click for the whole folder.

The folders are named for who they are for, not for the program's own name, so
it is clear at a glance which one to open: `extracted for max users` has the
model, its `.fbx` when Blender ran, and its textures already beside it;
`extracted for blender users` has the rigs with the same textures; and
`extracted for hek users` has `pc\` and `xbox\`, each with `data\` holding the
`.tif` bitmaps `tool.exe` compiles plus an empty `tags\` for what it builds.
Both channel orders ship because the port and the original Xbox read the masks
differently; nothing is left for you to swap by hand. The `.png` and `.tga`
copies are the same images as the `.tif`s, for the programs that do not read
TIFF.

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

An item is modelled where it is worn, and that is where it stays: a beret sits
at 1.40 m, a tee at 0.91 m, a ring 0.63 m out to one side, at a hand. The
position is the item's own, so a ring finds the hand by itself instead of landing
on whatever bone happens to be near the middle of the body. The `NXE` copy uses
those coordinates unchanged, because they are the avatar's own - a tee comes to
rest 16 mm from the spine joint and a ring 35 mm from a finger.

The Halo copies are grown to the biped, which is a 1.91 m Spartan against the
1.4 m body the items are authored on. One uniform factor, measured from the
biped's own floor-to-head height, lifts a beret onto the head and a tee's top to
`spine1`. Cloth grows from the floor. A solid prop grows where it stands: its
position belongs to the hand wearing it, and growing it from the ground would
push it sideways, off the hand and onto an arm.

Halo's body and hands are separate models, and the fingers exist only on the
arms. An item whose nearest bone is a hand - a ring, a wristband - therefore also
gets its own copy on the arms, bound to the finger it belongs to. `report.txt`
names all three bindings: the avatar joint, the biped bone, and the arms bone.

Each `.blend` is a saved scene holding just that one model, so it opens straight
onto the item rather than onto the whole rigging session.

`colour_00.png` draws the item's colour table the way the editor pages it, the
base colour first and then the swatches, three chips across, and `_colours.txt`
lists the same colours as `base` / `swatch1..9` with hex and 0..1 triples. A
container with no colour table still gets the text file, saying so.

Whether an item was a team-colour item is **not recorded in the file**, so
nothing here decides it: `catalogue.json` records what the item holds
(`colour_table.present`, `colour_table.swatches`) and every item gets the files
for both builds. Use the base map alone for a fixed colour, or the base map with
the multipurpose map for a team colour.

The `.jms` is written in Halo CE's own layout, taken from the game's exporter
(BlueStreak 1.0.4): positional fields, no section markers, one vertex per
triangle corner, and the texture coordinate on the vertex line as `u v w`.
That is the slot Halo's shader tags read - one per vertex, which is all a
`gbxmodel` vertex stores.

Every `.jms` is then read back by `jms_check.py`, which walks it by its counts
the way `tool.exe` has to: the header, the node block and the hierarchy its
child/sibling links describe, each corner's two node slots and their weights, the
`u v w` slot with `w` at zero, and the faces against the vertex, material and
region counts. The result is logged as it is written and recorded in `report.txt`
as `jms check : ok`. That proves the file is well formed - only the compiler can
prove `tool.exe` accepts it.

The `.obj` carries the UV set the item binds its first texture slot to, because
that is all an OBJ can hold. The item's other sets travel in `catalogue.json` and
become real layers in the `.blend` - `uv0`, `uv1`, `uv2` - so a map that belongs
on a later set has somewhere to go.

Every item also gets an image to bind, in `.png`, `.tga` and `.tif`: the decoded
base map when the container carries a texture, and otherwise its own colour as a
flat 64x64 image, `<stem> colour.*`. The `.mtl` names it with `map_Kd`, so the
colour survives import in Max and Blender rather than being dropped along with
`Kd`, and the `.tif` is a bitmap source for Halo CE's tool.

Every block the container held is named in `catalogue.json` and in `report.txt` -
its id, its name and its size - and the two that say what an item *is* are read,
not just listed: the metadata block gives its gender, asset type, component and
subcategory, the shape block gives the body triangles the item hides and the
vertices it moves, and a prop's skeleton block gives its bones and its tree. No
block is written out as a raw file: the bytes stay in the container, and a block
this build has no reader for is named with its size, so a missing texture can be
looked at rather than guessed about.

The base map comes from the model block's own texture table first - the item
names its slots there and each slot states its size, format and whether it holds
anything - and only falls back to a texture kept in its own block when the model
has no table at all. A table of empty slots means there is no base map to write,
and the report says so.

Each item also gets the packed mask bitmap `shader_model` wants, in both channel
orders, plus the team-colour mask on its own as
`<stem> change colour.png/.tga/.tif`. Halo CE (the Gearbox port and the HEK that
builds its bitmaps) keeps the channels in this order - the original Xbox order
is different, so both are written rather than leaving you to swap channels:

| | red | green | blue | alpha |
|---|---|---|---|---|
| Halo CE | detail mask | self-illumination | specular | colour change |
| Xbox | specular | self-illumination | colour change | detail |

  * `<stem> multipurpose.*` - Halo CE order. The colour change mask is white for
    the whole item, so all of it takes the player's colour; a part that must keep
    its own needs painting black there. Specular and self-illumination are zero,
    because an item does not say which parts are shiny or glow and inventing that
    would be a guess.
  * `<stem> multipurpose xbox.*` - the same masks in Xbox order, for H1A with the
    shader's "og xbox channel order" flag (0x40) set. Halo CE and the legacy HEK
    always read Gearbox order, which is why the first set is not a substitute.
  * `<stem> multipurpose sp.*` - single player. Nothing is masked, so the item
    keeps the colour it was drawn in. Every channel is zero, which makes the
    image valid in either order: one set covers both, so it is written once.

The masks are the same four channels either way; only which channel holds which
mask moves, and the colour change channel is the team colour.

Parts keep their own colours when the item states them: each mesh batch is its
own material with its own `Kd`, and when the batches differ, each gets its own
flat colour image instead of one image painting them all alike.

`report.txt` says the same in plain text: the blocks, the mesh counts, the
texture slots the model declares, whether a base map and a colour table were
found, and each part's shader and texture bindings. The extractor writes it
before any Blender runs, so a run without Blender still describes the file;
the rigging section is added underneath it when Blender is there.

## Working on the extractor itself

Neither script is needed to run the tool.

```sh
python3 tools/payload.py unpack Extract-AvatarItem-v20.bat src/
# edit src/extract_items.py, then put it back - --rigs is not optional:
python3 tools/payload.py pack Extract-AvatarItem-v20.bat src/ --rigs src/rig
```

`pack` decodes its own output and refuses to write unless it matches the files it
was given, so a half-written rebuild cannot be shipped.

Leaving out `--rigs` used to pass that check, because it only compared what it
had packed: the rebuild silently lost Halo's two `.blend` files and shrank from
674 KB to 82 KB. `pack` now compares the rebuild against what the shipped file
already carries and refuses to write if anything would go missing.

```sh
python3 tools/test_all.py
```

Unpacks the payload the `.bat` actually ships and runs every test against it, so
a suite that passes proves something about the file people run. Needs no Blender
and no build beside the repository; names any test that fails and exits non-zero.
It does not cover the Blender passes themselves - the rigging tests use a
stand-in `blender.exe`, so a real Blender run is still yours to do.

```sh
python3 tools/test_pipeline.py
```

Runs the modules the `.bat` actually ships against a synthetic container and
checks the files the extractor owns: `.obj`, `.mtl`, the base map or colour image
in three formats, `colour_00.png`, the hex list, `catalogue.json`, and the three
mask sets - including the channel each mask actually lands in, because the two
channel orders differ in exactly two channels and a copied set passes a
name-only check while rendering wrong in H1A.

```sh
python3 tools/test_strb.py
```

Checks the block walk: entries wider than one byte, and the zero fill a real
container carries after its last block, which must not be read as a run of empty
blocks.

```sh
python3 tools/test_blocks.py
```

Checks the two blocks that say what an item is: metadata (gender, asset type,
component, subcategory, and the skeleton in the versioned form) and shape
overrides (the target body, the triangle numbers read back as written, and the
vertex overrides), and a skeleton's bones and parent tree. A truncated metadata
block, a shape block with a non-zero reserved word and a skeleton that does not
end on its last bone must all be refused, because that is what a misread looks
like.

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
