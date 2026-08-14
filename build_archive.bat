@echo off
REM ===========================================================================
REM  build_archive.bat - DOUBLE-CLICK THIS to build + install the voice archive.
REM
REM  This is what makes a FEMALE V sound female. A line's two takes share one
REM  String ID and the engine picks the male one, so the mod ships its own
REM  String IDs pointing at the female recording. They live in
REM  JackieLives.archive. See ..\NCLives\docs\research\vo_gender.md.
REM
REM  You only need to run this when tools\gen_vomap.py has written new rows
REM  (i.e. when config.lua gained voiced lines). Ordinary code changes just
REM  need deploy.bat. ArchiveXL must be installed for the archive to do
REM  anything - without it V keeps the male takes and nothing breaks.
REM
REM  First run: it ASKS for your WolvenKit.CLI.exe path and writes .env itself.
REM  (Windows Explorer won't let you rename a file to ".env" - a name starting
REM  with a dot - so making you create that by hand was a dead end.)
REM ===========================================================================
setlocal

cd /d "%~dp0"

REM Find Python. The `py` launcher ships with the python.org installer; `python`
REM covers a Store install or a custom PATH entry.
set PY=
where py >nul 2>&1 && set PY=py
if "%PY%"=="" ( where python >nul 2>&1 && set PY=python )
if "%PY%"=="" (
  echo.
  echo   Python is not installed, or not on PATH.
  echo   Install it from https://www.python.org/downloads/  and tick
  echo   "Add python.exe to PATH" on the FIRST screen of the installer.
  echo.
  pause
  exit /b 1
)

REM First-run setup. Writing .env FOR her matters: Explorer refuses to create or
REM rename to a name starting with "." ("You must type a file name."), so "copy
REM .env.example to .env" is not actually a thing you can do by mouse.
if not exist ".env" call :makeenv
if not exist ".env" exit /b 1

%PY% "tools\build_archive.py" %*
echo.
pause
exit /b 0

REM ---------------------------------------------------------------------------
REM Ask for the WolvenKit CLI path and write .env. In a CALLed subroutine so the
REM variable is read back on the following line - inside an if-block it wouldn't
REM be (batch expands the whole block before running it).
REM ---------------------------------------------------------------------------
:makeenv
echo.
echo   ==== First-time setup =================================================
echo.
echo   I need the path to WolvenKit.CLI.exe.
echo.
echo   This is NOT the WolvenKit app you already have - that folder only has
echo   WolvenKit.exe. The command-line tool is a SEPARATE download:
echo.
echo     1. Open  https://github.com/WolvenKit/WolvenKit/releases
echo     2. Download  WolvenKit.Console-8.19.0.zip
echo        (NOT WolvenKit-8.19.0.zip, NOT WolvenKitSetup)
echo     3. Unzip it somewhere you'll keep, e.g.  C:\Tools\WolvenKit.Console\
echo     4. Find WolvenKit.CLI.exe at the top level of that folder
echo     5. Right-click it, choose "Copy as path"
echo     6. Paste it below with Ctrl+V, then press Enter
echo.
echo   (Just press Enter on its own to stop and do this later.)
echo.
set "WKPATH="
set /p "WKPATH=WolvenKit.CLI.exe path: "

if not defined WKPATH (
  echo.
  echo   Cancelled - nothing was saved. Re-run this file when you have it.
  echo.
  pause
  exit /b 1
)

REM "Copy as path" wraps the path in quotes; strip them so the Python side and
REM the exist-check below both see a bare path.
set WKPATH=%WKPATH:"=%

if /i not "%WKPATH:~-4%"==".exe" (
  echo.
  echo   That doesn't end in .exe:
  echo     %WKPATH%
  echo   I need the file itself, not the folder. Re-run and try again.
  echo.
  pause
  exit /b 1
)

if not exist "%WKPATH%" (
  echo.
  echo   No file there:
  echo     %WKPATH%
  echo   Check the path and re-run this file.
  echo.
  pause
  exit /b 1
)

> ".env" echo # Written by build_archive.bat. Machine-specific - never committed.
>>".env" echo WOLVENKIT_CLI=%WKPATH%
echo.
echo   Saved. Building now...
echo.
exit /b 0
