# Journal quests + readable shards — authoring spec

_Written 2026-08-25. Supersedes `docs/BLAZE_WOLVENKIT_OBJECTIVES.md` (WolvenKit-GUI plan, obsolete)
and the "one WolvenKit action" split at the bottom of `docs/research/shard_placement_research.md`._

**Every confidence tag in this doc means one of:**
- `VERIFIED-GAME` — read out of the shipped game on this Mac (decompiled scripts, or the vanilla
  `cooked_journal.journal` parsed with `small_cyberpunk_mods/TimedChoices/redlib.py`).
- `VERIFIED-SHIPPED` — the exact shape is in a mod that is published and known to work in game.
- `VERIFIED-REPO` — already works in our own NCLives archive pipeline.
- `INFERRED` — follows from the above but this exact composition has not been seen running.
- `UNKNOWN` — flagged, do not assume.

---

## 0. VERDICT (read this and nothing else if you're in a hurry)

| question | answer | confidence |
|---|---|---|
| Can a mod add a **brand-new tracked quest with ticking objectives** via an ArchiveXL-merged `.journal` + Lua, with **no `.questphase`**? | **Yes.** Every piece is a general journal API with no quest-graph coupling. | `INFERRED` (all four ingredients `VERIFIED`, the composition not yet seen in game) |
| Is the HUD tracker (top-right, with the chime) reachable from CET? | **Yes** — `journalManager:TrackEntry(objectiveHandle)`. Callable from Lua, shipped mods do it. | `VERIFIED-GAME` + `VERIFIED-SHIPPED` |
| Does **any** step need the WolvenKit **GUI**? | **No. Not one.** Hand-written CR2W-JSON → `WolvenKit.CLI convert deserialize` → `pack`. | `VERIFIED-REPO` (NCLives ships a hand-authored `.journal` exactly this way) |
| Shard verdict | **Fully text-authorable.** Item + action = TweakXL YAML; text = localization JSON; the readable entry = one `gameJournalOnscreen` in our `.journal`. | `VERIFIED-SHIPPED` (two independent shipped mods) |
| The one thing that is genuinely hard | **World placement of a physical shard case** (`.streamingsector`) and **quest map pins**. Both need a base-game anchor and are a separate project. Ship v1 with **no pins and no world prop**: give the shard from Lua, drive objectives from Lua. | `VERIFIED-SHIPPED` (documented failure modes, see §6) |

**Blaze of Glory can therefore get real HUD objectives without WolvenKit, without a quest graph, and
without map pins.** `blaze.lua`'s existing `pushObjective()` call sites do not change; only the two
helpers bound in `onInit` get repointed (§4.5).

---

## 1. The one Windows step, and the one repo edit it needs

`tools/build_archive.py` currently hard-codes two source kinds in `all_sources()` (line 90) and in
the pack loop (line 163), both shaped `<root>/<locale>/<stem>`. A `.journal` has **no locale
subfolder**, so it will be silently skipped. `VERIFIED-REPO` (read the file).

**Required edit before Antonia's build produces anything** (spec only — not applied by this doc):

```python
# near the top, beside VOMAP_SRC / ONSCREEN_SRC
JOURNAL_SRC = os.path.join(ARCH_SRC, "journal")

def flat_sources(root, stem):
    """A non-localized source: <root>/<stem>. Journals have no locale folder."""
    p = os.path.join(root, stem)
    return [("", p)] if os.path.isfile(p) else []

def all_sources():
    return locale_sources(VOMAP_SRC, "jackielives_vomap.json.json") + \
           locale_sources(ONSCREEN_SRC, "jackielives_onscreens.json.json") + \
           flat_sources(JOURNAL_SRC, "jackielives.journal.json")
```

and in the `[3/3]` pack loop, after the existing `for kind, root, stem in (...)` block:

```python
    for _loc, src in flat_sources(JOURNAL_SRC, "jackielives.journal.json"):
        dst = os.path.join(stage, "mod", "jackielives", "journal")
        os.makedirs(dst, exist_ok=True)
        shutil.copy(src[: -len(".json")], dst)   # drop the outer .json
```

Everything else about her build is unchanged: `python tools\build_archive.py` on Windows.

> ⚠️ **The `.json.json` convention is real, not a typo.** `WolvenKit.CLI convert deserialize
> foo.journal.json` writes `foo.journal` next to it. The onscreens sources in this repo are named
> `jackielives_onscreens.json.json` because the *resource* is `…onscreens.json`. A journal source is
> `jackielives.journal.json` → `jackielives.journal`. `VERIFIED-REPO`.

### `.xl` lines to add

`archive/pc/mod/JackieLives.archive.xl` — append at top level (sibling of `localization:`):

```yaml
journal:
  - mod\jackielives\journal\jackielives.journal
```

`journal:` **merges** into the base tree by id-path: existing containers are descended into, missing
entries appended. That is why a modded quest can live under the game's own `quests` folder without
replacing it, and why this cannot conflict with other journal mods.
`VERIFIED-REPO` (NCLives' `.xl` does exactly this) + `VERIFIED-SHIPPED` (ArchiveXL
`src/App/Extensions/Journal/Extension.cpp`, `EmplaceBack`).

`localization: onscreens: en-us:` already exists in our `.xl` and currently carries the
archive-presence beacon. Turn it into a **list** (ArchiveXL accepts a list per locale — NCLives
already relies on that) so the shard/quest strings go in a second file without disturbing the
beacon:

```yaml
localization:
  vomaps:
    en-us: mod\jackielives\vomaps\en-us\jackielives_vomap.json
  onscreens:
    en-us:
      - mod\jackielives\onscreens\en-us\jackielives_onscreens.json     # the beacon — do not remove
      - mod\jackielives\onscreens\en-us\jackielives_text.json          # NEW: quest + shard strings
```

`VERIFIED-REPO` (the list form is in `../NCLives/archive/pc/mod/NCLives.archive.xl`).

---

## 2. The CR2W-JSON envelope (identical for every file below)

```json
{
  "Header": {
    "WolvenKitVersion": "8.18.0",
    "WKitJsonVersion": "0.0.9",
    "GameVersion": 2310,
    "DataType": "CR2W",
    "ArchiveFileName": "jackielives.journal"
  },
  "Data": {
    "Version": 195,
    "BuildVersion": 0,
    "RootChunk": { "...": "see below" },
    "EmbeddedFiles": []
  }
}
```

`ArchiveFileName` is the file's **own name**, not a depot path — WolvenKit takes the folder from
where the JSON sits in the raw tree. `VERIFIED-REPO` + `VERIFIED-SHIPPED`.

### Primitive spellings — get these wrong and the file will not deserialize

