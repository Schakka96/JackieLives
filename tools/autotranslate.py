#!/usr/bin/env python3
"""
Fill in the MISSING translations automatically, offline, with no AI assistant involved.

    python3 tools/autotranslate.py --setup        # ONE TIME: build the venv + download the models
    python3 tools/autotranslate.py                # translate every missing string, every language
    python3 tools/autotranslate.py --lang ja      # ...just one language
    python3 tools/autotranslate.py --dry-run      # ...print what it would write, change nothing
    python3 tools/autotranslate.py --prune        # also delete STALE keys (dead reworded lines)

WHY THIS EXISTS
---------------
`lang_extract.py --check-all` is a release gate: reword one English line and nine languages go
STALE + MISSING and the build refuses to ship. Until now the only way to clear that was to hand-
write nine translations, which is slow and is not a good use of an AI assistant's time for what is,
mostly, UI text.

WHAT IT USES
------------
**Argos Translate** (https://github.com/argosopentech/argos-translate) — MIT-licensed, offline
neural MT, the engine behind LibreTranslate. It runs entirely on this machine: the language models
are downloaded once (~100 MB each) and after that there is no network, no API key, no account, and
nothing about this project's text is sent anywhere. That last point is the reason it was chosen over
`translate-shell`, which is a scraper front-end for Google/Bing and needs the network every time.

⚠️ MACHINE TRANSLATION IS NOT A TRANSLATOR — READ THIS BEFORE POINTING IT AT DIALOGUE
------------------------------------------------------------------------------------
It is fine at UI and instructional text ("Take control", "Save this seat", the settings menu). It is
noticeably worse at *character voice*, and it does not know the difference. A real example from the
first run of this tool, on the seat card:

    EN  "automatic sitting floats, so it's off"
    DE  "automatisches Sitzen schwimmt, also ist es aus"   <- "floats" as in *swims*

That is the failure mode throughout: idiom read literally. Judy's "gonk", Panam's drawl, Jackie's
Spanglish and every joke in the small-talk hubs will come out flat or wrong, and a player reading
their own language will see a character who talks like a manual.

So the intended split, and `--only`/`--skip` exist to enforce it:
  * UI, settings, cards, objectives, prompts  -> machine translation is good enough. Use this tool.
  * CHARACTER DIALOGUE                        -> keep it human (or assistant) written.
It is deliberately non-destructive about this: **an existing translation is NEVER overwritten**, so
anything already hand-written stays, and this only ever fills blanks.

HOW IT KEEPS THE KEYS VALID
---------------------------
The keys are Lua SOURCE text, escapes and all (`\\n`, `\\"`), and `lang.lua` looks a string up by
exact match — so a key that differs by one character is a key that never matches. This script
therefore never invents a key: it imports `lang_extract` and reuses `harvest()` and `_block_keys()`,
the exact same functions the checker uses. If those two agree the string is missing, it is missing.

Before translating, three classes of substring are pulled OUT and put back afterwards, because MT
will happily rewrite all three and each one is a live bug if it does:
  * `%s` / `%.1f` / `%d`  — Lua format specifiers. `("...%s"):format(x)` throws if they are mangled.
  * `\\"`                  — an escaped quote; a stray one ends the Lua string early.
  * `\\n`                  — paragraph breaks. Segments are translated one at a time and rejoined,
                            which also keeps the model from merging a bulleted list into one blob.
"""

import argparse
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# ⚠️ THE VENV LIVES OUTSIDE ALL THREE REPOS, in the folder that contains them, and that is
# deliberate. It is ~430 MB before a single language model and ~1.4 GB with all nine, the three
# repos need the identical thing, and none of them should carry it: one shared copy, ignored by
# every .gitignore because it is not inside any of them. Override with NCL_TRANSLATE_VENV if you
# keep the repos somewhere they don't share a parent.
VENV = pathlib.Path(os.environ.get("NCL_TRANSLATE_VENV") or (ROOT.parent / ".venv-translate"))
VENV_PY = VENV / "bin" / "python"

sys.path.insert(0, str(ROOT / "tools"))
import lang_extract as LX                                     # noqa: E402  (needs the path above)

TRANSLATIONS = LX.MOD / "translations.lua"

# Argos language codes differ from the mod's codes in two places, and both are ordinary:
# `ptbr` is Brazilian Portuguese (Argos ships one `pt`), and `zhcn` is Simplified Chinese
# (Argos ships one `zh`, which IS Simplified).
ARGOS_CODE = {"ptbr": "pt", "zhcn": "zh"}

