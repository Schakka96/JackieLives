#!/usr/bin/env python3
"""
JackieLives dialogue editor -- tiny local server.

  python3 tools/dialogue-editor/serve.py
  -> open http://localhost:8777

Python 3 standard library ONLY. No pip install, no npm, no internet.

  GET  /api/dialogues   parse config.lua + retrieval.lua -> the dialogue model
  POST /api/save        splice edited text back into the raw .lua files

SAFETY (this is the whole point of the design):
  * We never re-serialize the Lua. Comments in these files are the project's
    documentation, so a save only replaces the exact byte spans of the string
    literals that changed -- applied back-to-front so earlier offsets stay valid.
  * Every save backs the file up first, then VERIFIES the result parses
    (`luac -p` / `lua`, else a structural check). If verification fails the
    backup is restored and the UI is told, loudly. A broken config.lua means the
    mod won't load in-game, so we never leave one on disk.
  * A save is refused if the file changed on disk since it was read.
"""

import argparse
import difflib
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import luaparse          # noqa: E402
import extract           # noqa: E402
import ops               # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
STATIC = os.path.join(HERE, "static")
BACKUPS = os.path.join(HERE, "backups")

FILES = {
    "config": "config.lua",
    "retrieval": "retrieval.lua",
}
ROOTS = {"config": {"Config"}, "retrieval": {"M"}}

MOD_DIR = None          # set in main()


# ---------------------------------------------------------------------------
# file I/O
# ---------------------------------------------------------------------------

def path_of(key):
    return os.path.join(MOD_DIR, FILES[key])


def read_file(key):
    with open(path_of(key), "rb") as fh:
        raw = fh.read()
    return raw.decode("utf-8"), hashlib.sha256(raw).hexdigest()


def write_file(key, text):
    with open(path_of(key), "wb") as fh:
        fh.write(text.encode("utf-8"))


# ---------------------------------------------------------------------------
# Lua verification
# ---------------------------------------------------------------------------

def find_lua():
    for exe in ("luac", "luac5.4", "luac5.3", "luac5.1", "lua", "lua5.4",
                "lua5.3", "lua5.1", "luajit"):
        p = shutil.which(exe)
        if p:
            return exe, p
    return None, None


def verify_lua(text, key):
    """
    Return (ok, how, detail).
    Always runs the structural check. If a lua binary exists, runs that too.
    """
    # 1. structural / re-parse check -- always available
    try:
        luaparse.sanity_check(text, ROOTS[key])
    except luaparse.LuaSyntaxError as e:
        return False, "structural", str(e)
    except Exception as e:                                # noqa: BLE001
        return False, "structural", "%s: %s" % (type(e).__name__, e)

    # 2. the real thing, if it's installed
    exe, full = find_lua()
    if not exe:
        return True, "structural-only (no lua/luac on PATH)", ""

    tmp = tempfile.NamedTemporaryFile("wb", suffix=".lua", delete=False)
    try:
        tmp.write(text.encode("utf-8"))
        tmp.close()
        if exe.startswith("luac"):
            cmd = [full, "-p", tmp.name]
        else:
            cmd = [full, "-e",
                   "local f,e = loadfile([[%s]]) if not f then io.stderr:write(e) os.exit(1) end"
                   % tmp.name]
        r = subprocess.run(cmd, capture_output=True, timeout=20)
        if r.returncode != 0:
            err = (r.stderr or r.stdout).decode("utf-8", "replace").strip()
            return False, exe, err
        return True, exe, ""
    except Exception as e:                                # noqa: BLE001
        return True, "structural-only (%s failed to run: %s)" % (exe, e), ""
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# the voice-clip index (transcripts of Jackie's real VO)
#
# audioware/JackieLives/transcripts.json is a list of {file, transcript}. The
# Audioware event id is derived from the filename:
#   jackie_q000_f_170a459104405000.Wav  ->  jl_<int("170a...", 16)>   (the f/unisex bank)
#   jackie_q000_m_170f8b95404ea000.Wav  ->  jl_jackie_q000_m_170f...  (the male bank)
# Both forms are indexed, so whichever an sfx uses, we can show its real words.
# ---------------------------------------------------------------------------

_CLIPS = None
_CLIP_LIST = []


