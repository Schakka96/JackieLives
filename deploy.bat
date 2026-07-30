@echo off
REM ===========================================================================
REM  deploy.bat - DOUBLE-CLICK THIS to update JackieLives and install it.
REM
REM  It pulls the newest code from GitHub, then copies the CET mod into the
REM  game's mods folder and the Audioware voice bank into r6\audioware.
REM  No moving folders by hand, no PowerShell prompt, no typing.
REM
REM  This wrapper exists because Windows BLOCKS .ps1 scripts by default
REM  ("running scripts is disabled on this system"), which makes deploy.ps1
REM  look broken when it isn't. -ExecutionPolicy Bypass applies to THIS run
REM  only - it changes nothing about your machine's settings.
REM
REM  Anything you type after the file (or any switch you pass from a prompt)
REM  is forwarded straight through to deploy.ps1, e.g.:
REM     deploy.bat -NoPull
REM     deploy.bat -GameDir "X:\Games\Cyberpunk 2077"
REM ===========================================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" %*
echo.
pause
