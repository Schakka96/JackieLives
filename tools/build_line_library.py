#!/usr/bin/env python3
"""build_line_library.py — every line a character ever recorded, read from the local game.

WHY THIS EXISTS
  Writing voiced dialogue for a persona means picking from what CDPR actually recorded for
  that actor (docs/research/native_vo_dialogline.md: we play the game's own take by String
  ID, we never make new audio). So the writing question is always "what CAN she say?" —
  and until now the only answer was JackieLives' route: extract 1200 .wav files with
  WolvenKit and run Whisper over them. That cost a Windows box, a 940 MB export, an hour of
  transcription, and it still only recovered 777 of Jackie's 977 lines, in Whisper's words
  rather than CDPR's.

  None of that is necessary. The game ships every subtitle as text, and every scene knows
  who speaks each line and for how long. Both are readable on the Mac with redlib. This
  script joins them:

      lang_en_text.archive                     stringId -> the exact subtitle text
        localizationPersistenceSubtitleEntries      (75k lines, ~0.5 s)
      every *.scene in the base archives       who says it, how long, to whom
        actors[].voicetagId                        the character (stable game-wide)
        screenplayStore.lines[].speaker            which actor says this line
        screenplayStore.lines[].locstringId.ruid   == the String ID
        scnDialogLineEvent.duration                milliseconds
        scnDialogLineEvent.voParams                phone call? radio? shouted?

  Result: ~2100 Panam lines, ~1400 Judy, ~1000 River, with CDPR's own punctuation — in
  about a hundred seconds, from the install that is already on this machine.

WHAT IT WRITES  (all of it into vo_library/, which is GITIGNORED)
  vo_library/<persona>.json   the library — id, text, seconds, addressee, context, scene
  vo_library/<persona>.csv    same, for a spreadsheet
  vo_library/<persona>.html   a browsable, searchable page — this is the one to write from
  vo_library/_scan.json       the raw game scan, so later runs are instant

  ⚠️ The text is CDPR's, so NOTHING under vo_library/ may be committed or shipped
  (GROUND_RULES: game assets are not redistributable). It is regenerated from the player's
  — or the writer's — own install in ~100 s. Only tools/voicetags.json is committed, and
  that file holds nothing but numbers and character names.

USAGE
    python3 tools/build_line_library.py build                 # everyone in voicetags.json
    python3 tools/build_line_library.py build --persona panam
    python3 tools/build_line_library.py build --all-speakers  # also every unnamed voicetag
    python3 tools/build_line_library.py search panam aldecaldo
    python3 tools/build_line_library.py search judy "^No\\b" --max 3.0
    python3 tools/build_line_library.py discover                       # name the voicetags
    python3 tools/build_line_library.py discover --sounddb Claire      # name a hard one

  `build` and `discover` scan the game once and cache it; add --rescan to force a re-read.
  `search` never touches the game.

REQUIREMENTS
  redlib.py from the sibling cyberpunk-mods repo (TimedChoices/redlib.py) — pass --redlib if
  your checkout is elsewhere. Stdlib only otherwise. Reads the game; never runs it, so the
  Mac is fine.
"""

import argparse
import collections
import csv
import html
import json
import os
import re
import sys
import unicodedata
import time
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEFAULT_REDLIB = os.path.join(ROOT, "..", "cyberpunk-mods", "TimedChoices")
VOICETAGS = os.path.join(HERE, "voicetags.json")
OUTDIR = os.path.join(ROOT, "vo_library")
SCAN = os.path.join(OUTDIR, "_scan.json")

API = "https://sounddb.zhincore.eu/v1"
UA = "NCLives-mod/1.0 (personal Cyberpunk 2077 mod)"


# ── the game scan ───────────────────────────────────────────────────────────

def load_redlib(path):
    path = os.path.abspath(path)
    if not os.path.isfile(os.path.join(path, "redlib.py")):
        sys.exit(f"redlib.py not found in {path}\n"
                 "It lives in the sibling cyberpunk-mods repo (TimedChoices/redlib.py).\n"
                 "Pass --redlib <dir> if your checkout is elsewhere.")
    sys.path.insert(0, path)
    import redlib  # noqa: E402
    return redlib


