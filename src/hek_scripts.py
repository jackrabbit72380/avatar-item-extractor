"""The two Windows scripts the extractor writes beside its output.

They are text here rather than .bat files beside this module: the payload ships
everything in src/, so two more .bat files in it made a one-click program look
like it had three things to click. rig_items.py writes these out byte for byte -
"Compile <item> Avatar.bat" beside the HEK builds, and "Check the shaders.bat"
beside them - so the only .bat a player is ever handed is the one that extracts.
"""

BUILD_HEK = r"""@echo off
setlocal EnableExtensions
title %~n0

rem ===========================================================================
rem  Runs the tool.exe verbs over each build folder the extractor wrote:
rem
rem    tool bitmaps "<build>\bitmaps"    .tif -> .bitmap tags
rem    tool model   "<build>"            .jms -> .gbxmodel
rem    tool collision-geometry "<build>" .jms -> .model_collision_geometry
rem    tool physics "<build>"            .jms -> .physics
rem
rem  This file is written beside the builds as "Compile <item> Avatar.bat", named
rem  after the item it compiles, and it runs from there. A kit already unpacked
rem  near it is found on its own: the folder holding tool.exe beside this file,
rem  one folder up, one folder down, or next to this folder is used without
rem  asking anything. The folder's
rem  name is never looked at - H1-EK, HCEEK, hcex, whatever yours is called is a
rem  kit because tool.exe is in it. hek_path.txt is only the fallback for a kit
rem  somewhere else. Everything it does is logged to a .log file of the same name
rem  beside it, which is what to paste if something fails.
rem
rem  One data folder is built per channel order: data\<item>\ - the item's own
rem  colours with the team-colour mask bound and any decal blended into the base
rem  map. Only the multiplayer version uses team colour, so there is no sp/mp
rem  pair to choose between: what is built is the version that takes a colour.
rem
rem  The team-colour mask is the alpha of <item> multipurpose: white where the
rem  armour takes red or blue, black where it keeps the colour it was painted.
rem  For an item whose tint slot is blank and which carries no colour table (the
rem  Marine armour is one) that mask is worked out from the base map.
rem
rem  Every .jms is named for the LOD Tool reads - the permutation, a space, then
rem  superhigh, then .jms - because Tool builds a model's markers from the
rem  superhigh LOD only: the word makes that LOD explicit instead of Tool's
rem  undocumented default. Tool strips it off, so the permutation is still the
rem  item's name.
rem
rem  The model carries Halo's own biped node names, in the order that graph
rem  stores, and its .jms header carries that graph's node list checksum
rem  (1828349080) - Tool copies the header's second field into the gbxmodel, so
rem  the two tags agree. BlueStreak writes its constant 3251 there, which is why
rem  a correct skeleton can still say the model and graph don't match. A model
rem  no graph drives (the arms) writes 0: H1 compares a node count only for a
rem  model it is animating, and the first-person renderer reads the weapon's
rem  graph with no model at all and maps the graph's nodes onto the arms by name,
rem  so the arms' 37 nodes are never measured against a 42-node weapon graph. It
rem  also carries the two markers a biped must have - head on bip01 head, body on bip01
rem  spine1 - so it can be the model of a biped tag. That tag also needs an
rem  animation graph, and this tool writes no animations: the character is
rem  skinned to Halo's own 19-bone biped, so point the tag at
rem  characters\cyborg\cyborg.model_animations. A graph built against other node
rem  names, or this skeleton in another order, is the "the model ... and the
rem  animation graph ... don't match" failure; no graph at all is the "units
rem  must have models and animation graphs" failure.
rem
rem  The model needs a shader tag named after each .jms material. Those tags are
rem  checked before the model is compiled - under the whole of tags\, because that
rem  is how tool.exe looks one up: by NAME, in whatever folder it sits - and a
rem  missing one is named (with the bitmap it draws with) and nothing is built:
rem  tool.exe would write an EMPTY shader under that name, bake the reference into
rem  the model, and that surface draws white in game for good. Make each shader
rem  once (README.md, "Building it in Halo's editing kit") and run this again -
rem  one-time, the same shader for every copy of the item.
rem
rem  Those names are LOWER CASE - "unsc marine armor face", not "UNSC Marine
rem  Armor face" - because a tag path is, and tool.exe finds the shader by the
rem  name the .jms spells. The names in "shaders to make.txt" are exactly what
rem  the model asks for, so build the tags under the spellings printed there and
rem  no other.
rem
rem  Usage: "Compile <item> Avatar.bat" [pc|xbox]     (pc when nothing is given)
rem ===========================================================================

set "ORDER=%~1"
if not defined ORDER set "ORDER=pc"
set "OUT=%~dp0"
set "LOG=%OUT%%~n0.log"
rem  The kit is usually right here - unpacked beside the builds under whatever
rem  name its folder has, or with this file dropped into it - so look around
rem  before asking: beside this file, one folder up, one folder down, and the
rem  folders next to this one. tool.exe is the only thing that says a folder is
rem  a kit, so the name never matters. Typing a path that is already sitting
rem  next to the script is not a step anybody should have to take.
set "HEK="
if exist "%OUT%tool.exe" set "HEK=%OUT:~0,-1%"
if not defined HEK if exist "%OUT%..\tool.exe" set "HEK=%OUT%.."
if not defined HEK for /d %%D in ("%OUT%*") do if not defined HEK if exist "%%D\tool.exe" set "HEK=%%D"
if not defined HEK for /d %%D in ("%OUT%..\*") do if not defined HEK if exist "%%D\tool.exe" set "HEK=%%D"
if not defined HEK goto saved
rem  A folder found by looking around can be named with "..\" in its path; make
rem  it the plain folder, so the log and the copy name the kit as it really is.
pushd "%HEK%"
set "HEK=%CD%"
popd
goto run

:saved
if exist "%OUT%hek_path.txt" set /p HEK=<"%OUT%hek_path.txt"
if not defined HEK goto ask
if not exist "%HEK%\tool.exe" goto ask
goto run

:ask
echo.
echo   No tool.exe was found beside this file, one folder up, one folder down or
echo   in a folder next to this one.
echo   Where is your Halo editing kit? That is the folder holding tool.exe,
echo   data\ and tags\ - whatever that folder is called on your machine. For
echo   example, a kit folder named HCEEK:
echo     C:\Program Files ^(x86^)\Steam\steamapps\common\Halo The Master Chief Collection\halo1\HCEEK
echo.
set /p HEK=Path: 
if not exist "%HEK%\tool.exe" (
  echo.
  echo   "%HEK%" has no tool.exe in it, so nothing was built.
  exit /b 1
)
> "%OUT%hek_path.txt" echo %HEK%

:run
if not exist "%OUT%extracted for hek users\%ORDER%\data" (
  echo.
  echo   There is no "extracted for hek users\%ORDER%\data" folder beside this
  echo   file. Run this from the item's output folder.
  exit /b 1
)
echo Build started %DATE% %TIME% > "%LOG%"
echo   kit: "%HEK%"
echo kit: "%HEK%" >> "%LOG%"
echo order: %ORDER% >> "%LOG%"
rem A tool.exe verb takes a path inside the kit's own data\ folder, so each
rem build is copied there first, keeping its folder name - which is also the
rem tag path the bitmaps and the model are written under.
pushd "%HEK%"
for /d %%B in ("%OUT%extracted for hek users\%ORDER%\data\*") do call :build "%%~nxB"
popd

echo.
echo Done. Build log: %LOG%
pause
exit /b 0

:build
set "BUILD=%~1"
echo.
echo == %BUILD%
rem  Always refresh the kit's copy, and clear the .jms first: the model's file
rem  name carries the LOD word, and a model left by an earlier run would be
rem  compiled beside this one. tool.exe compiles every .jms in models\, and the
rem  tag is written to tags\, so nothing here is the built tag.
echo   putting %BUILD% in the kit's data folder
echo putting %BUILD% in the kit's data folder >>"%LOG%"
if exist "%HEK%\data\%BUILD%\models\*.jms" del /Q "%HEK%\data\%BUILD%\models\*.jms" >>"%LOG%" 2>&1
if exist "%HEK%\data\%BUILD%\fp\models\*.jms" del /Q "%HEK%\data\%BUILD%\fp\models\*.jms" >>"%LOG%" 2>&1
xcopy /E /I /Y "%OUT%extracted for hek users\%ORDER%\data\%BUILD%" "%HEK%\data\%BUILD%" >>"%LOG%" 2>&1
echo -- bitmaps "%BUILD%\bitmaps" >>"%LOG%"
tool.exe bitmaps "%BUILD%\bitmaps" >>"%LOG%" 2>&1
if errorlevel 1 echo   bitmap compile reported an error for %BUILD% - see the log
rem  A material with no shader tag is not an error to tool.exe: it asks which
rem  type to make, writes an EMPTY shader under that name, and bakes the
rem  reference into the .gbxmodel. An empty shader has no base map, so the engine
rem  draws that surface with its white shader - and compiling the model again
rem  does not undo it, because the empty tag is there now. That is the white
rem  face: never a missing texture, always a missing or empty shader tag.
rem  So every tag is checked first, and the model is left alone until they all
rem  exist. "shaders to make.txt" beside this file lists them as
rem  <item>|<shader tag>|<bitmap tag>.
rem  The search is the whole of tags\, not two guessed folders. It used to look
rem  in tags\ and tags\<item>\ only, so a tag in the place Halo's own tags live -
rem  tags\characters\<item>\ - read as missing: the build said "nothing was
rem  compiled, on purpose" and stopped, the model tag on disk stayed the one from
rem  before, and the game went on drawing those arms and that white face however
rem  many times the item had been rebuilt since. An index of every shader_model
rem  in the kit is the same test tool.exe makes - the name, wherever it sits.
if not defined TEMP set "TEMP=%OUT%"
set "TAGINDEX=%TEMP%\avatar shader tags %RANDOM%.txt"
if exist "%HEK%\tags" dir /b /s "%HEK%\tags\*.shader_model" > "%TAGINDEX%" 2>nul
set "NEEDSHADER="
if exist "%OUT%shaders to make.txt" for /f "usebackq tokens=1,2,3 delims=|" %%A in ("%OUT%shaders to make.txt") do if /i "%%A"=="%BUILD%" call :needs "%%B" "%%C"
if exist "%TAGINDEX%" del /Q "%TAGINDEX%" >nul 2>&1
if defined NEEDSHADER (
  echo.
  echo   Nothing was compiled for %BUILD%, on purpose. tool.exe would write an
  echo   empty shader under each name above and bake it into the model, and a
  echo   shader with no base map draws that surface white in game - the white
  echo   face. Make each one in Guerilla: New, shader_model, in whatever folder
  echo   you keep your tags in - tags\NAME.shader_model, or your own layout
  echo   tags\<you>\characters\NAME.shader_model, it makes no difference, the
  echo   NAME is what is looked up. Set its base map to the bitmap named beside
  echo   it. Then run this file again. It is a one-time step.
  echo not compiled - the shader tags above are missing >>"%LOG%"
  exit /b 0
)
echo -- model "%BUILD%" >>"%LOG%"
tool.exe model "%BUILD%" >>"%LOG%" 2>&1
if errorlevel 1 echo   model compile reported an error for %BUILD% - if it asked for a shader, make that shader tag and run this again
rem  The first-person arms are a second model, in their own folder, and H1 reads
rem  them from the map's game globals ("first person hands"), not from the
rem  biped or a weapon. tool.exe reads models\ only, so the body compile above
rem  never sees fp\models\: compile that folder as its own source directory and
rem  the tag lands at tags\<item>\fp\. H1 poses it from each weapon's own
rem  first-person graph, node by node, with no model passed to the comparison
rem  (first_person_weapons.c), so its 37 nodes are never counted against that
rem  graph's 42. It is matched by name instead, so the arms' exporter refuses
rem  any bone outside Halo's 37: a renamed rig fails the arms export and names
rem  the nodes rather than writing a model no weapon graph can match. Leave the
rem  arms on the globals reference and nowhere else.
rem  A biped is not collidable without a collision model and a physics tag, and
rem  tool.exe reads both from physics\ inside this same source folder:
rem  collision-geometry and physics each look for <item>.JMS there. Both are
rem  written by the extractor with this model's own node block, so all three
rem  tags carry one node list checksum, and the collision model names the one
rem  region the model names - the two checks tool.exe fails with "node list
rem  checksum ... don't match" and "region counts don't match".
rem
rem  The two source files are parked as .keep while each verb runs, because
rem  tool.exe reads the .JMS files it finds in physics\ and a second one sitting
rem  there would be imported beside the real one. They are named back afterwards
rem  so the folder still shows what the tags were built from.
set "PHYS=%HEK%\data\%BUILD%\physics"
if exist "%PHYS%\%BUILD% collision.jms" ren "%PHYS%\%BUILD% collision.jms" "%BUILD% collision.keep" >>"%LOG%" 2>&1
if exist "%PHYS%\%BUILD% physics.jms" ren "%PHYS%\%BUILD% physics.jms" "%BUILD% physics.keep" >>"%LOG%" 2>&1
if exist "%PHYS%\%BUILD%.jms" del /Q "%PHYS%\%BUILD%.jms" >>"%LOG%" 2>&1
if exist "%PHYS%\%BUILD% collision.keep" (
  copy /Y "%PHYS%\%BUILD% collision.keep" "%PHYS%\%BUILD%.jms" >>"%LOG%" 2>&1
  echo -- collision geometry "%BUILD%" >>"%LOG%"
  tool.exe collision-geometry "%BUILD%" >>"%LOG%" 2>&1
  if errorlevel 1 echo   collision geometry reported an error for %BUILD% - see the log, and any .wrl beside it
  del /Q "%PHYS%\%BUILD%.jms" >>"%LOG%" 2>&1
)
if exist "%PHYS%\%BUILD% physics.keep" (
  copy /Y "%PHYS%\%BUILD% physics.keep" "%PHYS%\%BUILD%.jms" >>"%LOG%" 2>&1
  echo -- physics "%BUILD%" >>"%LOG%"
  tool.exe physics "%BUILD%" >>"%LOG%" 2>&1
  if errorlevel 1 echo   physics reported an error for %BUILD% - see the log
  del /Q "%PHYS%\%BUILD%.jms" >>"%LOG%" 2>&1
)
if exist "%PHYS%\%BUILD% collision.keep" ren "%PHYS%\%BUILD% collision.keep" "%BUILD% collision.jms" >>"%LOG%" 2>&1
if exist "%PHYS%\%BUILD% physics.keep" ren "%PHYS%\%BUILD% physics.keep" "%BUILD% physics.jms" >>"%LOG%" 2>&1

if exist "%HEK%\data\%BUILD%\fp\models\*.jms" (
  echo -- fp arms model "%BUILD%\fp" >>"%LOG%"
  tool.exe model "%BUILD%\fp" >>"%LOG%" 2>&1
  if errorlevel 1 echo   fp arms model reported an error for %BUILD% - see the log
)
rem  A map carries its own copy of every tag it uses - the model, the shader
rem  references, the bitmap pixels - packed in when the map was built. Compiling
rem  a model tag again changes the tag and nothing else, so a .map built before
rem  this run keeps the model and the shaders it was built with. That is why a
rem  model can be compiled ten times over a fixed shader and still draw white.
rem  Build the map again (tool build-cache-file "<scenario>" classic) after this.
echo.
echo   Compiled %BUILD%. The game draws a model from the .map it was built into,
echo   not from tags\, so build the map again to see the change.
exit /b 0

:needs
rem  %~1 is a shader tag name from "shaders to make.txt", %~2 the bitmap behind
rem  it. A name in the index is a tag tool.exe will find, wherever it sits.
set "FOUND="
for /f "usebackq delims=" %%F in ("%TAGINDEX%") do if /i "%%~nxF"=="%~1.shader_model" set "FOUND=1"
if defined FOUND exit /b 0
echo   needs a shader tag: %~1    base map: %~2
echo shader missing: %~1    base map: %~2 >>"%LOG%"
set "NEEDSHADER=1"
exit /b 0
"""


CHECK_SHADERS = r"""@echo off
setlocal EnableExtensions
title Check the shaders
rem  Why a surface draws white. Nothing here writes anything: it reads the tags
rem  this computer actually holds and the names this build asks for, and says
rem  which of them is the reason. Python 3.8+ is the same thing the extractor
rem  needs, so it is already on any machine that produced this build.
set "PY=py -3"
py -3 -c "import sys;raise SystemExit(0 if sys.version_info[:2]>=(3,8) else 1)" >nul 2>&1
if not errorlevel 1 goto run
set "PY=python"
python -c "import sys;raise SystemExit(0 if sys.version_info[:2]>=(3,8) else 1)" >nul 2>&1
if not errorlevel 1 goto run
set "PY=python3"
python3 -c "import sys;raise SystemExit(0 if sys.version_info[:2]>=(3,8) else 1)" >nul 2>&1
if not errorlevel 1 goto run
echo.
echo   Python 3.8 or newer was not found on this computer.
echo   Install it from https://www.python.org/downloads/windows/ and tick
echo   "Add python.exe to PATH" in the installer, then run this again.
pause
exit /b 1

:run
echo.
%PY% "%~dp0check_shaders.py" "%~dp0."
echo.
pause
exit /b 0
"""
