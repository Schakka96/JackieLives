@echo off
REM ===========================================================================
REM  deploy_lua.bat - DOUBLE-CLICK THIS WHILE THE GAME IS RUNNING.
REM
REM  The FAST deploy: it copies only the CET Lua folder (JackieLives) and stops.
REM
REM  Use this one while testing. CET re-reads the Lua, so you can alt-tab out,
REM  double-click this, alt-tab back and hot-reload the mod from the CET
REM  console - no restart, no loading screen.
REM
REM  It deliberately does NOT touch:
REM     r6\scripts    (the redscript shim)
REM     r6\audioware  (the voice bank)
REM     archive\pc\mod
REM  Cyberpunk holds those open while it runs, so they need the game CLOSED.
REM  Use deploy.bat whenever you changed the .reds or the voice bank.
REM
REM  Switches are forwarded, e.g.:  deploy_lua.bat -NoPull
REM ===========================================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" -LuaOnly %*
echo.
