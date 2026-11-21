@echo off
REM ONE CLICK. Double-click this file. Nothing to choose, nothing to drop.
REM   It searches fixed locations, extracts every item it finds,
REM   writes to .\extracted and opens that folder.
setlocal
cd /d "%~dp0"
title Avatar Item Extractor

set "OUT=extracted"

REM ---- 1. the readers (avatar_mesh.py + lzx.py) -------------------------
if not exist "vendor\avatar_mesh.py" call :vendor
if not exist "vendor\avatar_mesh.py" (
    echo.
    echo Could not set up the item readers. Check your internet connection,
    echo or put a UniKron checkout next to this folder and run again.
    echo.
    pause
    exit /b 1
)

where py >nul 2>nul
if %errorlevel%==0 (set "PY=py -3") else (set "PY=python")

REM ---- 2. find and extract ---------------------------------------------
%PY% extract_items.py %* --obj --out "%OUT%"
set "RESULT=%errorlevel%"

if "%RESULT%"=="0" (
    echo.
    echo Done. Opening the results folder...
    start "" "%OUT%"
    echo.
    echo  catalogue.json  - every item: name, masks, geometry, where it came from
    echo  items\*.obj     - the models, ready to open in Blender
    echo  icons\*.png     - the item icons
    echo.
    pause
    exit /b 0
)

echo.
if "%RESULT%"=="4" (
    echo No avatar items were found. The folders listed above were searched
    echo and none of them holds a closet_index.tsv or any .bin/.asset files.
    echo.
    echo Put the closet folder in Downloads, or beside this .bat, and run again.
) else (
    echo Items were found but none could be read - see the lines above.
    echo If they say "not a STRB container", those files are not retail avatar
    echo items and this tool cannot read them.
)
echo.
pause
exit /b %RESULT%

REM ---- helpers ---------------------------------------------------------

:vendor
if not exist "vendor" mkdir vendor
set "LOCAL=..\UniKron\avatar\avatar_tools"
if exist "%LOCAL%\avatar_mesh.py" (
    echo Copying item readers from %LOCAL%
    copy /y "%LOCAL%\avatar_mesh.py" "vendor\" >nul
    copy /y "%LOCAL%\lzx.py" "vendor\" >nul
    exit /b 0
)
echo Downloading the item readers...
set "BASE=https://raw.githubusercontent.com/jackrabbit72380/UniKron/main/avatar/avatar_tools"
powershell -NoProfile -Command "try { Invoke-WebRequest -UseBasicParsing '%BASE%/avatar_mesh.py' -OutFile 'vendor\avatar_mesh.py'; Invoke-WebRequest -UseBasicParsing '%BASE%/lzx.py' -OutFile 'vendor\lzx.py' } catch { exit 1 }"
exit /b 0
