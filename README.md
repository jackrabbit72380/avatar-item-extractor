# Avatar Item Extractor

Put your Xbox 360 avatar items beside `Extract-AvatarItem-v29.bat` - one folder
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

Needs Python 3.8+. Blender 5.2 or newer makes the rigging files: the two
rigs it ships were saved by 5.2, and 4.x cannot open them.

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
        Test Item - halo.fbx  the rigged model, once Blender has run; also
                       - halo fp arms, - NXE and - unrigged, copied out of
                       the Blender folder
        master chief skeleton.fbx  Halo's biped, for repairing a binding by hand
        Test Item base map.png  also .tga  - the texture the model binds
        Test Item multipurpose.png  also .tga  Halo CE channel order
        Test Item multipurpose xbox.png  also .tga  Xbox channel order
        Test Item multipurpose sp.png  also .tga  nothing masked
        Test Item change colour.png  also .tga  the team-colour mask
    extracted for blender users\
        Test Item - halo.blend  the item on Halo's biped, ready to export
        Test Item - halo.fbx  the same rig for tools that cannot read .blend
        Test Item - halo fp arms.blend, .fbx  the item's arms on Halo's
                        first-person arms rig; every item gets this pair
        Test Item - NXE.blend, .fbx, .glb  the 71-joint NXE skeleton
        Test Item - unrigged.blend, .fbx  the model with no skeleton
        the same textures as the Max folder, so a rig opens with its maps
        source rigs\  master chief skeleton.blend, fp arms.blend  Halo's own
                       rig files, kept for repair
    extracted for hek users\
        pc\data\Test Item\
            bitmaps\    Test Item base map.tif, Test Item multipurpose.tif,
                        Test Item change colour.tif - Halo CE channel order
            models\     Test Item.jms  the model, for tool.exe
            animations\  empty until there are animation files to put here
            source\     Test Item - halo.blend, .fbx  what the model came from
            fp\         the first-person arms, a model of their own
                bitmaps\  the item's own maps, for the arms
                models\   Test Item - fp arms.jms
                source\   Test Item - halo fp arms.blend, .fbx
        xbox\data\Test Item\
            the same folders, the bitmaps in the original Xbox order
    Test Item.png  the item's icon, when the package has one
    colour_00.png  the item's own palette, when it carries one
    Test Item_colours.txt
    report.txt, blender.log  the run's facts; rigging adds a scene section
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
`extracted for hek users` has `pc\` and `xbox\`, each with `data\<item>\` -
the source directory `tool.exe` is pointed at - holding `bitmaps\` with the
`.tif` files it compiles, `models\` with the `.jms` (in both builds, because the
one text model compiles for either target), `animations\` for animation data,
and `source\` with the `.blend` and `.fbx` the model was exported from. The
first-person arms are a model of their own, so they get their own `fp\` folder
inside the item: `fp\bitmaps\` with the maps they compile against,
`fp\models\` with their `.jms`, and `fp\source\` with their `.blend` and
`.fbx`. There is deliberately no `tags\` in there: `tool.exe` writes its output
to `tags\` at the HEK root, never inside `data\`.
Both channel orders ship because the port and the original Xbox read the masks
differently; nothing is left for you to swap by hand. The `.png` and `.tga`
copies are the same images as the `.tif`s, for the programs that do not read
TIFF.

Halo's own two rig files are the base every item is skinned to, and they are
kept for repair: the `.blend` files are copied, unchanged and under their own
names, into `extracted for blender users\source rigs\`, and the biped also goes
to `extracted for max users\` as `.fbx` for programs that cannot open a
`.blend`. They are in their own folder so they are never mistaken for an item's
file - what sits beside an item is that item's own `- halo.blend`.

Each item gets two Halo sets, because Halo's in-game hands are a separate model
from the body and the player sees the arms, not the body's:

* `Test Item - halo.blend` - the whole item on the 19-bone biped, facing the
  way the game faces, in Halo units, with its textures packed in. Export it
  with the BlueStreak `.jms` exporter, or append another item's `- halo.blend`
  and join the meshes; every item is skinned to the same biped.
* `Test Item - halo fp arms.blend` - the item's own arm geometry (sleeves,
  gauntlets, or the base body's bare arms) on Halo's 37-bone first-person arms
  rig, in that rig's own rest pose. Whole shells are taken, not loose vertices:
  a piece joins the set when most of its weight is on an upper arm, forearm or
  hand bone. Shoulder plates stay on the body: a pauldron is worn over the
  shoulder rather than on the arm, and carried with an arm that turns about the
  joint it leaves its place on the body and stands across the arm as a plate
  that belongs to nothing - which is what the Marine's pauldrons did. It is in
  the item's own `- halo.blend`, where it is worn. The seam falls where the arm
  ends, and no plate is ever cut in half. Each side is then carried onto Halo's rig as one piece: the
  arm's own long axis is turned onto Halo's arm bones, its length is laid along
  them, and the middle of its own sleeve is shifted onto Halo's bone - so an arm
  modelled slightly outboard of its own skeleton still sits centred on Halo's
  instead of hanging that far out. The reach is laid to the end of Halo's
  *fingers*, not to the end of its wriste bone: that bone stops at the knuckles
  while the hand the game draws goes on to the fingertips, and matching the
  knuckles alone left every glove sitting over the palm with its fingers
  stopping dead at Halo's wrist, so a weapon would have been held in front of
  the hand instead of in it. The reach lands a little past those fingertips, so
  the glove encloses the finger bones its fingers ride instead of ending flush
  with them. The side is lined up by its glove on Halo's own hand - the hand is
  what a player watches hold a weapon - and that shift only moves the arm across
  Halo's, never along it, so the reach stays where the scale put it. A bare
  sleeve with no glove is lined up by its middle on the bone instead. One turn and one scale for the
  whole side - sleeve, glove and pad - so every edge keeps its length up to that
  single factor, and a side carried that way cannot tear whatever shape it is.
  (Turning upper arm, forearm and hand by different amounts tore the shell at
  the   joints whatever the blend; that is why it is one similarity now.) A plate
  worn on the arm - a bracer, a gauntlet - is below the joint and turns with
  it, as it should. How far
  round the arm the side sits is answered separately: the shortest turn onto
  Halo's arm leaves the glove rolled however the item was modelled, so a glove
  authored palm-down lands flat across Halo's hand instead of lying in it -
  aligned with the bone and visibly a twist. The glove's own palm normal is
  measured across its arm, Halo's own hand's flat is measured from the arm mesh
  inside `fp arms.blend`, and one turn about the arm lays one in the other;
  being about the arm's own line, it moves nothing off it and still cannot
  stretch an edge. The half turn that is also flat is settled by whichever
  stands closer to Halo's own hand, and a glove too round to have a flat - a
  fist - keeps the roll the item gave it, which `report.txt` says. A bent
  arm keeps its bend.

  The bones say where an arm is jointed; the arm mesh inside `fp arms.blend` says
  how it actually leans - Halo's own sleeve sits a couple of degrees off its
  bone line, and an item's sleeve can lean the other way by ten, which is the
  arm a player sees at the wrong angle. So once a side is placed, its sleeve is
  turned onto Halo's. Both sides are measured the same way, from the skin the
  upper arm and forearm bones hold and never the hand - the glove is weighted
  onto the finger bones once it is carried, so a hand counted on one side and
  not the other left the two measurements describing different things. What is
  fitted is the line between the middle of the sleeve's shoulder end and the
  middle of its cuff, not the cloud's widest direction: a flared cuff or a
  shoulder pad pulls that widest direction a degree or two off the line the arm
  runs, and a fit onto it stops short while reporting nothing left to do. Only
  the turn is fitted, never the size, because the size is what puts the glove
  past Halo's fingertips; each pass is capped at twelve degrees so the arm
  settles instead of swinging past, and the shift is worked out again after each
  pass, so the glove stays on Halo's hand while the sleeve finds the angle the
  game wears. Fitting the whole arm cloud by nearest point was tried first and
  was worse at this: it closes the distance by rolling a fat sleeve without ever
  pointing it the right way. Bands ordered by distance from Halo's shoulder
  instead of along the sleeve were tried too, and are not stable - an item's arm
  does not sit where Halo's does, so "furthest from the joint" is not the cuff,
  and one side came out a quarter turn wrong and inside out.

  Every run therefore prints the angle twice, and the second number is the one
  to trust: `report.txt` gives the sleeve angle against Halo's own arm measured
  by the cloud's widest direction, an estimator the fit never uses, beside the
  fit's own distance. A fit graded by the measurement it optimises always
  reports success, so the two are reported together and the check beside them
  (`tools/test_arms_fit.py`) measures against a direction it chooses itself.

  The glove's thumb is the item's own guard, and it is weighted differently
  from the other fingers because it is a different shape: a plate standing well
  off the bones it was modelled on, not a slim finger lying along them. Distance
  to the nearest bone is no guide there - every vertex of a guard like the
  Marine's is about as far from all three thumb bones - so it is weighted by
  where it lies **along** its own chain, each bone owning its length and handing
  over across a short band at the joint. Measured on the Marine, nearest-bone
  weighting gave `thumb low` 7% of the thumb, `thumb mid` 39% and `thumb tip`
  54% against Halo's own hand's 38/30/32, and because a .jms carries two weights
  a vertex the base bone was dropped everywhere and drove nothing at all: the
  thumb bent from its tip instead of folding from its base. It now holds 9-13
  vertices, and every thumb vertex is on two bones or fewer, so nothing is
  thrown away on export.

  A finger is hand, not forearm. The item gives its glove no hand bone at all, so
  the glove's weight ran up the forearm and only the part faded in at the wrist
  could be given to the fingers - which left the Marine's thumb tip 42% on the
  forearm and upper arm. Halo's own fingers carry no forearm weight, and an elbow
  bend dragged that 42% out of the thumb, so the finger's share of the forearm
  and upper arm is handed over with the hand's, by the same grip fade. The thumb
  tip now carries none.

  The guard itself is left where the item put it, and the report says where that
  is: on the Marine it runs 31-36 degrees off Halo's thumb chain and its middle
  stands 1.5 units past the chain's end, which is why it reads as a fat finger
  lying along the index rather than a thumb set apart from the fingers. Moving it
  onto the chain was tried both ways and is worse both times. Turned about the
  chain's joint it swung the whole guard off the bones (all three thumb bones 1.5
  units outside it); turned about its own base and re-centred on the chain it tore
  the glove where the guard joins it (24 edges past x3) and still left the base
  bones outside. A guard that does not fit the thumb it was given is the item's
  shape, and the one thing that cannot be fixed without re-modelling it.

  A turntable of the glove from ten angles, both hands, is what settled that.
  The guard is an open shell: it closes against the palm only in the place it
  was modelled, so every move that changes its tilt opens its base to the
  camera - a black cavity at the thumb's root from a00, a135 and a180, and a
  dark wedge at a225 to a315, where the unmoved glove shows none. Moving it
  made the one view better and the other nine worse, so it stays where the
  item put it and the weights carry the fix.

  Two more ways of moving it were built and measured before settling on
  that. Sliding the guard down with no tilt at all (0.0 degrees) opens the
  same cavity, and on the right hand it stretches its edges x1.79 - past the
  1.6 limit, so that side refused the move. Wrapping the guard onto Halo's
  own thumb surface vertex by vertex moves 51 of its 59 vertices and keeps
  its edges to x1.42, but a flat plate cannot be folded onto a round thumb:
  it collapses into a horn with a hole at its root, worse from every angle
  than leaving it alone. The guard is a plate and Halo's thumb is a tube,
  and no displacement of one becomes the other.

  What does fix it in the hand is the chain the guard rides. All-thumb
  weighting swings the plate off the palm the moment the thumb bends; all-hand
  weighting leaves the thumb dead. Adding a hand share on top of the thumb's
  weights does not work either - a .jms carries two weights a vertex, so a third
  makes the export drop one the plate was using and the plate tears (posed,
  x5.84). So the guard's chain is carried 1.2 units back past the thumb's base
  and named for the hand bone: its root lands in the palm's own segment, its tip
  still on the thumb's, and every vertex keeps the two bones that straddle it.
  Only the guard's own shell is re-seated - a palm vertex that merely brushes
  the thumb must not be pulled away from the vertices beside it, which is what
  tore the palm at x4.38. Posed at 30/25/20 the worst edge is x2.22-2.25 and a
  full grip x2.29-2.38, with no edge past x3 either way, against x2.49 for the
  thumb left on its own bones. `tools/test_thumb_seated.py` pins it: two weights
  a vertex, the root on the hand and the tip on the thumb, no neighbouring pair
  left without a bone to share, and the root moving under three quarters of what
  it moved before - and it fails when the seating is removed, when the chain is
  not carried back, or when a vertex outside the guard's shell is re-seated.

  Its vertex groups are renamed to Halo's (`frame l upperarm`,
  `frame l forearm`, `frame l wriste`), and a glove the item weighted to its
  forearm alone - an avatar rig has no finger bones - hands over to
  `frame l wriste` along its length, so the glove follows Halo's hand instead of
  swinging from the elbow, and its fingers end where Halo's own do. Past the
  knuckles each glove vertex is weighted onto the two nearest bones of **its own
  finger's chain** - `frame l index`, `middle`, `ring`, `pinky` or `thumb`, each in
  its low/mid/tip bones (the thumb by its place along the chain, see above) - so
  the glove closes round a rifle the way the game's
  hand does, and no weight reaches across to the finger next door. The weight is
  measured along that finger, not along Halo's hand: a glove's fingers stop short
  of Halo's, and measured from the wrist the half of every glove finger nearest
  the knuckle stayed on the hand bone while the rest curled - the bend collected
  in one loop and creased the knuckle. It fades out where the finger is no nearer
  than the hand bone, which leaves the palm on `frame l wriste`.

  A glove is often one surface across two fingers rather than separate fingers:
  the Marine's is a single 226-vertex skin, and the skin between its index and
  middle fingertips belongs to both. Where a vertex is near two fingers the
  weight is shared between the two nearest, in proportion to how close it is to
  each and with a steep enough fall-off that a finger's own middle stays its own.
  Each small piece then commits to the one finger most of its weight is on,
  because a plate or a finger shell split between two fingers pulls itself in
  two as soon as they curl apart.

  The thumb is found by its own chain, not by how far along the hand it lies. It
  sits beside the wrist and never crosses the knuckle line the other fingers do,
  so the hand's own measure put it behind that line: the Marine's whole thumb
  guard stayed on the wriste bone and did not move with the thumb at all. A
  vertex belongs to the thumb when it is nearer the thumb chain than the hand
  bone or any other finger, and it eases in over the first part of the thumb's
  length so it still joins the glove's palm smoothly. Halo's thumb bones sit
  outside the Marine's bulky thumb guard by 0.68-0.96 units - `report.txt` names
  that per bone - so the guard follows the thumb from outside it, as armour over
  a joint does, rather than being left behind.
  Weights cannot tear anything: the geometry is already carried whole. The
  finger room `report.txt` gives is measured on the glove's own vertices, past
  the wrist, and never over the whole arm: a sleeve or a bracer runs further
  along the arm than the hand does, so a whole-arm measurement would report room
  the glove does not have and hide a glove that stopped short of Halo's fingers.
  Each of Halo's finger bones is then measured on its own against the glove's
  own skin, and `report.txt` lists all of them with their side: a negative
  number is how far the bone sits inside the glove, a positive one is how far
  it stands outside. A thumb outside its glove therefore shows up by name
  instead of passing on the hand-wide number, which another finger can satisfy.
  The rig in
  the file *is* Halo's own 37-bone set, so the game's first-person animations
  drive it as they stand. Nothing is modelled again and nothing is retextured:
  faces, UVs, smoothing and
  materials come across as they are. A closed shell the item itself had inside
  out - a sleeve or a glove whose faces wind inward, which shows its own blank
  back to the world - is written the right way round; an open plate is left
  exactly as it was, because there is no inside to measure. A hand item - a
  ring, a badge - rides its
  hand bone instead, whole, on the supplied arms rig. An item with no arm
  geometry at all (a hat) still gets the file, on the arms rig with an empty
  mesh, and `report.txt` says why.

Both `.blend` files carry a `READ ME` text block inside them naming the game,
the rig and the mesh, so the file still says what it is after it is copied out
of the folder.

The `NXE` files need only Blender, because that skeleton travels inside the
`.bat`. The biped, the arms, the `.jms` and the two Halo `.blend` files use
Halo's two rig files, which travel inside the `.bat` as well. If they are
somehow missing, the NXE and unrigged copies are still written and the run says
which files it could not find. If rigging cannot run at all, the reason is
written to `blender.log` in the output folder and the window stays open to say so.

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
push it sideways, off the hand and onto an arm. A whole body is not grown that
way at all - it is fitted to the bones, joint by joint, as the next paragraphs
describe.

A body is the one case a single scale cannot fit, because it is not worn on the
biped: it *is* the thing the bones animate. The Marine armour is a whole avatar
body - 1.51 m of it, modelled in the avatar's T-pose on the avatar's own
skeleton - and its shoulders sit 0.72 m below the biped's. Growing it would
lift the figure and still leave every joint short of its bone, with the biped's
arms hanging through the middle of its chest. So an item that spans more than
0.8 of the 1.4 m body (a whole body, not a hat or a tee) is fitted joint by
joint instead: each of the avatar's 19 joints is carried onto the Halo bone it
belongs to, the bone between two joints is stretched to Halo's own length so the
joint past it lands too, and the mesh around each joint turns with it - which is
how an arm modelled straight out comes down into the pose Halo's skeleton
holds. It is the mesh that is fitted to the skeleton, never the other way round:
Halo's animations carry a node transform for every frame, so a skeleton shrunk
to a short item would be put straight back by the first frame of the game's own
animation.

One size is kept from the item, the one the two skeletons share: its own head
joint goes on Halo's head node. On the Marine that is x1.63 from the item's own
metres (x1.20 on top of the x1.36 fit), which puts the armour at 2.46 m - the
biped's own height, because the armour is a child avatar's body and its helmet
is proportionally large. Its 19 bones all end up inside the armour, the nearest
surface 0.2-5.4 units away, and the worst edge anywhere is x6.45, at the
armpit, where an arm modelled out to the side is turned 79 degrees down. Nothing
is cut and nothing is re-modelled: it is the same 5,294 vertices.
`tools/test_body_fit.py` stands a body on the avatar's own joints and pins it:
every joint lands on its bone to the last decimal, every bone ends Halo's length
to within 1%, both arms lie along Halo's arm bones, the helmet rides the head and
the soles end on the floor - and each check is run again against a fit that
drops the turn, the length stretch or the leaf caps, and has to fail there.
`report.txt` records it as `biped fit : 19 joints carried onto their bones,
x1.195, 2.46 m tall, worst edge x6.45`.

The first-person arms are cut from the body as it was before the fit, so the set
that was tuned to Halo's fingers keeps the geometry it was measured on: fitting
the body first would have moved every glove away from the bones it rides.

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

When an item states no colour at all - no colour table, no batch colour and no
texture of its own - the colour is taken from its own icon, the closet thumbnail
it ships with: the page the item sits on and its near-black outline do not vote,
and what is drawn is averaged. `report.txt` says where the colour came from, and
only an item with no icon either falls back to clay `#CCCCCC`. An item that
carries a base map never needs it: its own pixels paint the base map, the `.mtl`
and the blend.

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