| thing | JSON |
|---|---|
| handle wrapper | `{"HandleId": "<unique-in-file integer as string>", "Data": { ... }}` |
| CName | `{"$type": "CName", "$storage": "string", "$value": "None"}` |
| TweakDBID (null) | `{"$type": "TweakDBID", "$storage": "uint64", "$value": "0"}` |
| TweakDBID (set) | `{"$type": "TweakDBID", "$storage": "string", "$value": "Districts.Badlands"}` |
| NodeRef (null) | `{"$type": "NodeRef", "$storage": "uint64", "$value": "0"}` |
| LocalizationString | `{"unk1": "0", "value": "jl-obj-reach-hideout"}` |
| Vector3 | `{"$type": "Vector3", "X": 0.0, "Y": 0.0, "Z": 0.5}` |

`VERIFIED-SHIPPED` (`andreaolivato/cyberpunk-codes:tools/questkit/journal.py`).

> ⚠️ **`unk1` is an editor CRUID, not a hash. `"0"` is correct for a mod.** NCLives writes a real
> FNV-1a64 there; harmless, but unnecessary. `VERIFIED-SHIPPED`.
>
> ⚠️ **LocKeys in a journal are written BARE, with no `LocKey#` prefix** (`"value":
> "jl-shard-badlands-title"`). ArchiveXL converts any non-prefixed value to `LocKey#<FNV1a64>` and
> registers the localization entry under the same hash. A value that *does* start with `LocKey#` is
> assumed numeric and left alone — which is why the current
> `mod/JackieLives_shards/tweaks/.../jl_shards.yaml` (`displayName: LocKey#jl_shard_..._name`) would
> render raw on screen. `VERIFIED-SHIPPED` (AXL `Journal/Extension.cpp: ConvertLocKeys`).
>
> ⚠️ **HandleId must be unique within the file.** Any integers, in any order. Number them 0,1,2,…
> as you go.

---

## 3. (A) The quest tree — exact class shapes

### 3.1 What a vanilla quest actually looks like

Dumped live from `base\journal\cooked_journal.journal` in `basegame_4_gamedata.archive` on this Mac
(`redlib.py`, 4.79 MB, 47,478 exports). `VERIFIED-GAME`:

```
[9667] gameJournalQuest         id=mq049_edgerunners  title=LocKey#83940  type=MinorQuest
                                recommendedLevelID=121918464551  districtID=Districts.SantoDomingo
  [9668] gameJournalQuestDescription  id=desc  description=LocKey#83941
  [9669] gameJournalQuestPhase        id=01_el_captian
    [9670] gameJournalQuestObjective    id=01_text_capitan  description=LocKey#83942
      [9671] gameJournalQuestCodexLink    id=santo_domingo
    [9675] gameJournalQuestObjective    id=02_wait         description=LocKey#84034
  [9676] gameJournalQuestPhase        id=02_falco
    [9677] gameJournalQuestObjective    id=01_respond_to_falco
  [9678] gameJournalQuestPhase        id=03_gift
    [9679] gameJournalQuestObjective    id=02_pick_up_gift
      [9680] gameJournalQuestMapPin      id=mq049_mp_jacket
```

**There is no separate `gameJournalQuestGroup` class.** The containers are, in order:
`gameJournalRootFolderEntry` → `gameJournalPrimaryFolderEntry` (id `quests`) →
`gameJournalFolderEntry` (id `minor_quest` / `side_quest` / `street_stories` / …) →
`gameJournalQuest`. The nine primary folders in the vanilla root are exactly: `quests`,
`metaquests`, `codex`, `contacts`, `tarots`, `briefings`, `points_of_interest`, `onscreens`,
`internet_sites`. `VERIFIED-GAME`.

**The `uniquePath` you pass to `ChangeEntryState` is the id chain with no leading slash:**

```
quests/minor_quest/jl_retrieval
quests/minor_quest/jl_retrieval/phase_main
quests/minor_quest/jl_retrieval/phase_main/obj_reach_hideout
```

