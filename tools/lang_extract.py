#!/usr/bin/env python3
"""
Jackie Lives — extract every player-facing string into a translation template.

    python3 tools/lang_extract.py                 # write mod/JackieLives/lang_template.lua
    python3 tools/lang_extract.py --check ja      # report drift in lang_ja.lua

WHY: lang.lua uses the English string itself as the lookup key, so a translation
file is only correct as long as its keys still match the English source word for
word. Edit a line in config.lua and that line silently reverts to English. This
script is the guard: --check lists every key that no longer exists in the source
(stale) and every source string with no translation (missing).

It scans the SAME strings the four runtime chokepoints can see — the `text =`,
`label =`, `title =` style assignments in the Lua sources — which is why it does
not need to understand the dialogue-tree structure.
"""

import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
MOD = ROOT / "mod" / "JackieLives"

# The files whose authored text reaches the screen, and WHICH keys in each hold
# player-facing prose. init.lua is deliberately absent from this table: almost
# all of its quoted strings are CET tuner-window slider labels, which are drawn
# straight to ImGui and never pass a translation chokepoint. Its handful of real
# player strings are inline call arguments, harvested by CALLS below instead.
# Player-facing prose is matched by KEY-NAME PATTERN, not a fixed list, so a new
# field like `refuseText` / `noticeTitle` / `objectiveText` is picked up
# automatically instead of silently falling back to English (which is exactly how
# V's dismiss/invite/parting choices were missed in v1.60). Any key ending in one
# of these prose words — with or without an optional trailing `M` (the male-variant
# convention: tipTextM) — qualifies; SKIP still drops identifier-valued ones.
PROSE_KEY = r'[A-Za-z]*?(?:[Tt]ext|[Ll]ine|[Tt]itle|[Bb]ody|[Pp]rompt|[Mm]sg|[Nn]otice|[Ll]abel|[Cc]aption)M?'
ASSIGN = re.compile(r'\b(?:%s)\s*=\s*"((?:[^"\\]|\\.)*)"' % PROSE_KEY)

# Files whose authored text reaches the screen, plus any EXTRA exact keys whose
# names don't fit the prose pattern (retrieval's objective banners: tip/awaiting/…).
# init.lua is absent: its prose-keyed strings are CET tuner labels drawn straight
# to ImGui, never through a translation chokepoint; its few real player strings are
# inline call arguments caught by CALLS.
SOURCES = {
    "config.lua":    (),
    "blaze.lua":     (),
    "retrieval.lua": ("tip", "awaiting", "arriving", "done"),
    "session.lua":   (),
}

# The shard / postShard notes are TABLES of bare string lines (no `key =`),
# translated per-line at retrieval.lua's concatT before display. Harvest a line
# that is ONLY a quoted string (optionally starting a `..` concat or ending in a
# comma) AND reads like prose (has a space) — i.e. an authored note line, not a
# code literal. `joined()` then folds any continuation fragments into one key.
BARE = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*(?:\.\.)?\s*,?\s*$')

# String literals passed directly to a translated chokepoint, OR wrapped in an
# explicit Lang.t("...") at a call site (e.g. init.lua's "Talk" hub label and the
# "Talk to Jackie [ " prompt prefix) — Lang.t is exactly the translate call, so any
# literal inside it is by definition a key.
CALLS = re.compile(
    r'(?:showOnscreenMsg|showSubtitle|showDialogueText|Lang\.t|localizedName\s*=)\s*\(?\s*'
    r'"((?:[^"\\]|\\.)*)"'
)

# Restaurant venue names become dialogue choices in withDateChoices as
# `r.name .. "."` — so the key the runtime looks up carries a trailing period.
# Emit that exact form or the translation would never match.
VENUE = re.compile(r'^\s*name\s*=\s*"((?:[^"\\]|\\.)*)"\s*,\s*appearance\s*=')

# Values that are identifiers/paths rather than prose — never shown to a player.
SKIP = re.compile(r'^(?:[a-z0-9_]+|[A-Za-z]+\.[A-Za-z0-9_.]+|jl_[0-9a-z_]+|\W*)$')


