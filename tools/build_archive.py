#!/usr/bin/env python3
r"""build_archive.py — build JackieLives.archive from the generated CR2W-JSON sources. WINDOWS ONLY.

    python tools\build_archive.py

This is the only step in the whole project that needs Windows, because it shells out to WolvenKit's
CLI. Everything upstream of it runs on the Mac.

WHAT IS IN THE ARCHIVE, AND WHY THERE IS ONE AT ALL
  Exactly two files, and neither is content:

    vomaps\en-us\jackielives_vomap.json     47 rows that make a female V audible
    onscreens\en-us\jackielives_onscreens.json  ONE string, the archive-presence beacon

  A line's male and female takes share ONE String ID and the ENGINE picks the column natively, so no
  Lua and no redscript can ask for a take (../NCLives/docs/research/vo_gender.md). The only lever is
  to put the female recording behind a String ID of our own and let ArchiveXL MERGE it into the
  game's voiceover index. The rows carry ids and depot paths only — no audio, nothing of CDPR's.

  ⚠️ This script does NOT regenerate the sources. `tools/gen_vomap.py` does, and it only runs on the
  MAC because it reads the installed game through redlib (which needs a macOS Oodle dylib). The
  generated files are COMMITTED precisely so this box can build without the game.

⚠️ WolvenKit.CLI.exe is a SEPARATE download — the normal WolvenKit app ships only WolvenKit.exe.
Get "WolvenKit.Console-<version>.zip" from https://github.com/WolvenKit/WolvenKit/releases and unzip
it; the exe is at the top level. Then set it in a .env file at the repo root:

    WOLVENKIT_CLI=C:\Tools\WolvenKit.Console\WolvenKit.CLI.exe
    CP2077_DIR=E:\SteamLibrary\steamapps\common\Cyberpunk 2077

⚠️ Cyberpunk locks installed archives while it is running. Close the game before deploying.
"""

import hashlib
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.normpath(os.path.join(HERE, ".."))
ARCH_SRC = os.path.join(PROJ, "archive", "source", "mod", "jackielives")
VOMAP_SRC = os.path.join(ARCH_SRC, "vomaps")
ONSCREEN_SRC = os.path.join(ARCH_SRC, "onscreens")
XL = os.path.join(PROJ, "archive", "pc", "mod", "JackieLives.archive.xl")
BUILD = os.path.join(PROJ, ".build")

STEAM_DEFAULT = r"E:\SteamLibrary\steamapps\common\Cyberpunk 2077"

# ⚠️ 2026-08-17 BUG FIX: this list is USED on two lines below and was never DEFINED, so the script
# died with `NameError: name 'WOLVENKIT_DEFAULTS' is not defined` before it did anything at all —
# including before it could print the helpful "here is where I looked" message, which is the one
# thing that block exists for. Ported from NCLives, which has had it all along; the two copies of
# this file drifted, as they do.
#
# Where WolvenKit's CLI actually lives, tried in order. `.env` and the environment still WIN, so a
# second machine overrides without touching this file — but on Antonia's box it just works, which is
# the point: .env is gitignored, so a fresh clone had no path and the build stopped on setup rather
# than on anything real.
WOLVENKIT_DEFAULTS = [
    r"C:\Users\donat\Desktop\Projects\Modding\Wolvenkit_CLI\WolvenKit.CLI.exe",
    r"C:\Tools\WolvenKit.Console\WolvenKit.CLI.exe",
]

def load_env():
    cfg = {}
    path = os.path.join(PROJ, ".env")
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, _, v = line.partition("=")
                    cfg[k.strip()] = v.strip().strip('"').strip("'")
    return cfg


def locale_sources(root, stem):
    """[(locale, path-to-the-.json.json)] under `root`, sorted so the digest is stable."""
    if not os.path.isdir(root):
        return []
    out = []
    for loc in sorted(os.listdir(root)):
        p = os.path.join(root, loc, stem)
        if os.path.isfile(p):
            out.append((loc, p))
    return out


def all_sources():
    return locale_sources(VOMAP_SRC, "jackielives_vomap.json.json") + \
           locale_sources(ONSCREEN_SRC, "jackielives_onscreens.json.json")


def source_digest():
    """One hash over every generated CR2W-JSON source that goes into the archive.

    `--digest` prints it without touching WolvenKit, so the Mac can check whether a committed archive
    is still current. ONE implementation on purpose: NCLives shipped a second copy of this loop inside
    its packaging script and the two silently drifted, leaving its staleness gate permanently red.
    """
    h = hashlib.sha256()
    for _loc, f in all_sources():
        with open(f, "rb") as fh:
            # normalise CRLF -> LF: the same content must hash the same whether the sources were
            # generated on Windows or on the Mac
            h.update(hashlib.sha256(fh.read().replace(b"\r\n", b"\n")).digest())
    return h.hexdigest()