def clip_ids(filename):
    """
    (canonical_id, [all ids this clip answers to]).

    The male bank is referenced by its stem (`jl_jackie_q000_m_170f...`) and the
    female/unisex bank by the decimal of its trailing hex (`jl_1661700...`) --
    that's just how the two scrapes were done. We index BOTH forms and pick the
    canonical one by bank, so the picker offers the id config.lua actually uses.
    """
    stem = re.sub(r"\.[Ww][Aa][Vv]$", "", filename)
    ids = []
    m = re.search(r"([0-9a-fA-F]{12,})$", stem)
    if m:
        ids.append("jl_%d" % int(m.group(1), 16))
    ids.append("jl_" + stem)
    canonical = ("jl_" + stem) if "_m_" in stem else ids[0]
    return canonical, ids


def load_clips():
    global _CLIPS, _CLIP_LIST
    if _CLIPS is not None:
        return _CLIPS
    _CLIPS, _CLIP_LIST = {}, []
    path = os.path.join(REPO, "audioware", "JackieLives", "transcripts.json")
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:                                     # noqa: BLE001
        return _CLIPS                                     # no transcripts -> feature just goes quiet
    for e in data:
        fn = e.get("file") or ""
        if not fn:
            continue
        canonical, ids = clip_ids(fn)
        rec = {"id": canonical, "file": fn,
               "transcript": e.get("transcript") or "", "male": "_m_" in fn}
        for cid in ids:
            _CLIPS.setdefault(cid, rec)
        _CLIP_LIST.append(rec)
    return _CLIPS


def _norm(s):
    return re.sub(r"[^a-z0-9 ]+", "", (s or "").lower()).strip()


def clip_match(subtitle, transcript):
    """0..1 — how well a subtitle matches what the clip actually says."""
    a, b = _norm(subtitle), _norm(transcript)
    if not a or not b:
        return None
    return round(difflib.SequenceMatcher(None, a, b).ratio(), 3)


def annotate_clips(groups):
    """Hang the real clip transcript (and a match score) on every voiced line."""
    clips = load_clips()
    if not clips:
        return

    def do(ln):
        for key, sfxkey in (("clip", "sfx"), ("clipM", "sfxM")):
            sfx = ln.get(sfxkey)
            if not sfx:
                continue
            c = clips.get(sfx)
            if not c:
                ln[key] = {"missing": True}
                continue
            txt = (ln.get("m") if sfxkey == "sfxM" else ln.get("text")) or {}
            ln[key] = {"transcript": c["transcript"], "file": c["file"],
                       "match": clip_match(txt.get("value"), c["transcript"])}

    for g in groups:
        for s in g["sections"]:
            if s["kind"] == "tree":
                for n in s["nodes"]:
                    for ln in n["lines"] + n["choices"]:
                        do(ln)
            elif s["kind"] == "pool":
                for col in s["columns"]:
                    for ln in col["lines"]:
                        do(ln)
            else:
                for f in s["fields"]:
                    do(f)


def api_dialogues():
    src = {}
    hashes = {}
    for key in FILES:
        src[key], hashes[key] = read_file(key)

    groups, warnings = extract.build(src["config"], src["retrieval"])
    annotate_clips(groups)
    errors, gwarn, ginfo = extract.validate(groups)
    secs, nodes, fields = extract.count_editable(groups)

    exe, _ = find_lua()
    return {
        "modDir": MOD_DIR,
        "files": {k: {"name": FILES[k], "hash": hashes[k], "path": path_of(k)}
                  for k in FILES},
        "groups": groups,
        "warnings": warnings,
        "graphErrors": errors,
        "graphWarnings": gwarn,
        "graphInfo": ginfo,
        "stats": {"sections": secs, "nodes": nodes, "lines": fields,
                  "clips": len(load_clips())},
        "luaVerifier": exe or None,
    }


def api_clips():
    load_clips()
    out = [{"id": c["id"], "transcript": c["transcript"], "male": c["male"]}
           for c in _CLIP_LIST if c["transcript"].strip()]
    out.sort(key=lambda r: r["transcript"])
    return {"clips": out}


