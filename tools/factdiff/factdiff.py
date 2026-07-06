#!/usr/bin/env python3
"""
factdiff.py — analyse a JLFactDump  factdump.log  from the "Save Jackie" datamining spike.

It splits the captured quest facts into SEGMENTS at each MARKER you dropped in-game, shows which
facts were set in each segment, and flags the two things we care about:

  * WATSON / world-unlock candidates — facts that flip around "Heist complete" (the lever we want
    to pull to open the world without the death/Johnny tail).
  * JOHNNY / RELIC facts — facts that appear at "Playing for Time" etc. (the ones we must NEVER
    trigger in the mod).

USAGE:
    python3 factdiff.py [path/to/factdump.log]

Default path is the mod's own log:  ../../mod/JLFactDump/factdump.log  (relative to this script).

The log line formats JLFactDump writes:
    NNNNNN <TAB> SET    <TAB> <src> <TAB> <name>=<value>
    === MARKER <TAB> NNNNNN <TAB> <label> ===
Any other  === … ===  line is treated as a comment/header.
"""

import os
import re
import sys

# Facts whose NAME matches these are highlighted as world-unlock / Watson-lever candidates.
WATSON_RE = re.compile(
    r"watson|lockdown|lock_down|prevention|prevent|barrier|district|"
    r"open.?world|fast.?travel|fasttravel|act_?0?2|world_?open|q005.*(end|complete|done|over)",
    re.I,
)
# Facts we must NOT let the mod trigger — the Relic/Johnny/Act-2 story path.
JOHNNY_RE = re.compile(
    r"johnny|silverhand|relic|resurrection|q101|firestorm|engram|biochip|"
    r"chip_?install|tapeworm|sq032",
    re.I,
)

SET_RE = re.compile(r"^\s*(\d+)\tSET\t([^\t]*)\t(.+?)=(.*?)\s*$")
MARKER_RE = re.compile(r"^=== MARKER\t(\d+)\t(.*?) ===\s*$")


def default_log_path():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.normpath(os.path.join(here, "..", "..", "mod", "JLFactDump", "factdump.log"))


def parse(path):
    """Return a list of segments. Each segment = {'label', 'sets': [(seq, src, name, value)]}."""
    segments = [{"label": "(before first marker)", "sets": []}]
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            m = MARKER_RE.match(raw)
            if m:
                segments.append({"label": m.group(2), "sets": []})
                continue
            s = SET_RE.match(raw)
            if s:
                seq, src, name, value = int(s.group(1)), s.group(2), s.group(3), s.group(4)
                segments[-1]["sets"].append((seq, src, name, value))
    return segments


def final_values(sets):
    """Collapse duplicate/repeated sets (incl. cross-class dupes) to the LAST value per fact name."""
    out = {}
    for _seq, _src, name, value in sets:
        out[name] = value
    return out


def flag(name):
    if JOHNNY_RE.search(name):
        return "AVOID"   # Johnny/Relic — must never be triggered
    if WATSON_RE.search(name):
        return "WATSON"  # world-unlock lever candidate
    return ""


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else default_log_path()
    if not os.path.exists(path):
        print(f"[factdiff] log not found: {path}")
        print("Copy factdump.log from the Windows CET mod folder, or pass its path as an argument.")
        sys.exit(1)

    segments = parse(path)
    total = sum(len(s["sets"]) for s in segments)
    print(f"[factdiff] {path}")
    print(f"[factdiff] {total} fact-set lines across {len(segments)} segment(s)\n")

    seen = {}  # name -> value carried across segments, to distinguish NEW vs CHANGED
    watson_hits, avoid_hits = [], []

    for i, seg in enumerate(segments):
        fvals = final_values(seg["sets"])
        if not fvals and i == 0:
            continue
        print("=" * 78)
        print(f"SEGMENT {i}: {seg['label']}   ({len(fvals)} distinct facts set)")
        print("-" * 78)
        for name in sorted(fvals):
            value = fvals[name]
            if name not in seen:
                kind = "NEW"
            elif seen[name] != value:
                kind = f"CHG {seen[name]}->{value}"
            else:
                kind = "same"
            tag = flag(name)
            marker = f"  [{tag}]" if tag else ""
            print(f"  {kind:>14}  {name} = {value}{marker}")
            if tag == "WATSON":
                watson_hits.append((i, seg["label"], name, value))
            elif tag == "AVOID":
                avoid_hits.append((i, seg["label"], name, value))
            seen[name] = value
        print()

    print("#" * 78)
    print("# SHORTLIST")
    print("#" * 78)
    print("\n## WATSON / world-unlock lever candidates (want to pull these WITHOUT the tail):")
    if watson_hits:
        for i, label, name, value in watson_hits:
            print(f"  seg {i} [{label}]  {name} = {value}")
    else:
        print("  (none matched the name patterns — scan the SEGMENT dumps above by hand around")
        print("   the 'Heist complete' marker; the lever may have an unexpected name.)")

    print("\n## JOHNNY / RELIC facts — the mod must NEVER set these:")
    if avoid_hits:
        for i, label, name, value in avoid_hits:
            print(f"  seg {i} [{label}]  {name} = {value}")
    else:
        print("  (none matched — check the 'Playing for Time' segment by hand.)")

    print("\nHow to read this: a fact that flips in the 'Heist complete' segment but is NOT in the")
    print("AVOID list is a prime candidate for the Watson lever. Facts appearing only at/after")
    print("'Playing for Time' are the Act-2/Johnny state we intercept BEFORE. Send me this output.")


if __name__ == "__main__":
    main()
