# deploy_probe.ps1 - copy a standalone CET probe mod into the game's mods folder.
# Usage:
#   .\deploy_probe.ps1                       # deploys JackieSceneProbe, auto-detect Steam
#   .\deploy_probe.ps1 -ModName JackieLipsync
#   .\deploy_probe.ps1 -GameDir "X:\...\Cyberpunk 2077"
param([string]$ModName = "JackieSceneProbe", [string]$GameDir = "")

$ErrorActionPreference = "Stop"
$src = Join-Path $PSScriptRoot ("mod\" + $ModName)
if (-not (Test-Path $src)) { Write-Host "ERROR: source mod not found at $src"; exit 1 }

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
  Write-Host "Could not auto-find Cyberpunk 2077. Re-run: .\deploy_probe.ps1 -GameDir 'X:\path\to\Cyberpunk 2077'"
  exit 1
}

$modsDir = Join-Path $game "bin\x64\plugins\cyber_engine_tweaks\mods"
if (-not (Test-Path $modsDir)) { Write-Host "CET mods folder not found at: $modsDir"; exit 1 }

$dest = Join-Path $modsDir $ModName
robocopy $src $dest /E /NFL /NDL /NJH /NJS /NP /R:2 /W:1 | Out-Null
if ($LASTEXITCODE -ge 8) {
  Write-Host "Deploy FAILED (robocopy $LASTEXITCODE): file locked. Close the game and retry."; exit 1
}
Write-Host "Deployed '$ModName' to $dest" -ForegroundColor Green
Write-Host "In-game: reload all mods (CET overlay) or restart. Output lands in $dest\scene_methods.txt" -ForegroundColor Green
exit 0