def subtitle_text(redlib, content):
    """{stringId: [femaleVariant, maleVariant]} — every subtitle the English build ships."""
    out = {}
    arc = redlib.Archive(os.path.join(content, "lang_en_text.archive"))
    for _h, data in arc.iter_main():
        try:
            res = redlib.parse(data)
        except Exception:
            continue
        for i in range(len(res.exports)):
            if res.class_of(i) != "localizationPersistenceSubtitleEntries":
                continue
            for e in res.obj(i).get("entries") or []:
                sid = e.get("stringId")
                if sid:
                    out[str(sid)] = [e.get("femaleVariant") or "", e.get("maleVariant") or ""]
    arc.close()
    return out


def scene_label(names):
    """A readable name for a scene, recovered from its actors' spawn names.

    Archives key files by FNV1a64 hash, never by path, so a scene cannot tell us its own
    depot path while we iterate. It doesn't have to: CDPR names each spawned actor after the
    scene it belongs to — 'a_mq055_01_megabuilding_panam', 'a_mq055_01_megabuilding_judy' —
    so the shared prefix IS the scene. Good enough to answer "where is this line from".
    """
    stems = [re.sub(r"^[a-z]_", "", n) for n in names if n]
    if not stems:
        return ""
    parts = [s.split("_") for s in stems]
    common = parts[0]
    for p in parts[1:]:
        k = 0
        while k < min(len(common), len(p)) and common[k] == p[k]:
            k += 1
        common = common[:k]
    if len(common) >= 2:
        return "_".join(common)
    return "_".join(parts[0][:-1]) or stems[0]


def scan_game(redlib, content):
    """Read every scene: {voicetag: {stringId: row}} plus the spawn names each tag was seen under.

    A `voicetagId` is the character. It is stable across the whole game — Panam is
    1196850303899549696 in the prologue and in the epilogue — which is what makes a
    per-character library possible at all. `speaker` on a screenplay line is an *actorId*,
    local to that scene, so it has to be resolved through the scene's own actor list first.
    """
    lib = collections.defaultdict(dict)
    seen_names = collections.defaultdict(collections.Counter)
    scenes = 0
    for path in redlib.archives(content):
        arc = redlib.Archive(path)
        for _h, data in arc.iter_main():
            try:
                res = redlib.parse(data)
            except Exception:
                continue
            if res.root_class != "scnSceneResource":
                continue
            root = res.obj(0) or {}
            lines = (root.get("screenplayStore") or {}).get("lines") or []
            if not lines:
                continue
            scenes += 1

            vt_of, spawn_names = {}, []
            for act in (root.get("actors") or []):
                aid = (act.get("actorId") or {}).get("id", 0)
                vt = (act.get("voicetagId") or {}).get("id")
                nm = (act.get("spawnDespawnParams") or {}).get("dynamicEntityUniqueName") or ""
                vt_of[aid] = str(vt) if vt else ""
                if nm:
                    spawn_names.append(nm.lower())
                    if vt:
                        seen_names[str(vt)][nm.lower()] += 1
            for act in (root.get("playerActors") or []):
                aid = (act.get("actorId") or {}).get("id", 0)
                vt = (act.get("voicetagId") or {}).get("id")
                vt_of[aid] = str(vt) if vt else ""
                if vt:
                    seen_names[str(vt)]["v"] += 1
            label = scene_label(spawn_names)

            # duration + delivery live on the events, keyed by screenplay line id
            dur, vop = {}, {}
            for i in range(len(res.exports)):
                if res.class_of(i) != "scnDialogLineEvent":
                    continue
                ev = res.obj(i) or {}
                iid = (ev.get("screenplayLineId") or {}).get("id")
                if iid is None:
                    continue
                d = ev.get("duration")
                # One line can have several events (retakes, variants). The longest is the
                # real one: a subtitle that outlives its audio reads as a pause, one that
                # dies early reads as a bug.
                if isinstance(d, (int, float)) and d > dur.get(iid, 0):
                    dur[iid] = d
                pr = ev.get("voParams") or {}
                if pr:
                    vop[iid] = [str(pr.get("voContext") or ""), str(pr.get("voExpression") or "")]

            for ln in lines:
                sid = str((ln.get("locstringId") or {}).get("ruid") or "")
                if not sid or sid == "0":
                    continue
                vt = vt_of.get((ln.get("speaker") or {}).get("id", 0), "")
                if not vt:
                    continue
                iid = (ln.get("itemId") or {}).get("id")
                secs = round(dur.get(iid, 0) / 1000.0, 3)
                ctx, exp = vop.get(iid, ["", ""])
                row = lib[vt].get(sid)
                if row is None:
                    lib[vt][sid] = {
                        "s": secs,
                        "to": vt_of.get((ln.get("addressee") or {}).get("id", -1), ""),
                        "ctx": ctx, "exp": exp,
                        "sc": [label] if label else [],
                        "n": 1,
                    }
                else:
                    # The same line turns up again in the game's `versions\<patch>\` copies
                    # of a scene, and in genuinely different scenes. Fold, don't double-count.
                    row["n"] += 1
                    if secs > row["s"]:
                        row["s"] = secs
                    if ctx and not row["ctx"]:
                        row["ctx"], row["exp"] = ctx, exp
                    if label and label not in row["sc"] and len(row["sc"]) < 6:
                        row["sc"].append(label)
        arc.close()
    return lib, seen_names, scenes


