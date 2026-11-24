@echo off
setlocal EnableExtensions
title Build an avatar item in Halo's editing kit

rem ===========================================================================
rem  Runs the two tool.exe verbs over each build folder the extractor wrote:
rem
rem    tool bitmaps "<build>\bitmaps"    .tif -> .bitmap tags
rem    tool model   "<build>"            .jms -> .gbxmodel
rem
rem  Put this file in the item's output folder - beside "extracted for hek
rem  users" - and run it. A kit that is already unpacked in the same place is
rem  found on its own: tool.exe beside this file, one folder up or one folder
rem  down is used without asking anything. hek_path.txt is only the fallback for
rem  a kit somewhere else. Everything it does is logged to build-hek.log, which
rem  is what to paste if something fails.
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
rem  The model needs a shader tag named after each .jms material, and tool.exe
rem  will ask for one if it cannot find it. Make that shader once (README.md,
rem  "Building it in Halo's editing kit") and run this again: the shader is the
rem  same for every copy of the item, so it is a one-time step.
rem
rem  Usage: build-hek.bat [pc|xbox]     (pc when nothing is given)
rem ===========================================================================

set "ORDER=%~1"
if not defined ORDER set "ORDER=pc"
set "OUT=%~dp0"
set "LOG=%OUT%build-hek.log"
rem  The kit is usually right here - H1-EK unpacked beside the builds, or this
rem  file dropped into H1-EK - so look beside this file, one folder up and one
rem  folder down before asking where it is. Typing a path that is already
rem  sitting next to the script is not a step anybody should have to take.
set "HEK="
if exist "%OUT%tool.exe" set "HEK=%OUT:~0,-1%"
if not defined HEK if exist "%OUT%..\tool.exe" set "HEK=%OUT%.."
if not defined HEK for /d %%D in ("%OUT%*") do if not defined HEK if exist "%%D\tool.exe" set "HEK=%%D"
if defined HEK goto run
if exist "%OUT%hek_path.txt" set /p HEK=<"%OUT%hek_path.txt"
if not defined HEK goto ask
if not exist "%HEK%\tool.exe" goto ask
goto run

:ask
echo.
echo   No tool.exe was found beside this file, one folder up or one folder down.
echo   Where is your Halo editing kit? That is the folder holding tool.exe,
echo   data\ and tags\, for example:
echo     C:\Program Files ^(x86^)\Steam\steamapps\common\Halo The Master Chief Collection\halo1\H1-EK
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
if not exist "%HEK%\data\%BUILD%" (
  echo   putting %BUILD% in the kit's data folder
  xcopy /E /I /Y "%OUT%extracted for hek users\%ORDER%\data\%BUILD%" "%HEK%\data\%BUILD%" >>"%LOG%" 2>&1
)
echo -- bitmaps "%BUILD%\bitmaps" >>"%LOG%"
tool.exe bitmaps "%BUILD%\bitmaps" >>"%LOG%" 2>&1
if errorlevel 1 echo   bitmap compile reported an error for %BUILD% - see the log
echo -- model "%BUILD%" >>"%LOG%"
tool.exe model "%BUILD%" >>"%LOG%" 2>&1
if errorlevel 1 echo   model compile reported an error for %BUILD% - if it asked for a shader, make that shader tag and run this again
exit /b 0
