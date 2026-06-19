"""
tag_usage.py — mark which lines are ALREADY USED in the mod (and their role),
and which are stashed as "usable" candidates, so the tagger can pre-mark them.

Idempotent: clears the prior usage marks every run, then re-derives from source,
so removing a line from config.lua un-marks it next run.

Sources of truth:
  - mod/JackieLives/config.lua        → lines wired into the mod (sfx = "jl_...")
  - docs/conversations.md  §4         → the "Are we using these anywhere yet?" stash

Writes onto each matching line in tools/voice-tagger/lines.json:
  used      : true            (wired into config.lua)
  category  : <role>          (greeting/accept/decline/bye/food/conversation)
  usable    : true            (stashed candidate, not wired yet)  -> category "usable"
  seed_done : true            (tagger pre-marks these as tagged on load)

Role is derived from the STRUCTURAL context in config.lua (field/node names are
reliable), falling back to a light transcript keyword heuristic, else "conversation".
"""

import json, re, sys

DRY_RUN = "--dry-run" in sys.argv
LINES_JSON = r"C:\Users\ficht002\Documents\Projects\Cyberpunk_modding\tools\voice-tagger\lines.json"
CONFIG_LUA = r"C:\Users\ficht002\Documents\Projects\Cyberpunk_modding\mod\JackieLives\config.lua"
CONVOS_MD  = r"C:\Users\ficht002\Documents\Projects\Cyberpunk_modding\docs\conversations.md"

# field-name -> role (strongest signal)
FIELD_ROLE = {
    "acksfx": "accept", "refusesfx": "decline", "partingsfx": "bye",
    "picksfx": "food", "donesfx": "conversation", "getupsfx": "bye",
}
# node-name -> role
NODE_ROLE = {
    "arrivalgreetings": "greeting", "jackieinvite": "food", "restaurants": "food",
}

def kw_role(text):
    t = (text or "").lower()
    if any(k in t for k in ["good to see you","talk to me","you alive","how's things",
                            "qué onda","que onda","te sientes","hey v","about time",
                            "things come to those"]):
        return "greeting"
    if any(k in t for k in ["time we were on our way","take it easy","on our way"]):
        return "bye"
    if any(k in t for k in ["let's do our thing","ready to mosey","right on","let's drink",
                            "andale","yeah, ok","all right, all right","i'm comin","you comin",
                            "back out now","best be quick","had enough for one day"]):
        return "accept"
    if any(k in t for k in ["lunch","starv","liquor","grab a bite","tight-bite"]):
        return "food"
    return "conversation"

# ── parse config.lua: collect each used key + best role ─────────────────────

cfg = open(CONFIG_LUA, encoding="utf-8").read().splitlines()
used = {}   # key -> role (first reliable wins; reliability: field > node > keyword)
node = ""
ROLE_RANK = {"field": 3, "node": 2, "kw": 1}
# tiebreak when two sources tie on rank: prefer the rarer/more-specific role
ROLE_PRIORITY = {"decline": 6, "food": 5, "accept": 4, "greeting": 3, "bye": 2, "conversation": 1}
best_src = {}

for line in cfg:
    s = line.strip()
    m = re.match(r'(\w+)\s*=\s*\{', s)
    if m and m.group(1) not in ("choices", "nodes"):
        node = m.group(1).lower()
    for fld, key in re.findall(r'(\w*[Ss]fx)\s*=\s*"(jl_[^"]+)"', line):
        if key == "jl_<id>":  # template placeholder in a comment
            continue
        fld = fld.lower()
        tm = re.search(r'text\s*=\s*"([^"]*)"', line)
        text = tm.group(1) if tm else ""
        if fld in FIELD_ROLE:
            role, src = FIELD_ROLE[fld], "field"
        elif node in NODE_ROLE:
            role, src = NODE_ROLE[node], "node"
        else:
            role, src = kw_role(text), "kw"
        # keep the highest-reliability role seen for this key; on a rank tie,
        # prefer the rarer/more-specific role (e.g. decline over bye)
        if (key not in used
                or ROLE_RANK[src] > ROLE_RANK[best_src[key]]
                or (ROLE_RANK[src] == ROLE_RANK[best_src[key]]
                    and ROLE_PRIORITY[role] > ROLE_PRIORITY[used[key]])):
            used[key] = role
            best_src[key] = src

print(f"config.lua used keys: {len(used)}")

# ── parse conversations.md §4 (the 'usable' stash) ──────────────────────────

md = open(CONVOS_MD, encoding="utf-8").read()
sec4 = re.search(r'## 4\..*?(?=\n## 5\.)', md, re.S)
usable_keys = set(re.findall(r'jl_[A-Za-z0-9_]+', sec4.group(0))) if sec4 else set()
print(f"conversations.md §4 usable keys: {len(usable_keys)}")

# ── map an sfx key -> the line id in lines.json ─────────────────────────────
# old lines: id == string_id ; sfx == jl_<string_id>
# new lines: id == new_<stem> ; sfx == jl_<stem>

with open(LINES_JSON, encoding="utf-8") as f:
    lines = json.load(f)
by_id = {l["id"]: l for l in lines}

def find_line(key):
    stem = key[3:]            # strip 'jl_'
    if stem in by_id:         # old line (string_id)
        return by_id[stem]
    if ("new_" + stem) in by_id:
        return by_id["new_" + stem]
    return None

# clear prior marks (idempotent)
for l in lines:
    for fld in ("used", "usable", "seed_done"):
        l.pop(fld, None)

n_used = n_usable = n_missing = 0
for key, role in used.items():
    l = find_line(key)
    if not l:
        n_missing += 1; print(f"  used key not in lines.json: {key}"); continue
    l["used"] = True
    l["category"] = role
    l["seed_done"] = True
    n_used += 1

for key in usable_keys:
    l = find_line(key)
    if not l:
        n_missing += 1; print(f"  usable key not in lines.json: {key}"); continue
    if not l.get("used"):                 # don't override an already-wired line
        l["usable"] = True
        l["category"] = "usable"
        l["seed_done"] = True
        n_usable += 1

from collections import Counter
roles = Counter(l["category"] for l in lines if l.get("used"))
print(f"marked used: {n_used}  (roles: {dict(roles)})")
print(f"marked usable: {n_usable}")
print(f"keys not found in lines.json: {n_missing}")

if not DRY_RUN:
    with open(LINES_JSON, "w", encoding="utf-8") as f:
        json.dump(lines, f, ensure_ascii=False, indent=2)
    print("lines.json updated.")
else:
    print("[dry] no changes written.")
