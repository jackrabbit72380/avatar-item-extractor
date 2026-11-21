@echo off
setlocal EnableExtensions
title Avatar Item Extractor + Halo Rig
rem ===========================================================================
rem  One double-click. Extracts every avatar item, then rigs every item onto
rem  Halo's own biped and first-person arms. No questions, no folder picker.
rem
rem  Keep these beside each other:
rem      AvatarRig.bat
rem      Extract-AvatarItem-v20.bat
rem      rig_items.py
rem      rig\master chief skeleton.blend
rem      rig\fp arms.blend
rem
rem  Blender 4.x must be installed. If it is not, the items are still extracted
rem  and the run says so.
rem ===========================================================================

set "HERE=%~dp0"
set "OUT=%HERE%extracted"
set "RIGGED=%HERE%rigged"

echo.
echo   Avatar Item Extractor + Halo Rig
echo   --------------------------------
echo.

rem ------------------------------------------------------------------ extract
if not exist "%HERE%Extract-AvatarItem-v20.bat" goto :noextractor
echo   Extracting items...
rem The extractor waits for a key at the end; the piped newline answers it so
rem the whole run stays one double-click.
echo.|call "%HERE%Extract-AvatarItem-v20.bat"
if not exist "%OUT%" goto :nothingextracted

rem --------------------------------------------------------------------- rig
if not exist "%HERE%rig_items.py" goto :norigger
if not exist "%HERE%rig\master chief skeleton.blend" goto :norigs
if not exist "%HERE%rig\fp arms.blend" goto :norigs

set "BL="
for /f "delims=" %%D in ('dir /b /ad /o-n "%ProgramFiles%\Blender Foundation" 2^>nul') do if not defined BL if exist "%ProgramFiles%\Blender Foundation\%%D\blender.exe" set "BL=%ProgramFiles%\Blender Foundation\%%D\blender.exe"
if not defined BL if exist "%ProgramFiles%\Blender Foundation\Blender\blender.exe" set "BL=%ProgramFiles%\Blender Foundation\Blender\blender.exe"
if not defined BL goto :noblender

echo.
echo   Rigging every item onto the Halo skeleton and first-person arms...
echo.
"%BL%" -b --factory-startup --python "%HERE%rig_items.py" -- --items "%OUT%" --rig "%HERE%rig\master chief skeleton.blend" --fp "%HERE%rig\fp arms.blend" --out "%RIGGED%"
if not "%ERRORLEVEL%"=="0" goto :rigfailed

echo.
echo   Done.
echo      %OUT%      extracted catalogue, icons and .obj
echo      %RIGGED%      rigged .blend, .fbx and .jms
echo.
pause
endlocal
exit /b 0

:noextractor
echo   Extract-AvatarItem-v20.bat is not in this folder.
echo   Keep it beside AvatarRig.bat and run this file again.
echo.
pause
exit /b 4

:nothingextracted
echo.
echo   No item sources were found, so there was nothing to rig.
echo   A source is a folder holding closet_index.tsv, or one holding the item
echo   .bin / .asset files - in Downloads, Desktop, Documents or this folder.
echo.
pause
exit /b 3

:norigger
echo.
echo   rig_items.py is not in this folder, so nothing was rigged.
echo   The extracted items are in %OUT%.
echo.
pause
exit /b 5

:norigs
echo.
echo   The items are extracted, but nothing was rigged: the two skeleton files
echo   were not found. Put "master chief skeleton.blend" and "fp arms.blend" in
echo   a folder called rig next to this file and run it again.
echo.
pause
exit /b 5

:noblender
echo.
echo   The items are extracted, but nothing was rigged: Blender was not found.
echo   Install it from https://www.blender.org/download/ and run this file again
echo   - it rigs every item without any other setup.
echo.
start "" https://www.blender.org/download/
pause
exit /b 6

:rigfailed
echo.
echo   Extracted everything, but the rigging pass stopped with an error above.
echo   The extracted items are fine and are in %OUT%.
echo.
pause
exit /b 7
