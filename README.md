# Avatar Item Extractor

Put your Xbox 360 avatar items beside `Extract UNSC Marine Armor Avatar-v96.bat`
- one folder
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
        Test Item base map + decal.png  also .tga  the same base map with the
                        item's decal blended over it by its own alpha - this
                        is what the .blend binds, and what a Halo CE build
                        needs, because the shader has one colour layer
        Test Item slot 2 decal map.png  also .tga  a texture the item binds,
                        written as it came out of the model, colours and all
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
        pc\data\Test Item sp\
            the faithful build: the base map exactly as the pack stores it, and
            a multipurpose map that masks nothing. This is the folder to compile
            when the item should look like itself.
            bitmaps\    Test Item base map.tif, Test Item multipurpose.tif,
                        Test Item change colour.tif, Test Item slot 2 decal
                        map.tif, and Test Item base map + decal.tif
            models\     Test Item sp.jms  the model, named for the build
            animations\  empty until there are animation files to put here
            source\     Test Item - halo.blend, .fbx  what the model came from
            fp\         the first-person arms, a model of their own
                bitmaps\  the same maps, for the arms
                models\   Test Item sp - fp arms.jms
                source\   Test Item - halo fp arms.blend, .fbx
        pc\data\Test Item sp-decals\   the same with the decal baked in
        pc\data\Test Item mp\          the team-colour mask bound
        pc\data\Test Item mp-decals\   team colour and decal
        xbox\data\  all four again, in the original Xbox channel order: the
                    team colour sits in blue there, not in alpha

    The four builds are independent because the two choices are: Halo CE's
    shader_model samples one colour layer, so a decal is baked into the base map
    or absent, and the team colour is a channel of the multipurpose map. Each
    folder is a complete data\ directory with its own model and JMS material
    names, so tool.exe writes four sets of tags instead of overwriting one.
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
Each `.jms` writes every bone in its parent's space, because that is where Halo
keeps a node: the marines' own model has its calf 15.87 along its thigh's axis,
not at the calf's height above the floor. Written in the model's space instead,
`tool.exe` builds the skeleton with every bone hung off the origin - a pile of
garbage bones and no model in the viewer. The skeletons here rebuild from their
`.jms` to within 0.00005 units of the armature they came from, and
`tools/test_jms.py` fails if a node is ever written in the model's space again.

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
sheet of olive plates, khaki fatigues and dark straps; its 32x32 tint slot is
blank, and the colour-change mask is the alpha channel of the 256x128 map in its
decal slot, which is also where the greyscale detail art lives. Two things had
to be right to read them: the pixels are the *compressed* size the slot's
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