That table is where an item's colours actually are, and reading it is not
optional: a garment ships its whole look as three slots - a base colour map, a
tint mask and a decal - and every material names which slot each one comes from
(id 1 base, 2 mask, 3 decal). The Marine armour's base map is a 256x128 DXT1
sheet of olive plates, khaki fatigues and dark straps, and its tint mask is a
32x32 DXT5 that becomes the multipurpose map's colour-change channel. Two things
had to be right to read them: the pixels are the *compressed* size the slot's
format implies (half a byte a texel for DXT1, one for DXT5), not the padded
`bytes a frame` in the header - a 32x32 mask says 4,096 there and stores 1,024 -
and they are tens of kilobytes, so they cannot be read through the bit reader the
meshes use. Reading the padded size walked off the table and lost every slot after
the first; `tools/test_model_texture.py` pins both, and the third slot is read
after an empty one to prove the walk keeps its place.

Each item also gets the packed mask bitmap `shader_model` wants, in both channel
orders, plus the team-colour mask on its own as
`<stem> change colour.png/.tga/.tif`. Halo CE (the Gearbox port and the HEK that
builds its bitmaps) keeps the channels in this order - the original Xbox order
is different, so both are written rather than leaving you to swap channels:

| | red | green | blue | alpha |
|---|---|---|---|---|
| Halo CE | detail mask | self-illumination | specular | colour change |
| Xbox | specular | self-illumination | colour change | detail |

  * `<stem> multipurpose.*` - Halo CE order. The colour change mask comes from
    the item itself, in this order: its own tint mask texture when the model
    binds one; otherwise the painted base texture's own islands (anything not
    transparent and not black); and only failing both, the UV coverage. The
    report's `mask source:` line says which was used. A part that must keep its own colour
    needs painting black there. The `.png` is 1024x1024 and a few kilobytes; the
    `.tga` and `.tif` are the same mask at 256, because uncompressed at 1024 they
    are 4 MB each and 256 is what a bitmap compiled by `tool.exe` uses anyway.
    Detail, specular and self-illumination are zero, because an item does not say
    which parts are shiny, glow or take a detail map, and inventing that would
    be a guess.
  * `<stem> multipurpose xbox.*` - the same masks in Xbox order, for H1A with the
    shader's "og xbox channel order" flag (0x40) set. Halo CE and the legacy HEK
    always read Gearbox order, which is why the first set is not a substitute.
  * `<stem> multipurpose sp.*` - single player. Nothing is masked, so the item
    keeps the colour it was drawn in. Every channel is zero, which makes the
    image valid in either order: one set covers both, so it is written once.

The masks are the same four channels either way; only which channel holds which
mask moves, and the colour change channel is the team colour. The mask follows
the UV set the item's base-colour material names, which is the space the shader
samples the base map and the mask in together.

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
python3 tools/payload.py unpack Extract-AvatarItem-v29.bat src/
# edit src/extract_items.py, then put it back - --rigs is not optional:
python3 tools/payload.py pack Extract-AvatarItem-v29.bat src/ --rigs src/rig
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
