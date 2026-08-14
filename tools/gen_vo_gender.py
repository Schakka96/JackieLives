#!/usr/bin/env python3
"""gen_vo_gender.py — the male-V subtitle for every gendered line the mod speaks.

THE BUG THIS FIXES
  Antonia, 2026-08-13: *"he does not apply the correct male/female V versions, the subtitles
  now say chica (husbando mode) but his voice says mano often."*

  She was right, and the cause is not our Husbando/Hermano switch — it is that CDPR recorded
  TWO takes of some Jackie lines under ONE String ID, and the game picks the take from V's
  BODY GENDER, not from anything a mod says. `docs/research/native_vo_dialogline.md` already
  called this out ("Q6 male/female variants — A NON-ISSUE. The game picks the variant from V's
  gender. Nothing for us to do") and that was half right: nothing to do about the AUDIO, but
  our SUBTITLE is a hard-coded string in config.lua, and config.lua was written from the
  female-V take. Male V -> he says "mano", the subtitle still says "chica".

  So the subtitle has to follow V's body gender too. This script reads what CDPR actually
  wrote for both takes and emits it as a lookup table; init.lua swaps the subtitle when V is
  male. The audio is untouched — the game was already getting that right.

  ⚠️ COROLLARY, and it is the more damaging half: Config.hermanoLines used to ALSO override
  `sfx` to a `jackie_*_m_*` wem stem. Those aren't String IDs, so vo.lua's `lineId` rejects
  them and the native path can't speak them — the male "mirror" lines were the only ones in
  the mod that DIDN'T play. Same id, different subtitle, is the whole fix.

WHERE THE DATA COMES FROM
  The game on this machine. `lang_en_text.archive` stores every subtitle keyed by String ID,
  with a separate male variant where one exists; NCLives' tools/build_line_library.py already
  joins that against the scene data and caches it as vo_library/jackie.json. Nothing is
  downloaded and nothing is guessed.

USAGE
    python3 tools/gen_vo_gender.py                     # writes mod/JackieLives/vo_gender.lua
    python3 tools/gen_vo_gender.py --check             # exit 1 if the file is out of date
    python3 tools/gen_vo_gender.py --library <path>    # a jackie.json somewhere else

  Re-run it whenever config.lua gains new `sfx = "jl_<digits>"` lines. If the library is
  missing (a fresh checkout, no game), it leaves the existing vo_gender.lua alone and says so
  — the generated file is committed precisely so a machine without the game still builds.
"""

import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONFIG = ROOT / "mod" / "JackieLives" / "config.lua"
OUT = ROOT / "mod" / "JackieLives" / "vo_gender.lua"
DEFAULT_LIB = ROOT.parent / "NCLives" / "vo_library" / "jackie.json"


def render(text):
    """CDPR's subtitle markup -> the plain string we draw ourselves.

    <mothertongue m="chica" b="before " a=" after"/>  is a foreign-language word spliced into
    an English sentence: b + m + a. <kiroshi o="Chica." t="Sister."/> is a fully foreign line
    with a Kiroshi translation under it; `o` is what he actually says, so `o` is the subtitle.
    <Rich .../> is styling and carries no words of its own.
    """
    def sub(m):
        attrs = dict(re.findall(r'(\w+)="([^"]*)"', m.group(2)))
        tag = m.group(1)
        if tag == "mothertongue":
            return attrs.get("b", "") + attrs.get("m", "") + attrs.get("a", "")
        if tag == "kiroshi":
            return attrs.get("b", "") + attrs.get("o", "") + attrs.get("a", "")
        return ""

    out = re.sub(r"<(\w+)([^>]*?)/>", sub, text)
    out = re.sub(r"</?Rich[^>]*>", "", out)          # styling spans, no words
    out = out.replace("\\\"", '"')
    return re.sub(r"\s+", " ", out).strip()