def do_scan(args):
    redlib = load_redlib(args.redlib)
    content = redlib.content_dir()
    print(f"game: {content}")

    t = time.time()
    text = subtitle_text(redlib, content)
    print(f"  subtitles: {len(text)} lines ({time.time() - t:.1f}s)")

    t = time.time()
    lib, names, scenes = scan_game(redlib, content)
    print(f"  scenes:    {scenes} parsed, {len(lib)} distinct voices ({time.time() - t:.1f}s)")

    os.makedirs(OUTDIR, exist_ok=True)
    blob = {"text": text, "lib": lib, "names": {k: dict(v) for k, v in names.items()}}
    with open(SCAN, "w", encoding="utf-8") as fh:
        json.dump(blob, fh)
    return blob


def get_scan(args):
    if not args.rescan and os.path.isfile(SCAN):
        with open(SCAN, encoding="utf-8") as fh:
            print(f"using cached scan ({os.path.getsize(SCAN) // 1_000_000} MB) — --rescan to re-read the game")
            return json.load(fh)
    return do_scan(args)


# ── naming the voices ───────────────────────────────────────────────────────

def vote_name(counter):
    """Guess a character name for a voicetag from the actor names it was spawned under."""
    words = collections.Counter()
    for nm, n in counter.items():
        parts = re.sub(r"^[a-z]_", "", nm).split("_")
        for p in parts[-2:]:
            if p and not p.isdigit():
                words[p] += n
    return [w for w, _ in words.most_common(3)]


