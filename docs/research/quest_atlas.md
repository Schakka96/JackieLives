# Quest atlas — verified places, times, and character records the mod can already reach

Research-only, compiled 2026-08-25 for authoring a new questline with real coordinates and real
game-time precision. Everything below is either (a) captured in-game by Antonia and already wired
into `Config`, or (b) cross-checked against AMM's shipped `db.sqlite3` (an installed record's
appearance list only exists if the record itself is real — AMM ships no fake entries).

Sources: `docs/research/captured_positions.md`, `mod/JackieLives/config.lua`,
`mod/JackieLives/retrieval.lua`, `mod/JackieLives/init.lua`, `mod/JackieLives/blaze.lua`, and
`reference_mods/Appearance Menu Mod-790-.../.../AppearanceMenuMod/db.sqlite3` (read-only query,
nothing copied out of `reference_mods/`).

---

## 1. Places (name | coords | source | verified?)

All coords are world-space `{ x, y, z }`; `yaw` in degrees. "Verified" = captured in-game with the
CET position-capture button and currently live in `Config.locations`/`Config.retrieval`/etc.

| Name | Anchor pos | yaw | Source (file:line) | Verified? |
|---|---|---|---|---|
| Noodle bar (Jackie's stall) | `{ -1439.472, 1259.021, 23.090 }` | -87.1 | `config.lua:2941` (`Config.locations.noodle`) | Yes — captured |
| Misty's Esoterica | `{ -1541.777, 1196.792, 15.905 }` | 86.6 | `config.lua:2951` | Yes — captured |
| El Coyote Cojo (Mama Welles' bar) | `{ -1262.463, -1002.345, 12.037 }` | -50.9 | `config.lua:2961` | Yes — captured |
| Afterlife | `{ -1457.063, 1018.598, 16.524 }` | -96.9 | `config.lua:2973` | Yes — captured |
| Ginger Panda (restaurant) | `{ -485.426, 576.939, 31.302 }` | -17.1 | `config.lua:2984` | Yes — captured, not in daily schedule |
| Redwood Market | `{ -402.802, 710.778, 123.000 }` | 108.1 | `config.lua:2996` | Yes — captured, not in daily schedule |
| Lizzie's Bar (Mox club) | `{ -1194.874, 1561.692, 22.915 }` | -85.6 | `config.lua:3007` | Yes — captured. Closed before 21:00 in-fiction. |
| Secret nap spot (easter egg) | `{ -1470.154, 1201.503, 19.084 }` | -41.9 | `config.lua:3021` | Yes — captured |
| Vik's clinic (Misty's Esoterica interior) | `{ -1546.551, 1229.270, 11.520 }` | 129.8 | `retrieval.lua:37` (`M.Config.vikPos`) | Yes — captured |
| Rocky Ridge hideout (Badlands garage) | `{ 2575.852, 0.291, 80.871 }` | 129.8 | `retrieval.lua:41` (`M.Config.hideoutPos`) | Yes — captured |
| Reverend Flash BD shack (near Rocky Ridge gas station) | `{ 2548.57, -31.076, 82.609 }` | — | `config.lua:982` (`Config.revflash.pos`) | Yes — captured |
| Goro/Smasher elevator spot (Konpeki Plaza, Blaze finale) | `{ x=-2226.165, y=1765.743, z=308.329 }` | -157.5 | `blaze.lua:86` | Yes — captured (Blaze set-piece) |
| Test spot (native-box test save) | `{ -854.737, 1833.329, 36.207 }` | 44.4 | `config.lua:3019` | Yes — captured, dev-only |
| Jackie's apartment/home | — | — | not modeled | **NO — not captured.** Schedule treats "home" as `state = "unavailable"` (no coords at all); Jackie simply despawns. There is no home interior position anywhere in the mod. |
| Mama Welles' apartment (distinct from El Coyote) | — | — | not modeled | **NO.** Only the bar (`coyote`) is captured; if her *home* (not the bar) is a quest beat, it needs a fresh capture. |
| Rocky Ridge — wider area beyond the two captured points | — | — | partially | Only the hideout garage and the BD shack are captured; anything else "in Rocky Ridge" (e.g. a lookout point, a second building) is not. |

### Location metadata each captured venue actually carries

Each `Config.locations.<key>` entry also has: `name`, `appearance` (AMM appearance string),
`exitWaypoint` (departure/despawn point, not all venues have one), and a `waypoints` list — each
waypoint has its own `pos`/`yaw`/`pose` (`stand`/`sit`/`lean`) and optionally `dwell = {min,max}`
seconds and `poseAnim`. This is the right shape to imitate for a new venue: capture an anchor,
capture 2-6 waypoints, tag each with a pose.

---

## 2. Time / schedule system

### The exact game-time reader (copy these, don't reinvent)

| Helper | file:line | What it returns |
|---|---|---|
| `getGameHour()` | `init.lua:1419` | Current in-game clock hour as a **fractional** float (`23.5` = 23:30), wrapped 0-24. Reads `Game.GetTimeSystem():GetGameTime()`, tries `GetHour`/`GetHours` + `GetMinute`/`GetMinutes`, falls back to seconds-of-day / 3600. Returns `nil` if TimeSystem isn't up yet — **callers must handle nil**. |
| `getGameSeconds()` | `init.lua:1445` | MONOTONIC total in-game seconds across days (`GetGameTime():ToSeconds()`/`GetTotalSeconds`/`GetSeconds`). Use for measuring durations (companion timers, cooldowns), never for "what hour is it" (that wraps). |
| `jlGameDay()` | `init.lua:1520` (global, not a `local` — usable from other modules) | Absolute in-game day index (`floor(seconds/86400)`), for once-per-day gates. Returns `nil` if the clock can't be read. |
| `hourInBlock(h, s, e)` | `init.lua:1593` | `true` if fractional hour `h` falls in `[s, e)`, correctly handling a block that wraps past midnight (`s > e`, e.g. `21..3`). |
| `activeSchedule()` | `init.lua:1586` | Today's list of schedule blocks (`Config.daySchedules[dayType]`), falling back to `Config.fallbackDay`. |
| `currentScheduleBlock()` | `init.lua:1597` | The one block matching the current hour, with a special-case copy-and-mutate for the Husbando Misty-retirement swap — model for any "if X has happened, redirect this block" logic. |
| `ensureDayTemplate()` | `init.lua:1567` | Detects a midnight wrap (`hour < lastHour`) to advance to a new day-type, pulling from the shuffle bag. |

**Design pattern to copy for a quest**: don't call the raw `Game.GetTimeSystem()` API yourself —
call `getGameHour()` (promote it to a `function` global if you need it outside `init.lua`, the same
way `jlGameDay()` was) and compare against fractional hours. For "meet Jackie at X at 20:00", the
check is `local h = getGameHour(); if h and hourInBlock(h, 19.9, 20.1) and nearPoint(spot, 4.0) then ... end` —
exactly retrieval.lua's own proximity pattern (see §6).

### The day-type system (5-day shuffle bag, not a calendar)

`Config.dayBag = { "active1", "active2", "active3", "quiet", "gone" }` (`config.lua:3115`) — one
day-type is popped per in-game day (`nextDayTemplate()`, `init.lua:1558`), each type used exactly
once per 5-day cycle, order randomized, then reshuffled. This is **not** tied to real calendar days
or a quest clock — it's Jackie's own independent daily routine. A new questline that wants "Jackie
is definitely at the noodle bar on day N" either has to (a) pick a schedule-agnostic venue and gate
on proximity + time regardless of day-type, or (b) special-case override the schedule (there's
precedent: the Husbando Misty-retirement swap at `init.lua:1601-1609` mutates the schedule block by
program logic, not by editing `Config.daySchedules`).

### `Config.daySchedules` — every place Jackie goes, with hours (`config.lua:3130-3179`)

Bedtime is always midnight; sleep is always `00:00-06:00 unavailable`. Fractional hours = half-hour
resolution.

**active1** — Noodle 08:00-13:00 (5h) → home 13:00-15:00 → Misty's 15:00-21:00 (6h) → Lizzie's
21:00-23:30 (2.5h, opens 21:00 in-fiction) → El Coyote 23:30-24:00 (wind-down).

**active2** — Redwood 08:00-13:00 (5h) → Ginger Panda 13:00-17:00 (4h) → home 17:00-19:00 →
Afterlife 19:00-23:30 (4.5h) → El Coyote 23:30-24:00.

**active3** — Noodle 08:00-12:00 (4h) → Misty's 12:00-15:00 (3h) → home 15:00-17:00 → Afterlife
17:00-20:00 (3h) → El Coyote 20:00-24:00 (4h, straight to bed).

**quiet** — home 06:00-14:00 → Misty's 14:00-18:00 (4h) → home 18:00-21:00 → El Coyote 21:00-24:00
(3h).

**gone** — unavailable all 24h (he's out of town; no Coyote return this day).

Every block is `{ startHour, endHour, state = "at_location", locationKey = "..." }` or
`state = "unavailable"`. **"unavailable" carries no position at all** — that's the gap for a "home"
scene (see §1's missing row).

### The "approach cameo" boost (`Config.approach`, `config.lua:3097`)

Not a schedule mechanic per se, but relevant to quest pacing: getting within 20 m of ANY of his 7
venues rolls a chance (35% first-of-day, 10% repeat, always 10% for the noodle bar) to force his
schedule to that venue for the rest of the day, so V "runs into him" more than the raw schedule
alone would produce. If a quest needs deterministic placement, this RNG layer needs to be bypassed
or accounted for.

---

## 3. Character records — confirmed spawnable, source of truth = AMM's `db.sqlite3`

`Character.<x>` strings the mod code actually uses today, plus every Heywood/Jackie-story
character verified against AMM's shipped database (`entities` table — `entity_path` column, plus
`appearances` table for wardrobe names). AMM would silently refuse a fake record at spawn time, so
an entry existing in its DB is real confirmation the record loads.

### Already used by the mod

| Record | Where used | Notes |
|---|---|---|
| `Character.Jackie` | `config.lua:31` (`Config.jackieRecord`), `init.lua` throughout | 17 verified appearances (`docs/research/amm_appearance_research.md`) — `jackie_welles_default`, `_default_collar_down`, `__q005_suit(+variants)`, `_valentino(+variants)`, `_wounded(+variants)`, `_naked(+variants)`. AMM entity_id `0xA1C78C30, 16`, rig `man_big`. |
| `Character.Takemura` | `blaze.lua:45,86`, `init.lua:10331` (diagnostic spawn) | Confirmed via AMM (`0xF43B2B48, 18`). Goro's Blaze-finale spot: `{ x=-2226.165, y=1765.743, z=308.329 }`, yaw -157.5. |
| `Character.Smasher` | `blaze.lua:44,94`, `init.lua:10334` | Confirmed via AMM (`0x215A57FC, 17`). Spawns at Goro's same elevator pos. |
| `Character.q005_arasaka_kill_squad_1` | `blaze.lua:126` | Not independently found in AMM's DB under this exact string — the q005-suffixed grunt records may not be AMM-spawnable (only the officer variant is, see below). Treat as **unverified outside the game itself**. |
| `Character.q005_arasaka_kill_squad_4` | `blaze.lua:125` | Same caveat. |
| `Character.q005_arasaka_kill_squad_4_officer` | `blaze.lua:124` | **Confirmed** — AMM entity `0xDA75E747, 43`, "Assault Squad Commander". |

### Verified but NOT yet wired into any mod code (new — good for a Heywood/Jackie questline)

| Character | Record | AMM entity_id | Verified appearances |
|---|---|---|---|
| Vik (Viktor Vektor) | `Character.Victor_Vector` | `0x717263B6, 23` | `victor_vektor_default`, `victor_vektor_jackies_funeral`, `victor_ep__q307__two_years_later` |
| Misty | `Character.Misty` | `0xA22A7797, 15` | `misty_default`, `misty_dress`, `misty_underwear`, `misty_naked`, `misty_ep__q307__two_years_later` |
| Mama Welles (Guadalupe Alejandra Welles) | `Character.Mama_Welles` | `0xA12192C4, 21` | `gang__valentinos_wa__sq018__mama_welles`, `..._funeral` |
| Regina Jones | `Character.reggie` | `0x3A16C103, 16` | `service__fixer_wa__regina_jones` |
| Nix | `Character.Nix` | `0x44F307AA, 13` | `gang__cyberpunk_ma__q103__nix` |
| Wakako Okada | `Character.wakako_okada` | `0x6008CB00, 22` | (not queried — same DB, same method) |
| Wakako's Driver | `Character.ow_wakako_driver` | `0xF65C7373, 26` | — |
| Claire Russo | `Character.Claire` | `0x7EE3CE36, 16` | — |
| Voodoo Queen / Maman Brigitte | `Character.Voodoo_Queen` | `0x56A63E19, 22` | — |
| Saburo Arasaka | `Character.Saburo` | `0x62F914F8, 16` | — |
| Yorinobu Arasaka | `Character.Yorinobu` | `0x8D34B4F2, 18` | — |
| Judy | `Character.Judy` | `0xB1B50FFA, 14` | — |
| Panam | `Character.Panam` | `0xC67F0E01, 15` | — |
| Rogue | `Character.Rogue` | `0x73C44EBA, 15` | — |

**Method to verify any other name**: open `reference_mods/Appearance Menu Mod-790-.../.../db.sqlite3`
(read-only, never redistribute) and run
`sqlite3 db.sqlite3 "SELECT entity_id, entity_name, entity_path FROM entities WHERE entity_name LIKE '%NAME%'"`
then `SELECT app_name FROM appearances WHERE entity_id='<that id>'` for wardrobe names. Full method
and caveats already documented in `docs/research/amm_appearance_research.md`.

### How to actually spawn one — `spawnDynEntity()` (`init.lua:5226`)

```lua
local function spawnDynEntity(recordStr, pos, yawDeg, tag, appearance)
```
Builds a `DynamicEntitySpec` (record, appearanceName, position, orientation from yaw, `persistState
= false`, `persistSpawn = false`, `spawnInView = true`) and calls
`Game.GetDynamicEntitySystem():CreateEntity(spec)`. This is the native path (NOT AMM) the mod
already uses for Blaze's Goro/Smasher/kill-squad spawns — it's the one to reuse for any new NPC
spawn, since it needs no AMM dependency. Remember: **`CreateEntity` hands back a raw id, not a
resolved handle** (see the "Native spawn handle trap" project memory) — you still need your own
resolver loop (`Game.FindEntityByID`) before touching the entity.

---

## 4. Real-world Heywood/Jackie locations — verified vs. not

| Place | Verified coords? | Where |
|---|---|---|
| El Coyote Cojo (Mama Welles' bar) | **Yes** | `Config.locations.coyote`, 6 waypoints incl. arcade, upstairs table, railing, outside door + exitWaypoint |
| Vik's clinic (inside Misty's Esoterica) | **Yes** | `retrieval.lua:37` — separate capture from the `misty` venue capture (same building, ripperdoc chair vs. shop floor) |
| Misty's Esoterica (shop floor) | **Yes** | `Config.locations.misty`, 3 waypoints (anchor, near cats, deep chair) |
| Mama Welles' place | **Only the bar.** No separate "her apartment" capture exists — El Coyote Cojo IS her venue in this mod. | — |
| Jackie's apartment/home | **No.** Modeled only as `state = "unavailable"` with zero coordinates — he simply despawns for his "home" blocks. | `config.lua:3130` |
| The Afterlife | **Yes** | `Config.locations.afterlife`, 4 waypoints (entrance, alcove, dancers, bar) |
| Rocky Ridge | **Partially.** Two specific points captured — the hideout garage (`retrieval.lua:41`) and the Reverend Flash BD shack (`config.lua:982`) — but not "Rocky Ridge" broadly. | — |

---

## 5. Mappin / quest-marker helpers

No custom UI — the mod uses the game's own native map-pin system directly, twice, identically:

| Function | file:line | What it does |
|---|---|---|
| `placePin()` | `retrieval.lua:553` | Registers a `gamemappinsMappinData` (`Mappins.DefaultStaticMappin`, `gamedataMappinVariant.CustomPositionVariant`) at `M.Config.hideoutPos` via `Game.GetMappinSystem():RegisterMappin(data, pos)`. Stores the id in `state.mappinId`; no-ops if already placed or no `hideoutPos` configured. |
| `clearPin()` | `retrieval.lua:566` | `Game.GetMappinSystem():UnregisterMappin(state.mappinId)`, clears the stored id. |
| Dinner waypoint mappin | `init.lua:2896-2914` | Same exact pattern (`DefaultStaticMappin` + `CustomPositionVariant`) for the dinner-date venue pin, unregistered/re-registered on each dinner cycle. |

**Copy-paste recipe for a new quest marker:**
```lua
local data = NewObject("gamemappinsMappinData")
data.mappinType = TweakDBID.new("Mappins.DefaultStaticMappin")
data.variant    = gamedataMappinVariant.CustomPositionVariant
local id = Game.GetMappinSystem():RegisterMappin(data, pos)   -- pos = ToVector4{x=...,y=...,z=...,w=1.0}
-- later: Game.GetMappinSystem():UnregisterMappin(id)
```

---

## 6. Reusable "proximity objective" pattern

The retrieval questline's whole "get V to a place" detection is three small self-contained
primitives (no dependency on init.lua internals):

| Function | file:line | Signature / behavior |
|---|---|---|
| `playerPos()` | `retrieval.lua:266` | `Game.GetPlayer():GetWorldPosition()`, pcall-guarded, returns `nil` on failure. |
| `dist2(ax, ay, bx, by)` | `retrieval.lua:272` | Horizontal-only Euclidean distance (ignores Z — "forgiving outdoors", avoids failing a check because V is on a rooftop above the target). |
| `nearPoint(pt, radius)` | `retrieval.lua:277` | `pt` = `{x, y, z}` array (index 1/2, not `.x`/`.y`!). Returns `true` if V is within `radius` metres horizontally. Defaults `radius` to 4.0 if omitted. |

**Call-site pattern** (from `M.tick`, `retrieval.lua:822-831`): poll `nearPoint(spot, radius)` once
per tick inside the module's own `tick(dt)` (driven from `init.lua`'s `onUpdate`), gated by a
one-shot boolean (`state.vikFired`) so the trigger only fires once. This is the exact shape to reuse
for any new "reach location X" quest beat — including the `hourInBlock`/`getGameHour` combo from §2
if the beat also needs a time window ("only between 20:00 and 20:30").

---

## 7. What's MISSING — needs an in-game capture before it can be authored precisely

- **Jackie's own apartment/home interior.** Never captured; the schedule just despawns him for
  "home" blocks. Any "meet Jackie at his place" beat needs a fresh capture session.
- **Mama Welles' private residence**, if distinct from El Coyote Cojo (the mod currently treats the
  bar as her venue, full stop — no separate home).
- **Vik's actual ripperdoc *chair*** is captured (inside Misty's shop) but nothing beyond that one
  point — no waypoints around the clinic interior the way Misty's/Coyote's venues have.
- **Rocky Ridge beyond the two captured points** (hideout garage, BD shack) — no wider-area
  waypoints if a scene needs Jackie/V to move around the settlement.
- **The Afterlife's other rooms/floors** — only the 4 ground-level social spots are captured, not
  e.g. a private booth or the back office.
- **Ginger Panda and Redwood Market are captured but NOT in the daily schedule** — usable for a
  quest (a one-off, scripted appearance), but Jackie will never organically be there without a
  quest script placing him.
- **Character records for Vik/Misty/Mama Welles/Regina/Nix are confirmed to exist and spawn**, but
  none of their *dialogue*, quest hooks, or in-fiction schedules exist in this mod — spawning them
  is the easy 10%; giving them anything to say/do for a new questline is unbuilt.
- **No day-type is deterministic.** If a quest beat needs "Jackie is guaranteed at the noodle bar
  Tuesday at 09:00," the shuffle-bag schedule can't promise that without a program-level override
  (precedent: the Husbando Misty-retirement swap, `init.lua:1601-1609`).
