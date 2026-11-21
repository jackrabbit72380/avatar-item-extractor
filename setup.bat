@echo off
REM Vendors avatar_mesh.py and lzx.py into .\vendor
REM   From a local UniKron checkout if one is next to this repo,
REM   otherwise from GitHub raw.
setlocal
cd /d "%~dp0"

set "SRC=%~1"
if "%SRC%"=="" set "SRC=..\UniKron\avatar\avatar_tools"

if not exist "vendor" mkdir vendor

if exist "%SRC%\avatar_mesh.py" (
    echo Copying readers from %SRC%
    copy /y "%SRC%\avatar_mesh.py" "vendor\avatar_mesh.py" >nul
    copy /y "%SRC%\lzx.py" "vendor\lzx.py" >nul
    goto check
)

echo No local UniKron checkout at %SRC%
echo Downloading readers from GitHub...

set "BASE=https://raw.githubusercontent.com/jackrabbit72380/UniKron/main/avatar/avatar_tools"
powershell -NoProfile -Command "Invoke-WebRequest -UseBasicParsing '%BASE%/avatar_mesh.py' -OutFile 'vendor\avatar_mesh.py'"
powershell -NoProfile -Command "Invoke-WebRequest -UseBasicParsing '%BASE%/lzx.py' -OutFile 'vendor\lzx.py'"

:check
if not exist "vendor\avatar_mesh.py" (
    echo.
    echo Could not get avatar_mesh.py.
    echo Clone UniKron and run:  setup.bat path\to\UniKron\avatar\avatar_tools
    echo.
    pause
    exit /b 1
)

echo.
echo Done. avatar_mesh.py and lzx.py are in vendor\
echo.
pause
