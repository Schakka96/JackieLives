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

# --- translations must be in sync with the English source ---------------------------------------
# The English string IS the translation key, so editing or adding one player-facing line silently
# un-translates it in every language — it falls back to English, with no error anywhere. That is how
# v1.62/v1.64 shipped four untranslated strings to nine languages. A release is the last place to
# catch it, so catch it here. Non-blocking only if python3 is unavailable.
if command -v python3 >/dev/null 2>&1; then
  echo "Checking translations against the English source..."
  if ! python3 tools/lang_extract.py --check-all; then
    echo
    echo "❌ Translation drift — fix it, or ship English fallbacks to every non-English player."
    echo "   python3 tools/lang_extract.py --check <code>   shows the exact strings."
    exit 1
  fi
  echo
else
  echo "⚠️  python3 not found — SKIPPING the translation drift check."
fi

# --- staging must match mod/JackieLives ----------------------------------------------------------
# ⚠️ THE BUG THIS CLOSES (2026-08-14). This script had NO sync and NO drift check: it zipped whatever
# happened to be sitting in staging/, and staging is a hand-maintained COPY of mod/JackieLives. So it
# rots silently, and a zip built from rotted staging ships old code that passed every test you just
# ran on mod/ — the tests read mod/, the zip carries staging/.
#
# Not hypothetical: v1.69.1 was cut and handed over as "the dialogue-highlight fix", and its
# staging/dialogui.lua was 141 lines behind mod/. The zip did not contain the fix it was named after.
# (NCLucy's script already had this guard, and its header says the same thing happened there at v1.3.)
#
# So staging is verified file by file, and `--sync` fixes it rather than just complaining. mod/ is the
# source of truth; staging is only ever a copy of it.
SYNC=0
[ "${1:-}" = "--sync" ] && SYNC=1

CET_DIR="$STAGING/bin/x64/plugins/cyber_engine_tweaks/mods/JackieLives"
[ -f "$CET_DIR/init.lua" ] || { echo "❌ $CET_DIR/init.lua is missing."; exit 1; }

