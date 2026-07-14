#!/usr/bin/env bash
#
# package_nexus.sh — build the Nexus-ready zip, on a Mac, that installs correctly on Windows.
#
#   ./tools/package_nexus.sh
#   -> dist/JackieLives-v<version>.zip
#
# WHY THIS SCRIPT EXISTS
# ----------------------
# A zip is a zip — Windows does not care that it was made on a Mac. There are exactly two ways a
# Mac-built mod zip goes wrong, and both are silent:
#
#   1. WRAPPER FOLDER. If you right-click `staging` in Finder -> "Compress", you get a zip whose root is
#      a folder called `staging/`. Vortex/MO2 then can't see `fomod/` at the top level, fail to detect the
#      FOMOD installer, and drop back to the "couldn't determine mod type" fallback — which installs the
#      files to the wrong place. The CONTENTS of staging/ must be at the archive root.
#
#   2. MAC METADATA. Finder and `ditto` bury `__MACOSX/` folders and `._`-prefixed AppleDouble files in
#      the archive, and Finder litters `.DS_Store` everywhere. On Windows these show up as junk files
#      inside the game folder. `zip -X` plus the excludes below keep them all out.
#
# This script does it correctly and then VERIFIES the result, so neither mistake can ship.

set -euo pipefail
cd "$(dirname "$0")/.."          # repo root, wherever this is run from

STAGING="staging"
OUT_DIR="dist"

# The single source of truth for the version is Config.version in the mod itself.
VERSION="$(sed -n 's/^Config\.version *= *"\([^"]*\)".*/\1/p' mod/JackieLives/config.lua)"
if [ -z "$VERSION" ]; then echo "❌ Could not read Config.version from mod/JackieLives/config.lua"; exit 1; fi

ZIP="$OUT_DIR/JackieLives-v${VERSION}.zip"

# --- sanity: staging must look like the game root -----------------------------------------------
for d in fomod bin r6; do
  [ -d "$STAGING/$d" ] || { echo "❌ staging/$d is missing — staging must mirror the game root."; exit 1; }
done

# --- the fomod version must match Config.version (Vortex shows this) ----------------------------
FOMOD_VER="$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' "$STAGING/fomod/info.xml" | head -1)"
if [ "$FOMOD_VER" != "$VERSION" ]; then
  echo "❌ Version mismatch: Config.version=$VERSION but fomod/info.xml=$FOMOD_VER"
  echo "   Bump BOTH before packaging."
  exit 1
fi

# --- purge Mac junk from staging BEFORE zipping -------------------------------------------------
find "$STAGING" \( -name '.DS_Store' -o -name '._*' \) -delete

mkdir -p "$OUT_DIR"
rm -f "$ZIP"

# --- build: cd INTO staging so its CONTENTS land at the archive root, not staging/ itself --------
#   -r  recurse   -X  drop Mac extended attributes / resource forks   -q  quiet
( cd "$STAGING" && zip -r -X -q "../$ZIP" . -x '.DS_Store' '**/.DS_Store' '__MACOSX/*' '._*' )

# --- VERIFY. A broken zip is worse than no zip, so prove all four properties. --------------------
# `unzip -Z1` prints the bare archive paths, one per line — no column formatting to trip the greps over.
echo "Built $ZIP"
echo
fail=0
PATHS="$(unzip -Z1 "$ZIP")"

echo "1. fomod/ must be at the archive ROOT (this is what makes Vortex/MO2 use the installer):"
if printf '%s\n' "$PATHS" | grep -qx 'fomod/ModuleConfig.xml'; then
  echo "   ✅ fomod/ModuleConfig.xml is at the top level"
else
  echo "   ❌ fomod/ModuleConfig.xml is NOT at the top level"; fail=1
fi

echo "2. No wrapper folder (nothing may sit under a 'staging/' prefix):"
if printf '%s\n' "$PATHS" | grep -q '^staging/'; then
  echo "   ❌ a staging/ wrapper folder leaked in"; fail=1
else
  echo "   ✅ no wrapper folder — bin/, fomod/, r6/ are the roots"
fi

echo "3. No Mac metadata:"
if printf '%s\n' "$PATHS" | grep -qE '__MACOSX|\.DS_Store|(^|/)\._'; then
  echo "   ❌ Mac junk (__MACOSX / .DS_Store / ._*) is in the archive"; fail=1
else
  echo "   ✅ clean — no __MACOSX, .DS_Store or ._* files"
fi

echo "4. The CET mod files are where the game expects them:"
if printf '%s\n' "$PATHS" | grep -qx 'bin/x64/plugins/cyber_engine_tweaks/mods/JackieLives/init.lua'; then
  echo "   ✅ init.lua is at bin/x64/plugins/cyber_engine_tweaks/mods/JackieLives/"
else
  echo "   ❌ init.lua is not at the expected path"; fail=1
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "❌ VERIFICATION FAILED — do NOT upload this zip."
  exit 1
fi

echo "✅ $ZIP is ready to upload to Nexus (v$VERSION, $(du -h "$ZIP" | cut -f1))."
