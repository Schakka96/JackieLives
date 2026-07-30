# deploy.ps1 - PULL the latest JackieLives from GitHub, then copy it into the game.
#
# NOTE: THIS FILE LIVES AT THE REPO ROOT (next to mod\, staging\, tools\) - NOT inside mod\.
#
# One command does everything: fetch the newest code from GitHub, copy the CET mod into
# the game's mods folder, and copy the Audioware voice bank into r6\audioware.
# Overwrites files IN PLACE (no folder delete) so it can run while the game is open.
#
# Usage (run from the repo root, in PowerShell):
#   .\deploy.ps1                       # git pull, then deploy (auto-detect Steam install)
#   .\deploy.ps1 -NoPull               # deploy what's already on disk; don't touch git
#   .\deploy.ps1 -Force                # pull even with local edits (stashes + reapplies them)
#   .\deploy.ps1 -GameDir "X:\...\Cyberpunk 2077"
#
# It NEVER throws your work away: if the repo has uncommitted changes it skips the pull and
# says so, rather than clobbering them. -Force uses --autostash, which puts them back after.
param([string]$GameDir = "", [switch]$NoPull, [switch]$Force)

$ErrorActionPreference = "Stop"
$modName = "JackieLives"
$src = Join-Path $PSScriptRoot ("mod\" + $modName)

if (-not (Test-Path $src)) { Write-Host "ERROR: source mod not found at $src"; exit 1 }

# --- STEP 1: get the newest code from GitHub -------------------------------
# Without this you had to remember to `git pull` by hand before deploying - and a deploy that
# silently ships yesterday's code is the worst kind of test result, because nothing looks wrong.
function Update-FromGitHub {
  if ($NoPull) { Write-Host "Skipping the update (-NoPull)." -ForegroundColor DarkGray; return }

  if (-not (Test-Path (Join-Path $PSScriptRoot ".git"))) {
    Write-Host "This folder is not a git clone, so there's nothing to pull." -ForegroundColor Yellow
    Write-Host "  To get one-command updates in future, clone the repo once:" -ForegroundColor Yellow
    Write-Host "    git clone https://github.com/Schakka96/JackieLives.git" -ForegroundColor Yellow
    Write-Host "  ...then run .\deploy.ps1 from inside it. Deploying what's on disk for now."
    return
  }
  $git = Get-Command git -ErrorAction SilentlyContinue
  if (-not $git) {
    Write-Host "git isn't on PATH - install Git for Windows (https://git-scm.com/download/win)." -ForegroundColor Yellow
    Write-Host "  Deploying what's on disk for now."
    return
  }

  # git writes ordinary progress to STDERR. Under $ErrorActionPreference = "Stop" (and PowerShell 7's
  # native-command error handling) that can abort the whole script over a perfectly normal fetch, so
  # relax it for the duration and decide success from the EXIT CODE instead. Restored in `finally`.
  $prevEAP = $ErrorActionPreference
  $ErrorActionPreference = "Continue"

  Push-Location $PSScriptRoot
  try {
    $before = (& git rev-parse --short HEAD 2>$null)
    $dirty  = (& git status --porcelain 2>$null)

    if ($dirty -and -not $Force) {
      Write-Host "Local changes present - SKIPPING the pull so nothing of yours is lost:" -ForegroundColor Yellow
      $dirty | Select-Object -First 8 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
      Write-Host "  Commit them, or re-run as:  .\deploy.ps1 -Force   (stashes + reapplies)" -ForegroundColor Yellow
    }
    else {
      Write-Host "Pulling the latest from GitHub..."
      if ($Force) { & git pull --rebase --autostash 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray } }
      else        { & git pull --ff-only          2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray } }

      if ($LASTEXITCODE -ne 0) {
        # Diverged history, no network, whatever - never block the deploy over it.
        Write-Host "Pull failed (see above). Deploying the code already on disk instead." -ForegroundColor Yellow
      }
      else {
        $after = (& git rev-parse --short HEAD 2>$null)
        if ($after -eq $before) { Write-Host "Already up to date ($after)." -ForegroundColor DarkGray }
        else { Write-Host "Updated $before -> $after" -ForegroundColor Green }
      }
    }
  }
  catch {
    # An update is a convenience, never a reason to fail a deploy. Say what happened and carry on.
    Write-Host "Update step errored: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "  Deploying the code already on disk instead."
  }
  finally {
    Pop-Location
    $ErrorActionPreference = $prevEAP
  }
}

