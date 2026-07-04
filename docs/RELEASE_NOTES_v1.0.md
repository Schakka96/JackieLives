# Jackie Lives — v1.0 (first full voiced release)

*Paste-ready for the Nexus "Changelog" / description. Trim as you like.*

---

## v1.0 — Jackie speaks

This is the big one: **Jackie now talks in his own voice, with his mouth moving**, on top of
everything the mod already does. If you've been running the subtitle-only builds, this is the
version to jump to.

### What's in 1.0
- 🔊 **Real voice** — Jackie speaks his actual lines through Audioware. You add the audio yourself
  from your own game files (CDPR audio can't be redistributed); a step-by-step
  `HOW_TO_ADD_JACKIE_VOICES.txt` ships in the mod. **New this release: no renaming.** Drop your raw
  WolvenKit exports straight in — the sound bank already refers to the game's own filenames. A small
  `rebuild_bank_yml.py` helper is included if your extract ever needs re-matching.
- 👄 **Mouth movement** — his lips flap while he speaks (needs AMM Expressions Overhaul; see
  Requirements). There's a live "shuffle interval" slider in the Jackie Lives window to tune the pace.
- 🗺️ **The full experience** it's built on: the *"Where's Jackie?"* retrieval questline, holocalls,
  scheduled presence at his Heywood haunts, proximity encounters, branching voiced dialogue, the
  side-job companion (summon on side jobs only — he declines main missions), walk-abreast following,
  bike cruise on his Arch, and dinner outings.
- 🧹 **Cleaned-up settings window** for release — the pure-dev clutter is gone; venue/collision/seat
  tuning is tucked into one "Jackie's spots fine tuning" section.
- Runs **subtitle-only and crash-free** if you don't add audio, or don't have Audioware.

### Requirements
- **RED4ext**, **Cyber Engine Tweaks (1.18.1+)**, **AppearanceMenuMod (AMM)**, **Codeware**,
  **Native Settings UI**
- **Audioware** — for his voice (without it: subtitles only)
- **AMM Expressions Overhaul** ([mod 20108](https://www.nexusmods.com/cyberpunk2077/mods/20108)) —
  for his mouth to move
- **WolvenKit** — to extract his voice-over yourself (see the included HOW_TO)

### Adding his voice
Install Audioware, extract Jackie's VO with WolvenKit, convert to WAV, and drop the files into
`r6\audioware\JackieLives\` — keep their original names. Full walkthrough in
`HOW_TO_ADD_JACKIE_VOICES.txt`.