# ⚠️ Order matters: `\\` first, or the later rules re-escape what it produced.
UNESCAPE = [("\\\\", "\x00BACKSLASH\x00"), ('\\"', '"'), ("\\n", "\n"), ("\\t", "\t")]


def _need_venv():
    """Re-exec inside the venv, so `python3 tools/autotranslate.py` is the only command needed."""
    try:
        import argostranslate.translate  # noqa: F401
        return
    except ImportError:
        pass
    if VENV_PY.exists():
        os.execv(str(VENV_PY), [str(VENV_PY), str(pathlib.Path(__file__).resolve())] + sys.argv[1:])
    sys.exit("Argos Translate isn't installed yet. Run:  python3 tools/autotranslate.py --setup")


# --------------------------------------------------------------------------------------------
# setup
# --------------------------------------------------------------------------------------------
def setup(codes):
    """Build the venv and download one model per shipping language. Safe to re-run."""
    if not VENV_PY.exists():
        print(f"creating {VENV} ...")
        # ⚠️ PINNED TO 1.9.6 ON PURPOSE. Newer argostranslate requires spacy, which has no wheel
        # for the macOS system Python (3.9) — the install dies building `thinc`. 1.9.6 uses
        # stanza + sacremoses only, installs clean, and translates identically for our purposes.
        subprocess.check_call([sys.executable, "-m", "venv", str(VENV)])
        subprocess.check_call([str(VENV / "bin" / "pip"), "install", "-q", "--upgrade", "pip"])
        subprocess.check_call([str(VENV / "bin" / "pip"), "install", "-q", "argostranslate==1.9.6"])
    script = (
        "import argostranslate.package as pkg\n"
        "pkg.update_package_index()\n"
        "avail = pkg.get_available_packages()\n"
        "have = {(p.from_code, p.to_code) for p in pkg.get_installed_packages()}\n"
        "for code in %r:\n"
        "    if ('en', code) in have:\n"
        "        print('  already have en->' + code); continue\n"
        "    m = [p for p in avail if p.from_code == 'en' and p.to_code == code]\n"
        "    if not m:\n"
        "        print('  NO MODEL for en->' + code); continue\n"
        "    print('  downloading en->' + code + ' ...')\n"
        "    pkg.install_from_path(m[0].download())\n"
    ) % sorted({ARGOS_CODE.get(c, c) for c in codes})
    subprocess.check_call([str(VENV_PY), "-c", script])
    print("\nready. Now run:  python3 tools/autotranslate.py")


# --------------------------------------------------------------------------------------------
# escaping
# --------------------------------------------------------------------------------------------
def to_plain(key):
    """Lua source text -> the sentence a translator should see, plus the tokens pulled out of it."""
    s = key
    for a, b in UNESCAPE:
        s = s.replace(a, b)
    s = s.replace("\x00BACKSLASH\x00", "\\")
    # Lua format specifiers survive as opaque markers. `@@0@@` reads as a word to the model, so it
    # is carried through the sentence instead of being translated or dropped.
    slots = []

    def grab(m):
        slots.append(m.group(0))
        return "@@%d@@" % (len(slots) - 1)

    s = re.sub(r"%[-+ #0-9.]*[sdifgqxX%]", grab, s)
    # Lua's DECIMAL byte escapes (\226\154\160 = the warning sign). Left alone they reach the model
    # as literal backslash-digits, and it happily rewrites or drops them — which corrupts the string
    # for every language at once. Decode to the real character BEFORE translating: the model then
    # treats it as ordinary text and it re-encodes as plain UTF-8 on the way out.
    s = re.sub(r"((?:\\\\[0-9]{1,3})+)",
               lambda m: bytes(int(x) for x in re.findall(r"\\\\([0-9]{1,3})", m.group(1)))
                          .decode("utf-8", "replace"), s)
    return s, slots


def to_lua(text, slots):
    """The translated sentence -> Lua source text, with the format specifiers put back."""
    for i, slot in enumerate(slots):
        # The model sometimes spaces the marker out ("@@ 0 @@") — accept that too, or the
        # specifier is silently lost and the .format() call throws in game.
        text = re.sub(r"@@\s*%d\s*@@" % i, lambda _m, s=slot: s, text)
    out = text.replace("\\", "\\\\").replace('"', '\\"')
    return out.replace("\n", "\\n").replace("\t", "\\t")


def translate_key(key, target, translate):
    """Translate one key, paragraph by paragraph, preserving blank lines and bare markers."""
    plain, slots = to_plain(key)
    done = []
    for seg in plain.split("\n"):
        if not seg.strip() or re.fullmatch(r"[\s@0-9@]*", seg):
            done.append(seg)                      # blank line, or nothing but a format specifier
            continue
        try:
            done.append(translate(seg, "en", target).strip())
        except Exception as exc:                  # a model hiccup must not lose the whole run
            print(f"    ! {target}: {exc} — left in English")
            done.append(seg)
    return to_lua("\n".join(done), slots)