echo "Checking staging/ against mod/JackieLives..."
drift=0
for src in mod/JackieLives/*.lua mod/JackieLives/README.md; do
  [ -e "$src" ] || continue
  f="$(basename "$src")"
  if [ "$SYNC" -eq 1 ]; then cp "$src" "$CET_DIR/$f"; continue; fi
  if [ ! -f "$CET_DIR/$f" ]; then echo "   ❌ staging is MISSING $f"; drift=1; continue; fi
  diff -q "$src" "$CET_DIR/$f" >/dev/null 2>&1 || { echo "   ❌ staging's $f is out of date"; drift=1; }
done
# A .lua in staging with no counterpart in mod/ was deleted or renamed and left behind — CET would
# still load it, so it fails the build rather than shipping as a ghost.
for stale in "$CET_DIR"/*.lua; do
  [ -e "$stale" ] || continue
  f="$(basename "$stale")"
  [ -f "mod/JackieLives/$f" ] || { echo "   ❌ staging has an ORPHAN $f (not in mod/JackieLives — delete it)"; drift=1; }
done

# ⚠️ NEVER SHIP A .txt FROM THE CET FOLDER. JackieLives writes the player's own state next to
# init.lua (jl_settings.txt and friends). Shipping one would overwrite their tuning on update and look
# exactly like "the update broke the mod". The sync loop only copies *.lua and README.md, so this can
# only happen by hand or by running a tool from the wrong directory — which has happened before.
for stray in "$CET_DIR"/*.txt "$CET_DIR"/*.log "$CET_DIR"/*.log.prev; do
  [ -e "$stray" ] || continue
  echo "   ❌ staging contains PLAYER STATE: $(basename "$stray") — shipping it would overwrite the"
  echo "      player's own settings on update. Delete it from $CET_DIR and re-run."
  drift=1
done

# The redscript shim is a source file too, and it drifts the same way.
if [ -f "reds/JackieLivesVO.reds" ]; then
  mkdir -p "$STAGING/r6/scripts/JackieLives"
  if [ "$SYNC" -eq 1 ]; then
    cp reds/*.reds "$STAGING/r6/scripts/JackieLives/"
  elif ! diff -q reds/JackieLivesVO.reds "$STAGING/r6/scripts/JackieLives/JackieLivesVO.reds" >/dev/null 2>&1; then
    echo "   ❌ staging's JackieLivesVO.reds is out of date"; drift=1
  fi
fi

if [ "$SYNC" -eq 1 ]; then
  echo "   ✅ staging synced from mod/JackieLives"
elif [ "$drift" -ne 0 ]; then
  echo
  echo "   staging/ is out of sync. Re-run as:  ./tools/package_nexus.sh --sync"
  exit 1
else
  echo "   ✅ staging matches the mod source"
fi

# --- the voice archive (v1.71) -------------------------------------------------------------------
# What it is: 47 rows of our OWN String IDs pointing at the vanilla FEMALE .wem, merged into the
# game's voiceover index by ArchiveXL. It is what makes a female V, and a Jackie talking TO one,
# sound right — a line's two takes share one String ID and the ENGINE picks the male column
# (../NCLives/docs/research/vo_gender.md). No audio in it: ids and depot paths only.
#
# It is built on WINDOWS (WolvenKit), so this machine can neither rebuild it nor easily look inside.
# build_archive.py therefore leaves a .stamp of the sources it baked, and we compare — an archive
# built before the last gen_vomap.py run would ship String IDs the Lua references and the archive
# does not contain, i.e. SILENT lines, invisible until a player says so.
ARCHIVE_SRC="archive/pc/mod"
STAGING_ARCHIVE="$STAGING/archive/pc/mod"
if [ -f "$ARCHIVE_SRC/JackieLives.archive" ] && [ -f "$ARCHIVE_SRC/JackieLives.archive.xl" ]; then
  mkdir -p "$STAGING_ARCHIVE"
  cp "$ARCHIVE_SRC/JackieLives.archive" "$ARCHIVE_SRC/JackieLives.archive.xl" "$STAGING_ARCHIVE/"
  echo "   ✅ voice archive staged ($(du -h "$ARCHIVE_SRC/JackieLives.archive" | cut -f1))"
  if command -v python3 >/dev/null 2>&1; then
    # ONE implementation of the digest, in build_archive.py. A second copy here is exactly how
    # NCLives' equivalent gate silently rotted: the copy stopped hashing a source and could never
    # agree with the stamp again.
    STAMP_NOW="$(python3 tools/build_archive.py --digest)"
    STAMP_WAS="$(tr -d '\r\n' < "$ARCHIVE_SRC/JackieLives.archive.stamp" 2>/dev/null || echo none)"
    [ -n "$STAMP_WAS" ] || STAMP_WAS=none
    if [ "$STAMP_WAS" != "$STAMP_NOW" ]; then
      echo
      echo "❌ THE VOICE ARCHIVE IS STALE — it was built from different sources."
      echo "   Shipping it would reference String IDs the archive doesn't carry: V's gendered lines"
      echo "   would go SILENT instead of sounding female. Rebuild on the WINDOWS box:"
      echo "       build_archive.bat, then commit archive/pc/mod/ (all three files)"
      echo "   (stamp on disk: ${STAMP_WAS:0:12}...  sources now: ${STAMP_NOW:0:12}...)"
      exit 1
    fi
    echo "   ✅ ...and it matches the current voice map"
  fi
else
  # A stale copy must not ship either — a previous run may have left one in staging.
  rm -rf "$STAGING/archive"
  echo
  echo "⚠️  NO VOICE ARCHIVE — this zip ships WITHOUT it, so a female V keeps the MALE takes."
  echo "   That is the pre-v1.71 behaviour, not a crash: the mod detects the missing archive and"
  echo "   falls back. To include it, build it on Windows (double-click build_archive.bat) and"
  echo "   commit archive/pc/mod/."
fi

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

echo "5. The redscript voice shim is aboard (v1.66 — this is what gives Jackie his voice):"
if printf '%s\n' "$PATHS" | grep -qx 'r6/scripts/JackieLives/JackieLivesVO.reds'; then
  echo "   ✅ r6/scripts/JackieLives/JackieLivesVO.reds"
else
  echo "   ❌ JackieLivesVO.reds is MISSING — every player would get a silent Jackie."; fail=1
fi

echo "6. No CDPR audio leaked in (the one mistake that gets a page taken down):"
if printf '%s\n' "$PATHS" | grep -qiE '\.(ogg|wav|wem|opuspak|opusinfo)$'; then
  echo "   ❌ audio files are in the archive — CDPR assets are NOT redistributable"
  printf '%s\n' "$PATHS" | grep -iE '\.(ogg|wav|wem|opuspak|opusinfo)$' | sed 's/^/      /'
  fail=1
else
  echo "   ✅ no audio of any kind — nothing to redistribute, nothing to get wrong"
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "❌ VERIFICATION FAILED — do NOT upload this zip."
  exit 1
fi

echo "✅ $ZIP is ready to upload to Nexus (v$VERSION, $(du -h "$ZIP" | cut -f1))."