`VERIFIED-GAME` (the same rule, at `quests/minor_quest/mq049_edgerunners/03_gift/02_pick_up_gift`,
is what NCLives' jacket gate already reads successfully in a live game) + `VERIFIED-REPO`.

### 3.2 Field census across all 360 vanilla quests / 549 phases / 4,008 objectives

`VERIFIED-GAME` (counts are "how many of the N entries carry this property at all"; CR2W omits
defaults, so a missing property = the default):

| class | property | present | notes |
|---|---|---|---|
| `gameJournalQuest` | `id` | 360/360 | string |
| | `title` | 342/360 | LocalizationString |
| | `type` | 292/360 | enum `gameJournalQuestType` |
| | `districtID` | 258/360 | TweakDBID `Districts.*` |
| | `recommendedLevelID` | 280/360 | TweakDBID; `0` is fine |
| | `entries` | 341/360 | phases (+ optional `gameJournalQuestDescription`) |
| `gameJournalQuestPhase` | `id`, `entries` | 549/549 | `locationPrefabRef` on 118, optional |
| `gameJournalQuestObjective` | `id` | 4008/4008 | |
| | `description` | 3997/4008 | LocalizationString — **this is the tracker line** |
| | `entries` | 3831/4008 | map pins + codex links; may be `[]` |
| | `optional` | 304/4008 | `1` = the grey "(optional)" |
| | `counter` | 45/4008 | `n` = "0/n" style objective |
| | `districtID` | 1229/4008 | |
| `gameJournalQuestDescription` | `id`, `description` | 402/402 | the quest-log body text |

`gameJournalQuestType` enum values (`journalManager.script:140-152`, `VERIFIED-GAME`):
`MainQuest, SideQuest, MinorQuest, StreetStory, CyberPsycho, Contract, VehicleQuest, ApartmentQuest,
CourierQuest, CourierSideQuest`.

> ⚠️ **Pick a type or the quest presents as a main quest.** `VERIFIED-SHIPPED` (cyberpunk-codes
> gotcha 6). For Blaze/retrieval, `MinorQuest` or `SideQuest`; the HUD styles the title as
> `'Quest'` for MainQuest/SideQuest/CourierSideQuest/MinorQuest and `'Gigs'` for everything else
> (`quest_tracker.script:253-254`, `VERIFIED-GAME`).

### 3.3 Copy-pasteable skeleton — `archive/source/mod/jackielives/journal/jackielives.journal.json`

Placeholders are marked `<<LIKE THIS>>`. Replace **every** one; ids must be lowercase
`a-z0-9_`, LocKeys lowercase with hyphens and a `jl-` prefix (namespacing is not optional — see the
BowieKnife99 hash-collision crash noted in `../NCLives/docs/MESSAGES.md` §2).

```json
{
  "Header": {
    "WolvenKitVersion": "8.18.0",
    "WKitJsonVersion": "0.0.9",
    "GameVersion": 2310,
    "DataType": "CR2W",
    "ArchiveFileName": "jackielives.journal"
  },
  "Data": {
    "Version": 195,
    "BuildVersion": 0,
    "EmbeddedFiles": [],
    "RootChunk": {
      "$type": "gameJournalResource",
      "cookingPlatform": "PLATFORM_PC",
      "entry": {
        "HandleId": "0",
        "Data": {
          "$type": "gameJournalRootFolderEntry",
          "id": "",
          "journalEntryOverrideDataList": [],
          "entries": [
            {
              "HandleId": "1",
              "Data": {
                "$type": "gameJournalPrimaryFolderEntry",
                "id": "quests",
                "journalEntryOverrideDataList": [],
                "entries": [
                  {
                    "HandleId": "2",
                    "Data": {
                      "$type": "gameJournalFolderEntry",
                      "id": "minor_quest",
                      "journalEntryOverrideDataList": [],
                      "entries": [
                        {
                          "HandleId": "3",
                          "Data": {
                            "$type": "gameJournalQuest",
                            "id": "<<QUEST_ID e.g. jl_blaze_of_glory>>",
                            "title": { "unk1": "0", "value": "<<jl-blaze-title>>" },
                            "type": "MinorQuest",
                            "districtID": { "$type": "TweakDBID", "$storage": "string", "$value": "Districts.Watson" },
                            "recommendedLevelID": { "$type": "TweakDBID", "$storage": "uint64", "$value": "0" },
                            "journalEntryOverrideDataList": [],
                            "entries": [
                              {
                                "HandleId": "4",
                                "Data": {
                                  "$type": "gameJournalQuestDescription",
                                  "id": "desc",
                                  "description": { "unk1": "0", "value": "<<jl-blaze-desc>>" },
                                  "journalEntryOverrideDataList": []
                                }
                              },
                              {
                                "HandleId": "5",
                                "Data": {
                                  "$type": "gameJournalQuestPhase",
                                  "id": "phase_main",
                                  "locationPrefabRef": { "$type": "NodeRef", "$storage": "uint64", "$value": "0" },
                                  "journalEntryOverrideDataList": [],
                                  "entries": [
                                    {
                                      "HandleId": "6",
                                      "Data": {
                                        "$type": "gameJournalQuestObjective",
                                        "id": "<<obj_smasher>>",
                                        "description": { "unk1": "0", "value": "<<jl-obj-smasher>>" },
                                        "counter": 0,
                                        "optional": 0,
                                        "districtID": "",
                                        "itemID": { "$type": "TweakDBID", "$storage": "uint64", "$value": "0" },
                                        "locationPrefabRef": { "$type": "NodeRef", "$storage": "uint64", "$value": "0" },
                                        "journalEntryOverrideDataList": [],
                                        "entries": []
                                      }
                                    },
                                    {
                                      "HandleId": "7",
                                      "Data": {
                                        "$type": "gameJournalQuestObjective",
                                        "id": "<<obj_takemura>>",
                                        "description": { "unk1": "0", "value": "<<jl-obj-takemura>>" },
                                        "counter": 0,
                                        "optional": 0,
                                        "districtID": "",
                                        "itemID": { "$type": "TweakDBID", "$storage": "uint64", "$value": "0" },
                                        "locationPrefabRef": { "$type": "NodeRef", "$storage": "uint64", "$value": "0" },
                                        "journalEntryOverrideDataList": [],
                                        "entries": []
                                      }
                                    },
                                    {
                                      "HandleId": "8",
                                      "Data": {
                                        "$type": "gameJournalQuestObjective",
                                        "id": "<<obj_extract>>",
                                        "description": { "unk1": "0", "value": "<<jl-obj-extract>>" },
                                        "counter": 0,
                                        "optional": 0,
                                        "districtID": "",
                                        "itemID": { "$type": "TweakDBID", "$storage": "uint64", "$value": "0" },
                                        "locationPrefabRef": { "$type": "NodeRef", "$storage": "uint64", "$value": "0" },
                                        "journalEntryOverrideDataList": [],
                                        "entries": []
                                      }
                                    }
                                  ]
                                }
                              }
                            ]
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            },
            { "HandleId": "9", "Data": { "...": "the ONSCREENS primary folder from §5.2 goes here, as a sibling" } }
          ]
        }
      }
    }
  }
}
```

`VERIFIED-SHIPPED` — this is structurally the tree emitted by
`andreaolivato/cyberpunk-codes:tools/gig01/gen_journal.py`, which ships in a published gig, with
folder ids swapped from `street_stories` to `minor_quest` (both exist in vanilla, `VERIFIED-GAME`).

> ⚠️ **`journalEntryOverrideDataList: []` on every entry.** Present on every vanilla-shaped emitter.
> Omitting it has not been tested. `INFERRED` that it is required; include it, it costs nothing.
>
> ⚠️ **One phase, many objectives** is the right shape for us. Vanilla splits phases because the
> quest *graph* advances phase by phase; we have no graph, so a single `phase_main` keeps every
> `uniquePath` short and stable. `INFERRED`.

---

## 4. (A) The exact Lua

### 4.1 The API surface, cited

All in `scripts/core/systems/journalManager.script` (`CDPR-Modding-Documentation/Cyberpunk-Scripts`,
v2.3 branch). `VERIFIED-GAME`:

```
:411  GetEntryByString( uniquePath : String, className : String ) : weak<JournalEntry>
:412  GetEntryState( entry ) : gameJournalEntryState
:414  IsEntryVisited( entry ) : Bool
:418  GetTrackedEntry() : weak<JournalEntry>
:419  IsEntryTracked( entry ) : Bool
:420  TrackEntry( entry : weak<JournalEntry> )
:422  UntrackEntry()
:423  ChangeEntryState( uniquePath, className, state, notifyOption ) : Bool
:424  ChangeEntryStateByHash( hash : Uint32, state, notifyOption )
```

Enums (`scripts/cyberpunk/UI/quests/journalTypes.script:1-8, 30-35`, `VERIFIED-GAME`):
`gameJournalEntryState = { Undefined, Inactive, Active, Succeeded, Failed }`;
`JournalNotifyOption = { Undefined, DoNotNotify, Notify }`.

**There is NO `SetTrackedEntry`.** The setter is `TrackEntry`. There is also a
`SetScriptedQuestEntryState` / `CreateScriptedQuestFromTemplate` family at
`journalManager.script:440-470` — **do not use it**: the script bodies are `constexpr … return
false` / empty, i.e. it is inert in 2.3 and is only driven by `gameplayQuestSystem.script` for the
apartment/vehicle metaquest templates. `VERIFIED-GAME`.

### 4.2 What the HUD tracker actually requires

`scripts/cyberpunk/UI/quests/quest_tracker.script:231-290`, `VERIFIED-GAME`. In order:

1. `GetTrackedEntry()` must cast to `JournalQuestObjective` (`:234`) — **so the thing you Track is an
   OBJECTIVE, never the quest**.
2. Its parent must be a `JournalQuestPhase` and its grandparent a `JournalQuest` (`:237, :241`).
3. The container is shown only if `m_trackedQuest.GetTitle(...) != ""` (`:250`) — **an untitled quest
   renders nothing at all**, which is exactly the failure you'd see with a broken LocKey.
4. Phases are fetched with `filter.active = true` (`:231`), and objectives likewise — **so the quest,
   the phase AND the objective must each be in state `Active`** for a line to draw.
5. A new objective row is only spawned when `GetEntryState(objective) == Active` (`:278`).

`TrackQuestNotificationAction.Execute` (`notificationActions.script:23-49`) is CDPR's own pattern and
it does exactly what §4.3 does: `TrackEntry(quest)` then walk to the first active objective of the
first active phase and `TrackEntry` that. `VERIFIED-GAME`.

### 4.3 Copy-pasteable Lua (CET)

Drop this in a new `mod/JackieLives/journalquest.lua` module (**never** a new top-level `local` in
`init.lua` — 200-local cap).

```lua
-- journalquest.lua — drive our ArchiveXL-merged journal quest from Lua.
-- ⚠️ Enum arguments cross the CET boundary as PLAIN STRINGS ("Active", "Notify"). Never
--    gameJournalEntryState.Active — `_G[typename]` is nil in CET's sandbox.
-- ⚠️ Never call before a save is loaded: Game.GetJournalManager() is nil in the main menu.
JQ = {}

local QUEST = "quests/minor_quest/jl_blaze_of_glory"     -- <<QUEST_ID>>
local PHASE = QUEST .. "/phase_main"

local function jm()
  local m; pcall(function() m = Game.GetJournalManager() end)
  return m
end

-- state: "Inactive" | "Active" | "Succeeded" | "Failed"
-- notify: "Notify" (chime + "quest updated" banner) | "DoNotNotify"
function JQ.set(path, class, state, notify)
  local m = jm(); if not m then return false end
  local ok, res = pcall(function()
    return m:ChangeEntryState(path, class, state, notify or "DoNotNotify")
  end)
  return ok and res or false
end

function JQ.entry(path, class)
  local m = jm(); if not m then return nil end
  local e; pcall(function() e = m:GetEntryByString(path, class) end)
  return e
end

-- 1) START THE QUEST. Parents first, always: a child of an inactive parent is not
--    enumerated by GetChildren(filter.active), so the HUD would show nothing.
function JQ.start()
  JQ.set(QUEST, "gameJournalQuest",      "Active", "Notify")
  JQ.set(PHASE, "gameJournalQuestPhase", "Active", "DoNotNotify")
end

-- 2) ACTIVATE ONE OBJECTIVE (this is what puts a line in the top-right tracker)
function JQ.objective(id, notify)
  return JQ.set(PHASE .. "/" .. id, "gameJournalQuestObjective",
                "Active", notify or "Notify")
end

-- 3) TICK IT OFF (strikethrough + chime, then it fades from the tracker)
function JQ.succeed(id)
  return JQ.set(PHASE .. "/" .. id, "gameJournalQuestObjective", "Succeeded", "Notify")
end

function JQ.fail(id)
  return JQ.set(PHASE .. "/" .. id, "gameJournalQuestObjective", "Failed", "Notify")
end

-- 4) TRACK IT. Track the OBJECTIVE, not the quest — quest_tracker.script:234 casts
--    GetTrackedEntry() to JournalQuestObjective and gives up if it isn't one.
function JQ.track(id)
  local m = jm(); if not m then return false end
  local e = JQ.entry(PHASE .. "/" .. id, "gameJournalQuestObjective")
  if not e then return false end
  local ok = pcall(function() m:TrackEntry(e) end)
  return ok
end

-- Convenience: activate + track in one call. This is the normal "next objective" beat.
function JQ.push(id)
  JQ.objective(id, "Notify")
  return JQ.track(id)
end

-- 5) FINISH. Succeed the last objective, then the phase, then the quest.
function JQ.finish(lastObjectiveId)
  if lastObjectiveId then JQ.succeed(lastObjectiveId) end
  JQ.set(PHASE, "gameJournalQuestPhase", "Succeeded", "DoNotNotify")
  JQ.set(QUEST, "gameJournalQuest",      "Succeeded", "Notify")
end

-- 6) READ BACK (for probes / the log). GetEntryState returns either the enum NAME
--    or its ORDINAL depending on the CET build — normalise, as messages.lua does.
function JQ.state(path, class)
  local m = jm(); if not m then return "no-journal-manager" end
  local e = JQ.entry(path, class); if not e then return "no-entry" end
  local s; pcall(function() s = m:GetEntryState(e) end)
  if type(s) == "number" then
    return ({ [0]="Undefined", [1]="Inactive", [2]="Active", [3]="Succeeded", [4]="Failed" })[s]
        or tostring(s)
  end
  return tostring(s)
end

return JQ
```

`VERIFIED-REPO` for the `pcall`/string-enum/`GetEntryState`-normalisation idioms (lifted from
`../NCLives/mod/NCLives/messages.lua:136-175`, which runs in a shipped game).
`VERIFIED-SHIPPED` for `journalManager:TrackEntry(objective)` and
`Game.GetJournalManager():GetEntryByString(path, class)` from CET Lua — CyberScript Core does both
(`cyberscript77/release:…/modules/observers/quest.lua:236, :313`).
`INFERRED` that `ChangeEntryState` accepts `"gameJournalQuest"` / `"gameJournalQuestPhase"` /
`"gameJournalQuestObjective"` as `className` — the parameter is a free string and the engine's own UI
code changes quest-child states this way (`questLogDetailsPanel.script:236`), but we have not run it.

### 4.4 Probe to run FIRST, in-game, before writing any content

Per Antonia's testing rule (probes in the mod, writing to the log — no console pasting):

```lua
-- one debug button, prints a verdict line to jackie_debug.log
function JQ.probe()
  local out = {}
  out[#out+1] = "quest  : " .. JQ.state(QUEST, "gameJournalQuest")
  out[#out+1] = "phase  : " .. JQ.state(PHASE, "gameJournalQuestPhase")
  JQ.start()
  JQ.push("obj_smasher")                    -- <<first objective id>>
  local m = jm()
  local tracked = m and m:GetTrackedEntry() or nil
  out[#out+1] = "after start/push -> quest=" .. JQ.state(QUEST, "gameJournalQuest")
             .. " phase=" .. JQ.state(PHASE, "gameJournalQuestPhase")
             .. " obj=" .. JQ.state(PHASE .. "/obj_smasher", "gameJournalQuestObjective")
             .. " tracked=" .. tostring(tracked ~= nil)
  return table.concat(out, " | ")
end
```

**Pass = the log says `quest=Active phase=Active obj=Active tracked=true` AND the top-right HUD shows
the quest title with one objective line.** If the states are Active but the HUD is empty, the
suspect is the title LocKey (`quest_tracker.script:250`), not the API.

### 4.5 What changes in `blaze.lua` / `init.lua`

Nothing in `blaze.lua`. Only the two helpers bound in `onInit` (per
`docs/BLAZE_WOLVENKIT_OBJECTIVES.md` Part 2):

```lua
objective = function(text, dur)
  -- text is now IGNORED for the HUD (the wording lives in the journal LocKey);
  -- keep the message band as a belt-and-braces fallback if JQ.push fails.
  if not JQ.push(Blaze.objectiveIds[text]) then showOnscreenMsg(text, dur or 8.0) end
end,
```

i.e. a lookup table from the existing English strings to objective ids, and a fall-through to the
current message band whenever the journal is missing (archive not installed, ArchiveXL absent). That
fall-through is the whole degradation story: **no archive → the mod behaves exactly as it does
today**, never worse. `INFERRED`.

---

## 5. (B) The readable shard

### 5.1 A shard is four independent things

| | what it is | where it lives | needs WolvenKit GUI? |
|---|---|---|---|
| the TEXT | a `gameJournalOnscreen` entry | our `.journal` | **no** — hand-written JSON |
| the WORDS | a `localizationPersistenceOnScreenEntry` | our onscreens JSON | **no** |
| the ITEM | `gamedataItem_Record` + `gamedataItemAction_Record` | `r6/tweaks/**.yaml` (loose, no archive at all) | **no** |
| the OBJECT | a named node in a `.streamingsector` | our archive | **not needed for v1 — skip it, see §6** |

`VERIFIED-SHIPPED` (`andreaolivato/cyberpunk-codes:docs/shard-playbook.md`).

### 5.2 The journal onscreen entry

Vanilla puts collectible shards at `onscreens/emails/generic/shards/<group>/<id>` and quest shards at
`onscreens/emails/quests/<questfolder>/<quest>/<group>/<id>`. Folder classes, `VERIFIED-GAME`
(read out of `cooked_journal.journal`):

```
onscreens          gameJournalPrimaryFolderEntry
  emails           gameJournalFolderEntry
    quests         gameJournalFolderEntry
      minor_quest  gameJournalFolderEntry
        jl_shards  gameJournalFolderEntry
          shards   gameJournalOnscreenGroup      <- the leaf GROUP, a different class
            <id>   gameJournalOnscreen           <- title / description / tag
```

**Canonical path for our tester shard** (replaces the invented
`onscreens/emails/quests/minor_quest/new_shards/shards/…` in the current
`mod/JackieLives_shards/` files):

```
onscreens/emails/quests/minor_quest/jl_shards/shards/jl_shard_badlands_note
```

Sibling of the `quests` primary folder, inside the same `jackielives.journal.json`:

```json
{
  "HandleId": "9",
  "Data": {
    "$type": "gameJournalPrimaryFolderEntry",
    "id": "onscreens",
    "journalEntryOverrideDataList": [],
    "entries": [{
      "HandleId": "10",
      "Data": {
        "$type": "gameJournalFolderEntry",
        "id": "emails",
        "journalEntryOverrideDataList": [],
        "entries": [{
          "HandleId": "11",
          "Data": {
            "$type": "gameJournalFolderEntry",
            "id": "quests",
            "journalEntryOverrideDataList": [],
            "entries": [{
              "HandleId": "12",
              "Data": {
                "$type": "gameJournalFolderEntry",
                "id": "minor_quest",
                "journalEntryOverrideDataList": [],
                "entries": [{
                  "HandleId": "13",
                  "Data": {
                    "$type": "gameJournalFolderEntry",
                    "id": "jl_shards",
                    "journalEntryOverrideDataList": [],
                    "entries": [{
                      "HandleId": "14",
                      "Data": {
                        "$type": "gameJournalOnscreenGroup",
                        "id": "shards",
                        "journalEntryOverrideDataList": [],
                        "entries": [{
                          "HandleId": "15",
                          "Data": {
                            "$type": "gameJournalOnscreen",
                            "id": "<<jl_shard_badlands_note>>",
                            "title":       { "unk1": "0", "value": "<<jl-shard-badlands-title>>" },
                            "description": { "unk1": "0", "value": "<<jl-shard-badlands-body>>" },
                            "tag": { "$type": "CName", "$storage": "string", "$value": "None" },
                            "iconID": { "$type": "TweakDBID", "$storage": "uint64", "$value": "0" },
                            "journalEntryOverrideDataList": []
                          }
                        }]
                      }
                    }]
                  }
                }]
              }
            }]
          }
        }]
      }
    }]
  }
}
```

> ⚠️ **`tag`.** Only 376 of 1,398 vanilla onscreens carry one (`notes` 107, `articles` 56,
> `cyberpsycho` 39, `world` 38, `others` 33, `literature_fiction` 26 …) and every one of them is a
> **generic collectible** under `onscreens/emails/generic/shards`. Quest shards use `None`.
> `VERIFIED-GAME`. The old SHARD_SHEET's `tag: articles` would file Jackie's note under the
> collectible-articles Codex category — wrong shelf, not fatal.
>
> ⚠️ **Real newlines are the line breaks** in the description string (JSON `\n`). `VERIFIED-SHIPPED`.

### 5.3 The localization entries

New file `archive/source/mod/jackielives/onscreens/en-us/jackielives_text.json.json` (the second
entry in the `.xl` list from §1). Same envelope, `ArchiveFileName: "jackielives_text.json"`:

```json
"RootChunk": {
  "$type": "JsonResource",
  "cookingPlatform": "PLATFORM_PC",
  "root": { "HandleId": "0", "Data": {
    "$type": "localizationPersistenceOnScreenEntries",
    "entries": [
      { "$type": "localizationPersistenceOnScreenEntry",
        "femaleVariant": "Shard — Jackie Welles", "maleVariant": "",
        "primaryKey": "0", "secondaryKey": "jl-shard-badlands-title" },
      { "$type": "localizationPersistenceOnScreenEntry",
        "femaleVariant": "If you're readin' this, V, then the doc kept his word...\n\n...— Jackie",
        "maleVariant": "", "primaryKey": "0", "secondaryKey": "jl-shard-badlands-body" },
      { "$type": "localizationPersistenceOnScreenEntry",
        "femaleVariant": "Shard: Jackie Welles", "maleVariant": "",
        "primaryKey": "0", "secondaryKey": "jl-shard-badlands-item" },
      { "$type": "localizationPersistenceOnScreenEntry",
        "femaleVariant": "A message left for you.", "maleVariant": "",
        "primaryKey": "0", "secondaryKey": "jl-shard-badlands-item-desc" },
      { "$type": "localizationPersistenceOnScreenEntry",
        "femaleVariant": "Blaze of Glory", "maleVariant": "",
        "primaryKey": "0", "secondaryKey": "jl-blaze-title" },
      { "$type": "localizationPersistenceOnScreenEntry",
        "femaleVariant": "Kill Adam Smasher", "maleVariant": "",
        "primaryKey": "0", "secondaryKey": "jl-obj-smasher" }
    ]
  }}
}
```

`primaryKey: "0"` + a **bare** `secondaryKey` is what a shipped mod uses; ArchiveXL hashes the
secondary key and that hash is what the journal's converted LocKey resolves against.
`VERIFIED-SHIPPED` (`questkit/localization.py`). `maleVariant: ""` falls back to the female variant,
so a non-gendered line is written once. `VERIFIED-SHIPPED`.

> ⚠️ Our existing `mod/JackieLives_shards/localization/jl_shards.json` is **not** in this shape: it
> has no `Header`/`Data` envelope and uses `primaryKey: 0` (number, not string) with underscore keys
> that the YAML references as `LocKey#…`. Rewrite it into the file above; the *prose* in it is good
> and should be carried across verbatim.

### 5.4 The TweakXL YAML

Two published mods do this two different ways; **both work**. Deploys **loose** to
`<game>\r6\tweaks\JackieLives\jl_shards.yaml` — no archive, no WolvenKit, no rebuild.

**Form A — fully explicit, no `$base` (safest; this exact record ships in Kidnap Quest, Nexus 17329):**
`VERIFIED-SHIPPED`

```yaml
Items.jl_shard_badlands_note:
  $type: gamedataItem_Record
  animFeatureName: ItemData
  itemType: ItemType.Gen_Readable
  itemSecondaryAction: Items.jl_shard_badlands_note_inline0
  canDrop: True
  dropObject: defaultItemDrop
  objectActions:
    - ItemAction.Drop
    - ItemAction.Disassemble
  tags:
    - Readable
    - Shard
    - SkipActivityLog
    - HideInBackpackUI
    - HideAtVendor

Items.jl_shard_badlands_note_inline0:
  $type: gamedataItemAction_Record
  actionName: Read
  hackCategory: HackCategory.DeviceHack
  objectActionType: ObjectActionType.Item
  journalEntry: onscreens/emails/quests/minor_quest/jl_shards/shards/jl_shard_badlands_note
```

**Form B — `$base` on the game's plain shard (shorter, gives you an inventory name):**
`VERIFIED-SHIPPED` (cyberpunk-codes gig 01), `INFERRED` that `Items.Shard1` exists in *our* 2.3 build
— we cannot read `r6/cache/tweakdb.bin` on the Mac, so **if Form B fails with "unknown base record",
fall back to Form A**.

```yaml
ObjectAction.jl_shard_badlands_read:
  $base: Items.generic_hanako_flowers_shard_inline0
  journalEntry: onscreens/emails/quests/minor_quest/jl_shards/shards/jl_shard_badlands_note

Items.jl_shard_badlands_note:
  $base: Items.Shard1
  displayName: jl-shard-badlands-item
  localizedDescription: jl-shard-badlands-item-desc
  itemSecondaryAction: ObjectAction.jl_shard_badlands_read
```

**Four things that are not guessable and that our current YAML gets wrong:** `VERIFIED-SHIPPED`

1. **`itemSecondaryAction` is the line the whole thing hangs off.** It names the action record whose
   `journalEntry` flat is the onscreen path. All 335 vanilla shards are built this way.
2. **`objectActions` is a different property and is NOT the read action.** The vanilla shard's is
   `[Drop, Disassemble]`. Overriding it silently costs the player Disassemble and buys nothing.
3. **The title the player sees — loot line under the crosshair AND scanner panel — is the JOURNAL
   ENTRY's title, not the item's `displayName`.** The vanilla shard's displayName is empty and it
   still shows a title. `displayName`/`localizedDescription` only affect the inventory row.
4. **`displayName` takes a BARE ArchiveXL key** (`jl-shard-badlands-item`), never `LocKey#<name>`.
   A `LocKey#` prefix on a non-numeric key renders raw. Our current file has this bug.
5. **Never `$base` a shard that already has a story** (e.g. `generic_hanako_flowers_shard`): a
   `$base` clone inherits every inline child still pointing at the base's content, so you ship a
   record that applies in full and shows somebody else's note. (Basing the *ObjectAction* on
   `…_inline0` in Form B is fine — that record has no children.)

