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

## ⚠️ Three repos share this engine
`JackieLives`, [`NCLives`](https://github.com/Schakka96/NCLives) and `NCLucy`. NCLives was ported from
this one and NCLucy was split out of NCLives, so all three carry the same `dialogui.lua`, `vo.lua`,
`session.lua`, `lang.lua`, `native.lua` and the same engine shape in `init.lua`.

**"The repo" is ambiguous — check which one you are in before acting**, especially when something is
reported missing. And an engine fix made here does **not** reach the other two: port it deliberately,
in the same session, or it drifts. Two examples of what drift costs, both 2026-08-14:

- the dialogue-highlight bug was fixed in all three at once (one file, three copies);
- the dead `addButton` here had **already been fixed in NCLives months earlier** — nobody carried it
  back, and Jackie shipped an unreachable Esc-menu button until `tools/loadsim.lua` was ported.

## Environment / platform notes

- **Mac** = code, docs, and every offline check below. **Windows 11 / PowerShell** = deploy and
  in-game testing. Synced via GitHub; `deploy.bat` at the repo root pulls before it copies.
- ✅ **The game is installed on the Mac too** (native macOS build, unmodded, base 2.3, no Phantom
  Liberty): `~/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077`. You cannot *run* it
  from here, but you can *read* it — so never guess whether an asset path exists.
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
  archive/pc/mod/                                         <- JackieLives.archive + .archive.xl (v1.71, the female-V voice map)
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
| `tools/test_vo.lua` | `lua tools/test_vo.lua` — 132 checks. **Run before every deploy.** §9 fails the build if the shim's symbols ever carry NCLives' or NCLucy's prefix. |
| `mod/JackieLives/vo_gender.lua` | GENERATED by `tools/gen_vo_gender.py`. Covers **Jackie's AND V's** gendered lines since v1.70. |
| `tools/build_line_library.py` | `python3 tools/build_line_library.py build` — every line every character recorded, from the local install (~100 s, cached). Writes gitignored `vo_library/`. |
| `tools/v_index.py` | **The V corpus, made navigable.** See "V speaks too" below. |
| `mod/JackieLives/vo_female_ids.lua` | GENERATED by `tools/gen_vomap.py`. See "The female take" below. |
| `tools/gen_vomap.py` | **Mac only** (reads the installed game). Writes the archive sources + the Lua map. `--check` fails if they're stale. |
| `tools/build_archive.py` + `build_archive.bat` | **Windows only** (WolvenKit CLI). Bakes those sources into `JackieLives.archive`. `--digest` works anywhere. |

## The female take — v1.71 (2026-08-15)

⚠️ **Read `../NCLives/docs/research/vo_gender.md` before touching any of this.** It records four
sessions of eliminated theories, and re-deriving them is the expensive mistake here.

A line's male and female takes **share ONE String ID**. `locVoiceoverMap` holds a PAIR of paths and
the ENGINE picks the column, natively: `audioDialogLineEventData` has no gender field, `AudioSystem`
has no gender argument, and there is exactly one `v` voice tag. **So no Lua and no redscript can ask
for a take** — the Esc control used to vary the *shape* of the event and was, provably, doing
nothing.

The fix is to put the recording we want behind a String ID **of our own**: `gen_vomap.py` mints a
synthetic id per gendered line whose female *and* male columns both point at the vanilla female
`.wem`, and ArchiveXL **merges** those rows into the game's voiceover index (`vomaps:` — undocumented
but in ArchiveXL's source). `VO.femaleTakeId` then substitutes it. 47 rows: **41 of V's own lines and
6 of Jackie's "chica"/"mano" pairs**, which are gendered for the same reason (they address V).

- **ArchiveXL is a new OPTIONAL dependency.** Without it, or without the archive, `jlArchiveLoaded()`
  returns false and everyone keeps the male takes — the pre-v1.71 behaviour, not a crash.
- ⚠️ **Never speak a synthetic id without checking the archive.** It resolves to nothing and the line
  is SILENT, with no error anywhere (the shim returns true for any id it can parse). That is strictly
  worse than the wrong gender, which is why the archive gate is checked LAST, after the preference.
- ⚠️ **The archive-presence beacon is not dead content.** JackieLives has no journal to probe, so the
  archive carries one localization string (`jl_archive_beacon`) purely so Lua can detect it.
- ⚠️ **`jlLineText` follows the AUDIO now, not V's body.** A female-bodied player with no archive
  reads "mano", because "mano" is what she hears. Reading the wrong word was the original bug.
- The Esc control (`JL.vVoice` → `jlTakePref`) finally does something: Auto / Male / Female now pick
  the TAKE. `jlPlayerVariant()` is pinned to 0 and kept only so nobody re-derives the dead theory.

## V speaks too — v1.70 (2026-08-14)

V's own dialogue choices are voiced now, out of V's body, with V's own recordings. A choice row —
or a `callFarewells` entry, or a `textPool` row — may carry `sfx = "jl_<String ID>"`, and
`jlSpeakPlayerLine` plays it while the subtitle is held for the recording's real length.

⚠️ **It does NOT go through `VO.play`.** That path honours `Config.voice.voiceTag`, so handing it
the player would make V answer Jackie *in Jackie's voice*. `JLVO_SpeakAsPlayer` (shim v3) has no
tag argument at all — the API refusing to express the only mistake available here.

⚠️ **V's voice gender is the ENGINE's call, not ours.** One String ID, two takes, picked from V's
BODY. Nothing here *tells* the game what sex V is — it already knows. All a mod can change is the
SHAPE of the event, in the hope the engine then resolves the take differently. `jlPlayerVariant()`
owns that choice; never wire it to the Husbando/Hermano switch, which is a story preference about
*Jackie's* lines and says nothing about V's body.

| `JL.vVoice` | variant | |
|---|---|---|
| `auto` (default) | body decides: male → 0, female → `femaleVariant` | Esc ▸ Settings ▸ Jackie Lives ▸ Voice |
| `male` | 0 — `isPlayer`, no tag | the shape with in-game evidence |
| `female` | 1 — no `isPlayer`, inject `n"v"` | **hypothesis, never heard yet** |

**The female half is unverified.** Settle it with the CET window ▸ Voice ▸ **"Test V's voice (A/B)"**
— one press plays the same line as both variants, ~3 s apart, each named in `jackie_debug.log`.
⚠️ **If both takes sound identical, the engine is reading V's body and ignoring the event shape:
retire the switch, don't retune it.** The first V line each session also logs shim version, body
gender and brain gender, because three of the four "V sounds wrong" causes are answerable from the
log alone (and `shim=v0` means the `.reds` never deployed, which is the whole bug).

**Finding a line to use** — V has **12,996** of them, so don't grep the raw library:

```
python3 tools/v_index.py build     # once: vo_library/v_index.{json,html}
python3 tools/v_index.py find --intent farewell --to jackie,- --standalone --max-secs 3
python3 tools/v_index.py verify    # ⚠️ RUN THIS AFTER ANY sfx EDIT
```

`find` prints paste-ready Lua rows. Every line is bucketed by **intent** (greet/farewell/checkin/
affirm/decline/gig/invite/…), mood, channel (phone/inner/world), length, addressee, whether the
male and female takes use different WORDS, and whether it is **standalone** — sayable on any day
of the story, which is the bar hub small talk has to clear. `v_index.html` filters as you type.

`verify` catches the three mistakes that are **audible only**: a V line in Jackie's mouth (or the
reverse), a caption that isn't what the recording says, and a gendered line with no `vo_gender.lua`
entry. Near-identical captions are a *note*, not a failure — several of Jackie's differ from CDPR's
by punctuation, and `translations.lua` is keyed on the authored English, so "fixing" one drops nine
languages to English to correct something no player can hear.

