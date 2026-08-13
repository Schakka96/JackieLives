#!/usr/bin/env python3
"""lang_apply.py — splice new translations into translations.lua, and drop dead keys.

WHY THIS EXISTS
  translations.lua is one big Lua file with a block per language, and every content change
  leaves it out of sync in two directions at once: new English strings have no translation
  (they silently render in English in nine languages) and reworded ones leave a STALE key
  pointing at text that no longer exists. `lang_extract.py --check-all` finds both; this
  applies the fix, so nobody hand-edits nine parallel blocks and mis-pastes one.

USAGE
    python3 tools/lang_apply.py <patch.json>        # add/replace the given keys
    python3 tools/lang_apply.py <patch.json> --prune-stale
        also DELETE any key in a block that no longer appears in the English source.

  patch.json is  { "<english string>": { "ja": "...", "es": "...", ... }, ... }
  — the same English string exactly as lang_extract.py prints it. A key already present in a
  block is overwritten; a language missing from an entry is left alone. Idempotent: running it
  twice changes nothing the second time.

  Always finish with:  python3 tools/lang_extract.py --check-all
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TRANS = ROOT / "mod" / "JackieLives" / "translations.lua"


def lua_quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def lua_unquote(s):
    return s.replace('\\"', '"').replace("\\\\", "\\")


def blocks(body):
    """[(code, start_of_body, end_of_body)] for each ["xx"] = { ... } language block."""
    out = []
    for m in re.finditer(r'\[\s*"(\w+)"\s*\]\s*=\s*\{', body):
        i, depth = m.end(), 1
        while i < len(body) and depth:
            depth += {"{": 1, "}": -1}.get(body[i], 0)
            i += 1
        out.append((m.group(1), m.end(), i - 1))
    return out


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    patch = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
    prune = "--prune-stale" in sys.argv

    source = None
    if prune:
        sys.path.insert(0, str(ROOT / "tools"))
        import lang_extract
        source = set(lang_extract.harvest())

    body = TRANS.read_text(encoding="utf-8")
    added = replaced = pruned = 0

    # Back to front, so earlier offsets stay valid as we rewrite.
    for code, start, end in reversed(blocks(body)):
        block = body[start:end]
        existing = {}
        for m in re.finditer(r'^(\s*)\[\s*"((?:[^"\\]|\\.)*)"\s*\]\s*=\s*"((?:[^"\\]|\\.)*)"\s*,\s*$',
                             block, re.M):
            existing[lua_unquote(m.group(2))] = m

        # 1. rewrite the values of keys we already have
        edits = []
        for eng, langs in patch.items():
            if code in langs and eng in existing:
                m = existing[eng]
                edits.append((m.start(), m.end(),
                              "%s[%s] = %s," % (m.group(1), lua_quote(eng), lua_quote(langs[code]))))
                replaced += 1
        # 2. drop keys the English source no longer has
        if prune:
            for eng, m in existing.items():
                if eng not in source:
                    edits.append((m.start(), m.end(), None))
                    pruned += 1
        for s, e, text in sorted(edits, key=lambda x: -x[0]):
            if text is None:
                nl = block.find("\n", e)
                block = block[:s] + block[(nl + 1 if nl >= 0 else e):]
            else:
                block = block[:s] + text + block[e:]

        # 3. append the ones this block has never had
        new = ["    [%s] = %s," % (lua_quote(eng), lua_quote(langs[code]))
               for eng, langs in patch.items() if code in langs and eng not in existing]
        added += len(new)
        if new:
            block = block.rstrip("\n ") + "\n" + "\n".join(new) + "\n  "

        body = body[:start] + block + body[end:]

    TRANS.write_text(body, encoding="utf-8")
    print("translations.lua: %d added, %d replaced, %d stale removed" % (added, replaced, pruned))


if __name__ == "__main__":
    main()
