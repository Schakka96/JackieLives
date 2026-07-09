# CET API — scene / music / combat teardown (verified 2026-07-08)

Verified against decompiled 2.x game scripts (`CDPR-Modding-Documentation/Cyberpunk-Scripts`), the
NativeDB RTTI dump (`striderxfossility/NativeDB`), and a shipping fast-travel mod. Used by the Blaze
finale's "escape the scene" teardown (`init.lua` `blazeFinaleTeardown` and friends). In CET,
`Game.GetX()` == RTTI static `GameInstance.GetX(gi)`; `SomeClass.new()` constructs a scripted class/struct.

## 1. End the active quest `.scene`
- `Game.GetSceneSystem()` → `scnISceneSystem` **is** reachable.
- **No scripted per-scene abort exists** (`scnSceneSystem`/`scnISceneSystem`/`gameISceneSystem` expose no
  Stop/Kill/Abort — teardown is native, quest-graph-driven).
- Only script handle on a running scene = **fast-forward** (what skip-cutscene uses):
  ```lua
  local si = Game.GetSceneSystem():GetScriptInterface()
  si:FastForwardingActivate(scnFastForwardMode.Default)   -- Default=0, GameplayReview=1
  si:FastForwardingDeactivate()                           -- must turn it back off, or the NEXT scene runs fast
  ```
  Confidence: high that no abort exists; medium that FF cleanly ends a given bed.
  ⚠️ Fast-forwarding a LIVE story scene can let the quest graph advance — for Blaze that risks the
  `q005_09_no_tell_motel` death/Johnny tail. Watch for it; `Blaze.cfg.endSceneOnFinale=false` disables.

## 2. Fast-travel LOAD (full world teardown → guaranteed music/scene kill)
- Reachable, but **only to registered fast-travel POINTS, not arbitrary XYZ** (`FastTravelPointData` =
  `pointRecord:TweakDBID` + `markerRef:NodeRef` + `isEP1:Bool` — no position vector). So it can't land
  exactly at a custom coord like El Coyote.
  ```lua
  local ft = Game.GetScriptableSystemsContainer():Get("FastTravelSystem")
  FastTravelSystem.RemoveFastTravelLock("InCombat", Game.GetPlayer():GetGame())  -- FT is locked in combat
  local req = PerformFastTravelRequest.new()
  req.pointData = pd            -- a valid FastTravelPointData
  req.player    = Game.GetPlayer()
  ft:QueueRequest(req)          -- fires the real loading screen
  ```
- Getting `pd`: read `FastTravelSystem.m_fastTravelNodes` via reflection, OR capture live with
  `Observe("FastTravelSystem","OnPerformFastTravelRequest", ...)`, OR build one with
  `pd.pointRecord = TweakDBID.new("FastTravel.<point>")` + its `markerRef`.

## 3. Stop / reset music
`Game.GetAudioSystem()` (`gameGameAudioSystem`) verified methods:
```
Play(event:CName, id:EntityID, emitter:CName) · Stop(event:CName, id:EntityID, emitter:CName)
Switch(group:CName, value:CName, id:EntityID, emitter:CName) · Parameter(name:CName, val:Float, id, emitter)
GlobalParameter(name:CName, val:Float) · NotifyGameTone(event:CName) · State(group:String, state:String)
RequestSongOnRadioStation(station:CName, song:CName) · HandleCombatMix(player) · HandleOutOfCombatMix(player)
```
- **No universal "music off" state.** Combat/tension music is driven by **game tones**, not a flippable
  state group. Kill combat music by replaying the game's own combat-exit routine:
  ```lua
  local a = Game.GetAudioSystem()
  a:NotifyGameTone("LeaveCombat")          -- the tone fired on combat exit
  a:HandleOutOfCombatMix(Game.GetPlayer()) -- re-evaluate the out-of-combat mix
  ```
- A scene that explicitly `Play()`'d a music event only fully dies from `Stop()` with **that event's
  CName** (per-quest, not enumerated — capture in-game).

## Bonus — clear the PLAYER's combat state
```lua
local pl   = Game.GetPlayer()
local defs = GetAllBlackboardDefs().PlayerStateMachine
local bb   = Game.GetBlackboardSystem():GetLocalInstanced(pl:GetEntityID(), defs)
bb:SetInt(defs.Combat, EnumInt(gamePSMCombat.OutOfCombat), true)   -- OutOfCombat = 0
Game.GetAudioSystem():NotifyGameTone("LeaveCombat")
Game.GetAudioSystem():HandleOutOfCombatMix(pl)
FastTravelSystem.RemoveFastTravelLock("InCombat", pl:GetGame())
```
Mirrors `playerCombatController.ActivateOutOfCombat`. Caveat: if hostiles are still alive & tracking V,
the SM can re-assert InCombat next update → clear it AFTER moving V away / pacifying NPCs.

