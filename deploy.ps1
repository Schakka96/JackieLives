# deploy.ps1 - copy the JackieLives CET mod into the game's mods folder.
# Overwrites files IN PLACE (no folder delete) so it can run while the game is open.
# Usage:
#   .\deploy.ps1                      # auto-detect Steam install
#   .\deploy.ps1 -GameDir "X:\...\Cyberpunk 2077"
param([string]$GameDir = "")

$ErrorActionPreference = "Stop"
$modName = "JackieLives"
$src = Join-Path $PSScriptRoot ("mod\" + $modName)

if (-not (Test-Path $src)) { Write-Host "ERROR: source mod not found at $src"; exit 1 }

# Read the mod version from config.lua (Config.version = "x.y.z") so every deploy spells it out.
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

Write-Host "Restart the game (or reload the mod) to load JackieLives v$version." -ForegroundColor Green
exit 0
