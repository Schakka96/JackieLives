#!/usr/bin/env python3
"""
rebuild_bank_yml.py — regenerate JackieLives.yml from the ACTUAL audio files present,
so Jackie's voice plays without renaming a single audio file.

WHY THIS EXISTS
  Audioware looks each clip up by the exact `file:` name in the manifest. WolvenKit
  exports Jackie's VO with the game's own stem names (e.g. jackie_q000_f_<hex>.Wav),
  but the shipped manifest referenced jl_<id>.wav names. Mismatch -> Audioware finds
  nothing -> it drops the WHOLE bank (test_tone Duration = -1, no voice in dialogue).

  This script points the manifest back at your real files. It also references ONLY
  files that exist, so a missing clip can never sink the bank again.

THE MAPPING (no lookup table needed — it's arithmetic)
  A line's VO String ID (what config.lua plays as jl_<decimal>) is the trailing hex
  token of the wem stem, in decimal:
      jackie_q000_f_170a4a14f8405008.Wav  ->  int("170a4a14f8405008", 16)
                                          ->  jl_1660220866564214792
  (Verified against all 777 scraped lines: 777/777.) For every audio file we emit two
  event aliases that both point at that one file, so either code path resolves:
      jl_<decimal>     — how config.lua references lines
      jl_<full_stem>   — how the game-extracted lines are keyed

USAGE (run it on the machine that HAS the audio files)
  Easiest: copy this file into your game bank folder next to the .Wav files:
      <game>\r6\audioware\JackieLives\
  then open PowerShell there and run:
      python rebuild_bank_yml.py
  Or point it at the folder from anywhere:
      python rebuild_bank_yml.py --bank "D:\...\Cyberpunk 2077\r6\audioware\JackieLives"

  It rewrites JackieLives.yml in place (the old one is saved as JackieLives.yml.bak).
  Stdlib only — no pip installs.
"""

import argparse
import os


def trailing_hex(stem):
    """Return the trailing '_'-delimited hex token (the VO hash) or None."""
    tok = stem.split("_")[-1]
    if len(tok) < 8:
        return None
    try:
        int(tok, 16)
    except ValueError:
        return None
    return tok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bank", default=os.path.dirname(os.path.abspath(__file__)),
                    help="folder holding the .Wav files + JackieLives.yml "
                         "(default: this script's own folder)")
    args = ap.parse_args()
    bank = os.path.abspath(args.bank)

    # 1) collect every audio file (any case: .wav / .Wav / .WAV)
    audio = sorted(n for n in os.listdir(bank) if n.lower().endswith(".wav"))
    if not audio:
        print("No .wav files found in:\n  %s\nNothing to do." % bank)
        return

    # 2) build event -> filename aliases (first mapping for an event wins)
    entries = []           # ordered [(event, filename)]
    seen = set()

    def add(event, fname):
        if event not in seen:
            seen.add(event)
            entries.append((event, fname))

    for fname in audio:
        stem = fname[:-4]                       # strip the 4-char extension
        low = stem.lower()
        if low in ("test_tone", "jl_fallback"):  # keep the two helper clips as-is
            add(stem, fname)
            continue
        add("jl_" + stem, fname)                 # stem alias
        hx = trailing_hex(stem)
        if hx is not None:
            add("jl_%d" % int(hx, 16), fname)    # numeric alias (what config plays)

    # 3) write the manifest (back up any existing one first)
    out = os.path.join(bank, "JackieLives.yml")
    if os.path.exists(out) and not os.path.exists(out + ".bak"):
        os.replace(out, out + ".bak")
        backed_up = True
    else:
        backed_up = False

    lines = [
        "# Jackie Lives - Audioware bank, regenerated from the ACTUAL files present.",
        "# Every event (jl_<decimal> and jl_<stem>) maps to a real .Wav in this folder;",
        "# no audio file was renamed. Regenerate anytime with tools/rebuild_bank_yml.py.",
        "version: 1.0.0",
        "sfx:",
    ]
    for event, fname in entries:
        lines.append("  %s:" % event)
        lines.append("    file: %s" % fname)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    # 4) report
    print("Bank folder : %s" % bank)
    print("Audio files : %d" % len(audio))
    print("Events wrote: %d  (numeric + stem aliases)" % len(entries))
    print("test_tone   : %s" % ("present" if any(e == "test_tone" for e, _ in entries) else "absent (harmless)"))
    print("jl_fallback : %s" % ("present" if any(e == "jl_fallback" for e, _ in entries) else "absent (harmless)"))
    print("Manifest    : %s%s" % (out, "  (old saved as JackieLives.yml.bak)" if backed_up else ""))
    print("\nDone. Launch the game — Jackie should speak. If a line is silent, that one")
    print("clip just isn't in the folder; the rest still play.")


if __name__ == "__main__":
    main()