def lua_quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def build(library):
    lines = {l["id"]: l for l in json.loads(library.read_text())["lines"]}
    # v1.70 — V'S LINES COUNT TOO. Since V speaks her own choice rows, config.lua's `sfx` ids are
    # no longer all Jackie's, and V has 1,983 lines whose male and female takes use DIFFERENT
    # WORDS. Miss those and a male V reads her female wording under his own audio — the exact bug
    # this file was written to close, reintroduced on the other side of the conversation. Merged
    # UNDER Jackie's entries (setdefault) so his library still wins any id they share.
    for extra in (ROOT / "vo_library" / "v.json",
                  ROOT.parent / "NCLives" / "vo_library" / "v.json"):
        if extra.exists():
            for l in json.loads(extra.read_text())["lines"]:
                lines.setdefault(l["id"], l)
            break
    used = sorted(set(re.findall(r'jl_(\d{6,})', CONFIG.read_text())))

    rows, missing = [], []
    for sid in used:
        line = lines.get(sid)
        if not line:
            missing.append(sid)
            continue
        male = line.get("text_male") or ""
        if not male:
            continue                                  # one take, spoken to any V — nothing to swap
        f, m = render(line["text"]), render(male)
        if f and m and f != m:
            rows.append((sid, f, m))

    body = [
        "-- GENERATED by tools/gen_vo_gender.py — DO NOT HAND-EDIT.",
        "--",
        "-- Some Jackie lines were recorded TWICE under ONE String ID: once addressed to a female V",
        "-- (\"chica\"), once to a male V (\"mano\"). The game picks the take from V's BODY GENDER all by",
        "-- itself — we never chose it and we cannot change it. What we DO control is the subtitle, and",
        "-- config.lua's text was written from the female take, so a male-V player heard \"mano\" and read",
        "-- \"chica\". That is the bug this table closes: same line id, subtitle picked to match.",
        "--",
        "-- ⚠️ This is V's BODY GENDER, not the mod's Husbando/Hermano switch. The switch is a",
        "-- RELATIONSHIP track and it is the player's to choose; which take the audio engine reaches for",
        "-- is decided by the save file. Mixing the two is exactly how we got here.",
        "--",
        "-- Text is CDPR's own, exactly as the game would render it (the <mothertongue>/<kiroshi> splice",
        "-- markup resolved), so the subtitle matches the audio word for word.",
        "--",
        "--   [\"<string id>\"] = { f = \"<female-V subtitle>\", m = \"<male-V subtitle>\" }",
        "",
        "return {",
    ]
    for sid, f, m in rows:
        body.append("  [%s] = { f = %s," % (lua_quote(sid), lua_quote(f)))
        body.append("%sm = %s }," % (" " * (len(sid) + 12), lua_quote(m)))
    body.append("}")
    return "\n".join(body) + "\n", rows, missing, used


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--library", type=pathlib.Path, default=DEFAULT_LIB)
    ap.add_argument("--check", action="store_true", help="exit 1 if vo_gender.lua is stale")
    args = ap.parse_args()

    if not args.library.exists():
        print("no line library at %s — leaving %s alone." % (args.library, OUT.name))
        print("build one with: python3 ../NCLives/tools/build_line_library.py build --persona jackie")
        return 0 if not args.check else 0

    text, rows, missing, used = build(args.library)

    if args.check:
        stale = (not OUT.exists()) or OUT.read_text() != text
        print("%s is %s" % (OUT.name, "STALE — re-run gen_vo_gender.py" if stale else "up to date"))
        return 1 if stale else 0

    OUT.write_text(text)
    print("%s: %d gendered lines out of %d spoken ids" % (OUT.name, len(rows), len(used)))
    for sid, f, m in rows:
        print("  %s\n      F %s\n      M %s" % (sid, f, m))
    if missing:
        print("\n%d id(s) not in the library (kept as-is): %s" % (len(missing), ", ".join(missing)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
