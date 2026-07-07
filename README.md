# Jackie Lives — a Cyberpunk 2077 mod

Bring **Jackie Welles** back after his Act 1 death, in a lore-friendly way, as a
**living Night City NPC** — not a default follower. Jackie didn't die at Vik's; he was
quietly smuggled out and healed, chose out of the merc life, and now works a bar and acts
as a low-level community fixer in Heywood. The player can summon him onto **side jobs only**.

> ⚠️ Fan project, not affiliated with CD PROJEKT RED. **No game assets are distributed here** —
> see [ASSETS_NOTICE.md](ASSETS_NOTICE.md). Requires a legally owned copy of Cyberpunk 2077.

## Status

Working CET-based prototype (v0.43). Jackie spawns and follows/fights as a companion, runs a
shuffled **daily schedule** (idle-spawns + free-roam wander at captured venues, per-location
outfits, sit/lean poses, a secret nap cameo), and talks through a data-driven **branching
dialogue box** with real voiced lines. You can **call him onto a side job** (holocall → he walks
or rides in), **talk** to him with location-specific trees, **send him off** (he walks away), and
**take him to dinner** (pick a restaurant → map waypoint + objective → he takes his seat → his
companion timer resets). A companion-duration clock sends him home on his own after a while.
See [TODO.md](TODO.md) for the live roadmap, [docs/conversations.md](docs/conversations.md) for the
voiced-line bank, and [docs/DESIGN.md](docs/DESIGN.md) for the full design.

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
  This mode is a **work-in-progress / throwaway-save toy**; see [TODO.md](TODO.md) and
  [docs/DESIGN.md](docs/DESIGN.md) §11 for scope and status.

## Layout

| Path | What |
|------|------|
| `mod/JackieLives/` | The CET mod — `init.lua` (logic), `config.lua` (data: schedule, locations, dialogue) |
| `audioware/JackieLives/` | Audioware voice-bank manifest (`.yml` + `index.json`). Audio files are gitignored. |
| `tools/` | `scrape_jackie.py` (voice-line catalogue), `convert_audio.py` (build the bank), `voice-tagger/` (web app to audition/tag lines) |
| `docs/` | Design, setup, captured positions, logbook |
| `deploy.ps1` | One-command deploy of the mod to the CET mods folder (auto-detects Steam) |

## Tech stack

RED4ext · redscript · Cyber Engine Tweaks (CET) · TweakXL · ArchiveXL · Codeware ·
AppearanceMenuMod (AMM) · Audioware. Authoring with WolvenKit where assets are needed.

## Build the voice bank (assets are not shipped)

```
python tools/scrape_jackie.py      # download Jackie's lines (CDPR audio, local only)
python tools/convert_audio.py      # build audioware/JackieLives/ (auto-fetches ffmpeg)
```

## License

Original code & tooling: [MIT](LICENSE). Game assets: not included, not licensed —
property of CD PROJEKT RED.
