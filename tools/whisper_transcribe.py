"""
whisper_transcribe.py — auto-transcribe Jackie's unscraped voice lines.

Usage:
    pip install openai-whisper
    python tools/whisper_transcribe.py

Transcribes every line in lines.json where transcript is empty (source=new_unscraped).
Saves progress after each file so you can Ctrl-C and resume safely.
Model: "small" (good accuracy on clean game VO, ~500 MB download on first run).
"""

import json, os, sys

LINES_JSON = r"C:\Users\ficht002\Documents\Projects\Cyberpunk_modding\tools\voice-tagger\lines.json"
AUDIO_DIR  = r"C:\Users\ficht002\Documents\Projects\Cyberpunk_modding\tools\voice-tagger\audio\new"
MODEL_SIZE = "small"   # tiny/base/small/medium — small is the sweet spot for game VO

try:
    import whisper
except ImportError:
    print("Whisper not installed. Run:  pip install openai-whisper")
    sys.exit(1)

print(f"Loading Whisper '{MODEL_SIZE}' model (downloads ~500 MB on first run)...")
model = whisper.load_model(MODEL_SIZE)
print("Model ready.\n")

with open(LINES_JSON, encoding="utf-8") as f:
    lines = json.load(f)

todo = [l for l in lines if l.get("source") == "new_unscraped" and not l.get("transcript")]
print(f"Lines to transcribe: {len(todo)} (skipping {len(lines)-len(todo)} already have text)\n")

done = 0
errors = 0

for i, line in enumerate(todo):
    # build audio path from the file field (audio/new/<stem>.Wav)
    wav_name = os.path.basename(line.get("file", ""))
    wav_path = os.path.join(AUDIO_DIR, wav_name)

    if not os.path.exists(wav_path):
        print(f"  [{i+1}/{len(todo)}] MISSING: {wav_name}")
        errors += 1
        continue

    print(f"  [{i+1}/{len(todo)}] {wav_name} ...", end=" ", flush=True)
    try:
        result = model.transcribe(wav_path, language="en", fp16=False)
        text = result["text"].strip()
        line["transcript"] = text
        print(text[:80])
        done += 1
    except Exception as e:
        print(f"ERROR: {e}")
        errors += 1

    # save after every file so progress survives Ctrl-C
    if (i + 1) % 10 == 0 or i == len(todo) - 1:
        with open(LINES_JSON, "w", encoding="utf-8") as f:
            json.dump(lines, f, ensure_ascii=False, indent=2)

print(f"\nDone. Transcribed: {done}  Errors/missing: {errors}")
print(f"lines.json updated — reload the tagger to see results.")
