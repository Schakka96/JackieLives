"""
upgrade_audio.py — replace low-quality .ogg voice lines with WolvenKit .wav exports
and move unknown lines into a new_lines/ staging folder.

Usage:
    python tools/upgrade_audio.py [--dry-run]

What it does:
  1. Reads tools/voice-tagger/lines.json (777 entries, each has vo_wem field).
  2. Scans the WolvenKit export folder for .Wav files.
  3. For each match (wem stem → string_id):
       - Copies <stem>.Wav → audioware/JackieLives/jl_<string_id>.wav
       - Deletes the old audioware/JackieLives/jl_<string_id>.ogg (if present)
  4. Rewrites JackieLives.yml: changes .ogg → .wav for all matched sfx entries.
  5. Moves unmatched .Wav files → <extraction_root>/new_lines/
"""

import json
import os
import re
import shutil
import sys

DRY_RUN = "--dry-run" in sys.argv

LINES_JSON = r"C:\Users\ficht002\Documents\Projects\Cyberpunk_modding\tools\voice-tagger\lines.json"
VO_DIR = r"C:\Users\ficht002\Documents\JackieLives\source\raw\base\localization\en-us\vo"
AUDIOWARE_DIR = r"C:\Users\ficht002\Documents\Projects\Cyberpunk_modding\audioware\JackieLives"
YML_PATH = os.path.join(AUDIOWARE_DIR, "JackieLives.yml")
NEW_LINES_DIR = os.path.join(VO_DIR, "new_lines")

# ── load crosswalk ──────────────────────────────────────────────────────────

with open(LINES_JSON, encoding="utf-8") as f:
    lines_data = json.load(f)

stem_to_id = {}
for line in lines_data:
    wem = line.get("vo_wem", "")
    if wem:
        stem = wem.split("/")[-1].replace(".wem", "").lower()
        stem_to_id[stem] = line["string_id"]

print(f"Crosswalk loaded: {len(stem_to_id)} entries")

# ── scan extraction folder ──────────────────────────────────────────────────

wav_files = [f for f in os.listdir(VO_DIR) if f.lower().endswith(".wav")]
print(f"WAV files found: {len(wav_files)}")

matched = {}    # string_id → wav filename
unmatched = []  # wav filenames with no crosswalk entry

for f in wav_files:
    stem = os.path.splitext(f)[0].lower()
    if stem in stem_to_id:
        matched[stem_to_id[stem]] = f
    else:
        unmatched.append(f)

print(f"Matched (known lines): {len(matched)}")
print(f"Unmatched (new lines): {len(unmatched)}")
print()

# ── step 1: copy matched wavs → audioware, delete old oggs ─────────────────

copied = 0
deleted_ogg = 0
skipped = 0

for string_id, wav_name in matched.items():
    src = os.path.join(VO_DIR, wav_name)
    dst_wav = os.path.join(AUDIOWARE_DIR, f"jl_{string_id}.wav")
    dst_ogg = os.path.join(AUDIOWARE_DIR, f"jl_{string_id}.ogg")

    if not DRY_RUN:
        shutil.copy2(src, dst_wav)
        copied += 1

    if os.path.exists(dst_ogg):
        if not DRY_RUN:
            os.remove(dst_ogg)
            deleted_ogg += 1

if not DRY_RUN:
    print(f"Copied {copied} WAV files to audioware/")
    print(f"Deleted {deleted_ogg} old OGG files")

# ── step 2: rewrite YML (.ogg → .wav for matched sfx entries) ──────────────

with open(YML_PATH, encoding="utf-8") as f:
    yml_text = f.read()

# Replace "file: jl_<id>.ogg" with "file: jl_<id>.wav" for matched ids
original_yml = yml_text
replacements = 0

for string_id in matched:
    old = f"file: jl_{string_id}.ogg"
    new = f"file: jl_{string_id}.wav"
    if old in yml_text:
        yml_text = yml_text.replace(old, new)
        replacements += 1

if not DRY_RUN and yml_text != original_yml:
    with open(YML_PATH, "w", encoding="utf-8") as f:
        f.write(yml_text)
    print(f"Updated YML: {replacements} .ogg → .wav entries rewritten")
elif DRY_RUN:
    print(f"[dry] Would rewrite {replacements} YML entries (.ogg -> .wav)")
else:
    print("YML: no changes needed")

# ── step 3: move unmatched wavs → new_lines/ ───────────────────────────────

if not DRY_RUN:
    os.makedirs(NEW_LINES_DIR, exist_ok=True)

moved = 0
for wav_name in unmatched:
    src = os.path.join(VO_DIR, wav_name)
    dst = os.path.join(NEW_LINES_DIR, wav_name)
    if not DRY_RUN:
        shutil.move(src, dst)
        moved += 1

if not DRY_RUN:
    print(f"Moved {moved} new/unknown lines → new_lines/")

print()
print("Done." if not DRY_RUN else "Dry run complete — rerun without --dry-run to apply.")
