#!/usr/bin/env python3
"""
scrape_jackie.py  -  Pull every Jackie Welles voice line from SoundDB into the
                     voice-tagger (transcript + String ID + real .ogg audio).

WHAT IT DOES
  1. Queries the public SoundDB API ( https://sounddb.zhincore.eu/v1 ) for
     `actor:Jackie` and pages through ALL of his lines (~977 for game v2.3).
  2. Writes  lines.json  next to index.html  -> the tagger imports it directly.
  3. (default) Downloads each line's preview audio to  audio/<id>.ogg  so you can
     LISTEN while tagging. Re-running skips files already on disk (resume-safe).

WHY THIS EXISTS
  SoundDB is a community catalogue of the game's voice-over. Its frontend plays a
  converted .ogg preview of every line from  static.zhincore.eu , and that URL is
  open, so we can fetch the same files for our own (personal, non-commercial)
  Cyberpunk mod. No WolvenKit extraction needed to start tagging.

USAGE  (PowerShell, from this folder)
  python scrape_jackie.py                 # metadata + audio (the full pull)
  python scrape_jackie.py --no-audio      # transcripts only, fast (~5 requests)
  python scrape_jackie.py --limit 20      # just the first 20 (quick test)
  python scrape_jackie.py --actor Misty   # someone else (any SoundDB actor)

Stdlib only - no pip installs. Python 3.9+.
"""

import argparse
import json
import os
import sys
import time
import urllib.parse
import urllib.request

API   = "https://sounddb.zhincore.eu/v1"
# Mirror of the frontend's getVoiceoverPreviewUrl(): PREVIEW + "vo/" + wem.replace(".wem",".ogg")
PREVIEW_BASE = "https://static.zhincore.eu/cp/vo/"
UA = "JackieLives-mod-tagger/1.0 (personal Cyberpunk 2077 mod; contact: local)"

HERE = os.path.dirname(os.path.abspath(__file__))

# Rough starting category from the line's scene context (you re-tag in the app).
CONTEXT_TO_CATEGORY = {
    "Vo_Context_Combat":        "combat",
    "Vo_Context_Quest":         "conversation",
    "Vo_Context_Community":     "conversation",
    "Vo_Context_Minor_Activity":"idle",
}


def http_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def fetch_all(actor, per_page, limit):
    """Page through /search/subtitles?q=actor:<actor> and return all items."""
    q = urllib.parse.quote(f"actor:{actor}")
    items, page = [], 1
    total = None
    while True:
        url = f"{API}/search/subtitles?q={q}&per_page={per_page}&page={page}"
        data = http_json(url)
        if data.get("syntaxErrors") or data.get("queryErrors"):
            print(f"  ! query problem: {data.get('syntaxErrors')} {data.get('queryErrors')}")
        if total is None:
            total = data.get("totalCount", 0)
            print(f"  SoundDB reports {total} lines for actor:{actor}")
        batch = data.get("items", [])
        if not batch:
            break
        items.extend(batch)
        print(f"  page {page}: +{len(batch)}  ({len(items)}/{total})")
        if limit and len(items) >= limit:
            items = items[:limit]
            break
        if len(items) >= total:
            break
        page += 1
        time.sleep(0.15)
    return items


def clean_text(t):
    """Light de-tag of <mothertongue .../> and <kiroshi .../> into readable text."""
    if not t or "<" not in t:
        return t or ""
    import re
    def repl(m):
        attrs = dict(re.findall(r'(\w)="(.*?)(?<!\\)"', m.group(1)))
        before = attrs.get("b", "")
        content = attrs.get("m", attrs.get("o", ""))
        after = attrs.get("a", "")
        return f"{before}{content}{after}"
    return re.sub(r'<(?:mothertongue|kiroshi)\s+(.+?)/>', repl, t).strip()


def pick_variant(item):
    """Return (gender, subitem) preferring a variant that has a transcript+vo.
    Jackie lines usually carry one variant; prefer female, fall back to male."""
    for g in ("female", "male"):
        s = item.get(g)
        if s and (s.get("text") or (s.get("vo") or {}).get("main")):
            return g, s
    return None, None