Also drop `entityName: w_data_shard` and `removeAfterUse: False` from the current file: neither is
in either shipped recipe, and `removeAfterUse` is not a field on `gamedataItemAction_Record` in
either. `INFERRED`.

### 5.5 Giving the shard from Lua

The mod currently gives **no** items (`grep AddItem|GiveItem|ItemID.FromTDBID mod/JackieLives/*.lua`
→ only `init.lua:9061` `ts:RemoveItem(...)` for `B.keyItem`). `VERIFIED-REPO`. So the give call is
new. The `RemoveItem` line already proves the idiom works in this codebase:

```lua
-- Put the shard in V's inventory (Shards tab). Idempotent-ish: check first.
function JQ.giveShard()
  local ts, p = Game.GetTransactionSystem(), Game.GetPlayer()
  if not (ts and p) then return false end
  local id = ItemID.FromTDBID(TweakDBID.new("Items.jl_shard_badlands_note"))
  local have = false
  pcall(function() have = ts:HasItem(p, id) end)
  if have then return true end
  local ok = pcall(function() ts:GiveItem(p, id, 1) end)
  return ok
end
```

Console equivalent for a quick check: `Game.AddToInventory("Items.jl_shard_badlands_note", 1)`.

**No-item fallback — put the note in the Codex with zero TweakDB at all.** `ReadAction` is four
lines (`scripts/cyberpunk/items/actions/readAction.script:13`, `VERIFIED-GAME`) and the essential one
is a plain `ChangeEntryState`. So:

