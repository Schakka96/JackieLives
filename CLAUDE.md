# CLAUDE.md — Cyberpunk 2077 "Jackie Lives" Mod Project

Guidance for Claude Code when working in this project folder.

## What this project is

An extensive Cyberpunk 2077 mod (likely a small **framework**, not a single mod) that brings
**Jackie Welles** back after his Act 1 death — in a lore-friendly way — and integrates him as a
**living city NPC**, not a default follower.

Core design (decided):
- **Revival story = Option B**: Jackie didn't die at Vik's. He was smuggled out / quietly healed and
  went into hiding. A new **retrieval questline** brings him back into Night City.
- **The Quiet Life**: Jackie has chosen out of the merc life (near-death scared him straight, injury +
  Mama Welles won't allow it). He works a bar and acts as a low-level **community fixer in Heywood**.
- **Not a follower by default.** He's a scheduled-presence NPC with probabilistic encounters and
  conditional dialogue. The player can **summon him onto SIDE jobs only**; trying to pull him into a
  **MAIN quest** makes V decline ("not dragging Jackie into this mess").

See `docs/DESIGN.md` for the full lore + system design and `TODO.md` for the live task list.

## Ground Rules (always apply this session and future ones)

1. **Reality-check everything for feasibility.** Antonia has almost no modding experience. Before
   proposing an approach, state honestly whether it's achievable, and prefer implementations Claude
   can actually drive to completion. Flag anything that needs huge effort or is impractical.
2. **Beginner-friendly instructions.** Antonia can install anything (game, WolvenKit, mods, languages,
   tools) but needs exact, step-by-step "do this, click that" guidance — not assumptions.
3. **Reuse existing frameworks; don't reinvent wheels.** The game and the modding ecosystem already
   provide NPC reactions, pathfinding, follower/companion AI, quest/fact systems, dialogue scenes.
   Always look for an existing system/mod to build on before writing anything custom.
4. **Stay on top of scope & organization.** Claude owns project structure, the dependency list, and the
   roadmap. Keep a sane file layout and a rational dependency tree.
5. **Keep `TODO.md` current.** Update it after **every major change** — tasks done, tasks pending, and a
   running **Problems & Resolutions** log (problem faced → how it was solved).
6. **Three priority tiers:** Tier 1 = framework & core functionality · Tier 2 = immersion ·
   Tier 3 = details & fun interactions. Build Tier 1 first, smallest viable thing at each step.
7. **MVP first, then grow.** Prove feasibility with the smallest spawn-and-behave slice before adding
   complexity. Claude proposes the step order.
8. **Commit at every working version; tag releases.** Whenever a feature/fix reaches a working,
   testable state, make a git commit (don't batch many features into one rare commit). Use a clear
   `feat:`/`fix:`/`docs:` message. When a commit corresponds to a bumped version (e.g. v0.44), also
   `git tag v0.44` so it's easy to check out and diff later. Push to GitHub after committing for an
   offsite backup. Rationale: every commit is a full recoverable snapshot — this is what lets us roll
   back or compare when something breaks, and it means **superseded files should be deleted, not kept
   in a "legacy" folder** (git history is the archive).

## Tech stack (the frameworks we build on — install/reference)

Runtime mod stack (all standard Cyberpunk modding foundations):
- **RED4ext** — native plugin loader (foundation).
- **redscript** — compiler for the game's own scripting language; how we hook game logic/quests/dialogue.
- **Cyber Engine Tweaks (CET)** — Lua runtime + console; best tool for rapid prototyping, spawning NPCs,
  reading/setting quest facts, hooking events at runtime.
- **TweakXL** — runtime TweakDB record add/edit (NPC/character/item records).
- **ArchiveXL** — runtime loading of new entities, appearances, world/streaming additions.
- **Codeware** — scripting extension lib (reflection, persistent entity spawning, NPC utilities).
- **AppearanceMenuMod (AMM)** — already spawns Jackie and makes him a competent follower; our fast
  prototyping reference + possible runtime dependency for summon behavior.

Authoring tool:
- **WolvenKit** — the modding IDE: browse/extract `.archive` game files, edit entity/appearance/quest
  (`.quest`/`.questphase`/`.scene`) resources, repack. Used for asset + quest-graph work (heaviest part).

Our scripting: primarily **redscript** for game logic + **Lua (CET)** for prototyping/runtime glue.
Content (dialogue trees) should be **data-driven** so writing can be added without code changes.

## Environment / platform notes

- OS: Windows 11. Shell = PowerShell (Git Bash also available).
- ⚠️ **Game version compatibility is the #1 source of breakage.** The framework mods must match the game
  patch. Pin a stable game version and **disable auto-update** before building.
- ⚠️ The **Game Pass / Microsoft Store** version is much harder to mod. **GOG or Steam** strongly preferred.
- Always test on a **fresh/backup save**; mods can corrupt saves.

## Packaging for release (Nexus / mod managers)

The Nexus-ready mod lives in **`staging/`** and its internal layout **is** the zip layout — it must
mirror the game root so Vortex/MO2 install files 1:1. Current structure:

```
staging/
  fomod/                  <- installer metadata (info.xml + ModuleConfig.xml)
  bin/x64/plugins/cyber_engine_tweaks/mods/JackieLives/   <- CET mod (init/config/retrieval/README)
  r6/audioware/JackieLives/                               <- Audioware bank manifest + HOW_TO_ADD_JACKIE_VOICES.txt
```

Rules for future sessions:
- **A `fomod/` folder is required at the staging root.** It's what makes Vortex/MO2 recognise the mod
  instead of showing the "couldn't determine mod type / fallback installer" notice. `ModuleConfig.xml`
  installs `bin\` and `r6\` 1:1 to game root with no user options; bump the version in both `info.xml`
  and `Config.version` on release.
- **When you zip for upload, zip the *contents* of `staging/`** — so `fomod\`, `bin\`, `r6\` sit at the
  archive TOP LEVEL. Never zip the `staging` folder itself; a wrapper folder breaks FOMOD detection and
  drops the manager back to the fallback installer.
- **Copyrighted audio stays OUT** (gitignored `.ogg`/`.wav`/`.wem` + `index.json`). The bank manifest
  (`JackieLives.yml`) ships; users add Jackie's real voice themselves via WolvenKit (see the HOW_TO).
- Keep `staging/` in lockstep with `mod/JackieLives/` — the source of truth is `mod/`, staging is the
  packaged copy.

## Reference mods — `../reference_mods/` (read them; never republish them)

Third-party mods downloaded to study live in **`Mods/reference_mods/`** (sibling of this repo), one
folder per mod, Nexus download name intact. Currently: AMM, Night City Allies, the Panam and Rita
message mods, **V Voice Framework**. Read them before writing anything custom (ground rule 3) — and
cite them as `reference_mods/<mod>/<file>:<line>` in code comments.

⚠️ **Never commit or redistribute them.** They are other authors' work and their `.archive` files
contain CDPR assets. The folder is outside every git repo; `.gitignore` also lists `reference_mods/`
defensively. We ship nothing from it — the player installs any dependency themselves.
Full policy: `../GROUND_RULES.md`.

## Voice: v1.66 replaced Audioware entirely (2026-08-13)

**Read `docs/research/native_vo_dialogline.md` before touching anything voice-related.** Jackie now
speaks with the game's OWN recordings — no shipped audio, no extraction, no Audioware, no WolvenKit
for players. A `DialogLineEvent` carrying `audioDialogLineEventData.stringId` names the exact line;
our existing `sfx = "jl_<digits>"` content already held those ids, so nothing was rewritten.

| file | role |
|---|---|
| `reds/JackieLivesVO.reds` | the redscript shim (**optional** dependency). Deployed to `r6\scripts\JackieLives\`. |
| `mod/JackieLives/vo.lua` | global `VO` — the backend ladder: native → Audioware → ono grunt. |
| `mod/JackieLives/vo_durations.lua` | GENERATED by `tools/gen_vo_durations.py`; never hand-edit. |
| `tools/test_vo.lua` | `lua tools/test_vo.lua` — 53 checks. **Run before every deploy.** |

⚠️ **A String ID is ~2e18 and Lua numbers are doubles.** `tonumber("1660220866564214792")` returns a
*different* number. Ids are strings from config.lua all the way into redscript's `StringToUint64` —
never convert one, never do arithmetic on one. It fails silently, in game only. Asserted in the tests.

⚠️ **Never rename the `JLVO_` prefix in the .reds.** NCLives ships the identical shim as `NCLVO_`;
redscript refuses two definitions of one name, so a shared file would make installing both mods
together a hard failure.

✅ **CONFIRMED WORKING IN GAME on Windows, 2026-08-13** (Antonia: *"he summons and TALKS! With his
VOICE!"*), on a build that was simultaneously AMM-free and using the native dialogue picker. Verified
against `mode = "native"`, which locks Audioware out — so the audio could only have been the game's own.

## Files

- `CLAUDE.md` — this file (ground rules + project summary).
- `docs/DESIGN.md` — lore, the Quiet Life integration, summon rules, retrieval-quest outline, caveats.
- `TODO.md` — live roadmap (tiers + MVP), open decisions, and Problems & Resolutions log.