def collect_scene_meta(item):
    contexts, expressions, addressees, quests, actors = set(), set(), set(), set(), set()
    for scene in (item.get("scenes") or {}).values():
        for a in (scene.get("actors") or []):
            if a: actors.add(a)
        for a in (scene.get("addressees") or []):
            if a: addressees.add(a)
        for qpath in (scene.get("quests") or []):
            quests.add(qpath.replace("\\", "/").split("/")[-1].replace(".questphase", ""))
        for node in (scene.get("nodes") or {}).values():
            if isinstance(node, dict):
                if node.get("context"):    contexts.add(node["context"])
                if node.get("expression"): expressions.add(node["expression"])
    return contexts, expressions, addressees, quests, actors


def guess_category(contexts):
    # Combat wins if present (most specific), else first mapped context.
    if "Vo_Context_Combat" in contexts:
        return "combat"
    for c in contexts:
        if c in CONTEXT_TO_CATEGORY:
            return CONTEXT_TO_CATEGORY[c]
    return ""


def build_records(items):
    recs = []
    for it in items:
        gender, sub = pick_variant(it)
        if not sub:
            continue
        contexts, expressions, addressees, quests, actors = collect_scene_meta(it)
        wem = (sub.get("vo") or {}).get("main")
        rec = {
            "id":         str(it.get("id")),
            "file":       None,                       # set when audio is downloaded
            "transcript": clean_text(sub.get("text")) or "(no subtitle)",
            "category":   guess_category(contexts),
            # --- extra metadata (the mod uses these; tagger ignores them) ---
            "string_id":  str(it.get("id")),
            "raw_text":   sub.get("text") or "",
            "vo_wem":     wem,
            "lipsync":    sub.get("lipsyncAnim"),
            "gender":     gender,
            "context":    sorted(contexts),
            "expression": sorted(expressions),
            "addressees": sorted(addressees),
            "quests":     sorted(quests),
        }
        recs.append(rec)
    return recs


def preview_url(wem):
    return PREVIEW_BASE + wem[:-4] + ".ogg" if wem and wem.endswith(".wem") else None


def download_audio(recs, throttle):
    audio_dir = os.path.join(HERE, "audio")
    os.makedirs(audio_dir, exist_ok=True)
    ok = skip = miss = 0
    for i, rec in enumerate(recs, 1):
        url = preview_url(rec.get("vo_wem"))
        if not url:
            continue
        dest = os.path.join(audio_dir, rec["id"] + ".ogg")
        rel = "audio/" + rec["id"] + ".ogg"
        if os.path.exists(dest) and os.path.getsize(dest) > 0:
            rec["file"] = rel; skip += 1
            continue
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                blob = r.read()
            with open(dest, "wb") as f:
                f.write(blob)
            rec["file"] = rel; ok += 1
        except Exception as e:
            miss += 1
            if miss <= 10:
                print(f"  ! no audio for {rec['id']}: {e}")
        if i % 50 == 0:
            print(f"  audio {i}/{len(recs)}  (new {ok}, cached {skip}, missing {miss})")
        time.sleep(throttle)
    print(f"  audio done: {ok} downloaded, {skip} already had, {miss} missing")


def main():
    ap = argparse.ArgumentParser(description="Scrape an actor's voice lines from SoundDB into the tagger.")
    ap.add_argument("--actor", default="Jackie", help="SoundDB actor name (default: Jackie)")
    ap.add_argument("--no-audio", action="store_true", help="metadata only, skip audio download")
    ap.add_argument("--limit", type=int, default=0, help="only the first N lines (for testing)")
    ap.add_argument("--per-page", type=int, default=200, help="API page size")
    ap.add_argument("--throttle", type=float, default=0.06, help="seconds between audio downloads")
    ap.add_argument("--out", default=os.path.join(HERE, "lines.json"), help="output JSON path")
    args = ap.parse_args()

    print(f"Fetching '{args.actor}' lines from SoundDB ...")
    items = fetch_all(args.actor, args.per_page, args.limit)
    recs = build_records(items)
    print(f"Built {len(recs)} records.")

    if not args.no_audio:
        print("Downloading preview audio (Ctrl+C to stop; re-run resumes) ...")
        download_audio(recs, args.throttle)

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(recs, f, ensure_ascii=False, indent=1)
    have_audio = sum(1 for r in recs if r["file"])
    print(f"\nWrote {args.out}")
    print(f"  {len(recs)} lines  |  {have_audio} with audio  |  actor={args.actor}")
    if args.no_audio:
        print("  (metadata only - run without --no-audio to fetch the .ogg files)")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nInterrupted - partial audio is kept; re-run to resume.")
        sys.exit(1)