```lua
-- Makes the shard readable in the Codex/Shards list with NO item and NO tweak record.
function JQ.unlockShard(path)
  return JQ.set(path, "gameJournalOnscreen", "Active", "Notify")
end
```

That is the whole mechanism the game itself uses; the item only exists so the player can *pick it
up*. `VERIFIED-GAME`.

### 5.6 Knowing when it's been read

`VERIFIED-SHIPPED` — two paths, and you need both if a quest step waits on it:

- **Read in place with [R]** → `PopupsManager.OnShardReadClosed` fires (redscript wrap only).
- **Taken with [F] and read from the backpack** → that callback does **not** fire.
- Ask the journal instead: `m:IsEntryVisited(JQ.entry(path, "gameJournalOnscreen"))`.
- **Use `IsEntryVisited`, NOT `Active`** — an entry goes `Active` when the shard is merely **picked
  up**, so a state check completes the objective for a player who took it and read nothing.
- Both signals fire when the reader **OPENS**, not when it closes, and the popup pauses the game —
  so let **two** ticks pass before acting on it, or the next VO line plays under the popup.

---

## 6. What we are deliberately NOT doing in v1, and why

| dropped | why | confidence |
|---|---|---|
| **Quest map pins** (`gameJournalQuestMapPin`) | Need a base-game NodeRef anchor in one of the three `always_loaded_*` sectors plus an exact offset vector, because ArchiveXL computes `GetNodeTransform(anchor) + offset` and a quest activates its pins while V is across the city. Custom marker nodes in a mod sector **never resolve**. Also: **a pin cannot be un-shown** — setting it Inactive leaves the marker. | `VERIFIED-SHIPPED` |
| **A physical shard case in the world** (`.streamingsector`) | ArchiveXL cannot ADD nodes to a shipped sector, so it means shipping our own; the node must carry a full `$/03_night_city/...` `QuestPrefabRefHash` (an **unnamed node does not load at all**) and its 53-field `ShardCaseContainer` instance data lifted whole off a vanilla sector. This is the real work in the shard feature. | `VERIFIED-SHIPPED` |
| **World-spawn via `DynamicEntitySystem.CreateEntity` / a bespoke `.ent`** | The entity attaches and never renders; a hand-built interactable raises no loot prompt. `exEntitySpawner.Spawn` (Codeware) is the one that works **from Lua** — that is Route 1 in `shard_placement_research.md`, still available as the zero-archive fallback. | `VERIFIED-SHIPPED` |
| **A `.questphase` graph** | We don't need it (§0) and a graph is where our familiarity/venue/time logic cannot reach — the same reasoning that kept NCLives' SMS scheduling in Lua. | `VERIFIED-REPO` |

