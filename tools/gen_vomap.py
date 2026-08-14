#!/usr/bin/env python3
r"""gen_vomap.py — make female V audible, by minting our own String IDs for her takes.

THE BUG THIS FIXES
  A female V spoke every borrowed line in a MALE voice, and no setting changed it. The full
  investigation is `docs/research/vo_gender.md`; the one-paragraph version:

  A line's male and female takes share ONE String ID. `locVoiceoverMap` maps that id to a PAIR of
  paths — `femaleResPath` and `maleResPath` — and the ENGINE picks the column, natively. Vanilla
  dialogue is played by the SCENE system, which attaches `scnDialogLineVoParams` (it has an
  `alwaysUseBrainGender` flag); our `DialogLineEvent` carries a stringId and nothing else, so the
  native resolver has nothing to go on and falls through to the male column. There is no gender
  field on the event struct, no gender argument anywhere on `AudioSystem`, and exactly one `v` voice
  tag — so NOTHING in Lua or redscript can express "give me the female take". That search is over;
  don't reopen it (`vo_gender.md` §6).

WHAT THIS DOES INSTEAD
  It adds new rows to the game's voiceover map. For every gendered line the mod speaks, it mints a
  SYNTHETIC String ID whose female AND male columns both point at the vanilla FEMALE `.wem`. Then
  `vo.lua` speaks the synthetic id when V's body is female, and the real id otherwise:

      male V    -> real id       -> vanilla male take, untouched
      female V  -> synthetic id  -> female take, both columns force it

  ArchiveXL merges our rows in rather than replacing anything
  (`OnLoadVoiceOvers`, Extension.cpp:327 — `entry.voMapChunks.PushBack(ref)`), so no vanilla entry is
  modified, nothing conflicts with another mod, and a user without ArchiveXL just gets today's
  behaviour instead of a crash.

  ⚠️ NEVER re-point the REAL id's male column instead. It is global — every male V would start
  hearing female takes, and an archive cannot read a setting to opt out.

  ⚠️ Lipsync is keyed off the String ID too, so a synthetic id has NO lipsync. That is invisible for
  V (first person). It would NOT be invisible for an on-screen NPC speaking V's lines — see
  `vo_gender.md` §7.3; ArchiveXL merges `lipmaps` by the same mechanism if that day comes.

WHAT IT WRITES  (both committed, so a machine without the game can still build)
  archive/source/mod/jackielives/vomaps/en-us/jackielives_vomap.json.json   the rows
  archive/source/mod/jackielives/onscreens/en-us/...json.json           the presence beacon
  mod/JackieLives/vo_female_ids.lua                                     realId -> syntheticId

  Neither contains audio or a word of CDPR text — only String IDs and depot paths. That is the whole
  reason this design was chosen over shipping a patched copy of CDPR's own map, which would have
  meant redistributing 30,184 of their entries (4.19 MB) to change fifty.

USAGE  (Mac only — it reads the installed game; the ARCHIVE is still packed on Windows)
    python3 tools/gen_vomap.py                 # regenerate both outputs
    python3 tools/gen_vomap.py --check         # exit 1 if they are out of date
    python3 tools/gen_vomap.py --redlib <dir>  # if cyberpunk-mods isn't a sibling checkout

  Re-run whenever config.lua gains `sfx = "jl_<digits>"` lines. After that, `python tools\
  build_archive.py` on Windows bakes it in — that step does NOT regenerate this, on purpose:
  redlib needs the game and a macOS Oodle dylib, neither of which the Windows box has.
"""

import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.normpath(os.path.join(HERE, ".."))
DEFAULT_REDLIB = os.path.join(PROJ, "..", "cyberpunk-mods", "TimedChoices")

# Every .lua that may carry a line id. voices.lua holds the packs; config.lua and convos.lua have
# carried the odd one. Scanning too widely is harmless — an id that isn't gendered is dropped below.
LUA_SOURCES = ["config.lua", "init.lua", "blaze.lua", "retrieval.lua"]

