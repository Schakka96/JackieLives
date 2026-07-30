# Jackie Lives — a Cyberpunk 2077 mod

Bring **Jackie Welles** back after his Act 1 death, in a lore-friendly way, as a
**living Night City NPC** — not a default follower. Jackie didn't die at Vik's; he was
quietly smuggled out and healed, chose out of the merc life, and now works a bar and acts
as a low-level community fixer in Heywood. The player can summon him onto **side jobs only**.

> ⚠️ Fan project, not affiliated with CD PROJEKT RED. **No game assets are distributed here** —
> see [ASSETS_NOTICE.md](ASSETS_NOTICE.md). Requires a legally owned copy of Cyberpunk 2077.

## Status — v1.64.1

Playable and released. The mod is **gated behind a retrieval questline**: Vik reveals Jackie's alive,
V finds his note in the Badlands and calls him, and a reunion brings him home — only then does
everything else unlock.

After that he follows and fights as a companion, runs a shuffled **daily schedule** (idle-spawns and
free-roam wander at captured venues, per-location outfits, sit/lean poses, a secret nap cameo), and
talks through a data-driven branching tree rendered by **the game's own dialogue widget**, with real
voiced lines. You can **call him onto a side job** (holocall → he walks or rides in), **talk** to him
with location-specific trees, **send him off** (he walks away), and **take him to dinner** (pick a
restaurant → map waypoint and objective → he takes his seat → seated small talk). He **walks abreast**
of V on flat ground and falls into single file on stairs, and he **trails V on his Arch** when V rides
a bike. A companion-duration clock sends him home on his own after a while.

**Relationship modes:** two dialogue tracks — **Husbando** (slow-burn tension with V, more flirty,
split with Misty) and **Hermano** (canon brother-in-arms, still with Misty). Hermano is the default
until you choose; switch on the **Relationship** section of the in-game Jackie Lives settings page
(Native Settings UI).

**Localization:** all player-facing text runs through `lang.lua`, which keys off the English string
itself, so an untranslated line falls back to English instead of blanking. **Japanese** ships in
`translations.lua`; add a language with `python3 tools/lang_extract.py`.

Player-facing release notes are in [docs/NEXUS_UPDATE_NOTES.md](docs/NEXUS_UPDATE_NOTES.md). The live
roadmap and the full Problems & Resolutions log are in [TODO.md](TODO.md);
[docs/conversations.md](docs/conversations.md) is the voiced-line bank and
[docs/DESIGN.md](docs/DESIGN.md) the full design.

## Story modes

The mod has two mutually-exclusive **story modes**, chosen from the CET overlay window (Story mode
selector). The default is **Quiet Life**; switching to **Blaze of Glory** is a deliberate, guarded action.

- **Quiet Life** *(default, recommended)* — the main story plays out as normal, but Jackie secretly
  survived and returns as a living Heywood NPC. The least invasive layer; Jackie can join **side jobs
  only**, never the main plot. This is the mode all the polished content above targets.