def sounddb_ids(actor, per_page=5):
    """A few String IDs SoundDB attributes to this actor — used to identify a voicetag."""
    q = urllib.parse.quote(f"actor:{actor}")
    req = urllib.request.Request(f"{API}/search/subtitles?q={q}&per_page={per_page}",
                                 headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = json.load(r)
    return data.get("totalCount", 0), [str(i["id"]) for i in data.get("items", []) if i.get("id")]


def load_tags():
    if os.path.isfile(VOICETAGS):
        with open(VOICETAGS, encoding="utf-8") as fh:
            return json.load(fh)
    return {}


def cmd_discover(args):
    blob = get_scan(args)
    lib, names = blob["lib"], blob["names"]
    tags = load_tags()

    if args.sounddb:
        # The spawn-name vote fails for anyone the game never spawns by name — Claire came
        # out as "female". Ask SoundDB for a handful of that actor's String IDs and see which
        # voicetag owns them locally. One matched id is already decisive; five is proof.
        total, ids = sounddb_ids(args.sounddb)
        owner = collections.Counter()
        for vt, rows in lib.items():
            for sid in ids:
                if sid in rows:
                    owner[vt] += 1
        if not owner:
            sys.exit(f"no local voicetag owns any of SoundDB's {args.sounddb} lines — wrong name?")
        vt, hits = owner.most_common(1)[0]
        key = args.sounddb.lower()
        print(f"{args.sounddb}: voicetag {vt} ({hits}/{len(ids)} SoundDB ids matched), "
              f"{len(lib[vt])} local lines, SoundDB counts {total}")
        tags[key] = {"voicetag": vt, "aka": vote_name(names.get(vt, {}))}
        with open(VOICETAGS, "w", encoding="utf-8") as fh:
            json.dump(tags, fh, indent=2, sort_keys=True)
            fh.write("\n")
        print(f"wrote {os.path.relpath(VOICETAGS, ROOT)}")
        return

    known = {v["voicetag"] for v in tags.values()}
    rank = sorted(lib.items(), key=lambda kv: -len(kv[1]))
    print(f"\n{'name':<16}{'lines':>7}  voicetag              also seen as")
    for vt, rows in rank[:args.top]:
        guess = vote_name(names.get(vt, {}))
        mark = "*" if vt in known else " "
        print(f"{mark}{(guess[0] if guess else '?'):<15}{len(rows):>7}  {vt:<21} {' '.join(guess[1:])}")
    print("\n* = already in tools/voicetags.json. For a voice the guess got wrong, identify it "
          "with:\n    python3 tools/build_line_library.py discover --sounddb <ActorName>")


# ── the library ─────────────────────────────────────────────────────────────

def build_rows(blob, vt, tags):
    """The finished per-line records for one voicetag, newest-first by nothing — sorted by text."""
    text, lib = blob["text"], blob["lib"]
    who = {v["voicetag"]: k for k, v in tags.items()}
    out = []
    for sid, r in lib.get(vt, {}).items():
        f, m = text.get(sid, ["", ""])
        if not f and not m:
            continue          # a recorded line with no shipped subtitle — nothing to write with
        to = r.get("to") or ""
        out.append({
            "id": sid,                       # ⚠️ STRING. ~2e18 does not survive a Lua double.
            "text": f or m,
            "text_male": m if (m and m != f) else "",
            "seconds": r["s"],
            "to": "V" if to and who.get(to) == "v" else (who.get(to) or ""),
            "context": r.get("ctx", ""),
            "expression": r.get("exp", ""),
            "scenes": r.get("sc", []),
            "uses": r["n"],
        })
    out.sort(key=lambda r: (r["text"].lower(), r["id"]))
    return out


def write_json(path, persona, rows):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump({"persona": persona, "count": len(rows), "lines": rows}, fh,
                  indent=1, ensure_ascii=False)


def write_csv(path, rows):
    cols = ["id", "text", "text_male", "seconds", "to", "context", "expression", "uses", "scenes"]
    with open(path, "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(cols)
        for r in rows:
            w.writerow([r["id"], r["text"], r["text_male"], r["seconds"], r["to"],
                        r["context"], r["expression"], r["uses"], " ".join(r["scenes"])])


HTML_HEAD = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>%(persona)s — line library</title>
<style>
:root{--bg:#0a0c0f;--panel:#12161c;--panel2:#171d25;--line:#2a323d;--text:#dfe6ee;
 --muted:#8a95a3;--yellow:#f8db4b;--cyan:#73eff0;--pink:#ff5fa2;--ok:#5ee08a}
*{box-sizing:border-box}html,body{margin:0}
body{background:var(--bg);color:var(--text);font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
header{position:sticky;top:0;z-index:9;display:flex;gap:12px;align-items:center;flex-wrap:wrap;
 padding:10px 18px;background:var(--panel);border-bottom:1px solid var(--line)}
.brand{font-weight:700;letter-spacing:1px;color:var(--yellow)}.brand span{color:var(--pink)}
.stats{font-size:12px;color:var(--muted)}
input,select{padding:7px 10px;border:1px solid var(--line);border-radius:6px;
 background:var(--bg);color:var(--text);font-size:14px}
#q{flex:1;min-width:200px;max-width:420px}
input:focus,select:focus{outline:none;border-color:var(--cyan)}
main{padding:16px 18px 120px}
table{border-collapse:collapse;width:100%%;max-width:1200px}
th{position:sticky;top:53px;background:var(--panel2);text-align:left;font-size:11px;
 letter-spacing:1.1px;text-transform:uppercase;color:var(--muted);padding:8px 10px;
 border-bottom:1px solid var(--line);cursor:pointer;user-select:none}
td{padding:7px 10px;border-bottom:1px solid var(--line);vertical-align:top}
tr:hover td{background:var(--panel)}
.id{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11.5px;color:var(--muted);
 cursor:pointer;white-space:nowrap}
.id:hover{color:var(--cyan)}
.sec{color:var(--muted);font-size:12.5px;white-space:nowrap;text-align:right}
.to{color:var(--cyan);font-size:12px}.sc{color:var(--muted);font-size:11px}
.ph{color:var(--yellow);font-size:11px}
.copied{color:var(--ok)!important}
mark{background:#3a4a1e;color:var(--yellow)}
footer{position:fixed;bottom:0;left:0;right:0;padding:7px 18px;background:var(--panel);
 border-top:1px solid var(--line);font-size:12px;color:var(--muted)}
</style></head><body>
<header>
 <div class="brand">NC<span>Lives</span> · %(persona)s</div>
 <input id="q" placeholder="search her lines&hellip;  (regex ok)" autofocus>
 <select id="len"><option value="0">any length</option><option value="2">under 2 s</option>
  <option value="3">under 3 s</option><option value="5">under 5 s</option></select>
 <label class="stats"><input type="checkbox" id="tov" style="vertical-align:-1px"> only lines said to V</label>
 <div class="stats" id="stats"></div>
</header>
<main><table id="t"><thead><tr>
<th data-k="text">line</th><th data-k="seconds">sec</th><th data-k="to">to</th>
<th data-k="context">delivery</th><th data-k="scenes">from</th><th data-k="id">String ID</th>
</tr></thead><tbody></tbody></table></main>
<footer>Click a String ID to copy it. Paste it into <code>voices.lua</code> as <code>vo = "&lt;id&gt;"</code> —
 a <b>string</b>, always. %(persona)s's own recording plays.  ·  CDPR text, local use only — never commit or ship this file.</footer>
<script>
const ROWS = %(rows)s;
"""

HTML_TAIL = r"""
const tb=document.querySelector('#t tbody'),q=document.getElementById('q'),
      len=document.getElementById('len'),tov=document.getElementById('tov'),
      stats=document.getElementById('stats');
let sortK='text',sortD=1;
const esc=s=>s.replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
function render(){
  let re=null; const s=q.value.trim();
  if(s){ try{re=new RegExp(s,'i')}catch(e){re=new RegExp(s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&'),'i')} }
  const maxs=+len.value, onlyV=tov.checked;
  let rows=ROWS.filter(r=>(!re||re.test(r.text))&&(!maxs||(r.seconds&&r.seconds<=maxs))&&(!onlyV||r.to==='V'));
  rows.sort((a,b)=>{const x=a[sortK],y=b[sortK];
    return (typeof x==='number'?x-y:String(x).localeCompare(String(y)))*sortD;});
  stats.textContent=rows.length+' of '+ROWS.length+' lines';
  tb.innerHTML=rows.slice(0,3000).map(r=>{
    let t=esc(r.text); if(re) t=t.replace(new RegExp(re.source,'ig'),m=>'<mark>'+m+'</mark>');
    const d=[r.context.replace('Vo_Context_',''),r.expression.replace('Vo_Expression_','')]
            .filter(Boolean).join(' · ');
    return '<tr><td>'+t+(r.text_male?'<div class="sc">male V: '+esc(r.text_male)+'</div>':'')+'</td>'
      +'<td class="sec">'+(r.seconds?r.seconds.toFixed(2):'')+'</td>'
      +'<td class="to">'+esc(r.to)+'</td><td class="ph">'+esc(d)+'</td>'
      +'<td class="sc">'+esc(r.scenes.join(', '))+'</td>'
      +'<td class="id" data-id="'+r.id+'">'+r.id+'</td></tr>';
  }).join('');
}
tb.addEventListener('click',e=>{const c=e.target.closest('.id'); if(!c)return;
  navigator.clipboard.writeText(c.dataset.id);
  const o=c.textContent; c.textContent='copied ✓'; c.classList.add('copied');
  setTimeout(()=>{c.textContent=o;c.classList.remove('copied')},900);});
document.querySelectorAll('th').forEach(th=>th.onclick=()=>{
  const k=th.dataset.k; sortD=(k===sortK)?-sortD:1; sortK=k; render();});
[q,len,tov].forEach(el=>el.addEventListener('input',render));
render();
</script></body></html>
"""


def write_html(path, persona, rows):
    slim = [{k: r[k] for k in ("id", "text", "text_male", "seconds", "to",
                               "context", "expression", "scenes")} for r in rows]
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(HTML_HEAD % {"persona": html.escape(persona.title()),
                              "rows": json.dumps(slim, ensure_ascii=False)})
        fh.write(HTML_TAIL)


def cmd_build(args):
    blob = get_scan(args)
    tags = load_tags()
    if not tags:
        sys.exit("tools/voicetags.json is empty — run `discover` first.")

    targets = {k: v["voicetag"] for k, v in tags.items()}
    if args.persona:
        want = {p.lower() for p in args.persona}
        missing = want - set(targets)
        if missing:
            sys.exit(f"not in voicetags.json: {', '.join(sorted(missing))}")
        targets = {k: v for k, v in targets.items() if k in want}

    os.makedirs(OUTDIR, exist_ok=True)
    print()
    for persona, vt in sorted(targets.items()):
        rows = build_rows(blob, vt, tags)
        if not rows:
            print(f"  {persona:<12} no lines — wrong voicetag?")
            continue
        base = os.path.join(OUTDIR, persona)
        write_json(base + ".json", persona, rows)
        write_csv(base + ".csv", rows)
        write_html(base + ".html", persona, rows)
        to_v = sum(1 for r in rows if r["to"] == "V")
        short = sum(1 for r in rows if 0 < r["seconds"] <= 3)
        print(f"  {persona:<12} {len(rows):>5} lines  ({to_v} to V, {short} under 3 s)  "
              f"-> vo_library/{persona}.html")
    print(f"\nvo_library/ is gitignored on purpose: this is CDPR's text. Never commit it, never "
          f"ship it —\nanyone who needs it regenerates it from their own install in ~100 s.")


def cmd_search(args):
    path = os.path.join(OUTDIR, f"{args.persona.lower()}.json")
    if not os.path.isfile(path):
        sys.exit(f"{os.path.relpath(path, ROOT)} not built yet — run:\n"
                 f"    python3 tools/build_line_library.py build --persona {args.persona.lower()}")
    with open(path, encoding="utf-8") as fh:
        rows = json.load(fh)["lines"]
    rx = re.compile(args.pattern, re.I)
    hits = [r for r in rows if rx.search(r["text"])]
    if args.max:
        hits = [r for r in hits if 0 < r["seconds"] <= args.max]
    if args.to_v:
        hits = [r for r in hits if r["to"] == "V"]
    print(f"# {len(hits)} of {len(rows)} {args.persona} lines match /{args.pattern}/\n")
    for r in hits[:args.limit]:
        d = " ".join(x for x in (r["context"].replace("Vo_Context_", ""),
                                 r["expression"].replace("Vo_Expression_", "")) if x)
        print(f'{r["id"]}  {r["seconds"]:>5.2f}s  {("→" + r["to"]) if r["to"] else "  ":<4} {r["text"]}'
              + (f"   [{d}]" if d else ""))
    if len(hits) > args.limit:
        print(f"\n... {len(hits) - args.limit} more (--limit)")


# CDPR's recorded strings carry INLINE MARKUP that the game renders before it ever reaches a
# subtitle, so a raw string compare calls 43 of Jackie's 49 captions "drifted" when every one of
# them is right. Two forms appear in the corpus:
#   <mothertongue l="mex" m="chica" b="before " a="."/>   -> before + chica + .
#   <kiroshi l="mex" o="Si, si." t="Yeah, yeah." .../>     -> the spoken original, o (t is the gloss)
# Render them the way the player reads them, then compare. Anything we don't recognise is stripped
# to its bare text rather than dropped, so an unknown tag degrades to a looser check, never a
# silent pass.
def render_recorded(sub: str) -> str:
    if not sub or "<" not in sub:
        return sub

    def _mother(m):
        d = dict(re.findall(r'(\w+)="([^"]*)"', m.group(0)))
        return d.get("b", "") + d.get("m", "") + d.get("a", "")

    def _kiroshi(m):
        d = dict(re.findall(r'(\w+)="([^"]*)"', m.group(0)))
        return d.get("b", "") + (d.get("o") or d.get("t") or "") + d.get("a", "")

    out = re.sub(r"<mothertongue\b[^>]*/?>", _mother, sub)
    out = re.sub(r"<kiroshi\b[^>]*/?>", _kiroshi, out)
    out = re.sub(r"<[^>]+>", "", out)              # any other tag: keep the text around it
    return out.strip()


# Accents and curly punctuation differ between our authored text and CDPR's without being a
# different sentence ("Si" vs "Si"). Fold them for the comparison only — never for display, so the
# report still shows exactly what each side says.
def fold_caption(s: str) -> str:
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    for a, b in (("\u2019", "'"), ("\u2018", "'"), ("\u201c", '"'), ("\u201d", '"'),
                 ("\u2013", "-"), ("\u2014", "-"), ("\u2026", "..."),
                 ("\u00bf", ""), ("\u00a1", "")):   # Spanish opening ? and !: we don't author them
        s = s.replace(a, b)
    return " ".join(s.lower().split())


def cmd_verify(args):
    """Every `sfx` in voices.lua: is it that persona's line, and is the caption the line?

    Two mistakes this catches, both invisible until you hear them in game:
      · an id pasted into the WRONG pack — Judy's line coming out of Kerry. This repo has already
        shipped that bug once in the grunt form (v1.45, every persona grunting as Jackie), and a
        borrowed String ID is the same mistake with better production values.
      · a caption that drifted from the recording. The engine happily plays a line under any
        subtitle; the player reads one sentence and hears another.
    Needs a built library, so it SKIPS (exit 0) on a checkout that has none rather than failing.
    """
    blob_path = os.path.join(OUTDIR, "_scan.json")
    if not os.path.isfile(blob_path):
        print("no vo_library/_scan.json — skipping (run `build` first to enable this check)")
        return
    with open(blob_path, encoding="utf-8") as fh:
        blob = json.load(fh)
    tags = load_tags()
    text, lib = blob["text"], blob["lib"]

    # ⚠️ THE CONTENT FILE IS NOT THE SAME IN ALL THREE REPOS. This was hardcoded to NCLives'
    # `mod/NCLives/voices.lua`, so in JackieLives `verify` died with FileNotFoundError and the
    # caption check — the ONLY check that can see a subtitle drifting from its recording — could
    # not run at all in the most heavily voiced repo of the three.
    #   NCLives / NCLucy : mod/<Mod>/voices.lua, many `Voices.packs.<name>` blocks
    #   JackieLives      : mod/JackieLives/config.lua, ONE character and no packs at all
    src = None
    for cand in (os.path.join(ROOT, "mod", "NCLives", "voices.lua"),
                 os.path.join(ROOT, "mod", "NCLucy", "voices.lua"),
                 os.path.join(ROOT, "mod", "JackieLives", "config.lua")):
        if os.path.exists(cand):
            src = cand
            break
    if src is None:
        raise SystemExit("verify: found no content file (voices.lua / config.lua) under mod/")
    with open(src, encoding="utf-8") as fh:
        lua = fh.read()

    # Which pack is each line in? Packs are top-level and in file order, so a running marker is
    # enough — no Lua parsing, and nothing to keep in step with the content.
    packs = [(m.start(), m.group(1)) for m in re.finditer(r"^Voices\.packs\.(\w+) = \{", lua, re.M)]

    # A repo with no `Voices.packs.*` (JackieLives) is ONE character, not an unknown one — reporting
    # "?" there would make every row look unattributable and hide the real failures in the noise.
    # The persona name has to be a key in voicetags.json ("jackie"), not the mod folder
    # ("JackieLives") — get that wrong and every single row reports "no voicetag" and the real
    # failures drown in 130 lines of noise.
    solo = None
    if not packs:
        folder = os.path.basename(os.path.dirname(src)).lower()
        known  = load_tags()
        solo   = next((k for k in known if k and k in folder), folder)

    def pack_at(pos):
        if solo:
            return solo
        cur = "?"
        for start, name in packs:
            if start <= pos:
                cur = name
            else:
                break
        return cur

    # Entries are one per line in this file, which is what makes a line scan honest here — and a
    # line scan is what lets us tell the two KINDS of voiced entry apart:
    #   a companion line   { text = "...", sfx = "jl_N" }                -> must be the pack's persona
    #   a CHOICE row       { text = "...", to = "node", sfx = "jl_N" }   -> is V speaking, so must be V
    # Getting that backwards is silent in the log and obvious in the ear: Panam's voice coming out of
    # V's mouth, which is the v1.45 bug wearing a different hat.
    problems, checked, v_rows = [], 0, 0
    for raw in lua.split("\n"):
        m = re.search(r'sfx\s*=\s*"jl_(\d{6,})"', raw)
        if not m:
            continue
        cap = re.search(r'text\s*=\s*"((?:[^"\\]|\\.)*)"', raw)
        if not cap:
            problems.append(f"an sfx with no text on the same line: {raw.strip()[:80]}")
            continue
        sid, caption = m.group(1), cap.group(1).replace('\\"', '"')
        pos = lua.find(raw)
        pack = pack_at(pos)
        is_choice = re.search(r'\bto\s*=\s*("|nil)', raw) is not None
        speaker = "v" if is_choice else pack
        checked += 1
        v_rows += 1 if is_choice else 0

        vt = (tags.get(speaker) or {}).get("voicetag")
        if not vt:
            problems.append(f"{speaker}: no voicetag in voicetags.json — cannot check jl_{sid}")
            continue
        if sid not in lib.get(vt, {}):
            owner = next((k for k, v in tags.items() if sid in lib.get(v["voicetag"], {})), None)
            who = "V" if is_choice else speaker
            problems.append(f"{pack}: jl_{sid} is NOT {who}'s line"
                            + (f" — it belongs to {owner}" if owner else " (no persona owns it)")
                            + f'  "{caption[:60]}"')
            continue
        real = text.get(sid, ["", ""])
        shown = [render_recorded(r) for r in real]
        if fold_caption(caption) not in {fold_caption(x) for x in shown if x}:
            problems.append(f'{pack}: caption differs from the recording\n'
                            f'    subtitle: "{caption}"\n'
                            f'    recorded: "{shown[0] or shown[1]}"')
        # A choice row is not run through nclVar, so it has ONE subtitle for both Vs. A line the game
        # recorded with different male and female text would caption one player and be heard by the
        # other — pick a gender-neutral take instead.
        if is_choice and real[1] and real[0] and real[0] != real[1]:
            problems.append(f'{pack}: jl_{sid} has different male/female subtitles, so it cannot be a\n'
                            f'    choice row (choices get no `m` variant):\n'
                            f'    female: "{real[0]}"\n'
                            f'    male:   "{real[1]}"')

    print(f"{checked} voiced lines checked across {len(packs)} packs "
          f"({checked - v_rows} companion, {v_rows} spoken by V)")
    for p in problems:
        print("  ✗ " + p)
    if problems:
        sys.exit(f"\n{len(problems)} problem(s) — a wrong id or a drifted caption is only audible in game.")
    print("all good: every id belongs to the right voice, and every caption is the line.")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--redlib", default=DEFAULT_REDLIB)
    ap.add_argument("--rescan", action="store_true", help="re-read the game instead of the cache")
    sub = ap.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("build", help="write vo_library/<persona>.{json,csv,html}")
    b.add_argument("--persona", action="append", help="only this persona (repeatable)")
    b.set_defaults(fn=cmd_build)

    d = sub.add_parser("discover", help="name the voicetags / add one to voicetags.json")
    d.add_argument("--sounddb", metavar="ACTOR",
                   help="identify this actor's voicetag by cross-referencing SoundDB")
    d.add_argument("--top", type=int, default=40)
    d.set_defaults(fn=cmd_discover)

    v = sub.add_parser("verify", help="check every sfx in voices.lua against the library")
    v.set_defaults(fn=cmd_verify)

    s = sub.add_parser("search", help="grep a built library")
    s.add_argument("persona")
    s.add_argument("pattern")
    s.add_argument("--max", type=float, help="only lines this many seconds or shorter")
    s.add_argument("--to-v", action="store_true", help="only lines she says to V")
    s.add_argument("--limit", type=int, default=60)
    s.set_defaults(fn=cmd_search)

    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