**Three rules when casting a V line** (all learned the hard way in v1.70):
1. **The recording owns the words.** Bend the row's text to the take; never caption a recording
   with something it doesn't say.
2. **Check the reply still answers it.** The corpus will happily hand you "Misty misses you...
   loads." for Misty's shop — V recorded it while Jackie was *dead*, and it contradicts this mod's
   entire premise. Every swap needs the node it leads to read back.
3. **A voiced row must never be the only way out of a node whose setup varies.** A `jackiePool`
   draws at random; keep a written row that fits whatever he happened to say.

⚠️ **A String ID is ~2e18 and Lua numbers are doubles.** `tonumber("1660220866564214792")` returns a
*different* number. Ids are strings from config.lua all the way into redscript's `StringToUint64` —
never convert one, never do arithmetic on one. It fails silently, in game only. Asserted in the tests.

⚠️ **Never rename the `JLVO_` prefix in the .reds.** NCLives ships the identical shim as `NCLVO_`;
redscript refuses two definitions of one name, so a shared file would make installing both mods
together a hard failure.

✅ **CONFIRMED WORKING IN GAME on Windows, 2026-08-13** (Antonia: *"he summons and TALKS! With his
VOICE!"*), on a build that was simultaneously AMM-free and using the native dialogue picker. Verified
against `mode = "native"`, which locks Audioware out — so the audio could only have been the game's own.

## Offline checks — run these before every deploy (Mac, no game needed)

| Command | Covers |
|---|---|
| `lua tools/loadsim.lua` | **The only check that RUNS the engine.** Stubs CET, loads `init.lua`, runs `onInit`, presses every hotkey twice (the second press takes the toggle-off branch), ticks `onUpdate`, draws the dev panel with every header forced open, registers the Esc menu against a strict Native Settings stub and presses every control on it. Plus three static scans: forward references, `addButton` arity, and the 200-local headroom. **48 checks.** |
| `lua tools/test_dialogui.lua` | The native picker, 48 checks. |
| `lua tools/test_vo.lua` | Voice, 132 checks — including that the `.reds` symbols carry no other mod's prefix. |
| `lua tools/test_familiarity.lua` · `test_follower.lua` · `test_spawn_backend.lua` · `test_walk_gates.lua` · `test_blaze_calm.lua` | One subsystem each. All run bare from the repo root. |

### Three traps these exist to catch — read before editing `init.lua`
1. ⚠️ **The 200-local cap.** `init.lua` is one chunk with ~19 spare local slots. **Never add a
   top-level `local`** — make it a global, or a module (the engine already holds seven that way:
   `Retrieval` `Blaze` `Session` `Lang` `DialogUI` `VO` `Native`). loadsim §3c reports the headroom.
2. ⚠️ **Never call a file-`local` helper from ABOVE its `local function` line.** A local is not in
   scope before its declaration, so it silently compiles to a nil GLOBAL and throws the first time
   that line runs. This shipped in NCLives as a total no-spawn. loadsim §3 scans for it.
3. ⚠️ **`ns.addButton` takes `textSize` BEFORE the callback.** Omit it and nothing complains at
   registration — it dies at DRAW time and the whole subcategory vanishes from the Esc menu. That
   shipped here, unnoticed, on the "Start the search for Jackie" button. loadsim §3b and §5 catch it.

## Files

- `CLAUDE.md` — this file (ground rules + project summary).
- `docs/DESIGN.md` — lore, the Quiet Life integration, summon rules, retrieval-quest outline, caveats.
- `TODO.md` — live roadmap (tiers + MVP), open decisions, and Problems & Resolutions log.