---

## 7. Build order for tonight

1. Write `archive/source/mod/jackielives/journal/jackielives.journal.json` (§3.3 + §5.2 as siblings
   under one root folder entry). One file, both features.
2. Write `archive/source/mod/jackielives/onscreens/en-us/jackielives_text.json.json` (§5.3).
3. Add the two `.xl` blocks (§1).
4. Patch `tools/build_archive.py` (§1) — ~10 lines.
5. Rewrite `mod/JackieLives_shards/tweaks/JackieLives/jl_shards.yaml` to Form A (§5.4) and fix the
   `journalEntry` path; retire `SHARD_SHEET.md`'s WolvenKit-GUI procedure (§0).
6. Add `mod/JackieLives/journalquest.lua` (§4.3) + one debug button calling `JQ.probe()` (§4.4).
7. Windows: `python tools\build_archive.py`, copy the tweaks YAML to `r6\tweaks\JackieLives\`,
   load a save, press the probe button, read `jackie_debug.log`.

**Validate the JSON on the Mac before committing** — `python3 -c "import json;
json.load(open('...'))"` catches a trailing comma; `tools/check_ent_json.py` in NCLives is the
precedent for validating CR2W-JSON locally.

## 8. Residual unknowns — the honest list

1. **`UNKNOWN`: whether a journal-merged quest driven ONLY by `ChangeEntryState` (no quest graph)
   renders in the HUD tracker and the quest log.** Every ingredient is verified separately; the
   composition is not. §4.4's probe answers it in one load. This is the single risk in (A).
