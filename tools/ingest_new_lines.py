"""
ingest_new_lines.py — copy new (unscraped) Jackie lines into the tagger and
append stub entries to lines.json so they show up in the UI.

Usage:
    python tools/ingest_new_lines.py [--dry-run]

Source:  JackieLives WolvenKit export new_lines/ folder
Dest:    tools/voice-tagger/audio/new/   (already gitignored)
         tools/voice-tagger/lines.json   (appended, NOT modified for existing entries)
"""

import json
import os
import shutil
import sys

DRY_RUN = "--dry-run" in sys.argv

NEW_LINES_DIR = r"C:\Users\ficht002\Documents\JackieLives\source\raw\base\localization\en-us\vo\new_lines"
AUDIO_NEW_DIR = r"C:\Users\ficht002\Documents\Projects\Cyberpunk_modding\tools\voice-tagger\audio\new"
LINES_JSON    = r"C:\Users\ficht002\Documents\Projects\Cyberpunk_modding\tools\voice-tagger\lines.json"

# ── load existing lines.json ────────────────────────────────────────────────

with open(LINES_JSON, encoding="utf-8") as f:
    lines_data = json.load(f)

existing_ids = {l["id"] for l in lines_data}
print(f"Existing lines: {len(lines_data)}")

# ── scan new_lines/ ─────────────────────────────────────────────────────────

wav_files = sorted(f for f in os.listdir(NEW_LINES_DIR) if f.lower().endswith(".wav"))
print(f"Files in new_lines/: {len(wav_files)}")

# ── copy wavs + build stub entries ─────────────────────────────────────────

if not DRY_RUN:
    os.makedirs(AUDIO_NEW_DIR, exist_ok=True)

new_entries = []
copied = 0
skipped = 0

for wav_name in wav_files:
    stem = os.path.splitext(wav_name)[0]

    # Use stem as id with a prefix so it's distinct from string_id-based lines
    entry_id = "new_" + stem

    if entry_id in existing_ids:
        skipped += 1
        continue

    src = os.path.join(NEW_LINES_DIR, wav_name)
    dst = os.path.join(AUDIO_NEW_DIR, wav_name)
    rel_file = "audio/new/" + wav_name   # relative to voice-tagger/ for the server

    if not DRY_RUN:
        shutil.copy2(src, dst)
        copied += 1

    # Guess quest from filename prefix (jackie_q005_f_... -> q005)
    parts = stem.split("_")
    quest = ""
    for p in parts:
        if p.startswith("q") and p[1:].isdigit():
            quest = p
            break

    new_entries.append({
        "id": entry_id,
        "file": rel_file,
        "transcript": "",
        "category": "",
        "string_id": "",
        "raw_text": "",
        "vo_wem": "base/localization/en-us/vo/" + stem + ".wem",
        "lipsync": "",
        "gender": "female",
        "context": [],
        "expression": [],
        "addressees": [],
        "quests": [quest] if quest else [],
        "source": "new_unscraped"
    })

print(f"New entries to add: {len(new_entries)}  (skipped {skipped} already present)")
if not DRY_RUN:
    print(f"Copied {copied} WAV files to audio/new/")

# ── append to lines.json ────────────────────────────────────────────────────

if not DRY_RUN and new_entries:
    lines_data.extend(new_entries)
    with open(LINES_JSON, "w", encoding="utf-8") as f:
        json.dump(lines_data, f, ensure_ascii=False, indent=2)
    print(f"lines.json updated: now {len(lines_data)} entries total")
elif DRY_RUN:
    print(f"[dry] Would write lines.json with {len(lines_data) + len(new_entries)} entries total")

print()
print("Done." if not DRY_RUN else "Dry run complete.")
