#!/usr/bin/env python3
"""
backfill_string_ids.py  -  Fill the `string_id` field for the new (unscraped) lines.

WHY
  The game's VO String ID (what SoundDB stores as `id`/`string_id` for the old 777)
  IS the wem hash, just written in decimal. The wem filename carries it in hex:
      base/.../jackie_q000_f_170a4a14f8405008.wem   ->  trailing hex token 170a4a14f8405008
      String ID (decimal) = int("170a4a14f8405008", 16) = 1660220866564214792
  Verified against all 777 scraped lines: string_id == int(<trailing hex>, 16), 777/777.

  So the 503 new lines were never missing their String ID - it's the wem hash.
  This script computes it and writes it into the existing `string_id` reference field.
  It does NOT touch `id`/sfx keys (config.lua keys off jl_<stem>; those stay stable).

USAGE  (from this folder's parent or anywhere)
  python tools/backfill_string_ids.py            # backfill new_unscraped records
  python tools/backfill_string_ids.py --all      # also re-verify the old 777 match

Idempotent: re-running only sets values that are missing/wrong. Stdlib only.
"""

import argparse
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
LINES = os.path.join(HERE, "voice-tagger", "lines.json")


def hex_token(rec):
    """The trailing _-delimited hex token of the wem stem = the VO hash (hex)."""
    src = rec.get("vo_wem") or rec.get("id") or ""
    stem = src.replace("\\", "/").rsplit("/", 1)[-1]
    if stem.lower().endswith(".wem"):
        stem = stem[:-4]
    tok = stem.split("_")[-1]
    try:
        int(tok, 16)
    except ValueError:
        return None
    return tok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true",
                    help="also re-verify the old scraped lines' string_id matches the hex")
    ap.add_argument("--path", default=LINES)
    args = ap.parse_args()

    recs = json.load(open(args.path, encoding="utf-8"))
    filled = unchanged = skipped = 0
    verified = mismatched = 0

    for r in recs:
        is_new = r.get("source") == "new_unscraped"
        tok = hex_token(r)
        if tok is None:
            skipped += 1
            continue
        sid = str(int(tok, 16))

        if is_new:
            if r.get("string_id") == sid:
                unchanged += 1
            else:
                r["string_id"] = sid
                filled += 1
        elif args.all:
            # old scraped line: sanity-check that the relationship holds
            if str(r.get("string_id") or r.get("id")) == sid:
                verified += 1
            else:
                mismatched += 1
                print(f"  ! mismatch {r.get('id')}: stored {r.get('string_id')} vs hex->{sid}")

    json.dump(recs, open(args.path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"new lines: filled {filled}, already correct {unchanged}, unparseable {skipped}")
    if args.all:
        print(f"old lines re-verified: {verified} match, {mismatched} mismatch")
    print(f"wrote {args.path}")


if __name__ == "__main__":
    main()
