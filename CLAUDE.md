# CLAUDE.md — JackieLives

Jackie Welles, back after Act 1, as a living Heywood NPC — not a default follower.
Design: `docs/DESIGN.md`. Tasks: `TODO.md`. Ground rules: repo root `../CLAUDE.md`.

## Design (decided)
- Jackie was smuggled out, healed, hidden. A retrieval questline brings him back.
- Retired from merc life. Works a bar, low-level Heywood fixer.
- Not summonable as a follower. Summon works on SIDE jobs only; declines MAIN quests.

## Stack
RED4ext (native loader) + redscript (game logic/quests/dialogue) + CET/Lua (prototype/runtime glue) +
TweakXL (records) + ArchiveXL (entities/appearances) + Codeware (utils) + AMM (reference, optional
follower behavior). WolvenKit for asset/quest editing. Content is data-driven.

## Three repos share this engine
JackieLives, NCLives, NCLucy carry the same `dialogui.lua`/`vo.lua`/`session.lua`/`lang.lua`/
`native.lua`/`init.lua` shape. **Check which repo you're in** before acting, especially on "X is
missing" reports. Fixes here don't propagate — port deliberately, same session, or it drifts.

## Environment
Mac = code. Windows = deploy + in-game test. Sync via GitHub.
Game is also installed on the Mac (base 2.3, no Phantom Liberty, unmodded):
`~/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077` — readable, not runnable, so
verify asset paths instead of guessing. Pin game version, disable auto-update. GOG/Steam only, never
Game Pass. Test on backup saves.

## Packaging (Nexus)
`staging/` layout = zip layout = mirrors game root: `fomod/`, `bin/x64/plugins/.../JackieLives/`,
`r6/audioware/JackieLives/`, `archive/pc/mod/`. `fomod/` is required (else Vortex/MO2 fallback
installer). **Zip the contents of `staging/`**, never the folder itself. No copyrighted audio ships
(gitignored) — only the bank manifest; players add real voice via WolvenKit. `mod/` is the source of
truth; keep `staging/` in lockstep.

## Voice — game's own recordings (v1.66+, no shipped audio)
`DialogLineEvent` + `audioDialogLineEventData.stringId` plays an exact game line. Read
`docs/research/native_vo_dialogline.md` before touching anything voice-related.

| file | role |
|---|---|
| `reds/JackieLivesVO.reds` | optional redscript shim, deploys to `r6/scripts/JackieLives/` |
| `mod/JackieLives/vo.lua` | `VO` — backend ladder: native → Audioware → grunt |
| `mod/JackieLives/zengine.lua` | optional 0-Engine integration; read `../NCLives/docs/research/zero_engine.md` first — never move our tick into their `OnUpdate`, never source V's position from them, `nil` = ask the engine, never guess |
| `mod/JackieLives/vo_durations.lua`, `vo_gender.lua`, `vo_female_ids.lua` | GENERATED — never hand-edit |
| `tools/test_vo.lua` | 132 checks, run before every deploy; fails if shim symbols carry another mod's prefix |
| `tools/build_line_library.py` | every recorded line, from local install, cached |
| `tools/v_index.py` | V's 12,996-line corpus, made searchable — see below |
| `tools/gen_vomap.py` | Mac-only, reads installed game, writes female-take sources + Lua map; `--check` catches staleness |
| `tools/build_archive.py` | Windows-only (WolvenKit CLI), bakes sources into `JackieLives.archive` |

## The female take (v1.71)
Read `../NCLives/docs/research/vo_gender.md` first — four sessions of eliminated theories.
A line's male/female takes share ONE String ID; the engine picks the column from V's body — no Lua
or redscript can request a take. Fix: `gen_vomap.py` mints a synthetic id per gendered line, both
columns pointing at the female `.wem`; ArchiveXL merges it into the voiceover map; `VO.femaleTakeId`
substitutes it. 47 rows (41 V, 6 Jackie "chica/mano" pairs).
- ArchiveXL is optional — without it, everyone gets the male take (pre-v1.71 behavior, not a crash).
- Never speak a synthetic id without checking the archive — unresolved id = silence, no error.
- `jlLineText` follows the AUDIO, not V's body.

## V speaks too (v1.70)
V's choice rows can carry `sfx = "jl_<String ID>"`; `jlSpeakPlayerLine` plays it, subtitle held for
real length. **Never route through `VO.play`** (would speak V in Jackie's voice) — use
`JLVO_SpeakAsPlayer`, no tag argument. V's voice gender is the ENGINE's call from V's body; never wire
`jlPlayerVariant()` to a story preference.

Finding a line: `python3 tools/v_index.py find --intent farewell --to jackie,- --standalone
--max-secs 3`. Run `verify` after any `sfx` edit. Casting rules: the recording owns the words (never
caption what it doesn't say); check the reply still answers the node it leads to; a voiced row must
never be the only way out of a node whose setup varies.

⚠️ String IDs are ~2e18, Lua numbers are doubles — ids stay **strings**, never `tonumber()`.
⚠️ Never rename the `JLVO_` prefix — NCLives ships the same shim as `NCLVO_`; a name collision breaks
redscript compilation for both mods if a player installs both.

## Traps in `init.lua` — read before editing
1. **200-local cap.** Never add a top-level `local` — use a global or a module.
2. **Never call a file-`local` helper from above its declaration** — silently compiles to a nil
   global, throws on first call. Shipped once as a total no-spawn.
3. **`ns.addButton` takes `textSize` before the callback.** Omit it and the button dies silently at
   draw time, not registration.

## Offline checks — run before every deploy (Mac, no game needed)
`lua tools/loadsim.lua` (loads init.lua for real, runs onInit, presses every hotkey, scans for the
three traps above, 48 checks) · `tools/test_dialogui.lua` (48) · `tools/test_zengine.lua` (54) ·
`tools/test_vo.lua` (132) · `test_familiarity.lua` / `test_follower.lua` / `test_spawn_backend.lua` /
`test_walk_gates.lua` / `test_blaze_calm.lua`.

## Files
`docs/DESIGN.md` — lore, summon rules, retrieval quest. `TODO.md` — roadmap + Problems & Resolutions.