ARCH_SRC = os.path.join(PROJ, "archive", "source", "mod", "jackielives")
VOMAP_JSON = os.path.join(ARCH_SRC, "vomaps", "en-us", "jackielives_vomap.json.json")
BEACON_JSON = os.path.join(ARCH_SRC, "onscreens", "en-us", "jackielives_onscreens.json.json")
VOMAP_LUA = os.path.join(PROJ, "mod", "JackieLives", "vo_female_ids.lua")

# The archive-presence beacon. NCLives can ask "is my archive loaded?" by looking for one of its
# journal contacts; JackieLives ships no journal, so it ships ONE localization string instead and
# asks for it by key. Without a detector we could not tell "no archive" from "wrong gender", and
# speaking a synthetic id with no archive is SILENCE — the failure this whole design must never have.
BEACON_KEY = "jl_archive_beacon"
BEACON_VALUE = "jl-ok"

# The maps, by depot path. Addressed by PATH, never by archive index: indices move between patches
# and these do not. Recovered by reversing the archives' FNV1a64 file table against WolvenKit's
# `usedhashes.kark` dictionary — see docs/research/vo_gender.md §7.5 if they ever need re-checking.
VOMAPS = [
    ("lang_en_voice.archive", r"base\localization\en-us\voiceovermap.json"),
    ("lang_en_voice.archive", r"base\localization\en-us\voiceovermap_1.json"),
    ("lang_en_voice.archive", r"base\localization\en-us\voiceovermap_rewinded.json"),
    ("lang_en_voice.archive", r"base\localization\en-us\voiceovermap_holocall.json"),
    ("lang_en_voice.archive", r"base\localization\en-us\voiceovermap_helmet.json"),
    ("audio_1_general.archive", r"base\localization\common\voiceovermap.json"),
    ("audio_1_general.archive", r"base\localization\common\voiceovermap_rewinded.json"),
    ("audio_1_general.archive", r"base\localization\common\voiceovermap_holocall.json"),
    ("audio_1_general.archive", r"base\localization\common\voiceovermap_helmet.json"),
]

# Namespace for the synthetic ids. Anything stable and ours-only works; this string is part of the
# contract between the archive and vo_female_ids.lua, so CHANGING IT INVALIDATES EVERY BAKED ARCHIVE.
ID_NAMESPACE = "jackielives:vo:female:"


def load_redlib(path):
    path = os.path.abspath(path)
    if not os.path.isfile(os.path.join(path, "redlib.py")):
        sys.exit(f"redlib.py not found in {path}\n"
                 "It lives in the sibling cyberpunk-mods repo (TimedChoices/redlib.py).\n"
                 "Pass --redlib <dir> if your checkout is elsewhere.")
    sys.path.insert(0, path)
    import redlib  # noqa: E402
    return redlib


def wanted_ids():
    """Every `jl_<digits>` the mod's content can ask for, as decimal strings."""
    ids = set()
    for name in LUA_SOURCES:
        p = os.path.join(PROJ, "mod", "JackieLives", name)
        if not os.path.isfile(p):
            continue
        with open(p, encoding="utf-8") as f:
            ids.update(re.findall(r'"jl_(\d{6,})"', f.read()))
    return ids


def read_maps(redlib, content):
    """{stringId(str): (femaleResPath, maleResPath)} across every voiceover map the game ships."""
    out = {}
    for archive_name, depot in VOMAPS:
        path = os.path.join(content, archive_name)
        if not os.path.isfile(path):
            print(f"  ! {archive_name} not installed — skipping {depot}")
            continue
        arc = redlib.Archive(path)
        idx = arc.find(depot)
        if idx is None:
            print(f"  ! {depot} not found in {archive_name}. If the game updated, re-check the "
                  f"paths (docs/research/vo_gender.md §7.5).")
            continue
        cr = redlib.parse(arc.read_main(idx))
        root = cr.obj(cr.obj(0)["root"].index)
        n = 0
        # `.get(...) or []`: CR2W omits default-valued properties, so a map with no rows (the
        # common\voiceovermap_holocall.json case) simply has no `entries` key at all.
        for e in root.get("entries") or []:
            d = cr.obj(e.index) if hasattr(e, "index") else e
            sid = d.get("stringId")
            if sid is None:
                continue
            out[str(sid)] = (d.get("femaleResPath", ""), d.get("maleResPath", ""))
            n += 1
        print(f"  {depot}  {n} entries")
    return out