def find_wolvenkit(cfg):
    """.env > environment > the known install paths. Returns None only if none of them exist."""
    for c in [cfg.get("WOLVENKIT_CLI"), os.environ.get("WOLVENKIT_CLI")] + WOLVENKIT_DEFAULTS:
        if c and os.path.isfile(c):
            return c
    return None


def find_game(cfg):
    for c in (cfg.get("CP2077_DIR"), os.environ.get("CP2077_DIR"), STEAM_DEFAULT):
        if c and os.path.isdir(c):
            return c
    return None


def main():
    if "--digest" in sys.argv:
        print(source_digest())
        return

    cfg = load_env()
    wk = find_wolvenkit(cfg)
    if not wk:
        print("ERROR: I couldn't find WolvenKit.CLI.exe. I looked here:")
        for c in WOLVENKIT_DEFAULTS:
            print("         %s" % c)
        print("       ...and at WOLVENKIT_CLI in .env / the environment.")
        print()
        print("       WolvenKit.CLI.exe is NOT part of the normal WolvenKit app (that's just")
        print("       WolvenKit.exe). Download WolvenKit.Console-<version>.zip from")
        print("       https://github.com/WolvenKit/WolvenKit/releases and unzip it.")
        sys.exit(1)

    sources = all_sources()
    if not sources:
        print("ERROR: no generated sources under archive/source/.")
        print("       Run `python3 tools/gen_vomap.py` on the MAC and commit what it writes —")
        print("       it reads the installed game, so this box cannot produce it.")
        sys.exit(1)
    print("[1/3] sources:", ", ".join(os.path.basename(p) for _l, p in sources))

    # CR2W-JSON -> CR2W. WolvenKit writes the binary next to the source, dropping the outer .json.
    print("[2/3] converting to CR2W ...")
    for _loc, src in sources:
        subprocess.run([wk, "convert", "deserialize", src], check=True)

    # Pack a CLEAN staging tree holding ONLY the CR2W binaries — the .json sources must not end up
    # inside the archive.
    print("[3/3] packing archive ...")
    if os.path.isdir(BUILD):
        shutil.rmtree(BUILD)
    stage = os.path.join(BUILD, "JackieLives")
    for kind, root, stem in (("vomaps", VOMAP_SRC, "jackielives_vomap.json.json"),
                             ("onscreens", ONSCREEN_SRC, "jackielives_onscreens.json.json")):
        for loc, src in locale_sources(root, stem):
            dst = os.path.join(stage, "mod", "jackielives", kind, loc)
            os.makedirs(dst, exist_ok=True)
            shutil.copy(src[: -len(".json")], dst)
    subprocess.run([wk, "pack", stage, "-o", BUILD], check=True)

    archive = os.path.join(BUILD, "JackieLives.archive")
    if not os.path.isfile(archive):
        print("ERROR: pack did not produce JackieLives.archive")
        sys.exit(2)

    out = os.path.join(PROJ, "archive", "pc", "mod", "JackieLives.archive")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    shutil.copy(archive, out)
    print("      wrote", os.path.relpath(out, PROJ))

    # Stamp WHAT this archive was built from, so the Mac (which can neither rebuild it nor easily
    # look inside it) can still refuse to ship a release whose voice map was never baked in.
    with open(os.path.join(PROJ, "archive", "pc", "mod", "JackieLives.archive.stamp"), "w") as f:
        f.write(source_digest() + "\n")
    print("      stamped it against the current sources")

    game = find_game(cfg)
    if not game:
        print("      no Cyberpunk 2077 install found — skipping deploy.")
        print(r"      Copy these two into <game>\archive\pc\mod\ yourself:")
        print(r"        JackieLives.archive, JackieLives.archive.xl")
    else:
        dst = os.path.join(game, "archive", "pc", "mod")
        os.makedirs(dst, exist_ok=True)
        try:
            shutil.copy(out, os.path.join(dst, "JackieLives.archive"))
            shutil.copy(XL, os.path.join(dst, "JackieLives.archive.xl"))
            print("      deployed to", dst)
        except (PermissionError, OSError) as e:
            print("      WARN: could not write the game's archive (%s)." % e.__class__.__name__)
            print("            Close the game and run this again.")


if __name__ == "__main__":
    main()
