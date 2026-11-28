@echo off
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