def harvest():
    """Return {string: [where-it-came-from, ...]} in first-seen order."""
    found = {}

    def keep(s, origin):
        if len(s) < 2 or not re.search(r"[A-Za-z]", s) or SKIP.match(s):
            return
        found.setdefault(s, []).append(origin)

    for fname in list(SOURCES) + ["init.lua"]:
        path = MOD / fname
        if not path.exists():
            continue
        # prose-pattern keys everywhere except init.lua; plus this file's EXTRA
        # exact keys (objective banners) that don't fit the pattern.
        assign = None
        if fname in SOURCES:
            extra = SOURCES[fname]
            if extra:
                assign = re.compile(
                    r'\b(?:%s|%s)\s*=\s*"((?:[^"\\]|\\.)*)"' % (PROSE_KEY, "|".join(extra))
                )
            else:
                assign = ASSIGN
        lines = path.read_text(encoding="utf-8").splitlines()

        def joined(start, first):
            """Follow Lua source-level `.. "..."` continuation lines.

            A value written across several lines is ONE string at runtime, so
            the key must be the assembled whole — extracting only the first
            fragment yields a key that never matches (this is exactly how
            retrieval.lua's welcome card was silently untranslatable).
            """
            out, j = first, start
            while j < len(lines):
                cont = re.match(r'\s*\.\.\s*"((?:[^"\\]|\\.)*)"', lines[j])
                if not cont:
                    break
                out += cont.group(1)
                j += 1
            return out

        for num, raw in enumerate(lines, 1):
            if raw.lstrip().startswith("--"):
                continue  # a comment, not live code
            origin = f"{fname}:{num}"
            v = VENUE.match(raw)
            if v:
                keep(v.group(1) + ".", origin)   # matches withDateChoices' key
                continue
            if assign:
                m = assign.search(raw)
                if m:
                    keep(joined(num, m.group(1)), origin)
                    continue
            m = CALLS.search(raw)
            if m:
                keep(joined(num, m.group(1)), origin)
                continue
            # A bare authored note line (shard / postShard array element). Only
            # retrieval.lua has these; harvesting bare strings elsewhere would drag
            # in init.lua's CET tuner help-text, which never reaches a chokepoint.
            if fname == "retrieval.lua":
                b = BARE.match(raw)
                if b and " " in b.group(1):
                    keep(joined(num, b.group(1)), origin)
    return found


def lua_quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_template(found):
    out = [
        "-- Jackie Lives — TRANSLATION TEMPLATE (generated by tools/lang_extract.py)",
        "-- The English keys, for reference. Translations live in translations.lua,",
        "-- one block per language. Do NOT edit the keys — they must match source exactly.",
        "return {",
    ]
    for s, where in found.items():
        out.append("  -- %s" % ", ".join(where[:3]))
        out.append("  [%s] = %s," % (lua_quote(s), lua_quote(s)))
    out.append("}")
    dest = MOD / "lang_template.lua"
    dest.write_text("\n".join(out) + "\n", encoding="utf-8")
    words = sum(len(s.split()) for s in found)
    print(f"wrote {dest.relative_to(ROOT)} — {len(found)} strings, {words} words")


def _block_keys(code):
    """Keys defined in translations.lua's [code] = { ... } block."""
    path = MOD / "translations.lua"
    if not path.exists():
        sys.exit(f"no {path.relative_to(ROOT)}")
    body = path.read_text(encoding="utf-8")
    m = re.search(r'\[\s*"%s"\s*\]\s*=\s*\{' % re.escape(code), body)
    if not m:
        sys.exit(f"no '{code}' block in translations.lua")
    # slice from the block's opening brace to its matching close (brace depth 1→0)
    i, depth = m.end(), 1
    while i < len(body) and depth:
        depth += {"{": 1, "}": -1}.get(body[i], 0)
        i += 1
    block = body[m.end():i]
    keys = set()
    for k in re.finditer(r'\[\s*"((?:[^"\\]|\\.)*)"\s*\]\s*=', block):
        keys.add(k.group(1).replace('\\"', '"').replace("\\\\", "\\"))
    return keys


def check(code, found):
    keys = _block_keys(code)
    source = set(found)
    stale = sorted(keys - source)
    missing = sorted(source - keys)

    print(f"translations.lua [{code}]: {len(keys)} keys | source has {len(source)} strings")
    if stale:
        print(f"\n  STALE ({len(stale)}) — key no longer in the English source, "
              f"so this translation is dead:")
        for s in stale:
            print(f"    {s[:90]}")
    if missing:
        print(f"\n  MISSING ({len(missing)}) — will render in English:")
        for s in missing:
            print(f"    {s[:90]}")
    if not stale and not missing:
        print("  in sync ✅")
    return 1 if stale else 0


if __name__ == "__main__":
    strings = harvest()
    if len(sys.argv) > 2 and sys.argv[1] == "--check":
        sys.exit(check(sys.argv[2], strings))
    write_template(strings)
