#!/usr/bin/env python3
"""loc_grep.py — search a WolvenKit-exported onscreens localization JSON for a term.

onscreens.json holds UI + phone SMS + journal + shard text (NOT spoken scene subtitles,
which use 19-digit scene ruids that don't resolve here). Use this to find the *text*
mourning (messages/journal) that can't be read in the Scene Editor.

Usage:
    python3 tools/loc_grep.py <onscreens.json[.json]> [term]     # default term: Jackie
Prints: secondaryKey <TAB> primaryKey <TAB> text   (one per match)
"""
import json, sys

def find_entries(o):
    if isinstance(o, dict):
        for v in o.values():
            if isinstance(v, list) and v and isinstance(v[0], dict) and "primaryKey" in v[0]:
                return v
            r = find_entries(v)
            if r:
                return r
    return None

def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    path = sys.argv[1]
    term = (sys.argv[2] if len(sys.argv) > 2 else "Jackie").lower()
    ents = find_entries(json.load(open(path))) or []
    hits = []
    for e in ents:
        txt = (e.get("femaleVariant", "") or "") + " ||M|| " + (e.get("maleVariant", "") or "")
        if term in txt.lower():
            hits.append(e)
    print(f"# {len(hits)} entries matching '{term}' in {path}\n")
    for e in sorted(hits, key=lambda x: x.get("secondaryKey", "") or "~"):
        t = (e.get("femaleVariant") or e.get("maleVariant") or "").replace("\n", " ")
        print(f"{(e.get('secondaryKey') or '<empty>')}\t{e.get('primaryKey')}\t{t}")

if __name__ == "__main__":
    main()
