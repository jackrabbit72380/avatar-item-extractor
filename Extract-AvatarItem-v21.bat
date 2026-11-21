@echo off
setlocal EnableExtensions
title Avatar Item Extractor v21
rem ===========================================================================
rem  One double-click. Keep these beside each other:
rem      Extract-AvatarItem-v21.bat    double-click this
rem      Extract-AvatarItem-v20.bat    carries the extractor
rem      v21_run.py                    adds the v21 fixes
rem      avatar_mesh.py, lzx.py        the two readers, once
rem ===========================================================================

set "HERE=%~dp0"
set "CACHE=%LOCALAPPDATA%\AvatarItemExtractor"
set "OUT=%HERE%extracted"

echo.
echo   Avatar Item Extractor v21
echo   -------------------------
echo.

set "PY="
py -3 -c "import sys;raise SystemExit(0 if sys.version_info[:2]>=(3,8) else 1)" >nul 2>&1
if not errorlevel 1 set "PY=py -3"
if defined PY goto :run
python -c "import sys;raise SystemExit(0 if sys.version_info[:2]>=(3,8) else 1)" >nul 2>&1
if not errorlevel 1 set "PY=python"
if defined PY goto :run
python3 -c "import sys;raise SystemExit(0 if sys.version_info[:2]>=(3,8) else 1)" >nul 2>&1
if not errorlevel 1 set "PY=python3"
if defined PY goto :run

echo   Python 3.8 or newer was not found on this computer.
echo   Install it from https://www.python.org/downloads/windows/
echo   and tick "Add python.exe to PATH", then run this file again.
echo.
start "" https://www.python.org/downloads/windows/
pause
exit /b 2

:run
%PY% "%HERE%v21_run.py" "%CACHE%" --obj --out "%OUT%"
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" goto :done
if "%RC%"=="3" goto :unparsed
if "%RC%"=="4" goto :nothing
if "%RC%"=="5" goto :noreaders
if "%RC%"=="6" goto :nocarr

echo.
echo   The extractor stopped with code %RC%.
echo   Nothing was deleted or moved. Run this file again to retry.
echo.
pause
exit /b %RC%

:nocarr
echo.
echo   Extract-AvatarItem-v20.bat must sit beside this file.
echo   It carries the extractor; without it there is nothing to run.
echo.
pause
exit /b 6

:noreaders
echo.
pause
exit /b 5

:nothing
echo.
echo   No item sources were found.
echo   A source is a folder holding closet_index.tsv, or one holding the item
echo   .bin / .asset files - in Downloads, Desktop, Documents or this folder.
echo.
pause
exit /b 4

:unparsed
echo.
echo   Error: this container does not contain Avatar Item Content.
echo   Please try another.
echo.
pause
exit /b 3

:done
echo.
echo   Done. Everything is in:
echo      %OUT%
echo.
pause
endlocal
exit /b 0
