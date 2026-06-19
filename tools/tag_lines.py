"""
tag_lines.py — add machine-derivable tags to lines.json (idempotent, no external deps).

Adds two things every line can be tagged with for free (from the filename, no listening):

  1. v_gender : "male" | "female"
     CP2077 VO files encode the PLAYER-V scene variant as an `_f_` / `_m_` token right
     before the trailing wem hash (e.g. jackie_q000_*_f_<hash>, v_scene_jackie_default_m_<hash>).
     So "male" = the line belongs to a male-V playthrough, "female" = female-V.
     The old 777 are all female-V (the SoundDB scrape only pulled female); the new pool
     carries the male-V variants too.

  2. memorial flag on the V FUNERAL / VOICEMAIL set
     Every stem starting `v_scene_jackie_default_` is V (not Jackie) leaving messages on
     Jackie's line after his death ("So I went to your funeral", "my last call"…).
     These are voiced as V — DO NOT use them as Jackie's voice. They are the V-side
     audio for the reunion / memorial scene. We mark them:
        speaker  = "V"
        category = "memorial"   (so the tagger category filter surfaces them)
        memorial = true

Usage:  python tools/tag_lines.py [--dry-run]
"""

import json, sys

DRY_RUN = "--dry-run" in sys.argv
LINES_JSON = r"C:\Users\ficht002\Documents\Projects\Cyberpunk_modding\tools\voice-tagger\lines.json"

MEMORIAL_PREFIX = "v_scene_jackie_default_"


def stem_of(l):
    if l.get("source") == "new_unscraped":
        return l["id"].replace("new_", "", 1)
    wem = l.get("vo_wem", "")
    return wem.split("/")[-1].replace(".wem", "") if wem else ""


def v_gender(stem):
    parts = stem.split("_")
    if len(parts) >= 2 and parts[-2] in ("f", "m"):
        return "female" if parts[-2] == "f" else "male"
    return "unknown"


with open(LINES_JSON, encoding="utf-8") as f:
    lines = json.load(f)

n_gender = {"male": 0, "female": 0, "unknown": 0}
n_memorial = 0

for l in lines:
    stem = stem_of(l)
    g = v_gender(stem)
    l["v_gender"] = g
    n_gender[g] += 1

    if stem.startswith(MEMORIAL_PREFIX):
        l["speaker"] = "V"
        l["category"] = "memorial"
        l["memorial"] = True
        n_memorial += 1

print(f"v_gender tagged: {n_gender}")
print(f"memorial (V funeral/voicemail) flagged: {n_memorial}")

if not DRY_RUN:
    with open(LINES_JSON, "w", encoding="utf-8") as f:
        json.dump(lines, f, ensure_ascii=False, indent=2)
    print("lines.json updated.")
else:
    print("[dry] no changes written.")