Update-FromGitHub

# --- STEP 2: what are we about to deploy? ----------------------------------
# Read the version AFTER the pull, so the banner reflects the code actually being copied.
$version = "unknown"
$cfgPath = Join-Path $src "config.lua"
if (Test-Path $cfgPath) {
  $m = Select-String -Path $cfgPath -Pattern 'Config\.version\s*=\s*"([^"]+)"' | Select-Object -First 1
  if ($m) { $version = $m.Matches[0].Groups[1].Value }
}
Write-Host "=== Deploying $modName v$version ===" -ForegroundColor Cyan

function Find-GameDir {
  if ($GameDir -and (Test-Path $GameDir)) { return $GameDir }

  $default = "C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077"
  if (Test-Path $default) { return $default }

  $steam = "C:\Program Files (x86)\Steam"
  try { $steam = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction Stop).SteamPath } catch {}
  $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
  if (Test-Path $vdf) {
    $text = Get-Content $vdf -Raw
    $paths = [regex]::Matches($text, '"path"\s*"([^"]+)"') |
             ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' }
    foreach ($p in $paths) {
      $g = Join-Path $p "steamapps\common\Cyberpunk 2077"
      if (Test-Path $g) { return $g }
    }
  }
  return $null
}

$game = Find-GameDir
if (-not $game) {
  Write-Host "Could not auto-find Cyberpunk 2077. Re-run: .\deploy.ps1 -GameDir 'X:\path\to\Cyberpunk 2077'"
  exit 1
}

$modsDir = Join-Path $game "bin\x64\plugins\cyber_engine_tweaks\mods"
if (-not (Test-Path $modsDir)) {
  Write-Host "CET mods folder not found at: $modsDir"
  Write-Host "Is Cyber Engine Tweaks installed?"
  exit 1
}

$dest = Join-Path $modsDir $modName

# robocopy overwrites changed files in place (no delete); brief retry on locks.
robocopy $src $dest /E /NFL /NDL /NJH /NJS /NP /R:2 /W:1 | Out-Null
$rc = $LASTEXITCODE
if ($rc -ge 8) {
  Write-Host "Deploy FAILED (robocopy code $rc): a mod file is locked by the running game."
  Write-Host "Close Cyberpunk 2077, then run .\deploy.ps1 again."
  exit 1
}
Write-Host "Deployed '$modName' to $dest"

# --- Audioware sound bank (v0.20) -> <game>\r6\audioware\JackieLives ---------
# Manifest + .ogg files; Audioware (red4ext plugin) scans r6\audioware for these.
$awSrc = Join-Path $PSScriptRoot ("audioware\" + $modName)
if (Test-Path $awSrc) {
  $awDest = Join-Path $game ("r6\audioware\" + $modName)
  # /PURGE: mirror source -> dest (remove stale clips no longer shipped). Safe: this
  # subfolder is entirely mod-owned (manifest + our .ogg/.wav only).
  robocopy $awSrc $awDest /E /PURGE /NFL /NDL /NJH /NJS /NP /R:2 /W:1 | Out-Null
  $arc = $LASTEXITCODE
  if ($arc -ge 8) {
    Write-Host "Audioware deploy FAILED (robocopy code $arc): a file is locked by the running game."
    Write-Host "Close Cyberpunk 2077, then run .\deploy.ps1 again."
    exit 1
  }
  Write-Host "Deployed Audioware bank to $awDest"
} else {
  Write-Host "(no audioware\$modName folder - skipping sound bank)"
}

# --- what actually landed --------------------------------------------------
# Spell out the exact files deployed. A CET mod fails silently when it's stale, so "which .lua
# files are now in the game" is the single most useful thing to see before a test session.
$luaCount = (Get-ChildItem -Path $dest -Filter *.lua -File -ErrorAction SilentlyContinue | Measure-Object).Count
Write-Host ""
Write-Host "Restart the game (or reload the mod) to load JackieLives v$version." -ForegroundColor Green
Write-Host "  $luaCount .lua files in $dest" -ForegroundColor DarkGray
if (Test-Path (Join-Path $dest "dialogui.lua")) {
  Write-Host "  dialogui.lua present - the native dialogue picker (v1.63+) is installed." -ForegroundColor DarkGray
}
exit 0