2. **`UNKNOWN`: whether `Items.Shard1` exists in our 2.3 build.** `r6/cache/tweakdb.bin` is not
   readable with our Mac tooling. Form A (§5.4) sidesteps it entirely.
3. **`UNKNOWN`: does ArchiveXL's journal merge accept a `quests` subtree the same way it accepts
   `contacts`?** A shipped gig merges `quests/street_stories/<id>` this way, so this is very close to
   `VERIFIED-SHIPPED`, but that mod also ships a `.questphase`, so its journal was never exercised
   without one.
4. **`UNKNOWN`: does the quest survive a save/reload?** Journal entry states are persisted game state
   (the vanilla quest log survives reloads), so `INFERRED` yes — but our re-arm on load should be
   idempotent regardless: re-run `JQ.start()` + `JQ.push(currentObjectiveId)` on every `onInit`,
   exactly the way the message scheduler re-arms.

## 9. Sources

- **Vanilla `base\journal\cooked_journal.journal`**, parsed live on this Mac out of
  `basegame_4_gamedata.archive` with `small_cyberpunk_mods/TimedChoices/redlib.py` — the field
  census in §3.2, the folder classes in §3.1/§5.2, the shard-path survey in §5.2.
- **Decompiled scripts** (`CDPR-Modding-Documentation/Cyberpunk-Scripts`, v2.3):
  `scripts/core/systems/journalManager.script:394-470`,
  `scripts/cyberpunk/UI/quests/journalTypes.script:1-35`,
  `scripts/cyberpunk/UI/quests/quest_tracker.script:231-290`,
  `scripts/cyberpunk/UI/wrappers/journal_wrapper.script:123-140`,
  `scripts/cyberpunk/UI/fullscreen/notification/notificationActions.script:16-52`,
  `scripts/cyberpunk/items/actions/readAction.script:1-25`.
- **`andreaolivato/cyberpunk-codes`** — `docs/journal-research.md`, `docs/shard-playbook.md`,
  `docs/gotchas.md` (1, 2, 5, 6, 25), `tools/questkit/journal.py`, `tools/questkit/localization.py`,
  `tools/gig01/gen_journal.py`, `mods/gig-01-negative-balance/source/tweaks/shard.yaml`.
- **`rfuzzo/cyberpunk-nexus-script-dump`** — `mods/17329/kidnap_quest/r6/tweaks/Kidnap/kidnap.yaml`
  (Form A), `mods/6475/CyberScript Core/.../QuestJournalUI.lua` (`TrackEntry` from Lua).