- **Blaze of Glory** *(extremely experimental)* — an alternate timeline where you and Jackie fight out
  of the Heist: take down Smasher & Takemura, escape by helicopter, and cash out the Relic. It
  **disables the main plot** (no Relic, no Johnny, no dying). Because it rewrites the Heist ending, it
  must be chosen **before the Heist** and **cannot be undone** — so the toggle is behind a two-step
  "Are you sure? → Yes" confirm, and lives only in the CET developer overlay (not the in-game Esc menu).
  The Heist set-piece (spawn Takemura → Smasher → escape heli, Jackie fighting alongside as a companion
  with voiced barks, then wake at Vik's) is an early prototype. This mode is a
  **work-in-progress / throwaway-save toy**; see [TODO.md](TODO.md) and
  [docs/DESIGN.md](docs/DESIGN.md) §11 for scope and status.

## Installing (players)

Install the release zip with Vortex or MO2 — it carries a `fomod/` installer, so the manager maps
`bin\` and `r6\` to the game root for you — or extract it into the game folder by hand.

**The requirements list, first-run steps, and troubleshooting live in
[`mod/JackieLives/README.md`](mod/JackieLives/README.md)**, which ships inside the zip. In short:
RED4ext, CET 1.18.1+, AMM and Codeware are required; Audioware (his voice), AMM Expressions Overhaul
(his mouth moving) and Native Settings UI (the in-game settings page) are optional but wanted.

⚠️ **Jackie's voice is not shipped and cannot be** — CDPR's audio isn't redistributable. The mod ships
the Audioware bank *manifest* and runs **subtitle-only** without the audio; you extract the lines
yourself, following `r6\audioware\JackieLives\HOW_TO_ADD_JACKIE_VOICES.txt` in the zip.

## Updating & installing (Windows dev machine)

**Double-click `deploy.bat` in the repo root.** That's the whole workflow — it pulls the newest
code from GitHub and copies it into the game (CET mod → `bin\x64\plugins\cyber_engine_tweaks\mods\`,
voice bank → `r6\audioware\`). Nothing to move by hand. Restart the game afterwards.

Both files live at the **repo root**, next to `mod/` and `staging/` — not inside `mod/`.

| I want to… | Run |
|---|---|
| Update from GitHub + install | `deploy.bat` (double-click) |
| Install without pulling (offline, or testing local edits) | `deploy.bat -NoPull` |
| Pull even though I have uncommitted local edits | `deploy.bat -Force` (stashes and reapplies them) |
| Point at a non-Steam install | `deploy.bat -GameDir "X:\Games\Cyberpunk 2077"` |

If the repo has uncommitted changes, the pull is **skipped** rather than clobbering them — the script
says so and deploys what's on disk. `deploy.bat` is only a wrapper that runs `deploy.ps1` with
`-ExecutionPolicy Bypass`, because Windows blocks `.ps1` files by default; you can call `deploy.ps1`
directly from a PowerShell prompt instead.

## Layout

| Path | What |
|------|------|
| `mod/JackieLives/` | The CET mod. `init.lua` (engine), `config.lua` (data: schedule, locations, dialogue), `blaze.lua` / `retrieval.lua` (the two questlines), `dialogui.lua` (native dialogue picker), `lang.lua` + `translations.lua` (localization), and the shipped player README |
| `staging/` | **The zip layout.** Mirrors the game root: `fomod/` + `bin/…/mods/JackieLives/` + `r6/audioware/JackieLives/`. Keep in lockstep with `mod/` — `mod/` is the source of truth |
| `dist/` | Built release zips |
| `audioware/JackieLives/` | Audioware voice-bank manifest (`.yml` + `index.json`). The audio files themselves are gitignored |
| `tools/` | Build + content tooling — see below |
| `docs/` | Design, setup, captured positions, release notes, logbook |
| `deploy.bat` / `deploy.ps1` | Pull from GitHub, then deploy the mod + voice bank into the game (auto-detects Steam) |

## Tests (run before every release)

Stock Lua, no game needed. The two that take a path **extract the real functions out of `init.lua`**
and run them against stubs, so they can't drift from shipped code.

```
lua tools/test_dialogui.lua                              # 35 checks: the native dialogue picker
lua tools/test_walk_gates.lua  mod/JackieLives/init.lua  # 20 checks: abreast/trail handoff gates
lua tools/test_blaze_calm.lua  mod/JackieLives/init.lua  # the Blaze finale "transport calm"
```

## Package a release

```
./tools/package_nexus.sh        # -> dist/JackieLives-v<Config.version>.zip
```

Reads the version from `Config.version`, refuses to build if `fomod/info.xml` disagrees, strips Mac
metadata, and then **verifies** the archive (no wrapper folder, `fomod/` at the root, `init.lua` at the
CET path). Bump `Config.version` **and** `fomod/info.xml` together.

## Build the voice bank (assets are not shipped)

The lines are auditioned and tagged in `tools/voice-tagger/` (a small web app), transcribed with
`whisper_transcribe.py`, then converted and manifested:

```
python tools/convert_audio.py      # tools/voice-tagger/audio/*.ogg (Opus) -> audioware/JackieLives/ (Vorbis) + the .yml
python tools/rebuild_bank_yml.py   # rebuild the manifest alone, dropping any line whose .wav is missing
```

⚠️ Audioware rejects the **whole bank** if the manifest names a file that isn't there — one bad entry
means Jackie is completely silent. `rebuild_bank_yml.py` is the fix for that.

## Tech stack

RED4ext · redscript · Cyber Engine Tweaks (CET) · TweakXL · ArchiveXL · Codeware ·
AppearanceMenuMod (AMM) · Audioware. Authoring with WolvenKit where assets are needed.

## License

Original code & tooling: [MIT](LICENSE). Game assets: not included, not licensed —
property of CD PROJEKT RED.