## UPDATE 2026-07-09 — fast-travel LOAD is the real scene/music killer (VERIFIED, working)

The v1.06 music-stop + combat-clear + `FastForwardingActivate` did NOT stop the q005 heist music in-game:
the bed is owned by the still-running scene, and **there is no scripted scene-abort** (confirmed: the whole
`SceneSystemInterface` has only fast-forward / rewind / camera / read-only queries — no Stop/Kill/Cancel).

**The fix that works: a real fast-travel LOAD.** `PerformFastTravel` checks only `HasFastTravelPoint`, NOT
`IsFastTravelEnabled` — so queuing the request fires a loading screen EVEN during the locked heist, and that
world-sector reload unloads the stuck scene + its music in one shot. Must pass a `pointData` read back from
`GetFastTravelPoints()` (a hand-built one fails the `HasFastTravelPoint` match). Implemented as
`blazeFastTravelEscape()` in init.lua:
```lua
local ft = Game.GetScriptableSystemsContainer():Get("FastTravelSystem")   -- NOT Game.GetFastTravelSystem() (nil)
FastTravelSystem.RemoveAllFastTravelLocks(Game.GetPlayer():GetGame())     -- optional; gates only the map UI
local points = ft:GetFastTravelPoints()                                    -- read registered points
local dest = points[#points]                                              -- last (PerformFastTravel no-ops if dest == current point)
local req = PerformFastTravelRequest.new(); req.pointData = dest; req.player = Game.GetPlayer()
ft:QueueRequest(req)                                                       -- fires the loading screen
```
Nuclear fallback (`blazeLoadCheckpoint()`): `Game.GetSystemRequestsHandler():LoadLastCheckpoint(true)` — full
world rebuild, but rewinds to BEFORE the finale teleport, so it's an escape-the-softlock lever, not a finale path.

⚠️ FINALE INTEGRATION (TODO once confirmed in-game): fast-travel lands at a FT POINT, not the captured finale
coords, and a load likely culls the AMM companion — so wiring it into the auto-finale needs a two-step:
fast-travel → detect load done (poll: player pos jumped far from Konpeki) → soft-teleport to `finalePos` +
RESPAWN Jackie + run `blazeFinaleTree`. Validate the music kill via the console/overlay buttons FIRST.

## UPDATE 2026-07-09 (b) — fast-travel/reload SOFTLOCK; kill the AUDIO instead

In-game, `blazeFastTravelEscape()` **black-screened with no recovery**. Cause (verified): a running `.scene`
holds a hard lock on the player + world streaming; fast-travel tears down the sector but the prologue scene
never releases its lock / never gets a completion signal, so the load waits forever. **No CET-reachable safe
world/sector reload exists while a scene is active** — so world-reload (fast-travel AND checkpoint) is OUT.
`blazeFastTravelEscape` / `blazeLoadCheckpoint` are kept console-only; the overlay buttons were removed.

Kill the music DIRECTLY instead (v1.11):
- **`blazeLogAudio(true)`** — `ObserveAfter("gameGameAudioSystem", m, …)` on Play/Stop/Switch/State/Parameter/
  PlayOnEmitter/StopOnEmitter/RequestSongOnRadioStation; prints `[Blaze][AUDIO] …` while the bed loops so you
  can read the event/state CName, then **`blazeStopMusicEvent("<name>")`** (`AudioSystem:Stop`). Surgical, but
  only catches SCRIPT-routed audio — a scene bed fired natively in C++ shows nothing (likely for a quest bed).
- **`blazeMuteMusic(true)`** — GUARANTEED silence: `Game.GetSettingsSystem():GetVar("/audio/volume","MusicVolume")
  :SetValue(0)` (restores the saved value on `false`). Works even for a native/unnamed bed. Kills ALL music, so
  it's a toggle; wired into the finale via `Blaze.cfg.muteMusicOnFinale` (default true). This is the reliable fix.

Recommended: try the logger+Stop first (surgical); if the logger shows nothing, the finale mute is the answer.

## Sources
- decompiled `fastTravelSystem.script`, `playerCombatController.script`, `audioSystem.script`
  (CDPR-Modding-Documentation/Cyberpunk-Scripts)
- NativeDB RTTI dumps (`gameGameAudioSystem` / `scnSceneSystem` / `ScriptGameInstance`)
- `FastTravelFromAnywhere.reds` (rfuzzo/cyberpunk-nexus-script-dump 9241); `psiberx/cp2077-cet-kit`