Two corrections to that table, from the tag reference itself
([shader_model](https://c20.reclaimers.net/h1/tags/shader/shader_model)):

  * **Red is an auxiliary mask, not a detail map.** It only becomes the detail
    mask when the shader's *detail mask* field is set to *auxiliary mask*; the
    detail map itself is a second bitmap with `detail map` usage, and the shader
    blends it by one of three functions (double biased multiply, multiply,
    double biased add). This item carries no detail bitmap, so red is left black
    and the detail slot is unused.
  * **Blue is cubemap specularity**, not the reflection mask of an environment
    shader: full blue is the strongest reflection, black is none, and it needs a
    reflection cube map bound to do anything. No cube map is written here, so
    blue is black.
  * **Green is self-illumination, "used for lights on the model"** - it is added
    to diffuse light and then multiplied by the diffuse colour, so a black texel
    cannot glow. This item's data has no emission map of any kind, so green is
    black: its "lights" are painted into the base map, not lit.

**There is no bump map field in shader_model.** Halo 1's bump maps belong to
shader_environment (bitmaps compiled with `height map` usage and turned into
normal maps), so an armour item cannot have one: the model shader's only maps
are base, multipurpose, detail and the reflection cube map. Making a bump
bitmap for this item would produce a tag nothing can reference.

The decal is likewise not a shader input: `shader_model` samples one colour
layer, so the item's decal is blended into the base map by its alpha
(`base*(1-a) + decal.rgb*a`) in the `-decals` builds, and left out of the plain
ones.

  * `<stem> multipurpose.*` - Halo CE order. Colour change is the team colour,
    and the only thing an item states about it is its **tint mask** - a material's
    parameter id 2, written beside the base map as `slot <n> tint mask`. The
    avatar shader reads that mask as
    `lerp(base, red*C1 + green*C2 + blue*C3, alpha)`: red, green and blue pick
    which of the player's three custom colours a texel takes, and alpha is how
    much of it shows. Halo CE holds one team colour in the multipurpose alpha, so
    the alpha is the amount; an item that marks whole regions by colour and
    leaves alpha flat tints everywhere a weight is set. A blank tint slot states
    no colour change, and the item's colour table is the other half of the same
    fact: the avatar rule is `lerp(base, r*C1 + g*C2 + b*C3, a)`, with C1-C3 the
    item's three custom colours, and it is **untinted when the item has no colour
    table** (open-avatar-lib `docs/FORMATS.md` 3.6, which cites the game's own
    shader and All-Stars Avatar's `avatar_colours.py`). The Marine armour has
    both: a 32x32 tint slot with one texel set, and no colour-table block at all.
    So its exact mask is **black**: nothing tints, and `report.txt` says that in
    its `mask source:` line instead of inventing an amount from the base map. Two earlier versions did invent one; the second graded the suit to a
    third of the colour and still was not the item's data, so it is gone from the
    default path.

    A team colour is then a deliberate choice, and `extract_items.py --tint`
    takes it: `full` (every painted texel), `derived` (the armour/cloth rule
    below) or a path to a black-and-white PNG of your own. report.txt names the
    file as authored whenever one is used. The rule behind `derived`, for
    reference: cloth share = warmth (red above blue) x brightness, blurred two
    texels - the plates are dark near-neutral olive at (60, 56, 49), red minus
    blue 11, the cloth warm at 35, so the plates take 1.0 and the cloth 0.32.
    `tools/tint_preview.py` writes the base map out under a few team colours
    beside the mask, so an authored mask can be judged before it is compiled.
    The one-click .bat takes the same choice without a command line: a file
    named `tint_mask.png` beside it becomes `--tint` that file, and
    `tint_mode.txt` can say `full` or `derived` instead. With neither, nothing
    tints and the report says why.

    The slot beside the tint mask (parameter id 3) is a **decal**: artwork blended
    over the base map by its own alpha, a tee's logo. It is never read as a mask.
    The Marine armour's decal alpha covers two thirds of its canvas as a soft
    blend - a decal cutout, not panels - and treating it as a team-colour mask
    tinted most of the suit on no evidence at all. It is blended into a copy of
    the base map anyway, because that is the only way it can reach Halo CE:

        colour = base * (1 - alpha) + decal.rgb * alpha

    which is what both readers of the format do (open-avatar-lib's
    `avatar_bake.c` and All-Stars Avatar's `avatar_compose.py`). The decal has
    no channel of its own: open-avatar-lib's `docs/FORMATS.md` section 3.6 says
    so in one line - "id 3 a decal with alpha", then "the decal by its alpha" - and
    the tint mask is the item texture that is read as channels (red, green and
    blue pick which custom colour, alpha is the amount). Halo CE's
    `shader_model` samples one colour layer and cannot blend a second texture at
    run time, so `<stem> base map + decal.*` is the map for the game, the plain
    base map stays exactly as it came out of the pack, and the .blend binds the
    blended one. The decal is read in the UV set whose layout its artwork
    actually traces: the Marine's record names set 2, where it covers 9% of the
    body's triangles, against 34% in the base map's set - so it is sampled where
    the artwork was painted, and carried across the geometry when it really does
    belong to another set.

    The `.png` is 1024x1024 and a few kilobytes; the `.tga` and `.tif` are the same
    mask at 256, because uncompressed at 1024 they are 4 MB each and 256 is what a
    bitmap compiled by `tool.exe` uses anyway. Detail, specular and
    self-illumination are zero, because an item does not say which parts are
    shiny, glow or take a detail map, and inventing that would be a guess.

    The mask is read in **the base map's UV set**, because that is the space the
    shader samples it in. A tint mask painted in another set is decided by where
    its pixels actually cover the item, not by the set the material's record
    names: one that covers the body better in its own set is carried across the
    geometry into the base map's set, so the tint still lands where the base map
    shows it.

    The mask is in **the channel the shader reads** - alpha for the CE set,
    blue for the Xbox set. The `.png` and the `.tga` also paint it into colour,
    so an ordinary viewer shows the mask instead of a black square that looks
    like a broken one. The `.tif` is the file `tool.exe` compiles, so it carries
    the channel alone and stays black in an RGB viewer: open the `.png` beside
    it, or read `mask coverage:` in `report.txt`, for the fraction that takes
    the team colour. `multipurpose sp` is zero in every channel by design - it
    looks black because nothing is masked.
  * `<stem> slot <n> tint mask.*`, `<stem> slot <n> decal map.*` - the item's
    own other textures, written as they came out of the model: real colour, real
    alpha, no resampling. The team colour is read out of the tint mask, and both
    are worth looking at beside the mask file, because a mask is black wherever
    it masks nothing. A slot holding one flat value everywhere is blank (the
    Marine armour's 32x32 tint slot is) and the report names it instead of
    writing another black image.
  * `<stem> multipurpose xbox.*` - the same masks in Xbox order, for H1A with the
    shader's "og xbox channel order" flag (0x40) set. Halo CE and the legacy HEK
    always read Gearbox order, which is why the first set is not a substitute.
  * `<stem> multipurpose sp.*` - single player. Nothing is masked, so the item
    keeps the colour it was drawn in. Every channel is zero, which makes the
    image valid in either order: one set covers both, so it is written once.

The masks are the same four channels either way; only which channel holds which
mask moves, and the colour change channel is the team colour. The mask follows
the UV set the item's base-colour material names, which is the space the shader
samples the base map and the mask in together - and the images are written with
v running down the picture, the way the pack stores its textures, so a mask sits
on the base map's own islands rather than on their mirror image.

Parts keep their own colours when the item states them: each mesh batch is its
own material with its own `Kd`, and when the batches differ, each gets its own
flat colour image instead of one image painting them all alike.

`report.txt` says the same in plain text: the blocks, the mesh counts, the
texture slots the model declares, whether a base map and a colour table were
found, and each part's shader and texture bindings. The extractor writes it
before any Blender runs, so a run without Blender still describes the file;
the rigging section is added underneath it when Blender is there.

## Putting an avatar's own head under an item

An item is a shell: the game's own model has no head, because every player wears
the same one. So a whole-body item has a helmet with nothing inside it, and the
face is a hole. `--port` fills it from the avatar's own export:

```
python rig_items.py --items extracted --out extracted \
    --rig "master chief skeleton.blend" --fp "fp arms.blend" \
    --port MyAvatar.glb
```

A double-click finds it too: put `MyAvatar.glb` beside the `.bat` and every
whole-body item in that run gets its head, the same way `tint_mask.png` beside
it becomes the team-colour mask. The command above is the manual route, for
running the rigging pass again over items that are already extracted.

`MyAvatar.glb` is the file 360sona gives you. Three of its meshes matter: the
head, the face (the same head again, split into two patches either side of the
face so the eyes and mouth can carry more detail), and the small patch of neck
an armour leaves bare. Those are taken. The copy of the item the export carries
- its own armour, already placed on the avatar - is left out by name, because
the item being rigged is in the run already, and it is the one that keeps its
textures, UVs, masks and decal.

Two things are deliberately not carried across:

- **Vertex colour.** Every vertex in the export has one, but it is baked
  lighting rather than paint: 94% of the head's vertices sit at 0.90 or
  brighter, and the few that are darker are the mouth and chin. Halo lights the
  model itself, and the armour the head sits under has no vertex colours at all,
  so keeping them would light the face twice and from the wrong direction.
- **Roughness, metalness and specular.** The export stores one colour per
  texel and nothing else. A default Principled BSDF still gives that colour a
  0.5-roughness sheen and a half-strength specular highlight, which reads as a
  shiny mask on a painted face. The ported materials are therefore set fully
  rough, non-metallic and with no specular, which is what Halo's
  `shader_model` does with a base map. Blender's own view transform also
  plays a part: `Standard` shows the texture as authored, `AgX` (the 5.x
  default) washes it towards grey.
- **The export's skeleton, weights and joints.** The head is bound to the biped
  and to the NXE skeleton by the same `skin()` pass as the item, so it needs no
  name map, no weight transfer and no retarget table: the joints that carry the
  armour carry the face, and it stays in its helmet when the biped animates.

The export is already in the space items are authored in - y-up metres, the
avatar's own T-pose - so the head needs no scale and no offset. It lands where
the avatar's head is, which is where the item's collar expects it. Only the
texture coordinates are flipped once, because glTF runs them top-down and this
pipeline runs them bottom-up.

Its proportions are put back afterwards. A whole body is fitted joint by joint,
and the head straddles two of those joints - the neck and the head - whose bones
the fit scales and turns by different amounts, so a face blended between them
comes out stretched: measured, 6.7% wider and 3.5% shorter than the file's own
head, which reads as a squashed face with the brow down on the eyes. The port
restores the export's own width and depth at the height the fit gave the head,
and moves only the ported vertices - after that correction the head's
width-to-height ratio matches the export's to four decimals (0.7275 against
0.7274) and its depth-to-height to the same (0.9034 against 0.9034). The face is static geometry: no blink, no eye
movement, nothing that needs an animation to look right from outside.

What a ported item gains:

- `<stem> face.png` and `<stem> body_0.png` beside the item - the two images the
  export carries, byte for byte, packed into the `.blend` like every other
  texture.
- `<stem> face.tif` and `<stem> body_0.tif` in `bitmaps` **and** `fp\bitmaps` of
  every build, so each HEK folder carries everything it needs by itself.
- Two more materials in every `.jms`, named `face` and `body_0`, taking the same
  `_sp`, `_sp_decals`, `_mp` and `_mp_decals` suffixes as the item's own.

The armour is not touched. With and without `--port` its geometry comes out
identical to the last bit - all 4,876 triangles, 0.000000 units of movement -
because the fit is driven by joints, and the head only supplies one more cap.

With `MyAvatar.glb` beside the `.bat`, `--keep-shape` and `--eyes-forward` are
asked for as well, because those are the two things that keep the model looking
like the avatar it came from: its own proportions, and pupils drawn in the
middle of its eyes. `keep_shape.txt` and `eyes_forward.txt` still request them
on their own, and `rig_items.py` run without the flags gives the plain fit.

`--port` is used only for a whole body, an item that reaches 1.45 m or more. A
hat or a tee is worn on the catalogue's body, which brings its own head, and two
heads under one item is not a smaller mistake than none. `report.txt` says which
of the two happened.

### Eyes that look forward

A painted face keeps its gaze in the paint, and these faces are drawn as one
stroke per eye: a thin tail at one corner that swells into the pupil at the
other, so the pupil is painted wherever the artist wanted the avatar to look
and under a helmet he looks there in every frame. Nothing in the mesh or the
UVs moves it, and nothing in them can fix it.

The head's UVs were measured on the file: `du/dx` is positive on both sides of
the nose, so they run left to right on both eyes and do **not** mirror. The
drawn pair is itself mirrored, so a straight copy of one eye into the other
comes out with both lash tails on the same side of the nose and both lids on
the same slant - a pair that does not match.

The pupil is the heavy end of that same stroke, so it cannot simply be trimmed
off: a lid left behind by a removed pupil is a hairline where a bold, sharp
stroke was painted. The eye is drawn at 512 texels too - about seventy by
twenty of them - so cutting it about a texel at a time leaves a staircase,
which is what the earlier attempts looked like on the head.
`--eyes-forward` (or an `eyes_forward.txt` beside the `.bat`) therefore measures
the drawing and draws it again, finer:

  * the lash's centre line is a curve fitted through the stroke's painted top
    edge, so it keeps the shape it was drawn with and loses the steps,
  * its weight is the weight the stroke was painted with where it was not
    swollen, so the bold line stays bold, and it tapers to a point at both
    corners,
  * one pupil is a **circle**, as big as the room under the lash allows and
    sunk just far enough that the lash cuts its top off, in the eye's own ink:
  * both are sampled six times per texel and averaged down, which is what makes
    their edges smooth instead of stepped, and the finished eye is stamped into
    both drawn eyes, **mirrored into the second**. The head's UVs were measured
    on the file: `du/dx` is positive on both sides of the nose, so the UVs do
    not mirror, and two straight copies would put both lash tails on the same
    side of the nose. Mirrored, the pair matches across the nose.

It is off unless asked for, because it edits the avatar's own art rather than
the item's. Verified on the Marine face: one pupil, centred at 0.50 of the eye;
the lash's top edge on the painted row for every column it could be compared
on; the second eye the exact mirror of the first.

```
python rig_items.py --items extracted --out extracted \
    --rig "master chief skeleton.blend" --fp "fp arms.blend" \
    --port MyAvatar.glb --keep-shape --eyes-forward
```

## Keeping the item's own shape

A whole-body item is fitted to the biped **joint by joint**: every joint the
avatar's skeleton declares is carried onto Halo's bone for it, and the bone
between two joints turns the mesh with it. That is what makes an item match
Halo's animations - and it is also what changes its shape, because Halo's biped
is a realistic 1.9 m body and a 360sona avatar is not.

Measured on one real avatar and its Marine armour, the fit moved the mesh this
far:

| segment | as authored | after the fit | |
|---|---|---|---|
| torso, pelvis to spine1 | 4.1 units | 7.4 units | **x1.80** |
| upper arm | 7.6 | 10.8 | x1.42 |
| forearm | 6.9 | 11.3 | x1.64 |
| thigh | 12.0 | 17.2 | x1.43 |
| shin | 11.7 | 15.4 | x1.32 |
| neck to head | 5.3 | 1.7 | **x0.32** |

A body whose torso nearly doubles and whose neck is crushed to a third is not
the model its author made. `--keep-shape` is for that: it carries the item
through at 1:1 metres and touches nothing else, so every proportion survives -
and so does the size.

```
python rig_items.py --items extracted --out extracted \
    --rig "master chief skeleton.blend" --fp "fp arms.blend" \
    --port MyAvatar.glb --keep-shape
```

Halo cannot rescale a biped. The model's nodes are the skeleton its
animation graph drives by name, and everything the game places - the weapon in
the hand, the pickup, the collision capsule - is placed from them. A model whose
nodes sit at some other height does not line up with any of that, so the model
has to come onto Halo's scale, not the other way round.

It comes there by one uniform factor per part, never by stretching an axis:

* the avatar is scaled to the biped's height - 1.909 m here, measured from the
  rig rather than typed in - so a 1.850 m avatar goes x1.032 and keeps its shape;
* the item, authored for the 1.40 m avatar body, goes by the biped / 1.40 fit,
  x1.364, so it still covers the body it was made for.

Both are single factors on all three axes, so nothing is squashed. What the old
code did until v70 was scale the whole model by the *item's* height instead of
the avatar's, which turned a 1.85 m avatar into 1.45 m.

A `keep_shape.txt` beside the `.bat` asks for it on a double-click, the way
`tint_mask.png` asks for a team-colour mask.

The trade is honest and worth stating plainly: the joint fit exists so that the
mesh's joints sit on the bones Halo animates, and `--keep-shape` does not do
that. The mesh keeps the pose it was authored in - arms out, for a typical
export - and its limb lengths are the avatar's, not Halo's, so an animation
that bends Halo's knees and shoulders will move limbs that are the wrong length
for it. The model looks like the file; it does not move like the biped.

## Building it in Halo's editing kit

This tool stops at source data; `tool.exe` is the next step, and this is the whole
path from the folder to something the engine loads. The commands and channel
meanings below are from the H1 Editing Kit documentation - [H1-EK](https://c20.reclaimers.net/h1/h1-ek/),
[H1 Tool](https://c20.reclaimers.net/h1/h1-ek/h1-tool), [bitmap](https://c20.reclaimers.net/h1/tags/bitmap),
[shader_model](https://c20.reclaimers.net/h1/tags/shader/shader_model) and
[decal](https://c20.reclaimers.net/h1/tags/decal). Microsoft's [MCC creator
docs](https://learn.microsoft.com/en-us/halo-master-chief-collection/) cover
Halo 2 and Halo 3 tooling; they have no Halo 1 tool reference, so the H1-EK
pages are the ones that apply.

Each item arrives as one data folder per channel order, and the extractor writes
`Compile <item> Avatar.bat` beside them - for the Marine armour that is
`Compile UNSC Marine Armor Avatar.bat`, in the output folder's root, next to
`extracted for hek users`. The same file is at the repository root, so it can be
read without running the extractor first; the two are kept byte-identical. Run it and it looks for the editing kit
unpacked near it (tool.exe beside the script, one folder up, one folder down or
in a folder next to it) and only asks where the kit is when none of those has
one. It copies the folders into the kit's `data\`, compiles the bitmaps and the
models, and logs everything to a `.log` of the same name beside it. Passing
`xbox` does the same for the Xbox channel order. What it does, step by step:

1. **Put the build where the tool looks.** Copy
   `extracted for hek users\pc\data\<stem>` (or its `xbox` twin) into the
   editing kit's `data\` folder. The folder name is the tag path, and it is the
   only thing that has to move. There is one build per channel order, and it is
   the one that takes the team colour, with any decal already in its base map.
2. **Bitmaps.** `tool bitmaps "<stem> sp\bitmaps"` - H1A Tool also takes a type
   argument (`2d`), the legacy HEK reads it from the tag. Each `.tif` becomes
   `tags\<stem> sp\bitmaps\<name>.bitmap`, named after the file, so every map a
   shader asks for is already named the way it is referenced.
   - `.tif` must be at least 8 bits per pixel and power-of-two; ours are 32-bit.
   - Alpha survives only in a format that holds it: **DXT5 or 32-bit**. DXT1
     keeps one bit, which turns the decal's soft alpha into a hard cutout and
     blacks the colour where it is transparent.
   - Leave **usage** at `default` for all of these. `alpha blend` fades
     transparent pixels to black in the mips and `detail map` fades the mips to
     grey; both are for other kinds of texture, and these are mask images.
3. **Model.** `tool model "<stem> sp"` reads `data\<stem> sp\models\<file>.JMS`
   and writes `tags\<stem> sp\<stem> sp.gbxmodel`. Run it only after the shader
   exists: Tool looks up a shader per JMS material and will stop to ask for one. The material names inside the JMS are
   the only link to shaders, so each one needs a shader tag that exists. Tool
   reads the JMS **file name** as `<permutation> <lod>.JMS` (`base superhigh.JMS`;
   the LOD word is one of `superhigh`, `high`, `medium`, `low`, `superlow`, and
   the docs' own `rock.JMS` example leaves it off). Ours are `<stem> sp` and
   `<stem> mp` - if your Tool build reads the trailing word as a LOD and
   complains, rename them `<stem> sp superhigh.JMS` and `<stem> mp superhigh.JMS`.
4. **Shader.** Make one `shader_model` per JMS material, at a tag path that
   matches the material name, and set:

   | Field | Value |
   |---|---|
   | base map | `<stem> base map` - the decal is already blended into it |
   | multipurpose map | `<stem> multipurpose` for the sp build; the mp build's own, whose alpha is the team colour |
   | detail map, reflection cube map | none |
   | change colour source | none for sp; for mp, the source the map uses (multiplayer colours, or the object's) |
   | flags | none; `og xbox channel order` (0x40) only for an `xbox` build in H1A |

   Guerilla's own channel labels describe the **Xbox** order. Halo CE and the
   legacy HEK read **Gearbox** order, which is what the `pc` builds are written
   in - the `multipurpose xbox` bitmap and the 0x40 flag are the only pair that
   belongs together.

   An item built with `--port` carries two more materials, `face` and `body_0`,
   and each needs its own `shader_model` at the tag path its name gives -
   `<stem> sp\face`, `<stem> sp\body_0` - with its own base map (`<stem> face`
   and `<stem> body_0`, already beside the item's own in every build's
   `bitmaps`). Leave their multipurpose maps empty unless you want the face to
   take the team colour: it is skin, and a team colour on it flickers with the
   armour's.
5. **Map.** `tool build-cache-file "<scenario>" classic`, which packs the tags
   and the bitmap pixels into the map file.

### What the engine reads, and where a decal can go

A `shader_model` has four texture inputs - base map, multipurpose map, detail
map, reflection cube map - and no decal input at all. The channels below are the
only ones the engine reads from a model's textures:

- **base map**: `rgb` diffuse colour, `a` transparency (only meaningful when the
  shader blends).
- **multipurpose map, Gearbox order** (Halo CE, legacy HEK): `r` auxiliary mask,
  which masks the detail map when the detail mask is set to auxiliary (`Guerilla`
  calls that option "multipurpose map alpha", but in this order it is red);
  `g` self-illumination, added to diffuse light and then multiplied by diffuse
  colour; `b` specular/cubemap strength; `a` colour change.
- **multipurpose map, Xbox order**: `r` specular, `g` self-illumination,
  `b` colour change, `a` auxiliary.
- **detail map**: `rgb` only, combined by the detail function - double biased
  multiply `saturate(base * lerp(0.5, detail, mask) * 2)`, multiply
  `saturate(base * lerp(1.0, detail, mask))`, or double biased add
  `saturate(base + (2 * lerp(0.5, detail, mask) - 1))` - masked by whichever
  channel the detail mask names.

So a decal has three real routes, and "a decal channel" is not one of them:

1. **Bake it into the base map** - what this tool does. One shader, the tint
   mask still works, no extra tags, no mip problems.
2. **Detail map, masked by multipurpose red.** The decal art as the detail map
   (usage `detail map`, DXT5 or 32-bit), red white where it shows and black
   elsewhere, detail mask set to auxiliary. The engine multiplies or adds rather
   than lerps, and detail maps are built to tile and fade to grey in the mips,
   so this suits grain far better than a placed logo.
3. **Extra geometry with its own shader** - faces a hair above the surface and
   a `shader_model` with the `alpha blended decal` flag (0x8) and two-sided,
   its base map carrying the real alpha. That is how overlays on objects are
   done; the `decal` tag itself only draws on BSP surfaces.

## Recovering this project from GitHub alone

Nothing here lives on a machine or in a chat: the repository is the project, and
a fresh clone of it is a working one.

```sh
git clone https://github.com/jackrabbit72380/avatar-item-extractor.git
cd avatar-item-extractor
python3 tools/test_all.py
```

`test_all.py` unpacks the payload of the shipped
`Extract UNSC Marine Armor Avatar-v96.bat` and
runs the whole suite against it, so a green run proves the artifact itself is
intact rather than a copy of it beside the repository.

Halo's two rig files travel in the repository, and they have to: every item is
skinned to them, and without them nothing can be rigged.

| file | what it is |
|---|---|
| `src/rig/master chief skeleton.blend` | Halo's 19-bone biped, the target of the body fit |
| `src/rig/fp arms.blend` | Halo's 37-bone first-person arm set |

Rebuilding the shipped `.bat` from the sources needs only Python:

```sh
python3 tools/payload.py pack "Extract UNSC Marine Armor Avatar-v96.bat" src --rigs src/rig
```

`--rigs` is not optional, and `pack` refuses to write unless the rebuild decodes
back to exactly the files it was given, rigs included. The banner's
`Version : vNN` must also match `VERSION` in `src/rig_items.py` - `pack` refuses a
mismatch, which is what stops a rebuilt payload shipping under the old name. Bump
both when the sources change.

A full run - extraction, then rigging - needs Blender 5.2 or newer, which is the
one thing the repository does not carry:

```sh
python3 src/extract_items.py "<folder holding the item .bin>" --out out --obj
blender -b --factory-startup --python src/rig_items.py -- \
    --items out --out out \
    --rig "src/rig/master chief skeleton.blend" \
    --fp "src/rig/fp arms.blend"
```

That is the two halves the `.bat` runs in one double-click, and `out/report.txt`
records every number either half measured.

## Working on the extractor itself

Neither script is needed to run the tool.

```sh
python3 tools/payload.py unpack "Extract UNSC Marine Armor Avatar-v96.bat" src/
# edit src/extract_items.py, then put it back - --rigs is not optional:
python3 tools/payload.py pack "Extract UNSC Marine Armor Avatar-v96.bat" src/ --rigs src/rig
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
