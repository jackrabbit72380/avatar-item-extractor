@echo off
REM Double-click launcher for the avatar item extractor.
REM   Drag a closet folder onto this file, or just run it to use .\_closet
REM   Results go to .\extracted
setlocal
cd /d "%~dp0"

set "SRC=%~1"
if "%SRC%"=="" set "SRC=_closet"
set "OUT=%~2"
if "%OUT%"=="" set "OUT=extracted"

where py >nul 2>nul
if %errorlevel%==0 (set "PY=py -3") else (set "PY=python")

echo Extracting avatar items
echo   from: %SRC%
echo   to:   %OUT%
echo.

%PY% extract_items.py "%SRC%" "%OUT%" --obj
if errorlevel 1 (
    echo.
    echo Something went wrong.
    echo   "avatar_mesh.py not found"  -^> run setup.bat once
    echo   "no closet_index.tsv"        -^> the folder argument is wrong
    echo.
)

echo.
pause