# --------------------------------------------------------------------------------------------
# translations.lua surgery
# --------------------------------------------------------------------------------------------
def block_span(body, code):
    """(start, end) of the [code] = { ... } block's INTERIOR, or None."""
    m = re.search(r'\[\s*"%s"\s*\]\s*=\s*\{' % re.escape(code), body)
    if not m:
        return None
    i, depth = m.end(), 1
    while i < len(body) and depth:
        depth += {"{": 1, "}": -1}.get(body[i], 0)
        i += 1
    return m.end(), i - 1


def prune_stale(body, code, source):
    """Drop keys that no longer exist in the English source. Returns (body, count)."""
    span = block_span(body, code)
    if not span:
        return body, 0
    start, end = span
    kept, dropped = [], 0
    for line in body[start:end].split("\n"):
        k = re.match(r'\s*\[\s*"((?:[^"\\]|\\.)*)"\s*\]\s*=', line)
        if k and k.group(1).replace('\\"', '"').replace("\\\\", "\\") not in source:
            dropped += 1
            continue
        kept.append(line)
    return body[:start] + "\n".join(kept) + body[end:], dropped


def insert(body, code, pairs):
    """Append `pairs` (key, value) to the end of the [code] block, matching its indentation."""
    span = block_span(body, code)
    if not span:
        sys.exit(f"no '{code}' block in translations.lua — add an empty one first")
    start, end = span
    rows = "".join('    [%s] = %s,\n' % (LX.lua_quote(k), LX.lua_quote(v)) for k, v in pairs)
    tail = body[start:end].rstrip("\n ")
    return body[:start] + tail + "\n" + rows + "  " + body[end:]


# --------------------------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="Fill missing translations with offline machine translation.")
    ap.add_argument("--setup", action="store_true", help="build the venv and download the models, then exit")
    ap.add_argument("--lang", action="append", help="only this language code (repeatable)")
    ap.add_argument("--dry-run", action="store_true", help="print what would be written, change nothing")
    ap.add_argument("--limit", type=int, help="stop after N strings per language (for a quick look)")
    ap.add_argument("--prune", action="store_true", help="also delete STALE keys")
    ap.add_argument("--only", help="only strings matching this regex (e.g. the UI-text ones)")
    ap.add_argument("--skip", help="skip strings matching this regex — use it to hold dialogue back")
    args = ap.parse_args()

    codes = args.lang or LX._languages()
    if not codes:
        sys.exit("no shipping languages — could not read Lang.LANGUAGES from lang.lua")

    if args.setup:
        return setup(codes)

    _need_venv()
    from argostranslate.translate import translate

    source = LX.harvest()
    body = TRANSLATIONS.read_text(encoding="utf-8")
    only = re.compile(args.only) if args.only else None
    skip = re.compile(args.skip) if args.skip else None
    total = 0

    for code in codes:
        target = ARGOS_CODE.get(code, code)
        have = LX._block_keys(code)
        missing = [s for s in source if s not in have]
        if only:
            missing = [s for s in missing if only.search(s)]
        if skip:
            missing = [s for s in missing if not skip.search(s)]
        if args.limit:
            missing = missing[: args.limit]

        stale = 0
        if args.prune and not args.dry_run:
            body, stale = prune_stale(body, code, set(source))

        if not missing:
            print(f"{code:<5} nothing to translate" + (f" ({stale} stale removed)" if stale else ""))
            continue

        print(f"{code:<5} translating {len(missing)} string(s) via en->{target} ...")
        pairs = []
        for n, key in enumerate(missing, 1):
            value = translate_key(key, target, translate)
            pairs.append((key, value))
            if args.dry_run or n <= 2:
                print(f"    {key[:64]!r}\n      -> {value[:64]!r}")
        if not args.dry_run:
            body = insert(body, code, pairs)
        total += len(pairs)
        print(f"{code:<5} +{len(pairs)}" + (f", -{stale} stale" if stale else ""))

    if args.dry_run:
        print(f"\ndry run — {total} string(s) would be written. Nothing changed.")
        return
    TRANSLATIONS.write_text(body, encoding="utf-8")
    print(f"\nwrote {TRANSLATIONS.relative_to(ROOT)} — {total} new string(s).")
    print("Now run:  python3 tools/lang_extract.py --check-all")


if __name__ == "__main__":
    main()
