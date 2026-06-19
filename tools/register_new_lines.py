"""
register_new_lines.py — make the 503 new (unscraped) lines USABLE by the mod.

Problem this fixes:
  After ingest, the new clips live in audioware/JackieLives/ as raw "<stem>.Wav"
  but are NOT in JackieLives.yml — so config.lua cannot play them. The 777 old
  lines use the convention  jl_<string_id>  (key in YML + sfx ref in config.lua).
  The new lines have no string_id, so we key them by their unique wem stem:
        sfx key   = jl_<stem>
        audio file= jl_<stem>.wav   (renamed from <stem>.Wav for uniformity)

What it does (idempotent):
  1. Renames audioware/JackieLives/<stem>.Wav  ->  jl_<stem>.wav
  2. Appends a clearly-marked "NEW UNSCRAPED LINES" block to JackieLives.yml
     with one sfx entry per new line (skips any already present).
  Run with --dry-run to preview.

After this, any new line can be used in config.lua exactly like the old ones:
        sfx = "jl_jackie_q000_f_170a4a14f8405008"
"""

import json, os, re, sys

DRY_RUN = "--dry-run" in sys.argv

LINES_JSON    = r"C:\Users\ficht002\Documents\Projects\Cyberpunk_modding\tools\voice-tagger\lines.json"
AUDIOWARE_DIR = r"C:\Users\ficht002\Documents\Projects\Cyberpunk_modding\audioware\JackieLives"
YML_PATH      = os.path.join(AUDIOWARE_DIR, "JackieLives.yml")

MARKER = "# ===== NEW UNSCRAPED LINES (auto-added by tools/register_new_lines.py) ====="

with open(LINES_JSON, encoding="utf-8") as f:
    lines = json.load(f)

new = [l for l in lines if l.get("source") == "new_unscraped"]
print(f"New lines in lines.json: {len(new)}")

# existing YML keys, to stay idempotent
yml_text = open(YML_PATH, encoding="utf-8").read()
existing_keys = set(re.findall(r"^  (jl_[^\s:]+):", yml_text, re.M))

renamed = 0
missing_audio = 0
entries = []

for l in new:
    stem = l["id"].replace("new_", "", 1)
    key  = "jl_" + stem
    src  = os.path.join(AUDIOWARE_DIR, stem + ".Wav")
    dst_name = key + ".wav"
    dst  = os.path.join(AUDIOWARE_DIR, dst_name)

    # 1. rename <stem>.Wav -> jl_<stem>.wav
    if os.path.exists(src) and not os.path.exists(dst):
        if not DRY_RUN:
            os.rename(src, dst)
        renamed += 1
    elif not os.path.exists(src) and not os.path.exists(dst):
        missing_audio += 1
        print(f"  MISSING audio: {stem}.Wav")
        continue

    # 2. queue a YML entry (skip if already registered)
    # NOTE: we deliberately do NOT write the transcript into the YML — it is
    # verbatim CDPR text and the YML is a tracked/publishable file. Transcripts
    # live only in the gitignored lines.json.
    if key not in existing_keys:
        entries.append((key, dst_name))

print(f"Renamed .Wav -> jl_*.wav: {renamed}")
print(f"Missing audio files: {missing_audio}")
print(f"YML entries to add: {len(entries)} (skipped {len(new)-len(entries)-missing_audio} already present)")

# 3. append YML block
if entries:
    block = ["", MARKER]
    for key, fname in entries:
        block.append(f"  {key}:")
        block.append(f"    file: {fname}")
    new_block = "\n".join(block) + "\n"

    if not DRY_RUN:
        # strip any prior marker block (idempotent re-run), then append fresh
        if MARKER in yml_text:
            yml_text = yml_text[: yml_text.index(MARKER)].rstrip() + "\n"
        with open(YML_PATH, "w", encoding="utf-8") as f:
            f.write(yml_text.rstrip() + "\n" + new_block)
        print(f"YML updated: appended {len(entries)} new sfx entries")
    else:
        print(f"[dry] would append {len(entries)} entries under the marker block")

print("\nDone." if not DRY_RUN else "\nDry run complete.")