def api_save(payload):
    """
    Apply text edits + structural ops.

    Order of business, and every step matters:
      1. refuse if either file changed on disk since the editor read it
      2. resolve the structural ops against a FRESH parse of the file
      3. splice everything back-to-front, in memory
      4. GATE: valid Lua (luac/structural) AND a valid dialogue graph
      5. only now back up and write

    Step 4 is the whole point. `luac -p` will happily pass a file where a choice
    points at a node that no longer exists -- valid Lua, dead quest. So the graph
    validator is a peer of the Lua check, not an extra.
    """
    edits = payload.get("edits") or []
    ops_in = payload.get("ops") or []
    client_hashes = payload.get("hashes") or {}
    if not edits and not ops_in:
        return 400, {"ok": False, "error": "Nothing to save."}

    touched = set()
    for e in edits:
        if e.get("file") not in FILES:
            return 400, {"ok": False, "error": "Unknown file %r." % e.get("file")}
        touched.add(e["file"])
    for o in ops_in:
        ref = o.get("ref") or {}
        if ref.get("file") not in FILES:
            return 400, {"ok": False, "error": "Op with an unknown file %r." % ref.get("file")}
        touched.add(ref["file"])

    # ---- 1. nobody else moved the file under us -----------------------------
    src = {}
    for key in FILES:
        text, h = read_file(key)
        if key in touched and client_hashes.get(key) != h:
            return 409, {"ok": False, "error":
                         "%s changed on disk since the editor loaded it. Nothing "
                         "was written. Reload the page (F5) and redo your edits."
                         % FILES[key]}
        src[key] = text

    # ---- 2 + 3. text edits first, then ops one at a time ---------------------
    #
    # Text-edit spans are offsets into the ORIGINAL file, so they must all land
    # before any structural op moves bytes around. After that each op is resolved
    # against a FRESH parse of the evolving text -- which is what lets you add a
    # node and, in the same save, add a choice that points at it.
    results = []
    new_src = dict(src)
    for key in sorted(touched):
        text = src[key]

        file_edits = [e for e in edits if e["file"] == key]
        if file_edits:
            try:
                text = luaparse.apply_splices(
                    text, [(int(e["start"]), int(e["end"]),
                            luaparse.lua_quote(e["value"])) for e in file_edits])
            except luaparse.LuaSyntaxError as e:
                return 400, {"ok": False, "error": "Conflicting text edits: %s" % e}

        file_ops = [o for o in ops_in if o["ref"]["file"] == key]
        try:
            for op in ops.order_ops(file_ops):
                assigns = luaparse.parse_assigns(text, ROOTS[key])
                text = luaparse.apply_splices(
                    text, ops.splices_for(text, assigns, [op]))
        except ops.OpError as e:
            return 400, {"ok": False, "error": str(e)}
        except luaparse.LuaSyntaxError as e:
            return 400, {"ok": False, "error": "Conflicting edits: %s" % e}

        if text == src[key]:
            continue
        new_src[key] = text
        results.append({"file": FILES[key], "key": key, "text": text,
                        "edits": len(file_edits), "ops": len(file_ops)})

    if not results:
        return 400, {"ok": False, "error": "Nothing to save."}

    # ---- 4. THE GATE: valid Lua *and* a valid dialogue graph ----------------
    for r in results:
        ok, how, detail = verify_lua(r["text"], r["key"])
        if not ok:
            return 400, {"ok": False, "error":
                         "That change would make %s invalid Lua, so NOTHING was "
                         "written — your file on disk is untouched.\n\n%s"
                         % (r["file"], detail), "verifiedWith": how}
        r["verifiedWith"] = how

    try:
        errors, warnings, info = extract.validate_sources(
            new_src["config"], new_src["retrieval"])
    except Exception as e:                                # noqa: BLE001
        return 400, {"ok": False, "error":
                     "That change left the dialogue unreadable, so NOTHING was "
                     "written: %s: %s" % (type(e).__name__, e)}

    if errors:
        return 400, {"ok": False, "graphErrors": errors, "error":
                     "BROKEN DIALOGUE — nothing was written, your files are "
                     "untouched.\n\nThe Lua would still be valid, but the "
                     "conversation would break in-game:\n\n"
                     + "\n".join("  • " + e["msg"] for e in errors)}

    # ---- 5. only now touch the disk -----------------------------------------
    os.makedirs(BACKUPS, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    for r in results:
        backup = os.path.join(BACKUPS, "%s.bak-%s" % (r["file"], stamp))
        shutil.copy2(path_of(r["key"]), backup)
        r["backup"] = backup
        write_file(r["key"], r["text"])

    # belt and braces: re-verify what actually landed on disk
    for r in results:
        disk, _ = read_file(r["key"])
        ok, how, detail = verify_lua(disk, r["key"])
        if not ok or disk != r["text"]:
            for rr in results:
                shutil.copy2(rr["backup"], path_of(rr["key"]))    # RESTORE ALL
            return 500, {"ok": False, "error":
                         "%s did not survive the write, so every file was "
                         "RESTORED from backup.\n\n%s" % (r["file"], detail)}

    fresh = api_dialogues()
    return 200, {"ok": True,
                 "saved": [{"file": r["file"], "edits": r["edits"], "ops": r["ops"],
                            "backup": r["backup"], "verifiedWith": r["verifiedWith"]}
                           for r in results],
                 "graphWarnings": warnings, "graphInfo": info,
                 "hashes": {k: v["hash"] for k, v in fresh["files"].items()},
                 "groups": fresh["groups"], "stats": fresh["stats"]}


# ---------------------------------------------------------------------------
# http
# ---------------------------------------------------------------------------

MIME = {".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8",
        ".js": "application/javascript; charset=utf-8"}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("  %s\n" % (fmt % args))

    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        if not isinstance(body, bytes):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, code, obj):
        self._send(code, json.dumps(obj, ensure_ascii=False), )

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/api/clips":
            try:
                self._json(200, api_clips())
            except Exception as e:                        # noqa: BLE001
                self._json(500, {"error": "%s: %s" % (type(e).__name__, e)})
            return

        if path == "/api/dialogues":
            try:
                self._json(200, api_dialogues())
            except Exception as e:                        # noqa: BLE001
                import traceback
                traceback.print_exc()
                self._json(500, {"error": "%s: %s" % (type(e).__name__, e)})
            return

        if path == "/":
            path = "/index.html"
        name = os.path.basename(path)
        full = os.path.join(STATIC, name)
        if not os.path.isfile(full):
            self._send(404, "not found", "text/plain; charset=utf-8")
            return
        ext = os.path.splitext(name)[1]
        with open(full, "rb") as fh:
            self._send(200, fh.read(), MIME.get(ext, "application/octet-stream"))

    def do_POST(self):
        if self.path.split("?", 1)[0] != "/api/save":
            self._send(404, "not found", "text/plain; charset=utf-8")
            return
        try:
            n = int(self.headers.get("Content-Length") or 0)
            payload = json.loads(self.rfile.read(n).decode("utf-8"))
            code, body = api_save(payload)
            self._json(code, body)
        except Exception as e:                            # noqa: BLE001
            import traceback
            traceback.print_exc()
            self._json(500, {"ok": False, "error": "%s: %s" % (type(e).__name__, e)})


