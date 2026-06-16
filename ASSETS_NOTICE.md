# Asset & Copyright Notice

This is a fan-made modding project for **Cyberpunk 2077**. It is not affiliated
with or endorsed by CD PROJEKT RED.

## What is NOT in this repository (and never should be)

To respect CD PROJEKT RED's copyright, **no game assets are committed here**:

- **Jackie's voice lines** (`.ogg` / `.wav` / `.wem`) — these are CDPR-owned audio
  scraped from public catalogues and re-encoded for the Audioware bank. They are
  **excluded via `.gitignore`** and regenerated locally (see below).
- Any extracted game files, character records, or other CDPR intellectual property.

## How to regenerate the audio locally

The voice bank is a build artifact, not source. After cloning:

1. Run `tools/scrape_jackie.py` to download Jackie's lines into the voice-tagger.
2. Run `tools/convert_audio.py` to (re)build the Audioware bank in
   `audioware/JackieLives/` (it auto-downloads a portable ffmpeg to `tools/ffmpeg/`).

The Audioware manifest (`audioware/JackieLives/JackieLives.yml`) and the
`index.json` line index **are** tracked, since they are project configuration —
but the audio files they reference are not.

## Game ownership

Using this mod requires a legally owned copy of Cyberpunk 2077 and the standard
modding stack (RED4ext, redscript, CET, TweakXL, ArchiveXL, Codeware, AMM).
All game content remains the property of CD PROJEKT RED.