- **Our own repos** — `../NCLives/docs/MESSAGES.md`,
  `../NCLives/archive/source/mod/nclives/journal/nclives_messages.journal.json`,
  `../NCLives/mod/NCLives/messages.lua:136-175`,
  `../NCLives/archive/pc/mod/NCLives.archive.xl`, `tools/build_archive.py`.

---

# Handoff — changes owed to `build_archive.py` and the `.xl`

_Appended 2026-08-25 by the implementation pass. The feature is built and its offline harnesses
pass; these are the two files the implementer did not own, and the feature cannot reach the game
until the `.xl` item below is applied._

## 1. `tools/build_archive.py` — **nothing required.** One optional improvement.

§1 of this spec is **out of date**: it describes a version of `build_archive.py` that hard-coded
two `<root>/<locale>/<stem>` source kinds. That file has since been rewritten (v1.92): `all_sources()`
now *discovers* everything under `archive/source/mod/jackielives/`, detects flat vs. localized per
kind, and the `[3/3]` pack loop mirrors the source tree into the staging tree. Verified on the Mac —
it already reports both new sources:

```
journal   |       | journal/jackielives_quests.journal.json
questtext | en-us | questtext/en-us/jackielives_questtext.json.json
questtext | ja-jp | questtext/ja-jp/jackielives_questtext.json.json
```

So `flat_sources` / `JOURNAL_SRC` / the pack-loop addition in §1 must **not** be applied — they
would re-introduce the hand-maintained list the rewrite deleted.

**Optional (recommended) — a staleness guard.** `[0/3]` regenerates the SMS sources before packing,
so "I edited the words and rebuilt" is true for SMS. The quest/shard sources have no such guard, and
they are generated by `tools/gen_journal_quests.py`, which needs a **Lua interpreter** to read the
storyboard and therefore may not be runnable on the Windows box. So do not *run* it there — *check*
it, non-fatally:

```python
GEN_JOURNAL = os.path.join(HERE, "gen_journal_quests.py")
...
    # after the GEN_MESSAGES block in main()
    if os.path.isfile(GEN_JOURNAL):
        # --check needs a Lua interpreter (it reads storyboard.lua with the real one). If this box
        # hasn't got one it prints a note and we carry on: the committed sources are authoritative,
        # and a false alarm here must never block a build.
        r = subprocess.run([sys.executable, GEN_JOURNAL, "--check"])
        if r.returncode != 0:
            print("      WARN: quest/shard sources may be out of date. On the Mac run:")
            print("            python3 tools/gen_journal_quests.py    (then commit and pull here)")
```

## 2. `archive/pc/mod/JackieLives.archive.xl` — **required**, two edits

Without these the archive is built and merged but contains nothing the game will look at: the probe
in `docs/research/journal_probe.md` will report `archive=false` and the feature is untestable.

**(a) Add the quest journal to the existing `journal:` list** (it is already a list, so this is one
line):

```yaml
journal:
  - mod\jackielives\journal\jackielives_messages.journal
  - mod\jackielives\journal\jackielives_quests.journal      # NEW: tracked quest objectives + shard entries
```

`journal:` MERGES by id-path, so our `quests/side_quest/…` and `onscreens/emails/…` branches are
appended into the game's own tree without replacing anything, and cannot conflict with another
journal mod.

**(b) Add the quest/shard TEXT to `localization: onscreens:`, one line per locale:**

```yaml
  onscreens:
    en-us:
      - mod\jackielives\onscreens\en-us\jackielives_onscreens.json   # the vomap beacon — DO NOT REMOVE
      - mod\jackielives\onscreens\en-us\jackielives_msgs.json        # the SMS text
      - mod\jackielives\questtext\en-us\jackielives_questtext.json   # NEW: quest titles, objective lines, shard bodies
    ja-jp:
      - mod\jackielives\onscreens\ja-jp\jackielives_msgs.json
      - mod\jackielives\questtext\ja-jp\jackielives_questtext.json   # NEW
```

> ⚠️ **The folder is `questtext\`, not `onscreens\`, and that is deliberate** — the same reasoning
> the `.xl` already spells out for `jackielives_msgs.json`: a generator writing into the
> `onscreens\` folder is one filename collision away from silently overwriting
> `jackielives_onscreens.json`, the vomap beacon, which reads in game as a *voice* bug. A separate
> folder makes that collision impossible. The ArchiveXL key `onscreens:` names the resource TYPE;
> the depot path under it is free.

> ⚠️ `ja-jp` currently has **3 of 33** strings translated (the one pre-existing shard, carried
> across verbatim). The rest fall back to English by design — see `tools/journal_text/ja-jp.txt`.
> Shipping it half-done is safe; a blank record falls back, it never renders empty.

## 3. Corrections to this spec found during implementation

1. **§1 is obsolete** (above). `build_archive.py` needs no patch.
2. **§5.3 puts the new localization file in `onscreens/en-us/`.** Don't — see the folder-collision
   warning above. It is in `questtext/<locale>/`.
3. **`unk1: "0"` vs. the real hash.** §2 says `"0"` is correct for a mod and that NCLives' FNV-1a64
   is unnecessary. The implementation writes the **hash**, matching NCLives, because that is the
   form we have actually seen render in a shipped game; `"0"` is `INFERRED` only. Both are believed
   to work.
4. **§3.3's objective skeleton has `"districtID": ""`** — a bare string where the quest-level field
   is a TweakDBID struct. That looked like a deserialization failure waiting to happen, so the
   generator **omits** `districtID`, `itemID` and `counter`/`optional` when they are at their
   defaults (CR2W omits defaults; 1229/4008 vanilla objectives carry a district, so it is optional).
   `districtID` is omitted at quest level too: an unverifiable `Districts.*` TweakDBID is risk for
   no visible gain, since we ship no map pins.
5. **§4.3's module is a global `JQ = {}`.** Shipped as a normal module returning `M`, required into
   the global `JQuest` — `JQ` collides with nothing today but the three-engine repos share this
   file shape and a two-letter global is a bad neighbour.
6. **`quests/minor_quest` vs `quests/side_quest`.** The spec assumes one folder. "Ghost in the
   Machine" is a five-part story and is filed under `side_quest` as a `SideQuest`; the Heywood jobs
   are `minor_quest`/`MinorQuest`. Both folders are vanilla.
7. **The tester shard's canonical path in §5.2 is right, but the shard set is bigger than the spec
   assumed**: the storyboard declares three (`arc_scan`, `arc_vik_taps`, `arc_mama_note`) and the
   retrieval questline's `jl_shard_badlands_note` makes four. All four are generated.
