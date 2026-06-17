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

## Files

- `CLAUDE.md` — this file (ground rules + project summary).
- `docs/DESIGN.md` — lore, the Quiet Life integration, summon rules, retrieval-quest outline, caveats.
- `TODO.md` — live roadmap (tiers + MVP), open decisions, and Problems & Resolutions log.