def synth_id(redlib, real_id, taken):
    """A stable, collision-free 64-bit id of our own for the female take of `real_id`.

    Derived from the id rather than counted, so the mapping is reproducible: rebuilding the archive
    on another machine, or after new lines are added, must not renumber the ids already baked into a
    shipped archive. Salted only on the (astronomically unlikely) collision, so that stability holds
    for every id that doesn't collide.
    """
    salt = 0
    while True:
        key = f"{ID_NAMESPACE}{real_id}" + (f"#{salt}" if salt else "")
        h = redlib.fnv1a64(key)
        if h and h not in taken:
            return h
        salt += 1


def build(redlib, content):
    want = wanted_ids()
    print(f"content ids in voices.lua & co: {len(want)}")
    print("reading the game's voiceover maps ...")
    maps = read_maps(redlib, content)
    print(f"  total {len(maps)} entries")

    rows, skipped_unknown, skipped_ungendered = [], [], []
    taken = set(int(k) for k in maps)
    for real in sorted(want, key=int):
        pair = maps.get(real)
        if pair is None:
            skipped_unknown.append(real)
            continue
        female, male = pair
        if not female or female == male:
            # Not a gendered line — one recording serves both, so there is nothing to fix and a
            # synthetic id would only cost us lipsync. This filter is also what separates V's lines
            # from the companion's for free: only V's corpus is recorded twice.
            skipped_ungendered.append(real)
            continue
        sid = synth_id(redlib, real, taken)
        taken.add(sid)
        rows.append((real, str(sid), female))

    print(f"gendered lines to remap: {len(rows)}")
    if skipped_ungendered:
        print(f"  {len(skipped_ungendered)} not gendered (one take serves both) — left alone")
    if skipped_unknown:
        print(f"  ⚠ {len(skipped_unknown)} id(s) not in any voiceover map: "
              f"{', '.join(skipped_unknown[:5])}{' …' if len(skipped_unknown) > 5 else ''}")
        print("    Those are silent today too — the engine has no recording under that id.")
    return rows


def render_json(rows):
    entries = [{
        "$type": "locVoLineEntry",
        "stringId": syn,
        # BOTH columns point at the female take on purpose: whichever column the engine decides to
        # read, it can only get the recording we want. That is the entire mechanism.
        "femaleResPath": {
            "DepotPath": {"$type": "ResourcePath", "$storage": "string", "$value": female},
            "Flags": "Soft",
        },
        "maleResPath": {
            "DepotPath": {"$type": "ResourcePath", "$storage": "string", "$value": female},
            "Flags": "Soft",
        },
    } for _real, syn, female in rows]

    doc = {
        "Header": {
            "WolvenKitVersion": "8.18.0",
            "WKitJsonVersion": "0.0.9",
            "GameVersion": 2310,
            "DataType": "CR2W",
            "ArchiveFileName": "jackielives_vomap.json",
        },
        "Data": {
            "Version": 195,
            "BuildVersion": 0,
            "RootChunk": {
                "$type": "JsonResource",
                "cookingPlatform": "PLATFORM_None",
                "root": {
                    "HandleId": "0",
                    "Data": {"$type": "locVoiceoverMap", "entries": entries},
                },
            },
            # No "EmbeddedFiles" key. ArchiveXL's wiki example carries one, but the file this repo
            # ALREADY ships through WolvenKit (onscreens/en-us) does not — and that one is proven to
            # deserialize on Antonia's box. A rejection here costs a Mac->Windows round trip, so match
            # the known-good file rather than the documentation.
        },
    }
    return json.dumps(doc, indent=2, ensure_ascii=False) + "\n"


