@echo off
REM ONE CLICK. Double-click this file.
REM   - fetches the item readers on first run
REM   - asks for the folder if there is no _closet folder beside it
REM   - writes results to .\extracted and opens that folder
REM
REM You can also drag a folder or a single .bin file onto this file.
setlocal
cd /d "%~dp0"
title Avatar Item Extractor

set "OUT=extracted"
set "SRC=%~1"
if "%SRC%"=="" if exist "_closet" set "SRC=_closet"

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

REM ---- 2. what to extract ----------------------------------------------
if "%SRC%"=="" call :pick
if "%SRC%"=="" (
    echo.
    echo No folder chosen - nothing to do.
    echo.
    pause
    exit /b 1
)

REM ---- 3. extract ------------------------------------------------------
echo Extracting avatar items from:
echo   %SRC%
echo.
%PY% extract_items.py "%SRC%" "%OUT%" --obj
if errorlevel 1 goto failed

echo.
echo Done. Opening the results folder...
start "" "%OUT%"
echo.
echo  catalogue.json  - names, masks and geometry for every item
echo  items\*.obj     - the models, ready to open in Blender
echo  icons\*.png     - the item icons
echo.
pause
exit /b 0

:failed
echo.
echo Nothing was extracted.
echo   "not found"                -^> the path has no item files in it
echo   "avatar_mesh.py not found" -^> delete the vendor folder, run this again
echo   "no closet_index.tsv"      -^> that folder holds no .bin item files
echo.
echo If every item says "not a STRB container", the file is not a retail
echo avatar item (this tool reads YTGR/STRB assets only).
echo.
pause
exit /b 1

REM ---- helpers ---------------------------------------------------------

:pick
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; $f=New-Object System.Windows.Forms.FolderBrowserDialog; $f.Description='Pick the folder holding your avatar item files'; if($f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){$f.SelectedPath}"`) do set "SRC=%%I"
exit /b 0

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
