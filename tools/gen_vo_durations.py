#!/usr/bin/env python3
"""Generate `mod/JackieLives/vo_durations.lua` — how long each voiced line lasts.

WHY THIS EXISTS
  With the native VO route (docs/research/native_vo_dialogline.md) we no longer ship or
  extract audio, so we can no longer ask Audioware "how long is this clip?". But we still
  need the length: it paces the subtitle, the mouth flap, and the gap before the next line.

  The game knows. Every dialogue line in a `.scene` has a `scnDialogLineEvent` with a
  `duration`, and that is the same number the game itself uses when the line plays in a
  scene. So we read it out of the player's own install — exactly, not estimated.

HOW IT WORKS
  1. Scan the mod's Lua for every `jl_<digits>` the content actually references. Only those
     get a duration; there is no point shipping 977 numbers to play 55 lines.
  2. Ask SoundDB (metadata only — no audio downloads) which `.scene` each line lives in.
  3. Read those scenes from the LOCAL game install with redlib and pull the duration:
       screenplayStore.lines[].locstringId.ruid   == the String ID
       screenplayStore.lines[].itemId.id          == the screenplay line id
       scnDialogLineEvent.screenplayLineId.id     -> .duration   (milliseconds)
  4. Write a Lua table. Durations are plain numbers — no CDPR text, nothing copyrighted,
     so unlike index.json/transcripts.json this file IS committed.

USAGE (Mac or Windows, both fine — this reads the game, it doesn't run it)
    python3 tools/gen_vo_durations.py
    python3 tools/gen_vo_durations.py --actor Jackie --actor Misty
    python3 tools/gen_vo_durations.py --check      # exit 1 if the committed table is stale

REQUIREMENTS
  redlib.py — the archive reader + CR2W parser, from the sibling `cyberpunk-mods` repo.
  Point --redlib at it if your layout differs. Nothing else; stdlib only.
"""

import argparse
import json
import os
import re
import sys
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEFAULT_REDLIB = os.path.join(ROOT, "..", "cyberpunk-mods", "TimedChoices")
OUT = os.path.join(ROOT, "mod", "JackieLives", "vo_durations.lua")
LUA_DIR = os.path.join(ROOT, "mod", "JackieLives")
MOD_NAME = "JackieLives"

API = "https://sounddb.zhincore.eu/v1"
UA = "JackieLives-mod/1.0 (personal Cyberpunk 2077 mod)"

# A line shorter than this is almost certainly a parse error, not a real line; longer than
# this and something is wrong with the units. Both are asserted, not assumed.
MIN_SEC, MAX_SEC = 0.2, 60.0


def referenced_ids(lua_dir):
    """Every jl_<digits> the content actually plays."""
    ids = set()
    for name in sorted(os.listdir(lua_dir)):
        if not name.endswith(".lua"):
            continue
        with open(os.path.join(lua_dir, name), encoding="utf-8") as fh:
            ids.update(re.findall(r"\bjl_(\d{6,})\b", fh.read()))
    return ids


def http_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def scene_index(actors, per_page=250):
    """{string_id: [scene depot paths]} for every line by these actors. Metadata only."""
    out = {}
    for actor in actors:
        q = urllib.parse.quote(f"actor:{actor}")
        page, total = 1, None
        while True:
            data = http_json(f"{API}/search/subtitles?q={q}&per_page={per_page}&page={page}")
            if total is None:
                total = data.get("totalCount", 0)
                print(f"  SoundDB: {total} lines for actor:{actor}")
            items = data.get("items", [])
            if not items:
                break
            for it in items:
                sid = str(it.get("id") or "")
                if sid:
                    out.setdefault(sid, []).extend((it.get("scenes") or {}).keys())
            if len(out) >= total or len(items) < per_page:
                break
            page += 1
    return out


def load_redlib(path):
    path = os.path.abspath(path)
    if not os.path.isfile(os.path.join(path, "redlib.py")):
        sys.exit(
            f"redlib.py not found in {path}\n"
            "It lives in the sibling cyberpunk-mods repo (TimedChoices/redlib.py).\n"
            "Pass --redlib <dir> if your checkout is elsewhere."
        )
    sys.path.insert(0, path)
    import redlib  # noqa: E402
    return redlib


def durations_from_scene(redlib, archives_cache, scene_path):
    """{string_id: seconds} for every line in one .scene."""
    res = None
    for arc in archives_cache:
        idx = arc.find(scene_path)
        if idx is not None:
            res = redlib.parse(arc.read_main(idx))
            break
    if res is None:
        return {}

    root = res.obj(0)
    store = (root or {}).get("screenplayStore") or {}
    # screenplay line id -> string id
    by_item = {}
    for line in store.get("lines") or []:
        item = (line.get("itemId") or {}).get("id")
        ruid = (line.get("locstringId") or {}).get("ruid")
        if item is not None and ruid:
            by_item[item] = str(ruid)

    out = {}
    for i in range(len(res.exports)):
        if res.class_of(i) != "scnDialogLineEvent":
            continue
        ev = res.obj(i) or {}
        item = (ev.get("screenplayLineId") or {}).get("id")
        dur = ev.get("duration")
        sid = by_item.get(item)
        if sid and isinstance(dur, (int, float)) and dur > 0:
            secs = round(dur / 1000.0, 3)
            # A line can appear in several events (variants, retakes). Keep the longest:
            # a subtitle that outlives its audio reads as a pause, one that dies early
            # reads as a bug.
            if secs > out.get(sid, 0):
                out[sid] = secs
    return out


