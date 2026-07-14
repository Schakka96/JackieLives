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
import hashlib
import json
import os
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

def api_dialogues():
    src = {}
    hashes = {}
    for key in FILES:
        src[key], hashes[key] = read_file(key)

    groups, warnings = extract.build(src["config"], src["retrieval"])
    secs, nodes, fields = extract.count_editable(groups)

    exe, _ = find_lua()
    return {
        "modDir": MOD_DIR,
        "files": {k: {"name": FILES[k], "hash": hashes[k], "path": path_of(k)}
                  for k in FILES},
        "groups": groups,
        "warnings": warnings,
        "stats": {"sections": secs, "nodes": nodes, "lines": fields},
        "luaVerifier": exe or None,
    }


def api_save(payload):
    edits = payload.get("edits") or []
    client_hashes = payload.get("hashes") or {}
    if not edits:
        return 400, {"ok": False, "error": "No edits in the request."}

    # ---- group by file, validate -------------------------------------------
    by_file = {}
    for e in edits:
        key = e.get("file")
        if key not in FILES:
            return 400, {"ok": False, "error": "Unknown file %r." % key}
        by_file.setdefault(key, []).append(e)

    current = {}
    for key in by_file:
        text, h = read_file(key)
        if client_hashes.get(key) != h:
            return 409, {"ok": False, "error":
                         "%s changed on disk since the editor loaded it. "
                         "Nothing was written. Reload the page (F5) and redo "
                         "your edits." % FILES[key]}
        current[key] = text

    results = []
    for key, items in by_file.items():
        text = current[key]

        # descending by start so earlier offsets stay valid as we splice
        items = sorted(items, key=lambda e: int(e["start"]), reverse=True)

        # no overlaps, spans in range
        prev_start = None
        for e in items:
            s, t = int(e["start"]), int(e["end"])
            if not (0 <= s < t <= len(text)):
                return 400, {"ok": False,
                             "error": "Edit span %d-%d is outside %s." % (s, t, FILES[key])}
            if prev_start is not None and t > prev_start:
                return 400, {"ok": False,
                             "error": "Overlapping edits in %s -- refusing to write."
                                      % FILES[key]}
            prev_start = s

        new_text = text
        for e in items:
            s, t = int(e["start"]), int(e["end"])
            new_text = new_text[:s] + luaparse.lua_quote(e["value"]) + new_text[t:]

        # ---- back up, write, verify ----------------------------------------
        os.makedirs(BACKUPS, exist_ok=True)
        stamp = time.strftime("%Y%m%d-%H%M%S")
        backup = os.path.join(BACKUPS, "%s.bak-%s" % (FILES[key], stamp))
        shutil.copy2(path_of(key), backup)

        write_file(key, new_text)
        ok, how, detail = verify_lua(new_text, key)
        if not ok:
            shutil.copy2(backup, path_of(key))          # RESTORE
            return 500, {"ok": False,
                         "error": "%s would no longer be valid Lua (%s), so the "
                                  "original was RESTORED and nothing was changed.\n\n%s"
                                  % (FILES[key], how, detail),
                         "backup": backup}

        results.append({"file": FILES[key], "edits": len(items),
                        "backup": backup, "verifiedWith": how})

    fresh = api_dialogues()
    return 200, {"ok": True, "saved": results,
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
    print("  verifier: %s" % (data["luaVerifier"] or
                              "none on PATH -> structural check only"))
    for w in data["warnings"]:
        print("  WARNING : %s" % w)
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