def render_beacon():
    """One localization string, so Lua can prove the archive is really loaded.

    ArchiveXL merges this into the game's onscreens; `Game.GetLocalizedTextByKey(n"jl_archive_beacon")`
    then returns BEACON_VALUE if and only if BOTH ArchiveXL and our archive are installed. That is the
    same class of test NCLives makes against its journal entries — it just needs its own carrier here.
    `primaryKey` must be the FNV-1a 64 hash of the key, exactly as the game computes LocKey ids.
    """
    h = 0xCBF29CE484222325
    for b in BEACON_KEY.encode("utf-8"):
        h = ((h ^ b) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    doc = {
        "Header": {
            "WolvenKitVersion": "8.18.0",
            "WKitJsonVersion": "0.0.9",
            "GameVersion": 2310,
            "DataType": "CR2W",
            "ArchiveFileName": "jackielives_onscreens.json",
        },
        "Data": {
            "Version": 195,
            "BuildVersion": 0,
            "RootChunk": {
                "$type": "JsonResource",
                "cookingPlatform": "PLATFORM_None",
                "root": {
                    "HandleId": "0",
                    "Data": {
                        "$type": "localizationPersistenceOnScreenEntries",
                        "entries": [{
                            "$type": "localizationPersistenceOnScreenEntry",
                            "femaleVariant": BEACON_VALUE,
                            "maleVariant": BEACON_VALUE,
                            "primaryKey": str(h),
                            "secondaryKey": BEACON_KEY,
                        }],
                    },
                },
            },
        },
    }
    return json.dumps(doc, indent=2, ensure_ascii=False) + "\n"


def render_lua(rows):
    out = [
        "-- vo_female_ids.lua — GENERATED by tools/gen_vomap.py. Do not hand-edit.",
        "--",
        "-- realStringId -> the SYNTHETIC id whose voiceover-map row points at the FEMALE .wem.",
        "-- vo.lua speaks the synthetic one when V's body is female; see gen_vomap.py's header for",
        "-- why the engine cannot be asked for a gender directly, and docs/research/vo_gender.md",
        "-- for the whole investigation.",
        "--",
        "-- ⚠️ These ids only resolve if JackieLives.archive is installed AND ArchiveXL is present. When",
        "-- they don't resolve the line is silent, so vo.lua must never speak one without a fallback.",
        "--",
        "-- Numbers only — no CDPR text, no audio — so this file IS committed.",
        "",
        "local F = {",
    ]
    for real, syn, _female in rows:
        out.append(f'  ["{real}"] = "{syn}",')
    out += ["}", "", "return F", ""]
    return "\n".join(out)


def write_if_changed(path, text, check):
    old = None
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            old = f.read()
    rel = os.path.relpath(path, PROJ)
    if old == text:
        print(f"  = {rel} (up to date)")
        return True
    if check:
        print(f"  ! {rel} is OUT OF DATE — run: python3 tools/gen_vomap.py")
        return False
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"  + wrote {rel}")
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--redlib", default=DEFAULT_REDLIB)
    ap.add_argument("--content", default=None, help="the game's archive/.../content dir")
    ap.add_argument("--check", action="store_true", help="exit 1 if the outputs are stale")
    args = ap.parse_args()

    redlib = load_redlib(args.redlib)
    content = redlib.content_dir(args.content)
    if not os.path.isdir(content):
        # --check runs in the pre-deploy sweep, which must stay runnable on a machine without the
        # game. "I couldn't look" is not "they're stale", so say so and pass — the outputs are
        # committed precisely so such a machine can still build.
        if args.check:
            print(f"game not installed here ({content}) — skipping the freshness check.")
            sys.exit(0)
        sys.exit(f"game content dir not found: {content}\n"
                 "This tool reads the installed game. It only runs on the Mac.")

    rows = build(redlib, content)
    if not rows:
        sys.exit("no gendered lines found — refusing to write an empty map. "
                 "Check that config.lua still uses `sfx = \"jl_<digits>\"`.")

    ok = write_if_changed(VOMAP_JSON, render_json(rows), args.check)
    ok &= write_if_changed(BEACON_JSON, render_beacon(), args.check)
    ok &= write_if_changed(VOMAP_LUA, render_lua(rows), args.check)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