def main():
    global MOD_DIR
    ap = argparse.ArgumentParser(description="JackieLives dialogue editor")
    ap.add_argument("--mod-dir", default=os.environ.get(
        "JACKIE_MOD_DIR", os.path.join(REPO, "mod", "JackieLives")),
        help="folder holding config.lua + retrieval.lua "
             "(default: <repo>/mod/JackieLives; env: JACKIE_MOD_DIR)")
    ap.add_argument("--port", type=int,
                    default=int(os.environ.get("JACKIE_PORT", "8777")))
    ap.add_argument("--check", action="store_true",
                    help="parse the files, print a summary and exit (no server)")
    args = ap.parse_args()

    MOD_DIR = os.path.abspath(args.mod_dir)
    for key, name in FILES.items():
        if not os.path.isfile(path_of(key)):
            sys.exit("ERROR: %s not found in %s" % (name, MOD_DIR))

    data = api_dialogues()
    st = data["stats"]
    print("JackieLives dialogue editor")
    print("  mod dir : %s" % MOD_DIR)
    print("  parsed  : %d sections, %d tree nodes, %d editable lines"
          % (st["sections"], st["nodes"], st["lines"]))
    print("  clips   : %d voice-clip transcripts indexed" % st["clips"])
    print("  verifier: %s + dialogue-graph validator"
          % (data["luaVerifier"] or "structural check (no lua on PATH)"))
    for w in data["warnings"]:
        print("  WARNING : %s" % w)
    for e in data["graphErrors"]:
        print("  GRAPH ERROR : %s" % e["msg"])
    for w in data["graphWarnings"]:
        print("  GRAPH WARN  : %s" % w["msg"])
    print("  graph   : %d errors, %d warnings, %d notes"
          % (len(data["graphErrors"]), len(data["graphWarnings"]),
             len(data["graphInfo"])))
    if args.check:
        return

    srv = HTTPServer(("127.0.0.1", args.port), Handler)
    print("\n  ==> open  http://localhost:%d\n" % args.port)
    print("  (Ctrl+C to stop)")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nbye.")


if __name__ == "__main__":
    main()
