# Why Jackie's outfits never applied — AMM's `NewSpawn` appearance contract

Research for JackieLives (v1.43). Verified verbatim against the `main` branch of
[AppearanceMenuMod](https://github.com/MaximiliumM/appearancemenumod) and its shipped `db.sqlite3`.

## Symptom

The Blaze heist Jackie spawned at Konpeki Plaza in his **normal** clothes, not the Militech heist suit
(`Blaze.yori.fightAppearance = "jackie_welles__q005_suit"`).

## Verdict — TWO independent bugs, both fixed

The name was never wrong. Two separate things were.

### Bug 1 (the big one): we passed AMM a table where it wanted a string

`ammSpawn` called:

```lua
spawn = amm.Spawn:NewSpawn(name, recStr, { app = app }, companionFlag, recStr)   -- WRONG
```

AMM's real signature (`Modules/spawn.lua:11`):

```lua
function Spawn:NewSpawn(name, id, parameters, companion, path, template, rig)
    obj.appearanceName = (parameters or {}).app or "random"   -- written, NEVER read anywhere in AMM
    obj.parameters     = parameters                            -- <-- this is what actually gets used
```

`parameters` must be the **appearance name as a plain string**. Every real AMM call site passes a string
(e.g. `newEntity.parameters = AMM:GetScanAppearance(entity.handle)`).

Then `Spawn:SpawnNPC` does:

```lua
elseif (#custom > 0 or spawn.parameters ~= nil) then
    AMM:ChangeAppearanceTo(spawn, spawn.parameters)
```
→ `AMM:ChangeScanAppearanceTo(t, newAppearance)` →
```lua
t.handle:PrefetchAppearanceChange(newAppearance)
t.handle:ScheduleAppearanceChange(newAppearance)
```

Handed a **table** where a CName/string is required, both calls **silently no-op** — no error, no log — and
the NPC keeps his record default.

The trap is `obj.appearanceName = (parameters or {}).app`. That line reads exactly the `.app` key we were
passing, which is presumably why the table shape looked right. But `appearanceName` is **written once and
never read** anywhere in AMM's codebase. It's a dead field.

**Consequence: no appearance this mod ever requested was applied.** Not the heist suit, and not the venue
outfits either (`misty`, `afterlife`, `redwood` → `_default_collar_down`; `ginger`, `lizzies` →
`__q000_lizzies_club_no_jacket`). It went unnoticed for ~20 versions because 3 of the 7 venues ask for
`jackie_welles_default`, which is what the fallback produced anyway.

**Fix:** pass the string.
```lua
spawn = amm.Spawn:NewSpawn(name, recStr, app, companionFlag, recStr)   -- RIGHT
```

### Bug 2: the companion's outfit wasn't remembered across respawns

Two paths respawn a live companion — `catchUpTick` (stranded beyond teleport range) and
`companionPersistTick` (body culled / fast-travel). Both called `respawnCompanionAtV()`, which called
`ammSpawn(1)` with **no appearance**, resolving to `Config.defaultAppearance`.

So even once Bug 1 was fixed, the heist Jackie would lose his suit the first time Konpeki's streaming culled
him — which is constant during that mission.

**Fix:** `ammSpawn` records the *resolved* appearance on `JL.summon.appearance` for companion spawns;
`jlCompanionAppearance()` reads it back; `respawnCompanionAtV()` captures it before the despawn and
respawns him wearing it. Recording the resolved name (not the argument) means a plain `ammSpawn(1)` still
records `"default"`, so a normal summon reads back correctly.

## How AMM applies an appearance (worth knowing)

**Post-spawn, not at spawn time.** `SpawnNPC` sets `recordID`/`tags`/`position`/`orientation` on the
`DynamicEntitySpec` but never `appearanceName`. The entity spawns in its record default, and AMM then
`Cron.Every(0.2)`-polls `Game.FindEntityByID(spawn.entityID)` until the handle resolves, and only then
prefetches + schedules the appearance change (with further `Cron.After(0.15)` / `(0.2)` delays).

Implications for us:
- Calling `PrefetchAppearanceChange`/`ScheduleAppearanceChange` on a not-yet-attached entity **no-ops**.
- Prefetch **then** Schedule, same string, is the reliable order.
- An invalid appearance name is a **silent no-op** — he simply keeps what he's wearing. There is no error to
  catch, which is exactly why this bug was so quiet. (Inferred from AMM's code; AMM never checks a return
  value, it just trusts names from its own DB. UNVERIFIED by external report.)

## Jackie's verified appearance names

Source: AMM `db.sqlite3` → `appearances` where `entity_id = '0xA1C78C30, 16'` (→ `Character.Jackie`).
**One record carries all 17** — there is no separate q005 record needed for the suit.

```
jackie_welles_default                        jackie_welles_valentino
jackie_welles_default_collar_down            jackie_welles_valentino_beaten_up
jackie_welles_default_no_machete             jackie_welles_valentino_beaten_up_alt
jackie_welles__q000_lizzies_club_no_jacket   jackie_welles_valentino_collar_down
jackie_welles__q000_lizzies_club_no_machete  jackie_welles_wounded
jackie_welles__q005_suit                     jackie_welles_wounded_bleeding
jackie_welles__q005_suit_bleeding            jackie_welles_naked
jackie_welles__q005_suit_dirty               jackie_welles_naked_erect
jackie_welles__q005_suit_wounded
```

Naming rule: **quest-tagged appearances take a DOUBLE underscore** before the quest tag
(`jackie_welles__q005_…`, `jackie_welles__q000_…`); everything else is single
(`jackie_welles_default`, `_valentino`, `_wounded`). `jackie_welles_q005_suit` (single) does not exist.

All four names the mod uses are CONFIRMED valid. The record is `Character.Jackie` (AMM entity_id
`0xA1C78C30, 16`, rig `man_big`); `Character.jackie_welles` / `Character.q005_jackie` are not AMM-spawnable.

Note: `q005_suit_dirty` is a real *appearance* as well as an item — so if the clean `__q005_suit` reads too
pristine for a Konpeki firefight, `jackie_welles__q005_suit_dirty` (and `_bleeding` / `_wounded`) are drop-in
alternatives for `Blaze.yori.fightAppearance`.

## Never verified (and why it doesn't block us)

- AMM's `NewSpawn` arg 2 (`id`) is meant to be the AMM entity_id (`"0xA1C78C30, 16"`), and we pass the record
  string instead. It's only AMM's bookkeeping/SQL key. Jackie has no custom-appearance params, so
  `GetCustomAppearanceParams` returns empty and the standard `ChangeScanAppearanceTo` path runs regardless.
  **Left as-is deliberately** — changing it also changes `Util:CheckVByID(spawn.id)` behavior, and the
  current value is confirmed-good in-game across every spawn path in this mod.
- Whether the game's raw `.app` for Jackie holds appearances beyond AMM's 17 (cut/unused). Not cross-checked
  against a WolvenKit dump.

## Sources
- `Modules/spawn.lua`, `init.lua` (`ChangeAppearanceTo`, `ChangeScanAppearanceTo`), `Collabs/API.lua`, and
  `db.sqlite3` — https://github.com/MaximiliumM/appearancemenumod