def render(table, missing):
    lines = [
        "-- vo_durations.lua — GENERATED by tools/gen_vo_durations.py. Do not hand-edit.",
        "--",
        "-- How long each voiced line lasts, in seconds, read from the game's own .scene files",
        "-- (scnDialogLineEvent.duration). Used to pace subtitles and the mouth flap now that we",
        "-- no longer ship audio and so can no longer ask Audioware for a clip length.",
        "--",
        "-- Numbers only — no CDPR text — so this file IS committed, unlike index.json.",
        "-- Missing entries are not an error: VO.duration() falls back to reading time.",
        "",
        "local D = {",
    ]
    for sid in sorted(table, key=int):
        lines.append(f"  [\"{sid}\"] = {table[sid]:.3f},")
    lines.append("}")
    lines.append("")
    if missing:
        lines.append("-- No duration found for these referenced ids (reading-time fallback applies):")
        for sid in sorted(missing, key=int):
            lines.append(f"--   jl_{sid}")
        lines.append("")
    lines.append("return D")
    lines.append("")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--actor", action="append", default=None,
                    help="SoundDB actor to index (repeatable). Default: Jackie.")
    ap.add_argument("--redlib", default=DEFAULT_REDLIB)
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--lua-dir", default=LUA_DIR)
    ap.add_argument("--check", action="store_true",
                    help="don't write; exit 1 if the committed table differs")
    args = ap.parse_args()
    actors = args.actor or ["Jackie"]

    ids = referenced_ids(args.lua_dir)
    print(f"{MOD_NAME}: {len(ids)} distinct voiced line ids referenced by the content")
    if not ids:
        sys.exit("no jl_<digits> ids found — wrong --lua-dir?")

    print("Asking SoundDB which scenes they live in (metadata only, no audio)...")
    index = scene_index(actors)
    wanted = {sid: index.get(sid, []) for sid in ids}
    unknown = [s for s, v in wanted.items() if not v]
    scenes = sorted({p for v in wanted.values() for p in v})
    print(f"  {len(scenes)} scenes to read; {len(unknown)} ids SoundDB doesn't place in a scene")

    redlib = load_redlib(args.redlib)
    content = redlib.content_dir()
    print(f"Reading the local install: {content}")
    archives = [redlib.Archive(p) for p in redlib.archives(content)]
    try:
        found = {}
        for n, scene in enumerate(scenes, 1):
            path = scene.replace("/", "\\")
            for sid, secs in durations_from_scene(redlib, archives, path).items():
                if sid in ids and secs > found.get(sid, 0):
                    found[sid] = secs
            if n % 25 == 0 or n == len(scenes):
                print(f"  {n}/{len(scenes)} scenes — {len(found)}/{len(ids)} ids resolved")
    finally:
        for a in archives:
            a.close()

    # v1.69 FALLBACK. SoundDB doesn't place every line in a scene — the voice-set lines ("Make
    # moves, chica.", "You with me, chica?") aren't in one at all, so the scan above returns
    # nothing for them and the mod paces those subtitles by READING TIME, which for a one-second
    # line means it hangs around for two and a half. NCLives' line library already read a duration
    # for every line straight out of the game, so use it for whatever the scan missed. Optional:
    # no library (a checkout without the game) just leaves those ids as they were.
    #
    # ⚠️ v1.70 — READ **V'S** LIBRARY TOO, NOT JUST JACKIE'S. The SoundDB step above asks for
    # `actor:Jackie`, so it structurally cannot place a single one of V's lines — and since
    # v1.70 the content is full of them (V speaks her own choice rows now). Every one of those
    # came back with no duration and got paced by reading time, which is wrong in both
    # directions: it cuts "Hey!" off late and clips "It's good to see you, too, Jack. How ya
    # been?" short. Both libraries are read here, local first, so whichever repo has been built
    # supplies the number.
    here = os.path.dirname(__file__)
    libs = []
    for repo in (os.path.join(here, ".."), os.path.join(here, "..", "..", "NCLives")):
        for who in ("jackie", "v"):
            libs.append(os.path.join(repo, "vo_library", f"{who}.json"))
    still = ids - set(found)
    secs = {}
    for lib in libs:
        if not os.path.exists(lib):
            continue
        with open(lib, encoding="utf-8") as fh:
            for l in json.load(fh)["lines"]:
                secs.setdefault(l["id"], l.get("seconds") or 0)
    if still and secs:
        rescued = 0
        for sid in sorted(still):
            v = secs.get(sid, 0)
            if MIN_SEC <= v <= MAX_SEC:
                found[sid] = v
                rescued += 1
        if rescued:
            print(f"  +{rescued} duration(s) from the line libraries (not placed in any scene)")

    bad = {s: v for s, v in found.items() if not (MIN_SEC <= v <= MAX_SEC)}
    if bad:
        sys.exit(f"durations outside the sane range {MIN_SEC}-{MAX_SEC}s — units wrong? {bad}")

    missing = sorted(ids - set(found))
    text = render(found, missing)

    if args.check:
        old = open(args.out, encoding="utf-8").read() if os.path.exists(args.out) else ""
        if old != text:
            sys.exit(f"STALE: {args.out} does not match the game data — re-run without --check")
        print("up to date")
        return

    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(text)
    print(f"\nwrote {args.out}: {len(found)} durations, {len(missing)} without one")
    if missing:
        print("  no duration for: " + ", ".join("jl_" + m for m in missing[:10])
              + (" ..." if len(missing) > 10 else ""))


if __name__ == "__main__":
    main()
