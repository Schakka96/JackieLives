--[[
  Jackie Lives — CET prototype mod (MVP)  v0.2
  ----------------------------------------------------------------------------
  v0.2 changes:
    * Robust Jackie lookup (handles AMM list whether it's an array or a map, and
      whatever field holds the name/record).
    * "Run diagnostics" button — dumps AMM's character list + the time API to the
      console so we can see the exact shapes. (Paste the [JackieLives] lines to Claude.)
    * Robust game-hour read (handles GameTime object OR numeric form).
    * "Hide window" button + a toggle hotkey, so the panel can be dismissed without
      closing the whole CET overlay.

  Depends on: Cyber Engine Tweaks, AppearanceMenuMod (AMM), Codeware.
  Console lines are prefixed [JackieLives]. Red errors → send to Claude.

  ============================================================================
  ARCHITECTURE MAP (v0.44) — what each subsystem owns. There is only ever ONE
  Jackie ENTITY; "idle" and "companion" are two SYSTEMS that hand the same entity
  back and forth. Keep edits inside ONE subsystem; they share a few helpers (noted).

   • IDLE / SCHEDULE  (state: JL.idle)  — scheduleTick spawns him at his scheduled
     venue when V is near; wanderTick free-roams him between that venue's waypoints
     (dwell → walk → sit/lean pose). returnToPost hands a dismissed companion back here.
   • COMPANION        (state: JL.summon) — summonJackie (instant) / promoteToCompanion
     (after an arrival). Follower role = AMM SetNPCAsCompanion. dismissJackie removes him.
   • ARRIVAL (v0.50)  (state: JL.varrival) — vehicleArrivalTick is the ONE arrival machine, TWO modes
     (Config.call.arrivalMethod): "foot" DES-spawns Jackie at `Config.vehicle.spawnDistance` (50 m) and
     SPRINTS him in (-> WALK last 14 m); "bike" spawns his Arch + Jackie at `bikeSpawnDistance` (60 m),
     mounts, rides in, slows at 30 m, PARKS on the road at 20 m, then WALKS the rest. Both end at
     COMPANION via `Config.call.companionDistance` (5 m, small so AMM's catch-up teleport can't yank him
     into V), then say a GREETING LINE within `arrivalGruntDistance` (4 m; v0.52). Spawn point obeys: same level as V
     (`maxSpawnZDelta`), on a SIDE of V (`spawnSides`), and a STUCK->respawn-closer ladder (`respawnRungs`)
     if he can't path in. NOTE: the old AMM-spawn+hide+teleport "safe walk-in" + invisibility hack were
     DELETED in v0.50 — DES spawns out at distance, never pops near V.
   • DINNER OUTING    (state: JL.dinner)  — dinnerTick: companion Jackie walks to a
     restaurant, sits, resets his companion clock, re-follows. Owns its own collision.
   • DIALOGUE/CALL    (Branch.*, dlg, callTick) — the voiced choice-box + holocall convo.
   • POSES            (tryWorkspotPose/stopWorkspotPose/applyIdlePose) — AMM workspot
     sit/lean. SHARED by idle + dinner; it does NOT touch collision (callers do).
   • UI               (onDraw) — the debug window (Force venue, seat tuner, toggles).

  COLLISION OWNERSHIP (the v0.43 bug was two systems fighting over this):
     setNpcCollision(handle, on) is the only low-level toggle.
   • IDLE     -> applyIdleCollision() at placement, driven by Config.idleNoCollision.
   • DINNER   -> dinnerTick drops it on `seating`, restores it when he stands.
   • COMPANION-> promoteToCompanion() FORCES it on (a follower must collide / not clip V).
     The shared pose helpers must NEVER toggle collision — that caused the cross-talk.
  ============================================================================
--]]

local Config = require("config")
-- ⚠️ GLOBAL (not `local`) ON PURPOSE — see the "200-LOCAL CEILING" note below. init.lua's main chunk
-- is at Lua's hard 200-local-per-function limit; a new top-level `local` here would make the WHOLE file
-- fail to load in CET. Globals don't count toward that limit. (The CET debug window calls Retrieval.*)
Retrieval = require("retrieval")   -- "Where's Jackie?" questline + master mod gate (see retrieval.lua)
pcall(function() package.loaded["blaze"] = nil end)   -- v0.98: force a FRESH read on CET soft-reload; else the cached old module sticks (stale startYorinobu/diagnose)
Blaze     = require("blaze")       -- v0.96 GLOBAL (200-cap): "Blaze of Glory" Heist set-piece (see blaze.lua)
Session   = require("session")     -- v1.52 GLOBAL (200-cap): session guard + crash log (see session.lua)
-- 200-LOCAL CEILING (added with the retrieval feature, 2026-07-01): v0.66 silently crossed Lua's
-- 200-locals-per-function cap, so v0.66/v0.67 init.lua FAILED TO LOAD (`main function has more than
-- 200 local variables`). To get back under it, six ancient leaf helpers below were changed from
-- `local function` to plain `function` (globals): getAMMCharacters, discoverJackieFromSpawned,
-- diagnostics, dismissAllJackies, capturePosition, probeChoiceBoxAPI. If you add more top-level
-- locals, convert a few stable functions to globals OR extract a module (see retrieval.lua) to stay safe.

local JL = {
  amm    = nil,
  jackie = { record = nil, name = nil },
  ui     = { open = true, overlayOpen = false, lastCapture = nil, forceMainQuest = false, status = "",
             voIndex = 0, voText = "", forceVenue = nil },
  summon = { spawn = nil, active = false, companionSet = false, walkIn = false },
  -- v0.66 companion catch-up: while he's a confirmed, undismissed companion, if V gets far
  -- (fast-travel / ran off / he got left behind) he teleports back to V's SIDE (never onto V).
  catchUp = { farSince = nil, lastAt = nil, teleTries = nil },
  -- v0.82 respawn-settle: after a respawn-at-V (catch-up FT recovery / persist) hide Jackie + drop his
  -- collision briefly so he doesn't visibly POP in or spawn into a wall, then reveal + re-collide by clock.
  -- v1.40 reposePending/reposeAt/reposeLast: one-shot "move him off AMM's drop spot to V's front/side" latch.
  settle  = { hideUntil = nil, collideUntil = nil, handle = nil, reposePending = nil, reposeAt = nil, reposeLast = nil },
  -- v0.67 keep-close: periodically re-assert our tight follow so AMM's long leash can't let him
  -- trail far behind V. Just a throttle timestamp.
  follow  = { lastAt = nil },
  -- v0.72 companion PERSISTENCE: "is companion" is saved per-slot as the game fact
  -- jackielives_companion. On a fresh load (Lua state wiped) or a load-screen fast-travel that
  -- culled his entity, this re-spawns + re-promotes him at V. gapSince/lastRespawn are throttles.
  persist = { gapSince = nil, lastRespawn = nil, worldReadyAt = nil },
  -- v0.84 walk-abreast: keep-close variant that holds Jackie BESIDE/AHEAD of V (offset from V's
  -- forward vector) instead of trailing behind. lastAt is the re-issue throttle.
  abreast = { lastAt = nil },
  -- v1.57 loiter halt: `still` is the latched "V is basically standing" state (jlVLoitering); slowSince /
  -- fastSince are the two sustain timers that flip it; lastHoldAt throttles the re-issued hold command.
  loiter  = { still = false, slowSince = nil, fastSince = nil, frame = nil, lastHoldAt = nil },
  -- v0.35 free-roam wander: placed=on a waypoint yet; phase=dwelling|walking; cur/tgtIdx=waypoints.
  -- v0.38 walk-away: leaving=true while he's strolling to a venue exit before despawning.
  idle   = { spawn = nil, locationKey = nil, placed = false, phase = nil, curIdx = nil, tgtIdx = nil,
             spawnedAt = 0, dwellUntil = 0, arriveBy = 0, lastReissue = 0,
             leaving = false, leaveTarget = nil, leaveDeadline = 0, leaveReissue = 0,
             collisionOff = false },   -- v0.44: idle collision state (driven by Config.idleNoCollision)
  -- v0.43 seat tuner: live X/Y/Z/yaw OFFSETS from a location's captured seat, so a sit spot can be
  -- nudged in-game until perfect, then printed for config.lua. Targets Config.locations[key].
  tuner  = { init = false, key = "noodle", seatIdx = 1, live = true, pendingApplyAt = nil,
             baseX = 0, baseY = 0, baseZ = 0, baseYaw = 0,
             dx = 0, dy = 0, dz = 0, dyaw = 0,
             prevX = 0, prevY = 0, prevZ = 0, prevYaw = 0 },
  -- v0.36 day rotation: a shuffle bag of Config.dayBag; one day-type per in-game day. Rollover
  -- is detected by the game hour WRAPPING (current < last), since time only ever moves forward.
  day    = { lastHour = nil, count = 0, template = nil, bag = {}, bagPos = 0 },
  -- v0.41 secret sleeping-hours cameo: decided=rolled this night yet; active=he shows at the spot.
  secret = { decided = false, active = false },
  -- v1.3 approach cameo: V getting within Config.approach.radius of a venue can force Jackie to
  -- show there. day = in-game day we last reset on; premiumUsed = the one premium appearance has
  -- already landed today (rate drops after); forcedKey = the venue V's approach pinned him to for
  -- the day; near = per-venue edge-trigger state (each venue only re-rolls after V has left its
  -- radius and come back, so it can't roll every tick).
  approach = { day = -1, premiumUsed = false, forcedKey = nil, near = {} },
  -- holocall arrival state machine: spawn far (passive) -> walk in -> hand off to companion.
  arrival = { at = nil, phase = nil, pt = nil, placeAt = nil, moveAt = nil, deadline = nil, lastReissue = 0 },
  -- v0.33 "send Jackie off": drop follower role -> walk away -> despawn once far enough.
  leaving = { phase = nil, deadline = nil, lastReissue = 0 },
  -- v0.53 catch-his-eye smile: until_=hold-smile deadline; nextRoll=next gaze roll; nextApply=re-assert
  -- facial; cooldownUntil=earliest next smile; handle=who's smiling (to reset the right face).
  smile  = { until_ = 0, nextRoll = 0, nextApply = 0, cooldownUntil = 0, handle = nil,
             -- v0.93 reunion boost: on during reunionMeetTree; forceUntil = end of the forced-smile
             -- window; safety = hard expiry so an aborted meet can't leave him smiling forever; idle =
             -- which happy face is currently applied.
             reunionActive = false, reunionForceUntil = 0, reunionSafety = 0, idle = nil },
  -- v0.34 VEHICLE ARRIVAL: spawn on bike behind V -> drive in -> dismount -> jog/walk -> companion.
  varrival = { at = nil, phase = nil, pt = nil, bikeId = nil, bikeHandle = nil,
               placeAt = nil, driveAt = nil, sprintAt = nil, lastReissue = 0, deadline = nil, driveCmd = nil },
  call    = { ringingAt = nil },  -- holocall: clock time he "picks up" after the ring
  -- v0.55 ambient "feel alive" grunts: nextRoll = clock time of the next chance-to-grunt.
  ambient = { nextRoll = 0 },
  -- v0.41 dinner outing: walk to a chosen restaurant -> linger -> full companion-clock reset.
  dinner  = { phase = nil, dest = nil, destName = nil, destYaw = nil, mappinId = nil, satAt = nil,
              lastResetGame = nil, collisionOff = false, seatDeadline = nil, sitFireAt = nil,  -- v0.44 seat rework
              nextOfferGame = nil, offerSession = nil },  -- v0.48: Jackie's self-initiated dinner offer schedule
  -- v0.95 STORY MODE selector: "quietlife" (default, non-invasive layer) vs "blaze" (Blaze of Glory —
  -- the alternate-timeline route that rewrites the Heist ending + disables the main plot). Blaze
  -- MACHINERY IS WIP (pending the JLFactDump spike + WolvenKit q005 edits); the toggle persists the
  -- choice and sets the jl_mode_blaze quest fact that the future questphase edit reads. Field on JL
  -- (not a new top-level local) to respect the 200-locals cap.
  mode   = "quietlife",   -- "quietlife" | "blaze"
  -- v0.97 QUIET-LIFE MOURNING SUPPRESSION: hold the "Jackie is dead" grief facts down so a living
  -- Jackie doesn't collide with the ofrenda / grief calls. SAFE-BY-DEFAULT (off until confirmed) —
  -- persisted via JL_SETTINGS_KEYS; the actual fact list lives in JL_MOURNING_FACTS (below).
  mourningSuppress = false,
  keepBarOpen      = false,   -- v0.97b: force El Coyote / Mama's bar open (compensates for blocking sq018)
  mourningTimer    = 0,
  timer  = 0,
  clock  = 0,        -- accumulated game seconds (for talk cooldowns)
  lastTalk = -999,
  lastSeen = -999,
  talkDone = {},     -- v0.32: [treeKey] = clock time a cooldown'd talk tree was finished
}

-- v0.76: log to the CET console AND append to jackie_debug.log in the mod folder (CET sandboxes io to
-- the mod dir → .../mods/JackieLives/jackie_debug.log). Commit that file to share full logs — no more
-- OCR'ing the console. Truncated fresh each load (see onInit). pcall'd so io being unavailable never breaks logging.
local function log(msg)
  local line = "[JackieLives] " .. tostring(msg)
  print(line)
  pcall(function() local f = io.open("jackie_debug.log", "a"); if f then f:write(line .. "\n"); f:close() end end)
end

-- ---------------------------------------------------------------------------
-- AMM + Jackie record
-- ---------------------------------------------------------------------------
local function getAMM()
  if JL.amm == nil then JL.amm = GetMod("AppearanceMenuMod") end
  return JL.amm
end

function getAMMCharacters()   -- global (not local): keeps main chunk under Lua's 200-local cap; see note at top
  local amm = getAMM()
  if not amm or not amm.API or not amm.API.GetAMMCharacters then return nil end
  local ok, chars = pcall(function() return amm.API.GetAMMCharacters() end)
  if not ok or type(chars) ~= "table" then return nil end
  return chars
end

-- collect every string-ish field from an entry (table or string), any shape
local function entryFields(c)
  local f = {}
  if type(c) == "table" then
    for _, key in ipairs({ "name", "record", "id", "path", "appearance" }) do
      if c[key] ~= nil then f[#f + 1] = c[key] end
    end
    if c[1] ~= nil then f[#f + 1] = c[1] end
    if c[2] ~= nil then f[#f + 1] = c[2] end
    if c[3] ~= nil then f[#f + 1] = c[3] end
  elseif type(c) == "string" then
    f[#f + 1] = c
  end
  return f
end

local function looksLikeRecord(s)
  s = tostring(s)
  return (s:find("0x") ~= nil) or (s:find("Character") ~= nil) or (s:find("%.") ~= nil)
end

-- Discover Jackie's record from NPCs already spawned through AMM's own menu.
-- (AMM stores them in AMM.Spawn.spawnedNPCs, keyed by uniqueName, each with .name/.path.)
function discoverJackieFromSpawned(verbose)   -- global (not local): 200-local cap; see note at top
  local amm = getAMM()
  if not amm or not amm.Spawn or not amm.Spawn.spawnedNPCs then
    log("AMM.Spawn.spawnedNPCs not available."); return false
  end
  local found = false
  for _, sp in pairs(amm.Spawn.spawnedNPCs) do
    local nm   = tostring(sp.name or "")
    local path = tostring(sp.path or sp.id or "")
    if verbose then log(string.format("  spawned: name=%s path=%s", nm, path)) end
    if nm:lower():find("jackie") or path:lower():find("jackie") then
      JL.jackie.name   = sp.name or "Jackie"
      JL.jackie.record = sp.path or sp.id
      log("DISCOVERED Jackie record = '" .. tostring(JL.jackie.record) ..
          "'   <- paste this into config.jackieRecord")
      found = true
      break
    end
  end
  if not found then
    log("No Jackie among AMM's spawned NPCs. Spawn him via AMM's menu first, then click 'Find Jackie'.")
  end
  return found
end

-- v0.96 BLAZE: generalised version of discoverJackieFromSpawned — grab ANY AMM-spawned
-- NPC/vehicle's record path by a name substring (e.g. "smasher", "takemura", "av"). Spawn
-- it via AMM's own menu first, then call this; returns the record string (also logged so it
-- can be pasted into blaze.lua M.cfg for permanence). Global (not local) => 200-cap safe.
function discoverBlazeRecord(nameFilter)
  local amm = getAMM()
  if not amm or not amm.Spawn then log("AMM.Spawn unavailable."); return nil end
  nameFilter = tostring(nameFilter or ""):lower()
  local hit = nil
  local function scan(tbl)
    if type(tbl) ~= "table" then return end
    for _, sp in pairs(tbl) do                     -- keep the LAST match (newest spawn wins)
      if type(sp) == "table" then
        local nm   = tostring(sp.name or ""):lower()
        local path = sp.path or sp.id
        if path and (nameFilter == "" or nm:find(nameFilter, 1, true) or tostring(path):lower():find(nameFilter, 1, true)) then
          hit = tostring(path)
        end
      end
    end
  end
  scan(amm.Spawn.spawnedNPCs)                       -- NPCs live here...
  for k, v in pairs(amm.Spawn) do                   -- ...vehicles/props may live in a sibling "spawned*" table
    if type(v) == "table" and tostring(k):lower():find("spawn", 1, true) then scan(v) end
  end
  if hit then log("Blaze DISCOVERED record for '" .. nameFilter .. "' = '" .. hit .. "'   <- saved")
  else        log("Blaze: no AMM-spawned entity matched '" .. nameFilter .. "'. (Vehicles: use the look-at grab.)") end
  return hit
end

-- v0.97 BLAZE: grab the TweakDB record path off whatever V is LOOKING AT. Works for the heli
-- (a vehicle — not in AMM's NPC table) and anything else with a crosshair hitbox. Reads
-- GetRecordID() and reverses it to the readable "Vehicle.xxx"/"Character.xxx" string via CET's
-- TDBID.ToStringDEBUG. Global (not local) => 200-cap safe.
function discoverBlazeRecordFromTarget()
  local pl = Game.GetPlayer(); if not pl then log("Blaze look-at grab: no player."); return nil end
  local target
  pcall(function()
    local ts = Game.GetTargetingSystem()
    if ts then target = ts:GetLookAtObject(pl, false, false) end
  end)
  if not target then log("Blaze look-at grab: not looking at anything — put your crosshair ON the heli, then click."); return nil end
  local rec
  pcall(function()
    if target.GetRecordID then
      local id = target:GetRecordID()
      if TDBID and TDBID.ToStringDEBUG then rec = TDBID.ToStringDEBUG(id) end   -- hash -> readable path
    end
  end)
  local cls = "?"; pcall(function() local c = target:GetClassName(); cls = tostring(c and (c.value or c)) end)
  if rec and rec ~= "" then
    log("Blaze look-at grab [" .. cls .. "] record = '" .. rec .. "'   <- saved")
    return rec
  end
  log("Blaze look-at grab: entity [" .. cls .. "] gave no readable record — tell Claude this class name so we can adapt.")
  return nil
end

-- v0.96 BLAZE: capture V's current transform as a plain {x,y,z,yaw} table for a set-piece
-- spawn point, and LOG it so it can be pasted into blaze.lua M.cfg. Global => 200-cap safe.
function blazeCapture()
  local pl = Game.GetPlayer(); if not pl then log("Blaze capture: no player."); return nil end
  local pos = pl:GetWorldPosition(); local yaw = 0.0
  pcall(function() yaw = pl:GetWorldOrientation():ToEulerAngles().yaw end)
  local t = { x = pos.x, y = pos.y, z = pos.z, yaw = yaw }
  log(string.format("Blaze capture -> { x = %.3f, y = %.3f, z = %.3f, yaw = %.1f }", t.x, t.y, t.z, yaw))
  return t
end

-- v0.96 BLAZE: persist the whole set-piece config to a plain-text file in the mod folder
-- (CET sandboxes io to .../mods/JackieLives/), written as executable Lua assignments so it
-- RE-LOADS itself on launch (see blazeLoadConfig) -- captures survive reloads/redeploys with
-- ZERO console copying. Move this file to the Mac only if you want the values baked into
-- blaze.lua for the shipped mod. Auto-called on every capture/grab. Global => 200-cap safe.
BLAZE_CONFIG_FILE = "blaze_config.txt"

-- v1.x BLAZE: the Story-mode description, shown both in the arm/confirm prompt and once Blaze is on.
-- Global (not a top-level local) => 200-cap safe; one source of truth for the two draw sites.
-- v1.07 (Antonia): spoiler-light — hint that it's INTENSE, don't reveal who you fight, what happens
-- after, or the payoff. Keep the functional warnings (replaces the ending, disables the main plot, can't undo).
BLAZE_DESC = "A wilder, more intense way out of the Heist -- you and Jackie face it together, guns up. " ..
  "This REPLACES the Heist's ending and DISABLES the main storyline. Extremely experimental, and it " ..
  "CAN'T be undone. Choose it BEFORE jumping off the building in the Heist."

-- v1.03: records/positions capture was removed from the overlay — the bosses use hardcoded records +
-- the fixed elevator spawn, and the escape is the roof AV (coords in blaze.lua M.yori). The only thing
-- still worth persisting is the OPTIONAL spawned-VTOL record (if you ever set Blaze.cfg.heliRecord via
-- the console). Everything else lives in blaze.lua now.
function blazeDumpConfig()
  local c = Blaze.cfg
  local function q(s) return s and string.format("%q", tostring(s)) or "nil" end
  local out = {
    "-- Blaze of Glory captured config (AUTO-WRITTEN; re-loaded on launch).",
    "Blaze.cfg.heliRecord = " .. q(c.heliRecord),
  }
  pcall(function()
    local f = io.open(BLAZE_CONFIG_FILE, "w")
    if f then f:write(table.concat(out, "\n") .. "\n"); f:close() end
  end)
end

-- v0.96 BLAZE: read blaze_config.txt (if present) and apply it to Blaze.cfg on load. The file
-- IS Lua (Blaze.cfg.* = ...), so we just load+run it. Guarded: a missing file or a disabled
-- load() simply no-ops (in-session captures still work). Global => 200-cap safe.
function blazeLoadConfig()
  local content
  pcall(function() local f = io.open(BLAZE_CONFIG_FILE, "r"); if f then content = f:read("*a"); f:close() end end)
  if not content or content == "" then return false end
  local ok = pcall(function()
    local chunk = (load and load(content)) or (loadstring and loadstring(content))
    if chunk then chunk() end
  end)
  log(ok and "Blaze config loaded from blaze_config.txt." or "Blaze config present but could not be applied.")
  return ok
end

-- ===========================================================================
-- v1.06 BLAZE (Antonia item 10) — "ESCAPE THE SCENE" finale teardown.
-- The Heist "everything goes wrong" music kept playing into the finale because our soft teleport moves
-- V within the already-streamed world and never ends the q005 heist scene/combat mix. These helpers are
-- the verified game calls (decompiled 2.x scripts) that tear that state down. All pcall-guarded; every
-- unknown name simply no-ops. Globals => 200-cap safe. See docs/research/q005_graph_findings.md +
-- the CET-API research note for sources.
-- ===========================================================================

-- (1) MUSIC / MIX RESET. The real routine the game runs when combat ends (playerCombatController.
-- ActivateOutOfCombat): the "LeaveCombat" game tone + re-evaluate the out-of-combat music mix. This
-- reliably kills COMBAT-tension music. A scene-quest music bed that was Play()'d explicitly only dies
-- from Stop() with its own event CName — so we also fire best-effort Stop() on candidate names; pass
-- blazeStopMusic("<event>") from the console to hunt the exact one and add it to BLAZE_MUSIC_STOP.
BLAZE_MUSIC_STOP = {
  -- one-shot "stop" events to try (best-effort; add the real captured one here).
  events = { "stop_music", "mus_stop", "q005_music_stop" },
}
function blazeStopMusic(oneEvent)
  local a; pcall(function() a = Game.GetAudioSystem() end)
  if not a then log("[Blaze] stopMusic: no AudioSystem."); return false end
  local pl; pcall(function() pl = Game.GetPlayer() end)
  local pid; pcall(function() pid = pl:GetEntityID() end)
  local empty = CName.new("")
  if oneEvent then   -- console tester: blazeStopMusic("some_event") tries just that one, loudly
    pcall(function() a:Stop(CName.new(oneEvent), pid, empty) end)
    log("[Blaze] stopMusic TEST: Stop('" .. tostring(oneEvent) .. "') fired — did the music stop?")
    return true
  end
  -- Verified out-of-combat mix reset (kills combat-tension music):
  pcall(function() a:NotifyGameTone(CName.new("LeaveCombat")) end)
  pcall(function() a:HandleOutOfCombatMix(pl) end)
  -- Best-effort explicit Stop() on candidate scene-music events:
  for _, ev in ipairs(BLAZE_MUSIC_STOP.events) do
    pcall(function() a:Stop(CName.new(ev), pid, empty) end)
  end
  log("[Blaze] stopMusic: LeaveCombat tone + out-of-combat mix + best-effort Stop() fired. If a SCENE " ..
      "music bed persists, capture its event with blazeStopMusic('<name>') and add it to BLAZE_MUSIC_STOP.")
  return true
end

-- (2) CLEAR V's COMBAT STATE — force the player state-machine's Combat slot to OutOfCombat (mirrors the
-- game's own ActivateOutOfCombat) + drop the fast-travel InCombat lock. Lets the combat mix resolve and
-- unblocks fast travel. NOTE: if hostiles are still alive & tracking V the SM can re-assert InCombat, so
-- the Blaze finale runs this AFTER teleporting V far away (bosses left behind).
function blazeClearCombat()
  local pl; pcall(function() pl = Game.GetPlayer() end)
  if not pl then return false end
  pcall(function()
    local defs = GetAllBlackboardDefs().PlayerStateMachine
    local bb   = Game.GetBlackboardSystem():GetLocalInstanced(pl:GetEntityID(), defs)
    if bb then bb:SetInt(defs.Combat, EnumInt(gamePSMCombat.OutOfCombat), true) end
  end)
  pcall(function() FastTravelSystem.RemoveFastTravelLock("InCombat", pl:GetGame()) end)
  pcall(function()
    local a = Game.GetAudioSystem()
    if a then a:NotifyGameTone(CName.new("LeaveCombat")); a:HandleOutOfCombatMix(pl) end
  end)
  log("[Blaze] clearCombat: V forced OutOfCombat + FT lock cleared.")
  return true
end

-- v1.12 (Antonia): HOLSTER V's weapon — the exact request the game's own code queues to holster (verified
-- in the decompiled EquipmentSystem: UnequipWeapon manipulation). Empties V's hands + plays the holster anim.
function blazeHolsterWeapon(pl)
  pl = pl or Game.GetPlayer(); if not pl then return false end
  local ok = false
  pcall(function()
    local es  = Game.GetScriptableSystemsContainer():Get("EquipmentSystem")
    local req = EquipmentSystemWeaponManipulationRequest.new()
    req.owner, req.requestType = pl, EquipmentManipulationAction.UnequipWeapon
    es:QueueRequest(req)
    ok = true
  end)
  log("[Blaze] holster -> " .. tostring(ok))
  return ok
end

-- v1.12 (Antonia): FORCE-STAND (uncrouch). The PSM Locomotion blackboard int is an OUTPUT (gets overwritten
-- every tick), so poking it does nothing — the engine's real switch is a status effect tagged `ForceStand`
-- (verified in locomotionTransitions CrouchDecisions). v1.53: we mint that record ourselves at runtime
-- (blazeEnsureForceStandRecord) instead of shipping a TweakXL yaml, so the mod gains no new dependency.
-- Removed again when the finale convo ends (blazeReleaseStand).
-- v1.53: WE BUILD THE ForceStand RECORD OURSELVES — no TweakXL, no extra dependency.
--
-- The engine's real uncrouch switch is a status effect carrying the GAMEPLAY TAG `ForceStand` — not any
-- particular record name. locomotionTransitions.script tests it by tag in three places, e.g.
--     ToStand():  if StatusEffectSystem.ObjectHasStatusEffectWithTag( owner, 'ForceStand' ) … return true
-- and the crouch-input handlers refuse to re-crouch while it's present. The game ships the exact counterpart
-- `GameplayRestriction.ForceCrouch` (the sniper nest uses it) but no stock ForceStand-tagged record.
--
-- We used to supply one via a TweakXL yaml. Antonia's call (2026-07-09): don't make players install a whole
-- framework just to stand V up. CET's TweakDB API can clone that record and swap the tag AT RUNTIME — exactly
-- the two edits the yaml made — so we do it in Lua. TweakDB edits are runtime-only (never written into the
-- save), so this is redone each launch, lazily, the first time the finale needs it.
--
-- If it fails we DEGRADE, we don't fight: no uncrouch, V simply stays crouched through the transport. That is
-- Antonia's explicit fallback ("if that's unstable/proven not workable, no un-sneak at all"). It never
-- crashes and never blocks the finale. A TweakXL yaml still works if you happen to have one — GetRecord finds
-- it and we skip the clone — but nothing requires it.
function blazeEnsureForceStandRecord()
  if JL.forceStandReady ~= nil then return JL.forceStandReady end   -- resolved once per game launch
  local have
  pcall(function() have = TweakDB:GetRecord("GameplayRestriction.JLForceStand") end)
  if have ~= nil then
    JL.forceStandReady = true
    log("[Blaze] forceStand: JLForceStand already present (a TweakXL yaml supplied it) — no clone needed.")
    return true
  end
  local ok = pcall(function()
    TweakDB:CloneRecord("GameplayRestriction.JLForceStand", "GameplayRestriction.ForceCrouch")
    TweakDB:SetFlat("GameplayRestriction.JLForceStand.gameplayTags", { CName.new("ForceStand") })
    TweakDB:Update("GameplayRestriction.JLForceStand")
  end)
  if ok then pcall(function() have = TweakDB:GetRecord("GameplayRestriction.JLForceStand") end) end
  JL.forceStandReady = (have ~= nil)
  if JL.forceStandReady then
    log("[Blaze] forceStand: cloned ForceCrouch -> JLForceStand and swapped the tag to ForceStand "
        .. "(runtime TweakDB; no TweakXL required).")
  else
    log("[Blaze] forceStand: could NOT build a ForceStand record at runtime -> V stays crouched through the "
        .. "finale transport. Harmless: the scene runs normally.")
  end
  return JL.forceStandReady
end

-- ⚠️ v1.51 — THE OLD LOOP COULD NOT FAIL, AND SO COULD NOT FALL BACK.
-- It did `pcall(function() ApplyStatusEffect(pl, rec); ok = true end)` and treated "nothing threw" as
-- success. But ApplyStatusEffect is a native import: handed a TweakDBID that doesn't exist it simply does
-- nothing — it does NOT raise. So `ok` was ALWAYS true for the first record, we logged
-- "applied GameplayRestriction.JLForceStand", returned, and never tried the stock fallback. When the record
-- wasn't present, V stayed crouched while the log insisted the effect had been applied.
--
-- (Back then the record came from a TweakXL yaml that `deploy.ps1` never copied — which is why it "used to
-- work" and then didn't. v1.53 removed that dependency entirely: blazeEnsureForceStandRecord mints the record
-- at runtime. The silent-success bug below is fixed regardless, because it would hide any future absence too.)
--
-- Fix: choose the record by whether TweakDB actually HAS it — a synchronous, reliable discriminator — instead
-- of by whether ApplyStatusEffect declined to throw. (We deliberately do NOT verify with
-- StatusEffectSystem.ObjectHasStatusEffect here: on the frame the effect is applied it can still read false,
-- which would send us down the fallback for no reason. blazeCalmHoldTick does the real outcome check, by
-- watching whether V actually stands up.)
function blazeForceStand(pl)
  pl = pl or Game.GetPlayer(); if not pl then return false end
  blazeEnsureForceStandRecord()   -- v1.53: mint JLForceStand at runtime if it isn't there yet
  for _, rec in ipairs({ "GameplayRestriction.JLForceStand", "GameplayRestriction.ForceStand" }) do
    local present
    pcall(function() present = TweakDB:GetRecord(rec) end)
    if present == nil then
      log("[Blaze] forceStand: record " .. rec .. " is NOT in TweakDB -> skipping it.")
    else
      local sent = pcall(function() StatusEffectHelper.ApplyStatusEffect(pl, rec) end)
      if sent then JL.forceStandRec = rec; log("[Blaze] forceStand: applied " .. rec); return true end
      log("[Blaze] forceStand: " .. rec .. " exists but ApplyStatusEffect errored.")
    end
  end
  log("[Blaze] forceStand: no ForceStand record available -> V stays crouched through the transport. "
      .. "Harmless; the finale runs normally.")
  return false
end

-- Release the ForceStand effect (so V can crouch again after the finale). Safe to call anytime.
function blazeReleaseStand(pl)
  pl = pl or Game.GetPlayer(); if not pl or not JL.forceStandRec then return end
  pcall(function() StatusEffectHelper.RemoveStatusEffect(pl, JL.forceStandRec) end)
  log("[Blaze] forceStand: released " .. tostring(JL.forceStandRec))
  JL.forceStandRec = nil
end

-- v1.11 (Antonia): put V in a CALM state for the finale fade-in — out of combat, weapon HOLSTERED, and
-- STANDING (not crouched). Exact holster/uncrouch calls verified separately; each is pcall-guarded so a
-- wrong/absent one just no-ops. Called at full black in the finale.
function blazeTransportCalm()
  pcall(blazeClearCombat)   -- out of combat (verified)
  local pl; pcall(function() pl = Game.GetPlayer() end)
  if not pl then return false end
  -- HOLSTER the weapon (filled from research).
  pcall(function() blazeHolsterWeapon(pl) end)
  -- STAND UP / uncrouch (filled from research).
  pcall(function() blazeForceStand(pl) end)
  -- v1.51: ARM THE HOLD. This runs in the SAME FRAME as V's teleport, and the teleport is ASYNC (the very
  -- reason the finale re-issues Jackie's placement until he lands). Firing the holster/uncrouch once into
  -- that frame is a race: whichever of the two the engine processes second can swallow the first. So we
  -- keep re-asserting on a short heartbeat until V is OBSERVED standing, then stop and say how long it took.
  -- If the window expires with V still crouched, we say THAT — instead of the old log's confident "applied".
  local C = Config.blazeCalm or {}
  JL.blazeCalm = { startedAt = JL.clock or 0, deadline = (JL.clock or 0) + (C.holdSeconds or 3.0),
                   nextAt = (JL.clock or 0) + (C.interval or 0.25), holsters = 0 }
  log("[Blaze] transportCalm: out-of-combat + holster + stand issued; verifying for "
      .. tostring(C.holdSeconds or 3.0) .. " s.")
  return true
end

-- v1.51: watch the calm to a conclusion. Stepped from onUpdate. Cheap: does nothing unless armed.
-- Re-asserts ForceStand quietly (we already know which record works — no repeat of its log line), and
-- re-queues the holster a couple of times, since a weapon can be re-drawn by the state the teleport lands in.
function blazeCalmHoldTick()
  local h = JL.blazeCalm; if not h then return end
  local C = Config.blazeCalm or {}
  local now = JL.clock or 0
  if now < (h.nextAt or 0) then return end
  h.nextAt = now + (C.interval or 0.25)
  local pl; pcall(function() pl = Game.GetPlayer() end)
  if not pl then return end

  if not jlVCrouched() then                       -- the outcome we actually wanted
    log(("[Blaze] transportCalm: V is STANDING (took %.2f s)."):format(now - (h.startedAt or now)))
    JL.blazeCalm = nil
    return
  end
  if now >= (h.deadline or 0) then
    log("[Blaze] transportCalm: V is STILL CROUCHED after " .. tostring(C.holdSeconds or 3.0)
        .. " s — the ForceStand effect never took. See the `forceStand:` line above. This is cosmetic: V just "
        .. "stays crouched through the transport and the finale runs normally.")
    JL.blazeCalm = nil
    return
  end
  -- still crouched, still inside the window -> re-assert.
  if JL.forceStandRec then                        -- known-good record: re-apply it without re-logging
    pcall(function() StatusEffectHelper.ApplyStatusEffect(pl, JL.forceStandRec) end)
  else
    pcall(function() blazeForceStand(pl) end)     -- never resolved one; this logs why
  end
  if (h.holsters or 0) < (C.maxHolsterReasserts or 3) then
    h.holsters = (h.holsters or 0) + 1
    pcall(function() blazeHolsterWeapon(pl) end)
  end
end

-- (3) END THE ACTIVE SCENE — there is NO scripted per-scene abort in 2.x; the only script handle on a
-- running .scene is FAST-FORWARD (what the game's skip-cutscene uses). We activate it to blow the active
-- heist scene through to its end (killing its music bed), then auto-deactivate a few seconds later
-- (blazeSceneFFTick) so the NEXT scene doesn't play accelerated.
-- ⚠️ RISK (max-risk mode, Antonia's call): fast-forwarding the LIVE q005 heist scene could let the quest
--    graph advance toward the No-Tell/death tail — the very thing Blaze skips. Blaze has already teleported
--    V out (scene likely orphaned → FF is a no-op then), but WATCH on a throwaway save: does the quest jump
--    forward / does Johnny start after the finale? If so, set Blaze.cfg.endSceneOnFinale = false.
function blazeEndScene(durSeconds)
  local si; pcall(function() si = Game.GetSceneSystem():GetScriptInterface() end)
  if not si then log("[Blaze] endScene: no scene ScriptInterface."); return false end
  local mode = 0; pcall(function() mode = scnFastForwardMode.Default end)
  local ok = false
  pcall(function() si:FastForwardingActivate(mode); ok = true end)
  JL.blazeFF = { active = ok, offAt = (JL.clock or 0) + (durSeconds or 6.0) }
  log("[Blaze] endScene: scene fast-forward " .. (ok and "ACTIVATED" or "FAILED") ..
      " (auto-off in " .. tostring(durSeconds or 6.0) .. "s).")
  return ok
end
-- Deactivate the scene fast-forward once its timer elapses (stepped from onUpdate's blaze branch).
function blazeSceneFFTick()
  local ff = JL.blazeFF
  if not ff or not ff.active then return end
  if (JL.clock or 0) < (ff.offAt or 0) then return end
  ff.active = false
  pcall(function() local si = Game.GetSceneSystem():GetScriptInterface(); if si then si:FastForwardingDeactivate() end end)
  log("[Blaze] scene fast-forward: deactivated.")
end

-- (4) NUCLEAR OPTION — real fast-travel LOAD (full world teardown → guaranteed music/scene kill). Only
-- reaches registered fast-travel POINTS (not arbitrary XYZ), so it CANNOT land exactly at El Coyote —
-- it drops V at the nearest metro/FT point. Kept as a console tester (not in the auto-finale) for when
-- the softer layers don't fully silence a stubborn bed. blazeFastTravelEscape() picks the closest node.
-- VERIFIED against decompiled 2.x scripts (docs/research/cet_scene_music_teardown.md): PerformFastTravel
-- checks only HasFastTravelPoint, NOT IsFastTravelEnabled — so queuing the request fires a real loading
-- screen EVEN during the locked heist, and that world reload is what actually unloads the stuck q005 scene
-- + its music bed. Must pass a pointData READ BACK from GetFastTravelPoints() (a hand-built one fails the
-- HasFastTravelPoint match). `idx` optional -> which registered point (default: last, usually another district).
function blazeFastTravelEscape(idx)
  local ft; pcall(function() ft = Game.GetScriptableSystemsContainer():Get("FastTravelSystem") end)
  if not ft then log("[Blaze] fastTravelEscape: FastTravelSystem unreachable."); return false end
  pcall(function() FastTravelSystem.RemoveAllFastTravelLocks(Game.GetPlayer():GetGame()) end)  -- free insurance (gates only the map UI)
  local points; pcall(function() points = ft:GetFastTravelPoints() end)
  local n = 0; pcall(function() n = #points end)
  log("[Blaze] fastTravelEscape: registered fast-travel points = " .. tostring(n))
  if not points or n == 0 then
    log("[Blaze] fastTravelEscape: NO registered points on this save yet -> use blazeLoadCheckpoint() instead.")
    return false
  end
  local dest = points[math.min(idx or n, n)]   -- default: LAST point (PerformFastTravel no-ops if dest == your start point)
  pcall(function() log("[Blaze] fastTravelEscape: dest record = " .. tostring(dest:GetPointRecord())) end)
  local ok = false
  pcall(function()
    local req = PerformFastTravelRequest.new()
    req.pointData = dest
    req.player = Game.GetPlayer()
    ft:QueueRequest(req)
    ok = true
  end)
  log("[Blaze] fastTravelEscape: queued fast-travel LOAD -> " .. tostring(ok) ..
      " (if nothing happens, the dest was your current point — try blazeFastTravelEscape(1) or another index).")
  return ok
end

-- NUCLEAR fallback (verified): full checkpoint reload -> rebuilds world state, guaranteed to drop the
-- stuck scene + music. ⚠️ Rewinds to BEFORE the finale teleport (the checkpoint predates our hack), so it's
-- an escape-the-softlock lever, not a finale path. Use if fast-travel reports 0 points.
function blazeLoadCheckpoint()
  local srh; pcall(function() srh = Game.GetSystemRequestsHandler() end)
  if not srh then pcall(function() srh = Game.GetInkSystem():GetSystemRequestsHandler() end) end
  if not srh then log("[Blaze] loadCheckpoint: system requests handler unreachable."); return false end
  local ok = false
  pcall(function() srh:LoadLastCheckpoint(true); ok = true end)
  log("[Blaze] loadCheckpoint: LoadLastCheckpoint(true) -> " .. tostring(ok) .. " (rewinds to before the teleport).")
  return ok
end

-- ===========================================================================
-- v1.11 BLAZE (Antonia) — stuck-scene MUSIC tools. Fast-travel/checkpoint reload BLACK-SCREEN (the live
-- q005 scene holds a hard world lock), so world-reload is OUT. Two real levers instead (verified via
-- decompiled scripts + CET audio API research, docs/research/cet_scene_music_teardown.md):
--   A) LOG the playing audio event (blazeLogAudio) -> capture its CName -> Stop it (blazeStopMusicEvent).
--      Surgical, but only catches SCRIPT-routed audio; a scene bed fired natively in C++ shows nothing.
--   B) GUARANTEED silence: drop the game's MusicVolume to 0 (blazeMuteMusic) — works even for a native
--      bed. Heavy-handed (kills ALL music until restored), so it's a toggle, not auto-on.
-- ===========================================================================

-- (A) Observe every script-routed audio call so the console prints what's firing while the bed loops.
-- Registers the hooks ONCE (they can't be removed); the print is gated on JL.audioLog so it's quiet by
-- default. Reproduce the music with it ON, watch for a repeating Play(...) / Switch/State(...) line.
function blazeLogAudio(on)
  if on == nil then on = true end
  JL.audioLog = on and true or false
  if not JL.audioObsArmed then
    JL.audioObsArmed = true
    for _, m in ipairs({ "Play", "Stop", "Switch", "State", "Parameter", "PlayOnEmitter", "StopOnEmitter", "RequestSongOnRadioStation" }) do
      pcall(function()
        ObserveAfter("gameGameAudioSystem", m, function(_, a, b, c, d)
          if not JL.audioLog then return end
          log(("[Blaze][AUDIO] %s( %s | %s | %s | %s )"):format(m, tostring(a), tostring(b), tostring(c), tostring(d)))
        end)
      end)
    end
  end
  log("[Blaze] audio logger " .. (JL.audioLog and "ON — reproduce the music, watch console for [AUDIO] lines (then blazeStopMusicEvent('<name>'))." or "OFF."))
  return true
end

-- Stop a captured event CName (feed it what blazeLogAudio printed).
function blazeStopMusicEvent(name)
  if not name or name == "" then log("[Blaze] stopMusicEvent: pass the captured event name string."); return false end
  local ok = false
  pcall(function() Game.GetAudioSystem():Stop(CName.new(name), Game.GetPlayer():GetEntityID(), CName.new("")); ok = true end)
  log("[Blaze] stopMusicEvent: Stop('" .. tostring(name) .. "') -> " .. tostring(ok) .. " — did the music stop?")
  return ok
end

-- (B) GUARANTEED silence: MusicVolume -> 0 (on) / restore (off). Kills ALL music engine-wide, so it's a
-- toggle. Saves the prior value to restore. This is the reliable finale fix if the event can't be captured.
function blazeMuteMusic(on)
  if on == nil then on = true end
  local ss; pcall(function() ss = Game.GetSettingsSystem() end)
  if not ss then log("[Blaze] muteMusic: no SettingsSystem."); return false end
  local v; pcall(function() v = ss:GetVar("/audio/volume", "MusicVolume") end)
  if not v then log("[Blaze] muteMusic: MusicVolume var not found (try DumpType in console)."); return false end
  if on then
    if JL.musicVolSaved == nil then pcall(function() JL.musicVolSaved = v:GetValue() end) end
    pcall(function() v:SetValue(0) end)
    log("[Blaze] muteMusic: MusicVolume -> 0 (was " .. tostring(JL.musicVolSaved) .. "). Restore with blazeMuteMusic(false).")
  else
    local restore = JL.musicVolSaved or 100
    pcall(function() v:SetValue(restore) end)
    JL.musicVolSaved = nil
    log("[Blaze] muteMusic: MusicVolume restored -> " .. tostring(restore) .. ".")
  end
  return true
end

-- The combined at-black teardown the finale runs (music reset + combat clear, and scene fast-forward
-- when Blaze.cfg.endSceneOnFinale). Order: clear combat first (so the mix re-evaluates clean), then music,
-- then end the scene. Each layer is independently guarded. v1.11: also MUTE music at the finale when
-- Blaze.cfg.muteMusicOnFinale (default true) — the only guaranteed way to kill the stuck q005 bed.
function blazeFinaleTeardown()
  pcall(blazeClearCombat)
  pcall(blazeStopMusic)
  if Blaze and Blaze.cfg and Blaze.cfg.endSceneOnFinale ~= false then pcall(blazeEndScene) end
  if not (Blaze and Blaze.cfg and Blaze.cfg.muteMusicOnFinale == false) then pcall(function() blazeMuteMusic(true) end) end
end

-- v1.07 BLAZE (Antonia): force SUNNY weather once Smasher's down + V reaches the heli. Weather is
-- version-finicky, so this is the helper the overlay's A/B buttons + the auto-trigger both call. Priority
-- must beat the heist's stormy state (3 is high). ⚠️ The heist is at NIGHT — "sunny" clears the sky but
-- you still need DAYTIME for actual sun; use blazeSetMidday() (overlay button) alongside it. Globals => 200-cap safe.
BLAZE_WEATHER_SUN = "24h_weather_sunny"
function blazeSetWeather(state, transition, priority)
  state = state or BLAZE_WEATHER_SUN
  local ws; pcall(function() ws = Game.GetWeatherSystem() end)
  if not ws then log("[Blaze] weather: no WeatherSystem."); return false end
  local ok = false
  pcall(function() ws:SetWeather(state, transition or 8.0, priority or 3); ok = true end)   -- string auto-converts to CName
  if not ok then pcall(function() ws:SetWeather(CName.new(state), transition or 8.0, priority or 3); ok = true end) end
  log(("[Blaze] weather: SetWeather('%s', %s, prio %s) -> %s"):format(tostring(state), tostring(transition or 8.0), tostring(priority or 3), tostring(ok)))
  return ok
end
function blazeResetWeather()
  local ws; pcall(function() ws = Game.GetWeatherSystem() end)
  if not ws then return false end
  local ok = false
  pcall(function() ws:ResetWeather(true); ok = true end)
  log("[Blaze] weather: ResetWeather(true) -> " .. tostring(ok) .. " (back to the natural cycle).")
  return ok
end
-- Jump the clock to midday so "sunny" actually reads as sunshine (the heist is a night scene).
--
-- ⚠️ v1.44: this SHOVES THE GAME CLOCK FORWARD, typically ~10 h (the heist runs at night). Jackie's
-- companion-duration clock (`JL.summon.companionExpiresGame`) is measured in ABSOLUTE game seconds, so a
-- jump like this instantly blows past `maxGameHours` (6 h) and the auto-leave fires: he says his parting
-- line and walks off — right before the finale, where he then failed to appear. The escape sequence calls
-- this, so it broke its own finale.
--
-- We can't call armCompanionTimer() from here (it's a main-chunk local declared further down, so it isn't
-- in scope at this point in the file). Instead raise a flag; onUpdate re-arms the clock on the next tick,
-- once the new time is live. That keeps the fix working for the overlay's "Set time -> midday" button too,
-- not just the scripted escape.
function blazeSetMidday(hour)
  local ts; pcall(function() ts = Game.GetTimeSystem() end)
  if not ts then log("[Blaze] time: no TimeSystem."); return false end
  local ok = false
  pcall(function() ts:SetGameTimeByHMS(hour or 12, 0, 0); ok = true end)
  if ok then JL.rearmCompanionClock = true end   -- the jump must not count against his time with V
  log("[Blaze] time: SetGameTimeByHMS(" .. tostring(hour or 12) .. ",0,0) -> " .. tostring(ok))
  return ok
end

local function resolveJackieRecord()
  if JL.jackie.record then return true end

  -- 1) hardcoded in config (best — set after discovery)
  if Config.jackieRecord and Config.jackieRecord ~= "" then
    JL.jackie.record = Config.jackieRecord
    JL.jackie.name   = Config.jackieName or "Jackie"
    log("Using config.jackieRecord = '" .. tostring(JL.jackie.record) .. "'")
    return true
  end

  -- 2) AMM's small custom list (rarely contains base-game Jackie, but cheap to check)
  local chars = getAMMCharacters()
  if chars then
    for _, c in pairs(chars) do
      local fields = entryFields(c)
      local hit = false
      for _, f in ipairs(fields) do
        if f and tostring(f):lower():find("jackie") then hit = true; break end
      end
      if hit then
        local rec, nm
        for _, f in ipairs(fields) do
          local s = tostring(f)
          if looksLikeRecord(s) and not rec then rec = s
          elseif not nm and not looksLikeRecord(s) then nm = s end
        end
        JL.jackie.record, JL.jackie.name = rec or nm, nm or "Jackie"
        log("Found Jackie in custom list -> record='" .. tostring(JL.jackie.record) .. "'")
        return true
      end
    end
  end

  -- 3) discover from a Jackie already spawned via AMM's menu
  if discoverJackieFromSpawned(false) then return true end

  log("Jackie record not found. Spawn him via AMM's menu, then click 'Find Jackie'.")
  return false
end

-- ---------------------------------------------------------------------------
-- Diagnostics (dumps the exact shapes we need to see)
-- ---------------------------------------------------------------------------
function diagnostics()   -- global (not local): 200-local cap; see note at top
  log("----- DIAGNOSTICS -----")
  local amm = getAMM()
  log("AMM=" .. tostring(amm ~= nil) ..
      "  Spawn=" .. tostring(amm and amm.Spawn ~= nil) ..
      "  API=" .. tostring(amm and amm.API ~= nil))
  local chars = getAMMCharacters()
  if chars then
    local total = 0; for _ in pairs(chars) do total = total + 1 end
    log("GetAMMCharacters total = " .. total)
    local i = 0
    for k, c in pairs(chars) do
      i = i + 1
      if type(c) == "table" then
        log(string.format("  [%s] name=%s record=%s id=%s [1]=%s [2]=%s",
          tostring(k), tostring(c.name), tostring(c.record), tostring(c.id),
          tostring(c[1]), tostring(c[2])))
      else
        log(string.format("  [%s] = %s", tostring(k), tostring(c)))
      end
      if i >= 12 then break end
    end
  else
    log("GetAMMCharacters returned nothing usable.")
  end
  -- spawned NPCs (this is where we discover base-game Jackie's record)
  if amm and amm.Spawn and amm.Spawn.spawnedNPCs then
    local n = 0
    for _, sp in pairs(amm.Spawn.spawnedNPCs) do
      n = n + 1
      log(string.format("  spawned[%d]: name=%s path=%s", n, tostring(sp.name), tostring(sp.path or sp.id)))
      if n >= 12 then break end
    end
    log("AMM spawnedNPCs count = " .. n)
  else
    log("AMM.Spawn.spawnedNPCs not available.")
  end
  -- time probe (find which method returns the hour)
  local ts = Game.GetTimeSystem()
  local gt; pcall(function() gt = ts:GetGameTime() end)
  log("GetGameTime type=" .. type(gt) .. " value=" .. tostring(gt))
  for _, m in ipairs({ "GetHour", "GetHours", "ToSeconds", "GetSeconds", "GetMinute" }) do
    local r; pcall(function() local f = gt and gt[m]; if f then r = f(gt) end end)
    log("  time." .. m .. " -> " .. tostring(r))
  end
  log("----- END -----")
end

-- ---------------------------------------------------------------------------
-- Spawn helpers (delegate to AMM's proven spawn/companion path)
-- ---------------------------------------------------------------------------
-- companionFlag: 1 = follow + fight as ally, 0 = passive idle NPC
-- appearance: AMM appearance name to spawn him in (e.g. "suit"); nil/"" -> Config.defaultAppearance.
--
-- ⚠️ v1.43 — THE OUTFIT BUG. AMM's `Spawn:NewSpawn(name, id, parameters, companion, path, template, rig)`
-- wants `parameters` to be the appearance-name **STRING**, not a table. We were passing `{ app = app }`.
-- AMM stores it verbatim on `spawn.parameters`, and `SpawnNPC` later does
--     if #custom > 0 or spawn.parameters ~= nil then AMM:ChangeAppearanceTo(spawn, spawn.parameters)
-- which bottoms out in `handle:PrefetchAppearanceChange(x)` / `handle:ScheduleAppearanceChange(x)`. Handed
-- a TABLE where a CName is required, both calls silently no-op and Jackie keeps his record default. (AMM's
-- own `obj.appearanceName = (parameters or {}).app` line reads our `.app` key — but that field is written
-- and never read anywhere in AMM. It's a dead end, which is why this looked plausible and never worked.)
-- Net effect: NO appearance we ever asked for was applied — not the heist suit, not the venue outfits.
-- Three of his seven venues use `jackie_welles_default` anyway, which is why it went unnoticed for so long.
local function ammSpawn(companionFlag, appearance)
  local amm = getAMM()
  if not amm or not amm.Spawn or not amm.Spawn.NewSpawn then return nil, "AMM Spawn module not available" end
  if not resolveJackieRecord() then return nil, "Jackie record not found" end
  local recStr = tostring(JL.jackie.record)
  -- Fall back to a REAL appearance name, never "random": an unknown name is a silent no-op (leaving him in
  -- whatever he had), and AMM's random-cycle path would put him in a different outfit every spawn.
  local app = (appearance and appearance ~= "") and appearance or (Config.defaultAppearance or "jackie_welles_default")
  -- Force AMM's companion toggle to MATCH the flag. It was only ever set TRUE (for companion
  -- spawns) and never reset, so a "passive" arrival spawn following any companion summon still
  -- came out as a companion -> follower role -> catch-up TELEPORT to V's face. Resetting it to
  -- false makes companionFlag 0 truly passive (no follower role, no teleport).
  pcall(function() if amm.userSettings then amm.userSettings.spawnAsCompanion = (companionFlag == 1) end end)
  local spawn
  Session.mark("AMM NewSpawn " .. tostring(app))
  local ok = pcall(function()
    -- arg 3 = the appearance NAME AS A STRING (see the note above). arg 5 (`path`) is the record that
    -- actually spawns; arg 2 (`id`) is only AMM's bookkeeping key, so the record string is harmless there.
    spawn = amm.Spawn:NewSpawn(JL.jackie.name or "Jackie", recStr, app, companionFlag, recStr)
  end)
  Session.clear()
  if not ok or not spawn then return nil, "NewSpawn failed" end
  Session.mark("AMM SpawnNPC")
  local ok2 = pcall(function() amm.Spawn:SpawnNPC(spawn) end)
  Session.clear()
  if not ok2 then return nil, "SpawnNPC failed" end
  -- v1.52: stamp the record with the session that created it. Session.stale() reads this to know the
  -- handle is a dead pointer after a load, so callers drop it instead of dereferencing it.
  Session.stamp(spawn)
  -- v1.43: REMEMBER what the companion is wearing. Every companion respawn (culled body, stranded
  -- fast-travel) used to call ammSpawn(1) with no appearance and silently put him back in
  -- Config.defaultAppearance — which is why the Blaze heist Jackie lost his suit at Konpeki, where
  -- streaming/cutscenes cull him constantly. Recording the RESOLVED name (not the arg) means a nil
  -- arg records "default", so a plain summon still reads back correctly.
  if companionFlag == 1 then JL.summon.appearance = app end
  return spawn
end

-- v1.43: the outfit a respawned COMPANION should come back in — whatever he was last spawned wearing,
-- falling back to his normal clothes. GLOBAL -> costs no top-level local (200-cap).
function jlCompanionAppearance()
  return JL.summon.appearance or Config.defaultAppearance or "jackie_welles_default"
end

local function ammDespawn(spawn)
  if not spawn then return end
  local amm = getAMM()
  -- 1) let AMM remove it (it owns the spawn record)
  pcall(function() if amm and amm.Spawn and amm.Spawn.DespawnNPC then amm.Spawn:DespawnNPC(spawn) end end)
  -- 2) delete via the DYNAMIC-ENTITY id we got from CreateEntity (vehicle-arrival Jackie is spawned
  --    that way -> JL.summon.spawn.id). This is the reliable handle for DES entities; deleting via
  --    handle:GetEntityID() below can MISS for them, which left dismissed bike-Jackies un-despawned.
  pcall(function()
    if spawn.id then
      local des = Game.GetDynamicEntitySystem()
      if des then des:DeleteEntity(spawn.id) end
    end
  end)
  -- 3) delete the entity directly via its runtime entity id (AMM-spawned path)
  pcall(function()
    local h = spawn.handle
    if h and h.GetEntityID then
      local des = Game.GetDynamicEntitySystem()
      if des then des:DeleteEntity(h:GetEntityID()) end
    end
  end)
  -- 4) last resort
  pcall(function() if spawn.handle and spawn.handle.Dispose then spawn.handle:Dispose() end end)
end

-- ---------------------------------------------------------------------------
-- Main-quest ban. We read the player's CURRENTLY TRACKED journal quest (the one the HUD
-- objective tracker is showing) and check whether it's a MAIN quest. Main quests have
-- gameJournalQuestType.MainQuest; side jobs / NCPD / minor are other types. So: V tracking a
-- main quest -> Jackie won't be pulled in (declines a summon, and excuses himself if already
-- tagging along). Everything is pcall-guarded and defaults to "not main" so a reflection
-- hiccup can never wrongly strand or block him. Result is cached for ~0.5 s so we don't walk
-- the journal every frame (isMainQuestActive is polled from onUpdate + several buttons).
local mq = { val = false, checkedAt = -999 }

-- True if `entry` (or any parent up the journal tree) is a main-type quest.
local function entryIsMainQuest(jm, entry)
  local hops = 0
  while entry and hops < 8 do
    hops = hops + 1
    local cls; pcall(function() cls = entry:GetClassName().value end)
    if cls == "gameJournalQuest" then
      -- read the quest type; match by NAME so we're robust to the enum's exact spelling/order
      local isMain = false
      pcall(function()
        local t = entry:GetType()                      -- gameJournalQuestType
        local s = tostring(t)
        isMain = s:find("Main") ~= nil                 -- "MainQuest" / "gameJournalQuestType.MainQuest"
      end)
      return isMain
    end
    local parent; pcall(function() parent = jm:GetParentEntry(entry) end)
    entry = parent
  end
  return false
end

local function isMainQuestActive()
  if JL.allowMainGigs then return false end             -- v1.32: player opted Jackie INTO main missions (Esc-menu toggle, not recommended)
  if JL.ui.forceMainQuest then return true end          -- debug override (CET checkbox)
  local now = JL.clock or 0
  if (now - mq.checkedAt) < 0.5 then return mq.val end   -- cached
  mq.checkedAt = now
  local active = false
  pcall(function()
    local jm = Game.GetJournalManager()
    if not jm then return end
    local tracked; pcall(function() tracked = jm:GetTrackedEntry() end)
    if tracked then active = entryIsMainQuest(jm, tracked) end
  end)
  mq.val = active
  return active
end

-- ---------------------------------------------------------------------------
-- Summon / dismiss
-- ---------------------------------------------------------------------------
local function summonJackie()
  if not Retrieval.isUnlocked() then JL.ui.status = Retrieval.unavailableMsg(); Retrieval.notifyUnavailable(); return end  -- gated until the retrieval quest is done
  if isMainQuestActive() then jlDeclineMainQuest(); return end
  if JL.summon.active then JL.ui.status = "Jackie is already with you."; return end
  local spawn, err = ammSpawn(1)
  if not spawn then JL.ui.status = "Summon failed: " .. tostring(err); log("Summon failed: " .. tostring(err)); return end
  JL.summon.spawn, JL.summon.active, JL.summon.companionSet = spawn, true, false
  JL.ui.status = "Summoning Jackie..."
  log("Summon requested.")
end

-- v0.34: clear the vehicle-arrival state + despawn its bike (inline so the early dismiss
-- functions don't depend on the vehicle helpers defined far below).
local function clearVehicleArrival()
  if JL.varrival.bikeId then
    pcall(function() local des = Game.GetDynamicEntitySystem(); if des then des:DeleteEntity(JL.varrival.bikeId) end end)
  end
  JL.varrival.at, JL.varrival.phase, JL.varrival.bikeId, JL.varrival.bikeHandle = nil, nil, nil, nil
  JL.varrival.placeAt, JL.varrival.driveAt, JL.varrival.sprintAt, JL.varrival.deadline, JL.varrival.driveCmd = nil, nil, nil, nil, nil
  JL.varrival.footFallbackAt, JL.varrival.footTried, JL.varrival.useBike = nil, nil, nil   -- v0.38 fallback / v0.46 bike flag
  JL.varrival.closestD, JL.varrival.lastProgressT, JL.varrival.rungIdx = nil, nil, nil      -- v0.51 stuck-respawn tracker
  JL.varrival.pingAt, JL.varrival.slowedLogged = nil, nil
end

local function dismissJackie()
  setCompanionFlag(false)   -- v0.72: V let him go -> clear the persisted companion intent
  if JL.summon.spawn then ammDespawn(JL.summon.spawn) end
  JL.summon.spawn, JL.summon.active, JL.summon.companionSet, JL.summon.walkIn = nil, false, false, false
  JL.summon.companionSinceGame, JL.summon.companionExpiresGame = nil, nil   -- v0.39: reset duration clock
  JL.summon.arrivalGreetPending = false   -- v0.46/v0.48: cancel a pending arrival greeting
  JL.arrival.at, JL.arrival.phase, JL.arrival.placeAt, JL.arrival.moveAt, JL.arrival.deadline = nil, nil, nil, nil, nil
  JL.leaving.phase, JL.leaving.deadline = nil, nil   -- v0.33: cancel any in-progress walk-off
  clearVehicleArrival()
  JL.ui.status = "Jackie dismissed."
  log("Dismissed.")
end

-- Despawn EVERY Jackie AMM knows about (clears orphans from failed dismisses / mod reloads).
function dismissAllJackies()   -- global (not local): 200-local cap; see note at top
  setCompanionFlag(false)   -- v0.72: a full wipe clears the persisted companion intent too
  local amm = getAMM()
  local n = 0
  if amm and amm.Spawn and amm.Spawn.spawnedNPCs then
    for _, sp in pairs(amm.Spawn.spawnedNPCs) do
      local nm   = tostring(sp.name or "")
      local path = tostring(sp.path or sp.id or "")
      if nm:lower():find("jackie") or path:lower():find("jackie") then
        ammDespawn(sp); n = n + 1
      end
    end
  end
  if JL.summon.spawn then ammDespawn(JL.summon.spawn) end
  if JL.idle.spawn then ammDespawn(JL.idle.spawn) end
  JL.summon.spawn, JL.summon.active, JL.summon.companionSet, JL.summon.walkIn = nil, false, false, false
  JL.summon.companionSinceGame, JL.summon.companionExpiresGame = nil, nil   -- v0.39: reset duration clock
  JL.idle.spawn, JL.idle.locationKey = nil, nil
  JL.arrival.at, JL.arrival.phase, JL.arrival.placeAt, JL.arrival.moveAt, JL.arrival.deadline = nil, nil, nil, nil, nil
  JL.leaving.phase, JL.leaving.deadline = nil, nil   -- v0.33
  clearVehicleArrival()
  pcall(function() if jlCruise and jlCruise.active then jlCruiseStop() end end)  -- v0.92: kill any cruise Arch
  JL.ui.status = "Dismissed all Jackies (" .. n .. " tracked by AMM)."
  log("Dismiss ALL: " .. n .. " Jackie(s).")
end

-- ---------------------------------------------------------------------------
-- Voice-over playback test (v0.4): prove we can make Jackie speak on command
-- ---------------------------------------------------------------------------
local function getTalkTarget()
  if JL.summon.spawn and JL.summon.spawn.handle then return JL.summon.spawn.handle, "summon" end
  if JL.idle.spawn and JL.idle.spawn.handle then return JL.idle.spawn.handle, "idle" end
  local h
  pcall(function()
    local ts = Game.GetTargetingSystem()
    if ts then h = ts:GetLookAtObject(Game.GetPlayer(), false, false) end
  end)
  -- never treat a VEHICLE as a talk target (Jackie's Arch record contains "jackie"). See lookedAtJackie.
  if h then
    local isVeh = false
    pcall(function() isVeh = tostring(h:GetClassName()):lower():find("vehicle") ~= nil end)
    if not isVeh then return h, "lookat" end
  end
  return Game.GetPlayer(), "player"
end

-- Play a sound event on an entity via the audio system (the method working dialogue mods use).
local function playEventOn(target, eventName, emitter)
  if not target then return false, "no target" end
  local audio = Game.GetAudioSystem()
  if not audio then return false, "no AudioSystem" end
  local ok, err = pcall(function()
    audio:Play(CName.new(eventName), target:GetEntityID(), CName.new(emitter or ""))
  end)
  return ok, err
end


-- ---------------------------------------------------------------------------
-- Time + position
-- ---------------------------------------------------------------------------
local function callMethod(obj, name)
  local r
  pcall(function() local f = obj[name]; if f then r = f(obj) end end)
  return r
end

-- Returns a FRACTIONAL hour (e.g. 23.5 = 23:30) so the schedule supports half-hour blocks
-- (the Coyote wind-down). Hour from GetHour + minutes/60; falls back to seconds-of-day.
local function getGameHour()
  local ts = Game.GetTimeSystem(); if not ts then return nil end
  local gt; pcall(function() gt = ts:GetGameTime() end)
  if gt == nil then return nil end
  -- direct hour methods (+ minutes for sub-hour resolution)
  for _, m in ipairs({ "GetHour", "GetHours" }) do
    local r = callMethod(gt, m)
    if type(r) == "number" then
      local minute = 0
      for _, mm in ipairs({ "GetMinute", "GetMinutes" }) do
        local rm = callMethod(gt, mm)
        if type(rm) == "number" then minute = rm % 60; break end
      end
      return (r % 24) + minute / 60
    end
  end
  -- seconds-of-day methods (already sub-hour precise)
  for _, m in ipairs({ "ToSeconds", "GetSeconds", "GetTotalSeconds" }) do
    local r = callMethod(gt, m)
    if type(r) == "number" then return (r % 86400) / 3600 end
  end
  return nil
end

-- v0.39: MONOTONIC total in-game time in SECONDS (across days), for measuring companion duration.
-- GetGameTime():ToSeconds() returns total game seconds (getGameHour mods it by a day for the clock).
local function getGameSeconds()
  local ts = Game.GetTimeSystem(); if not ts then return nil end
  local gt; pcall(function() gt = ts:GetGameTime() end)
  if gt == nil then return nil end
  for _, m in ipairs({ "ToSeconds", "GetTotalSeconds", "GetSeconds" }) do
    local r = callMethod(gt, m)
    if type(r) == "number" then return r end
  end
  return nil
end

-- ===========================================================================
-- v1.45 WATSON BARRIER HOLD. Blaze opens Watson by setting the prologue-lockdown facts directly
-- (`watson_prolog_unlock=1`, `watson_prolog_lock=0`) — the placed barrier reads them, and vanilla only
-- sets them deep inside q101, which this what-if never runs. Without them V can't cross the bridges.
--
-- That used to be a ONE-SHOT write inside the finale's at-black callback: no read-back, no re-assert. Two
-- ways that loses the bridges: the callback never runs (fade path failed), or the quest system flips
-- `watson_prolog_lock` back later. The latter is not hypothetical — jlMourningApply exists precisely
-- because "the quest system flips facts back up", and it re-asserts every 5 s for that reason.
--
-- So: we stamp our OWN save-persistent marker fact (`jl_watson_open`) when we open Watson, and from then
-- on a cheap tick re-asserts the two barrier facts whenever they drift. It runs in BOTH story modes, so
-- switching back to Quiet Life after Blaze cannot strand V behind the bridges.
-- GLOBAL -> costs no top-level local (200-cap).

-- `open` = true stamps the marker (call this when Blaze actually opens Watson). Otherwise this only
-- re-asserts for a save that has already been marked, so it can never open Watson on a vanilla run.
function jlWatsonApply(open)
  local qs; pcall(function() qs = Game.GetQuestsSystem() end)
  if not qs then return false end
  local marked, fixed = false, false
  pcall(function()
    if open then qs:SetFactStr("jl_watson_open", 1) end
    marked = ((qs:GetFactStr("jl_watson_open") or 0) == 1)
  end)
  if not marked then return false end
  pcall(function()
    if (qs:GetFactStr("watson_prolog_unlock") or 0) ~= 1 then qs:SetFactStr("watson_prolog_unlock", 1); fixed = true end
    if (qs:GetFactStr("watson_prolog_lock")   or 0) ~= 0 then qs:SetFactStr("watson_prolog_lock",   0); fixed = true end
  end)
  if open then
    log("[Blaze] world unlock -> watson_prolog_unlock=1, watson_prolog_lock=0 (+ jl_watson_open marker).")
  elseif fixed then
    log("[Blaze] Watson barrier had drifted shut -> re-asserted (bridges open).")
  end
  return true
end

-- Cheap 5 s heartbeat, mirroring the mourning re-assert. Self-guards: no marker -> instant no-op.
function jlWatsonHoldTick(dt)
  JL.watsonTimer = (JL.watsonTimer or 0) + (dt or 0)
  if JL.watsonTimer < 5.0 then return end
  JL.watsonTimer = 0
  pcall(function() jlWatsonApply(false) end)
end

-- v1.44: is the Blaze set-piece (or its finale) actually PLAYING right now? Used to suspend Quiet-Life
-- rules that would otherwise pull Jackie out of the scene — chiefly the companion-duration auto-leave.
-- Deliberately NOT `JL.mode == "blaze"`: that stays true for the rest of the save, so it would disable his
-- going-home behaviour permanently on a Blaze playthrough. `Blaze.reset()` nils `st`, and the finale tick
-- nils `JL.blazeFinale` when the conversation ends, so this goes false again the moment the scene is done.
-- GLOBAL -> costs no top-level local (200-cap). pcall-guarded: Blaze may not be loaded.
function jlBlazeSceneLive()
  if JL.blazeFinale then return true end
  local live = false
  pcall(function() live = (Blaze and Blaze.st and Blaze.st.active) and true or false end)
  return live
end

-- v1.41: ABSOLUTE in-game day index (0,1,2...) from the monotonic game clock. Used for once-per-day
-- gates. Deliberately NOT JL.day.count: that only advances when ensureDayTemplate catches the hour
-- WRAPPING past midnight, so a flat 24 h sleep (10:00 -> 10:00) never decreases the hour and would be
-- missed. Total-seconds / 86400 can't miss a day. Returns nil if the TimeSystem isn't up yet (callers
-- must treat nil as "don't fire the daily thing"). GLOBAL -> costs no top-level local (200-cap).
function jlGameDay()
  local s = getGameSeconds()
  if not s then return nil end
  return math.floor(s / 86400.0)
end

-- v0.39: start (or restart) Jackie's companion-duration clock. Called when he becomes a companion
-- and again when a dinner resets it. Stores when he joined + when he'll head home (game seconds).
local function armCompanionTimer(extendHours)
  local g = getGameSeconds()
  local hrs = extendHours or (Config.companion and Config.companion.maxGameHours) or 6.0
  if not JL.summon.companionSinceGame then JL.summon.companionSinceGame = g end
  JL.summon.companionExpiresGame = g and (g + hrs * 3600) or nil
end

-- v0.39: is the dinner invite available yet? Gated by `unlockAfterGameHours` once enforceUnlock
-- is turned on; for now (enforceUnlock=false) it's always available.
local function dateUnlocked()
  local d = Config.date; if not d then return false end
  if not d.enforceUnlock then return true end
  local since, now = JL.summon.companionSinceGame, getGameSeconds()
  return (since and now and (now - since) >= (d.unlockAfterGameHours or 1.0) * 3600) or false
end

-- Fisher-Yates shuffle of the Config.dayBag keys into JL.day.bag, reset the read position.
local function reshuffleDayBag()
  local src = {}
  for _, k in ipairs(Config.dayBag or {}) do src[#src + 1] = k end
  for i = #src, 2, -1 do
    local j = math.random(1, i)
    src[i], src[j] = src[j], src[i]
  end
  JL.day.bag, JL.day.bagPos = src, 0
  log("Day bag reshuffled: " .. table.concat(src, ", "))
end

-- Pull the next day-type from the bag (reshuffling when empty), so each cycle uses every
-- day-type exactly once in random order (no skips).
local function nextDayTemplate()
  if not JL.day.bag or #JL.day.bag == 0 or JL.day.bagPos >= #JL.day.bag then reshuffleDayBag() end
  JL.day.bagPos = JL.day.bagPos + 1
  return JL.day.bag[JL.day.bagPos]
end

-- Advance to the next day-type whenever the game hour WRAPS (current < last = passed midnight).
-- Time only moves forward (sleeping / fast-travel included), so a decrease means a new day.
-- Returns the active day-type key; falls back to Config.fallbackDay if the hour can't be read.
local function ensureDayTemplate()
  local h = getGameHour()
  if h == nil then
    return JL.day.template or Config.fallbackDay or "active1"
  end
  if JL.day.template == nil then                         -- first run this session
    JL.day.template = nextDayTemplate()
    JL.day.lastHour = h
    log("Day 1 -> schedule '" .. tostring(JL.day.template) .. "'")
  elseif h < JL.day.lastHour then                        -- midnight wrap -> new day
    JL.day.count    = (JL.day.count or 0) + 1
    JL.day.template = nextDayTemplate()
    log("New day (#" .. tostring(JL.day.count + 1) .. ") -> schedule '" .. tostring(JL.day.template) .. "'")
  end
  JL.day.lastHour = h
  return JL.day.template
end

-- The schedule (list of blocks) for today's day-type.
local function activeSchedule()
  local key = ensureDayTemplate()
  local sched = Config.daySchedules and Config.daySchedules[key]
  if not sched then sched = Config.daySchedules and Config.daySchedules[Config.fallbackDay or "active1"] end
  return sched or {}
end

local function hourInBlock(h, s, e)
  if s <= e then return h >= s and h < e else return h >= s or h < e end
end

local function currentScheduleBlock()
  local h = getGameHour(); if not h then return nil, nil end
  for _, b in ipairs(activeSchedule()) do
    if hourInBlock(h, b.startHour, b.endHour) then
      -- v1.55 (Husbando only): once Jackie has been to Misty's ONCE, that's where they break up — and he
      -- never goes back. Every later Misty slot in the schedule becomes the noodle bar instead. Hermano is
      -- untouched: there they're solid, and he keeps his standing visit.
      -- Return a COPY — the schedule blocks are shared Config tables and must never be mutated in place,
      -- or one swap would permanently rewrite the schedule for the whole session (Hermano included).
      if b.state == "at_location"
         and b.locationKey == (Config.mistyKey or "misty")
         and jlMistyRetired() then
        local c = {}; for k, v in pairs(b) do c[k] = v end
        c.locationKey = Config.mistyReplacementKey or "noodle"
        return c, h
      end
      return b, h
    end
  end
  return nil, h
end

-- v0.55: is Jackie asleep right now? True during his nightly sleep window (Config.secret
-- startHour..endHour, default 00:00-06:00). Calls placed while he's asleep don't connect — the
-- phone just rings out (he doesn't pick up). Independent of where the schedule has him.
local function jackieAsleep()
  local S = Config.secret
  local h = getGameHour()
  if not h or not S then return false end
  return hourInBlock(h, S.startHour or 0, S.endHour or 6)
end

local function playerPos()
  local p = Game.GetPlayer(); if not p then return nil end
  return p:GetWorldPosition()
end

local function dist3(a, b)
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function capturePosition()   -- global (not local): 200-local cap; see note at top
  local p = Game.GetPlayer(); if not p then log("No player."); return end
  local pos = p:GetWorldPosition()
  local yaw = 0.0
  pcall(function() yaw = p:GetWorldOrientation():ToEulerAngles().yaw end)
  local line = string.format("pos = { %.3f, %.3f, %.3f }, yaw = %.1f", pos.x, pos.y, pos.z, yaw)
  JL.ui.lastCapture = line
  log("Captured -> " .. line)
end

-- ---------------------------------------------------------------------------
-- Talk to Jackie: look at him + press the bound "Talk to Jackie" key -> he says
-- a random line (chance + cooldown). Plays via the same VO path as the test.
-- (A fully native dialogue-choice prompt is a heavier future upgrade — see README.)
-- ---------------------------------------------------------------------------
local function sameEntity(a, b)
  if not a or not b then return false end
  local eq = false
  pcall(function() eq = a:GetEntityID().hash == b:GetEntityID().hash end)
  return eq
end

local function lookedAtJackie()
  local player = Game.GetPlayer(); if not player then return nil end
  local target
  pcall(function()
    local ts = Game.GetTargetingSystem()
    if ts then target = ts:GetLookAtObject(player, false, false) end
  end)
  if not target then return nil end
  if JL.summon.spawn and sameEntity(target, JL.summon.spawn.handle) then return target end
  if JL.idle.spawn and sameEntity(target, JL.idle.spawn.handle) then return target end
  local isJackie = false
  pcall(function()
    -- NEVER match a vehicle: Jackie's Arch record is "Vehicle.v_sportbike2_arch_jackie_player",
    -- which also contains "jackie" — looking at his bike must NOT open a talk prompt. (bug 2026-07-04)
    local cn = tostring(target:GetClassName()):lower()
    if cn:find("vehicle") then return end
    local rec = target.GetRecordID and target:GetRecordID()
    if rec and tostring(rec):lower():find("jackie") then isJackie = true end
  end)
  return isJackie and target or nil
end

local function pickLine(pool)
  local lines = (Config.talkLines and Config.talkLines[pool]) or {}
  if #lines == 0 then return nil end
  return lines[math.random(1, #lines)]
end

local function talkToJackie()
  local jackie = lookedAtJackie()
  if not jackie then return end                       -- only when you're looking at him
  local now = JL.clock or 0
  if (now - (JL.lastTalk or -999)) < (Config.talk and Config.talk.cooldown or 1.5) then return end

  -- distance gate
  local pp = playerPos()
  if pp then
    local jp; pcall(function() jp = jackie:GetWorldPosition() end)
    if jp and dist3(pp, jp) > (Config.talk and Config.talk.range or 4.0) then return end
  end

  JL.lastTalk = now
  -- 5% -> rare pool, otherwise common pool
  local pool = (math.random() < (Config.talk and Config.talk.rareChance or 0.05)) and "rare" or "common"
  local event = pickLine(pool)
  if not event then JL.ui.status = "No talk lines for '" .. pool .. "' (fill Config.talkLines)."; return end
  playEventOn(jackie, event, (Config.talkTest and Config.talkTest.emitter) or "")
  JL.ui.status = "Jackie (" .. pool .. "): " .. event
  log("Talk -> " .. pool .. " '" .. event .. "'")
end

-- ---------------------------------------------------------------------------
-- v0.15: trigger Talk-to-Jackie on the game's NATIVE interact key (F), with NO
-- CET binding. CET can't *bind* F (the game reserves it for Interact), but it CAN
-- *observe* the player's input handler: PlayerPuppet:OnAction is a scripted method,
-- so Observe hooks it (same mechanism we used for the subtitle controller). We watch
-- for the interact/choice action being pressed and, if you're looking at Jackie in
-- range, fire the same talkToJackie() path. Press F -> Jackie talks. No binding.
--
-- If F doesn't trigger on first test, flip Config.talk.logActions = true, press F
-- near Jackie, and paste the "[JackieLives] OnAction:" lines - they print the exact
-- action name this game build uses for interact, and I'll add it to INTERACT_ACTIONS.
-- ---------------------------------------------------------------------------
local interactHook = { registered = false }

-- Forward declarations: defined after the dialogue runner below, but referenced by the
-- interact hook above as upvalues. `Branch` is a TABLE (captured once) whose method fields
-- are filled in later - so the hook can call Branch.start()/Branch.confirm() safely.
local startLinearDialogue
local startLeaving                 -- v0.33: "send Jackie off"; defined after the move helpers below
local returnToPost                 -- v0.40: dismiss near his venue -> walk back + go idle (defined late)
local unmountDriver                -- v0.62: bike-seat unmount; defined w/ the vehicle helpers, used early by promoteToCompanion's safety dismount
local Branch = { open = false }

-- Action names the interact / choice-confirm key (F by default) fires under. We accept
-- several because the exact CName varies by build; harmless extras just never match.
local INTERACT_ACTIONS = {
  ["Interact"] = true, ["Choice1"] = true, ["UI_Apply"] = true,
  ["click"] = false,                      -- (placeholder; mouse, ignore)
}

-- v0.33: move the highlighted choice with the ARROW keys (no CET binding needed). The exact
-- action CName the arrows fire under varies by build, so we accept several candidates and also
-- log unknown names while the box is open (Config.dialogue.cycleDebug) to confirm/extend these.
-- NOTE: arrow keys must emit a game input action on this build for this to fire; the bound
-- "Jackie dialogue: next choice" input remains as a guaranteed fallback either way.
-- v0.41: names CONFIRMED in-game on this build (deeper-layer release burst): up_button, popup_moveUp,
-- popup_navigate_up, navigate_up (+ UI_MoveUp). Kept the older speculative candidates too — harmless.
local CYCLE_UP_ACTIONS = {
  ["UI_MoveUp"] = true, ["up_button"] = true, ["popup_moveUp"] = true,
  ["popup_navigate_up"] = true, ["navigate_up"] = true,
  ["MoveUp"] = true, ["up"] = true, ["UI_Up"] = true,
  ["menu_up"] = true, ["ChoiceScrollUp"] = true, ["NavigateUp"] = true, ["IK_Up"] = true,
}
local CYCLE_DOWN_ACTIONS = {
  ["UI_MoveDown"] = true, ["down_button"] = true, ["popup_moveDown"] = true,
  ["popup_navigate_down"] = true, ["navigate_down"] = true,
  ["MoveDown"] = true, ["down"] = true, ["UI_Down"] = true,
  ["menu_down"] = true, ["ChoiceScrollDown"] = true, ["NavigateDown"] = true, ["IK_Down"] = true,
}

local function actionName(action)
  local n = "?"
  pcall(function() n = tostring(ListenerAction.GetName(action).value) end)
  if n == "?" then pcall(function() n = Game.NameToString(ListenerAction.GetName(action)) end) end
  return n
end

local function actionJustPressed(action)
  local pressed = false
  pcall(function() pressed = ListenerAction.IsButtonJustPressed(action) end)
  return pressed
end

-- v0.40: the action's TYPE (BUTTON_PRESSED / AXIS_CHANGE / ...) and analog VALUE. Used only by the
-- cycle-debug log so we can see whether deeper dialogue layers deliver the arrows as a button or an
-- axis (a button name we add to CYCLE_*; an axis needs different handling).
local function actionType(action)
  local t = "?"
  pcall(function() t = tostring(ListenerAction.GetType(action).value) end)
  if t == "?" then pcall(function() t = tostring(ListenerAction.GetType(action)) end) end
  return t
end

local function actionValue(action)
  local v
  pcall(function() v = ListenerAction.GetValue(action) end)
  return v
end

-- v0.41: true on the key-RELEASE edge. On deeper dialogue layers the arrows reach us ONLY as
-- BUTTON_RELEASED (never just-pressed), so navigation keys off this. IsButtonJustReleased covers
-- most cases; the typed-RELEASED fallback catches the rest.
local function actionReleased(action)
  local r = false
  pcall(function() r = ListenerAction.IsButtonJustReleased(action) end)
  if not r and actionType(action) == "BUTTON_RELEASED" then r = true end
  return r
end

local function setupInteractHook()
  if interactHook.registered then return end
  local ok = pcall(function()
    Observe("PlayerPuppet", "OnAction", function(self, action, consumer)
      local name = actionName(action)
      -- While a choice menu is open: route navigation + selection.
      if Branch.open then
        -- v0.40 DEBUG: log EVERY action while the box is open (name + type + value), BEFORE the
        -- just-pressed gate, so arrows that arrive as an AXIS on deeper layers are visible too
        -- (the old log sat behind that gate and hid them). Turn cycleDebug off once locked.
        if Config.dialogue and Config.dialogue.cycleDebug then
          log(string.format("CYCLE action: %s  type=%s value=%s pressed=%s",
            tostring(name), tostring(actionType(action)), tostring(actionValue(action)),
            tostring(actionJustPressed(action))))
        end
        -- v0.41: NAVIGATION fires on the RELEASED edge. On the first choice layer the arrows arrive as
        -- BUTTON_PRESSED, but on DEEPER layers the dialog/popup input context delivers them ONLY as
        -- BUTTON_RELEASED (confirmed: up_button/UI_MoveUp/popup_moveUp/popup_navigate_up/navigate_up all
        -- arrive RELEASED, never just-pressed). RELEASE is the one edge present in EVERY context. A single
        -- press emits several matching names in one frame, so debounce to one move per ~0.12 s (collapses
        -- the same-frame burst; still lets distinct taps through).
        if actionReleased(action) and (CYCLE_UP_ACTIONS[name] or CYCLE_DOWN_ACTIONS[name]) then
          local now = JL.clock or 0
          if (now - (JL.lastCycle or -999)) >= 0.12 then
            JL.lastCycle = now
            if CYCLE_UP_ACTIONS[name] then pcall(function() Branch.move(-1) end)  -- v0.42: UP = toward top row
            else                           pcall(function() Branch.move(1)  end) end  -- DOWN = toward bottom row
          end
          return
        end
        -- SELECT stays on the press edge (F already works on every layer).
        if actionJustPressed(action) and INTERACT_ACTIONS[name] then pcall(function() Branch.confirm() end) end
        return
      end
      if not actionJustPressed(action) then return end
      if Config.talk and Config.talk.logActions then log("OnAction: " .. tostring(name)) end
      if not INTERACT_ACTIONS[name] then return end
      -- v1.0 BLAZE: at the "[F]: Get in the AV" escape moment, F triggers the final fade. Consumes the
      -- press so it doesn't also grunt/talk. No-op (returns false) any other time.
      if JL.mode == "blaze" then
        local consumed = false
        pcall(function() consumed = Blaze.tryEscapePress and Blaze.tryEscapePress() end)
        if consumed then return end
      end
      -- v0.32: try to start the location-based branching convo FIRST. Only if it doesn't
      -- start (not looking, busy, or the 'everywhere' tree is on its DONE cooldown) do we
      -- fall back to a one-off grunt. This both avoids grunt+dialogue overlapping AND gives
      -- the "just grunts during cooldown" behaviour for free.
      local started = false
      if Branch.kick then pcall(function() started = Branch.kick() end) end
      if not started then pcall(talkToJackie) end          -- grunt (look/range/cooldown gated inside)
    end)
  end)
  interactHook.registered = ok
  log("Interact hook (PlayerPuppet:OnAction) registered: " .. tostring(ok) ..
      (ok and "" or "  <- F-trigger unavailable; '=' fallback still works"))
end

-- ---------------------------------------------------------------------------
-- The REAL native choice BOX (v0.17), via the interaction blackboard.
-- Authoritative types/flow from the decompiled scripts (interactionData.script +
-- interactionsUI.script):
--   * The interactions UI controller registers a blackboard listener on the field
--     UIInteractions.InteractionChoiceHub. On change it runs OnUpdateInteraction,
--     casts the Variant to InteractionChoiceHubData, and builds the on-screen box.
--     => because it's a LISTENER, a Lua push to that field should trigger a real render
--        (NOT a widget-attach - that's why v0.13 failed; this is data-push).
--   * InteractionChoiceHubData = { id:Int32, flags, active:Bool, title:String,
--       choices:array<InteractionChoiceData>, timeProvider }
--   * InteractionChoiceData    = { inputAction:CName, localizedName:String,
--       type:ChoiceTypeWrapper, captionParts:InteractionChoiceCaption, ... }
-- v0.16's probe proved our first guess (gameinteractionsChoiceHubData / DialogChoiceHubs)
-- was wrong; these are the real names. Still fully pcall-guarded, so it can't crash.
-- OPEN QUESTION the test answers: does the box need an active world "visualizer"
-- (VisualizersInfo) to appear, or does pushing InteractionChoiceHub alone render it?
-- ---------------------------------------------------------------------------
local choiceBox = { shown = false, id = 7731, lastPush = -999 }

-- Reconnaissance: confirm the CORRECT interaction structs + blackboard field exist
-- in this build. Safe to run anytime; prints to console. Paste the lines to Claude.
function probeChoiceBoxAPI()   -- global (not local): 200-local cap; see note at top
  log("----- CHOICE-BOX PROBE v0.17 -----")
  local function tryNew(label, ctor)
    local ok = pcall(ctor)
    log("  type " .. label .. " : " .. (ok and "OK" or "MISSING"))
  end
  tryNew("InteractionChoiceHubData", function() return InteractionChoiceHubData.new() end)
  tryNew("InteractionChoiceData",    function() return InteractionChoiceData.new() end)
  tryNew("InteractionChoiceCaption", function() return InteractionChoiceCaption.new() end)
  pcall(function()
    local idef = GetAllBlackboardDefs().UIInteractions
    log("  UIInteractions def present: " .. tostring(idef ~= nil))
    for _, k in ipairs({ "InteractionChoiceHub", "VisualizersInfo", "ActiveChoiceHubID", "DialogChoiceHubs" }) do
      local present = false
      pcall(function() present = idef[k] ~= nil end)
      log("  field UIInteractions." .. k .. " : " .. tostring(present))
    end
  end)
  log("----- END PROBE -----")
end

-- Build a one-choice hub ("Talk") for Jackie. Returns the hub or nil.
-- (No captionParts on the first cut - localizedName alone; if the box appears but the
--  row is blank, we add the caption struct next.)
local function buildJackieHub()
  local hub
  pcall(function()
    hub        = InteractionChoiceHubData.new()
    hub.id     = choiceBox.id
    hub.active = true
    pcall(function() hub.title = "Jackie" end)
    local choice = InteractionChoiceData.new()
    pcall(function() choice.localizedName = "Talk" end)
    pcall(function() choice.inputAction   = CName.new("Choice1") end)
    hub.choices = { choice }
  end)
  return hub
end

-- Push the hub onto UIInteractions.InteractionChoiceHub (the field the controller listens to).
local function showJackieChoiceBox()
  local hub = buildJackieHub()
  if not hub then log("choice box: hub build failed - run Probe API"); return false end
  local pushed = false
  local ok = pcall(function()
    local idef = GetAllBlackboardDefs().UIInteractions
    local bb   = Game.GetBlackboardSystem():Get(idef)
    if not bb or not idef.InteractionChoiceHub then return end
    bb:SetVariant(idef.InteractionChoiceHub, ToVariant(hub), true)
    pushed = true
  end)
  local wasShown = choiceBox.shown
  choiceBox.shown = ok and pushed
  if choiceBox.shown then choiceBox.lastPush = JL.clock or 0 end
  -- log only on a state change (first show) or on failure - the box re-asserts every
  -- boxRefresh (~1s) while looking at Jackie, which was spamming the console every second.
  if (choiceBox.shown and not wasShown) or not ok then
    log("choice box: show -> ok=" .. tostring(ok) .. " pushed=" .. tostring(pushed))
  end
  return choiceBox.shown
end

local function hideJackieChoiceBox()
  if not choiceBox.shown then return end
  pcall(function()
    local idef = GetAllBlackboardDefs().UIInteractions
    local bb   = Game.GetBlackboardSystem():Get(idef)
    if not bb or not idef.InteractionChoiceHub then return end
    local empty = InteractionChoiceHubData.new()   -- clear by pushing an inactive empty hub
    empty.id, empty.active, empty.choices = choiceBox.id, false, {}
    bb:SetVariant(idef.InteractionChoiceHub, ToVariant(empty), true)
  end)
  choiceBox.shown = false
end

-- ---------------------------------------------------------------------------
-- "Talk" prompt (v0.14): shown while you look at Jackie nearby, during normal
-- gameplay (no CET overlay). Uses the game's NATIVE on-screen message system.
-- NOTE: the literal yellow-band dialogue box is drawn by a native HUD controller
-- that CET Lua can't attach to in patch 2.3 (no scriptable hook there), so we use
-- the native message system instead. The bound "Talk to Jackie" key plays the line.
-- ---------------------------------------------------------------------------
local talkUI = { shown = false, checkT = 0, lastShow = -999 }

-- v1.x: play a short 2D UI sound event on the player (base-game AudioSystem, no entity/emitter needed).
-- Gives the on-screen banners an audible cue, and previews candidates in the "Banner sound" tester.
-- Defined ABOVE showOnscreenMsg so the banner can call it. Empty/nil event = no-op.
-- GLOBAL (not a top-level local): init.lua is at Lua's 200-local cap, so cross-scope helpers are globals.
function playUiSound(evt)
  if not evt or evt == "" then return false end
  local ok = pcall(function()
    local pl = Game.GetPlayer()
    if not pl then return end
    Game.GetAudioSystem():Play(CName.new(evt), pl:GetEntityID(), CName.new(""))
  end)
  return ok
end

-- Show text via the game's native on-screen message blackboard (reliable, no attach).
-- v1.x: every banner now ALSO plays the configured UI sound (Config.banner.sfx) so it isn't silent —
-- pass silent=true to suppress it for the noisy re-asserted cases (look heartbeat, subtitle fallback).
local function showOnscreenMsg(text, duration, silent)
  pcall(function()
    local defs = GetAllBlackboardDefs()
    local bb = Game.GetBlackboardSystem():Get(defs.UI_Notifications)
    if not bb then return end
    local msg = SimpleScreenMessage.new()
    msg.isShown = true
    msg.duration = duration or 3.0
    msg.message = text
    bb:SetVariant(defs.UI_Notifications.OnscreenMessage, ToVariant(msg), true)
  end)
  if not silent then playUiSound(Config.banner and Config.banner.sfx) end
end

-- v0.93: MAIN-QUEST CALL REFUSAL notice. Calling/summoning Jackie during a MAIN quest is a deliberate
-- no-op (he won't get dragged into the story), but it used to fail SILENTLY — the only feedback was the
-- CET status text, invisible during normal play — so it read as a bug ("I did the retrieval quest, why
-- won't he answer?"). This routes every refusal through one place: V's status line + log AS BEFORE, PLUS
-- the blue on-screen NOTICE band so the player is told why on screen. Global (not a top-level local) so
-- it's callable from summonJackie (defined ABOVE showOnscreenMsg) and 200-local-cap safe.
function jlDeclineMainQuest()
  JL.ui.status = Config.declineLine
  log(Config.declineLine)
  showOnscreenMsg(Config.mainQuestBlockNotice or Config.declineLine, 8.0)   -- v0.94: doubled hold (was 4.0) so it's readable
end

-- ---------------------------------------------------------------------------
-- NATIVE subtitles (v0.22): the REAL bottom subtitle band, via the UIGameData
-- blackboard fields ShowDialogLine / HideDialogLine. This is the exact path
-- Audioware uses internally (r6/scripts/Audioware/Codeware.reds -> PropagateSubtitle,
-- Callback.reds -> hide). Replaces the on-screen NOTIFICATION (the blue objective-style
-- field) for spoken dialogue, so lines render as proper subtitles at the bottom.
-- ---------------------------------------------------------------------------
-- dueAt (v0.80): clock time when this line's on-screen time is up. subtitleWatchdogTick (onUpdate)
-- uses it to GUARANTEE a dangling line gets wiped even if some branch forgot to call hideSubtitle.
local subtitle = { line = nil, seq = 700, warned = false, dueAt = nil }

-- Push a real subtitle to the bottom band. Logs the exact failure point the first time
-- it can't (so we can pinpoint which CET call differs on this build).
local function showSubtitle(text, speakerName, duration, speakerObj)
  local line
  local ok, err = pcall(function()
    line = scnDialogLineData.new()
    line.text         = tostring(text or "")
    line.speakerName  = tostring(speakerName or "")
    line.duration     = duration or 4.0
    line.isPersistent = false
    pcall(function() line.type = scnDialogLineType.Regular end)
    if speakerObj then pcall(function() line.speaker = speakerObj end) end
    subtitle.seq = subtitle.seq + 1
    pcall(function() line.id = CreateCRUID(subtitle.seq) end)   -- so we can hide this exact line
    local defs = GetAllBlackboardDefs()
    local bb   = Game.GetBlackboardSystem():Get(defs.UIGameData)
    if not bb then error("UIGameData blackboard nil") end
    if not defs.UIGameData.ShowDialogLine then error("ShowDialogLine field nil") end
    -- CET can't infer the array element type from a plain Lua table (-> "Unknown type ''"),
    -- so force it explicitly: array:scnDialogLineData (per the CET Lua kit ToVariant docs).
    bb:SetVariant(defs.UIGameData.ShowDialogLine, ToVariant({ line }, "array:scnDialogLineData"), true)
  end)
  if ok then
    subtitle.line  = line
    -- when the watchdog is allowed to force-wipe this line if nothing else has (display time + grace)
    subtitle.dueAt = (JL.clock or 0) + (duration or 4.0) + 0.75
    return true
  end
  if not subtitle.warned then
    log("SUBTITLE push FAILED -> falling back to on-screen msg. Error: " .. tostring(err))
    subtitle.warned = true
  end
  return false
end

local function hideSubtitle()
  subtitle.dueAt = nil
  if not subtitle.line then return end
  local prev = subtitle.line
  subtitle.line = nil
  pcall(function()
    local defs = GetAllBlackboardDefs()
    local bb   = Game.GetBlackboardSystem():Get(defs.UIGameData)
    bb:SetVariant(defs.UIGameData.HideDialogLine, ToVariant({ prev.id }, "array:CRUID"), true)
  end)
end

-- Preferred dialogue text path: real subtitle, falling back to the on-screen message
-- if scnDialogLineData / the blackboard push isn't available on this build.
local function showDialogueText(speaker, text, duration, speakerObj)
  if not showSubtitle(text, speaker, duration, speakerObj) then
    showOnscreenMsg(tostring(speaker) .. ":   " .. tostring(text), (duration or 4.0) + 0.5, true)  -- silent: subtitle fallback, not a notice banner
  end
end

-- Show the prompt while looking at Jackie within talk range. Called (throttled) from onUpdate.
local function updateTalkPrompt(dt)
  talkUI.checkT = (talkUI.checkT or 0) + dt
  if talkUI.checkT < 0.2 then return end
  talkUI.checkT = 0
  -- v1.01: while Blaze's "Get in the AV" prompt owns the native interaction box, don't touch it.
  if JL.mode == "blaze" then
    local esc = false; pcall(function() esc = Blaze.escapePromptActive and Blaze.escapePromptActive() end)
    if esc then talkUI.shown = false; return end
  end
  if jlInCutscene() then           -- v0.92: no talk prompt / dialogue picker during a cutscene
    if choiceBox.shown then hideJackieChoiceBox() end
    talkUI.shown = false
    return                         -- Jackie just barks his bye line (startLeaving) + walks off; V never replies
  end
  if Branch.busy then return end   -- a conversation is running; don't fight / clear its choice box
  local j = lookedAtJackie()
  local within = false
  if j then
    within = true
    local pp = playerPos()
    if pp then
      local jp; pcall(function() jp = j:GetWorldPosition() end)
      if jp and dist3(pp, jp) > (Config.talk and Config.talk.range or 4.0) then within = false end
    end
  end
  if within then
    if Config.talk and Config.talk.useChoiceBox then
      -- Permanent look-driven box: push on first look, then re-assert on the heartbeat
      -- interval so it survives if the game's interaction system clears the blackboard.
      local now     = JL.clock or 0
      local refresh = (Config.talk and Config.talk.boxRefresh) or 1.0
      if (not choiceBox.shown)
         or (refresh > 0 and (now - (choiceBox.lastPush or -999)) >= refresh) then
        showJackieChoiceBox()
      end
    else
      local now = JL.clock or 0
      if (now - (talkUI.lastShow or -999)) > 2.5 then          -- heartbeat so it stays up while looking
        local key = (Config.talk and Config.talk.keyLabel) or "="
        showOnscreenMsg("Talk to Jackie   [ " .. key .. " ]", 3.0, true)  -- silent: re-asserted every 2.5s while looking, don't beep
        talkUI.lastShow = now
      end
    end
    talkUI.shown = true
  else
    if choiceBox.shown then hideJackieChoiceBox() end
    talkUI.shown = false
  end
end

-- ---------------------------------------------------------------------------
-- Dialogue runner (v0.18, MVP) - the data-driven "build new V<->Jackie dialogue" tool.
-- Plays a scripted exchange: each line shows as an on-screen subtitle (speaker + text);
-- Jackie's lines also fire one of his WWise voice events so there's real voice presence.
-- Conversations live in Config (Config.testDialogue for now; later a JSON file / phone call).
-- PHASE 2 will swap the placeholder bark for the line's EXACT audio - his real ".ogg"
-- (already scraped for all 777 lines) played via Audioware - so he speaks the actual words.
-- ---------------------------------------------------------------------------
local dlg = { active = false, lines = nil, idx = 0, nextT = 0 }

-- The entity Jackie's voice plays on (summoned or idle); nil -> subtitle only, no audio.
local function dialogueTarget()
  if JL.summon.spawn and JL.summon.spawn.handle then return JL.summon.spawn.handle end
  if JL.idle.spawn and JL.idle.spawn.handle then return JL.idle.spawn.handle end
  return nil
end

-- ---------------------------------------------------------------------------
-- LIP-MOVEMENT flap (v0.34). Our Audioware audio can't drive real visemes, so while a Jackie
-- line plays we shuffle AMM Expressions Overhaul "Talking" faces (category 7, idle 231..266 -
-- 242 skipped; verified from Collabs/Extra_Expressions_AMM.lua) on his face for the line's
-- duration. ~0.9s cadence looked best in testing (JackieLipsync). Requires AMM Expressions
-- Overhaul installed; no-ops gracefully if its faces are absent. (Greeting/reaction barks that
-- use real VO voiceset contexts get true lipsync separately - see memory jackie-facial-rig-runtime.)
-- ---------------------------------------------------------------------------
local flap = { until_ = 0, nextAt = 0, idles = nil, interval = 0.82 }
local function flapIdles()
  if flap.idles then return flap.idles end
  local t = {}
  for i = 231, 266 do if i ~= 242 then t[#t + 1] = i end end
  flap.idles = t; return t
end
local function applyTalkingFace(handle)
  if not handle then return end
  pcall(function()
    local anim = handle:GetAnimationControllerComponent()
    if not anim then return end
    local list = flapIdles()
    local f = NewObject("handle:AnimFeature_FacialReaction")
    pcall(function() f.category = 7 end)
    pcall(function() f.idle = list[math.random(1, #list)] end)
    anim:ApplyFeature(CName.new("FacialReaction"), f)
  end)
end
-- begin flapping the speaking Jackie for `seconds` (called when a line starts).
local function startFlap(seconds)
  if not dialogueTarget() then return end
  flap.until_ = (JL.clock or 0) + (seconds or 3.0)
  flap.nextAt = 0   -- apply on the next tick
end
-- stepped from onUpdate: shuffle a talking face every interval until the line elapses, then
-- reset his face once so he doesn't freeze mid-expression.
local function flapTick()
  local now = JL.clock or 0
  if flap.until_ <= 0 then return end
  if now >= flap.until_ then
    flap.until_ = 0
    pcall(function()
      local h = dialogueTarget()
      if h then local s = h:GetStimReactionComponent(); if s then s:ResetFacial(0) end end
    end)
    return
  end
  if now >= (flap.nextAt or 0) then
    flap.nextAt = now + (flap.interval or 0.9)
    applyTalkingFace(dialogueTarget())
  end
end

-- ---------------------------------------------------------------------------
-- v0.53 CATCH-HIS-EYE SMILE. While V holds their look straight on Jackie (and nothing else is
-- driving his face), roll a LOW chance every `rollEvery` s; on a hit he smiles for `duration` s
-- then relaxes. Same FacialReaction mechanism as the talk-flap, so it's gated OFF whenever a line
-- is playing (flap/dialogue) — a smile must never stomp the mouth mid-sentence.
-- ---------------------------------------------------------------------------
local function applySmileFace(handle, idleOverride)
  if not handle then return end
  pcall(function()
    local anim = handle:GetAnimationControllerComponent()
    if not anim then return end
    local f = NewObject("handle:AnimFeature_FacialReaction")
    pcall(function() f.category = (Config.smile and Config.smile.category) or 3 end)
    pcall(function() f.idle     = idleOverride or (Config.smile and Config.smile.idle) or 6 end)
    anim:ApplyFeature(CName.new("FacialReaction"), f)
  end)
end
local function resetSmileFace(handle)
  if not handle then return end
  pcall(function() local s = handle:GetStimReactionComponent(); if s then s:ResetFacial(0) end end)
end

-- v0.94: pick WHICH happy face a smile uses once it has fired. `selfChance` -> his own `idle` (Smile);
-- otherwise an evenly-picked one of `otherIdles` (Joy etc.), so the "other" faces COLLECTIVELY make up
-- the remaining share. Does NOT touch how OFTEN he smiles — the chance roll upstream is unchanged.
local function pickSmileIdle(cfg)
  cfg = cfg or Config.smile or {}
  local own = cfg.idle or 6
  local others = cfg.otherIdles
  if not others or #others == 0 then return own end        -- no alternates -> always his own
  local r = 1.0; pcall(function() r = math.random() end)
  if r < (cfg.selfChance or 0.60) then return own end
  local i = 1; pcall(function() i = math.random(1, #others) end)
  return others[i] or own
end

-- stepped from onUpdate.
local function smileTick()
  local cfg = Config.smile
  if not (cfg and cfg.enabled) then return end
  local now = JL.clock or 0
  local s   = JL.smile

  -- (a) a smile is in progress: hold it (re-assert so it doesn't decay), then relax when it elapses.
  if s.until_ > 0 then
    if now >= s.until_ then
      resetSmileFace(s.handle)
      s.until_, s.handle = 0, nil
      -- during the reunion boost we want him to be able to grin again right away (no 25s cooldown).
      s.cooldownUntil = now + ((s.reunionActive and 0) or (cfg.cooldown or 25.0))
    elseif now >= (s.nextApply or 0) then
      s.nextApply = now + (cfg.reapply or 0.6)
      applySmileFace(s.handle, s.idle)
    end
    return
  end

  -- v0.93 REUNION SMILE BOOST — while the first-meeting dialogue is running he beams. Bypasses the
  -- gaze + Branch/dialogue gates (we WANT smiles mid-convo here), but still yields to his mouth flap
  -- so spoken lines lip-sync. Hard `reunionSafety` expiry protects against an aborted meet.
  if s.reunionActive then
    if now > (s.reunionSafety or 0) then s.reunionActive = false; return end
    local jackie = (JL.summon.spawn and JL.summon.spawn.handle) or lookedAtJackie()
    if flap.until_ > 0 or dlg.active then return end   -- never over his mouth flap
    -- (i) forced continuous smile for the first `reunionForceSeconds`.
    if now < (s.reunionForceUntil or 0) then
      if jackie and now >= (s.nextApply or 0) then
        s.handle    = jackie
        s.idle      = (cfg.reunionIdles and cfg.reunionIdles[1]) or cfg.idle or 6
        s.nextApply = now + (cfg.reapply or 0.6)
        applySmileFace(s.handle, s.idle)
      end
      return
    end
    -- (ii) rest of the chat: roll at `reunionChanceMult`x the normal chance, no gaze requirement.
    if now < (s.nextRoll or 0) then return end
    s.nextRoll = now + (cfg.rollEvery or 1.5)
    if not jackie then return end
    if math.random() >= ((cfg.chance or 0.033) * (cfg.reunionChanceMult or 3.0)) then return end
    local pool = cfg.reunionIdles or { cfg.idle or 6 }
    s.handle, s.idle = jackie, pool[math.random(#pool)]
    s.until_, s.nextApply = now + (cfg.duration or 3.0), 0
    return
  end

  -- (b) never start a smile while he's talking (would stomp the mouth flap) or in cooldown.
  if flap.until_ > 0 or dlg.active or Branch.open or Branch.busy then return end
  if now < (s.cooldownUntil or 0) then return end

  -- (c) roll only while V is actually looking straight at Jackie, within range, on the roll cadence.
  if now < (s.nextRoll or 0) then return end
  s.nextRoll = now + (cfg.rollEvery or 1.5)
  local jackie = lookedAtJackie()
  if not jackie then return end
  local pp = playerPos()
  if pp then
    local jp; pcall(function() jp = jackie:GetWorldPosition() end)
    if jp and dist3(pp, jp) > (cfg.range or 8.0) then return end
  end
  -- low likelihood normally; bumped while out for dinner with him (the happy occasion)
  local chance = (JL.dinner.phase and cfg.dinnerChance) or cfg.chance or 0.033
  if math.random() >= chance then return end

  s.handle    = jackie
  s.idle      = pickSmileIdle(cfg)   -- v0.94: mostly his own Smile, occasionally an "other" happy face
  s.until_    = now + (cfg.duration or 3.0)
  s.nextApply = 0   -- apply on the next tick
  log("Smile: caught V's eye -> brief smile (idle " .. tostring(s.idle) .. ").")
end

-- v0.55 AMBIENT "feel alive" grunts. While Jackie is present (companion OR idle at a venue) and
-- nothing else is driving his voice/face, roll a small `chance` every `everyMinutes` real minutes
-- for ONE of his non-pained vocal efforts (a laugh, a huff, a curious "hmm"). The pool deliberately
-- excludes pain/choking/scream/death + combat barks, so he never randomly grunts like he's hurt or
-- fighting. Same WWise playback path as the talk grunts; gated by the same talk/call locks as the smile.
local function ambientGruntTick()
  local cfg = Config.ambientGrunt
  if not (cfg and cfg.enabled) then return end
  local now = JL.clock or 0
  local a   = JL.ambient
  -- only when Jackie's actually here (never on V or a random look-at target)
  local handle = (JL.summon.spawn and JL.summon.spawn.handle) or (JL.idle.spawn and JL.idle.spawn.handle)
  if not handle then a.nextRoll = 0; return end           -- gone -> re-arm a fresh full gap next time
  -- don't grunt over a line / dialogue / call (same locks the smile uses)
  if flap.until_ > 0 or dlg.active or Branch.open or Branch.busy then return end
  -- first arm after he appears: wait one full gap before the first roll (no grunt the instant he spawns)
  if not a.nextRoll or a.nextRoll == 0 then
    a.nextRoll = now + (cfg.everyMinutes or 10.0) * 60
    return
  end
  if now < a.nextRoll then return end
  a.nextRoll = now + (cfg.everyMinutes or 10.0) * 60      -- next window regardless of the roll outcome
  if math.random() >= (cfg.chance or 0.10) then return end
  local pool = cfg.events or {}
  if #pool == 0 then return end
  local ev = pool[math.random(1, #pool)]
  pcall(function() playEventOn(handle, ev, "") end)
  log("Ambient: '" .. tostring(ev) .. "' (feel-alive grunt).")
end

-- Audioware: play a registered voice clip (his real .ogg) by event name. 2D for the
-- MVP (no positional emitter setup needed); upgrade to PlayOnEmitter later if wanted.
local function playVoice(name)
  if not name or name == "" then return false end
  local ok = pcall(function() Game.GetAudioSystemExt():Play(CName.new(name)) end)
  return ok
end

-- Audioware: real clip length (seconds) so subtitle timing matches the audio. nil if unknown.
local function voiceDuration(name)
  if not name or name == "" then return nil end
  local d
  pcall(function() d = Game.GetAudioSystemExt():Duration(CName.new(name)) end)
  if type(d) == "number" and d > 0 then return d end
  return nil
end

-- Diagnostic: prove the Audioware pipe end-to-end. Logs the plugin version, whether the
-- 'test_tone' event is registered (Duration > 0 = the manifest loaded), then plays it.
local function audiowareProbe()
  local ver = "?"
  pcall(function() ver = Game.GetAudioSystemExt():Version() end)
  local dur = -1
  pcall(function() dur = Game.GetAudioSystemExt():Duration(CName.new("test_tone")) end)
  local registered = (type(dur) == "number" and dur > 0)
  log("Audioware probe: version=" .. tostring(ver) ..
      "  Duration('test_tone')=" .. tostring(dur) ..
      (registered and "  (REGISTERED - manifest loaded)" or "  (NOT registered - manifest/folder issue)"))
  local ok = playVoice("test_tone")
  log("Audioware probe: Play('test_tone') ok=" .. tostring(ok) ..
      " -> you should hear a 1s beep if the pipe works")
  JL.ui.status = "Audioware ver=" .. tostring(ver) .. "  test_tone dur=" .. tostring(dur) .. " (see console)"
end

local function startDialogue(lines)
  if Branch.open or Branch.busy then return end                 -- don't run two conversations at once
  if not lines or #lines == 0 then JL.ui.status = "No dialogue lines (fill Config.testDialogue)."; return end
  pcall(hideJackieChoiceBox)                                    -- remove the "[F] Talk" prompt while talking
  Branch.busy = true
  dlg.active, dlg.lines, dlg.idx, dlg.nextT = true, lines, 0, 0
  JL.ui.status = "Dialogue started."
  log("Dialogue: start (" .. #lines .. " lines).")
end

-- Stepped from onUpdate: advance one line each time its predecessor's audio elapses.
local function dialogueTick()
  if not dlg.active then return end
  local now = JL.clock or 0
  if now < dlg.nextT then return end
  dlg.idx = dlg.idx + 1
  local line = dlg.lines and dlg.lines[dlg.idx]
  if not line then
    dlg.active = false; Branch.busy = false; hideSubtitle()
    JL.ui.status = "Dialogue done."; log("Dialogue: done."); return
  end
  local who = tostring(line.speaker or "?")
  -- v0.20: real voice via Audioware for BOTH speakers (V reuses Jackie clips for now)
  local spoke = false
  if line.sfx then spoke = playVoice(line.sfx) end
  if (not spoke) and line.fallbackSfx then spoke = playVoice(line.fallbackSfx) end  -- guaranteed WAV
  -- legacy WWise bark still supported if a line uses `event` (extra presence / fallback)
  if line.event then
    local target = dialogueTarget()
    if target then pcall(function() playEventOn(target, line.event, "") end) end
  end
  -- pace by the real clip length when readable, else the configured dur; small gap after
  local secs = voiceDuration(line.sfx) or line.dur or 4.0
  -- v0.22: real subtitle band (speaker = Jackie's entity for his lines, else V)
  local isJk = who:lower():find("jackie") ~= nil
  local spk  = isJk and dialogueTarget() or Game.GetPlayer()
  if isJk then startFlap(secs) end   -- lip-movement: flap only on Jackie's lines
  hideSubtitle()
  showDialogueText(who, line.text or "", secs + 0.6, spk)
  dlg.nextT = now + secs + 0.4
  log(string.format("Dialogue: %s '%s' sfx=%s spoke=%s secs=%.2f",
      who, tostring(line.text or ""), tostring(line.sfx), tostring(spoke), secs))
end

-- F-press launcher (assigns the forward-declared upvalue). Look at Jackie + press F
-- -> start the scripted conversation (ignored if one is already running).
startLinearDialogue = function()
  if dlg.active then return end
  if not lookedAtJackie() then return end
  startDialogue(Config.testDialogue)
end

-- ===========================================================================
-- RELATIONSHIP MODE (v1.2): Husbando (female-V track) vs Hermano (male-V track).
-- JL.husbando (persisted) is the switch: true = Husbando, false = Hermano. The base
-- text/sfx authored in config.lua IS the Husbando track; a Jackie line, pool entry or
-- choice may carry an `m = {...}` MASCULINE OVERRIDE that replaces it in Hermano mode.
-- No `m` -> the shared (unisex) line is reused — it's Jackie's own voice either way, so
-- any content-neutral clip works for both. Declared GLOBAL (not local) to respect
-- init.lua's 200-local cap. See config.lua header + docs/VOICE_LINES.md.
-- ===========================================================================
function jlHermano() return JL.husbando == false end   -- true while the male-V (Hermano) track is active

-- Mode-appropriate variant of a Jackie line / pool-entry table {text=, sfx=, m={text=,sfx=}}.
-- In Hermano mode, resolution order:
--   1) an inline `m = {...}` on the entry (used for text-only lines + one-offs), else
--   2) a central sfx-keyed override in Config.hermanoLines (rewrites EVERY recurrence of a
--      voiced female-coded line at once — e.g. the "...chica" greeting appears in 5+ trees).
-- No match -> the shared (unisex) entry is returned unchanged. nil-safe.
function jlVar(entry)
  if entry and jlHermano() then
    if entry.m then return entry.m end
    local map = Config.hermanoLines
    if map and entry.sfx and map[entry.sfx] then return map[entry.sfx] end
  end
  return entry
end

-- v1.54: HERMANO IS THE DEFAULT FOR EVERY V. The old v1.2/v1.3 behaviour auto-read V's body gender on
-- first load and locked Female V -> Husbando; that's gone (jlDetectGenderOnce deleted). Rationale: most
-- players run a male V, Hermano is the canon track, and a player who wants Husbando can just flip the
-- Esc -> Settings switch. So the mode is ONLY ever non-default if the player explicitly chose it.
--
-- JL.modeChosen (persisted) records that explicit choice — it is set ONLY by the settings switch. Until
-- then we force Hermano on every load, which also MIGRATES old saves that the auto-detect had silently
-- locked to Husbando. Global (200-local cap). Called from onInit, right after jlLoadSettings.
function jlDefaultHermano()
  if JL.modeChosen then return end       -- player flipped the switch themselves -> their choice wins, always
  if JL.husbando ~= false then
    JL.husbando = false                  -- no explicit choice on record -> Hermano (the default)
    log("Relationship mode defaulted to Hermano (flip 'Husbando mode' in Esc -> Settings to change it).")
  end
end

-- ---------------------------------------------------------------------------
-- THE ARCH (v1.54). Jackie's bike is no longer an automatic hand-back: on the reunion call it's an
-- OPTIONAL hub topic, and if V does raise it she can either promise it back or tell him she's keeping
-- it. The outcome lives in the save (a game fact), not in memory, because the payoff is read LATER —
-- by the reunion_arrival action and again by the face-to-face reunionMeetTree — across a possible
-- save/reload in between. Globals, not locals (200-local cap).
JL_BIKE_UNASKED  = 0   -- the bike never came up on the call
JL_BIKE_RETURNED = 1   -- V told him she'd kept it safe -> he gets the Arch back on arrival
JL_BIKE_KEPT     = 2   -- V told him she's keeping it -> it stays in her garage

-- ---------------------------------------------------------------------------
-- FOLLOW DISTANCE (v1.55). ONE player-set number (Esc -> Settings -> Gameplay) driving how far Jackie sits
-- from V in BOTH follow modes — the trail (followKeepCloseTick, while V jogs/sprints) and the walk-abreast
-- side anchor (while V strolls). Antonia: the two can share a default, ~3-5 m. Clamped to the slider's own
-- range so a corrupt settings file can't park him 200 m away or inside V. Global (200-local cap).
function jlFollowDistance()
  local d = JL.followDistance
  if type(d) ~= "number" then d = Config.followDistanceDefault or 3.5 end
  local lo = Config.followDistanceMin or 1.2
  local hi = Config.followDistanceMax or 8.0
  if d < lo then d = lo elseif d > hi then d = hi end
  return d
end

function jlFactNum(name)          -- read a numeric game fact; 0 if unset/unreadable
  local v; pcall(function() v = Game.GetQuestsSystem():GetFactStr(name) end)
  return (type(v) == "number") and v or 0
end
function jlSetFactNum(name, n)
  pcall(function() Game.GetQuestsSystem():SetFactStr(name, n) end)
end
function jlBikeOutcome() return jlFactNum("jackielives_bike") end

-- ---------------------------------------------------------------------------
-- MISTY, RETIRED (v1.55 — Husbando only). Antonia: "after Jackie has been to Misty's once (that's when
-- they break up) Jackie should NOT go to Misty again. Swap for noodle bar in schedule, he won't come back
-- to her." So the break-up is never SPOKEN (v1.54 cut all of that) — it's shown, by his absence.
--
-- jackielives_misty_done is set the first time he's actually spawned at her shop, and persists in the save.
-- The one subtlety: while he is STILL THERE we must not report him retired, or scheduleTick would see the
-- swapped block, decide he's at the wrong venue, and walk him out mid-visit. So the visit he's currently
-- having always finishes; only the NEXT Misty slot gets swapped.
-- HERMANO IS UNAFFECTED — they're together, and he keeps his standing visit forever.
JL_FACT_MISTY_DONE = "jackielives_misty_done"

function jlMistyRetired()
  if JL.husbando ~= true then return false end                        -- Hermano -> he always goes to Misty's
  if JL.idle and JL.idle.locationKey == (Config.mistyKey or "misty") then return false end  -- mid-visit, let it play out
  return jlFactNum(JL_FACT_MISTY_DONE) >= 1
end

-- Called when he's spawned at Misty's: latch the (one and only) visit into the save.
function jlMarkMistyVisited()
  if JL.husbando ~= true then return end                              -- only Husbando breaks up
  if jlFactNum(JL_FACT_MISTY_DONE) >= 1 then return end               -- already latched
  jlSetFactNum(JL_FACT_MISTY_DONE, 1)
  log("Husbando: Jackie's been to Misty's — that's the last time. Her schedule slot now goes to the noodle bar.")
end

-- ---------------------------------------------------------------------------
-- BRANCHING dialogue (v0.23): native-looking choice box driving a small tree.
-- Jackie speaks a node's line (voice + subtitle); after it, a CHOICE BOX of silent
-- player options appears; selecting one jumps to the next node or ends. Choices are
-- silent text (like the game's dialogue wheel), so the missing V audio is a non-issue.
--   Selection : F confirms the HIGHLIGHTED row; the bound "Cycle Jackie choice" key
--               moves the highlight; Choice2/Choice3 keys also select directly IF this
--               build fires them (we log every action while a menu is open to find out).
-- ---------------------------------------------------------------------------
local menu = { shown = false, choices = nil, sel = 1, title = "Jackie" }
-- openAt   : clock time to reveal the menu after Jackie's line
-- pending* : after the player's chosen line shows (1s), go to `pending` node (or end)
local bstate = { node = nil, openAt = nil, pending = nil, pendingAt = nil, talkCooldownKey = nil }

-- Reading time scaled to line LENGTH (v0.94); used when no voice-clip length paces the line (the mute
-- build) on the emotional reunion beats — so long lines linger while short ones stay snappy.
-- secs = clamp(min, base + chars/cps, max). Config.subtitleReading holds the tunables.
local function readingSecs(text)
  local cfg = Config.subtitleReading or {}
  local n = #tostring(text or "")
  local s = (cfg.base or 1.6) + n / (cfg.charsPerSec or 22.0)
  return math.max(cfg.minSecs or 2.0, math.min(cfg.maxSecs or 16.0, s))
end
-- The emotional beats that get length-scaled subtitles (so long mute lines don't flash by): the reunion
-- phone call + first meeting, and (v1.07) the Blaze finale conversation.
local function isReunionBeat()
  return bstate.tree == Config.reunionCallTree or bstate.tree == Config.reunionMeetTree
      or bstate.tree == Config.blazeFinaleTree
end

-- Play a Jackie line: real voice (sfx, else the guaranteed jl_fallback WAV) + subtitle.
-- v1.56 `mute`: suppress the jl_fallback GRUNT on a text-only line. Normally an unvoiced line still plays
-- a neutral vocal effort so Jackie isn't silent — but on the reunion beats that's exactly the problem
-- Antonia hit: a long stretch of grunt-backed subtitles with the occasional real VO line landing on top of
-- it reads as broken rather than intentional. A tree can now set `muteFallback = true` (Branch.start passes
-- it through) to be GENUINELY silent except for the lines that carry a real `sfx`.
local function speakJackieLine(text, sfx, mute)
  local spoke = false
  if sfx then spoke = playVoice(sfx) end
  if not spoke and not mute then spoke = playVoice("jl_fallback") end
  -- pace by the real clip length when readable; on the mute build, scale to text length for the
  -- reunion beats (v0.94), else the old flat 3 s.
  local secs = voiceDuration(sfx) or (isReunionBeat() and readingSecs(text)) or 3.0
  hideSubtitle()
  -- carrier entity for the subtitle band: Jackie if spawned, else the player (on a phone
  -- call Jackie isn't in the world yet, and a null speaker can make the band skip the line).
  showDialogueText("Jackie", text or "", secs + 0.6, dialogueTarget() or Game.GetPlayer())
  startFlap(secs)   -- lip-movement: flap his mouth for the line's duration
  log("Branch: Jackie '" .. tostring(text) .. "' sfx=" .. tostring(sfx) .. " spoke=" .. tostring(spoke))
  return secs
end

-- ===========================================================================
-- DINNER OUTING (v0.41): pick a restaurant -> map waypoint + follow -> walk banter ->
-- arrive + linger -> FULL companion-clock reset. Pure Lua state machine (no quest/WolvenKit).
-- ===========================================================================

-- Drop the dinner map pin (if any).
local function clearDinnerWaypoint()
  if JL.dinner.mappinId then
    pcall(function() Game.GetMappinSystem():UnregisterMappin(JL.dinner.mappinId) end)
    JL.dinner.mappinId = nil
  end
end

-- Register a custom map pin at `pos` (Vector4) so the minimap shows it (and, where the variant
-- supports it, a route line). Stores the id for later removal.
local function setDinnerWaypoint(pos)
  clearDinnerWaypoint()
  if not pos then return end
  pcall(function()
    local data = NewObject("gamemappinsMappinData")
    data.mappinType = TweakDBID.new("Mappins.DefaultStaticMappin")
    data.variant    = gamedataMappinVariant.CustomPositionVariant
    data.visibleThroughWalls = true
    JL.dinner.mappinId = Game.GetMappinSystem():RegisterMappin(data, pos)
  end)
  log("Dinner: waypoint set (mappin id=" .. tostring(JL.dinner.mappinId) .. ").")
end

-- Resolve a restaurant by key. "random" = Jackie self-picks: he prefers venues he can NAME (have a pickSfx)
-- so he actually says where they're going; if none are nameable he falls back to any with coords.
local function findRestaurant(key)
  local list = (Config.date and Config.date.restaurants) or {}
  if key == "random" then
    local nameable, anyPos = {}, {}
    for _, r in ipairs(list) do
      if r.pos then
        anyPos[#anyPos + 1] = r
        if r.pickSfx then nameable[#nameable + 1] = r end
      end
    end
    local avail = (#nameable > 0) and nameable or anyPos
    if #avail == 0 then return nil end
    local i = 1; pcall(function() i = math.random(1, #avail) end)
    return avail[i]
  end
  for _, r in ipairs(list) do if r.key == key then return r end end
  return nil
end

-- Throw out one random multi-line banter section (skips if a conversation is already running).
-- Begin the outing to restaurant `key`. Sets the map waypoint + objective, says an ack line. The
-- auto-leave is paused for the whole outing (see onUpdate); dinnerTick (defined LATER, after the
-- pose/move helpers) handles arrive -> seat -> sit -> line -> reset -> walk-away -> re-follow.
local function startDinnerWalk(key)
  if not JL.summon.active then return end
  local D = Config.date or {}
  -- v1.57: he AGREED to eat — so he is definitively not walking off any more. (Belt-and-braces: the invite
  -- in runCallAction already aborts, but Jackie can also propose the outing himself, and a leaving Jackie
  -- must never be left coasting on jlRetreatFollow once a dinner is on.) Full companion shift, since a
  -- dinner is exactly the thing that resets his clock; dinnerTick resets it again when the meal is done.
  pcall(function() jlAbortDeparture((Config.companion and Config.companion.maxGameHours) or 6.0, "dinner accepted") end)
  -- v0.47: the "not twice a day" refusal moved UP to the invite (runCallAction "start_date"), so by the
  -- time we get here V has already passed the cooldown gate and committed to a venue.
  local r = findRestaurant(key)
  if not r or not r.pos then
    armCompanionTimer((Config.companion and Config.companion.maxGameHours) or 6.0)
    JL.ui.status = "No coords for that spot yet - reset Jackie's clock instead."
    log("Dinner: no restaurant coords for key='" .. tostring(key) .. "'; did a plain reset.")
    return
  end
  local pos = Vector4.new(r.pos[1], r.pos[2], r.pos[3], 1.0)
  setDinnerWaypoint(pos)
  JL.dinner.phase    = "walking"
  JL.dinner.dest     = pos
  JL.dinner.destName = r.name
  JL.dinner.destYaw  = r.yaw or 0.0
  JL.dinner.satAt    = nil
  -- v0.52: if HE picked the spot ("You pick, hermano." -> dine:random) and it has a naming line, he SAYS it
  -- ("Meet me at Lizzie's." / "...we hit the Afterlife..."); otherwise the generic accept ack.
  local selfPick = (key == "random") and r.pickSfx
  local line = selfPick and r.pickText or D.ackText
  local sfx  = selfPick and r.pickSfx  or D.ackSfx
  local av   = jlVar({ text = line, sfx = sfx })   -- v1.2: Hermano swap (e.g. "Right on, chica." -> "...mano.")
  pcall(function() speakJackieLine(av.text, av.sfx) end)
  -- v0.64: flash the objective as the native neon-left on-screen message (not a persistent ImGui box).
  -- v1.x: bars (r.drinks = true, e.g. Lizzie's / Afterlife) read "grab some drinks" instead of "food".
  local fmt = (r.drinks and (D.objectiveTextDrinks or "Grab some drinks with Jackie: Go to %s"))
             or (D.objectiveText) or "Grab some food with Jackie: Go to %s"
  pcall(function() showOnscreenMsg(fmt:format(tostring(r.name)), D.objectiveDuration or 6.0) end)
  JL.ui.status = "Headin' to " .. tostring(r.name) .. " with Jackie."
  log("Dinner: walk to '" .. tostring(r.name) .. "' started.")
end
-- dinnerTick is defined further down (it needs sendMoveToPoint / aiTeleport
-- / tryWorkspotPose / promoteToCompanion, all declared below this point).

-- v0.24: the choice menu is a CUSTOM ImGui box drawn during gameplay (overlay closed),
-- styled like the game's dialogue picker (docs/dialogue_picker_design.png): speaker name
-- on top, choices in a vertical column, the HIGHLIGHTED row in yellow. Navigation is OUR
-- cycle key + F - no native hub, so no side-by-side "F / R / 1" input prompts.
-- v0.26: picker styled toward the game's look (docs/dialogue_picker_design.png) -
-- BORDERLESS + TRANSPARENT (no title bar / collapse arrow / window bg), speaker name in a
-- red-framed box to the LEFT, choices stacked on the right. Three style variants so we can
-- compare what CET renders best (JL.ui.pickerStyle = 1/2/3, set by the testV1/2/3 buttons):
--   1: name = red-bordered child box ; selected row = translucent YELLOW HIGHLIGHT BAR
--   2: name = red-bordered child box ; selected row = bright YELLOW TEXT (no bar)
--   3: name = red "[ JACKIE ]" text  ; selected row = translucent YELLOW HIGHLIGHT BAR
local dlgBoxWarned = false

-- Exact colors Antonia pulled from the game (RGBA 0-1):
local COL = {
  unsel = { 0.451, 0.937, 0.941, 1.0 },  -- #73eff0  unselected choice text
  selTx = { 0.302, 0.082, 0.020, 1.0 },  -- #4d1505  selected text (dark, sits on the yellow bar)
  bar   = { 0.973, 0.859, 0.294, 1.0 },  -- #f8db4b  solid selection bar
  frame = { 0.453, 0.227, 0.224, 1.0 },  -- #743a39  red name-box frame
  -- v1.54: muted gold for a `final` (irreversible) choice that is NOT under the cursor. The game marks
  -- point-of-no-return options with a yellow plate; we keep the plate on such a row at all times, dim
  -- when unhighlighted and full-brightness (COL.bar) once the cursor lands on it. Dark selTx text stays
  -- legible on both shades, so a final row reads as "this one ends things" before you ever select it.
  barDim = { 0.663, 0.586, 0.200, 1.0 },
}

-- defensive flag builder: sum only the flags that actually exist on this CET build.
-- NOTE: AlwaysAutoResize is intentionally OMITTED - combined with Selectable it caused the
-- highlight bar to grow wider every frame. We set an explicit window size instead.
local function pickerWindowFlags()
  local f = 0
  for _, n in ipairs({ "NoTitleBar", "NoResize", "NoMove", "NoCollapse", "NoScrollbar",
                       "NoSavedSettings", "NoNav", "NoFocusOnAppearing", "NoMouseInputs",
                       "NoBackground" }) do
    local v = ImGuiWindowFlags[n]
    if type(v) == "number" then f = f + v end
  end
  return f
end

-- v1.42: the picker scales with the display, so the name plate has to scale with it too — otherwise a
-- 4K box gets a 1080p-sized "JACKIE" tag rattling around in the corner of it. drawDialogueBox stashes
-- the live scale on JL.ui.pickerScale just before it calls us.
local function drawNameChild(name)
  local P = Config.picker or {}
  local s = JL.ui.pickerScale or 1.0
  ImGui.PushStyleColor(ImGuiCol.Border, COL.frame[1], COL.frame[2], COL.frame[3], 1.0)
  ImGui.PushStyleVar(ImGuiStyleVar.ChildBorderSize, 1.0)   -- thin frame
  ImGui.BeginChild("##jkname", (P.nameW or 128.0) * s, (P.nameH or 34.0) * s, true)
  ImGui.PushStyleColor(ImGuiCol.Text, 0.80, 0.32, 0.30, 1.0)
  ImGui.Text(" " .. tostring(name or "JACKIE"):upper())
  ImGui.PopStyleColor(1)
  ImGui.EndChild()
  ImGui.PopStyleVar(1)
  ImGui.PopStyleColor(1)
end

local function drawChoiceRows(style)
  ImGui.BeginGroup()
  if style == 2 then
    -- selected = recolored text (no bar); for comparison.
    -- v1.54: no plate exists in this style, so a `final` row is marked by tinting its TEXT gold instead —
    -- otherwise the irreversible option would look identical to a safe one here.
    for i, c in ipairs(menu.choices) do
      local col = (i == menu.sel) and COL.bar or (c.final and COL.barDim) or COL.unsel
      ImGui.PushStyleColor(ImGuiCol.Text, col[1], col[2], col[3], 1.0)
      ImGui.Text(tostring(c.text or ""))
      ImGui.PopStyleColor(1)
    end
  else
    -- styles 1 & 3: SOLID yellow bar behind the selected row, sized to the TEXT width
    -- (explicit Selectable size -> no more growing bar).
    -- v1.54: the bar colour is now pushed PER ROW, not once for the whole list, because a `final`
    -- (irreversible) choice keeps its plate even when the cursor is elsewhere — just in the dimmer gold.
    for i, c in ipairs(menu.choices) do
      local label = " " .. tostring(c.text or "") .. " "
      local tw    = ImGui.CalcTextSize(label)            -- reflects the window font scale (set in Begin)
      local isSel = (i == menu.sel)
      local plate = isSel or (c.final == true)           -- does this row get a yellow plate at all?
      local bar   = (isSel and COL.bar) or COL.barDim    -- cursor row = bright; a dim final row = muted gold
      local col   = plate and COL.selTx or COL.unsel     -- dark text on a plate, cyan without one
      ImGui.PushStyleColor(ImGuiCol.Header,        bar[1], bar[2], bar[3], 1.0)
      ImGui.PushStyleColor(ImGuiCol.HeaderHovered, bar[1], bar[2], bar[3], 1.0)
      ImGui.PushStyleColor(ImGuiCol.HeaderActive,  bar[1], bar[2], bar[3], 1.0)
      ImGui.PushStyleColor(ImGuiCol.Text, col[1], col[2], col[3], 1.0)
      ImGui.Selectable(label, plate, 0, tw, 0)           -- width = text width -> bar fits the text
      ImGui.PopStyleColor(4)
    end
  end
  ImGui.EndGroup()
end

-- v0.33e: true while any game menu is up (pause/ESC, map, inventory...). UI_System.IsInMenu
-- is the game's own blackboard flag, so this catches them all without per-menu hooks.
local function uiInMenu()
  local v = false
  pcall(function()
    local defs = Game.GetAllBlackboardDefs()
    local bb   = Game.GetBlackboardSystem():Get(defs.UI_System)
    v = bb:GetBool(defs.UI_System.IsInMenu)
  end)
  return v
end

-- ---------------------------------------------------------------------------
-- v1.02 BLAZE: real FADE TO BLACK (then back in). A full-screen black ImGui overlay whose alpha
-- animates out -> hold -> in. Covers ALL game UI, but SKIPS drawing while a game menu (pause/ESC/map)
-- is up (uiInMenu) so it never blacks those out. At full black it runs the injected `atBlack` callback
-- (the finale: teleport + quest-complete), so the swap is hidden. Stepped from onUpdate (tick) + onDraw
-- (draw). Globals (not top-level locals) => 200-cap safe.
-- ---------------------------------------------------------------------------
function startBlazeFade(atBlackFn)
  JL.blazeFade = JL.blazeFade or {}
  local f = JL.blazeFade
  f.outDur, f.holdDur, f.inDur = 0.8, 0.6, 0.9
  if f.phase then                                   -- already fading: just (re)arm the callback
    if atBlackFn then f.atBlack, f.ranBlack = atBlackFn, false end
    return
  end
  f.phase, f.t, f.alpha, f.ranBlack, f.atBlack = "out", 0, 0, false, atBlackFn
end

function blazeFadeTick(dt)
  local f = JL.blazeFade
  if not f or not f.phase then return end
  f.t = f.t + (dt or 0)
  if f.phase == "out" then
    f.alpha = math.min(1.0, f.t / (f.outDur or 0.8))
    if f.t >= (f.outDur or 0.8) then
      f.alpha = 1.0
      if not f.ranBlack then f.ranBlack = true; if f.atBlack then pcall(f.atBlack) end end
      f.phase, f.t = "hold", 0
    end
  elseif f.phase == "hold" then
    f.alpha = 1.0
    if f.t >= (f.holdDur or 0.6) then f.phase, f.t = "in", 0 end
  elseif f.phase == "in" then
    f.alpha = math.max(0.0, 1.0 - f.t / (f.inDur or 0.9))
    if f.t >= (f.inDur or 0.9) then f.phase, f.alpha, f.atBlack = nil, 0, nil end
  end
end

function drawBlazeFade()
  local f = JL.blazeFade
  if not f or not f.phase or (f.alpha or 0) <= 0.001 then return end
  if uiInMenu() then return end                     -- never cover the pause/ESC/map menus
  pcall(function()
    local sw, sh = 1920, 1080
    pcall(function() local x, y = ImGui.GetDisplaySize(); if x and x > 0 then sw, sh = x, y end end)
    local flags = 0
    for _, n in ipairs({ "NoTitleBar","NoResize","NoMove","NoCollapse","NoScrollbar",
                         "NoSavedSettings","NoNav","NoFocusOnAppearing","NoInputs","NoBringToFrontOnFocus" }) do
      local v = ImGuiWindowFlags[n]; if type(v) == "number" then flags = flags + v end
    end
    ImGui.SetNextWindowPos(0, 0, ImGuiCond.Always)
    ImGui.SetNextWindowSize(sw, sh, ImGuiCond.Always)
    ImGui.PushStyleColor(ImGuiCol.WindowBg, 0.0, 0.0, 0.0, f.alpha)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 0.0)
    ImGui.Begin("##blazefade", flags)
    ImGui.End()
    ImGui.PopStyleVar()
    ImGui.PopStyleColor()
  end)
end

local function drawDialogueBox()
  if not menu.shown or not menu.choices then return end
  -- v0.33e: don't draw over the pause/ESC menu (sit behind it); fully close if we've left to the
  -- main menu (no player), so a dangling picker can't survive the session. (closeChoiceMenu is
  -- defined below this fn, so reset inline.)
  if not Game.GetPlayer() then
    menu.shown, menu.choices, Branch.open, Branch.busy = false, nil, false, false
    return
  end
  if uiInMenu() then return end
  local style = JL.ui.pickerStyle or 1
  local ok, err = pcall(function()
    -- v1.42: TRUE-centre horizontally + sit in the lower fifth, at ANY resolution. See Config.picker.
    local P = Config.picker or {}
    local sw, sh = 1920.0, 1080.0
    pcall(function() local x, y = ImGui.GetDisplaySize(); if x and x > 0 and y and y > 0 then sw, sh = x, y end end)

    -- Uniform scale off the screen HEIGHT (not width): width varies wildly with ultrawides/21:9, height
    -- is what actually tracks "how big is a pixel here". Clamped so extremes stay usable.
    local s = math.max(P.minScale or 0.8, math.min(P.maxScale or 3.0, sh / (P.refH or 1080.0)))
    JL.ui.pickerScale = s                                  -- drawNameChild reads this
    local W, H = (P.baseW or 620.0) * s, (P.baseH or 240.0) * s

    local px = (sw - W) * 0.5 + (P.xOffset or 0.0) * s     -- genuinely centred (the old -150 nudge is gone)
    -- TOP EDGE of the box at `topFrac` of screen height, measured DOWN FROM THE TOP.
    -- v1.51: was 0.36, which parked the box just ABOVE the middle of the screen (Antonia: "now it's VERY
    -- high"). The "36%" she asked for was 36% measured UP FROM THE BOTTOM — i.e. topFrac = 1 - 0.36 = 0.64.
    -- The box is baseH/refH ≈ 22% of screen height, so it now spans 64%..86%: squarely in the lower half and
    -- still clear of the native subtitle band at the very bottom, which the old lower-fifth placement hit.
    -- `bottomMargin` stays a safety clamp for extreme aspect ratios / scale clamps; at 0.64 it doesn't bind.
    -- Both are fractions of the screen, so this holds identically at any resolution.
    local py = (P.topFrac or 0.64) * sh
    py = math.min(py, sh - H - (P.bottomMargin or 0.02) * sh)
    py = math.max(py, 0.0)

    ImGui.SetNextWindowPos(px, py, ImGuiCond.Always)
    ImGui.SetNextWindowSize(W, H, ImGuiCond.Always)       -- fixed (transparent) -> stable layout
    ImGui.Begin("##jkpicker", pickerWindowFlags())
    ImGui.SetWindowFontScale((P.baseFont or 1.45) * s)
    if style == 3 then
      ImGui.PushStyleColor(ImGuiCol.Text, 0.80, 0.32, 0.30, 1.0)
      ImGui.Text("[ " .. tostring(menu.title or "JACKIE"):upper() .. " ]")
      ImGui.PopStyleColor(1)
    else
      drawNameChild(menu.title)
    end
    ImGui.SameLine(0, 16)
    drawChoiceRows(style)
    ImGui.SetWindowFontScale(1.0)
    ImGui.End()
  end)
  if not ok and not dlgBoxWarned then
    log("PICKER draw FAILED (style " .. tostring(style) .. "): " .. tostring(err)); dlgBoxWarned = true
  end
end

-- v0.33: while Jackie is your COMPANION (following you), every face-to-face talk node also
-- offers a "send him off" choice that walks him away + despawns him. Returns a FRESH list so
-- the config tree is never mutated. Not added during a CALL (you can't call him while he's with
-- you anyway) - guarded by JL.summon.active + the tree not being the call tree.
local function withCompanionExtras(choices)
  if not JL.summon.active then return choices end
  if bstate.tree == Config.callTree
     or bstate.tree == Config.reunionCallTree then return choices end  -- not on a call
  if Config.date and bstate.tree == Config.date.tree then return choices end -- and not mid-date (no recursion)
  if bstate.tree == Config.reunionMeetTree then return choices end  -- v0.85: no "send off" during the first meeting
  -- v0.83: NEVER offer "Head home, Jackie" during a dinner outing — dismissing a SEATED puppet (role
  -- cleared, in a sit workspot) doesn't stand him up and crashes the game. The dinner "Enough chillin',
  -- let's go" option (seatedTree) is the safe way to end the outing.
  if JL.dinner.phase then return choices end
  -- v0.81: dinner invite + "Head home, Jackie" only appear on the tree's START node (the MAIN talk). Once
  -- V dives into a sub-branch the convo just plays out and closes; to dismiss/invite again she reopens the
  -- conversation. Keeps sign-off branches clean and dismiss out of every follow-up node.
  local t = bstate.tree
  if not (t and t.nodes and bstate.node == t.nodes[t.start]) then return choices end
  local out = {}
  for _, c in ipairs(choices or {}) do out[#out + 1] = c end
  -- v0.39: dinner invite (gated by dateUnlocked; for now always shown). Starts the date tree.
  if Config.date and dateUnlocked() then
    out[#out + 1] = {
      text   = Config.date.inviteText or "Hey - you hungry?",
      to     = nil,
      action = "start_date",
    }
  end
  out[#out + 1] = {
    text   = (Config.dismiss and Config.dismiss.choiceText) or "Head home, Jackie.",
    to     = nil,
    action = "dismiss_walkaway",
  }
  return out
end

-- v0.41/v0.52: on the date tree's restaurant-picker node, auto-build a choice per restaurant (action
-- "dine:<key>"), shown BEFORE the node's static choices ("You pick" / raincheck). v0.52: only `venuesShown`
-- (default 4) RANDOM venues from the full pool are offered. Runs once per menu-open (branchTick), so the
-- random selection stays stable while the picker is up.
local function withDateChoices(node, choices)
  if not (node and node.restaurantPicker and Config.date and Config.date.restaurants) then return choices end
  local pool = {}
  for _, r in ipairs(Config.date.restaurants) do if r.pos then pool[#pool + 1] = r end end
  for i = #pool, 2, -1 do                                  -- Fisher-Yates shuffle
    local j = i; pcall(function() j = math.random(1, i) end)
    pool[i], pool[j] = pool[j], pool[i]
  end
  local n = math.min((Config.date.venuesShown or 4), #pool)
  local out = {}
  for i = 1, n do
    local r = pool[i]
    out[#out + 1] = { text = r.name .. ".", to = nil, action = "dine:" .. r.key }
  end
  for _, c in ipairs(choices or {}) do out[#out + 1] = c end
  return out
end

local function openChoiceMenu(choices, title)
  -- Per-choice options, resolved once each time the menu opens:
  --  • v0.83 `chance` (0..1): the choice only APPEARS with that probability (re-rolled per open) — used
  --    for the random "get it off your chest" dinner topics. A choice with no `chance` always shows.
  --  • v0.81 `textPool` (array): display a RANDOM line from it (like Jackie's jackiePool replies shuffle).
  --  • v1.54 `once = "<key>"`: a ONE-TIME branch. Once the player picks it, it's struck off for the rest of
  --    THIS conversation (bstate.taken) and never re-offered — how the reunion call's hub lets V work
  --    through the bike / her-last-months / the-desert topics one by one without repeating one.
  --  • v1.54 `final = true`: an IRREVERSIBLE choice (ends the call). Purely cosmetic here — drawChoiceRows
  --    paints the row with the game's yellow "point of no return" background. Put it FIRST in the list.
  --  • v1.54 `cond = function() return <bool> end`: the choice only appears when the predicate holds —
  --    e.g. the face-to-face bike beats, which depend on what V decided about the Arch on the call. A
  --    predicate that ERRORS is treated as false, so a bad cond hides its choice instead of crashing.
  local shown = {}
  for _, c in ipairs(choices or {}) do
    local appear = true
    if c.chance then local r = 1.0; pcall(function() r = math.random() end); appear = (r < c.chance) end
    if c.once and bstate.taken and bstate.taken[c.once] then appear = false end   -- v1.54: already walked this branch
    if appear and c.cond then
      local ok, res = pcall(c.cond)
      appear = (ok and res == true)
    end
    if appear then
      -- v1.2: resolve the DISPLAY text into a shallow COPY so re-rolling a textPool or switching
      -- relationship mode never clobbers the config's base text. In Hermano mode a choice's `m`
      -- override ({text=} or {textPool=}) wins; otherwise the base choice text is used.
      local sc = {}; for k, v in pairs(c) do sc[k] = v end
      local src  = (c.m and jlHermano()) and c.m or c
      local pool = src.textPool
      if pool and #pool > 0 then
        local i = 1; pcall(function() i = math.random(1, #pool) end)
        sc.text = pool[i]
      elseif src.text then
        sc.text = src.text
      end
      shown[#shown + 1] = sc
    end
  end
  -- safety: never open an empty menu. Fall back only to choices that are still LEGAL (a spent `once`
  -- branch must stay spent — resurrecting it would let the player replay a hub topic).
  if #shown == 0 then
    for _, c in ipairs(choices or {}) do
      if not (c.once and bstate.taken and bstate.taken[c.once]) then shown[#shown + 1] = c end
    end
    if #shown == 0 then shown = choices end   -- everything was spent -> last resort, show the raw list
  end
  menu.choices, menu.sel, menu.title = shown, 1, title or "Jackie"
  menu.shown, Branch.open = true, true
  log("Branch: menu open (" .. tostring(#shown) .. " choices). Cycle key=move, F=select.")
end

local function closeChoiceMenu()
  menu.shown, Branch.open, menu.choices = false, false, nil
end

-- Branch.finish (v0.80): the ONE authoritative "a conversation has ENDED" tool. Every path that ends a
-- talk should funnel through here so the on-screen overlay/menu AND the bottom subtitle band are ALWAYS
-- cleaned up together — no more per-branch bookkeeping. It's idempotent (safe to call twice) and is
-- backed by subtitleWatchdogTick (onUpdate) as a guaranteed safety net for any path that still forgets.
Branch.finish = function(reason)
  closeChoiceMenu()                 -- close the ImGui choice picker + drop Branch.open
  Branch.open, Branch.busy = false, false
  pcall(hideJackieChoiceBox)        -- clear the native "[F] Talk" prompt
  bstate.node, bstate.openAt = nil, nil
  bstate.pending, bstate.pendingAt, bstate.pendingAction = nil, nil, nil
  bstate.tree, bstate.talkCooldownKey = nil, nil
  bstate.taken = nil                -- v1.54: drop the one-time-choice ledger with the conversation
  hideSubtitle()                    -- wipe the bottom band NOW (watchdog would catch it too)
  if reason then JL.ui.status = reason end
end

-- Pick a line from a node's jackiePool. Entries may carry `chance` (0..1) = an independent roll
-- for that RARE line (e.g. chance=0.01 -> ~1% of the time). If no chance-gated line hits, pick
-- uniformly among the normal (non-chance) lines. So common lines stay common and a flagged line
-- only slips in occasionally. (v0.34b)
local function pickPoolLine(pool)
  local normal = {}
  for _, e in ipairs(pool) do
    if e.chance then
      local r = 1.0; pcall(function() r = math.random() end)
      if r < e.chance then return e end
    else
      normal[#normal + 1] = e
    end
  end
  if #normal == 0 then normal = pool end                  -- safety: every entry was chance-gated
  local i = 1; pcall(function() i = math.random(1, #normal) end)
  return normal[i]
end

-- enter a node: Jackie speaks, then (after his line) the choices appear.
-- `tree` lets a CALL (Config.callTree) reuse this engine; it persists in bstate.tree so
-- mid-conversation Branch.start(nextNode) stays in the same tree. Default = dialogueTree.
Branch.start = function(nodeKey, tree)
  tree = tree or bstate.tree or Config.dialogueTree
  if not tree or not tree.nodes then return end
  -- v1.54: entering a DIFFERENT tree = a brand-new conversation, so wipe the one-time-choice ledger
  -- (bstate.taken). Within one tree it persists, which is what makes a HUB node work: a branch the
  -- player already walked (`once = "<key>"`) stays hidden when they come back to the hub.
  if bstate.tree ~= tree then bstate.taken = nil end
  bstate.tree = tree
  nodeKey = nodeKey or tree.start
  local node = tree.nodes[nodeKey]
  if not node then log("Branch: node '" .. tostring(nodeKey) .. "' missing"); return end
  Branch.busy = true
  Branch.open = false
  closeChoiceMenu()
  pcall(hideJackieChoiceBox)        -- clear the native "[F] Talk" prompt while we talk
  bstate.node = node
  -- a node may give a single `jackie` line OR a `jackiePool` (array) we pick from (rarity-aware)
  local jline = node.jackie
  if node.jackiePool and #node.jackiePool > 0 then
    jline = pickPoolLine(node.jackiePool)
  end
  jline = jlVar(jline)   -- v1.2: swap in the Hermano (male-V) line if this entry carries an `m = {...}`
  -- v1.56: a tree may declare `muteFallback = true` -> no grunt on its text-only lines (see speakJackieLine).
  local secs = speakJackieLine(jline and jline.text, jline and jline.sfx, tree.muteFallback)
  bstate.openAt = (JL.clock or 0) + secs + 0.4
end

-- act on a choice (idx optional -> highlighted). Shows the player's chosen line as a
-- subtitle for ~1s, THEN advances to Jackie's reply / ends (handled in branchTick).
Branch.confirm = function(idx)
  if not Branch.open or not menu.choices then return end
  idx = idx or menu.sel
  local c = menu.choices[idx]
  if not c then return end
  closeChoiceMenu()
  log("Branch: selected #" .. tostring(idx) .. " '" .. tostring(c.text) .. "'")
  if c.once then                    -- v1.54: strike this branch off the hub for the rest of the conversation
    bstate.taken = bstate.taken or {}
    bstate.taken[c.once] = true
  end
  -- v1.54 `fact = { name = "...", value = N }`: record the choice into the SAVE, right now. A choice that
  -- routes onward (`to = "hub"`) can't fire an `action` — actions only run on a terminal choice — so this
  -- is how a mid-conversation decision (V keeps the Arch / gives it back) survives to be read later.
  if c.fact and c.fact.name then jlSetFactNum(c.fact.name, c.fact.value or 1) end
  hideSubtitle()
  -- v0.94: on the reunion beats, scale V's chosen line to its length too (so long picks aren't cut off).
  local hold = (isReunionBeat() and readingSecs(c.text))
               or (Config.dialogue and Config.dialogue.choiceHold) or 2.5
  showDialogueText("V", c.text or "", hold, Game.GetPlayer())  -- V's pick, shown before Jackie replies
  bstate.pending       = c.to or "__end__"
  bstate.pendingAction = c.action                              -- e.g. "summon_arrival" (fires at call end)
  bstate.pendingAt     = (JL.clock or 0) + hold                -- wait out V's line before Jackie replies
end

-- move the highlight (wraps); the ImGui box redraws every frame, so no push needed
Branch.move = function(delta)
  if not Branch.open or not menu.choices then return end
  local n = #menu.choices
  if n == 0 then return end
  menu.sel = ((menu.sel - 1 + delta) % n) + 1
end

-- v0.32: pick the talk tree for WHERE JACKIE CURRENTLY IS. If he's idle-spawned at a named
-- place with its own tree (noodle/coyote/afterlife/misty...), use that; otherwise fall back
-- to the short `everywhere` tree. Returns tree, key. Never nil if Config.locationDialogue.everywhere exists.
local function currentTalkTree()
  -- v0.83: seated at dinner -> casual small-talk tree (no dismiss; "Enough chillin'..." stands him up).
  if JL.dinner.phase == "seated" and Config.date and Config.date.seatedTree then
    return Config.date.seatedTree, "_dinner"
  end
  local ld = Config.locationDialogue
  if ld then
    local key = JL.idle.locationKey                 -- nil when summoned/following or unscheduled
    if key and ld[key] then return ld[key], key end
    if ld.everywhere then return ld.everywhere, "everywhere" end
  end
  return Config.dialogueTree, "_legacy"             -- safety net if locationDialogue is missing
end

-- start at the tree root if looking at Jackie (called from the F hook). Returns true if a
-- conversation actually started, false otherwise (not looking / busy / on DONE cooldown) so
-- the F hook can decide whether to play a plain grunt instead.
Branch.kick = function()
  if Branch.busy then return false end
  if not lookedAtJackie() then return false end
  local tree, key = currentTalkTree()
  if not tree or not tree.nodes then return false end
  -- DONE + cooldown (only the `everywhere` backup sets cooldownSeconds): if we're still
  -- inside the cooldown window, don't open dialogue -> the hook plays a grunt instead.
  -- EXCEPTION: while he's your active companion the cooldown is ignored, so the "send Jackie
  -- off" choice is always reachable and talking to your follower never degrades to a grunt.
  local cd = tree.cooldownSeconds
  if cd and not JL.summon.active then
    local doneAt = JL.talkDone[key]
    if doneAt and (JL.clock or 0) - doneAt < cd then
      return false
    end
  end
  -- remember which tree to mark DONE when it ends (cooldown'd trees only, and not while companion)
  bstate.talkCooldownKey = (cd and not JL.summon.active) and key or nil
  Branch.start(nil, tree)   -- the chosen talk tree, never a leftover call tree
  return true
end

-- ---------------------------------------------------------------------------
-- HOLOCALL (v0.28): "Calling Jackie..." -> he picks up (runs Config.callTree in the
-- same choice box) -> asking him onto a gig ends the call and, spawnDelay seconds later,
-- spawns him spawnDistance metres ahead of V; companion AI then walks him in.
-- Reuses the existing voiced dialogue engine + AMM summon; no native phone / death flag.
-- ---------------------------------------------------------------------------

-- A point Config.call.spawnDistance metres ahead of V (so he visibly walks in). Tries
-- several ways to read V's facing; logs which one worked + the final point so a bad spawn
-- is debuggable from the console. NEVER returns V's exact spot (that = "in your face").
local function arrivalPoint()
  local pl = Game.GetPlayer(); if not pl then return nil end
  local pp; pcall(function() pp = pl:GetWorldPosition() end)
  if not pp then return nil end
  local d = (Config.call and Config.call.spawnDistance) or 18.0

  -- 1) GetWorldForward (Vector4); 2) derive from world orientation quaternion; 3) camera forward.
  local fwd, how
  pcall(function() fwd = pl:GetWorldForward() end)
  if fwd then how = "GetWorldForward" end
  if not fwd then
    pcall(function()
      local q = pl:GetWorldOrientation()
      if q then local f = Quaternion.GetForward(q); if f then fwd = f; how = "orientation" end end
    end)
  end
  if not fwd then
    pcall(function()
      local cs = Game.GetCameraSystem()
      if cs and cs.GetActiveCameraForward then local f = cs:GetActiveCameraForward(); if f then fwd = f; how = "camera" end end
    end)
  end

  local pt
  if fwd then
    pt = Vector4.new(pp.x + fwd.x * d, pp.y + fwd.y * d, pp.z + fwd.z * d, 1.0)
  else
    pt = Vector4.new(pp.x + d, pp.y, pp.z, 1.0)   -- last resort: +X so he's NEVER on top of V
    how = "fallback+X"
  end
  log(("Call: arrival point via %s -> { %.2f, %.2f, %.2f } (V at %.2f, %.2f, %.2f)")
      :format(tostring(how), pt.x, pt.y, pt.z, pp.x, pp.y, pp.z))
  return pt
end

-- ---------------------------------------------------------------------------
-- NATIVE holocall driver (v0.29): drive the game's real phone call UI directly via
-- PhoneSystem:TriggerCall (recipe from docs/native_phone_probes.md). Lets us show Jackie's
-- real avatar + ringtone, then (later) hand off to our voice + dialogue box.
-- ---------------------------------------------------------------------------
-- Resolve a quest phone-call enum value: prefer the CET-exposed enum global, else integer.
local function phoneEnum(enumName, fieldName, intFallback)
  local v
  pcall(function() v = _G[enumName] and _G[enumName][fieldName] end)
  if v ~= nil then return v end
  return intFallback
end

local function getPhoneSystem()
  local ps
  pcall(function() ps = Game.GetScriptableSystemsContainer():Get(CName.new("PhoneSystem")) end)
  return ps
end

-- Fire one phase of a native call. phaseName/Int: IncomingCall/1, StartCall/2, EndCall/3.
local function triggerNativeCall(callId, phaseName, phaseInt)
  local ps = getPhoneSystem()
  if not ps then JL.ui.status = "Native call: PhoneSystem unavailable"; log("Native call: no PhoneSystem"); return false end
  local mode    = phoneEnum("questPhoneCallMode",    "Video",   2)
  local phase   = phoneEnum("questPhoneCallPhase",   phaseName, phaseInt)
  local visuals = phoneEnum("questPhoneCallVisuals", "Default", 0)
  local ok, err = pcall(function()
    JL.call.selfTriggering = true        -- so our own call doesn't re-fire the player-call hijack hook
    ps:TriggerCall(mode, false, CName.new(callId), true, phase, false, false, false, visuals)
  end)
  JL.call.selfTriggering = false
  JL.ui.status = ("Native call %s -> %s : %s"):format(callId, phaseName, ok and "ok" or "FAIL")
  log(("Native call: TriggerCall('%s', %s) ok=%s %s"):format(callId, phaseName, tostring(ok), ok and "" or tostring(err)))
  return ok
end

-- Open the silent, persistent native holocall window (StartCall) as the call "canvas".
local function openNativeCallWindow()
  if not (Config.nativeCall and Config.nativeCall.useNativeWindow) then return end
  triggerNativeCall(JL.call.activeId or (Config.nativeCall and Config.nativeCall.id) or "jackie_dead", "StartCall", 2)
  JL.call.nativeOpen = true
end

-- Close the native holocall window (EndCall). Safe to call when none is open.
local function closeNativeCallWindow()
  if not JL.call.nativeOpen then return end
  JL.call.nativeOpen = false
  triggerNativeCall(JL.call.activeId or (Config.nativeCall and Config.nativeCall.id) or "jackie_dead", "EndCall", 3)
  JL.call.activeId = nil    -- v1.33: clear the alive-swap override so the next call starts clean
end

-- A random V hang-up sign-off (text only; V has no voice).
local function pickFarewell()
  local f = Config.callFarewells
  if not f or #f == 0 then return "Later." end
  local i = 1
  pcall(function() i = math.random(1, #f) end)
  return f[i] or f[1]
end

-- Teleport a spawned NPC to `pos` (used to place a called-in Jackie at distance).
local function teleportEntity(handle, pos)
  if not handle or not pos then return end
  pcall(function()
    local tf = Game.GetTeleportationFacility()
    if tf then tf:Teleport(handle, pos, EulerAngles.new(0.0, 0.0, 0.0)) end
  end)
end

-- Run an action attached to a finished choice.
--   "summon_arrival"   -> schedule the delayed spawn-at-distance (spawn happens in arrivalTick).
--   "dismiss_walkaway" -> Jackie drops follower role, walks off, despawns (leavingTick).
--   "start_date"       -> begin the dinner conversation (Config.date.tree).
--   "date_accept"      -> dinner accepted: reset his companion clock (+resetCompanionHours).
local function runCallAction(name)
  if name == "dismiss_walkaway" then
    if JL.summon.active then
      -- v0.40: if he's near the venue the schedule wants him at, walk him BACK there + go idle
      -- (re-join the cycle) instead of despawning. Else, the normal walk-away-and-despawn.
      local returned = false
      if returnToPost then local ok, res = pcall(returnToPost); returned = ok and res == true end
      if not returned and startLeaving then pcall(startLeaving) end
    end
    return
  end
  if name == "start_date" then
    if not (Config.date and Config.date.tree) then return end
    local D = Config.date
    -- v0.47: the "not twice a day" refusal now fires HERE, right after V's invite, so an
    -- on-cooldown Jackie declines immediately with refuseText and the venue picker never shows.
    local g  = getGameSeconds()
    local cd = (D.resetCooldownHours or 24.0) * 3600
    if JL.dinner.lastResetGame and g and (g - JL.dinner.lastResetGame) < cd then
      pcall(function() speakJackieLine(D.refuseText, D.refuseSfx) end)
      JL.ui.status = "Jackie already ate out today - maybe tomorrow."
      log("Dinner: refused at invite (within " .. tostring(D.resetCooldownHours or 24) .. "h of his last dinner).")
      return
    end
    -- v1.57: he passed the cooldown gate, so the date tree is about to open. If he was mid-walk-off (his
    -- shift expired), STOP him here — otherwise he strolls away, and often despawns, while V is still
    -- picking a restaurant. Only a SHORT grace (`abortGraceHours`), so taking a raincheck at the picker
    -- doesn't quietly hand him a whole extra shift; startDinnerWalk extends it properly if V goes through.
    pcall(function() jlAbortDeparture(D.abortGraceHours or 1.0, "dinner invite") end)
    pcall(function() Branch.start(nil, Config.date.tree) end)
    return
  end
  if type(name) == "string" and name:sub(1, 5) == "dine:" then   -- v0.41: V picked a restaurant
    pcall(function() startDinnerWalk(name:sub(6)) end)
    return
  end
  if name == "dinner_leave" then   -- v0.83: "Enough chillin', let's go" — after his reply, get up + re-follow.
    -- dinnerTick's `seated` phase owns the stand-up (it has the workspot/collision helpers). We just flag
    -- it; the flag also tells it NOT to re-speak getUpText (the seatedTree already said his parting line).
    JL.dinner.leaveNow = true
    return
  end
  -- (v0.94b: the "return_bike" action handler was removed with the retired firstCallTree — the Arch is
  -- now returned by the reunion_arrival handler below and the "Give bike back" debug button.)
  -- v0.85: the reunion CALL ended -> he comes to V on foot.
  -- v1.54: the Arch is only handed back if V actually PROMISED it on the call. The bike is now an
  -- OPTIONAL hub topic, so there are three outcomes, recorded in the `jackielives_bike` fact by the
  -- hub's bike choices (see JL_BIKE_* / Config.reunionCallTree):
  --   0 = never came up (V hung up without asking) · 1 = V said she'd kept it safe · 2 = V is keeping it.
  -- Only 1 returns the bike. 0 and 2 leave it in V's garage, and reunionMeetTree branches on the same
  -- fact so the face-to-face never thanks him for a bike he never got back.
  if name == "reunion_arrival" then
    if jlBikeOutcome() == JL_BIKE_RETURNED and jlReturnJackiesBike then
      pcall(jlReturnJackiesBike)                                              -- his Arch is his again
    end
    pcall(function() Game.GetQuestsSystem():SetFactStr("jackielives_daemon", 1) end)  -- launch daemon-removal quest (stub)
    local delay = (Config.call and Config.call.vehicleSpawnDelay) or 2.0
    JL.varrival.at      = (JL.clock or 0) + delay
    JL.varrival.useBike = false          -- FOOT walk-in (reuse the standard foot arrival)
    JL.reunionPending   = true           -- arrivalGreetTick plays reunionMeetTree instead of a greeting
    pcall(function() Retrieval.notifyArrivalPending() end)   -- v1.54: "Wait for Jackie" objective banner
    JL.ui.status = "Jackie's on his way in..."
    log("Reunion: " .. (keep and "V KEPT the Arch" or "bike returned") .. " + FOOT walk-in armed; reunionMeet pending.")
    return
  end
  if name == "reunion_complete" then   -- v0.85: first-meeting dialogue ended -> UNLOCK the mod
    pcall(function() Retrieval.completeReunion() end)
    -- v0.93: disarm the reunion smile boost + relax his face.
    pcall(function()
      if JL.smile.until_ > 0 or JL.smile.reunionActive then resetSmileFace(JL.smile.handle) end
      JL.smile.reunionActive, JL.smile.reunionForceUntil = false, 0
      JL.smile.until_, JL.smile.handle = 0, nil
    end)
    JL.ui.status = "Jackie's back. Mod unlocked."
    log("Reunion: complete -> REUNITED.")
    return
  end
  if name == "blaze_finale_complete" then   -- v1.07: Blaze finale conversation ended; Jackie stays your companion.
    JL.ui.status = "Blaze finale complete. Jackie's with you."
    log("[Blaze] finale conversation complete.")
    return
  end
  if name == "date_accept" then   -- legacy (pre-v0.41 date tree); harmless
    local ext = (Config.date and Config.date.resetCompanionHours) or 6.0
    armCompanionTimer(ext)
    JL.ui.status = ("Dinner's on - Jackie's stickin' around (+%.0f h)."):format(ext)
    log(("Date: companion clock reset (+%.1f game-hours)."):format(ext))
    return
  end
  if name ~= "summon_arrival" then return end
  if isMainQuestActive() then jlDeclineMainQuest(); return end
  if JL.summon.active then JL.ui.status = "Jackie's already with you."; return end
  -- v0.50: two modes only — both run through vehicleArrivalTick (foot = bikeless, bike = useBike).
  -- v0.51: player Esc-menu "Disable vehicle arrivals" (JL.disableVehicleArrivals) forces FOOT,
  -- regardless of Config.call.arrivalMethod — the bike arrival is buggy and players can opt out.
  local bike  = ((Config.call and Config.call.arrivalMethod) == "bike") and not JL.disableVehicleArrivals
  local delay = (Config.call and Config.call.vehicleSpawnDelay) or 1.0
  JL.varrival.at      = (JL.clock or 0) + delay
  JL.varrival.useBike = bike
  JL.ui.status = bike and ("Jackie's grabbin' his bike (%.0fs)..."):format(delay)
                       or ("Jackie's headin' over (%.0fs)..."):format(delay)
  log(("Call: %s arrival scheduled in %ss."):format(bike and "BIKE" or "FOOT", tostring(delay)))
end

-- v1.32: a call is "in progress" from the moment it's armed (ring) until the window closes
-- (nativeOpen) and the queued hang-up/watchdog clear. Guards startCall / onPlayerCalledJackie so
-- you can't stack a SECOND call over a live one (the old guards left a gap during the farewell/
-- hang-up window, when Branch.busy is already false but the call window is still up). Global (not a
-- top-level local) to respect the 200-locals cap.
function jlCallInProgress()
  local c = JL.call
  return (c.ringingAt or c.noAnswerAt or c.connectAt or c.hangupAt or c.watchdogAt or c.nativeOpen)
         and true or false
end

-- v1.33: live-tunable "temporarily unavailable" fix state, seeded ONCE from Config.nativeCall so the
-- CET "Call fix" buttons/slider can change mode/delay at runtime. Global (not a top-level local) for
-- the 200-locals cap. mode: "quick" | "instant" | "alive" | "vanilla".
function jlCallFix()
  if not JL.callfix then
    local nc = Config.nativeCall or {}
    JL.callfix = {
      mode        = nc.hijackMode        or "quick",
      delay       = nc.hijackHangupDelay or 0.75,
      ourRing     = nc.hijackOurRingSfx  == true,
      forceHijack = false,   -- v1.38 TEST: hijack even pre-shard (ignore the reachable-stage gate)
    }
  end
  return JL.callfix
end

-- v1.37: how long the ALIVE-mode ring plays before Jackie "picks up" — random in [alivePickupMin,
-- alivePickupMax] (default 1.2-3.0 s) so it feels human, not a fixed beat. Global -> 200-local cap safe.
function jlAliveRingSecs()
  local nc = Config.nativeCall or {}
  local lo, hi = nc.alivePickupMin or 1.2, nc.alivePickupMax or 3.0
  if hi < lo then lo, hi = hi, lo end
  local r = 0.5; pcall(function() r = math.random() end)   -- [0,1)
  return lo + r * (hi - lo)
end

-- Begin a holocall. With useNativeWindow: fire the native RING (IncomingCall) now; callTick
-- then aborts it (STOP) and switches to the CONNECT window before running our convo.
local function startCall()
  -- v0.85: in AWAITING_CALL (shard read, reunion not done) V CAN call — Jackie always answers.
  if not Retrieval.isUnlocked() and not Retrieval.isAwaitingCall() then
    JL.ui.status = Retrieval.unavailableMsg(); Retrieval.notifyUnavailable(); return       -- gated until the retrieval quest is done
  end
  if jlCallInProgress() then JL.ui.status = "Already on a call with Jackie."; return end   -- v1.32: no re-entrant call
  if Branch.open or Branch.busy or dlg.active then JL.ui.status = "Busy - finish the current talk first."; return end
  if JL.summon.active then JL.ui.status = "Jackie's already with you."; return end
  if isMainQuestActive() then jlDeclineMainQuest(); return end
  Branch.busy = true                       -- reserve so the look-prompt / talk don't fight the ring
  pcall(hideJackieChoiceBox)
  local id   = (Config.nativeCall and Config.nativeCall.id) or "jackie_dead"
  JL.call.activeId = id                        -- v1.33: keep callTick/window on the same contact
  local ring = (Config.call and Config.call.ringEvent) or ""
  if ring ~= "" then pcall(function() playVoice(ring) end) end
  if Config.nativeCall and Config.nativeCall.useNativeWindow then
    triggerNativeCall(id, "IncomingCall", 1)   -- native ring (avatar + ringtone)
  end
  -- v0.55: if Jackie's asleep he doesn't pick up — ring out, then auto hang up (no connect, no convo).
  if jackieAsleep() and not Retrieval.isAwaitingCall() then   -- v0.85: reunion call always connects
    local rs = (Config.call and Config.call.asleepRingSeconds) or 7.0
    showOnscreenMsg("Calling Jackie...", rs + 0.5)
    JL.call.noAnswerAt = (JL.clock or 0) + rs
    JL.ui.status = "Calling Jackie... (no answer — asleep)"
    log("Call: ringing... (Jackie asleep — he won't pick up).")
    return
  end
  local secs = (Config.call and Config.call.ringSeconds) or 2.0
  showOnscreenMsg("Calling Jackie...", secs + 0.5)
  JL.call.ringingAt = (JL.clock or 0) + secs
  JL.ui.status = "Calling Jackie..."
  log("Call: ringing...")
end

-- Stepped from onUpdate. Sequences the call:
--  ringingAt   -> abort native ring (STOP/EndCall), arm connectAt (+0.2s)
--  connectAt   -> open the CONNECT window (StartCall), start our branching convo
--  hangupAt    -> (set at convo end) hide the farewell, hang up (EndCall), run the queued action
--  watchdogAt  -> safety: force hang up if a call somehow never completes (no permanent stuck call)
local function callTick()
  local now = JL.clock or 0
  -- v1.33: EndCall/connect the SAME contact we rang (alive-swap mode rings "jackie", not "jackie_dead").
  local id  = JL.call.activeId or (Config.nativeCall and Config.nativeCall.id) or "jackie_dead"
  local native = Config.nativeCall and Config.nativeCall.useNativeWindow

  -- v0.98: reset the vanilla-call interrupt pulse (see jlSilenceVanillaJackieCall) so a one-shot
  -- interrupt can't linger and block a legitimate later holocall.
  if JL.call.clearInterruptAt and now >= JL.call.clearInterruptAt then
    JL.call.clearInterruptAt = nil
    pcall(function() Game.GetQuestsSystem():SetFactStr("holo_interrupt_call", 0) end)
  end

  -- v0.55: asleep -> the call just rings out, then hangs up. No pickup, no convo.
  if JL.call.noAnswerAt and now >= JL.call.noAnswerAt then
    JL.call.noAnswerAt = nil
    if native then triggerNativeCall(id, "EndCall", 3) end   -- hang up the ring
    showOnscreenMsg("No answer.", 2.5)
    JL.ui.status = "No answer — Jackie's asleep."
    log("Call: no answer (Jackie asleep) -> hung up.")
    Branch.busy = false
    return
  end

  -- v1.38 DEFERRED ALIVE SWAP. The dead call is killed up-front in the observer; a couple frames later
  -- (once it's really gone) we ring the ALIVE avatar HERE. Deferring stops the swap racing the game's
  -- just-started dead call (synchronous swapping let the dead card + "unavailable" voicemail win).
  if JL.call.aliveSwapAt and now >= JL.call.aliveSwapAt then
    JL.call.aliveSwapAt = nil
    local deadId  = (Config.nativeCall and Config.nativeCall.id) or "jackie_dead"
    local aliveId = JL.call.activeId or (Config.nativeCall and Config.nativeCall.aliveId) or "jackie"
    pcall(function() triggerNativeCall(deadId,  "EndCall",     3) end)   -- belt-and-suspenders: dead card gone
    pcall(function() triggerNativeCall(aliveId, "IncomingCall", 1) end)  -- ring the alive avatar (see-through holo)
    local aring = (Config.call and Config.call.ringEvent) or ""
    if aring ~= "" then pcall(function() playVoice(aring) end) end
    JL.call.ringingAt = now + jlAliveRingSecs()                          -- random 1.2-3.0s, then connect
    JL.ui.status = "Jackie's phone ringing (alive)..."
    log("Call: deferred alive-swap -> ringing the live avatar.")
  end

  if JL.call.ringingAt and now >= JL.call.ringingAt then
    JL.call.ringingAt = nil
    if native then
      triggerNativeCall(id, "EndCall", 3)        -- STOP: abort the canned native ring
      JL.call.connectAt = now + 0.2              -- brief gap, then connect
    else
      JL.call.connectAt = now                    -- text-only flow: go straight to the convo
    end
  end

  if JL.call.connectAt and now >= JL.call.connectAt then
    JL.call.connectAt = nil
    if native then openNativeCallWindow() end     -- CONNECT: empty transparent window stays up
    JL.call.watchdogAt = now + 300                -- safety net (force-end if a call never completes)
    Branch.busy = false                           -- Branch.start re-sets it
    -- v0.85: in AWAITING_CALL this is THE reunion call (long, emotional, ends with him walking in);
    -- it folds in the bike-back beat. Every other call = the normal tree. (v0.94b: the old
    -- firstCallTree bike-back fallback was retired — the reunion + reunion_arrival cover it.)
    local tree = Config.callTree
    if Retrieval.isAwaitingCall() and Config.reunionCallTree then
      tree = Config.reunionCallTree
    end
    Branch.start(tree and tree.start or nil, tree)
  end

  if JL.call.hangupAt and now >= JL.call.hangupAt then
    JL.call.hangupAt = nil
    JL.call.watchdogAt = nil
    hideSubtitle()
    pcall(closeNativeCallWindow)                  -- hang up
    local act = JL.call.hangupAction; JL.call.hangupAction = nil
    JL.ui.status = "Call ended."; log("Call: ended.")
    if act then pcall(function() runCallAction(act) end) end
  end

  if JL.call.watchdogAt and now >= JL.call.watchdogAt then
    JL.call.watchdogAt = nil
    if JL.call.nativeOpen then pcall(closeNativeCallWindow) end
    Branch.busy = false
    log("Call: watchdog force-ended a lingering call.")
  end
end

-- v0.98 BUGFIX. When V dials Jackie in the Heist->Ofrenda window, vanilla fires
-- base\quest\holocalls\jackie\jackie_holocall.scene -> "number unavailable" + V's
-- "Jack, I got no idea where you are" — and it plays OVER our authored call. Our call is a
-- native PhoneSystem TriggerCall (contact 'jackie_dead'), which does NOT use these holo_* facts,
-- so zeroing them is safe for us. We (1) dis-arm the request facts so the scene can't (re)fire,
-- and (2) pulse holo_interrupt_call=1 — the scene's OWN interrupt branch — to cut it if it already
-- started; callTick resets that pulse a few seconds later so it can't block a legit future call.
-- Global (no top-level local) for the 200-cap. TEST: if this ever cuts our OWN call, drop the
-- holo_interrupt_call line and rely on the dis-arm alone.
function jlSilenceVanillaJackieCall()
  pcall(function()
    local qs = Game.GetQuestsSystem(); if not qs then return end
    qs:SetFactStr("holo_v_calls_jackie_start_activate", 0)   -- dis-arm the request (whole window)
    qs:SetFactStr("holo_v_calls_jackie_end_activate",   0)
    qs:SetFactStr("holo_v_calls_jackie_start",          0)
    qs:SetFactStr("holo_interrupt_call",                1)   -- cut it if already mid-play
  end)
  JL.call.clearInterruptAt = (JL.clock or 0) + 3.0           -- reset the interrupt pulse soon
  log("[CallFix] silenced vanilla Jackie 'unavailable' holocall (dis-arm + interrupt pulse).")
end

-- The player dialled Jackie from the in-game phone (the game fired IncomingCall). Route it into
-- our flow: the native ring is already playing, so we just arm callTick (STOP -> CONNECT -> convo)
-- without re-firing IncomingCall ourselves.
local function onPlayerCalledJackie()
  if not Retrieval.isUnlocked() and not Retrieval.isAwaitingCall() then return end  -- gated: let the game's own call ring out (no hijack)
  -- v1.38: the dead call is ALREADY killed in the observer before we get here, so every bail below just
  -- means "no call starts" — never "the dead voicemail plays". Log WHICH guard bails so we can diagnose.
  if jlCallInProgress() then log("[Hijack] bail: a call is already in progress (jlCallInProgress)."); return end
  if Branch.open or Branch.busy or dlg.active then log("[Hijack] bail: mid-conversation (Branch.open/busy or dlg.active)."); return end
  if JL.summon.active then log("[Hijack] bail: Jackie already summoned (companion) — can't 'call' him."); return end
  if isMainQuestActive() then log("[Hijack] bail: main quest active -> decline."); jlDeclineMainQuest(); return end
  -- v0.55: asleep -> he doesn't pick up (dead card already killed; just no connect).
  if jackieAsleep() and not Retrieval.isAwaitingCall() then   -- v0.85: reunion call always connects
    JL.ui.status = "Jackie's not pickin' up (asleep)."
    log("[Hijack] bail: Jackie asleep (schedule window) -> no pickup.")
    return
  end
  -- v1.33: the "temporarily unavailable" fix. The Observer just caught the game ringing the DEAD
  -- contact (jackie_dead), which flashes the "number unavailable" card. jlCallFix() holds the live
  -- mode/delay (CET "Call fix" section; seeded from Config.nativeCall). Branch on how to kill it.
  local cf  = jlCallFix()
  local m   = cf.mode or "quick"
  if m == "vanilla" then                                 -- A/B baseline: don't hijack at all
    JL.ui.status = "Call: vanilla (not hijacking — game's own call rings out)."
    log("Hijack: mode=vanilla -> left the game's call alone.")
    return
  end

  Branch.busy = true
  local id  = (Config.nativeCall and Config.nativeCall.id) or "jackie_dead"
  local now = JL.clock or 0
  if cf.ourRing then                                     -- optional (default OFF -> no "rings twice")
    local ring = (Config.call and Config.call.ringEvent) or ""
    if ring ~= "" then pcall(function() playVoice(ring) end) end
  end

  if m == "instant" then
    JL.call.activeId = id                                         -- EndCall/connect the dead contact
    pcall(function() triggerNativeCall(id, "EndCall", 3) end)     -- kill the dead ring THIS frame
    JL.call.connectAt = now + 0.15                                -- straight to our window, no ring/card
  elseif m == "alive" then
    local aliveId = (Config.nativeCall and Config.nativeCall.aliveId) or "jackie"
    JL.call.activeId = aliveId                                    -- callTick EndCall/connects "jackie"
    pcall(function() triggerNativeCall(id, "EndCall", 3) end)     -- kill the dead card again (attempt 2)
    -- v1.38: DON'T ring alive this frame — the game's dead call is still settling. Defer ~0.35 s so it's
    -- gone first, then callTick's aliveSwapAt block rings the live avatar + arms the connect->dialogue.
    JL.call.aliveSwapAt = now + 0.35
  else                                                   -- "quick": short dead ring, then EndCall->connect
    JL.call.activeId = id
    JL.call.ringingAt = now + (cf.delay or 0.75)
  end
  JL.ui.status = "Jackie picking up... (" .. m .. ")"
  log(("Hijack: mode=%s delay=%.2f ourRing=%s -> our flow."):format(m, cf.delay or 0.75, tostring(cf.ourRing)))
end

-- v1.37: run the FULL alive-call flow on demand — ring the live `jackie` avatar (see-through holo),
-- random pickup delay, connect, then our branching dialogue — WITHOUT the in-game phone. Used by the
-- CET "Test ALIVE call" button (the raw RING/CONNECT buttons only fire one phase, no dialogue).
-- callTick drives ring->EndCall->connect->Branch.start from the timers we arm here. Global -> cap safe.
function jlStartAliveCall()
  -- v1.38: it's a TEST button — clear any stale/stuck call state so a prior aborted attempt (e.g. a
  -- lingering Branch.busy) can't silently block it. Then run the full flow.
  JL.call.ringingAt, JL.call.connectAt, JL.call.aliveSwapAt = nil, nil, nil
  JL.call.noAnswerAt, JL.call.hangupAt, JL.call.watchdogAt = nil, nil, nil
  if JL.call.nativeOpen then pcall(closeNativeCallWindow) end
  Branch.busy = false
  if Branch.open or dlg.active then JL.ui.status = "Finish the current talk first."; return end
  Branch.busy = true
  local aliveId = (Config.nativeCall and Config.nativeCall.aliveId) or "jackie"
  local deadId  = (Config.nativeCall and Config.nativeCall.id)      or "jackie_dead"
  JL.call.activeId = aliveId
  pcall(function() triggerNativeCall(deadId,  "EndCall",     3) end)  -- clear any lingering dead card
  pcall(function() triggerNativeCall(aliveId, "IncomingCall", 1) end) -- ring the alive avatar
  local aring = (Config.call and Config.call.ringEvent) or ""
  if aring ~= "" then pcall(function() playVoice(aring) end) end
  JL.call.ringingAt = (JL.clock or 0) + jlAliveRingSecs()
  JL.ui.status = "Testing ALIVE call (ring -> connect -> dialogue)..."
  log("Test: full alive-call flow armed.")
end

-- ===========================================================================
-- v1.55 — PRE-EMPTING THE VANILLA CALL (the fix for the dead-card flash)
-- ===========================================================================
-- WHY EVERY PREVIOUS ATTEMPT WAS FLAKY: the old hijack (below) is an `Observe` on PhoneSystem.TriggerCall,
-- and CET's Observe is a POST-hook. By the time our callback ran, TriggerCall had ALREADY written the call
-- blackboard AND already called SetPhoneFact("phonecall_player_with_jackie_dead", 1) — which is the one and
-- only bridge from the phone to the quest graph (phoneSystem.script:318-330). The vanilla dead-number scene
-- was therefore already awake, and everything we did afterwards (EndCall, zeroing facts, the interrupt
-- pulse) was catch-up. It was a race we could only ever partly win — hence the flashing card.
--
-- THE FIX: PhoneSystem is a plain scripted ScriptableSystem, so its methods are RTTI-registered and
-- Override-able. `OnTriggerCall(request)` (phoneSystem.script:155) is the REQUEST HANDLER that runs BEFORE
-- TriggerCall. Every dial — player or quest — funnels through it. Override it and simply DON'T call
-- wrapped() for Jackie's dead contact, and the vanilla call never starts at all: no blackboard write, no
-- fact, no scene, no status card, no voicemail VO. Nothing to race.
--
-- ⚠️ THIS OVERRIDE SITS ON THE PATH OF EVERY PHONE CALL IN THE GAME. So it is written to FAIL OPEN: if we
-- cannot positively identify the request as a Jackie call we hand it straight to wrapped() untouched. Any
-- error, any unreadable field, any doubt -> vanilla behaviour. The worst realistic failure is that the old
-- dead-card flash comes back; it can never eat someone's quest call. Set Config.nativeCall.preemptCall =
-- false to disable the whole thing and fall back to the legacy Observe.
--
-- v1.56 — HOW WE IDENTIFY THE CALL WITHOUT KNOWING THE ENGINE'S FIELD NAMES.
--
-- The v1.55 attempt hooked `OnTriggerCall(request)` and tried to read named fields off the request struct
-- (`request.addressee` etc.). Those names were never verified, and Antonia has no Windows machine to check
-- them on — so that was a guess we couldn't test.
--
-- We don't need them. `TriggerCall` itself takes the contact and the phase as ORDINARY POSITIONAL ARGS, and
-- the mod's existing Observe on it has been reading them correctly this whole time (that is how the current
-- hijack recognises a Jackie call at all). So we Override THE SAME function whose arguments are already
-- proven to marshal. Override replaces the body: don't call wrapped() and TriggerCall never runs — so it
-- never writes the call blackboard and never calls SetPhoneFact, and the vanilla scene never wakes.
--
-- And rather than depend on the exact ARITY or argument ORDER, we do what Antonia suggested: scan EVERY
-- argument, stringify it, and keyword-match. If any argument names Jackie, it's a Jackie call. This is
-- immune to the signature changing between game patches, which is the thing that keeps breaking.
--
-- jlScanCallArgs(...) -> matchedKeyword|nil, joinedDescription
-- Pure string work, no game API — so it is unit-testable off-Windows (and is tested; see tools/).
function jlScanCallArgs(...)
  local parts = {}
  local n = select("#", ...)
  for i = 1, n do
    local v = select(i, ...)
    local s = nil
    pcall(function() s = tostring(v) end)          -- CName/enum/handle -> a readable string
    if s and s ~= "" and s ~= "nil" then parts[#parts + 1] = s end
  end
  local joined = table.concat(parts, " | ")
  local hay    = joined:lower()
  local keys   = (Config.nativeCall and Config.nativeCall.jackieKeywords)
                 or { "jackie", "jackie_dead", "disconnected", "unavailable" }
  for _, k in ipairs(keys) do
    if hay:find(tostring(k):lower(), 1, true) then return k, joined end
  end
  return nil, joined
end

-- Observe PhoneSystem:TriggerCall; when the PLAYER calls Jackie's contact (IncomingCall on a
-- 'jackie' call id, not one of our own TriggerCalls), hand off to onPlayerCalledJackie.
-- v1.55: this is now the FALLBACK path — used only if the pre-emptive Override can't be registered.
local function setupCallHijackLegacy()
  if not (Config.nativeCall and Config.nativeCall.hijackPlayerCalls) then return end
  local ok, err = pcall(function()
    Observe("PhoneSystem", "TriggerCall", function(self, mode, b1, callId, b2, phase)
      if JL.call.selfTriggering then return end                -- ignore our own TriggerCalls
      local nm = tostring(callId)
      if not nm:find("jackie") then return end                 -- only Jackie's contact
      if not tostring(phase):find("IncomingCall") then return end
      -- v1.37/38: BEFORE the shard-read stage (AWAITING), let the vanilla "number disconnected" call play
      -- out UNTOUCHED — Antonia wants the dead-phone experience early game (Jackie's believed dead). Only
      -- take over once he's reachable (or the CET "force hijack" test toggle is on).
      local reachable = Retrieval.isUnlocked() or Retrieval.isAwaitingCall()
      if not reachable and not jlCallFix().forceHijack then
        log("[Hijack] player dialed Jackie — pre-shard stage, letting the vanilla disconnected call play.")
        return
      end
      -- Reachable: the DEAD-contact call the game just started is WRONG (he's alive). KILL IT NOW —
      -- up front, before any guard in onPlayerCalledJackie can bail — so the dead card + voicemail never
      -- win. Then hand off; onPlayerCalledJackie defers the alive ring so the dead call is gone first.
      log("[Hijack] player dialed Jackie (reachable) -> killing the dead call, swapping to alive.")
      pcall(jlSilenceVanillaJackieCall)                        -- disarm the vanilla dead-number scene
      pcall(function() triggerNativeCall("jackie_dead", "EndCall", 3) end)  -- kill the dead card THIS instant
      pcall(onPlayerCalledJackie)
    end)
  end)
  log("Call hijack (legacy Observe) " .. (ok and "registered." or ("FAILED: " .. tostring(err))))
  return ok
end

-- v1.55: the PRE-EMPTIVE hijack. Swallows the vanilla Jackie call BEFORE it starts (see the essay above).
-- Returns true if the Override registered; the caller falls back to the legacy Observe if it didn't.
local function setupCallPreempt()
  if not (Config.nativeCall and Config.nativeCall.hijackPlayerCalls) then return false end
  if Config.nativeCall.preemptCall == false then return false end

  local ok, err = pcall(function()
    -- VARARGS, deliberately. CET appends `wrapped` as the LAST argument, so by capturing everything with
    -- `...` we never have to know TriggerCall's real arity or argument order — which is exactly the thing
    -- we could not verify without a Windows box, and exactly the thing that changes between game patches.
    Override("PhoneSystem", "TriggerCall", function(self, ...)
      local n       = select("#", ...)
      local args    = table.pack(...)
      local wrapped = args[n]                                  -- CET always appends the original last
      -- Run the untouched vanilla call. EVERY early-out below funnels through this: FAIL OPEN.
      local function vanilla() return wrapped(table.unpack(args, 1, n - 1)) end

      if type(wrapped) ~= "function" then return end           -- signature isn't what we think -> do nothing
      if JL.call and JL.call.selfTriggering then return vanilla() end   -- our OWN TriggerCalls pass straight through

      -- Antonia's "semi-smart identifier": stringify every argument and keyword-match, instead of trusting
      -- a field/param name we can't verify.
      local hit, desc = jlScanCallArgs(table.unpack(args, 1, n - 1))

      -- Log EVERY phone call we see, once each, so the real argument shapes end up in the CET log. This is
      -- how the signature gets pinned down from a log file instead of from a live debugger.
      JL.call.seenCalls = JL.call.seenCalls or {}
      if not JL.call.seenCalls[desc] then
        JL.call.seenCalls[desc] = true
        log("[Preempt] phone call seen: " .. tostring(desc) .. "   (match=" .. tostring(hit) .. ")")
      end

      if not hit then return vanilla() end                     -- not Jackie's -> never touch somebody else's call

      -- Pre-shard, Jackie IS believed dead: Antonia wants the vanilla "number disconnected" call to play out
      -- exactly as the base game does. Only take over once he's actually reachable.
      local reachable = Retrieval.isUnlocked() or Retrieval.isAwaitingCall()
      if not reachable and not jlCallFix().forceHijack then
        log("[Preempt] player dialed Jackie — pre-shard stage, letting the vanilla disconnected call play.")
        return vanilla()
      end

      -- REACHABLE. The call the game is about to start is the DEAD-contact one, which is simply wrong now.
      -- Don't call vanilla(): TriggerCall's body never runs, so it never writes the call blackboard and never
      -- calls SetPhoneFact — the vanilla scene is never woken. There is nothing left to race.
      log("[Preempt] Jackie call SWALLOWED before it started (matched '" .. tostring(hit) .. "') -> running ours.")
      pcall(jlSilenceVanillaJackieCall)   -- belt-and-braces: disarm the scene's facts anyway
      pcall(onPlayerCalledJackie)
      -- deliberately NO vanilla()
    end)
  end)
  if ok then
    log("Call PRE-EMPT registered (Override PhoneSystem.TriggerCall — the vanilla Jackie call is stopped " ..
        "BEFORE it starts, not chased after the fact).")
  else
    log("Call PRE-EMPT failed to register (" .. tostring(err) .. ") -> falling back to the legacy Observe.")
  end
  return ok
end

-- v1.55: kill the "number temporarily unavailable" status string while OUR call owns the phone.
-- OnSetPhoneStatus (phoneSystem.script:150) is the only thing that writes it. Cheap insurance: even if the
-- pre-empt above misses an edge case, the dead-number TEXT still can't appear over our call.
local function setupPhoneStatusSuppress()
  if not (Config.nativeCall and Config.nativeCall.hijackPlayerCalls) then return end
  if Config.nativeCall.suppressStatusText == false then return end
  local ok, err = pcall(function()
    Override("PhoneSystem", "OnSetPhoneStatus", function(self, request, wrapped)
      local c = JL.call
      local ours = c and (c.ringingAt or c.connectAt or c.hangupAt or c.watchdogAt or c.noAnswerAt)
      if ours then
        log("[Preempt] suppressed a native phone status message during our call.")
        return                                   -- swallow: no "number unavailable" over our call
      end
      return wrapped(request)                    -- every other time: untouched
    end)
  end)
  log("Phone status suppression " .. (ok and "registered." or ("FAILED: " .. tostring(err))))
end

-- The single entry point: try the pre-empt first; only if it can't register do we use the old racing Observe.
local function setupCallHijack()
  if not setupCallPreempt() then setupCallHijackLegacy() end
  setupPhoneStatusSuppress()
end

-- ---------------------------------------------------------------------------
-- ARRIVAL: navmesh-validated spawn-at-distance + WALK-IN (v0.31).
-- Old path: spawn 1 m from V, then NAIVELY teleport `spawnDistance` forward (no navmesh
-- check) -> could land inside a wall/car and get stuck. New path:
--   * snap the far point onto the human navmesh (NavigationSystem) so it's walkable;
--   * spawn Jackie PASSIVE (companionFlag 0) -> NO follower role -> the companion catch-up
--     teleport can't yank him to V and skip the distance we put between you;
--   * walk him in with AIFollowTargetCommand (teleport=false);
--   * promote him to a real companion only once he's within `companionDistance` of V.
-- (Antonia: "walk through walls"/collision-off is intentionally NOT used yet - the navmesh
--  snap makes it unnecessary for now.)
-- ---------------------------------------------------------------------------

-- Snap a candidate world point down onto the human navmesh. Returns a Vector4 or nil.
-- GetNearestNavmeshPointBelowOnlyHumanNavmesh returns a Vector4 directly (clean CET call -
-- no out-param / enum marshalling). We raise the origin a few metres so the downward sphere
-- search passes through the floor beneath the candidate.
local function snapToNavmesh(candidate)
  local nav = Game.GetNavigationSystem(); if not nav or not candidate then return nil end
  local origin = Vector4.new(candidate.x, candidate.y, candidate.z + 4.0, 1.0)
  local pt
  pcall(function() pt = nav:GetNearestNavmeshPointBelowOnlyHumanNavmesh(origin, 1.0, 12) end)
  if not pt then return nil end
  if pt.x == 0 and pt.y == 0 and pt.z == 0 then return nil end          -- "not found" sentinel
  local dx, dy = pt.x - candidate.x, pt.y - candidate.y                 -- must be ~under the candidate
  if (dx * dx + dy * dy) > (6.0 * 6.0) then return nil end
  return pt
end

-- Find a navmesh-valid arrival point ~`distance` m from V. Sweeps several headings and a few
-- shorter distances, so a blocked forward direction (building/wall) still yields a spot.
-- Returns a Vector4 (logged) or nil if nothing walkable is nearby.
local function navmeshArrivalPoint(distance)
  local pl = Game.GetPlayer(); if not pl then return nil end
  local pp; pcall(function() pp = pl:GetWorldPosition() end)
  local fwd; pcall(function() fwd = pl:GetWorldForward() end)
  if not pp or not fwd then return nil end
  -- seed RNG once per session so the first call-in isn't the same direction every restart
  if not JL.arrival.seeded then
    pcall(function() math.randomseed((os.time and os.time() or 0) + math.floor((JL.clock or 0) * 1000)) end)
    JL.arrival.seeded = true
  end
  local fwdAng  = math.atan2(fwd.y, fwd.x)
  -- v0.52: PLACEMENT. Default = a SIDE of V (left or right, 90°±20° off forward, random side first; the
  -- other side is tried as a fallback). Set Config.call.spawnSides=false to fall back to the old
  -- behind/front placement (Config.call.spawnBehind). Build the ordered list of base angles to try.
  local bases, label = {}, ""
  if Config.call and Config.call.spawnSides ~= false then
    local s = (math.random() < 0.5) and 1.0 or -1.0                        -- +1 = one side, -1 = the other
    local j = math.rad((math.random() * 40.0) - 20.0)                      -- ±20° within the side cone
    -- chosen side, then the OTHER side, then BEHIND (v0.53: behind is the reliable v0.51 fallback — a
    -- side point at 90° often lands in a building/wall = unreachable; falling back to behind keeps the
    -- spawn ON A STREET so he can actually path in, instead of bottoming out the stuck-respawn ladder).
    bases = { fwdAng + s * (math.pi * 0.5) + j, fwdAng - s * (math.pi * 0.5) + j, fwdAng + math.pi }
    label = "SIDE"
  else
    local behind = not (Config.call and Config.call.spawnBehind == false)  -- default TRUE
    bases = { behind and (fwdAng + math.pi) or fwdAng }
    label = behind and "BEHIND" or "front"
  end
  -- v0.51: reject snapped points whose height differs from V's by more than `maxSpawnZDelta`, so he
  -- never lands on a roof / balcony / metro level / parking deck the navmesh-below search can find. A
  -- same-level point is far likelier to actually have a walkable PATH to V (the stuck-respawn ladder
  -- is the backstop if it still doesn't).
  local maxZ = (Config.vehicle and Config.vehicle.maxSpawnZDelta) or 4.0
  -- for each base direction: sweep a few nearby angles + shorter distances until something snaps onto
  -- the human navmesh AT V'S LEVEL (a blocked direction/wall still yields a spot).
  for _, baseAng in ipairs(bases) do
    for _, df in ipairs({ 1.0, 0.8, 0.6 }) do
      local d = distance * df
      for _, deg in ipairs({ 0, 15, -15, 30, -30, 45, -45 }) do
        local a    = baseAng + math.rad(deg)
        local cand = Vector4.new(pp.x + math.cos(a) * d, pp.y + math.sin(a) * d, pp.z, 1.0)
        local snapped = snapToNavmesh(cand)
        if snapped and math.abs(snapped.z - pp.z) <= maxZ then
          log(("Call: arrival navmesh point %s dist=%.0f off=%+.0f dZ=%+.1f -> { %.2f, %.2f, %.2f }")
              :format(label, d, deg, snapped.z - pp.z, snapped.x, snapped.y, snapped.z))
          return snapped
        end
      end
    end
  end
  log(("Call: NO navmesh+height-valid point within %.0fm (%s, dZ<=%.0f) -> plain forward point.")
      :format(distance, label, maxZ))
  return nil
end

-- v1.40 FRONT-SIDE RECOVERY POINT. When a fast-travel RESPAWNS or catch-up TELEPORTS Jackie back to V,
-- put him slightly AHEAD and to V's SIDE — never BEHIND, which at a fast-travel point is usually a wall or
-- structure (the bug this fixes: he "caught up" straight into the geometry behind V). Reuses the walk-abreast
-- near-front anchors (Config.abreast.angleRight/angleLeft on the `positions` dial) so recovery lands him in
-- the same spot he holds while strolling beside V. Order: the side he's already on first (from `jp`, his
-- current pos — nil -> right first), then the other side, then straight ahead; each swept over a few nearby
-- angles + shorter distances and navmesh-snapped + height-checked, exactly like navmeshArrivalPoint. Returns
-- a snapped Vector4 or nil (caller falls back to navmeshArrivalPoint). GLOBAL: init.lua is at Lua's 200-local cap.
function frontSideArrivalPoint(distance, jp)
  local pl = Game.GetPlayer(); if not pl then return nil end
  local pp; pcall(function() pp = pl:GetWorldPosition() end)
  local fwd; pcall(function() fwd = pl:GetWorldForward() end)
  if not pp or not fwd then return nil end
  local fm = math.sqrt(fwd.x * fwd.x + fwd.y * fwd.y)
  local sx, sy = (fm > 1e-4) and (fwd.x / fm) or 0.0, (fm > 1e-4) and (fwd.y / fm) or 1.0
  local rx, ry = sy, -sx                                   -- V's right vector (forward rotated -90°)
  local A   = Config.abreast or {}
  local pos = A.positions or 12
  -- world-space heading of an abreast anchor (same formula as abreastTick, resolved to an angle)
  local function dirAngle(idx)
    local ang = math.rad(idx * (360.0 / pos))
    local ca, sa = math.cos(ang), math.sin(ang)
    return math.atan2(sy * ca + ry * sa, sx * ca + rx * sa)
  end
  local rAng, lAng = dirAngle(A.angleRight or 0.85), dirAngle(A.angleLeft or 11.25)
  local fwdAng     = math.atan2(sy, sx)
  -- which side is he already on? dot of (jp - pp) with V's right vector: >= 0 -> right. Keeps him from
  -- cutting across in front of V. No jp (fresh respawn, handle not resolved) -> right side first.
  local rightFirst = true
  if jp then rightFirst = ((jp.x - pp.x) * rx + (jp.y - pp.y) * ry) >= 0 end
  local bases = rightFirst and { rAng, lAng, fwdAng } or { lAng, rAng, fwdAng }
  local maxZ  = (Config.vehicle and Config.vehicle.maxSpawnZDelta) or 4.0
  for _, baseAng in ipairs(bases) do
    for _, df in ipairs({ 1.0, 0.8, 0.6 }) do
      local d = distance * df
      for _, deg in ipairs({ 0, 12, -12, 24, -24 }) do
        local a    = baseAng + math.rad(deg)
        local cand = Vector4.new(pp.x + math.cos(a) * d, pp.y + math.sin(a) * d, pp.z, 1.0)
        local snapped = snapToNavmesh(cand)
        if snapped and math.abs(snapped.z - pp.z) <= maxZ then
          log(("Recovery: front-side point base=%+.0f off=%+.0f d=%.1f dZ=%+.1f -> { %.2f, %.2f, %.2f }")
              :format(math.deg(baseAng), deg, d, snapped.z - pp.z, snapped.x, snapped.y, snapped.z))
          return snapped
        end
      end
    end
  end
  log("Recovery: NO front-side navmesh point found -> caller falls back to navmeshArrivalPoint.")
  return nil
end

-- Make an NPC treat V as a friend (so a passive spawn doesn't flee / react as a threat).
local function setFriendly(handle)
  pcall(function()
    local pl = Game.GetPlayer()
    if pl and handle and handle.GetAttitudeAgent then
      handle:GetAttitudeAgent():SetAttitudeTowards(pl:GetAttitudeAgent(), EAIAttitude.AIA_Friendly)
    end
  end)
end

-- Hide/show a spawned NPC's visuals. ToggleVisuals is the native entity method CET exposes for
-- this; we use it to keep a called-in Jackie INVISIBLE during the brief AMM "spawn 1 m in front
-- of V" pop + the teleport to distance, then reveal him already out at his arrival point. Returns
-- true if the call ran (so a missing method shows up as "not hidden" in the log, not a crash).
local function setVisible(handle, visible)
  if not handle then return false end
  return (pcall(function() handle:ToggleVisuals(visible and true or false) end))
end

-- Resolve a movement-speed name ("Walk"/"Run"/"Sprint") to the moveMovementType ENUM value.
-- Assigning a raw STRING to a command's enum field can silently fall back to Walk(0) on this
-- build (that's why "Run" looked like a slow walk); the enum value applies the speed correctly.
-- Falls back to the string if the enum isn't reachable (so this can't regress).
local function resolveMoveType(name)
  name = name or "Walk"
  local v
  pcall(function() if moveMovementType and moveMovementType[name] ~= nil then v = moveMovementType[name] end end)
  if v == nil then pcall(function() v = Enum.new("moveMovementType", name) end) end
  return v or name
end

-- Set a COMPANION's continuous follow at `desiredDistance` (used after handoff so Jackie holds a
-- gap and doesn't clip into V). AIFollowTargetCommand tracks the moving player; teleport=false.
-- v1.46 `stealth`: there is NO crouch/sneak entry in `moveMovementType` (it is only Walk/Run/Sprint).
-- The stealth gait is instead a BOOL on the command — `alwaysUseStealth`, inherited from AIMoveCommand —
-- whose handler puts the NPC into the Stealth high-level state, and THAT drives the crouched locomotion.
-- Set on its own field so an older/renamed build just ignores it (the follow still works).
local function sendWalkToPlayer(handle, movementType, desiredDistance, stealth)
  if not handle then return false end
  return (pcall(function()
    local cmd = NewObject('handle:AIFollowTargetCommand')
    cmd.target                     = Game.GetPlayer()
    cmd.desiredDistance            = desiredDistance or 1.6
    cmd.tolerance                  = 0.5
    cmd.stopWhenDestinationReached = false
    cmd.matchSpeed                 = true
    cmd.movementType               = resolveMoveType(movementType)
    cmd.teleport                   = false        -- KEY: no command-level catch-up teleport
    cmd.lookAtTarget               = Game.GetPlayer()
    if stealth then pcall(function() cmd.alwaysUseStealth = true end) end   -- v1.46: crouched gait
    handle:GetAIControllerComponent():SendCommand(cmd)
  end))
end

-- v0.77 walk-OFF: the INVERSE of the keep-close follow — an AIFollowTargetCommand with a LARGE
-- desiredDistance so the follow AI opens the gap and Jackie strolls AWAY from V until he's `distance`
-- metres off (then leavingTick despawns him). We use a follow command (not AIMoveToCommand) because on
-- game 2.31 a move-to-a-far-point instantly TELEPORTED a just-role-cleared puppet (confirmed via dumps);
-- follow commands still walk smoothly (keep-close proves it). matchSpeed=false so he moves at his own
-- pace instead of matching a standing V (which would leave him frozen). Global -> 200-local cap safe.
function jlRetreatFollow(handle, movementType, distance)
  if not handle then return end
  pcall(function()
    local cmd = NewObject('handle:AIFollowTargetCommand')
    cmd.target                     = Game.GetPlayer()
    cmd.desiredDistance            = distance or 30.0
    cmd.tolerance                  = 2.0
    cmd.stopWhenDestinationReached = false
    cmd.matchSpeed                 = false
    cmd.movementType               = resolveMoveType(movementType)
    cmd.teleport                   = false
    handle:GetAIControllerComponent():SendCommand(cmd)
  end)
end

-- Antonia's approach: command him to WALK TO V's CURRENT coordinates - a one-shot
-- AIMoveToCommand to a fixed WorldPosition. We re-issue it every ~2 s with V's latest position
-- (see arrivalTick), a manual "follow" that uses NO follow/companion semantics -> no teleport.
-- (AMM's Util:MoveTo idiom: the WorldPosition/AIPositionSpec setters take the object as arg 1.)
local function sendMoveToPlayer(handle, movementType, desiredDistance)
  if not handle then return false end
  local pl = Game.GetPlayer(); if not pl then return false end
  local pos; pcall(function() pos = pl:GetWorldPosition() end)
  if not pos then return false end
  return (pcall(function()
    local dest = NewObject('WorldPosition')
    dest:SetVector4(dest, pos)
    local spec = NewObject('AIPositionSpec')
    spec:SetWorldPosition(spec, dest)
    local cmd = NewObject('handle:AIMoveToCommand')
    cmd.movementTarget                  = spec
    cmd.movementType                    = resolveMoveType(movementType)
    cmd.ignoreNavigation                = false
    cmd.desiredDistanceFromTarget       = desiredDistance or 2.0
    cmd.finishWhenDestinationReached    = true
    cmd.rotateEntityTowardsFacingTarget = false
    handle:GetAIControllerComponent():SendCommand(cmd)
  end))
end

-- v0.33: send a puppet to an ARBITRARY world point (same AIMoveToCommand as sendMoveToPlayer,
-- but to a fixed Vector4 instead of V's position). Used to walk Jackie away when dismissed.
local function sendMoveToPoint(handle, pos, movementType, desiredDistance)
  if not handle or not pos then return false end
  return (pcall(function()
    local dest = NewObject('WorldPosition')
    dest:SetVector4(dest, pos)
    local spec = NewObject('AIPositionSpec')
    spec:SetWorldPosition(spec, dest)
    local cmd = NewObject('handle:AIMoveToCommand')
    cmd.movementTarget                  = spec
    cmd.movementType                    = resolveMoveType(movementType)
    cmd.ignoreNavigation                = false
    cmd.desiredDistanceFromTarget       = desiredDistance or 1.0
    cmd.finishWhenDestinationReached    = true
    cmd.rotateEntityTowardsFacingTarget = false
    handle:GetAIControllerComponent():SendCommand(cmd)
  end))
end

-- v1.57 STAND STILL. The counterpart to every "go there" command above: make Jackie hold the ground he is
-- on and stop micro-correcting (see the loiter gate, jlVLoitering, and Config.loiter).
-- DEFAULT PATH (`useHoldCommand = false`): an AIMoveToCommand to the point he is ALREADY standing on. It
-- completes on arrival — he has arrived — and sending it REPLACES the standing AIFollowTargetCommand, which
-- is what actually stops the shuffling. Unglamorous, but it runs on exactly the machinery the rest of this
-- file already proves works on a follower-role puppet, which is why it's the default.
-- OPTIONAL PATH (`useHoldCommand = true`): AIHoldPositionCommand (`scripts/core/ai/aiCommand.script:646` —
-- `duration : Float`), consumed by HoldPositionCommandTask (`scripts/cyberpunk/ai/commands/aiIdleCommand.script`),
-- which keeps the command IN_PROGRESS until `duration` elapses; occupying the command slot is what makes him
-- stand. The base game stands roadblock NPCs up with exactly this (`preventionSystem.script:4457`, 240 s).
-- ⚠️ UNVERIFIED IN-GAME on a FOLLOWER-role puppet: the dump proves the command and its handler exist, NOT
-- that the follower behaviour tree includes that task. Toggle it in the CET walk tuner and see which reads
-- better; if the hold command errors we drop to the move-to below anyway, so he is never left uncommanded.
-- Either way `duration` is short and re-issued on a heartbeat, never -1, so nothing freezes him for good.
-- Global (no top-level local) -> 200-local cap safe.
function jlHalt(handle)
  if not handle then return false end
  local L  = Config.loiter or {}
  local ok = false
  if L.useHoldCommand ~= false then
    ok = pcall(function()
      local cmd = NewObject('handle:AIHoldPositionCommand')
      cmd.duration = L.holdDuration or 6.0
      handle:GetAIControllerComponent():SendCommand(cmd)
    end)
  end
  if not ok then
    local jp; pcall(function() jp = handle:GetWorldPosition() end)
    if not jp then return false end
    ok = sendMoveToPoint(handle, jp, "Walk", 0.5)
  end
  return ok
end

-- A point well past `reach` metres from V, in the direction from V to Jackie (so he keeps
-- heading the way he's already facing, away from you). Falls back to +X if they overlap.
-- A point well past `reach` metres from V, in the direction from V to Jackie (so he keeps
-- heading the way he's already facing, away from you). Falls back to +X if they overlap.
local function awayPoint(handle, reach)
  local pp = playerPos(); if not pp then return nil end
  local jp; pcall(function() jp = handle:GetWorldPosition() end)
  if not jp then return nil end
  local dx, dy = jp.x - pp.x, jp.y - pp.y
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 0.5 then dx, dy, len = 1.0, 0.0, 1.0 end   -- overlapping -> pick an arbitrary heading
  return Vector4.new(pp.x + (dx / len) * reach, pp.y + (dy / len) * reach, jp.z, 1.0)
end

-- v0.33/v0.77: "send Jackie off". Say a parting line, then walk him AWAY from V and despawn once far
-- (or after maxSeconds). v0.77: we NO LONGER OnRoleCleared here — on game 2.31 a just-role-cleared
-- puppet's AIMoveToCommand teleported to its target (he snapped to the away-point and insta-despawned,
-- confirmed via dumps). Instead we keep him a companion and drive the exit with jlRetreatFollow (a
-- FollowTarget command set to a large desiredDistance) which the follow AI walks smoothly; leavingTick
-- re-issues it so it overrides AMM's own follow. Forward-declared above the F hook.
-- opts (optional): { text=, sfx= } to override the parting line — e.g. the main-quest "excuse himself".
startLeaving = function(opts)
  local sp = JL.summon.spawn
  local h  = sp and sp.handle
  if not h then return end
  local D = Config.dismiss or {}
  opts = jlVar(opts or {})   -- v1.2: Hermano swap for an explicit parting line (e.g. mainQuestExit's "...mamita.")
  -- 1) parting line (real VO + subtitle), like any Jackie line. Capture its duration so we can WIPE the
  --    subtitle afterwards - a one-off speakJackieLine has no follow-up hide, so the line stuck forever.
  local secs = 4.0
  -- v0.94: parting line is a POOL (Config.dismiss.partingPool) picked at random each dismiss; falls back to
  -- the single partingText/partingSfx. An explicit opts.text (e.g. mainQuestExit) still overrides the pool.
  -- These are function-local (NOT main-chunk locals) so they don't count toward init.lua's 200-local cap.
  local pText, pSfx = D.partingText, D.partingSfx
  local ppool = (jlHermano() and D.partingPoolM) or D.partingPool   -- v1.2: Hermano parting pool if present
  if ppool and #ppool > 0 then
    local pick = ppool[math.random(#ppool)]
    if pick then pText, pSfx = pick.text, pick.sfx end
  end
  pcall(function() secs = speakJackieLine(opts.text or pText, opts.sfx or pSfx) or 4.0 end)
  JL.leaving.subClearAt = (JL.clock or 0) + secs + 0.8
  -- 2) start walking away (retreat-follow to despawnDistance). Keep summon.active/companionSet so the
  --    onUpdate "re-apply companion role" block stays OFF until he's actually gone; leavingTick re-issues.
  pcall(function() jlRetreatFollow(h, D.movement or "Walk", (D.despawnDistance or 30.0) + 4.0) end)
  JL.leaving.phase       = "walking"
  JL.leaving.deadline    = (JL.clock or 0) + (D.maxSeconds or 30.0)
  JL.leaving.lastReissue = JL.clock or 0
  JL.ui.status = "Jackie's headin' out..."
  pcall(function() jlDumpState("startLeaving") end)   -- v0.77 DEBUG: baseline; leavingTick logs his dist as he goes
  log("Dismiss: Jackie walking away (retreat-follow; despawn at " .. tostring(D.despawnDistance or 30.0) .. " m).")
end

-- Stepped from onUpdate while Jackie is walking off: re-issue the move with the latest geometry
-- and despawn him once he's >= despawnDistance from V (or the safety deadline passes).
local function leavingTick()
  if JL.leaving.phase ~= "walking" then return end
  -- wipe the parting-line subtitle once it has had its time on screen (one-off line, no auto-hide).
  if JL.leaving.subClearAt and (JL.clock or 0) >= JL.leaving.subClearAt then
    JL.leaving.subClearAt = nil; pcall(hideSubtitle)
  end
  local sp = JL.summon.spawn
  local h  = sp and sp.handle
  if not h then JL.leaving.phase = nil; return end
  local D   = Config.dismiss or {}
  local pp  = playerPos()
  local jp; pcall(function() jp = h:GetWorldPosition() end)
  local d   = (pp and jp) and dist3(pp, jp) or nil
  local now = JL.clock or 0
  local far = d and d >= (D.despawnDistance or 30.0)
  if far or (JL.leaving.deadline and now >= JL.leaving.deadline) then
    setCompanionFlag(false)   -- v0.72: he's finished walking off and despawned -> intent over
    ammDespawn(sp)
    pcall(hideSubtitle)                                  -- never leave the parting line on screen
    JL.summon.spawn, JL.summon.active, JL.summon.companionSet, JL.summon.walkIn = nil, false, false, false
  JL.summon.companionSinceGame, JL.summon.companionExpiresGame = nil, nil   -- v0.39: reset duration clock
    JL.leaving.phase, JL.leaving.deadline, JL.leaving.subClearAt = nil, nil, nil
    JL.ui.status = far and "Jackie headed off." or "Jackie's gone."
    log(("Dismiss: despawned (%s, d=%s m)."):format(far and "reached distance" or "deadline",
        d and ("%.1f"):format(d) or "?"))
  elseif (now - (JL.leaving.lastReissue or 0)) >= 1.5 then
    JL.leaving.lastReissue = now
    pcall(function() jlRetreatFollow(h, D.movement or "Walk", (D.despawnDistance or 30.0) + 4.0) end)
    if d then log(("Dismiss: walking off... %.1f m from V."):format(d)) end
  end
end

-- v1.57 ABORT A DEPARTURE — "he doesn't stop walking away when I ask him to dinner" (Antonia).
-- Jackie's shift can run out (or a main quest can start) while he's with you; startLeaving then says his
-- parting line and hands him to jlRetreatFollow, which deliberately walks him AWAY from V until leavingTick
-- despawns him. Nothing cancelled that. So V could open the conversation mid-walk-off, invite him to dinner,
-- get an "aight, let's eat" — and watch him carry on out the door and vanish, dinner and all.
--
-- This is the one cancel path. It:
--   1) clears the leaving state so leavingTick stops re-issuing the retreat (and can no longer despawn him);
--   2) wipes the parting-line subtitle immediately (it would otherwise hang around mid-conversation);
--   3) RE-ARMS his companion clock. Non-negotiable: the clock EXPIRING is usually why he was leaving, so
--      without this the auto-leave block in onUpdate simply sends him out the door again on the next tick;
--   4) replaces the retreat command with the normal keep-close follow, so he turns around and comes back
--      instead of coasting to the end of his last order.
-- `graceHours` = how long the fresh shift is (a dinner accept passes the full companion duration; the mere
-- invite passes a short grace, so a raincheck doesn't silently gift him a whole extra day at V's side).
-- Returns true only if a departure was actually cancelled, so callers can log the interesting case.
-- Global (no top-level local) -> 200-local cap safe. Defined AFTER sendWalkToPlayer so it closes over it.
function jlAbortDeparture(graceHours, why)
  if JL.leaving.phase ~= "walking" then return false end
  -- Don't fight the MAIN-QUEST / cutscene exit. That one re-fires from onUpdate every tick while the quest
  -- is live, so cancelling it would just replay his parting line in a loop. He genuinely isn't coming.
  if not JL.allowMainGigs and (isMainQuestActive() or jlInCutscene()) then
    log("Departure abort DECLINED (" .. tostring(why or "?") .. ") — he's excusing himself from a main quest.")
    return false
  end
  JL.leaving.phase, JL.leaving.deadline, JL.leaving.lastReissue = nil, nil, nil
  JL.leaving.subClearAt = nil
  pcall(hideSubtitle)
  JL.summon.companionExpiresGame = nil                 -- force armCompanionTimer to mint a fresh deadline
  pcall(function() armCompanionTimer(graceHours) end)
  local h = JL.summon.spawn and JL.summon.spawn.handle
  if h then
    pcall(function()
      sendWalkToPlayer(h, (Config.follow or {}).movement or "Run", jlFollowDistance())
    end)
  end
  log(("Departure ABORTED (%s) — Jackie stays; companion clock re-armed for %.1f game-hours.")
      :format(tostring(why or "?"), graceHours or (Config.companion and Config.companion.maxGameHours) or 6.0))
  return true
end

-- Teleport a PUPPET via the AI system (AITeleportCommand) - reliable for freshly-spawned NPCs,
-- unlike the world TeleportationFacility which silently no-ops on them (confirmed in-game: the
-- facility Teleport left Jackie 1.9 m from V). doNavTest snaps the target onto navmesh; sent
-- through the AI controller, the same channel the move command uses.
local function aiTeleport(handle, pos, yawDeg, doNavTest)
  if not handle or not pos then return false end
  if doNavTest == nil then doNavTest = true end   -- default ON (existing callers); pass FALSE for exact placement
  return (pcall(function()
    local cmd = NewObject('handle:AITeleportCommand')
    cmd.position  = pos
    cmd.rotation  = yawDeg or 0.0
    cmd.doNavTest = doNavTest
    handle:GetAIControllerComponent():SendCommand(cmd)
  end))
end

-- v0.45: place a npc at an EXACT world pos + yaw, with NO navmesh snap. The seat tuner needs this
-- (doNavTest=true ate small slider nudges by snapping to the nearest navmesh point), and the SIT
-- facing needs it (else the workspot inherits his walk-in direction -> wrong seat angle).
-- IMPORTANT: the AITeleportCommand (doNavTest=false) is what ACTUALLY relocates a spawned puppet — the
-- world TeleportationFacility often no-ops on them (see docs/spawn_at_distance_research.md), so we lead
-- with the AI command and use the facility only as a belt-and-braces second write. It's ASYNC (lands a
-- frame or two later), so callers MUST leave a gap before playing a workspot or it can eject him.
local function placeAtExact(handle, pos, yawDeg)
  if not handle or not pos then return false end
  aiTeleport(handle, pos, yawDeg, false)            -- the real mover (exact, no navmesh snap)
  pcall(function()
    local tf = Game.GetTeleportationFacility()
    if tf then tf:Teleport(handle, pos, EulerAngles.new(0.0, 0.0, yawDeg or 0.0)) end
  end)
  return true
end

-- v0.43: toggle a spawned NPC's collision. NPCPuppet:DisableCollision()/EnableCollision() drop the
-- AI collider + obstacle trace, so chair/world geometry can't block him reaching a seat or shove him
-- out of it. Guarded — silently no-ops if the method isn't on this puppet/build. (Defined here, above
-- promoteToCompanion, so the companion path can call it. See COLLISION OWNERSHIP map up top.)
local function setNpcCollision(handle, enabled)
  if not handle then return end
  pcall(function()
    if enabled then handle:EnableCollision() else handle:DisableCollision() end
  end)
end

-- v0.62: is this NPC currently mounted to a vehicle? Asks the mounting facility for his mount
-- info and checks for a valid parent (the vehicle). pcall-guarded -> returns false on any reflection
-- hiccup, so the safety dismount below can NEVER play a phantom get-off on a Jackie who's on foot.
local function isMounted(handle)
  if not handle then return false end
  local mounted = false
  pcall(function()
    local mf = Game.GetMountingFacility()
    if not mf then return end
    local info = mf:GetMountInfoSingle(handle:GetEntityID())
    if info and info.parentId and EntityID.IsDefined(info.parentId) then mounted = true end
  end)
  return mounted
end

-- Promote the spawned Jackie to a real companion (follower role -> combat + auto-follow +
-- friendly). This is when the native catch-up teleport becomes available again; we only do it
-- once he's already close, so it never visibly skips the walk-in.
local function promoteToCompanion()
  local h = JL.summon.spawn and JL.summon.spawn.handle
  if not h then return end
  -- v0.62: SAFETY dismount. On a bike arrival Jackie is sometimes STILL in the seat when he's
  -- promoted (the walk-phase unmount didn't take). Re-issue one unmount, but ONLY if he's really
  -- still mounted — so a foot arrival or an already-grounded Jackie never plays a phantom get-off.
  if unmountDriver and isMounted(h) then
    log("promoteToCompanion: Jackie still mounted -> safety dismount.")
    pcall(function() unmountDriver(h, JL.varrival and JL.varrival.bikeHandle) end)
  end
  local amm = getAMM()
  pcall(function()
    if amm and amm.Spawn and amm.Spawn.SetNPCAsCompanion then amm.Spawn:SetNPCAsCompanion(h) end
  end)
  setFriendly(h)
  setVisible(h, true)   -- never leave him invisible
  setNpcCollision(h, true)   -- v0.44: a FOLLOWER must always collide (defensive: clears any idle/dinner
                             -- collision-off that could otherwise leak in and make him clip inside V)
  -- companion follow spacing so he holds ~followDistance and doesn't clip into V
  sendWalkToPlayer(h, (Config.call and Config.call.approachMovement) or "Run",
                      (Config.call and Config.call.followDistance) or 1.6)
  JL.summon.companionSet, JL.summon.walkIn = true, false
  JL.summon.arrivalGreetPending = true   -- v0.46/v0.48/v0.52: say a fresh greeting LINE once he closes to arrivalGruntDistance
  setCompanionFlag(true)                 -- v0.72: persist "is companion" in the save (survives reload / culling FT)
end

-- v0.50: the old AMM-spawn-near-V + HIDE + teleport "safe walk-in" (arrivalTick / arrivalMoveType)
-- was DELETED here. Both arrival modes now spawn via DES out at distance (no pop near V -> no
-- invisibility hack needed) and share vehicleArrivalTick's sprint -> walk -> companion tail. See the
-- ARRIVAL design note above Config.call in config.lua.

-- ---------------------------------------------------------------------------
-- ARRIVAL (v0.34, unified v0.50) - the ONE arrival state machine, for BOTH modes. Reuses helpers
-- (navmeshArrivalPoint / ammSpawn / aiTeleport / sendMoveToPoint / promoteToCompanion).
-- Pipeline: spawn bike behind V + spawn passive Jackie -> teleport him to the bike + mount as
-- driver -> drive in (re-targeting V every retargetInterval) -> stop+dismount at dismountDistance
-- -> sprint until sprintToWalk -> walk -> companion at arriveDistance (then despawn the bike).
-- ---------------------------------------------------------------------------
local function vehCfg() return Config.vehicle or {} end

-- Spawn any record via the dynamic entity system (the path AMM wraps; used here for BOTH the bike
-- and Jackie - same as the validated JackieVehicleTest harness). Returns the entity id; the handle
-- resolves a few frames later via Game.FindEntityByID.
local function spawnDynEntity(recordStr, pos, yawDeg, tag, appearance)
  local des = Game.GetDynamicEntitySystem(); if not des or not pos then return nil end
  local id
  local ok, err = pcall(function()
    local spec = DynamicEntitySpec.new()
    spec.recordID      = recordStr
    spec.appearanceName = appearance or "default"   -- v0.85: lockable (bike passes Config.vehicle.bikeAppearance)
    spec.position      = pos
    pcall(function() spec.orientation = EulerAngles.new(0.0, 0.0, yawDeg or 0.0):ToQuat() end)
    spec.persistState  = false
    spec.persistSpawn  = false
    spec.alwaysSpawned = false
    spec.spawnInView   = true
    spec.tags          = { CName.new(tag or "JackieLives_veh") }
    id = des:CreateEntity(spec)
  end)
  if not ok or not id then log("VehArrival: CreateEntity FAILED ('" .. tostring(recordStr) .. "'): " .. tostring(err)); return nil end
  return id
end

local function deleteEntityById(id)
  if not id then return end
  pcall(function() local des = Game.GetDynamicEntitySystem(); if des then des:DeleteEntity(id) end end)
end

-- Yaw (deg) so an entity at `from` faces V (so the bike points the way it will drive).
local function yawToward(from, to)
  if not from or not to then return 0.0 end
  return math.deg(math.atan2(to.y - from.y, to.x - from.x)) - 90.0
end

-- ---------------------------------------------------------------------------
-- v0.63: BIKE-MODEL TEST (kept as a FALLBACK tool — the hunt is RESOLVED).
-- RESOLVED: "Vehicle.v_sportbike2_arch_jackie_player" IS Jackie's correct (gold) Arch, confirmed
-- in-game. The earlier "spawned the wrong bike" reports were the pre-v0.85 DES spawn method, not the
-- record — the v0.85 appearance-lockable spawnDynEntity path spawns his real Arch reliably. The live
-- arrival, cruise, and bike-return all use this record (Config.vehicle/.cruise/.bikeReturn.bikeRecord).
-- These buttons remain as a fallback: if a livery/model regression ever appears, they spawn DIFFERENT
-- candidate records ~6 m in FRONT of you and log a READ-BACK of what actually spawned. Jackie's Arch
-- model lives under the entity "v_sportbike2_arch_nemesis"; the *_player records are garage wrappers.
-- Easy to swap: just edit BIKE_CANDIDATES.
-- ---------------------------------------------------------------------------
local BIKE_TEST_TAG = "JackieLives_biketest"

-- Candidate bikes, most-likely-his-bike first. app = "default" lets each record's own appearance
-- show; the read-back reveals the real appearance name to pin if the MODEL is right but colour isn't.
local BIKE_CANDIDATES = {
  { rec = "Vehicle.v_sportbike2_arch_jackie_tuned_player", app = "default", label = "B1: Jackie TUNED Arch (Heroes reward)" },
  { rec = "Vehicle.v_sportbike2_arch_nemesis",             app = "default", label = "B2: Arch model (nemesis entity)" },
  { rec = "Vehicle.v_sportbike2_arch_player",              app = "default", label = "B3: Arch Nazare (standard player)" },
}

-- point ~`d` m ahead of V (where you're looking), snapped to ground.
local function pointAheadOfV(d)
  local pl = Game.GetPlayer(); if not pl then return nil end
  local pp; pcall(function() pp = pl:GetWorldPosition() end); if not pp then return nil end
  local fwd; pcall(function() fwd = pl:GetWorldForward() end)
  local pt = fwd and Vector4.new(pp.x + fwd.x * d, pp.y + fwd.y * d, pp.z, 1.0)
                  or Vector4.new(pp.x + d, pp.y, pp.z, 1.0)
  return snapToNavmesh(pt) or pt
end

-- Spawn candidate #idx from BIKE_CANDIDATES in front of V; despawns the previous test bike.
local function bikeTestSpawn(idx)
  JL.biketest = JL.biketest or { id = nil, handle = nil, label = nil, reported = false }
  local cand = BIKE_CANDIDATES[idx]
  if not cand then JL.ui.status = "Bike test: no candidate " .. tostring(idx) .. "."; return end
  local st = JL.biketest
  if st.id then deleteEntityById(st.id); st.id, st.handle = nil, nil end
  local pos = pointAheadOfV(6.0)
  if not pos then JL.ui.status = "Bike test: no spawn point."; return end
  local yaw = yawToward(pos, playerPos())
  local des = Game.GetDynamicEntitySystem()
  if not des then JL.ui.status = "Bike test: DES unavailable."; return end
  local id
  local ok, err = pcall(function()
    local spec = DynamicEntitySpec.new()
    spec.recordID       = cand.rec
    spec.appearanceName = cand.app or "default"
    spec.position       = pos
    pcall(function() spec.orientation = EulerAngles.new(0.0, 0.0, yaw or 0.0):ToQuat() end)
    spec.persistState, spec.persistSpawn, spec.alwaysSpawned, spec.spawnInView = false, false, false, true
    spec.tags = { CName.new(BIKE_TEST_TAG) }
    id = des:CreateEntity(spec)
  end)
  if not ok or not id then
    JL.ui.status = cand.label .. " FAILED — record may not exist (see console)."
    log("BikeTest spawn FAILED for '" .. cand.rec .. "': " .. tostring(err)); return
  end
  st.id, st.handle, st.label, st.reported = id, nil, cand.label, false
  JL.ui.status = cand.label .. " spawning in front... read-back lands in console."
  log("BikeTest spawn: " .. cand.label .. "  record='" .. cand.rec .. "'  app='" .. (cand.app or "default") .. "'")
end

-- Once the handle resolves, read back what ACTUALLY spawned (record + appearance + class) — the
-- real diagnostic for "is this his bike". Stepped from onUpdate.
local function bikeTestTick()
  local st = JL.biketest
  if not st or not st.id then return end
  if not st.handle then pcall(function() st.handle = Game.FindEntityByID(st.id) end) end
  if st.handle and not st.reported then
    st.reported = true
    local rec, app, cls = "?", "?", "?"
    pcall(function() rec = tostring(st.handle:GetRecordID()) end)
    pcall(function() app = tostring(st.handle:GetCurrentAppearanceName()) end)
    pcall(function() cls = st.handle:GetClassName().value end)
    log(("BikeTest READ-BACK [%s]: record=%s  appearance=%s  class=%s"):format(tostring(st.label), rec, app, cls))
    JL.ui.status = ("%s spawned. appearance=%s (record in console)."):format(tostring(st.label), app)
  end
end

-- Best-effort: log any appearance names TweakDB lists for each candidate record. Vehicle appearances
-- usually live in the .ent template (not TweakDB), so this may be empty — the read-back above is the
-- reliable signal for the real appearance name.
local function bikeTestDumpAppearances()
  for _, cand in ipairs(BIKE_CANDIDATES) do
    log("BikeTest: TweakDB appearance dump for '" .. cand.rec .. "':")
    local any = false
    for _, flat in ipairs({ ".appearances", ".appearanceName", ".appearanceNames" }) do
      pcall(function()
        local v = TweakDB and TweakDB:GetFlat(cand.rec .. flat)
        if v ~= nil then any = true; log("  " .. flat .. " = " .. tostring(v)) end
      end)
    end
    if not any then log("  (nothing in TweakDB — appearances are in the .ent template; rely on the read-back)") end
  end
end

local function bikeTestDespawn()
  local st = JL.biketest
  if st and st.id then deleteEntityById(st.id) end
  if st then st.id, st.handle, st.reported = nil, nil, false end
  JL.ui.status = "Bike test despawned."
end

-- Mount/unmount an NPC as the bike's driver (AMM Scan:AssignSeats recipe).
local function mountAsDriver(npc, veh)
  if not (npc and veh) then return false end
  return (pcall(function()
    local cmd = NewObject('AIMountCommand')
    local md  = MountEventData.new()
    md.mountParentEntityId = veh:GetEntityID()
    md.isInstant = false
    md.setEntityVisibleWhenMountFinish = true
    md.removePitchRollRotationOnDismount = false
    md.ignoreHLS = false
    md.mountEventOptions = NewObject('handle:gameMountEventOptions')
    md.mountEventOptions.silentUnmount = false
    md.mountEventOptions.entityID = veh:GetEntityID()
    md.mountEventOptions.alive = true
    md.mountEventOptions.occupiedByNeutral = true
    md.slotName = "seat_front_left"
    cmd.mountData = md
    cmd = cmd:Copy()
    npc:GetAIControllerComponent():SendCommand(cmd)
  end))
end

unmountDriver = function(npc, veh)
  if not npc then return false end
  return (pcall(function()
    local cmd = NewObject('AIUnmountCommand')
    local md  = MountEventData.new()
    if veh then md.mountParentEntityId = veh:GetEntityID() end
    md.isInstant = false
    md.setEntityVisibleWhenMountFinish = true
    md.mountEventOptions = NewObject('handle:gameMountEventOptions')
    md.mountEventOptions.silentUnmount = false
    if veh then md.mountEventOptions.entityID = veh:GetEntityID() end
    md.mountEventOptions.alive = true
    md.slotName = "seat_front_left"
    cmd.mountData = md
    cmd = cmd:Copy()
    npc:GetAIControllerComponent():SendCommand(cmd)
  end))
end

-- Drive the bike to a world point (AIVehicleDriveToPointAutonomousCommand -> QUEUED TO THE
-- VEHICLE, not the driver). Returns the command (so we can stop it later).
local function driveBikeTo(veh, destV4, speed)
  if not (veh and destV4) then return nil end
  pcall(function() veh:TurnVehicleOn(true) end)
  local cmd
  pcall(function()
    cmd = NewObject('handle:AIVehicleDriveToPointAutonomousCommand')
    local v3; pcall(function() v3 = Vector3.new(destV4.x, destV4.y, destV4.z) end)
    cmd.targetPosition               = v3
    cmd.maxSpeed                     = speed or 8.0
    cmd.minSpeed                     = math.min(4.0, speed or 8.0)
    cmd.minimumDistanceToTarget      = 6.0
    cmd.clearTrafficOnPath           = false
    cmd.driveDownTheRoadIndefinitely = false
    pcall(function() cmd.needDriver = true end)
    cmd = cmd:Copy()
    local evt = NewObject('handle:AINPCCommandEvent'); evt.command = cmd
    veh:QueueEvent(evt)
    pcall(function() veh:GetAIComponent():SetInitCmd(cmd) end)
  end)
  return cmd
end

local function stopBikeVeh(veh, cmd)
  if not veh then return end
  pcall(function() if cmd then veh:StopExecutingCommand(cmd, true) end end)
  pcall(function() veh:TurnEngineOn(false) end)
end

-- v1.41 ANTI-CRASH #1 — the NPC bike KNOCK-OFF threshold. See the long note on Config.bikePhysics:
-- a bump harder than `KnockOffForce * aiBikeKnockOffModifier` force-ragdolls an NPC off his bike, and
-- that engine path ignores god-mode. Raising the modifier is what actually stops Jackie eating asphalt.
--
-- The flat is GLOBAL (every NPC bike rider in Night City), so this is REF-COUNTED: raised on the first
-- rider-on-bike, restored to the captured original when the last one dismounts. Restoring the captured
-- value (not a hard-coded 1.0) means we never clobber another mod that tuned it. Reads the flat first
-- and no-ops if it can't (wrong patch / renamed record) rather than writing blind.
-- GLOBAL -> costs no top-level local (200-cap).
function jlBikeKnockOff(on)
  local B = Config.bikePhysics or {}
  if not B.enabled then return end
  JL.knockRefs = JL.knockRefs or 0
  if on then
    JL.knockRefs = JL.knockRefs + 1
    if JL.knockRefs > 1 then return end                       -- already raised by the other bike system
    local cur; pcall(function() cur = TweakDB:GetFlat("AIGeneralSettings.aiBikeKnockOffModifier") end)
    if type(cur) ~= "number" then
      log("Bike: aiBikeKnockOffModifier unreadable -> anti-knock-off SKIPPED (he may still topple).")
      JL.knockRefs = 0; return
    end
    JL.knockOrig = cur
    local ok = pcall(function()
      TweakDB:SetFlat("AIGeneralSettings.aiBikeKnockOffModifier", B.knockOffModifier or 1000.0)
    end)
    log(ok and ("Bike: knock-off modifier %.1f -> %.1f (Jackie won't be bumped off)."):format(cur, B.knockOffModifier or 1000.0)
           or  "Bike: FAILED to raise aiBikeKnockOffModifier.")
  else
    if JL.knockRefs <= 0 then return end
    JL.knockRefs = JL.knockRefs - 1
    if JL.knockRefs > 0 then return end                        -- another bike system still needs it
    if type(JL.knockOrig) == "number" then
      pcall(function() TweakDB:SetFlat("AIGeneralSettings.aiBikeKnockOffModifier", JL.knockOrig) end)
      log(("Bike: knock-off modifier restored to %.1f."):format(JL.knockOrig))
    end
  end
end

-- v1.41 ANTI-CRASH #2 — make the spawned Arch Invulnerable so a hard hit can't DESTROY it out from
-- under him (a destroyed bike ends the follow). AMM god-modes its spawned entities the same way.
-- Does NOT stop knock-off — that's jlBikeKnockOff's job. GLOBAL -> 200-cap safe.
function jlBikeGodMode(veh)
  local B = Config.bikePhysics or {}
  if not (B.enabled and B.godMode and veh) then return end
  local ok = pcall(function()
    Game.GetGodModeSystem():AddGodMode(veh:GetEntityID(), gameGodModeType.Invulnerable, CName.new("JackieLives"))
  end)
  log(ok and "Bike: Arch set Invulnerable." or "Bike: god-mode call failed (bike stays destructible).")
end

-- Clean up a leftover arrival bike (called from dismiss paths + on handoff).
local function despawnArrivalBike()
  if JL.varrival.bikeId then deleteEntityById(JL.varrival.bikeId) end
  JL.varrival.bikeId, JL.varrival.bikeHandle = nil, nil
  -- v1.41: bike's gone -> drop OUR ref on the global knock-off flat, but only if this arrival actually
  -- took one (a foot arrival never armed it, and must not decrement the cruise system's ref).
  if JL.varrival.bikePhysArmed then
    JL.varrival.bikePhysArmed = false
    jlBikeKnockOff(false)
  end
end

-- Resolve the DES-spawned Jackie's handle from his entity id (stored on JL.summon.spawn).
-- JL.summon.spawn comes in TWO shapes and this has to resolve both:
--   * DES spawn (spawnDynEntity)  -> { id = <EntityID>, handle = nil }        -- `id` IS an EntityID
--   * AMM spawn (ammSpawn)        -> AMM's object: .handle / .entityID / .id  -- `id` is the RECORD STRING
--
-- v1.47: the AMM shape used to resolve ONLY via `sp.handle`, which AMM populates from its own Cron a few
-- frames after SpawnNPC. The `sp.id` fallback below then ran `FindEntityByID("Character.Jackie")` — a record
-- string, not an EntityID — so it could never help. If AMM's Cron was late (spawning at full black into a
-- not-yet-streamed world), the handle stayed nil, the Blaze finale's `place` phase silently timed out, and
-- Jackie was left standing wherever AMM dropped him. AMM sets `entityID` synchronously inside SpawnNPC, so
-- prefer it: we can resolve the body ourselves without waiting on AMM at all.
local function resolveJackieHandle()
  local sp = JL.summon.spawn
  if not sp then return nil end
  if sp.handle then return sp.handle end
  if sp.entityID then                                     -- AMM shape: set synchronously by SpawnNPC
    local h; pcall(function() h = Game.FindEntityByID(sp.entityID) end)
    if h then sp.handle = h; return h end
  end
  if sp.id then local h; pcall(function() h = Game.FindEntityByID(sp.id) end); if h then sp.handle = h end; return h end
  return nil
end

-- v0.38 FRESH-RESPAWN FALLBACK: the bike ride broke / stalled. Throw it all out — despawn the bike
-- and the (often stuck/mounted) Jackie — and respawn him FRESH ~fallbackDistance m away on the
-- navmesh, then drop into the existing on-foot "sprinting" phase (sprint -> walk -> companion).
-- Fires once per arrival; if even this stalls, the maxSeconds deadline teleports him in.
local function vehicleArrivalFootFallback(reason)
  local va, c = JL.varrival, vehCfg()
  despawnArrivalBike()                                   -- kill the bike
  if JL.summon.spawn then ammDespawn(JL.summon.spawn) end -- kill the stuck/mounted Jackie
  JL.summon.spawn = nil
  local pp = playerPos()
  local pt = navmeshArrivalPoint(c.fallbackDistance or 40.0) or arrivalPoint()
  if not pt then                                         -- nowhere to put him -> just hand off in place
    log("VehArrival: foot fallback found no navmesh point -> promoting in place.")
    -- re-spawn a companion right away as a last resort
    local spawn = ammSpawn(1, Config.defaultAppearance)
    JL.summon.spawn = spawn or nil
    JL.summon.active, JL.summon.companionSet, JL.summon.walkIn = true, (spawn ~= nil), false
    va.phase = nil; return
  end
  local yaw = yawToward(pt, pp)
  local jid = spawnDynEntity(Config.jackieRecord or "Character.Jackie", pt, yaw, "JackieLives_jackie")
  if not jid then
    log("VehArrival: foot fallback fresh spawn FAILED -> companion fallback.")
    local spawn = ammSpawn(1, Config.defaultAppearance)
    JL.summon.spawn = spawn or nil
    JL.summon.active, JL.summon.companionSet, JL.summon.walkIn = true, (spawn ~= nil), false
    va.phase = nil; return
  end
  JL.summon.spawn = Session.stamp({ id = jid, handle = nil })   -- v1.52: stamp so a post-load stale ref is dropped, not dereferenced
  JL.summon.active, JL.summon.companionSet, JL.summon.walkIn = true, false, true
  va.bikeId, va.bikeHandle = nil, nil
  va.phase          = "sprinting"                        -- reuse the on-foot sprint -> walk -> handoff
  va.sprintAt       = (JL.clock or 0) + 0.8
  va.unmountAgainAt = nil
  va.lastReissue    = -999
  va.footTried      = true                               -- once only
  JL.ui.status = "Jackie's bike's a bust - comin' on foot."
  log(("VehArrival: FOOT FALLBACK (%s) -> fresh Jackie ~%.0f m, sprinting in.")
      :format(tostring(reason), c.fallbackDistance or 40.0))
end

-- v0.51: (re)spawn a fresh on-foot Jackie `dist` m from V (navmesh + height-valid point) and drop
-- into the "sprinting" phase. Used for BOTH the initial foot arrival and the STUCK -> RESPAWN-CLOSER
-- ladder (if a sprinting/walking Jackie can't path to V — bad navmesh island / wrong building level —
-- we kill him and respawn at the next-closer rung). Despawns any current arrival Jackie + bike first
-- so we never leave a duplicate. Returns true on success.
local function beginFootApproach(dist, reason)
  local va, c = JL.varrival, vehCfg()
  local now = JL.clock or 0
  local pp  = playerPos()
  -- clear out whatever's there (DES Jackie + any bike) so there's never a second body
  despawnArrivalBike()
  local old = JL.summon.spawn
  if old then pcall(function() ammDespawn(old) end); if old.id then deleteEntityById(old.id) end end
  JL.summon.spawn = nil
  local pt = navmeshArrivalPoint(dist) or arrivalPoint()
  if not pt then JL.ui.status = "Arrival: no valid spawn point."; log(("FootApproach: NO navmesh/height-valid point at %.0f m."):format(dist)); return false end
  local jid = spawnDynEntity(Config.jackieRecord or "Character.Jackie", pt, yawToward(pt, pp), "JackieLives_jackie")
  if not jid then JL.ui.status = "Arrival spawn failed (see console)."; log("FootApproach: spawn failed."); return false end
  JL.summon.spawn = Session.stamp({ id = jid, handle = nil })   -- v1.52: stamp so a post-load stale ref is dropped, not dereferenced
  JL.summon.active, JL.summon.companionSet, JL.summon.walkIn = true, false, true
  va.pt             = pt
  va.bikeId, va.bikeHandle = nil, nil
  va.phase          = "sprinting"
  va.sprintAt       = now + 0.8
  va.unmountAgainAt = nil
  va.lastReissue    = -999
  va.deadline       = now + (c.maxSeconds or 120.0)
  va.footTried      = true
  va.pingAt, va.slowedLogged = 0, false
  va.closestD, va.lastProgressT = nil, now   -- reset the stuck-detector for this (re)spawn
  JL.ui.status = "Jackie's on his way (sprinting in)..."
  log(("FootApproach: spawned ~%.0f m (%s); sprinting in."):format(dist, tostring(reason)))
  return true
end

local function vehicleArrivalTick()
  local va, c = JL.varrival, vehCfg()
  -- (0) scheduled -> spawn at distance. TWO sub-paths (va.useBike, set when the arrival is armed):
  --   BIKE  — spawn his Arch + Jackie behind V, mount locally (no 80 m teleport-then-mount), then the
  --           "placing"/"driving" phases ride him in. Has a stuck failsafe + fresh-respawn foot fallback.
  --   SPRINT (bikeless) — spawn Jackie DIRECTLY at the far navmesh point (clean dynamic-entity spawn,
  --           no pop near V) and drop straight into "sprinting". The good bits, minus the flaky bike.
  -- Either way Jackie is tracked on JL.summon.spawn = {id,handle} so the rest of JackieLives (talk /
  -- dialogue / dismiss) treats him as the summoned Jackie.
  if va.at and (JL.clock or 0) >= va.at then
    va.at = nil
    va.rungIdx = 0   -- v0.51: stuck-respawn ladder starts fresh

    if not va.useBike then
      -- FOOT: spawn at Config.vehicle.spawnDistance (50 m) and sprint in (handled by the helper, which
      -- the stuck-respawn ladder also reuses). DES + navmesh/height-valid point, no invisibility hack.
      beginFootApproach(c.spawnDistance or 50.0, "call")
      return
    end

    -- BIKE: bike needs room to ride + brake, so it spawns farther than the foot sprint-in.
    local pp = playerPos()
    va.pt = navmeshArrivalPoint(c.bikeSpawnDistance or 80.0) or arrivalPoint()
    if not va.pt then JL.ui.status = "Arrival: no spawn point."; return end
    local yaw = yawToward(va.pt, pp)                                    -- face V (the way he'll ride)
    va.pingAt, va.slowedLogged = 0, false                              -- arm the 3s ping + "easing off" one-shot
    -- bike + Jackie spawn together behind V (local mount).
    -- LOCK to Jackie's real Arch (record + appearance). Same record the JackieVehicleTest harness
    -- confirmed spawns his correct gold Arch — never a random bike.
    va.bikeId  = spawnDynEntity(c.bikeRecord or "Vehicle.v_sportbike2_arch_jackie_player", va.pt, yaw,
                                "JackieLives_bike", c.bikeAppearance or "default")
    local jpos = snapToNavmesh(Vector4.new(va.pt.x + 1.5, va.pt.y, va.pt.z, 1.0)) or va.pt
    local jid  = spawnDynEntity(Config.jackieRecord or "Character.Jackie", jpos, yaw, "JackieLives_jackie")
    if not va.bikeId or not jid then
      JL.ui.status = "Vehicle arrival spawn failed (see console)."
      log("VehArrival: spawn failed (bike=" .. tostring(va.bikeId ~= nil) .. ", jackie=" .. tostring(jid ~= nil) .. ")")
      despawnArrivalBike(); if jid then deleteEntityById(jid) end; return
    end
    JL.summon.spawn = Session.stamp({ id = jid, handle = nil })   -- v1.52: stamp so a post-load stale ref is dropped, not dereferenced
    JL.summon.active, JL.summon.companionSet, JL.summon.walkIn = true, false, true
    va.bikeHandle = nil
    va.placeAt    = (JL.clock or 0) + 1.0
    va.phase      = "placing"
    va.deadline   = (JL.clock or 0) + (c.maxSeconds or 120.0)
    -- v0.47: the v0.38 foot-fallback (40s -> ditch bike + respawn on foot) was KILLING working rides
    -- before they finished (an 80 m city ride routinely exceeds 40s). It's now OPT-IN via
    -- Config.vehicle.footFallback (default OFF) so the bike gets its uninterrupted v0.36 conditions
    -- back. With it off, the only backstop is the maxSeconds deadline (force companion handoff).
    if c.footFallback then
      va.footFallbackAt = (JL.clock or 0) + (c.fallbackSeconds or 40.0)
      va.footTried = false
    else
      va.footFallbackAt, va.footTried = nil, true   -- no respawn; let the bike ride the whole way
    end
    JL.ui.status = "Jackie's on his way (bike)..."
    log("VehArrival: bike + Jackie spawned at distance; mount in 1.0s.")
    return
  end

  if not va.phase then return end
  local now = JL.clock or 0
  local pp  = playerPos()

  -- resolve handles each tick until both exist
  if va.bikeId and not va.bikeHandle then
    pcall(function() va.bikeHandle = Game.FindEntityByID(va.bikeId) end)
    -- v1.41: the moment the Arch exists, protect the ride-in — raise the NPC knock-off threshold so a
    -- clipped taxi can't ragdoll him off mid-arrival (which used to end as "Jackie NOT on the bike ->
    -- ditch bike, he comes on foot"), and make the bike invulnerable so it can't be destroyed under him.
    if va.bikeHandle and not va.bikePhysArmed then
      va.bikePhysArmed = true
      jlBikeKnockOff(true)
      jlBikeGodMode(va.bikeHandle)
    end
  end
  local jh = resolveJackieHandle()

  -- safety timeout (LAST RESORT). If Jackie's entity exists, force the companion handoff (AMM's
  -- catch-up teleport pulls a stuck-but-alive Jackie in). If there's NO valid handle — the DES spawn
  -- failed or his body was lost — promoteToCompanion would silently no-op and he'd NEVER appear; so
  -- RESCUE-SPAWN a fresh companion right at V (the instant summon path) and let the main tick promote
  -- him. This restores the guaranteed arrival the old AMM-spawn-near-V fallback gave us before v0.50.
  if va.deadline and now >= va.deadline then
    if resolveJackieHandle() then
      log("VehArrival: safety deadline -> force companion handoff.")
      pcall(promoteToCompanion); despawnArrivalBike()
      va.phase = nil; JL.ui.status = "Jackie rejoined."; return
    end
    log("VehArrival: safety deadline + NO Jackie handle -> rescue-spawn at V.")
    despawnArrivalBike()
    if JL.summon.spawn then pcall(function() ammDespawn(JL.summon.spawn) end) end
    JL.summon.spawn, JL.summon.active, JL.summon.companionSet, JL.summon.walkIn = nil, false, false, false
    va.phase = nil
    local spawn = ammSpawn(1)
    if spawn then
      JL.summon.spawn, JL.summon.active, JL.summon.companionSet, JL.summon.walkIn = spawn, true, false, false
      JL.summon.arrivalGreetPending = true   -- still greet once he's promoted + close
      JL.ui.status = "Jackie rejoined (rescued)."
    else
      JL.ui.status = "Rescue spawn failed (see console)."
      log("VehArrival: rescue ammSpawn(1) FAILED.")
    end
    return
  end

  -- v0.38 FRESH-RESPAWN FALLBACK: not handed off within fallbackSeconds and still on the bike
  -- (placing/driving) -> ditch the bike, respawn Jackie fresh ~40 m out, sprint/walk in. Once only.
  if not va.footTried and va.footFallbackAt and now >= va.footFallbackAt
     and (va.phase == "placing" or va.phase == "driving") then
    pcall(vehicleArrivalFootFallback, "40s, no handoff")
    return
  end

  -- v0.51 ON-FOOT STUCK -> RESPAWN CLOSER. While sprinting/walking, track his CLOSEST distance to V.
  -- If he makes no further progress for `respawnStuckSeconds` (bad navmesh island, wrong building
  -- level, blocked path — he just stutters in place, never closing), kill him and respawn at the next
  -- rung in `respawnRungs` (35 -> 20 m). v0.53: stops at 20 m (a 5 m respawn read as a face-teleport);
  -- once no rung is closer than where he's stuck, just hand off to companion in place.
  if (va.phase == "sprinting" or va.phase == "walking") and jh then
    local jp; pcall(function() jp = jh:GetWorldPosition() end)
    local d = (pp and jp) and dist3(pp, jp) or nil
    if d then
      if not va.closestD or d < va.closestD - (c.respawnProgressEps or 1.0) then
        va.closestD, va.lastProgressT = d, now                       -- real progress -> reset the timer
      elseif (now - (va.lastProgressT or now)) >= (c.respawnStuckSeconds or 5.0) then
        local nd
        for _, r in ipairs(c.respawnRungs or { 35.0, 20.0 }) do
          if r < (va.closestD or 1e9) - 2.0 then nd = r; break end   -- pick the first rung that's actually closer
        end
        if nd then
          log(("VehArrival: STUCK at %.1f m (no progress %.0fs) -> respawn closer at %.0f m.")
              :format(d, c.respawnStuckSeconds or 5.0, nd))
          beginFootApproach(nd, "stuck-respawn"); return
        else
          log(("VehArrival: STUCK at %.1f m, no closer rung -> companion in place."):format(d))
          pcall(promoteToCompanion); despawnArrivalBike(); va.phase = nil; return
        end
      end
    end
  end

  if va.phase == "placing" and va.placeAt and now >= va.placeAt then
    if not (va.bikeHandle and jh) then return end                   -- wait for both handles
    va.placeAt = nil
    setFriendly(jh)
    pcall(function() va.bikeHandle:TurnVehicleOn(true) end)
    mountAsDriver(jh, va.bikeHandle)                                -- local climb-on (both at distance)
    -- v0.53: give him REAL time to walk to the seat + climb on before the bike drives off. 1.2s was
    -- too short — the bike left without him. The "driving" phase then watches Jackie-to-bike distance
    -- and, if he's clearly NOT on it (mount failed), ditches the bike and he comes in on foot from there.
    va.driveAt = now + (c.mountSeconds or 4.0)
    va.mountAt = va.driveAt                                        -- stuck-grace starts when the bike starts moving
    va.lastReissue = -999
    va.stuckTime, va.lastBikePos, va.lastSpeedT = 0, nil, now      -- stuck-detector state
    va.phase = "driving"
    JL.ui.status = "Jackie's getting on the bike..."
    log(("VehArrival: mount sent; %.0fs to climb on, then drive."):format(c.mountSeconds or 4.0))
    return
  end

  if va.phase == "driving" then
    if not (va.bikeHandle and jh) then return end
    if now < (va.driveAt or 0) then return end
    local bp; pcall(function() bp = va.bikeHandle:GetWorldPosition() end)
    local jp; pcall(function() jp = jh:GetWorldPosition() end)
    local d   = (pp and bp) and dist3(pp, bp) or nil                  -- BIKE -> V (when to park)
    local dj  = (pp and jp) and dist3(pp, jp) or nil                  -- JACKIE -> V (what we report)
    local jbd = (jp and bp) and dist3(jp, bp) or nil                  -- JACKIE -> BIKE (is he actually riding?)
    -- v0.53: if the bike has been moving a couple seconds and Jackie is NOT on it (mount failed -> the
    -- bike drove off without him), DITCH the bike and he comes in ON FOOT from where he's standing. No
    -- teleport, no "bike arrives alone". This also fixes the report following the bike instead of him.
    if jbd and jbd > (c.fellOffDist or 6.0) and (now - (va.driveAt or 0)) >= 2.0 then
      log(("VehArrival: Jackie NOT on the bike (%.1f m from it) -> ditch bike, he comes on foot."):format(jbd))
      stopBikeVeh(va.bikeHandle, va.driveCmd); despawnArrivalBike()
      va.phase, va.sprintAt, va.lastReissue, va.pingAt = "sprinting", now, -999, 0
      va.closestD, va.lastProgressT = nil, now
      JL.ui.status = "Jackie missed the bike - on foot."
      return
    end
    local slowing = d and d <= (c.slowDownDistance or 30.0)            -- v0.52: he's intentionally crawling here
    -- v0.53: ping reports JACKIE's distance to V (bike's in parens), not the bike's, since he's the one arriving
    if dj and now >= (va.pingAt or 0) then va.pingAt = now + 3.0; log(("VehArrival: riding in... %.1f m to V (bike %.0f)."):format(dj, d or 0)) end
    -- re-issue the drive at V's live position so he tracks you. v0.50/0.52: ease off to `slowSpeed` once
    -- inside `slowDownDistance` (30 m) so the park at `dismountDistance` (20 m) is a smooth brake, not a
    -- hard stop. (The autonomous drive command decelerates toward a slower target.)
    if (now - (va.lastReissue or 0)) >= (c.retargetInterval or 2.0) then
      va.lastReissue = now
      local speed = slowing and (c.slowSpeed or 3.0) or (c.cruiseSpeed or 8.0)
      if slowing and not va.slowedLogged then va.slowedLogged = true; log(("VehArrival: easing off at %.0f m (slow to %0.0f m/s)."):format(d or 0, speed)) end
      va.driveCmd = driveBikeTo(va.bikeHandle, pp, speed)
    end
    -- STUCK FAILSAFE: after the grace beat, sample the bike's speed ~1x/s; if it crawls (< stuckSpeed)
    -- for stuckSustain seconds, he bails off + walks (dense area). v0.52: DISABLED while `slowing` —
    -- a deliberate crawl near the stop point was tripping it; only true stalls out on the open road count.
    local stuck = false
    if bp and not slowing and (now - (va.mountAt or 0)) >= (c.stuckGrace or 5.0)
       and (now - (va.lastSpeedT or now)) >= 1.0 then
      local dt    = now - (va.lastSpeedT or now)
      local moved = va.lastBikePos and dist3(bp, va.lastBikePos) or 999
      local spd   = (dt > 0) and (moved / dt) or 999
      va.stuckTime = (spd < (c.stuckSpeed or 2.0)) and ((va.stuckTime or 0) + dt) or 0
      va.lastBikePos, va.lastSpeedT = bp, now
      if (va.stuckTime or 0) >= (c.stuckSustain or 2.0) then stuck = true end
    end
    local reached = d and d <= (c.dismountDistance or 20.0)
    if reached or stuck then
      stopBikeVeh(va.bikeHandle, va.driveCmd)                       -- park the bike where it is (on the road)
      unmountDriver(jh, va.bikeHandle)
      va.unmountAgainAt = now + 1.0                                 -- one retry so he can't stick in the seat
      va.lastReissue = -999
      va.phase = "walking"                                         -- v0.52: park is close (20 m) -> just WALK in
      JL.ui.status = stuck and "Jackie's bike's stuck - he's on foot." or "Jackie parked the bike."
      log(("VehArrival: %s at %.0f m -> dismount + walk in."):format(stuck and "STUCK" or "reached", d or 0))
    end
    return
  end

  if va.phase == "sprinting" then
    if now < (va.sprintAt or 0) then return end
    local jp; pcall(function() jp = jh and jh:GetWorldPosition() end)
    local d = (pp and jp) and dist3(pp, jp) or nil
    if d and now >= (va.pingAt or 0) then va.pingAt = now + 3.0; log(("VehArrival: sprinting in... %.1f m to V."):format(d)) end
    if (now - (va.lastReissue or 0)) >= 1.2 then
      va.lastReissue = now
      sendMoveToPoint(jh, pp, "Sprint", c.arriveDistance or 3.0)
    end
    if d and d <= (c.sprintToWalk or 25.0) then va.phase = "walking"; va.lastReissue = -999; log(("VehArrival: %.0f m -> downshift to walk."):format(d)) end
    return
  end

  if va.phase == "walking" then
    -- v0.52: bike dismount enters here directly; retry the unmount once so he can't stick in the seat pose.
    if va.unmountAgainAt and now >= va.unmountAgainAt then
      va.unmountAgainAt = nil; pcall(function() unmountDriver(jh, va.bikeHandle) end)
    end
    local jp; pcall(function() jp = jh and jh:GetWorldPosition() end)
    local d = (pp and jp) and dist3(pp, jp) or nil
    if d and now >= (va.pingAt or 0) then va.pingAt = now + 3.0; log(("VehArrival: walking in... %.1f m to V."):format(d)) end
    if (now - (va.lastReissue or 0)) >= 1.5 then
      va.lastReissue = now
      sendMoveToPoint(jh, pp, "Walk", c.arriveDistance or 3.0)
    end
    if d and d <= ((Config.call and Config.call.companionDistance) or 5.0) then   -- v0.50: small (5 m) so AMM's catch-up teleport never yanks him into V
      pcall(function() unmountDriver(jh, va.bikeHandle) end)   -- FORCE unmount on entering companion range
      promoteToCompanion()
      va.phase = "handoff"
      va.bikeDespawnAt = now + 1.0                             -- let the unmount apply before the bike vanishes
      JL.ui.status = "Jackie's with you."
      log(("VehArrival: handoff to companion (%.1f m)."):format(d or 0))
    end
    return
  end

  if va.phase == "handoff" then
    -- brief beat so the unmount finishes, then remove the parked bike.
    if now >= (va.bikeDespawnAt or 0) then despawnArrivalBike(); va.phase = nil end
  end
end

-- v0.39 RECRUIT-IN-PLACE: dialogue "Let's go/roll" at a location -> the Jackie standing there
-- BECOMES your companion (no second Jackie arriving from afar). Hand his entity from the idle
-- system to the summon system, promote to companion, and stop the schedule/wander owning him
-- (DON'T despawn — same entity, no pop). This is what was missing: the gig dialogue ended but
-- nothing flipped him, so scheduleTick/wanderTick kept him idle.
local function recruitIdleJackie()
  local sp = JL.idle.spawn
  if not sp then JL.ui.status = "No idle Jackie here to recruit."; return false end
  -- hand the live entity to the companion system
  JL.summon.spawn        = sp
  JL.summon.active       = true
  JL.summon.companionSet = false
  JL.summon.walkIn       = false
  -- release the idle/schedule grip WITHOUT despawning him
  JL.idle.spawn, JL.idle.locationKey = nil, nil
  JL.idle.placed, JL.idle.phase      = false, nil
  JL.idle.curIdx, JL.idle.tgtIdx     = nil, nil
  JL.idle.leaving, JL.idle.leaveTarget = false, nil
  if sp.handle then pcall(function() Game.GetWorkspotSystem():StopInDevice(sp.handle) end) end  -- v0.39: get up if seated
  pcall(promoteToCompanion)            -- follower role + friendly + follow spacing
  JL.summon.companionSet = true        -- promoteToCompanion already set it, but be explicit
  JL.ui.status = "Jackie's with you."
  log("Recruited idle Jackie -> companion in place.")
  return true
end

-- v0.66 COMPANION CATCH-UP TELEPORT. The arrival sequence deliberately SUPPRESSES the catch-up
-- teleport (spawn passive, promote at 5 m, follow with teleport=false) so he never yanks into V's
-- face while walking in. But ONCE arrival is fully done and he's a confirmed companion, Antonia wants
-- the opposite: if V FAST-TRAVELS, runs off, or otherwise leaves him behind, he should snap back to her
-- side — exactly what a normal AMM companion does. We do it OURSELVES (our own aiTeleport, which the
-- code proves actually relocates a spawned puppet) instead of relying on AMM's opaque catch-up, so we
-- fully control WHERE he lands: a navmesh point a few metres to V's SIDE (Config.catchUp.placeDistance),
-- NEVER on top of her. Gated to the settled companion state only (not mid-arrival/dinner/walk-off), so it
-- can't reintroduce the arrival face-yank. NOTE: if a load-screen fast-travel CULLS his runtime entity
-- (handle goes nil) this can't save him — that's the heavier "persist + respawn" task (see TODO Session 1).
-- v1.35: is a FIGHT on? True if V or companion Jackie is in combat. While true, the SHORT LEASH
-- (walk-abreast / keep-close follow / catch-up teleport) all yield, so AMM's native follower COMBAT AI
-- takes over — Jackie breaks formation, takes cover, and fights freely instead of glued to V's side.
-- pcall-guarded + cached per frame; defaults FALSE so a reflection hiccup can never freeze him mid-fight
-- (worst case he just keeps following). ScriptedPuppet:IsInCombat() covers both the player and NPCs.
-- Global -> 200-local cap safe.
function jlInCombat()
  local st = JL.combat; if not st then st = {}; JL.combat = st end
  local now = JL.clock or 0
  if st.frame == now then return st.val end          -- compute once per frame (3 ticks call this)
  st.frame = now
  local val = false
  pcall(function()
    local p = Game.GetPlayer()
    if p and p:IsInCombat() then val = true; return end
    local h = JL.summon.spawn and JL.summon.spawn.handle
    if h and h:IsInCombat() then val = true end
  end)
  st.val = val
  return val
end

local function catchUpTick()
  local C = Config.catchUp or {}
  if C.enabled == false then return end
  if JL.blazeFinale then return end   -- v1.47: the finale places Jackie itself; a respawn-when-stranded here
                                      -- would despawn the body it just spawned (and hide the new one).
  -- v1.48: don't yank him back to V's side while he's crossing the room to take someone down. The
  -- approach legitimately opens a gap, and an aiTeleport mid-takedown would cancel the command.
  if jlTakedownBusy() then JL.catchUp.farSince, JL.catchUp.teleTries = nil, nil; return end
  -- settled companion only: active + role applied, and NOT mid-arrival / dinner / walking-off.
  if not (JL.summon.active and JL.summon.companionSet) then JL.catchUp.farSince, JL.catchUp.teleTries = nil, nil; return end
  -- v1.35: in COMBAT, let him roam/fight — don't yank him back to V's side. (Reset the far-timer so a
  -- post-combat gap re-arms cleanly instead of teleporting instantly on a stale timer.)
  if jlInCombat() then JL.catchUp.farSince, JL.catchUp.teleTries = nil, nil; return end
  if JL.dinner.phase or JL.leaving.phase or (JL.varrival and JL.varrival.phase)
     or (jlCruise and jlCruise.active) then   -- v0.85: don't teleport him off his cruising bike
    JL.catchUp.farSince, JL.catchUp.teleTries = nil, nil; return
  end
  local h = JL.summon.spawn and JL.summon.spawn.handle
  if not h then JL.catchUp.farSince = nil; return end
  local pp = playerPos(); if not pp then return end
  local jp; pcall(function() jp = h:GetWorldPosition() end); if not jp then return end
  local now = JL.clock or 0
  local d   = dist3(pp, jp)
  -- back within range -> the last teleport (if any) took; clear the retry counter.
  if d <= (C.distance or 25.0) then JL.catchUp.farSince, JL.catchUp.teleTries = nil, nil; return end
  -- he's far. Require it to PERSIST a beat (a fast-travel/load gap, not a momentary stream hiccup).
  JL.catchUp.farSince = JL.catchUp.farSince or now
  if (now - JL.catchUp.farSince) < (C.sustainSeconds or 2.0) then return end
  if (now - (JL.catchUp.lastAt or -1e9)) < (C.cooldown or 3.0) then return end

  -- v0.79 ESCALATION. aiTeleport (AITeleportCommand) can only move his body while it's still streamed with
  -- live AI. A load-screen fast-travel across DISTRICTS strands it far away, so the teleport silently no-ops
  -- (the old build then LIED "teleported to her side" and left him behind, and travelling back never fixed it).
  -- So: if he's beyond respawnDistance (obvious district-scale FT — skip the doomed teleport) OR a prior
  -- teleport already failed to close the gap (teleTries reached maxTeleTries -> still this far after cooldown),
  -- despawn the stranded body and respawn a fresh Jackie at V. Safe here: fires 2 s+ after the FT with V fully
  -- in-world, unlike the persist-on-LOAD respawn (Config.persist) that crashes into a not-yet-streamed world.
  local tries = JL.catchUp.teleTries or 0
  if (C.respawnWhenStranded ~= false)
     and (d >= (C.respawnDistance or 150.0) or tries >= (C.maxTeleTries or 1)) then
    JL.catchUp.lastAt, JL.catchUp.farSince, JL.catchUp.teleTries = now, nil, nil
    log(("CatchUp: Jackie stranded %.0f m from V (teleport can't cross) -> respawning at her side."):format(d))
    pcall(respawnCompanionAtV)   -- despawns the orphaned body + spawns fresh at V; onUpdate re-promotes next frame
    return
  end

  -- moderate gap, body still local: land him a few metres AHEAD/beside V on the navmesh (never ON V, never
  -- BEHIND into the wall at a fast-travel point), then re-assert follow. v1.40: prefer the front-side point
  -- (reuses the walk-abreast angles, picks the side he's already on via `jp`); fall back to the old
  -- side/behind navmesh sweep, then a plain forward point. Count the attempt so a no-op teleport escalates
  -- to a respawn on the next eligible tick.
  local pt = frontSideArrivalPoint(C.placeDistance or 3.0, jp)
             or navmeshArrivalPoint(C.placeDistance or 3.0) or arrivalPoint()
  if not pt then return end
  local yaw = 0.0
  pcall(function() local f = Game.GetPlayer():GetWorldForward(); yaw = math.deg(math.atan2(f.y, f.x)) end)
  aiTeleport(h, pt, yaw, false)
  sendWalkToPlayer(h, (Config.call and Config.call.approachMovement) or "Run",
                      (Config.call and Config.call.followDistance) or 1.6)
  JL.catchUp.lastAt    = now
  JL.catchUp.farSince  = nil
  JL.catchUp.teleTries = tries + 1
  log(("CatchUp: Jackie was %.0f m from V -> teleported to her side (try %d)."):format(d, tries + 1))
end

-- v0.85b: is V currently WALKING (a steady stroll) vs STILL or jogging/sprinting? Abreast (Jackie holds a
-- spot beside/ahead of V) only makes sense while V actually strolls; at jog/sprint he can't out-pace her
-- (V has 3 speeds, Jackie 2) and when STILL he'd hover at a weird side-angle, jerking as the camera pans.
-- So this returns true ONLY for the narrow "steady walk" case; every other state -> the close trail.
-- We read V's horizontal speed from her per-frame position delta (robust, no velocity API) with light
-- smoothing. Cached per frame (JL.clock) so calling it from both follow ticks does the work once.
-- v0.93 — this used to treat STANDING STILL (~0 m/s, which is <= walkMaxSpeed) as "walking", so abreast
-- hijacked normal standing-around conversation. Two gates fixed it:
--   * WALK BAND with hysteresis on BOTH edges: V must move FASTER than walkMinSpeed (not still) and slower
--     than jogMinSpeed. Once in the band she only leaves it by (near-)stopping or speeding up to a jog.
--   * SUSTAIN: abreast only engages after V holds that band CONTINUOUSLY for walkSustainSeconds (~3 s) — a
--     step or a shuffle mid-chat won't trip it; any drop out of the band resets the timer.
-- Global -> 200-local cap safe.
function jlVWalking()
  local A  = Config.abreast or {}
  local st = JL.abreast
  local now = JL.clock or 0
  if st.spdFrame ~= now then                    -- compute once per frame
    st.spdFrame = now
    local pp = playerPos()
    if pp then
      if st.spdPX then
        local dt = now - (st.spdT or now)
        if dt > 1e-4 then
          local dx, dy = pp.x - st.spdPX, pp.y - st.spdPY
          local inst = math.sqrt(dx * dx + dy * dy) / dt
          local a = math.min(dt / 0.25, 1.0)     -- ~0.25 s smoothing on the speed signal
          st.vSpeed = (st.vSpeed or inst) + a * (inst - (st.vSpeed or inst))
        end
      end
      st.spdPX, st.spdPY, st.spdT = pp.x, pp.y, now
    end
    local spd = st.vSpeed or 0.0
    -- --- WALK BAND (hysteresis on both edges): moving but not still, not jogging/sprinting --------------
    local lo, hi, jog = (A.walkMinSpeed or 0.6), (A.walkMaxSpeed or 2.0), (A.jogMinSpeed or 2.8)
    local inBand = st.inBand
    if inBand == nil then inBand = (spd >= lo and spd <= hi) end
    if inBand then
      if spd < (lo * 0.5) or spd > jog then inBand = false end   -- (near-)stopped OR sped up -> leave band
    else
      if spd >= lo and spd <= hi then inBand = true end           -- settled into a steady walk -> enter band
    end
    st.inBand = inBand
    -- --- SUSTAIN: only count as "walking" once the band has held continuously long enough ---------------
    if inBand then st.walkSince = st.walkSince or now else st.walkSince = nil end
    st.walking = (st.walkSince ~= nil) and ((now - st.walkSince) >= (A.walkSustainSeconds or 3.0))
  end
  return st.walking
end

-- v1.57 "IS V BASICALLY STANDING STILL?" — the loiter gate (Antonia: "when V is very slow, close to
-- standing, he should stand still; only after some inertia he should start moving").
-- A LATCH with two different thresholds, which is the whole point:
--   * falling  edge: speed <= stopSpeed held for stopSustain  -> latch STILL (Jackie plants his feet)
--   * rising   edge: speed >  goSpeed   held for goSustain     -> unlatch    (Jackie sets off again)
-- goSpeed is deliberately ABOVE stopSpeed. With a single threshold, V drifting around the line would flip
-- Jackie between halt and follow several times a second — visibly worse than the shuffling it replaces.
-- The speed signal is the same smoothed one jlVWalking maintains, so we call it to force this frame's
-- update and then read JL.abreast.vSpeed. That means the gate works identically whether the player has
-- walk-beside on or off (jlVWalking is otherwise only consulted by the abreast path).
-- Cached per frame; global -> 200-local cap safe.
function jlVLoitering()
  local L = Config.loiter or {}
  if L.enabled == false then return false end
  local st  = JL.loiter
  local now = JL.clock or 0
  if st.frame ~= now then
    st.frame = now
    jlVWalking()                                   -- refresh the shared per-frame speed EMA
    local spd = JL.abreast.vSpeed or 0.0
    if st.still then
      if spd > (L.goSpeed or 1.10) then st.fastSince = st.fastSince or now else st.fastSince = nil end
      if st.fastSince and (now - st.fastSince) >= (L.goSustain or 0.35) then
        st.still, st.fastSince, st.slowSince = false, nil, nil
      end
    else
      if spd <= (L.stopSpeed or 0.55) then st.slowSince = st.slowSince or now else st.slowSince = nil end
      if st.slowSince and (now - st.slowSince) >= (L.stopSustain or 0.60) then
        st.still, st.slowSince, st.fastSince = true, nil, nil
      end
    end
  end
  return st.still == true
end

-- v1.46 VERTICAL GATE — "is V on stairs / a slope / a ladder / a lift right now?"
-- Walking abreast assumes FLAT ground. Two things break on an incline:
--   * a staircase is rarely wide enough for two, so the side anchor lands in a wall or over a drop;
--   * the anchor's z was V's z, so a point ~5.5 m ahead of a CLIMBING V sat buried inside the steps ahead
--     (or, descending, floated above them). AIMoveToCommand then projected that point onto whichever
--     floor's navmesh happened to be nearest, flipping between the lower and upper level on successive
--     re-issues. That flip is the "he teleports jaggedly in front of V" report.
-- Either trigger fires: V's own vertical speed (she is climbing NOW), or a standing height gap between
-- the two of them (he's on a different step/landing). `slopeReleaseSeconds` latches the trail on for a
-- moment after she levels out, so a mid-staircase landing or a kerb can't flip him back and forth.
-- NOTE: a jump also trips slopeRate. That's harmless — he trails for ~1.5 s and resumes.
-- Cached once per frame (jlAbreastOn is asked by two ticks). Global -> 200-local cap safe.
function jlVertical()
  local A, st = Config.abreast or {}, JL.abreast
  local now = JL.clock or 0
  if st.vFrame ~= now then
    st.vFrame = now
    local pp = playerPos()
    if pp then
      if st.vzP then
        local dt = now - (st.vzT or now)
        if dt > 1e-4 then
          local inst = math.abs(pp.z - st.vzP) / dt
          local a = math.min(dt / 0.25, 1.0)      -- same ~0.25 s smoothing as the walk-speed signal
          st.vRate = (st.vRate or inst) + a * (inst - (st.vRate or inst))
        end
      end
      st.vzP, st.vzT = pp.z, now
    end
    local gapZ = 0.0                              -- standing height gap: he's a step (or a floor) away
    local h = JL.summon.spawn and JL.summon.spawn.handle
    if h and pp then
      local jp; pcall(function() jp = h:GetWorldPosition() end)
      if jp then gapZ = math.abs(jp.z - pp.z) end
    end
    if ((st.vRate or 0.0) > (A.slopeRate or 0.45)) or (gapZ > (A.maxZDelta or 1.0)) then
      st.slopeUntil = now + (A.slopeReleaseSeconds or 1.5)
    end
    st.vertical = (st.slopeUntil ~= nil) and (now < st.slopeUntil)
  end
  return st.vertical
end

-- v1.46 SNEAK DETECTION — "is V crouched right now?"
-- Read from the SAME PlayerStateMachine blackboard blazeClearCombat uses. The Locomotion int is an OUTPUT
-- (writing it does nothing — see blazeForceStand), but READING it is exactly what we want here.
-- The state values are resolved BY NAME through jlAnimEnum (`gamePSMLocomotionStates`), never hardcoded, so
-- a patch that renumbers the enum can't silently invert this. Resolved once and cached; if NOTHING resolves
-- we log once and report "not sneaking" — i.e. we degrade to the pre-v1.46 behaviour instead of erroring.
-- Global -> 200-local cap safe.
function jlSneakStates()
  if JL.sneakVals then return JL.sneakVals end
  local S, t, names = Config.stealth or {}, {}, {}
  for _, n in ipairs(S.locomotionStates or { "Crouch", "CrouchSprint" }) do
    local v = jlAnimEnum("gamePSMLocomotionStates", n)
    local i; if v ~= nil then pcall(function() i = EnumInt(v) end) end
    if type(i) == "number" then t[i] = true; names[#names + 1] = n .. "=" .. i end
  end
  JL.sneakVals = t
  if #names == 0 then
    log("Stealth: could NOT resolve any gamePSMLocomotionStates crouch value -> sneak behaviour disabled "
        .. "(Jackie will keep walking abreast while V crouches). Enum names may have changed this patch.")
  else
    log("Stealth: crouch locomotion states resolved -> " .. table.concat(names, ", "))
  end
  return t
end

-- v1.51: the RAW read — "is V crouched right now?" — with no mod-feature gate on it. The Blaze finale's
-- calm-hold needs this to verify V actually stood up, and that must not depend on Config.stealth.enabled.
-- jlVSneaking() below is this plus the stealth feature's on/off switch and a per-frame cache.
function jlVCrouched()
  local val = false
  pcall(function()
    local pl = Game.GetPlayer(); if not pl then return end
    local defs = GetAllBlackboardDefs().PlayerStateMachine
    local bb                                            -- the documented accessor...
    pcall(function() bb = pl:GetPlayerStateMachineBlackboard() end)
    if not bb then                                      -- ...falling back to the route blazeClearCombat uses
      pcall(function() bb = Game.GetBlackboardSystem():GetLocalInstanced(pl:GetEntityID(), defs) end)
    end
    if not bb then return end
    val = (jlSneakStates())[bb:GetInt(defs.Locomotion)] == true
  end)
  return val
end

function jlVSneaking()
  local S = Config.stealth or {}
  if S.enabled == false then return false end
  local st = JL.abreast
  local now = JL.clock or 0
  if st.snFrame == now then return st.sneaking end     -- compute once per frame (two ticks ask)
  st.snFrame = now
  st.sneaking = jlVCrouched()
  return st.sneaking
end

-- v1.46 DIAGNOSTIC (logs once). The engine hides a companion from enemy perception automatically —
-- `SenseComponent.ShouldIgnoreIfPlayerCompanion` short-circuits sensing, threat-tracking AND reactions for
-- anyone `AIHumanComponent.IsPlayerCompanion()` accepts. That returns true only when BOTH hold: his AI role
-- is Follower, and his `FriendlyTarget` behaviour arg is the player. AMM's "set as companion" establishes
-- both, so a properly-promoted Jackie should be invisible to guards for free.
-- Antonia nevertheless reports guards spotting him while sneaking. Either he is NOT truly a Follower-role
-- companion (this log settles it), or he was simply being walked into their faces by walk-abreast's
-- lead-ahead anchor (which v1.46 now stops). Print the answer once so the next test run tells us which.
function jlCompanionCheck()
  if JL.companionChecked then return end
  JL.companionChecked = true
  local h = JL.summon.spawn and JL.summon.spawn.handle
  if not h then JL.companionChecked = nil; return end   -- no body yet; ask again next tick
  local ok, val = pcall(function() return h:GetAIControllerComponent():IsPlayerCompanion() end)
  if not ok then
    log("Stealth: IsPlayerCompanion() unavailable on this build (cannot verify enemy-perception immunity).")
  elseif val then
    log("Stealth: Jackie IS a Follower-role player companion -> enemies should ignore him entirely.")
  else
    log("Stealth: ⚠ Jackie is NOT registered as a player companion -> enemies CAN see him. "
        .. "The Follower role / FriendlyTarget arg did not stick; AMM's companion promotion needs re-running.")
  end
end

-- v1.47 FOLLOWER TAKEDOWN. The Heist's parallel takedown reduced to its mechanism: one AI command, with the
-- victim passed as a plain runtime handle. See the long note on Config.takedown for the decompiled sources.
-- The handler's ONLY gates on the victim are these two, so we check them up front and explain the refusal
-- rather than firing a command the behaviour tree will silently drop.
-- Globals -> 200-local cap safe.
-- The handler's two gates FAIL OPEN: if a static isn't reachable, or returns a non-boolean, we leave the
-- default and let the behaviour tree run its own (identical) validation rather than refuse a good target.
-- The SAFETY gates below FAIL CLOSED — an unreadable attitude means we refuse, never guess.
function jlValidVictim(o)
  if not o then return false, "no target" end
  local T = Config.takedown or {}

  -- v1.48 SAFETY. Nothing in this path deals damage — the engine owns the grapple — but ordering a takedown
  -- on V or on a friendly is still wrong, so refuse before the command is ever built.
  local isPlayer = false
  pcall(function() local v = o:IsPlayer(); if type(v) == "boolean" then isPlayer = v end end)
  if isPlayer then return false, "that's V" end
  if T.requireHostile ~= false then
    -- EAIAttitude = { AIA_Friendly=0, AIA_Neutral=1, AIA_Hostile=2 }. Resolve AIA_Hostile by NAME (like every
    -- other enum here) and compare as ints, so this works whether CET hands us an enum object or a number.
    -- Fail CLOSED: an unreadable attitude refuses. But resolve the constant defensively — if the enum name
    -- itself can't be resolved we fall back to its ordinal rather than refusing every takedown outright.
    local want = 2
    do
      local e = jlAnimEnum("EAIAttitude", "AIA_Hostile")
      if e ~= nil then pcall(function() local i = EnumInt(e); if type(i) == "number" then want = i end end) end
    end
    local got
    pcall(function()
      local att = o:GetAttitudeTowards(Game.GetPlayer())
      if type(att) == "number" then got = att
      elseif att ~= nil then pcall(function() got = EnumInt(att) end) end
    end)
    if type(got) ~= "number" then
      return false, "couldn't read that target's attitude towards V (refusing, to be safe)"
    end
    if got ~= want then return false, "that one isn't hostile to V" end
  end

  local active, grappled = true, false
  pcall(function() local v = ScriptedPuppet.IsActive(o);        if type(v) == "boolean" then active   = v end end)
  pcall(function() local v = ScriptedPuppet.IsBeingGrappled(o); if type(v) == "boolean" then grappled = v end end)
  if not active then return false, "that target is not active (already dead or unconscious)" end
  if grappled   then return false, "that target is already being grappled" end
  return true
end

-- v1.48 Is a takedown running? While it is, our leash ticks must NOT re-issue movement commands to Jackie:
-- a fresh AIFollowTargetCommand / AIMoveToCommand replaces the takedown mid-approach and he just walks back
-- to V. (That is bug #2 behind "the NPC survived".) Global -> 200-local cap safe.
function jlTakedownBusy()
  local t = JL.takedown
  if not t or not t.deadline then return false end
  if (Config.takedown or {}).holdCommands == false then return false end
  return (JL.clock or 0) < t.deadline
end

-- Watch the ordered takedown to a conclusion and say what happened. Stepped from onUpdate.
-- Success = the victim is being grappled, or has stopped being active (down). Otherwise we time out and
-- hand Jackie back to the leash rather than freezing him forever.
function jlTakedownTick()
  local t = JL.takedown
  if not t or not t.deadline then return end
  local now, v = (JL.clock or 0), t.victim
  local grappled, active = false, true
  if v then
    pcall(function() local b = ScriptedPuppet.IsBeingGrappled(v); if type(b) == "boolean" then grappled = b end end)
    pcall(function() local b = ScriptedPuppet.IsActive(v);        if type(b) == "boolean" then active   = b end end)
  end
  if grappled and not t.sawGrapple then
    t.sawGrapple = true
    log("Takedown: the grapple STARTED — the follower behaviour tree accepted the command.")
  end
  if not active then
    log("Takedown: SUCCESS — the target is down" .. (t.sawGrapple and " (grapple played)." or " (no grapple seen)."))
    JL.takedown = nil
    return
  end
  if now >= t.deadline then
    log("Takedown: TIMED OUT after " .. tostring((Config.takedown or {}).timeoutSeconds or 15.0) .. " s — "
        .. (t.sawGrapple and "the grapple began but never finished."
                          or "Jackie never grappled. The follower BT ignored the command (is he a Follower-role "
                          .. "companion? check the Stealth: line) or the target moved out of reach."))
    JL.takedown = nil
  end
end

-- Issue the takedown. Returns (ok, message) — the message is shown in the CET panel and logged.
function jlTakedown(victim)
  local T = Config.takedown or {}
  local h = JL.summon.spawn and JL.summon.spawn.handle
  if not h then return false, "Jackie isn't spawned." end
  -- The takedown task lives ONLY in the Follower role's behaviour tree. Without the role the command is
  -- accepted and then quietly ignored, so refuse early and say why.
  if not (JL.summon.active and JL.summon.companionSet) then
    return false, "Jackie isn't a companion yet — the takedown only exists in the Follower behaviour tree."
  end
  local okV, why = jlValidVictim(victim)
  if not okV then return false, "Can't take that one down: " .. why .. "." end
  local sent = pcall(function()
    local cmd = NewObject('handle:AIFollowerTakedownCommand')
    cmd.target                         = victim          -- the runtime handle; targetRef stays empty
    cmd.approachBeforeTakedown         = (T.approachBeforeTakedown ~= false)
    cmd.doNotTeleportIfTargetIsVisible = (T.doNotTeleportIfTargetIsVisible ~= false)
    -- v1.48 THE FLAG THAT MAKES IT ACTUALLY FIRE. PlayerPuppet.OnTakedownOrder sets exactly this before
    -- broadcasting the same class. IsCombatCommand() has no script callers — the follower behaviour tree
    -- reads it natively to route the command into its takedown subtree. Left false, the command is
    -- accepted and silently ignored, which is why the first build left the guard standing.
    cmd.combatCommand                  = (T.combatCommand ~= false)
    h:GetAIControllerComponent():SendCommand(cmd)
  end)
  if not sent then
    log("Takedown: FAILED to construct/send AIFollowerTakedownCommand — the class may not be reachable "
        .. "from CET on this build. Falling back is a config decision (Config.takedown).")
    return false, "AIFollowerTakedownCommand could not be sent on this build (see jackie_debug.log)."
  end
  -- Arm the hold: for the next `timeoutSeconds` the follow / abreast / catch-up ticks leave Jackie alone,
  -- so they cannot cancel the takedown mid-approach. jlTakedownTick watches it to a conclusion.
  JL.takedown = { victim = victim, deadline = (JL.clock or 0) + ((T.timeoutSeconds or 15.0)), sawGrapple = false }
  log("Takedown: issued AIFollowerTakedownCommand to Jackie (approach="
      .. tostring(T.approachBeforeTakedown ~= false) .. ", combatCommand="
      .. tostring(T.combatCommand ~= false) .. "). Leash held for "
      .. tostring(T.timeoutSeconds or 15.0) .. " s.")
  return true, "Takedown issued — watch Jackie."
end

-- MVP test hook: take down whatever NPC V is currently looking at. Mirrors the existing
-- "Defeat target (look at)" debug button, so the aiming behaviour is already familiar.
function jlTakedownLookAt()
  local pl = Game.GetPlayer(); if not pl then return false, "no player" end
  local o
  pcall(function()
    local ts = Game.GetTargetingSystem()
    if ts then o = ts:GetLookAtObject(pl, false, false) end
  end)
  if not o then return false, "Aim at an NPC first." end
  return jlTakedown(o)
end

-- v1.46 THE SINGLE HANDOFF PREDICATE. followKeepCloseTick (the trail) runs BEFORE abreastTick each frame
-- and yields to abreast; abreastTick then decides whether it actually wants him. Before v1.46 the two asked
-- DIFFERENT questions (the trail yielded on bare `jlVWalking()`), so any gate added to abreastTick alone
-- opened a hole: on stairs the trail stood down AND abreast stood down, nobody drove Jackie, and he fell
-- back to AMM's long native leash. Both ticks now ask this one question, so exactly one of them owns him.
-- Global -> 200-local cap safe.
function jlAbreastOn()
  local A = Config.abreast or {}
  if not A.enabled or not JL.customWalk then return false end      -- v1.57: opt-in; default = plain trailing follower
  if not (JL.summon.active and JL.summon.companionSet) then return false end
  if JL.dinner.phase or JL.leaving.phase or (JL.varrival and JL.varrival.phase) then return false end
  if jlCruise and jlCruise.active then return false end            -- not while cruising on his bike
  if jlTakedownBusy() then return false end                        -- v1.48: a takedown owns him; don't re-issue
  if jlInCombat() then return false end                            -- fighting -> free him to fight
  if jlVertical() then return false end                            -- v1.46: stairs/slope -> single file
  if jlVSneaking() then return false end                           -- v1.46: crouched -> shadow her, never lead
  -- v1.57: V is basically standing -> the TRAIL owns him, because that's where the loiter halt lives. With
  -- stock values jlVWalking() already says no here (stopSpeed sits below walkMinSpeed), but the two are
  -- independently tunable now, so state it explicitly rather than rely on the bands not overlapping — if
  -- both ticks thought they owned him he'd be shoved to a side anchor and told to hold still at once.
  if jlVLoitering() then return false end
  return jlVWalking()
end

-- v0.67 KEEP-CLOSE FOLLOW. After handoff we issue ONE tight follow (followDistance), but AMM's own
-- companion follow then takes over with a much LONGER leash, so Jackie trails far behind V. This
-- re-asserts our tight AIFollowTargetCommand on a throttle so he holds `Config.follow.distance` (a few
-- metres) instead. Gated to the settled companion state only (not mid-arrival/dinner/walk-off) so it
-- never fights the scripted movement. If it ever looks jittery in-game, raise `interval` or set
-- enabled=false. Tiering: this owns ~handoff..catchUp.distance; catchUpTick teleports beyond that.
local function followKeepCloseTick()
  local F = Config.follow or {}
  if F.enabled == false then return end
  -- v1.48: a takedown is running — re-asserting the follow here would REPLACE it and walk him back to V.
  -- (jlAbreastOn() is false during a takedown, so without this the trail would happily grab him.)
  if jlTakedownBusy() then return end
  if jlInCombat() then return end   -- v1.35: fighting -> don't re-leash; native combat AI runs him
  -- v0.85b: abreast owns positioning ONLY while V walks; at jog/sprint the trail takes back over.
  -- v1.39: ...unless the player disabled the custom walk, in which case this trail is the default follower.
  -- v1.46: ask jlAbreastOn() — the SAME predicate abreastTick uses — so the two can never both stand down
  -- (on stairs the old `jlVWalking()` test here yielded to an abreast that had already gated itself off).
  if jlAbreastOn() then return end
  if not (JL.summon.active and JL.summon.companionSet) then return end
  if JL.dinner.phase or JL.leaving.phase or (JL.varrival and JL.varrival.phase)
     or (jlCruise and jlCruise.active) then return end   -- v0.85: leave him on his cruising bike
  local h = JL.summon.spawn and JL.summon.spawn.handle
  if not h then return end
  local now = JL.clock or 0
  -- v1.57: the geometry reads moved ABOVE the re-issue throttle so the loiter halt below can react within
  -- its own sustain window instead of waiting out F.interval (1.5 s) as well.
  -- don't fight the catch-up teleport: if he's far enough for that to own him, leave it.
  local pp = playerPos(); if not pp then return end
  local jp; pcall(function() jp = h:GetWorldPosition() end); if not jp then return end
  if dist3(pp, jp) > ((Config.catchUp and Config.catchUp.distance) or 25.0) then return end
  -- --- v1.57 LOITER HALT: V is basically standing -> so does Jackie -----------------------------------
  -- The follow command has no "close enough, stop" state, so a V who's just nudging about (aiming, reading
  -- a shard, browsing a vendor) had Jackie endlessly micro-correcting around her. jlVLoitering() is the
  -- hysteretic gate — slow for `stopSustain` to plant him, and only faster than `goSpeed` for `goSustain`
  -- to set him off again (the "inertia"). He is only allowed to plant himself once he's ALREADY close
  -- (slider + holdSlack); further out he keeps closing the gap first, or a V who stops while he's 15 m
  -- back would strand him there. Re-issued on `holdInterval` because the hold command is time-limited.
  if jlVLoitering() and dist3(pp, jp) <= (jlFollowDistance() + ((Config.loiter or {}).holdSlack or 2.0)) then
    if (now - (JL.loiter.lastHoldAt or -1e9)) >= ((Config.loiter or {}).holdInterval or 2.0) then
      JL.loiter.lastHoldAt = now
      jlHalt(h)
    end
    return
  end
  JL.loiter.lastHoldAt = nil   -- he's moving again -> the next halt takes effect immediately
  if (now - (JL.follow.lastAt or -1e9)) < (F.interval or 1.5) then return end
  JL.follow.lastAt = now
  -- v1.46: while V SNEAKS, shadow her — trail at the stealth gap and never Run (a running Jackie overshoots
  -- her and ends up in front, which is how he kept walking into the enemy she was creeping up on).
  local S = Config.stealth or {}
  if S.enabled ~= false and jlVSneaking() then
    jlCompanionCheck()   -- v1.46: one-time diagnostic — is he really a Follower-role companion?
    sendWalkToPlayer(h, S.movement or "Walk", S.followDistance or 3.0, S.stealthGait ~= false)
    return
  end
  sendWalkToPlayer(h, F.movement or "Run", jlFollowDistance())   -- v1.55: the slider drives the trail too
end

-- v0.85b WALK-ABREAST. Instead of trailing behind V (keep-close), hold Jackie at a point OFFSET from V —
-- beside / slightly ahead — computed from V's forward vector, so he walks next to her, not on the long
-- companion leash. Offsets are polar in V's own frame (`angleRight`/`angleLeft`, fractional dial steps of
-- `positions`; 0 = dead ahead, 3 = V's right, 9 = V's left) at `radius` m.
--
-- v0.85b tuning (Antonia's in-game feedback — this is now the DEFAULT companion behaviour):
--  * SMOOTH heading. V's INSTANT forward made the anchor snap on every camera twitch -> jitter. We EMA V's
--    forward (time-constant `smoothSeconds`) each frame and place the anchor off the SMOOTHED heading.
--  * CLOSEST SIDE. Two candidate anchors — `angleRight` and `angleLeft` (near-front on each side). Jackie
--    takes whichever is closer to where he already is, with a small stickiness margin, so he doesn't cut
--    across in front of V. He holds that side until the other is clearly closer.
--  * ANGULAR LEASH (v1.36 — replaces the jittery distance-chase of v1.3/v1.32). Jackie ambles inside a WIDE
--    zone (`zoneRadius`) around his side anchor, walking FORWARD with V (target led ahead by `leadDistance`)
--    at walk pace. His hurdle to SPRINT is high: he sprints ONLY once he drifts into the REAR ARC behind V
--    (`rearArcFrac` of the circle, centred directly behind her) — measured as the angle between V's forward
--    and the V->Jackie vector, so it's independent of distance. He sprints to the set angle, and once back
--    inside `zoneRadius` he CALMS to a walk and holds there until he falls into the rear arc again.
--  * WALK-ONLY. Only active while V WALKS (jlVWalking); at jog/sprint abreastTick yields and the trail
--    (followKeepCloseTick) takes over — V has 3 speeds, Jackie 2, so he can't out-pace a jogging V.
--  * OPT-IN (v1.57). `JL.customWalk` (Esc -> Settings -> Jackie Lives -> Gameplay) turns this whole
--    behaviour ON. It is OFF by default — out of the box Jackie is the plain trailing follower.
-- Command re-issue is throttled to `interval` (short, so he tracks the drifting anchor). Global -> cap safe.
function abreastTick()
  local A = Config.abreast or {}
  -- v1.46: every gate now lives in jlAbreastOn() (shared with followKeepCloseTick's yield test), so the
  -- trail picks him up in exactly the cases abreast declines him — stairs and slopes included.
  if not jlAbreastOn() then
    JL.abreast.smFwdX = nil     -- reset the heading EMA so it re-seeds cleanly when abreast resumes
    JL.abreast.catching = nil   -- v1.36: re-engage re-evaluates behind/hold from scratch
    return
  end
  local h = JL.summon.spawn and JL.summon.spawn.handle
  if not h then return end
  local pp = playerPos(); if not pp then return end
  local jp; pcall(function() jp = h:GetWorldPosition() end); if not jp then return end
  if dist3(pp, jp) > ((Config.catchUp and Config.catchUp.distance) or 25.0) then return end  -- catch-up owns him

  -- --- smoothed V-forward (EMA, updated every frame) -----------------------------------------------
  local fx, fy = 0.0, 1.0
  pcall(function()
    local f = Game.GetPlayer():GetWorldForward()
    if f then local m = math.sqrt(f.x * f.x + f.y * f.y); if m > 1e-4 then fx, fy = f.x / m, f.y / m end end
  end)
  local now = JL.clock or 0
  local dt  = now - (JL.abreast.lastFrame or now); JL.abreast.lastFrame = now
  if not JL.abreast.smFwdX then JL.abreast.smFwdX, JL.abreast.smFwdY = fx, fy end
  -- v1.3/v1.36: PHASED smoothing. While SPRINTING in (fallen behind) aim at a near-INSTANT heading
  -- (catchUpSmoothSeconds) so he heads straight to where V is NOW; while HOLDING, use the slow smoothSeconds
  -- EMA so the leash drifts, never snaps. Uses last frame's `catching` latch (updated below) -> lags one
  -- frame, fine.
  local catching = (JL.abreast.catching == true)
  local tau   = catching and (A.catchUpSmoothSeconds or 0.5) or (A.smoothSeconds or 3.3)
  local alpha = (tau > 0) and math.min(math.max(dt / tau, 0.0), 1.0) or 1.0
  local sx = JL.abreast.smFwdX + alpha * (fx - JL.abreast.smFwdX)
  local sy = JL.abreast.smFwdY + alpha * (fy - JL.abreast.smFwdY)
  local sm = math.sqrt(sx * sx + sy * sy); if sm > 1e-4 then sx, sy = sx / sm, sy / sm end
  JL.abreast.smFwdX, JL.abreast.smFwdY = sx, sy

  -- --- two candidate anchors off the smoothed heading; pick the side closest to Jackie --------------
  -- v1.55 FLEXIBLE BAND. The nominal radius is the player's slider (jlFollowDistance). But we do NOT drag
  -- him onto that exact ring every re-issue — that's what made him fight for a spot. If his CURRENT distance
  -- from V already sits inside [minRadius, maxRadius] (1.2-5 m), we accept it and build the anchor at that
  -- distance, correcting only his ANGLE (beside her, not behind). He's only pulled back toward the nominal
  -- radius when he's strayed outside the band. Note this is the FLAT (x/y) distance, matching the anchor maths.
  local rad  = jlFollowDistance()
  local curR = math.sqrt((jp.x - pp.x) ^ 2 + (jp.y - pp.y) ^ 2)
  local minR = A.minRadius or 1.2
  local maxR = A.maxRadius or 5.0
  if curR >= minR and curR <= maxR then rad = curR end   -- already comfortable -> keep his distance, fix the angle
  local pos  = A.positions or 12
  local rx, ry = sy, -sx                                    -- right vector (smoothed forward rotated -90°)
  local function anchor(idx)
    local ang = math.rad(idx * (360.0 / pos))
    local ca, sa = math.cos(ang), math.sin(ang)
    return pp.x + (sx * ca + rx * sa) * rad, pp.y + (sy * ca + ry * sa) * rad
  end
  local rX, rY = anchor(A.angleRight or 0.85)              -- V's right-of-ahead
  local lX, lY = anchor(A.angleLeft or 11.25)             -- V's left-of-ahead
  local function d2(ax, ay) return math.sqrt((jp.x - ax) ^ 2 + (jp.y - ay) ^ 2) end
  local gapR, gapL = d2(rX, rY), d2(lX, lY)
  -- sticky closest-side: keep the current side unless the other is closer by > sideHysteresis.
  local side = JL.abreast.side
  if side ~= "R" and side ~= "L" then side = (gapR <= gapL) and "R" or "L" end
  local m = A.sideHysteresis or 0.6
  if side == "R" and gapL < gapR - m then side = "L"
  elseif side == "L" and gapR < gapL - m then side = "R" end
  JL.abreast.side = side
  local tx, ty, gap = (side == "R") and rX or lX, (side == "R") and rY or lY, (side == "R") and gapR or gapL

  -- --- ANGULAR LEASH (v1.36): free-walk zone + sprint ONLY when he falls into the rear arc behind V ------
  -- The old "chase an exact moving point" logic jittered. Now `behind` is purely ANGULAR: the angle between
  -- V's forward and the V->Jackie vector. He's "behind" once that angle enters the rear arc (rearArcFrac of
  -- the circle, centred directly behind V). LATCH: he only STARTS sprinting when he falls behind, and only
  -- STOPS once he's sprinted back inside zoneRadius of the set angle — then he calms to a walk and holds.
  local dvx, dvy = jp.x - pp.x, jp.y - pp.y
  local rlen = math.sqrt(dvx * dvx + dvy * dvy)
  local fdot = (rlen > 1e-3) and ((dvx * sx + dvy * sy) / rlen) or 1.0   -- cos(angle off V-forward): 1 ahead, -1 behind
  local rearCos = math.cos(math.pi * (1.0 - (A.rearArcFrac or 0.40)))    -- behind when fdot < this (108° at 0.40)
  local catchingNow = JL.abreast.catching == true
  if not catchingNow then
    if fdot < rearCos then catchingNow = true end                       -- fell into the rear arc -> sprint
  else
    if gap <= (A.zoneRadius or 1.5) then catchingNow = false end         -- reached the set angle -> calm down
  end
  JL.abreast.catching = catchingNow
  local sprinting = catchingNow

  -- Target: while SPRINTING in, aim at the anchor itself (tight). While HOLDING, aim at a point a little
  -- AHEAD of the anchor along V's heading (leadDistance) so he strolls FORWARD with V inside the wide leash
  -- instead of stop-starting on the exact spot.
  local lead = A.leadDistance or 2.0
  local destX = sprinting and tx or (tx + sx * lead)
  local destY = sprinting and ty or (ty + sy * lead)

  -- --- issue on a short throttle; SPRINT while catching up (behind V), else Walk his natural gait ---------
  -- (v1.39: pace-match time-dilation removed — it made his stride float and broke the angular leash. He now
  -- just walks his own Walk gait and only sprints when he falls into the rear arc.) Holding desiredDistance
  -- = zoneRadius (the WIDE leash) so he settles anywhere in the zone and strolls, never fighting for a spot.
  if (now - (JL.abreast.lastAt or -1e9)) < (A.interval or 0.3) then return end
  JL.abreast.lastAt = now
  -- v1.46: GROUND THE ANCHOR (built here, past the throttle — the navmesh query is not free, and only the
  -- point we're about to send needs to be correct). Copying V's z verbatim only holds on flat ground: on an
  -- incline the point several metres ahead of her is under the surface (climbing) or above it (descending),
  -- and the nav projection then picks a different floor from one re-issue to the next. Snap it down onto the
  -- human navmesh instead. If the snap fails, or lands far enough from V's height to be a DIFFERENT floor (a
  -- balcony/metro deck the downward sphere search happened to find), distrust it and keep V's z — the old
  -- behaviour, harmless on flat ground. jlVertical() already puts him single-file on stairs, so this only
  -- has to cope with ramps and gentle slopes.
  local dest   = Vector4.new(destX, destY, pp.z, 1.0)
  local ground = snapToNavmesh(dest)
  if ground and math.abs(ground.z - pp.z) <= (A.maxAnchorZDelta or 2.5) then dest = ground end
  local mv  = sprinting and (A.catchUpMovement or "Sprint") or (A.movement or "Walk")
  local tol = sprinting and (A.catchUpTolerance or 0.35) or (A.zoneRadius or 1.5)
  sendMoveToPoint(h, dest, mv, tol)
end

-- v0.80: SUBTITLE WATCHDOG — the guaranteed cleanup. Stepped every frame from onUpdate. The old bug:
-- subtitle cleanup lived on each individual dialogue path, so any branch that ended without hitting a
-- hideSubtitle() (or a one-off line with no follow-up) left the bottom band stuck forever, because the
-- native band doesn't reliably auto-expire on this build. This is the belt-and-braces fix: if a line is
-- STILL showing past its own display time AND nothing owns the band right now (no talk / call / walk-off),
-- force-clear it. It never fires mid-conversation (Branch.busy/open, dlg.active, a live call, or the
-- leaving parting-line all keep it hands-off), so it can only ever wipe a genuinely orphaned subtitle.
-- Global (not a top-level local) so the 200-local cap is unaffected.
function subtitleWatchdogTick()
  if not subtitle.line then return end                 -- nothing on the band
  if not subtitle.dueAt then return end                -- its display time isn't tracked yet
  if (JL.clock or 0) < subtitle.dueAt then return end  -- still within its intended time on screen
  -- someone is actively driving the band? leave it alone.
  if Branch.busy or Branch.open then return end
  if dlg and dlg.active then return end
  if JL.leaving and JL.leaving.phase == "walking" then return end   -- leavingTick owns its parting line
  local c = JL.call
  if c and (c.ringingAt or c.connectAt or c.hangupAt or c.watchdogAt or c.noAnswerAt) then return end
  hideSubtitle()
  log("Subtitle watchdog: cleared a dangling subtitle (no active conversation).")
end

-- stepped from onUpdate: (1) reveal the menu once Jackie's line has played; (2) after the
-- player's chosen line has shown ~1s, advance to the next node or end the conversation.
local function branchTick()
  if bstate.openAt and (JL.clock or 0) >= bstate.openAt then
    bstate.openAt = nil
    if bstate.node and bstate.node.choices then
      openChoiceMenu(withCompanionExtras(withDateChoices(bstate.node, bstate.node.choices)), "Jackie")
    elseif bstate.node then
      -- v0.34c: terminal node with NO choices -> after Jackie's line, auto-end the convo and run
      -- its node-level `action` (e.g. gig accept -> summon). No redundant "Let's do it" V click.
      bstate.pending       = "__end__"
      bstate.pendingAction = bstate.node.action
      bstate.pendingAt     = JL.clock or 0
    end
  end
  if bstate.pendingAt and (JL.clock or 0) >= bstate.pendingAt then
    bstate.pendingAt = nil
    local nxt = bstate.pending; bstate.pending = nil
    if nxt and nxt ~= "__end__" then
      Branch.start(nxt)
    else
      Branch.busy = false
      local wasCall = (bstate.tree == Config.callTree
                       or bstate.tree == Config.reunionCallTree)
      bstate.tree = nil
      local act = bstate.pendingAction; bstate.pendingAction = nil
      if wasCall then
        hideSubtitle()
        if act == "summon_arrival" or act == "reunion_arrival" then
          -- v0.33e: Jackie already agreed to come - a V sign-off here ("...don't keep me
          -- waitin'") reads awkward. Skip it; just hang up after a short beat.
          JL.call.hangupAction = act
          JL.call.hangupAt = (JL.clock or 0) + 0.4
        else
          -- other call strands: V's random sign-off shows, THEN we hang up (callTick.hangupAt)
          showDialogueText("V", pickFarewell(), 1.8, Game.GetPlayer())
          JL.call.hangupAction = act
          JL.call.hangupAt = (JL.clock or 0) + 1.8
        end
        JL.ui.status = "Call wrapping up..."
      else
        -- v0.32: if this was a cooldown'd talk tree (the `everywhere` backup), stamp it DONE now so
        -- further F presses just grunt until the cooldown expires. Read it BEFORE Branch.finish (which
        -- clears bstate.talkCooldownKey as part of the reset).
        local cdKey = bstate.talkCooldownKey
        if cdKey then
          JL.talkDone[cdKey] = JL.clock or 0
          log("Branch: '" .. tostring(cdKey) .. "' marked DONE; cooldown started.")
        end
        Branch.finish("Dialogue ended.")   -- v0.80: authoritative close — overlay + subtitle, always
        log("Branch: end.")
        if act == "recruit_here" then pcall(recruitIdleJackie)   -- v0.39: idle Jackie -> companion in place
        elseif act then pcall(function() runCallAction(act) end) end
      end
      bstate.talkCooldownKey = nil
    end
  end
end

-- ---------------------------------------------------------------------------
-- Schedule tick (instant spawn/despawn MVP)
-- ---------------------------------------------------------------------------
local function clearIdle()
  if JL.idle.spawn and JL.idle.spawn.handle then   -- v0.39: get him out of any sit/lean workspot first
    pcall(function() Game.GetWorkspotSystem():StopInDevice(JL.idle.spawn.handle) end)
  end
  if JL.idle.spawn then ammDespawn(JL.idle.spawn) end
  JL.idle.spawn, JL.idle.locationKey = nil, nil
  JL.idle.posed, JL.idle.pendingPose, JL.idle.pendingSit = false, nil, nil
  JL.idle.placed, JL.idle.phase = false, nil
  JL.idle.curIdx, JL.idle.tgtIdx = nil, nil
  JL.idle.leaving, JL.idle.leaveTarget, JL.idle.leaveDeadline, JL.idle.leaveReissue = false, nil, 0, 0
end

-- ---------------------------------------------------------------------------
-- Free-roam wander (v0.35): idle Jackie strolls between his location's waypoints.
-- He's a PASSIVE NPC throughout (no follower role), so the AIMoveToCommand path used for the
-- walk-in / walk-off drives him here too. Stepped from onUpdate via wanderTick().
-- ---------------------------------------------------------------------------
local function locWaypoints(loc)
  if loc and loc.waypoints and #loc.waypoints > 0 then return loc.waypoints end
  -- no explicit waypoints -> a single anchor point built from pos/yaw (he just stands there)
  if loc and loc.pos then
    return { { pos = loc.pos, yaw = loc.yaw or 0.0, pose = loc.sitNearest and "sit" or "stand" } }
  end
  return nil
end

local function wpVec(wp)  return { x = wp.pos[1], y = wp.pos[2], z = wp.pos[3] } end
local function wpVec4(wp) return Vector4.new(wp.pos[1], wp.pos[2], wp.pos[3], 1.0) end

local function dwellFor(wp)
  local W  = Config.wander or {}
  local lo = (wp.dwell and wp.dwell[1]) or W.dwellMin or 15.0
  local hi = (wp.dwell and wp.dwell[2]) or W.dwellMax or 45.0
  if hi < lo then hi = lo end
  return lo + math.random() * (hi - lo)
end

-- Pick a random waypoint that ISN'T the current one (so he never paces straight back-and-forth).
local function pickNextWaypoint(wps, cur)
  local n = #wps
  if n < 2 then return 1 end
  for _ = 1, 8 do
    local r = math.random(1, n)
    if r ~= cur then return r end
  end
  return (cur % n) + 1
end

-- v0.43b: apply the MASTER idle-collision switch (Config.idleNoCollision) to the live idle Jackie.
-- ON  -> collision OFF for his whole stay (chairs/stalls can't block or shove him).
-- OFF -> collision ON (normal). Owned ONLY by the idle system. See COLLISION OWNERSHIP map up top.
-- Safe to call repeatedly (at placement and whenever the switch is flipped in the window).
local function applyIdleCollision()
  local h = JL.idle.spawn and JL.idle.spawn.handle
  if not h then return end
  setNpcCollision(h, not Config.idleNoCollision)
  JL.idle.collisionOff = Config.idleNoCollision and true or false
end

-- v0.39 SIT/LEAN via AMM workspots. Stop any workspot pose on a handle (gets him out of the chair
-- / off the wall) before he walks again.
local function stopWorkspotPose(handle)
  if not handle then return end
  pcall(function() Game.GetWorkspotSystem():StopInDevice(handle) end)
  -- v0.44: collision is NOT touched here (callers own it — see COLLISION OWNERSHIP map up top).
  JL.idle.posed = false
  JL.idle.pendingPose, JL.idle.pendingSit = nil, nil   -- cancel any not-yet-fired pose/sit
end

-- Play a real sit/lean animation on Jackie using AMM's proven Poses pipeline. Returns true if
-- the call went through (no guarantee it visually took — guarded; falls back to standing).
local function tryWorkspotPose(handle, pose, nameOverride)
  local P = Config.poses
  if not (P and P.enabled) then return false end
  if pose ~= "sit" and pose ~= "lean" then return false end
  local name = nameOverride or P[pose]; if not name then return false end  -- per-waypoint poseAnim wins
  local amm = getAMM()
  if not amm or not amm.Poses or not amm.NewTarget or not amm.GetScanID then return false end
  -- v0.44: NO collision handling here. tryWorkspotPose is shared by the IDLE and DINNER systems,
  -- which manage collision differently (idle = master switch at placement; dinner = around the seat).
  -- Doing it here made the two fight. Each caller owns collision now. See the COLLISION OWNERSHIP map
  -- near the top of this file.
  local ok = pcall(function()
    local t = amm:NewTarget(handle, "NPCPuppet", amm:GetScanID(handle), "Jackie", nil, nil)
    local anim = { name = name, rig = P.rig or "Man Average", comp = P.comp or "amm_workspot_base",
                   ent = P.ent or "base\\amm_workspots\\entity\\workspot_anim.ent" }
    amm.Poses:PlayAnimationOnTarget(t, anim)
  end)
  if ok then JL.idle.posed = true end
  return ok
end

-- Snap onto a waypoint (with optional poseOffset for sit/lean alignment) facing its yaw, then
-- SCHEDULE the sit/lean workspot for `Config.poses.delay` s later — playing it now would spawn the
-- pose prop at his pre-teleport spot (the float bug). wanderTick fires the pending pose when due.
local function applyIdlePose(handle, wp, forceSnap)
  if not handle or not wp then return end
  local W = Config.wander or {}
  -- the exact seat point (anchor + optional poseOffset) and its facing
  local v = wpVec4(wp)
  if (wp.pose == "sit" or wp.pose == "lean") and wp.poseOffset then
    v = Vector4.new(wp.pos[1] + (wp.poseOffset.x or 0), wp.pos[2] + (wp.poseOffset.y or 0),
                    wp.pos[3] + (wp.poseOffset.z or 0), 1.0)
  end
  if forceSnap or W.faceYawOnArrive ~= false then
    pcall(function() aiTeleport(handle, v, wp.yaw or 0.0) end)   -- nav-snap walk to roughly the spot
  end
  if wp.pose == "sit" or wp.pose == "lean" then
    -- v0.45: carry the EXACT pos + yaw so the deferred fire can lock his seat position AND facing
    -- (placeAtExact) right before the workspot plays — fixes the wrong-seat-angle on arrival.
    JL.idle.pendingPose = { pose = wp.pose, name = wp.poseAnim, vec = v, yaw = wp.yaw or 0.0,
                            at = (JL.clock or 0) + ((Config.poses and Config.poses.delay) or 0.5) }
  else
    JL.idle.pendingPose, JL.idle.pendingSit = nil, nil
  end
end

-- ===========================================================================
-- v1.41 LOOK-AT / head tracking. See the long note on Config.lookAt. We queue ONE `entLookAtAddEvent`
-- onto the puppet and the engine head-tracks V by itself from then on — including through a sit
-- workspot, because it's an additive animation-graph overlay rather than a body rotation. We only
-- decide WHEN he should be tracking; we never drive the rotation, so there's nothing to jitter.
-- All GLOBAL functions -> cost no top-level local (200-cap).
-- ===========================================================================

-- Resolve a named enum value, tolerating CET exposing it as a global table, via Enum.new, or not at all.
-- Returns nil on failure so the caller can skip that setter — the event still works on its defaults.
function jlAnimEnum(enumName, valueName)
  local v
  pcall(function() local t = _G[enumName]; if t and t[valueName] ~= nil then v = t[valueName] end end)
  if v == nil then pcall(function() v = Enum.new(enumName, valueName) end) end
  return v
end

-- Construct the look-at event. CET's marshalling for this class is UNVERIFIED (no shipped Lua mod builds
-- one), so try each construction form in turn and remember the one that worked to keep the log quiet.
function jlNewLookAtEvent()
  local evt
  if JL.lookAtCtor ~= "NewObject" and JL.lookAtCtor ~= "handle" then
    pcall(function() evt = entLookAtAddEvent.new() end)
    if evt then JL.lookAtCtor = "new"; return evt end
  end
  if JL.lookAtCtor ~= "handle" then
    pcall(function() evt = NewObject("entLookAtAddEvent") end)
    if evt then JL.lookAtCtor = "NewObject"; return evt end
  end
  pcall(function() evt = NewObject("handle:entLookAtAddEvent") end)
  if evt then JL.lookAtCtor = "handle"; return evt end
  return nil
end

-- Begin head-tracking V. Stores the event on JL.lookAt because the matching REMOVE has to reference the
-- same event object (it carries the outLookAtRef the engine handed back).
function jlLookAtStart(h)
  local L  = Config.lookAt or {}
  local pl = Game.GetPlayer()
  if not (h and pl) then return false end
  JL.lookAt = JL.lookAt or { on = false }   -- self-init: callable from a debug button before the first tick
  local evt = jlNewLookAtEvent()
  if not evt then
    if not JL.lookAtWarned then
      JL.lookAtWarned = true
      log("LookAt: cannot construct entLookAtAddEvent -> head tracking OFF (Jackie behaves exactly as before).")
    end
    return false
  end
  local ok = pcall(function()
    pcall(function() evt.bodyPart = CName.new(L.bodyPart or "Eyes") end)
    -- Target the PLAYER ENTITY (not a static position): the engine then follows her as she moves,
    -- which is the whole reason we don't need a per-frame update.
    evt:SetEntityTarget(pl, CName.new(L.targetSlot or "pla_default_tgt"), Vector4.new(0, 0, 0, 0))
    pcall(function() evt:SetStyle(jlAnimEnum("animLookAtStyle", "Normal")) end)
    pcall(function()
      evt:SetLimits(jlAnimEnum("animLookAtLimitDegreesType",  L.softLimit or "Wide"),
                    jlAnimEnum("animLookAtLimitDegreesType",  L.hardLimit or "Wide"),
                    jlAnimEnum("animLookAtLimitDistanceType", L.distLimit or "None"),
                    jlAnimEnum("animLookAtLimitDegreesType",  L.backLimit or "Normal"))
    end)
    h:QueueEvent(evt)
  end)
  if not ok then
    if not JL.lookAtWarned then
      JL.lookAtWarned = true
      log("LookAt: setup/QueueEvent threw -> head tracking OFF (Jackie behaves exactly as before).")
    end
    return false
  end
  JL.lookAt.evt, JL.lookAt.handle, JL.lookAt.on = evt, h, true
  log(("LookAt: now tracking V (ctor=%s, bodyPart=%s)."):format(tostring(JL.lookAtCtor), tostring(L.bodyPart or "Eyes")))
  return true
end

-- Stop head-tracking. Preferred path is the engine's own static helper; if CET won't dispatch the static,
-- hand-build the remove event and point it at the ref the add event returned. Failing BOTH is harmless —
-- the look-at simply stays on, which is the pretty failure rather than the ugly one.
function jlLookAtStop()
  local st = JL.lookAt
  if not (st and st.on) then return end
  local h, evt = st.handle, st.evt
  st.on, st.evt, st.handle = false, nil, nil
  if not (h and evt) then return end
  local ok = pcall(function() LookAtRemoveEvent.QueueRemoveLookatEvent(h, evt) end)
  if not ok then
    pcall(function()
      local rm = NewObject("entLookAtRemoveEvent")
      rm.lookAtRef = evt.outLookAtRef
      h:QueueEvent(rm)
    end)
  end
  log("LookAt: stopped.")
end

-- Which Jackie (if any) should be head-tracking V right now? The on-foot COMPANION is excluded: his
-- AIFollowTargetCommand already carries `lookAtTarget`, so he head-tracks already and stacking a second
-- look-at on him buys nothing. The two cases that have NO follow command — and so a frozen stare — are:
--   * IDLE Jackie at a venue (standing, leaning, or parked on his barstool)
--   * SEATED-at-dinner Jackie (still a companion, but the follow role is dropped while he eats)
function jlLookAtSubject()
  if JL.idle.spawn and JL.idle.spawn.handle and not JL.idle.leaving then
    return JL.idle.spawn.handle
  end
  if JL.dinner and JL.dinner.phase == "seated" and JL.summon.spawn then
    return JL.summon.spawn.handle
  end
  return nil
end

function jlLookAtTick()
  local L = Config.lookAt or {}
  JL.lookAt = JL.lookAt or { on = false }
  if not L.enabled then if JL.lookAt.on then jlLookAtStop() end; return end
  local st  = JL.lookAt
  local now = JL.clock or 0
  if now < (st.checkAt or 0) then return end
  st.checkAt = now + (L.check or 0.5)

  local h = jlLookAtSubject()
  if not h then if st.on then jlLookAtStop() end; return end
  if st.on and st.handle ~= h then jlLookAtStop() end   -- respawned/swapped body: old event is orphaned

  local pp = playerPos(); if not pp then return end
  local jp; pcall(function() jp = h:GetWorldPosition() end)
  if not jp then return end
  local d = dist3(pp, jp)

  if st.on then
    -- Re-arm across a pose change: playing a workspot rebuilds his animation graph, which can drop the
    -- overlay. `posed` only flips when he sits/stands, so this is not a per-frame cost.
    if st.posed ~= JL.idle.posed then
      st.posed = JL.idle.posed
      jlLookAtStop()
      if d <= (L.range or 12.0) then jlLookAtStart(h) end
      return
    end
    if d > (L.dropRange or 15.0) then jlLookAtStop() end
  elseif d <= (L.range or 12.0) then
    st.posed = JL.idle.posed
    jlLookAtStart(h)
  end
end

-- ===========================================================================
-- DINNER state machine (v0.43, seat reworked v0.44). Defined here (not with startDinnerWalk)
-- because it needs the pose/move helpers above. Phases: walking -> seating -> seated. Jackie stays
-- our companion (JL.summon.active) the whole time; we only swap his AI ROLE (follow <-> sit).
-- COLLISION: this system OWNS Jackie's collision while he's seating/seated — it drops it on entering
-- `seating` (so the chair/table can't block him reaching the seat or shove him out) and restores it
-- when he stands. It does NOT rely on the idle master switch or wanderTick (both are dead while he's
-- a companion). See the COLLISION OWNERSHIP map up top.
-- ===========================================================================
local function dinnerTick()
  local D = JL.dinner
  if not D.phase then return end
  local h = JL.summon.spawn and JL.summon.spawn.handle
  if not JL.summon.active or not h then               -- dismissed / gone -> abort cleanly
    pcall(clearDinnerWaypoint)
    if h then
      pcall(function() stopWorkspotPose(h) end)
      if D.collisionOff then setNpcCollision(h, true) end   -- never leave a freed entity collision-less
    end
    D.phase, D.collisionOff, D.seatDeadline, D.sitFireAt = nil, false, nil, nil
    return
  end
  local C   = Config.date or {}
  local now = JL.clock or 0
  local pp  = playerPos()

  if D.phase == "walking" then
    -- arrived = V within seatTriggerRadius of the seat. Then Jackie drops follow + heads to his seat.
    if pp and D.dest and dist3(pp, D.dest) <= (C.seatTriggerRadius or 12.0) then
      pcall(clearDinnerWaypoint)                       -- reached -> drop pin + objective
      pcall(function()                                 -- drop follower role so he obeys move+sit
        local role = h:GetAIControllerComponent():GetAIRole()
        if role then role:OnRoleCleared(h) end
        h.isPlayerCompanionCached = false
      end)
      setNpcCollision(h, false)                        -- v0.44: collision OFF so the chair can't block him
      D.collisionOff = true
      D.satAt, D.sitFireAt = nil, nil
      D.seatDeadline = now + (C.seatTimeout or 12.0)   -- v0.44: force the sit if he can't path within reach
      pcall(function() sendMoveToPoint(h, D.dest, "Walk", 0.5) end)
      D.phase = "seating"
      JL.ui.status = "Jackie's grabbin' his seat."
      log("Dinner: V arrived; Jackie heading to his seat.")
    end
    return
  end

  if D.phase == "seating" then
    if not D.satAt then
      -- (a) within reach OR timeout -> lock EXACT seat pos + facing NOW (v0.45 placeAtExact), then arm a
      --     deferred sit. Placing here (not at sit-time) leaves a gap so the async teleport lands before
      --     the workspot plays — same-frame would let it eject him. Forcing yaw keeps the seat angle
      --     consistent no matter which way he walked in.
      if not D.sitFireAt then
        local jp; pcall(function() jp = h:GetWorldPosition() end)
        local reached = jp and dist3(jp, D.dest) <= (C.seatReachRadius or 2.0)
        if reached or now >= (D.seatDeadline or 0) then
          placeAtExact(h, D.dest, D.destYaw or 0.0)
          D.sitFireAt = now + ((Config.poses and Config.poses.delay) or 0.5)
          if not reached then log("Dinner: seat reach timed out -> snapping him onto the seat.") end
        end
        return
      end
      -- (b) he's settled at the exact seat now -> just play the sit (NO teleport here).
      if now >= D.sitFireAt then
        pcall(function() tryWorkspotPose(h, "sit") end)
        D.satAt, D.sitFireAt = now, nil
        log("Dinner: Jackie seated.")
      end
      return
    end
    -- `sitWaitSeconds` after sitting -> one final line + the (once/24h) full reset
    if now - D.satAt >= (C.sitWaitSeconds or 2.0) then
      pcall(function() speakJackieLine(C.doneText, C.doneSfx) end)
      armCompanionTimer((Config.companion and Config.companion.maxGameHours) or 6.0)
      D.lastResetGame = getGameSeconds()   -- stamp the day: the start gate refuses a 2nd dinner within 24h
      JL.ui.status = "Good dinner - Jackie's clock is reset."
      log("Dinner: companion clock fully reset; dinner stamped for the day.")
      D.phase = "seated"
    end
    return
  end

  if D.phase == "seated" then
    -- He stands up + re-joins as companion (stays JL.summon.active) when EITHER V walks off (>getUpRadius)
    -- OR V ends the seated small-talk with "Enough chillin', let's go" (v0.83: D.leaveNow set by the action).
    local jp; pcall(function() jp = h:GetWorldPosition() end)
    local viaMenu = D.leaveNow == true
    if viaMenu or (pp and jp and dist3(pp, jp) >= (C.getUpRadius or 10.0)) then
      D.leaveNow = nil
      pcall(function() stopWorkspotPose(h) end)
      setNpcCollision(h, true)                          -- v0.44: restore collision before he follows again
      D.collisionOff = false
      -- the menu path already spoke his parting line (seatedTree `leave` node) — don't double it up
      if not viaMenu then pcall(function() speakJackieLine(C.getUpText, C.getUpSfx) end) end
      pcall(promoteToCompanion)                         -- re-add follower role + follow (also re-enables collision)
      D.phase, D.dest, D.satAt, D.seatDeadline, D.sitFireAt = nil, nil, nil, nil, nil
      JL.ui.status = "Jackie's back with you."
      log("Dinner: " .. (viaMenu and "'let's go' chosen" or "V left") .. "; Jackie up + following again.")
    end
    return
  end
end

-- v0.48: schedule Jackie's NEXT self-initiated dinner offer, a random in-game gap from now, tied to the
-- current companion session (so a fresh session re-rolls instead of firing instantly on a stale stamp).
local function scheduleJackieDinnerOffer()
  local g = getGameSeconds(); if not g then return end
  local ji = Config.date and Config.date.jackieInvite
  local mn = ((ji and ji.minGapGameMinutes) or 20.0) * 60
  local mx = ((ji and ji.maxGapGameMinutes) or 45.0) * 60
  local r  = 0; pcall(function() r = math.random() end)
  JL.dinner.nextOfferGame = g + mn + r * math.max(0, mx - mn)
  JL.dinner.offerSession  = JL.summon.companionSinceGame
end

-- v0.48: while Jackie is your companion and a dinner is available (off the once/24h cooldown), after the
-- scheduled gap HE just SAYS a hungry hint (jackieInvite.text) — no picker, no choices. It nudges V to use
-- her own "Wanna get something to eat?" invite. The gap is tuned close to his max summon time.
local function jackieDinnerOfferTick()
  local ji = Config.date and Config.date.jackieInvite
  if not (ji and ji.enabled) then return end
  if not (JL.summon.active and JL.summon.companionSet) then return end
  if JL.dinner.phase then return end                                  -- already mid-outing
  if JL.leaving.phase == "walking" then return end                    -- heading home, don't interrupt
  if Branch.open or Branch.busy or (dlg and dlg.active) then return end -- never talk over a conversation
  if not dateUnlocked() then return end
  local g = getGameSeconds(); if not g then return end
  local cd = (Config.date.resetCooldownHours or 24.0) * 3600
  if JL.dinner.lastResetGame and (g - JL.dinner.lastResetGame) < cd then return end  -- he just ate out
  -- (re)schedule on a fresh companion session or if never scheduled
  if JL.dinner.offerSession ~= JL.summon.companionSinceGame or not JL.dinner.nextOfferGame then
    scheduleJackieDinnerOffer(); return
  end
  if g < JL.dinner.nextOfferGame then return end
  scheduleJackieDinnerOffer()                                         -- arm the next gap regardless
  pcall(function() speakJackieLine(ji.text, ji.sfx) end)             -- just the line — V invites him for real
  JL.ui.status = "Jackie's gettin' hungry."
  log("Dinner: Jackie dropped a hungry hint.")
end

-- (v0.64) The persistent ImGui "head to dinner" objective was replaced by a native neon-left
-- on-screen flash fired once from startDinnerWalk (showOnscreenMsg). Map waypoint still guides.

local function wanderTick()
  if not (Config.wander and Config.wander.enabled) then return end
  if JL.summon.active then return end                  -- following V -> not idle-wandering
  if JL.idle.leaving then return end                   -- walking off to despawn -> idleLeavingTick owns him
  local sp = JL.idle.spawn
  local h  = sp and sp.handle
  if not h then return end
  local loc = Config.locations[JL.idle.locationKey]
  local wps = locWaypoints(loc)
  if not wps then return end
  local now = JL.clock or 0
  local W   = Config.wander

  -- v1.1 SEAT-TUNER WALK-IN (replaces the respawn/teleport re-seat that never took). Get him UP, walk
  -- him to a start point a few metres out, then walk him INTO the exact tuned coordinate and sit. Uses
  -- ONLY the walk command the idle wander already uses to move him between waypoints (proven to work) —
  -- never a teleport on a workspot-pinned puppet (that was the "solid as a rock" failure). Collisions
  -- stay off so he can walk into the bar-stool. Driven here (idle Jackie's per-frame tick) and RETURNS
  -- while active so the normal dwell/wander loop can't fight it. Loud logs so we can see each step.
  local TW = JL.tuner.walk
  if TW and TW.phase then
    local jp; pcall(function() jp = h:GetWorldPosition() end)
    if TW.phase == "toStart" then
      local d = jp and dist3(jp, { x = TW.startVec.x, y = TW.startVec.y, z = TW.startVec.z }) or 99
      if d <= 1.0 or now >= TW.deadline then
        TW.phase, TW.deadline, TW.nextAt = "toSeat", now + 6.0, 0
        log(("TUNER walk: reached start (d=%.2f m) -> walking into seat."):format(d))
      elseif now >= (TW.nextAt or 0) then
        TW.nextAt = now + 1.5
        pcall(function() sendMoveToPoint(h, TW.startVec, "Walk", 0.6) end)
      end
    elseif TW.phase == "toSeat" then
      local d = jp and dist3(jp, { x = TW.seatVec.x, y = TW.seatVec.y, z = TW.seatVec.z }) or 99
      if d <= 0.8 or now >= TW.deadline then
        placeAtExact(h, TW.seatVec, TW.yaw)                 -- STANDING now -> exact lock works (unlike when seated)
        TW.phase, TW.at = "sitting", now + 0.45
        log(("TUNER walk: at seat (d=%.2f m) -> exact place + sit in 0.45 s."):format(d))
      elseif now >= (TW.nextAt or 0) then
        TW.nextAt = now + 1.5
        pcall(function() sendMoveToPoint(h, TW.seatVec, "Walk", 0.4) end)
      end
    elseif TW.phase == "sitting" then
      if now >= (TW.at or 0) then
        pcall(function() tryWorkspotPose(h, "sit", TW.poseAnim) end)
        JL.tuner.walk = nil
        JL.idle.phase, JL.idle.dwellUntil = "dwelling", now + 3600   -- hold him seated while you judge the fit
        log("TUNER walk: sit played. DONE — nudge sliders + 'Move Jackie here' to redo.")
        JL.ui.status = "Seated. Nudge sliders + Move Jackie here to redo."
      end
    end
    return   -- walk-in owns him this frame; skip the normal dwell/wander logic below
  end

  -- v0.45 deferred sit/lean in TWO steps so the (async) exact-teleport lands BEFORE the workspot plays
  -- (playing it same-frame let the workspot re-pin him at the OLD spot — the "tuner does nothing" bug):
  --   (1) pendingPose -> placeAtExact (exact pos + facing) + arm pendingSit a beat later
  if JL.idle.pendingPose and now >= JL.idle.pendingPose.at then
    local pend = JL.idle.pendingPose; JL.idle.pendingPose = nil
    if pend.vec then placeAtExact(h, pend.vec, pend.yaw) end
    JL.idle.pendingSit = { pose = pend.pose, name = pend.name, vec = pend.vec, yaw = pend.yaw,
                           at = now + 0.4 }
  end
  --   (2) pendingSit -> he's now settled at the exact spot/facing from step (1); just play the workspot
  --       (NO teleport here — an async one would land after the pose and eject him from the seat).
  if JL.idle.pendingSit and now >= JL.idle.pendingSit.at then
    local s = JL.idle.pendingSit; JL.idle.pendingSit = nil
    pcall(function() tryWorkspotPose(h, s.pose, s.name) end)
  end

  -- (0) PLACE him on a starting waypoint shortly after spawn (let the entity settle first).
  if not JL.idle.placed then
    if (now - (JL.idle.spawnedAt or 0)) < 0.6 then return end
    applyIdleCollision()                               -- v0.43b: kill collision BEFORE the snap so the chair can't block him
    -- v1.1 seat tuner: if the tuner drove this (re)spawn it pins the EXACT seat it's editing
    -- (JL.idle.forceStartIdx) instead of a random waypoint, and HOLDS him there (long dwell) so he
    -- doesn't wander off mid-tune. A fresh, standing puppet always sits where we place it — this is
    -- why the tuner respawns him rather than teleporting a workspot-pinned (seated) puppet.
    local forced       = JL.idle.forceStartIdx
    JL.idle.forceStartIdx = nil
    local startIdx     = (forced and wps[forced]) and forced or math.random(1, #wps)
    JL.idle.curIdx     = startIdx
    applyIdlePose(h, wps[startIdx], true)              -- force-teleport him onto the spot
    JL.idle.placed     = true
    JL.idle.phase      = "dwelling"
    JL.idle.dwellUntil = forced and (now + 3600) or (now + dwellFor(wps[startIdx]))
    return
  end

  if #wps < 2 then return end                          -- single spot: just stand there

  if JL.idle.phase == "dwelling" then
    if now >= (JL.idle.dwellUntil or 0) then
      stopWorkspotPose(h)                            -- v0.39: get up out of the chair / off the wall first
      local tgt = pickNextWaypoint(wps, JL.idle.curIdx)
      JL.idle.tgtIdx      = tgt
      JL.idle.phase       = "walking"
      JL.idle.arriveBy    = now + (W.arriveTimeout or 30.0)
      JL.idle.lastReissue = now
      pcall(function() sendMoveToPoint(h, wpVec4(wps[tgt]), W.movement or "Walk", W.arriveDist or 1.5) end)
    end
  elseif JL.idle.phase == "walking" then
    local wp = wps[JL.idle.tgtIdx]
    if not wp then JL.idle.phase = "dwelling"; JL.idle.dwellUntil = now + 5.0; return end
    local jp; pcall(function() jp = h:GetWorldPosition() end)
    local d = jp and dist3(jp, wpVec(wp)) or nil
    if (d and d <= (W.arriveDist or 1.5) + 0.6) or now >= (JL.idle.arriveBy or 0) then
      JL.idle.curIdx     = JL.idle.tgtIdx
      applyIdlePose(h, wp)                             -- snap + face on arrival, then dwell
      JL.idle.phase      = "dwelling"
      JL.idle.dwellUntil = now + dwellFor(wp)
    elseif (now - (JL.idle.lastReissue or 0)) >= (W.repath or 2.5) then
      JL.idle.lastReissue = now
      pcall(function() sendMoveToPoint(h, wpVec4(wp), W.movement or "Walk", W.arriveDist or 1.5) end)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Walk-away (v0.38): when his block ends and you're watching, idle Jackie strolls to the venue's
-- exit (loc.exitWaypoint -> Coyote upstairs / Lizzie's outside; else just away from V) and
-- despawns once he reaches it, leaves your range, or leaveTimeout passes. Reuses the passive
-- AIMoveToCommand path (sendMoveToPoint / awayPoint).
-- ---------------------------------------------------------------------------
local function idleExitTarget(loc, h)
  if loc and loc.exitWaypoint and loc.exitWaypoint.pos then
    local e = loc.exitWaypoint
    return Vector4.new(e.pos[1], e.pos[2], e.pos[3], 1.0)
  end
  return awayPoint(h, (Config.transitions and Config.transitions.exitReach) or 18.0)  -- no exit -> walk off
end

-- Start the walk-off. Returns true if it began (caller falls back to instant clearIdle on false).
local function beginIdleDeparture()
  local sp = JL.idle.spawn; local h = sp and sp.handle
  if not h then return false end
  if not (Config.transitions and Config.transitions.departOnFoot) then return false end
  -- only bother animating the exit if you're actually around to see it
  local pp = playerPos(); local jp; pcall(function() jp = h:GetWorldPosition() end)
  if not pp or not jp or dist3(pp, jp) > (Config.proximityRadius or 45.0) then return false end
  local loc = Config.locations[JL.idle.locationKey]
  local tgt = idleExitTarget(loc, h)
  if not tgt then return false end
  local now = JL.clock or 0
  stopWorkspotPose(h)   -- v0.39: get up out of any sit/lean before he walks to the exit
  pcall(function() sendMoveToPoint(h, tgt, (Config.wander and Config.wander.movement) or "Walk", 1.0) end)
  JL.idle.leaving       = true
  JL.idle.leaveTarget   = tgt
  JL.idle.leaveDeadline = now + ((Config.transitions and Config.transitions.leaveTimeout) or 20.0)
  JL.idle.leaveReissue  = now
  log("Idle Jackie leaving " .. (loc and loc.name or "?") .. " -> walking to exit.")
  return true
end

-- Stepped from onUpdate: drive the walk-off, despawn when he reaches the exit / leaves range / times out.
local function idleLeavingTick()
  if not JL.idle.leaving then return end
  if JL.summon.active then clearIdle(); return end      -- summoned a companion mid-walk -> drop the idle one
  local sp = JL.idle.spawn; local h = sp and sp.handle
  if not h then JL.idle.leaving = false; return end
  local now = JL.clock or 0
  local pp = playerPos(); local jp; pcall(function() jp = h:GetWorldPosition() end)
  local T  = Config.transitions or {}
  local reached = false
  if jp and JL.idle.leaveTarget then
    reached = dist3(jp, { x = JL.idle.leaveTarget.x, y = JL.idle.leaveTarget.y, z = JL.idle.leaveTarget.z })
              <= (T.leaveReachDist or 2.5)
  end
  local outOfRange = (pp and jp) and dist3(pp, jp) > (Config.proximityRadius or 45.0) + 5.0
  local timedOut   = now >= (JL.idle.leaveDeadline or 0)
  if reached or outOfRange or timedOut then
    clearIdle()   -- despawns + resets leaving state
    log(("Idle Jackie gone (%s)."):format(reached and "reached exit" or (outOfRange and "out of range" or "timeout")))
  elseif (now - (JL.idle.leaveReissue or 0)) >= ((Config.wander and Config.wander.repath) or 2.5) then
    JL.idle.leaveReissue = now
    pcall(function() sendMoveToPoint(h, JL.idle.leaveTarget, (Config.wander and Config.wander.movement) or "Walk", 1.0) end)
  end
end

-- v0.40 RETURN-TO-POST: dismissing companion Jackie while he's near the venue the schedule wants
-- him at -> hand the SAME entity back to the idle system, drop his follower role, and walk him to
-- the nearest waypoint so he re-joins the cycle (no despawn/respawn). Returns true if it took over.
-- (Assigns the forward-declared `returnToPost` upvalue so runCallAction can reach it.)
returnToPost = function()
  local sp = JL.summon.spawn; local h = sp and sp.handle
  if not h then return false end
  local block = currentScheduleBlock()
  if not (block and block.state == "at_location") then return false end
  local loc = Config.locations[block.locationKey]
  if not (loc and loc.pos) then return false end
  local anchor = { x = loc.pos[1], y = loc.pos[2], z = loc.pos[3] }
  local jp; pcall(function() jp = h:GetWorldPosition() end)
  local ref = jp or playerPos()
  local radius = (Config.transitions and Config.transitions.returnRadius) or 100.0
  if not ref or dist3(ref, anchor) > radius then return false end       -- too far -> normal dismiss
  -- drop the follower role so the companion AI stops pulling him back (same as startLeaving)
  pcall(function()
    local role = h:GetAIControllerComponent():GetAIRole()
    if role then role:OnRoleCleared(h) end
    h.isPlayerCompanionCached = false
  end)
  -- hand the live entity back to the idle/schedule system (no despawn)
  JL.summon.spawn, JL.summon.active, JL.summon.companionSet, JL.summon.walkIn = nil, false, false, false
  JL.idle.spawn, JL.idle.locationKey = sp, block.locationKey
  JL.idle.leaving, JL.idle.posed = false, false
  applyIdleCollision()   -- v0.43b: re-joining idle -> apply the master collision switch to this entity
  -- walk to the NEAREST waypoint, then wanderTick takes over (dwell -> cycle)
  local wps = locWaypoints(loc) or {}
  local ti, best = 1, 1e9
  for i, wp in ipairs(wps) do local d = dist3(ref, wpVec(wp)); if d < best then best, ti = d, i end end
  JL.idle.placed      = true
  JL.idle.phase       = "walking"
  JL.idle.curIdx      = ti
  JL.idle.tgtIdx      = ti
  JL.idle.arriveBy    = (JL.clock or 0) + ((Config.wander and Config.wander.arriveTimeout) or 30.0)
  JL.idle.lastReissue = JL.clock or 0
  if wps[ti] then
    pcall(function() sendMoveToPoint(h, wpVec4(wps[ti]), (Config.wander and Config.wander.movement) or "Walk",
                                     (Config.wander and Config.wander.arriveDist) or 1.5) end)
  end
  JL.ui.status = "Jackie's headin' back to his spot at " .. (loc.name or "?") .. "."
  log("Dismiss: RETURN TO POST at " .. (loc.name or "?") .. " (re-joining idle cycle).")
  return true
end

-- v0.41 secret sleeping-hours cameo: during the sleep window, a once-per-night roll. Returns the
-- secret location key when he's "showing up" tonight, else nil. Re-rolls each new night.
local function secretWantKey(hour)
  local S = Config.secret
  if not (S and S.locationKey and Config.locations[S.locationKey] and Config.locations[S.locationKey].pos) then return nil end
  if hour == nil then return nil end
  if not hourInBlock(hour, S.startHour or 0, S.endHour or 6) then
    JL.secret.decided, JL.secret.active = false, false   -- left the window -> reset for next night
    return nil
  end
  if not JL.secret.decided then
    JL.secret.active  = (math.random() < (S.chance or 0.2))
    JL.secret.decided = true
    log("Secret nap roll: " .. (JL.secret.active and "YES — he's at the nap spot tonight" or "no"))
  end
  return JL.secret.active and S.locationKey or nil
end

-- v1.3 APPROACH CAMEO: raise how often V actually bumps into Jackie. When V gets within
-- Config.approach.radius (20 m) of one of his venues during his active hours (06:00–00:00), roll
-- once to force his schedule to THAT venue for the rest of the in-game day. The first appearance of
-- the day rolls at premiumChance (35%); each fresh venue-approach keeps rolling at that rate until
-- one lands, after which every roll drops to repeatChance (10%). The noodle bar is ALWAYS
-- noodleChance (10%) since V passes it constantly. Global (not local) to respect the 200-local cap.
--   hour        = current game hour (nil if unreadable)
--   naturalWant = the venue the normal schedule already wants him at now (don't re-roll there)
-- Returns the forced venue key while V is within proximityRadius of it, else nil (so a force set
-- earlier in the day never suppresses his real scheduled spot when V is somewhere else).
function approachTick(hour, naturalWant)
  local A = JL.approach
  local C = Config.approach
  if not (C and C.enabled) then return nil end
  -- once-per-in-game-day reset, keyed off the same day counter the schedule rotation uses
  local today = JL.day and JL.day.count or 0
  if A.day ~= today then
    A.day, A.premiumUsed, A.forcedKey, A.near = today, false, nil, {}
  end
  -- active hours only: sleep window (00:00–06:00) is left to the secret-nap cameo
  if hour == nil or hour < 6.0 then A.near = {}; return nil end
  local pp = playerPos(); if not pp then return nil end

  for _, key in ipairs(C.venues or {}) do
    local loc = Config.locations[key]
    if loc and loc.pos then
      local inside = dist3(pp, { x = loc.pos[1], y = loc.pos[2], z = loc.pos[3] }) <= (C.radius or 20.0)
      -- rising edge only: roll the first tick V crosses into the radius, then stay armed-off until
      -- V leaves and comes back. Skip venues he's already at (forced) or headed to (natural).
      if inside and not A.near[key] and key ~= A.forcedKey and key ~= naturalWant then
        local rate = (key == "noodle") and (C.noodleChance or 0.10)
                     or (A.premiumUsed and (C.repeatChance or 0.10) or (C.premiumChance or 0.35))
        local hit = math.random() < rate
        log(string.format("Approach roll: V near %s (%.0f%%) -> %s",
                           loc.name or key, rate * 100, hit and "HIT — Jackie shows here today" or "miss"))
        if hit then A.forcedKey, A.premiumUsed = key, true end
      end
      A.near[key] = inside
    end
  end

  -- apply the day's forced venue ONLY while V is actually near it
  if A.forcedKey then
    local fl = Config.locations[A.forcedKey]
    if fl and fl.pos and dist3(pp, { x = fl.pos[1], y = fl.pos[2], z = fl.pos[3] }) <= (Config.proximityRadius or 45.0) then
      return A.forcedKey
    end
  end
  return nil
end

local function scheduleTick()
  if JL.idle.leaving then return end                 -- a departure is in progress; idleLeavingTick owns it
  if JL.summon.active then clearIdle(); return end
  if not Retrieval.isUnlocked() then clearIdle(); return end   -- gated: Jackie stays "absent" until the retrieval quest is done
  if not Config.enableSchedule then clearIdle(); return end

  -- what location (if any) the schedule wants him at right now
  local block, hour = currentScheduleBlock()
  local wantKey = nil
  if block and block.state == "at_location" then
    local wl = Config.locations[block.locationKey]
    if wl and wl.pos then wantKey = block.locationKey end
  end
  -- secret nap cameo: while asleep/unavailable, he may be at the hidden spot instead
  if not wantKey then wantKey = secretWantKey(hour) end
  -- v1.3 approach cameo: V walking up to a venue can force him there for the day (overrides the
  -- normal schedule so he shows up where V actually is). See approachTick.
  local forced = approachTick(hour, wantKey)
  if forced then wantKey = forced end
  -- DEBUG override (CET window "Force venue"): pin him to one venue regardless of time
  if JL.ui.forceVenue and Config.locations[JL.ui.forceVenue] and Config.locations[JL.ui.forceVenue].pos then
    wantKey = JL.ui.forceVenue
  end

  -- spawned where the schedule no longer wants him -> walk away (or instant-clear if not watched)
  if JL.idle.spawn and JL.idle.locationKey ~= wantKey then
    if not beginIdleDeparture() then clearIdle() end
    return
  end

  if not wantKey then clearIdle(); return end

  local loc  = Config.locations[wantKey]
  local pp   = playerPos(); if not pp then return end
  local near = dist3(pp, { x = loc.pos[1], y = loc.pos[2], z = loc.pos[3] }) <= Config.proximityRadius
  if near then
    if not JL.idle.spawn then
      local spawn, err = ammSpawn(0, loc.appearance)   -- v0.36: wear this location's outfit
      if spawn then
        JL.idle.spawn, JL.idle.locationKey = spawn, wantKey
        JL.idle.placed, JL.idle.phase      = false, nil   -- v0.35: wanderTick places + roams him
        JL.idle.curIdx, JL.idle.tgtIdx     = nil, nil
        JL.idle.spawnedAt                  = JL.clock or 0
        -- v1.55: he's at Misty's, and in Husbando that only ever happens ONCE — latch it (see jlMistyRetired).
        if wantKey == (Config.mistyKey or "misty") then pcall(jlMarkMistyVisited) end
        log("Idle Jackie at " .. loc.name .. " (" .. tostring(loc.appearance or Config.defaultAppearance) .. ")")
      else
        log("Idle spawn failed: " .. tostring(err))
      end
    end
  else
    clearIdle()   -- player not nearby; no one's watching, just remove him
  end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
-- v0.44: register the "Jackie Lives" page in the Esc -> Settings screen via Native Settings UI.
-- DEFERRED + RETRIED from onUpdate (see nsTick) rather than run once in onInit, because CET loads
-- mods alphabetically: "JackieLives" initializes BEFORE "nativeSettings", so GetMod() is nil at our
-- onInit and a one-shot attempt silently fails (the menu then shows "No mods using native settings
-- installed!"). We poll until nativeSettings is available, register exactly once, and LOG any API
-- error instead of swallowing it. State lives in JL.ns so a concurrent JL-table edit won't clash.
local function nsState()
  if not JL.ns then JL.ns = { done = false, attempts = 0 } end
  return JL.ns
end

local function nsTick()
  local s = nsState()
  if s.done then return end
  s.attempts = s.attempts + 1
  if s.attempts > 1200 then   -- ~ a few min at 60 fps; nativeSettings clearly absent -> stop polling
    s.done = true
    log("Native Settings UI not found after retries — Esc-menu panel skipped; CET window still works.")
    return
  end
  local ns = GetMod("nativeSettings")
  if not ns then return end   -- not loaded yet this tick; try again next frame
  s.done = true               -- only ever attempt the real registration once
  -- Dupe-guard for CET hot-reload. CHECK THE TAB PATH ONLY ("/jackielives"), never a sub-path:
  -- nativeSettings.pathExists(".../recovery") indexes data[tab].subcategories on a NIL tab when the
  -- tab doesn't exist yet -> it THROWS. That crash (swallowed by pcall(nsTick), with s.done already
  -- set) was why v0.44/v0.45 silently never registered. pcall-wrapped here as belt-and-suspenders.
  local exists = false
  pcall(function() exists = ns.pathExists and ns.pathExists("/jackielives") end)
  if exists then
    log("Native Settings panel already present (hot-reload) — not re-registering.")
    return
  end
  -- defaults for the persisted flags (jlLoadSettings in onInit may already have set them)
  if JL.husbando == nil then JL.husbando = false end                              -- v0.47 (false = Hermano)
  if JL.disableVehicleArrivals == nil then JL.disableVehicleArrivals = false end  -- v0.51 (false = bike allowed)
  if JL.allowMainGigs == nil then JL.allowMainGigs = false end                    -- v1.32 (false = Quiet Life: no main-mission summons)
  if JL.customWalk == nil then JL.customWalk = false end                          -- v1.57 (false = plain trailing follower)
  if type(JL.followDistance) ~= "number" then JL.followDistance = Config.followDistanceDefault or 3.5 end  -- v1.55 slider
  local ok, err = pcall(function()
    ns.addTab("/jackielives", "Jackie Lives")

    ns.addSubcategory("/jackielives/relationship", "Relationship")
    ns.addSwitch(
      "/jackielives/relationship",
      "Husbando mode",
      "Picks Jackie's relationship track. DEFAULT = OFF (Hermano) for every V — flip it on here " ..
      "if you want the other track. " ..
      "OFF = HERMANO (canon, the default): Jackie's your brother-in-arms, strictly choom. " ..
      "ON = HUSBANDO: same story, but there's an unspoken warmth between Jackie and V — he's softer, " ..
      "and he calls you 'chica' instead of 'mano'. " ..
      "Changes his dialogue, greetings and the reunion/recovery notes to match.",
      JL.husbando,   -- current state (defaults to Hermano; persisted once the player flips it)
      false,         -- 'reset to default' value: HERMANO (v1.54 — was Husbando)
      function(state)
        JL.husbando   = state
        JL.modeChosen = true   -- v1.54: an EXPLICIT player choice — jlDefaultHermano stops forcing the default
        pcall(jlSaveSettings)
        JL.ui.status = "Jackie mode: " .. (state and "Husbando" or "Hermano")
        log("Jackie relationship mode -> " .. (state and "Husbando" or "Hermano") .. " (player choice; remembered)")
      end
    )

    ns.addSubcategory("/jackielives/arrivals", "Arrivals")
    ns.addSwitch(
      "/jackielives/arrivals",
      "Disable vehicle arrivals",
      "ON = Jackie always arrives ON FOOT when summoned. Jackie riding in on his bike often breaks " ..
      "(pathing/physics), so turn this ON if his arrivals glitch. OFF = allow the bike arrival when " ..
      "the arrival method is set to bike.",
      JL.disableVehicleArrivals,   -- current state
      false,                       -- default (vehicle arrivals allowed)
      function(state)
        JL.disableVehicleArrivals = state
        pcall(jlSaveSettings)
        JL.ui.status = "Vehicle arrivals: " .. (state and "DISABLED (foot only)" or "allowed")
        log("Vehicle arrivals -> " .. (state and "DISABLED (foot only)" or "allowed"))
      end
    )

    ns.addSubcategory("/jackielives/gameplay", "Gameplay")
    ns.addSwitch(
      "/jackielives/gameplay",
      "Allow Jackie on main missions",
      "OFF (default, recommended) = the Quiet Life: Jackie only joins SIDE jobs. Try to summon or " ..
      "call him during a MAIN mission and he bows out (\"not draggin' Jackie into this mess\"). " ..
      "ON = you can pull Jackie into main missions too. NOT recommended: it breaks the immersion of " ..
      "his Quiet Life, and main quests run scripted cutscenes where a tag-along companion can glitch, " ..
      "freeze, or get left behind. Leave OFF unless you specifically want him everywhere.",
      JL.allowMainGigs,   -- current state (persisted; default OFF)
      false,              -- 'reset to default' value: OFF (Quiet Life)
      function(state)
        JL.allowMainGigs = state
        pcall(jlSaveSettings)
        JL.ui.status = "Jackie on main missions: " .. (state and "ALLOWED (not recommended)" or "blocked (Quiet Life)")
        log("Allow main-mission summons -> " .. tostring(state))
      end
    )

    ns.addSwitch(
      "/jackielives/gameplay",
      "Walk beside me (custom follow style)",
      "OFF (default) = Jackie trails you like a normal companion. ON = when you're WALKING, he holds a " ..
      "spot BESIDE you instead (the walk-abreast style) — nice on a stroll, but he needs room, so it can " ..
      "look awkward in tight interiors. Turn it on if you want him at your shoulder.",
      JL.customWalk,   -- current state (ON = walk-abreast enabled; persisted)
      false,           -- 'reset to default' value: OFF (plain trailing follower) — v1.57
      function(state)
        JL.customWalk = state
        pcall(jlSaveSettings)
        JL.ui.status = "Walk-beside style: " .. (state and "ON (walk abreast)" or "OFF (default trailing follower)")
        log("Custom walk-beside -> " .. (state and "ON" or "OFF (default follower)"))
      end
    )

    -- v1.55: THE FOLLOW-DISTANCE SLIDER (Antonia asked for it back). One number for BOTH follow modes —
    -- the trail (while you jog/sprint) and the walk-abreast side anchor (while you stroll). Walk-abreast
    -- treats it as a NOMINAL distance, not a hard target: anywhere in Config.abreast.minRadius..maxRadius
    -- (1.2-5 m) is accepted without correction, so he ambles instead of fighting for an exact spot.
    ns.addRangeFloat(
      "/jackielives/gameplay",
      "Jackie's follow distance (m)",
      "How far away Jackie keeps while he's with you — used BOTH when he trails you (running) and when " ..
      "he walks beside you. Lower = he sticks right on your shoulder; higher = he gives you room. " ..
      "While walking beside you he treats this as a rough target, not an exact one: anywhere from about " ..
      "1.2 m to 5 m is fine and he won't keep correcting himself.",
      Config.followDistanceMin or 1.2,          -- min
      Config.followDistanceMax or 8.0,          -- max
      0.1,                                      -- step
      "%.1f",                                   -- display format
      jlFollowDistance(),                       -- current (persisted)
      Config.followDistanceDefault or 3.5,      -- 'reset to default'
      function(value)
        JL.followDistance = value
        pcall(jlSaveSettings)
        JL.ui.status = string.format("Jackie's follow distance: %.1f m", value)
        log(string.format("Follow distance -> %.1f m (trail + walk-abreast)", value))
      end
    )

    -- v1.56: THE MANUAL START. This is what makes it safe to ship the quest gate ON. The gate now stays
    -- silent unless it can POSITIVELY confirm you're post-heist (so it can never spoil a new game) — which
    -- means a player whose journal path we failed to resolve would otherwise be stuck forever. They press
    -- this instead. It's also mentioned on the welcome card, so they know it exists.
    ns.addSubcategory("/jackielives/quest", "The search for Jackie")
    ns.addButton(
      "/jackielives/quest",
      "Start the search for Jackie",
      "Use this if Jackie's questline never started for you. Normally Vik tells you himself when you next " ..
      "visit his clinic — but only once the heist is behind you. If you're past the heist and nothing has " ..
      "happened at Vik's, press this to start the search by hand.",
      "Start",
      function()
        local started = false
        pcall(function() started = Retrieval.startSearch() end)
        JL.ui.status = started and "The search for Jackie has begun — go see Vik."
                                or "The search is already under way."
      end
    )

    ns.addSubcategory("/jackielives/recovery", "Recovery")
    ns.addButton(
      "/jackielives/recovery",
      "Go Home Jackie",
      "Force-despawns every Jackie (including any stuck or duplicate copies), resets him to a clean " ..
      "state, and sends a fresh Jackie back to his scheduled location once you close this menu. " ..
      "Use this if Jackie is missing, frozen, won't follow, or is otherwise misbehaving.",
      "Go Home",   -- button text
      18,          -- font size
      function() pcall(hardReset) end
    )
  end)
  if ok then
    log("Native Settings panel registered (Esc -> Settings -> Jackie Lives -> Recovery).")
  else
    log("Native Settings registration FAILED: " .. tostring(err))
  end
end

-- ===========================================================================
-- RESTORED in v0.72: these three were accidentally dropped by the v0.69 dead-code
-- sweep (the VO/probe deletions), but their CALL SITES survived (nsTick's switch
-- callbacks + the "Go Home Jackie" button + onInit) — so settings persistence and the
-- recovery button had been silently no-op'ing. Brought back verbatim, but as GLOBALS
-- (no `local`) so they don't re-consume the 200-local headroom v0.69 just cleared.
-- ===========================================================================
JL_SETTINGS_FILE = "jl_settings.txt"
JL_SETTINGS_KEYS = { "husbando", "disableVehicleArrivals", "mourningSuppress", "keepBarOpen", "modeChosen", "allowMainGigs", "customWalk" }  -- persisted JL.* boolean flags (customWalk v1.57: walk-abreast is now OPT-IN, so the flag was INVERTED and RENAMED — the old `disableCustomWalk` line in an existing jl_settings.txt simply stops being read, which is exactly what we want: every existing player also drops back to the plain trailing follower until they turn walk-beside on) (modeChosen v1.54: did the player EXPLICITLY flip the Husbando switch? until they do, jlDefaultHermano forces Hermano on every load. Replaces the old `genderLock`, whose auto-detect is gone — an old save carrying genderLock just stops being read, so it re-defaults to Hermano exactly as intended)

-- v1.55: NUMERIC settings. The file used to serialize booleans only (plus the one `mode` string), which is
-- precisely why a slider could never be added — its value didn't survive a reload. These keys round-trip as
-- floats. Kept as a separate list so the boolean loop below stays untouched.
JL_SETTINGS_NUMS = { "followDistance" }

function jlSaveSettings()
  local f = io.open(JL_SETTINGS_FILE, "w")
  if not f then log("settings: could not write " .. JL_SETTINGS_FILE); return end
  for _, k in ipairs(JL_SETTINGS_KEYS) do f:write(k .. "=" .. tostring(JL[k] == true) .. "\n") end
  for _, k in ipairs(JL_SETTINGS_NUMS) do                        -- v1.55 floats
    if type(JL[k]) == "number" then f:write(k .. "=" .. string.format("%.3f", JL[k]) .. "\n") end
  end
  f:write("mode=" .. tostring(JL.mode or "quietlife") .. "\n")  -- v0.95 string setting (not a boolean)
  f:close()
end

function jlLoadSettings()
  local f = io.open(JL_SETTINGS_FILE, "r")
  if not f then return end
  for line in f:lines() do
    -- v1.55: the value class was `%w+`, which cannot match a float ("3.500" contains a '.') — so a numeric
    -- setting would have been written correctly and then silently dropped on load. Accept dots/minus too.
    local k, v = line:match("^(%w+)=([%w%.%-]+)$")
    if k then
      if k == "mode" and (v == "quietlife" or v == "blaze") then JL.mode = v end  -- v0.95
      for _, want in ipairs(JL_SETTINGS_KEYS) do
        if k == want then JL[k] = (v == "true") end
      end
      for _, want in ipairs(JL_SETTINGS_NUMS) do                                  -- v1.55 floats
        if k == want then local n = tonumber(v); if n then JL[k] = n end end
      end
    end
  end
  f:close()
end

-- ===========================================================================
-- SEAT-TUNER PERSISTENCE (v1.1) — fixes the old-S4 "sit coords don't persist on reload" bug.
-- The tuner used to only live-patch the in-memory Config + print a line for a manual config.lua
-- edit; on reload config.lua was re-required with its OLD baked coords, so every tuning session
-- was lost. Now each committed seat is written to jl_seats.txt and re-applied into Config on
-- onInit. The normal re-seat path already reads the live Config waypoint (wpVec/wpVec4/loc.pos),
-- so re-applying the override there is all it takes for the tuned spot to survive a reload AND
-- take effect immediately. Globals (no top-level `local`) to respect the 200-locals cap.
-- File format, one committed seat per line:  key|sitSeatIdx|x|y|z|yaw
-- (sitSeatIdx indexes the venue's SIT waypoints in Config order — the same order the tuner uses.)
-- ===========================================================================
-- ===========================================================================
-- v1.57 WALK TUNING — the knob list, and its persistence (jl_walk.txt).
-- ===========================================================================
-- Antonia: "add better walk abreast tuners (can't tweak much rn)". Two problems with the old tuner:
-- only three of the twenty-odd knobs were exposed, and NOTHING it changed survived a reload — Config is
-- re-required from the baked config.lua every load, so every tuning session evaporated. Same bug the seat
-- tuner had in v1.1, and the same fix: write the overrides to a file and re-apply them into Config on load.
--
-- ONE table drives BOTH the sliders and the file, so a new knob is a single line here and never drifts out
-- of sync. Fields: t = which Config table ("abreast" | "loiter"), k = the key, lo/hi = slider range,
-- label = what the tuner calls it. Order is the order they appear in the panel.
-- Global (no top-level local) -> 200-local cap safe.
JL_WALK_KEYS = {
  -- --- where he stands (walk-abreast) ---
  { t = "abreast", k = "angleRight",           lo = 0.0,  hi = 3.0,  label = "Anchor angle RIGHT (dial steps of 12)" },
  { t = "abreast", k = "angleLeft",            lo = 9.0,  hi = 12.0, label = "Anchor angle LEFT (dial steps of 12)" },
  { t = "abreast", k = "sideHysteresis",       lo = 0.0,  hi = 2.0,  label = "Side-swap stickiness (m)" },
  { t = "abreast", k = "minRadius",            lo = 0.5,  hi = 4.0,  label = "Accepted distance band: MIN (m)" },
  { t = "abreast", k = "maxRadius",            lo = 2.0,  hi = 8.0,  label = "Accepted distance band: MAX (m)" },
  -- --- how he moves ---
  { t = "abreast", k = "smoothSeconds",        lo = 0.5,  hi = 6.0,  label = "Heading smoothing while holding (s)" },
  { t = "abreast", k = "catchUpSmoothSeconds", lo = 0.1,  hi = 2.0,  label = "Heading smoothing while sprinting in (s)" },
  { t = "abreast", k = "interval",             lo = 0.1,  hi = 1.0,  label = "Command re-issue interval (s)" },
  { t = "abreast", k = "rearArcFrac",          lo = 0.15, hi = 0.60, label = "Sprint when behind: rear arc (frac of circle)" },
  { t = "abreast", k = "zoneRadius",           lo = 0.5,  hi = 3.5,  label = "Free-walk zone radius (m)" },
  { t = "abreast", k = "leadDistance",         lo = 0.0,  hi = 4.0,  label = "Walk lead ahead of anchor (m)" },
  { t = "abreast", k = "catchUpTolerance",     lo = 0.1,  hi = 1.5,  label = "Sprint-in target tolerance (m)" },
  -- --- when abreast is allowed at all (V's speed band + the sustain) ---
  { t = "abreast", k = "walkMinSpeed",         lo = 0.1,  hi = 1.5,  label = "V counts as walking ABOVE (m/s)" },
  { t = "abreast", k = "walkMaxSpeed",         lo = 1.0,  hi = 3.0,  label = "V counts as walking BELOW (m/s)" },
  { t = "abreast", k = "jogMinSpeed",          lo = 1.5,  hi = 4.5,  label = "V counts as jogging ABOVE (m/s) -> trail" },
  { t = "abreast", k = "walkSustainSeconds",   lo = 0.0,  hi = 6.0,  label = "Hold the walk band this long first (s)" },
  -- --- the stairs / slope gate ---
  { t = "abreast", k = "slopeRate",            lo = 0.1,  hi = 1.5,  label = "Stairs gate: V's vertical speed (m/s)" },
  { t = "abreast", k = "maxZDelta",            lo = 0.3,  hi = 3.0,  label = "Stairs gate: Jackie-vs-V height gap (m)" },
  { t = "abreast", k = "slopeReleaseSeconds",  lo = 0.0,  hi = 4.0,  label = "Stairs gate: stay trailing after (s)" },
  { t = "abreast", k = "maxAnchorZDelta",      lo = 0.5,  hi = 5.0,  label = "Distrust navmesh anchor beyond (m)" },
  -- --- v1.57 loiter halt (works in BOTH follow modes) ---
  { t = "loiter",  k = "stopSpeed",            lo = 0.0,  hi = 2.0,  label = "STAND STILL when V is slower than (m/s)" },
  { t = "loiter",  k = "goSpeed",              lo = 0.1,  hi = 3.0,  label = "SET OFF when V is faster than (m/s)" },
  { t = "loiter",  k = "stopSustain",          lo = 0.0,  hi = 3.0,  label = "...slow for this long first (s)" },
  { t = "loiter",  k = "goSustain",            lo = 0.0,  hi = 2.0,  label = "...fast for this long first (s) = inertia" },
  { t = "loiter",  k = "holdSlack",            lo = 0.0,  hi = 6.0,  label = "Only stand still within slider + (m)" },
  { t = "loiter",  k = "holdDuration",         lo = 1.0,  hi = 20.0, label = "Hold command duration (s)" },
  { t = "loiter",  k = "holdInterval",         lo = 0.5,  hi = 8.0,  label = "Hold command re-issue every (s)" },
}
-- The two BOOLEAN walk knobs. Same file, written as 1/0.
JL_WALK_BOOLS = {
  { t = "loiter", k = "enabled",        label = "Loiter halt ON (Jackie stands still when V does)" },
  { t = "loiter", k = "useHoldCommand", label = "Use AIHoldPositionCommand (off = move-to-own-spot fallback)" },
}
JL_WALK_FILE = "jl_walk.txt"

-- Flush every live walk knob to disk. Called by the tuner's Save button (not on every slider frame — that
-- would hammer io.open at 60 fps).
function jlSaveWalk()
  local f = io.open(JL_WALK_FILE, "w")
  if not f then log("walk: could not write " .. JL_WALK_FILE); return false end
  for _, d in ipairs(JL_WALK_KEYS) do
    local tbl = Config[d.t]
    if tbl and type(tbl[d.k]) == "number" then f:write(("%s.%s=%.4f\n"):format(d.t, d.k, tbl[d.k])) end
  end
  for _, d in ipairs(JL_WALK_BOOLS) do
    local tbl = Config[d.t]
    if tbl then f:write(("%s.%s=%s\n"):format(d.t, d.k, tbl[d.k] and "1" or "0")) end
  end
  f:close()
  log("walk: tuning saved to " .. JL_WALK_FILE)
  return true
end

-- Re-apply saved overrides INTO the live Config. Called from onInit, straight after jlLoadSeats — the whole
-- point being that config.lua's baked defaults are the FLOOR, and whatever the tuner last saved wins.
-- Unknown keys in the file are ignored, so deleting a knob here can never break a load.
function jlLoadWalk()
  local f = io.open(JL_WALK_FILE, "r")
  if not f then return end
  local n = 0
  for line in f:lines() do
    local t, k, v = line:match("^(%w+)%.(%w+)=([%w%.%-]+)$")
    if t and Config[t] then
      local num = tonumber(v)
      for _, d in ipairs(JL_WALK_KEYS) do
        if d.t == t and d.k == k and num then Config[t][k] = num; n = n + 1 end
      end
      for _, d in ipairs(JL_WALK_BOOLS) do
        if d.t == t and d.k == k then Config[t][k] = (v == "1" or v == "true"); n = n + 1 end
      end
    end
  end
  f:close()
  if n > 0 then log(("walk: %d tuned value(s) restored from %s."):format(n, JL_WALK_FILE)) end
end

-- Throw the saved overrides away and go back to config.lua's baked values. Needs a reload to take effect
-- for real (Config is already patched in memory), so the button says so.
function jlResetWalk()
  local f = io.open(JL_WALK_FILE, "w")
  if f then f:close() end
  log("walk: tuning file cleared — reload the mod to get config.lua's defaults back.")
end

JL_SEATS_FILE = "jl_seats.txt"

-- Re-apply one persisted override INTO the live Config, mirroring tunerPrint's in-memory patch so
-- both the tuner and the normal scheduled sit path pick it up. Returns true if it landed on a seat.
function jlApplySeatOverride(key, seatIdx, x, y, z, yaw)
  local loc = Config.locations and Config.locations[key]
  if not (loc and loc.waypoints) then return false end
  local seats = {}   -- SIT waypoints in Config order (matches tunerSitWaypoints)
  for _, wp in ipairs(loc.waypoints) do if wp.pose == "sit" then seats[#seats + 1] = wp end end
  local wp = seats[seatIdx]
  if not wp then return false end
  wp.pos = { x, y, z }; wp.yaw = yaw
  if #seats <= 1 then loc.pos = { x, y, z }; loc.yaw = yaw end   -- single-seat venue: anchor tracks it
  return true
end

-- Write every committed override to disk. JL.tuner.saved is the in-memory map (id -> coords).
function jlSaveSeats()
  local f = io.open(JL_SEATS_FILE, "w")
  if not f then log("seats: could not write " .. JL_SEATS_FILE); return end
  local saved = JL.tuner.saved
  if saved then
    for _, s in pairs(saved) do
      f:write(("%s|%d|%.4f|%.4f|%.4f|%.2f\n"):format(s.key, s.seatIdx, s.x, s.y, s.z, s.yaw))
    end
  end
  f:close()
end

-- Record + persist the seat the tuner just committed, then flush the whole set to disk.
function jlPersistSeat(key, seatIdx, x, y, z, yaw)
  JL.tuner.saved = JL.tuner.saved or {}
  JL.tuner.saved[key .. "|" .. seatIdx] = { key = key, seatIdx = seatIdx, x = x, y = y, z = z, yaw = yaw }
  jlSaveSeats()
end

-- Read jl_seats.txt on load and re-apply each override into the live Config. Called from onInit.
function jlLoadSeats()
  JL.tuner.saved = JL.tuner.saved or {}
  local f = io.open(JL_SEATS_FILE, "r")
  if not f then return end
  local n = 0
  for line in f:lines() do
    local key, si, x, y, z, yaw =
      line:match("^([%w_]+)|(%d+)|(-?[%d.]+)|(-?[%d.]+)|(-?[%d.]+)|(-?[%d.]+)$")
    if key then
      si, x, y, z, yaw = tonumber(si), tonumber(x), tonumber(y), tonumber(z), tonumber(yaw)
      JL.tuner.saved[key .. "|" .. si] = { key = key, seatIdx = si, x = x, y = y, z = z, yaw = yaw }
      if jlApplySeatOverride(key, si, x, y, z, yaw) then n = n + 1 end
    end
  end
  f:close()
  if n > 0 then log(("seats: restored %d tuned seat(s) from %s"):format(n, JL_SEATS_FILE)) end
end

-- v0.95 single source of truth for the story mode. Persists the choice AND mirrors it to the
-- jl_mode_blaze quest fact so a (future) WolvenKit questphase edit on q005_heist can gate the
-- Heist-ending reroute on it (fact set => Blaze reroute fires; unset => vanilla story). Global
-- (not a top-level local) for the 200-locals cap.
function jlSetMode(m)
  JL.mode = (m == "blaze") and "blaze" or "quietlife"
  pcall(function() Game.GetQuestsSystem():SetFactStr("jl_mode_blaze", JL.mode == "blaze" and 1 or 0) end)
  jlSaveSettings()
  log("Story mode -> " .. JL.mode)
end

-- ===========================================================================
-- MOURNING SUPPRESSION (v0.97, "Quiet Life") — hold the "Jackie is dead" grief
-- facts down so a living Jackie doesn't collide with the ofrenda / grief calls.
-- DATA-DRIVEN + SAFE-BY-DEFAULT. Forcing quest facts out of order can soft-lock
-- (docs/research/main_quest_freeze_research.md), so this framework:
--   * ONLY runs in Quiet Life mode AND when JL.mourningSuppress is ON,
--   * NEVER writes the player's canon body-choice facts (JL_MOURNING_PROTECTED),
--   * offers a dry-run PREVIEW that only LOGS what it would set (verify first!),
--   * is reversible — we only pin narrative "on/active" facts to 0; flip the
--     toggle off and we stop asserting them.
-- This is the RUNTIME (CET) half of the A+B plan; the preferred long-term half is
-- baked .questphase edits gated on quietlife (see docs/mourning_suppression.md).
-- Fact NAMES below came from `strings` on the mourning binaries (docs/mounring_scenes/);
-- exact target VALUES stay marked CONFIRM until the .questphase JSONs are read.
-- Globals (no main-chunk `local`) for the 200-local cap.
-- ===========================================================================

-- The player's canon "where did Jackie's body go" decision. We suppress the
-- DOWNSTREAM grief, NEVER these — hard-blocked so a bad list row can't corrupt a save.
JL_MOURNING_PROTECTED = {
  q005_jackie_to_mama     = true,
  q005_jackie_to_hospital = true,
  q005_jackie_stay_notell = true,
}

-- The grief levers. Each row: name = quest fact · hold = value we pin (0 = keep
-- this content OFF) · note = what it gates. EDIT rows here once the JSONs land;
-- the machinery below needs no other change. Rows marked CONFIRM are best-guess
-- from the binaries and must be validated (JSON or in-game) before enabling.
JL_MOURNING_FACTS = {
  -- "Heroes" ofrenda side quest (sq018). CONFIRMED from sq018_01_mama_welles.questphase.json:
  -- the ofrenda phase gates on `sq018_active > 0`, so pinning it to 0 blocks the whole ofrenda
  -- without touching the body-choice facts. Heroes is a narrative dead-end (not a prerequisite).
  { name = "sq018_active", hold = 0, note = "Heroes/ofrenda arm flag; phase gates on >0 [VALUE CONFIRMED]" },
  -- Mama Welles grief holocalls. CONFIRMED from mama_welles_holocall.questphase.json: each call is
  -- REQUESTED by setting `holo_mama_welles_calls_v_*_activate = 1`, then fires while the shared
  -- `holo_setup_active < 1`. Pinning the request facts to 0 suppresses the calls. Mama only ever
  -- calls V about Jackie, so this is grief-exclusive. (NEVER pin `holo_setup_active` — that is the
  -- shared holocall system; zeroing it would break ALL phone calls in the game.)
  { name = "holo_mama_welles_calls_v_start_activate", hold = 0, note = "Mama grief call — request (start)" },
  { name = "holo_mama_welles_calls_v_end_activate",   hold = 0, note = "Mama grief call — request (end)"   },
  -- Misty grief holocalls (`holo_misty_calls_v_*_activate`). ENABLED per Antonia's call (v1.31).
  -- ⚠️ Misty also phones V for non-grief reasons (Evelyn, tarot) — these *_activate triggers are
  -- believed grief-specific but UNVERIFIED. TODO (TODO.md v1.31): confirm in-game no unrelated Misty
  -- call is silenced; if one is, re-comment these two lines.
  { name = "holo_misty_calls_v_start_activate", hold = 0, note = "Misty grief call — request (start) [verify not over-broad]" },
  { name = "holo_misty_calls_v_end_activate",   hold = 0, note = "Misty grief call — request (end) [verify not over-broad]"   },
  -- World-bark grief (Misty at Esoterica / Mama at El Coyote switch to mourning state) is Tier-3 /
  -- ambient — handled by scene edits, not runtime pins; a somber-but-alive Misty isn't lore-breaking.
}

-- KEEP EL COYOTE OPEN (v0.97b). Blocking sq018 (above) ALSO stops the ofrenda from ever
-- activating El Coyote Cojo as Mama's bar — the three facts below are what make it a live
-- location, and vanilla only ever sets them inside the Heroes flow we just blocked. So when
-- the player wants the bar without the grief quest, we force them ON (=1 by naming convention:
-- *_default_on / *_activated). Applied only when JL.keepBarOpen is set (separate menu toggle),
-- and only from inside jlMourningApply (which already requires Quiet Life + mourningSuppress).
-- ⚠️ POST-HEIST only: forcing coyote_community_activated=1 during the prologue could disturb the
-- early El Coyote scenes (Jackie's intro). Quiet-Life play is post-return, so that's the intent.
-- NOTE: this opens the bar/vendor; Mama's *ambient lines* may still read somber (that's Tier-3
-- scene-edit territory, see docs/mourning_suppression.md) — the location + vendor are the win here.
JL_BAR_KEEPOPEN = {
  { name = "mama_welles_default_on",     hold = 1, note = "Mama tends El Coyote (ambient dialogue on)" },
  { name = "elcoyote_barman_default_on", hold = 1, note = "El Coyote barman active" },
  { name = "coyote_community_activated", hold = 1, note = "El Coyote as a live community location" },
}

-- Apply one {name,hold,note} list. Skips rows already at target, refuses protected
-- (body-choice) facts. dryRun => only LOG. Returns count changed/would-change.
function jlApplyFactHolds(qs, list, dryRun)
  local n = 0
  for _, e in ipairs(list) do
    if JL_MOURNING_PROTECTED[e.name] then
      log("[Mourning] REFUSED protected body-choice fact " .. tostring(e.name) .. " (never touched)")
    else
      local cur; pcall(function() cur = qs:GetFactStr(e.name) end)
      if cur ~= e.hold then
        if dryRun then
          log(string.format("[Mourning] WOULD set %s: %s -> %d  (%s)", e.name, tostring(cur), e.hold, e.note or ""))
        else
          pcall(function() qs:SetFactStr(e.name, e.hold) end)
          log(string.format("[Mourning] set %s: %s -> %d  (%s)", e.name, tostring(cur), e.hold, e.note or ""))
        end
        n = n + 1
      end
    end
  end
  return n
end

-- Apply the mourning holds (or, dryRun=true, just LOG what it would do). Also forces the
-- bar-open facts when JL.keepBarOpen. Returns the number of facts it changed/would-change.
function jlMourningApply(dryRun)
  local blaze = (JL.mode == "blaze")
  -- Quiet Life pins the grief holds only when the player opted in (the tick gates on JL.mourningSuppress).
  -- BLAZE always suppresses grief + the ofrenda (Blaze rewrites the ending so none of it fits — Antonia
  -- 2026-07-08) AND forces El Coyote open, since the Blaze finale deposits V at the bar.
  if not blaze and JL.mode ~= "quietlife" then return 0 end
  local qs; pcall(function() qs = Game.GetQuestsSystem() end)
  if not qs then return 0 end
  local n = jlApplyFactHolds(qs, JL_MOURNING_FACTS, dryRun)
  if blaze or JL.keepBarOpen then n = n + jlApplyFactHolds(qs, JL_BAR_KEEPOPEN, dryRun) end
  return n
end

-- Short menu status line.
function jlMourningStatus()
  if JL.mode ~= "quietlife" then return "n/a — Blaze mode auto-suppresses grief" end
  if not JL.mourningSuppress then return "OFF" end
  local active = 0
  for _, e in ipairs(JL_MOURNING_FACTS) do if not JL_MOURNING_PROTECTED[e.name] then active = active + 1 end end
  return "ON — holding " .. tostring(active) .. " grief fact(s)" .. (JL.keepBarOpen and " + El Coyote forced open" or "")
end

-- Force-despawns EVERY Jackie (orphans included), wipes ALL transient state machines, then lets
-- the next scheduleTick re-place a clean idle Jackie at his scheduled spot. Fired from the Esc ->
-- Settings recovery button while the game is PAUSED (onUpdate frozen), so re-placement is left to
-- the first unpaused tick (we just prime JL.timer to fire it ASAP).
function hardReset()
  -- get him out of any sit/lean workspot first so the despawn can't strand a posed body
  pcall(function()
    local ws = Game.GetWorkspotSystem()
    if ws then
      if JL.idle.spawn   and JL.idle.spawn.handle   then ws:StopInDevice(JL.idle.spawn.handle)   end
      if JL.summon.spawn and JL.summon.spawn.handle then ws:StopInDevice(JL.summon.spawn.handle) end
    end
  end)
  pcall(dismissAllJackies)   -- AMM-wide despawn + summon/idle/arrival/leaving/vehicle reset (clears the companion fact)
  -- wipe the newer idle/dinner/secret/call/branch state dismissAllJackies doesn't cover
  JL.idle.placed, JL.idle.phase, JL.idle.curIdx, JL.idle.tgtIdx = false, nil, nil, nil
  JL.idle.leaving, JL.idle.leaveTarget, JL.idle.leaveDeadline, JL.idle.leaveReissue = false, nil, 0, 0
  JL.idle.posed, JL.idle.pendingPose, JL.idle.pendingSit = false, nil, nil
  JL.idle.collisionOff, JL.idle.collisionRestoreAt = false, nil
  JL.dinner.phase, JL.dinner.dest, JL.dinner.mappinId = nil, nil, nil
  JL.secret.decided, JL.secret.active = false, false
  JL.call.ringingAt, JL.call.hangupAt, JL.call.hangupAction = nil, nil, nil
  JL.leaving.subClearAt = nil
  JL.persist.gapSince, JL.persist.lastRespawn = nil, nil   -- v0.72: don't immediately re-spawn after a manual reset
  -- release any open conversation so the UI can't be stuck mid-dialogue
  pcall(hideSubtitle)
  if Branch then Branch.open, Branch.busy = false, false end
  JL.timer = Config.scheduleCheckInterval or 0   -- fire scheduleTick on the very next (unpaused) tick
  JL.ui.status = "Go Home Jackie: reset done. He'll return to his schedule shortly."
  log("Hard reset: every Jackie despawned + state wiped; schedule will re-place a clean one.")
end

-- ===========================================================================
-- COMPANION PERSISTENCE (v0.72) — see Config.persist / List_of_companion_issues Session 1.
-- The "is companion" intent is stored as the per-save game fact jackielives_companion (mirrors
-- retrieval.lua's stage fact), so it survives save/load and is automatically per-save-slot correct.
-- Globals (no `local`) to respect the 200-local cap.
-- ===========================================================================
JL_COMPANION_FACT = "jackielives_companion"

function setCompanionFlag(on)
  pcall(function() Game.GetQuestsSystem():SetFactStr(JL_COMPANION_FACT, on and 1 or 0) end)
end

function companionFlagSet()
  local v; local ok = pcall(function() v = Game.GetQuestsSystem():GetFactStr(JL_COMPANION_FACT) end)
  return ok and v == 1
end

-- ===========================================================================
-- BIKE RETURN (v0.84) — one-time reunion beat: on his first call after he's back,
-- Jackie asks for his Arch, and V hands it over. Giving it back = removing Jackie's
-- Arch from V's garage (it's HIS ride again). Persisted via Config.bikeReturn.fact so
-- it only happens once. Globals (no main-chunk `local`) to respect the 200-local cap.
-- ===========================================================================
function jlBikeReturned()
  local f = (Config.bikeReturn and Config.bikeReturn.fact) or "jackielives_bikeback"
  local v; pcall(function() v = Game.GetQuestsSystem():GetFactStr(f) end)
  return type(v) == "number" and v >= 1
end

-- Remove Jackie's Arch from V's owned/garage vehicles. Reversible (re-enable to restore).
-- `markDone` false = just remove without setting the fact (used by the debug button).
function jlReturnJackiesBike(markDone)
  local B   = Config.bikeReturn or {}
  local rec = B.bikeRecord or "Vehicle.v_sportbike2_arch_jackie_player"
  local ok  = pcall(function()
    Game.GetVehicleSystem():EnablePlayerVehicle(rec, false, true)   -- (id, enable=false, updateGarage)
  end)
  -- best-effort: if this build ever has a literal bike-"key" inventory item, pull it too
  -- (vanilla 2.x has none, so this no-ops unless Config.bikeReturn.keyItem is set)
  if B.keyItem then
    pcall(function()
      local ts, p = Game.GetTransactionSystem(), Game.GetPlayer()
      if ts and p then ts:RemoveItem(p, ItemID.FromTDBID(TweakDBID.new(B.keyItem)), 1) end
    end)
  end
  if markDone ~= false then
    pcall(function() Game.GetQuestsSystem():SetFactStr((B.fact or "jackielives_bikeback"), 1) end)
  end
  log("Bike return: removed '" .. rec .. "' from V's garage (ok=" .. tostring(ok) .. ").")
  return ok
end

-- Debug helper: give the Arch back to V (undo), for re-testing the reunion beat.
function jlRestoreJackiesBike()
  local B   = Config.bikeReturn or {}
  local rec = B.bikeRecord or "Vehicle.v_sportbike2_arch_jackie_player"
  pcall(function() Game.GetVehicleSystem():EnablePlayerVehicle(rec, true, true) end)
  pcall(function() Game.GetQuestsSystem():SetFactStr((B.fact or "jackielives_bikeback"), 0) end)
  log("Bike return: RESTORED '" .. rec .. "' to V (reset the one-time flag).")
end

-- ===========================================================================
-- BIKE CRUISE (v0.85) — companion Jackie trails V on his Arch while V rides a BIKE.
-- AIVehicleFollowCommand + useKinematic (the AMM bike-follow recipe proven in JackieVehicleTest).
-- Globals (no main-chunk `local` -> 200-cap safe); reuses the local helpers spawnDynEntity /
-- mountAsDriver / unmountDriver / deleteEntityById / promoteToCompanion / playerPos / yawToward /
-- snapToNavmesh, all defined earlier in this chunk. The keep-close / catch-up / abreast ticks are
-- gated on jlCruise.active so they don't drag him off the bike. Ghost-trail was NOT shipped.
-- ===========================================================================
jlCruise = { active = false, bikeId = nil, bikeHandle = nil, mountAt = nil, lastReissue = -999 }

function jlPlayerVehicleObj()
  local qm; pcall(function() qm = Game.GetPlayer():GetQuickSlotsManager() end)
  local veh; if qm then pcall(function() veh = qm:GetVehicleObject() end) end
  return veh
end

function jlIsBikeVeh(veh)
  if not veh then return false end
  local cn = ""; pcall(function() cn = tostring(veh:GetClassName()) end)
  cn = cn:lower()
  return (cn:find("bike") ~= nil) or (cn:find("motorcycle") ~= nil)
end

-- True only during a real locked cutscene (PlayerStateMachine SceneTier >= 4 = FPPCinematic/Cinematic).
-- NO false positives on holocalls / dialogue / vendors / braindance (those stay tier 1-3). Verified
-- against psiberx/cp2077-cet-kit GameUI (the base AMM + most companion mods use). Global -> cap-safe.
function jlInCutscene()
  local inCut = false
  pcall(function()
    local defs  = Game.GetAllBlackboardDefs()
    local psmBB = Game.GetBlackboardSystem():Get(defs.PlayerStateMachine)
    if not psmBB then return end
    local tier = psmBB:GetInt(defs.PlayerStateMachine.SceneTier)   -- 1=gameplay ... 4/5=cinematic
    inCut = (tier >= 4)
  end)
  return inCut
end

-- (Re)issue the follow command onto Jackie's Arch so it trails V's bike.
function jlCruiseFollow()
  local bh, p = jlCruise.bikeHandle, Game.GetPlayer()
  if not (bh and p) then return end
  local C = Config.cruise or {}
  pcall(function() bh:TurnVehicleOn(true) end)
  pcall(function()
    local cmd = NewObject('handle:AIVehicleFollowCommand')
    cmd.target = p                                   -- V's PLAYER object (tracks his bike)
    cmd.distanceMin = C.followDistMin or 6.0
    cmd.distanceMax = C.followDistMax or 10.0
    cmd.stopWhenTargetReached = false
    cmd.useTraffic = false
    cmd.useKinematic = true                          -- bike-safe: no wobble / topple
    pcall(function() cmd.needDriver = true end)
    cmd = cmd:Copy()
    local evt = NewObject('handle:AINPCCommandEvent'); evt.command = cmd
    bh:QueueEvent(evt)                               -- queue to the VEHICLE, not the driver
  end)
  jlCruise.lastReissue = JL.clock or 0
end

function jlCruiseStart()
  if jlCruise.active then return end
  local jh = JL.summon and JL.summon.spawn and JL.summon.spawn.handle
  if not jh then return end
  local pp = playerPos(); if not pp then return end
  local C = Config.cruise or {}
  local behind = C.spawnBehind or 8.0
  local fwd; pcall(function() fwd = Game.GetPlayer():GetWorldForward() end)
  local pt = fwd and Vector4.new(pp.x - fwd.x * behind, pp.y - fwd.y * behind, pp.z, 1.0) or pp
  pt = snapToNavmesh(pt) or pt
  local bid = spawnDynEntity(C.bikeRecord or "Vehicle.v_sportbike2_arch_jackie_player", pt,
                             yawToward(pt, pp), "JackieLives_cruisebike", C.bikeAppearance or "default")
  if not bid then log("Cruise: Arch spawn failed."); return end
  jlCruise.active, jlCruise.bikeId, jlCruise.bikeHandle = true, bid, nil
  jlCruise.mountAt, jlCruise.lastReissue = (JL.clock or 0) + 1.2, -999
  log("Cruise: spawning Jackie's Arch to trail V.")
end

function jlCruiseStop()
  if not jlCruise.active then return end
  local jh = JL.summon and JL.summon.spawn and JL.summon.spawn.handle
  if jh and unmountDriver then pcall(function() unmountDriver(jh, jlCruise.bikeHandle) end) end
  if jlCruise.bikeId then pcall(function() deleteEntityById(jlCruise.bikeId) end) end
  if jlCruise.bikePhysArmed then                      -- v1.41: release our ref on the global knock-off flat
    jlCruise.bikePhysArmed = false
    jlBikeKnockOff(false)
  end
  jlCruise.active, jlCruise.bikeId, jlCruise.bikeHandle, jlCruise.mountAt = false, nil, nil, nil
  jlCruise.rightAt, jlCruise.rightCheckAt = nil, nil
  pcall(promoteToCompanion)                          -- resume normal on-foot follow
  log("Cruise: ended -> Jackie back on foot.")
end

-- v1.41 ANTI-CRASH #3 — the cruise safety net. Even with the knock-off threshold raised, a bad enough
-- impact (or `IsBeingDragged()`, which ignores the threshold entirely) can still put the Arch on its
-- side and throw Jackie off. Detect that, stand the bike back up behind V, wake its physics, re-mount
-- him and re-issue the follow. Rate-limited so a bike wedged against a wall can't teleport-thrash.
-- GLOBAL -> 200-cap safe.
function jlCruiseRightingTick()
  local B = Config.bikePhysics or {}
  if not (B.enabled and B.rightIfFlipped) then return end
  if not (jlCruise.active and jlCruise.bikeHandle) or jlCruise.mountAt then return end
  local now = JL.clock or 0
  if now < (jlCruise.rightCheckAt or 0) then return end
  jlCruise.rightCheckAt = now + (B.rightCheck or 1.0)

  local bh = jlCruise.bikeHandle
  local jh = JL.summon and JL.summon.spawn and JL.summon.spawn.handle
  if not jh then return end

  -- toppled? prefer the engine's own answer, fall back to the up-vector dot the engine uses internally
  -- (ComputeIsVehicleUpsideDown: Dot(GetWorldUp(), Vector4.UP()) < 0).
  local flipped
  pcall(function() flipped = bh:IsFlippedOver() end)
  if flipped == nil then
    pcall(function() flipped = (bh:GetWorldUp().z < (B.uprightDot or 0.4)) end)
  end
  -- knocked off? he's cruising but no longer in the saddle ('NoDriver' after a ForceRagdollEvent)
  local thrown = (isMounted and not isMounted(jh)) or false
  if not (flipped or thrown) then return end
  if now < (jlCruise.rightAt or 0) then return end        -- cooling down from the last recovery
  jlCruise.rightAt = now + (B.rightCooldown or 4.0)

  local pp = playerPos(); if not pp then return end
  local fwd; pcall(function() fwd = Game.GetPlayer():GetWorldForward() end)
  local behind = (Config.cruise or {}).spawnBehind or 8.0
  local pt = fwd and Vector4.new(pp.x - fwd.x * behind, pp.y - fwd.y * behind, pp.z, 1.0) or pp
  pt = snapToNavmesh(pt) or pt
  pcall(function()
    Game.GetTeleportationFacility():Teleport(bh, pt, EulerAngles.new(0, 0, yawToward(pt, pp) or 0))
  end)
  pcall(function() bh:PhysicsWakeUp() end)
  pcall(function() bh:TurnVehicleOn(true) end)
  if thrown and mountAsDriver then pcall(function() mountAsDriver(jh, bh) end) end
  jlCruise.lastReissue = -999                             -- force jlCruiseFollow to re-command next tick
  log(("Cruise: bike recovered (flipped=%s thrown=%s) -> righted behind V + re-issued follow.")
      :format(tostring(flipped), tostring(thrown)))
end

function jlCruiseTick()
  local C = Config.cruise or {}
  if C.enabled == false then if jlCruise.active then jlCruiseStop() end; return end
  local companion = JL.summon and JL.summon.active and JL.summon.spawn and JL.summon.spawn.handle
  -- only cruise a SETTLED companion (not mid-arrival / dinner / walk-off)
  local settled = companion and JL.summon.companionSet
    and not (JL.dinner.phase or JL.leaving.phase or (JL.varrival and JL.varrival.phase))
    and not jlInCutscene()   -- v0.92: never spawn/keep his Arch during a cutscene
  local onBike = settled and jlIsBikeVeh(jlPlayerVehicleObj())
  if onBike and not jlCruise.active then jlCruiseStart()
  elseif jlCruise.active and not onBike then jlCruiseStop() end
  if not jlCruise.active then return end
  if jlCruise.bikeId and not jlCruise.bikeHandle then
    pcall(function() jlCruise.bikeHandle = Game.FindEntityByID(jlCruise.bikeId) end)
    -- v1.41: Arch exists -> raise the NPC knock-off threshold + make it invulnerable for the ride.
    if jlCruise.bikeHandle and not jlCruise.bikePhysArmed then
      jlCruise.bikePhysArmed = true
      jlBikeKnockOff(true)
      jlBikeGodMode(jlCruise.bikeHandle)
    end
  end
  if jlCruise.mountAt and (JL.clock or 0) >= jlCruise.mountAt and jlCruise.bikeHandle then
    local jh = JL.summon.spawn.handle
    if jh and mountAsDriver then pcall(function() mountAsDriver(jh, jlCruise.bikeHandle) end) end
    jlCruise.mountAt, jlCruise.lastReissue = nil, -999
    log("Cruise: Jackie mounted his Arch; following V.")
  end
  if not jlCruise.mountAt and jlCruise.bikeHandle
     and ((JL.clock or 0) - (jlCruise.lastReissue or -999)) >= (C.reissue or 5.0) then
    jlCruiseFollow()
  end
  pcall(jlCruiseRightingTick)   -- v1.41: stand the bike back up if it topples / he gets thrown
end

-- v0.76 DEBUG: dump Jackie's full runtime state to the console (bound to a CET button + called at the
-- start/end of the dismiss walk-away so we can see WHY he vanishes). Global (no main-chunk local -> cap safe).
-- Reports, for each system's entity: handle validity, world position, live distance to V, AMM companion
-- caching + whether an AI role is attached — so a bogus position read or a stale handle is obvious.
function jlDumpState(tag)
  local function fmt(v) if not v then return "nil" end
    local ok, s = pcall(function() return string.format("(%.1f,%.1f,%.1f)", v.x, v.y, v.z) end)
    return ok and s or "?" end
  local pp = playerPos()
  local function info(sp)
    if not sp then return "spawn=nil" end
    if not sp.handle then return "spawn set, handle=NIL id=" .. tostring(sp.id) end
    local jp; pcall(function() jp = sp.handle:GetWorldPosition() end)
    local d = (pp and jp) and dist3(pp, jp) or nil
    local comp, role
    pcall(function() comp = sp.handle.isPlayerCompanionCached end)
    pcall(function() role = (sp.handle:GetAIControllerComponent():GetAIRole() ~= nil) end)
    return string.format("handle=ok pos=%s dist=%s companionCached=%s hasRole=%s",
      fmt(jp), d and string.format("%.1f", d) or "nil", tostring(comp), tostring(role))
  end
  log("==== JACKIE STATE [" .. tostring(tag) .. "] ====")
  log("V=" .. fmt(pp))
  log("summon: active=" .. tostring(JL.summon.active) .. " companionSet=" .. tostring(JL.summon.companionSet)
      .. " walkIn=" .. tostring(JL.summon.walkIn) .. " | " .. info(JL.summon.spawn))
  log("idle: locKey=" .. tostring(JL.idle.locationKey) .. " | " .. info(JL.idle.spawn))
  log("phases: varrival=" .. tostring(JL.varrival.phase) .. " leaving=" .. tostring(JL.leaving.phase)
      .. " dinner=" .. tostring(JL.dinner.phase))
  local flag; pcall(function() flag = companionFlagSet() end)
  log("saveFlag=" .. tostring(flag) .. " catchUp=" .. tostring(Config.catchUp and Config.catchUp.enabled)
      .. " follow=" .. tostring(Config.follow and Config.follow.enabled)
      .. " persist=" .. tostring(Config.persist and Config.persist.enabled))
  log("=====================================")
end

-- Bring Jackie back at V's side (the same instant AMM companion spawn `summonJackie` uses). Clears
-- any stale/culled spawn first so we never leak or double up. The onUpdate promote block applies the
-- follower role next frame; armCompanionTimer re-arms the duration clock fresh.
function respawnCompanionAtV()
  -- v1.43: capture his outfit BEFORE the despawn clears the spawn, and bring him back wearing it. A bare
  -- ammSpawn(1) here reverted him to Config.defaultAppearance — the Blaze heist Jackie kept losing his
  -- dirty suit at Konpeki Plaza, because that's where his body gets culled and this path fires.
  local app = jlCompanionAppearance()
  if JL.summon.spawn then ammDespawn(JL.summon.spawn) end
  JL.summon.spawn, JL.summon.active, JL.summon.companionSet, JL.summon.walkIn = nil, false, false, false
  local spawn, err = ammSpawn(1, app)
  if not spawn then log("Persist: respawn at V FAILED (" .. tostring(err) .. ") — will retry."); return false end
  JL.summon.spawn, JL.summon.active, JL.summon.companionSet = spawn, true, false
  -- v0.82: arm the settle window. He's freshly popped in at V (AMM drops him ~1 m from her); hide him +
  -- drop collision for a beat so he doesn't visibly POP or clip into a wall, then settleTick reveals him +
  -- restores collision by clock. handle may be nil this frame (DES resolves later) — settleTick re-hides
  -- once it appears, so the reveal is always by TIME, never a one-shot that can miss the async handle.
  local S = Config.respawnSettle or {}
  if S.enabled ~= false then
    local now = JL.clock or 0
    JL.settle.hideUntil    = now + (S.hideSeconds or 2.0)
    JL.settle.collideUntil = now + (S.collideSeconds or 4.0)
    JL.settle.handle       = nil   -- resolved live in settleTick (spawn.handle isn't ready yet)
    -- v1.40: AMM drops the fresh body at its OWN spot (often the wall BEHIND V at a fast-travel point).
    -- Arm a one-shot reposition to V's front/side, done by settleTick while he's still hidden. Clearing the
    -- retry timers so it re-evaluates from scratch. Toggle with Config.catchUp.frontSideRespawn.
    JL.settle.reposePending = (Config.catchUp and Config.catchUp.frontSideRespawn ~= false)
    JL.settle.reposeAt      = nil
    JL.settle.reposeLast    = nil
  end
  log("Persist: companion flag set but Jackie was absent -> respawned him at V.")
  return true
end

-- v0.82 SETTLE TICK. During the brief window after a respawn-at-V, keep the fresh Jackie INVISIBLE (so V
-- doesn't see him pop in beside her) and NON-COLLIDING (so he can't get shoved out of a wall/geometry he
-- spawned against). Both are re-asserted every frame against the live handle (which resolves a frame or
-- two after the spawn), then lifted by clock: reveal at hideUntil, re-collide at collideUntil. Hands-off
-- once the window closes. Mirrors the arrival sequence's own hide-until-placed trick (setVisible/setNpcCollision).
-- GLOBAL (not a top-level local): init.lua is at Lua's 200-local hard cap — see companionPersistTick etc.
function settleTick()
  local s = JL.settle
  if not (s and (s.hideUntil or s.collideUntil or s.reposePending)) then return end
  local now = JL.clock or 0
  local h = JL.summon.spawn and JL.summon.spawn.handle
  -- v1.40 FRONT-SIDE REPOSITION. While he's still hidden after a respawn-at-V, move him off AMM's drop spot
  -- (often the wall behind V at a fast-travel point) to a point AHEAD/beside V (frontSideArrivalPoint reuses
  -- the walk-abreast angles). Wait ~0.15 s after the handle resolves so his AI can accept an AITeleportCommand,
  -- then re-issue at most every ~0.4 s until he's within ~4 m of V or the hide window ends (so the reveal shows
  -- him at V's side). aiTeleport is the same puppet-relocate the catch-up teleport + arrival flow already use.
  if s.reposePending and h then
    s.reposeAt = s.reposeAt or (now + 0.15)
    if now >= s.reposeAt and (now - (s.reposeLast or -1e9)) >= 0.4 then
      local jp; pcall(function() jp = h:GetWorldPosition() end)
      local pp = playerPos()
      if jp and pp and dist3(pp, jp) <= 4.0 then
        s.reposePending = nil                 -- already beside V -> done
      elseif jp then
        local pt = frontSideArrivalPoint((Config.catchUp and Config.catchUp.placeDistance) or 3.0, jp)
        if pt then
          local yaw = 0.0
          pcall(function() local f = Game.GetPlayer():GetWorldForward(); yaw = math.deg(math.atan2(f.y, f.x)) end)
          aiTeleport(h, pt, yaw, false)
          log("Settle: repositioned respawned Jackie to V's front/side (front-side recovery).")
        end
        s.reposeLast = now
      end
    end
    if s.hideUntil and now >= s.hideUntil then s.reposePending = nil end  -- window's up -> stop trying
  end
  -- still hiding? keep him invisible + collision-off (re-assert each frame; handle may have just resolved).
  if s.hideUntil and now < s.hideUntil then
    if h then setVisible(h, false) end
  elseif s.hideUntil then
    -- v1.47: only close the window once we ACTUALLY revealed him. This used to clear `hideUntil`
    -- unconditionally, so if the handle happened to be nil on the exact reveal frame (a respawn swapped
    -- JL.summon.spawn under us) the reveal was skipped forever and Jackie stayed INVISIBLE — present,
    -- companion, unseeable. Keep retrying until a handle shows up, with a hard cap so we can't hide him
    -- for the rest of the session if his body never comes back.
    if h then
      setVisible(h, true)                 -- window's up -> reveal him where he settled
      s.hideUntil, s.hideGiveUpAt = nil, nil
    else
      s.hideGiveUpAt = s.hideGiveUpAt or (now + 5.0)
      if now >= s.hideGiveUpAt then
        log("Settle: reveal window expired with no handle — dropping the hide (no body to reveal).")
        s.hideUntil, s.hideGiveUpAt = nil, nil
      end
    end
  end
  if s.collideUntil and now < s.collideUntil then
    if h then setNpcCollision(h, false) end
  elseif s.collideUntil then
    if h then setNpcCollision(h, true) end  -- restore collision (a follower must always collide)
    s.collideUntil = nil
  end
end

-- v1.52 SESSION RESET — called by Session.tick() the frame a new session begins (game load, load-from-
-- save, new game). Every entity handle we hold belongs to the world that just went away.
--
-- ⚠️ DROP the references. Do NOT despawn, do NOT read a position, do NOT null-check by dereferencing.
-- Those handles point at freed native memory; touching one is the crash we are here to prevent. AMM
-- rebuilds its own spawn table on load, so its bodies are its problem, not ours — there is nothing for
-- us to clean up, only references for us to forget.
function jlResetSessionState(id, why)
  JL.summon   = { spawn = nil, active = false, companionSet = false, walkIn = false }
  JL.idle     = { spawn = nil, locationKey = nil, placed = false, phase = nil, curIdx = nil, tgtIdx = nil,
                  spawnedAt = 0, dwellUntil = 0, arriveBy = 0, lastReissue = 0,
                  leaving = false, leaveTarget = nil, leaveDeadline = 0, leaveReissue = 0,
                  collisionOff = false }
  JL.settle   = { hideUntil = nil, collideUntil = nil, handle = nil,
                  reposePending = nil, reposeAt = nil, reposeLast = nil }
  JL.smile    = { until_ = 0, nextRoll = 0, nextApply = 0, cooldownUntil = 0, handle = nil,
                  reunionActive = false, reunionForceUntil = 0, reunionSafety = 0, idle = nil }
  JL.varrival = { at = nil, phase = nil, pt = nil, bikeId = nil, bikeHandle = nil,
                  placeAt = nil, driveAt = nil, sprintAt = nil, lastReissue = 0, deadline = nil, driveCmd = nil }
  JL.arrival  = { at = nil, phase = nil, pt = nil, placeAt = nil, moveAt = nil, deadline = nil, lastReissue = 0 }
  JL.leaving  = { phase = nil, deadline = nil, lastReissue = 0 }
  JL.catchUp  = { farSince = nil, lastAt = nil, teleTries = nil }
  JL.follow   = { lastAt = nil }
  JL.abreast  = { lastAt = nil }
  JL.persist  = { gapSince = nil, lastRespawn = nil, worldReadyAt = nil }
  -- dinner: clear only the in-flight outing, keep the cross-session offer schedule
  if JL.dinner then
    JL.dinner.phase, JL.dinner.dest, JL.dinner.destName, JL.dinner.destYaw = nil, nil, nil, nil
    JL.dinner.mappinId, JL.dinner.satAt, JL.dinner.seatDeadline, JL.dinner.sitFireAt = nil, nil, nil, nil
    JL.dinner.collisionOff = false
  end
  log(("[SESSION] #%d state reset (%s) — all entity handles dropped."):format(id or -1, tostring(why)))
end

-- Per-frame guard: keep the saved companion fact in sync with reality, and if the save says Jackie
-- should be with V but his body is gone (fresh load wiped Lua state, or a load-screen fast-travel
-- culled him), bring him back. Reuses JL.clock for all timing (no dt needed).
function companionPersistTick()
  local P = Config.persist or {}
  if P.enabled == false then return end
  if JL.blazeFinale then return end   -- v1.47: the finale OWNS Jackie's body while it spawns/places him.
                                      -- Otherwise this sees "companion set, handle not resolved yet",
                                      -- despawns the finale's fresh Jackie and respawns its own — which
                                      -- also arms the settle HIDE window over the finale scene.
  if not Retrieval.isUnlocked() then return end                 -- mod still gated -> no companion to keep

  -- v0.84 CRASH FIX: the startup grace MUST be measured from when the player entered the world, NOT
  -- from JL.clock (time since onInit). A mid-session load-from-save does NOT re-run onInit, so JL.clock
  -- is already huge and the old `JL.clock < startupGrace` gate was skipped instantly -> we respawned into
  -- a still-streaming world = the load crash. Now: while the player is absent (load screen / fast-travel)
  -- we clear worldReadyAt; the frame he reappears we stamp it, then require startupGrace of settled,
  -- in-world time before touching AMM. This resets correctly on EVERY load and district-scale fast-travel.
  local now = JL.clock or 0
  if not playerPos() then                                       -- player not in-world (loading / FT screen)
    JL.persist.worldReadyAt = nil; JL.persist.gapSince = nil; return
  end
  JL.persist.worldReadyAt = JL.persist.worldReadyAt or now
  if (now - JL.persist.worldReadyAt) < (P.startupGrace or 8.0) then return end  -- let the world finish streaming

  -- Is a LIVE, settled companion actually present right now?
  -- v1.52: Session.stale() FIRST. A spawn record from a previous session holds a dead native pointer;
  -- the GetWorldPosition() below would be a use-after-free. Drop it without touching it.
  local live = false
  if JL.summon.spawn and Session.stale(JL.summon.spawn) then
    log("[SESSION] persist: dropping stale spawn record from a previous session (not dereferenced).")
    JL.summon.spawn, JL.summon.active, JL.summon.companionSet = nil, false, false
  end
  if JL.summon.active and JL.summon.companionSet and JL.summon.spawn and JL.summon.spawn.handle then
    local jp; pcall(function() jp = JL.summon.spawn.handle:GetWorldPosition() end)
    live = (jp ~= nil)
  end

  if live then
    -- v1.52 CROSS-SAVE LEAK FIX: only self-heal the fact if THIS save already claimed him when the
    -- session began. Previously a stale handle that still happened to resolve made `live` true, and
    -- this line wrote the companion fact into a freshly-loaded save that never had a Jackie — a
    -- one-way ratchet that made him "come with" into other saves. Never create the fact, only repair it.
    if not companionFlagSet() then
      if Session.companionAtStart then
        setCompanionFlag(true)                                  -- self-heal: this save DID claim him
      else
        log("[SESSION] persist: live companion but this save never claimed him — NOT writing the fact.")
      end
    end
    JL.persist.gapSince = nil
    return
  end

  -- No live companion. If the save doesn't claim him, there's nothing to restore.
  if not companionFlagSet() then JL.persist.gapSince = nil; return end

  -- He SHOULD be here. Don't fight a state machine that's already placing/removing him.
  if (JL.varrival and JL.varrival.phase) or JL.leaving.phase or JL.dinner.phase or JL.summon.walkIn then
    JL.persist.gapSince = nil; return
  end

  -- v0.84 CRASH FIX: don't spawn until AMM has re-initialised post-load and Jackie's record resolves.
  -- After a load AMM re-inits a beat later than us; calling its Spawn path before it's ready was the other
  -- half of the load crash. Bail (and reset the gap timer) until both are live, then spawn is the same
  -- proven path the confirmed catch-up respawn (bug 2f) already uses safely.
  local amm = getAMM()
  if not (amm and amm.Spawn and amm.Spawn.NewSpawn) then JL.persist.gapSince = nil; return end
  if not resolveJackieRecord() then JL.persist.gapSince = nil; return end

  -- Require the gap to persist a beat (rides out a momentary stream/handle hiccup), then respawn
  -- on a cooldown (which also covers the few frames a fresh spawn needs to resolve + promote).
  JL.persist.gapSince = JL.persist.gapSince or now
  if (now - JL.persist.gapSince) < (P.gapSustain or 1.5) then return end
  if (now - (JL.persist.lastRespawn or -1e9)) < (P.cooldown or 5.0) then return end
  JL.persist.gapSince, JL.persist.lastRespawn = nil, now
  respawnCompanionAtV()
end

registerForEvent("onInit", function()
  -- v1.52: ROTATE, don't truncate. The old `io.open("...","w")` here destroyed the log of the run that
  -- crashed, on the very next launch — i.e. exactly when you went looking for it. The crashing run now
  -- survives as jackie_debug.log.prev; read its tail for the last [MARK] before the process died.
  Session.bind{ log = log, onNewSession = jlResetSessionState }
  Session.rotateLog()
  Session.header(JL.mode)
  pcall(function() math.randomseed((os.time and os.time() or 0)) end)  -- v0.36: random day-bag shuffle
  getAMM()
  setupInteractHook()   -- v0.15: native F (Interact) triggers Talk-to-Jackie, no binding
  pcall(setupCallHijack)   -- v0.30: player phone-calls to Jackie route into our flow
  pcall(jlLoadSettings)    -- v0.51: restore persisted Esc-menu toggles (husbando / disableVehicleArrivals)
  pcall(jlDefaultHermano)  -- v1.54: Hermano for everyone unless the player explicitly flipped the switch
  pcall(jlLoadSeats)       -- v1.1: restore tuned sit coords into Config so they survive a reload (old-S4 fix)
  pcall(jlLoadWalk)        -- v1.57: same for the walk/loiter tuner's knobs (they used to die on every reload)
  -- retrieval questline: logger + v1.2 relationship-mode selector (Husbando/Hermano recovery text)
  -- + v1.54 showObjective -> the native banner (with its UI sound), so the quest's steps actually
  -- tell the player what to do next ("Find Jackie...", "Call Jackie", "Wait for Jackie").
  pcall(function()
    Retrieval.bind{
      log = log, isHermano = jlHermano, showObjective = showOnscreenMsg,
      -- v1.55: the SAME record jlReturnJackiesBike disables, so the Reverend Flash restore re-enables exactly the
      -- bike the reunion took away — they can't drift apart.
      bikeRecord = (Config.bikeReturn and Config.bikeReturn.bikeRecord) or nil,
    }
    -- v1.55: the Reverend Flash easter egg is authored in config.lua (with all the other content), but it RUNS in
    -- retrieval.lua, which owns the proximity/popup machinery and does not require config.lua. Hand it over.
    Retrieval.Config.revflash = Config.revflash
  end)
  -- v0.96 BLAZE: inject every game-touching primitive the set-piece needs, built from the
  -- proven helpers in this file. blaze.lua stays pure Lua; ONLY this table calls Game.*.
  pcall(function()
    Blaze.bind{
      log = log,
      spawnDyn = function(rec, p, yaw, tag)
        return spawnDynEntity(rec, Vector4.new(p.x, p.y, p.z, 1.0), yaw, tag)   -- reuse the bike/Jackie DES spawn
      end,
      findEntity = function(id) local h; pcall(function() h = Game.FindEntityByID(id) end); return h end,
      teleport = function(h, p, yaw)
        pcall(function()
          local tf = Game.GetTeleportationFacility()
          if tf then tf:Teleport(h, Vector4.new(p.x, p.y, p.z, 1.0), EulerAngles.new(0.0, 0.0, yaw or 0.0)) end
        end)
      end,
      setHostile = function(h)
        pcall(function()
          local pl = Game.GetPlayer()
          if pl and h and h.GetAttitudeAgent then
            h:GetAttitudeAgent():SetAttitudeTowards(pl:GetAttitudeAgent(), EAIAttitude.AIA_Hostile)
            -- v1.0 BLAZE: make the boss MUTUALLY hostile to companion Jackie too. Setting the enemy
            -- hostile only toward V left Jackie a neutral bystander (he'd follow but never swing).
            -- With mutual hostility his AMM follower AI registers the boss as a threat and engages.
            local jh = JL.summon and JL.summon.spawn and JL.summon.spawn.handle
            if jh and jh.GetAttitudeAgent then
              h:GetAttitudeAgent():SetAttitudeTowards(jh:GetAttitudeAgent(), EAIAttitude.AIA_Hostile)
              jh:GetAttitudeAgent():SetAttitudeTowards(h:GetAttitudeAgent(), EAIAttitude.AIA_Hostile)
            end
          end
        end)
      end,
      isDead = function(h)
        if not h then return true end                    -- despawned/culled -> treat as gone
        local dead = false
        pcall(function() if h.IsDead then dead = h:IsDead() end end)
        if not dead then                                 -- fallback: health pool <= 0
          pcall(function()
            local sps = Game.GetStatPoolsSystem()
            if sps and h.GetEntityID then
              local hp = sps:GetStatPoolValue(h:GetEntityID(), gamedataStatPoolType.Health, false)
              if hp ~= nil and hp <= 0 then dead = true end
            end
          end)
        end
        return dead
      end,
      distToPlayer = function(p)
        local pp = playerPos(); if not pp or not p then return 1e9 end
        local dx, dy, dz = pp.x - p.x, pp.y - p.y, pp.z - p.z
        return math.sqrt(dx * dx + dy * dy + dz * dz)
      end,
      deleteById = function(id) deleteEntityById(id) end,
      -- v1.0 BLAZE: hand a weapon straight into V's inventory (MVP for the staged fight pickups).
      -- Direct inventory-add is 100% reliable vs a physical AMM ground-drop; the trigger coords in
      -- blaze.lua just gate WHEN each is given. Returns true if AddToInventory didn't error.
      giveWeapon = function(rec)
        local ok = false
        pcall(function() Game.AddToInventory(rec, 1); ok = true end)
        return ok
      end,
      -- v1.0 BLAZE: read a quest fact (numeric). Used to gate the fight on the "T-Bug opens the glass
      -- doors" beat instead of a raw proximity check. Returns 0 if the fact/system isn't available.
      getFact = function(name)
        local v = 0
        pcall(function() local qs = Game.GetQuestsSystem(); if qs then v = qs:GetFactStr(name) or 0 end end)
        return v
      end,
      -- v1.01 BLAZE: show/clear the game's NATIVE yellow [F] interaction prompt (the same
      -- InteractionChoiceHub the "Talk to Jackie" box uses) with a custom label, e.g. "Get in the AV".
      -- Reuses choiceBox.id/.shown so updateTalkPrompt's heartbeat stays coordinated (it yields while
      -- Blaze.escapePromptActive()). F is caught by the OnAction hook -> Blaze.tryEscapePress.
      showPrompt = function(label)
        pcall(function()
          local hub = InteractionChoiceHubData.new()
          hub.id, hub.active = choiceBox.id, true
          pcall(function() hub.title = "" end)
          local choice = InteractionChoiceData.new()
          pcall(function() choice.localizedName = tostring(label or "Interact") end)
          pcall(function() choice.inputAction = CName.new("Choice1") end)
          hub.choices = { choice }
          local idef = GetAllBlackboardDefs().UIInteractions
          local bb   = Game.GetBlackboardSystem():Get(idef)
          if bb and idef.InteractionChoiceHub then
            bb:SetVariant(idef.InteractionChoiceHub, ToVariant(hub), true)
            choiceBox.shown, choiceBox.lastPush = true, JL.clock or 0
          end
        end)
      end,
      hidePrompt = function()
        pcall(function()
          local idef = GetAllBlackboardDefs().UIInteractions
          local bb   = Game.GetBlackboardSystem():Get(idef)
          if bb and idef.InteractionChoiceHub then
            local empty = InteractionChoiceHubData.new()
            empty.id, empty.active, empty.choices = choiceBox.id, false, {}
            bb:SetVariant(idef.InteractionChoiceHub, ToVariant(empty), true)
          end
          choiceBox.shown = false
        end)
      end,
      -- v1.03 BLAZE: TONE-DOWN a spawned boss — multiply its max Health by `hpMul` (e.g. 0.2 = 20%).
      -- Story Takemura/Smasher spawned at full boss stats are near-unkillable at V's low Heist level.
      -- v1.56 (Antonia 2026-07-23): also scales OUTGOING damage. `dmgMul` is a plain multiplier
      -- (1.6 = +60% damage); it lands as an ADDITIVE modifier on AllDamageDonePercentBonus, which the
      -- damage pipeline reads off the INSTIGATOR for every attack — NPC or player alike, no player gate:
      --   damageSystem.script:2931  tempDamage += GetStatValue(instigatorID, AllDamageDonePercentBonus)
      --   damageSystem.script:2977  attackValues[i] *= (1.0 + tempDamage)
      -- (called from CalculateSourceModifiers, damageSystem.script:2137). The stat is a FRACTION, so
      -- the modifier value is dmgMul - 1.0.
      weaken = function(h, hpMul, dmgMul)
        if not h then return end
        pcall(function()
          local ss = Game.GetStatsSystem()
          if hpMul then
            local mod = RPGManager.CreateStatModifier(gamedataStatType.Health, gameStatModifierType.Multiplier, hpMul)
            ss:AddModifier(h:GetEntityID(), mod)
          end
          if dmgMul and dmgMul ~= 1.0 then
            local dmod = RPGManager.CreateStatModifier(gamedataStatType.AllDamageDonePercentBonus,
                                                       gameStatModifierType.Additive, dmgMul - 1.0)
            ss:AddModifier(h:GetEntityID(), dmod)
          end
        end)
        log(string.format("[Blaze] boss stats scaled: Health x%s, damage x%s",
                          tostring(hpMul or 1.0), tostring(dmgMul or 1.0)))
      end,
      -- v1.56 BLAZE: the player's chosen DIFFICULTY, as the game's own enum NAME. Source of truth is
      -- StatsDataSystem.GetDifficulty() (statsDataSystem.script:23) — the same call the base game uses to
      -- pick its damage constants (damageSystem.script:952).
      -- ⚠️ The enum names are OFF BY ONE from the menu labels (verified in
      -- characterCreationSummaryMenu.script:94 — Story/Easy/Hard/VeryHard map to LocKeys 52792/52791/
      -- 52790/52789 = Easy/Normal/Hard/Very Hard, and corroborated at damageSystem.script:1231 where
      -- `case gameDifficulty.Easy` reads the TweakDB field `.normalDifficultySelfDamagePerTick`). So:
      --   "Story" = menu EASY · "Easy" = menu NORMAL · "Hard" = menu HARD · "VeryHard" = menu VERY HARD
      -- ⚠️⚠️ And the DECLARATION ORDER is not the difficulty order either — statsDataSystem.script:1 is
      -- literally `enum gameDifficulty { Easy, Hard, VeryHard, Story }`, i.e. 0/1/2/3 = Easy/Hard/
      -- VeryHard/Story. Never infer these ordinals from the menu; that mapping is the numeric fallback below.
      -- Returns nil if the system can't be reached, and callers then fall back to the Normal tier.
      difficulty = function()
        local d, name
        pcall(function() d = Game.GetStatsDataSystem():GetDifficulty() end)
        if d == nil then return nil end
        pcall(function() name = tostring(d.value or d) end)
        -- Numeric fallback: some CET builds hand back a bare Int for an imported enum.
        if name == nil or not name:match("^%a+$") then
          local n; pcall(function() n = EnumInt(d) end)
          if type(n) ~= "number" then n = tonumber(name) end
          name = ({ [0] = "Easy", [1] = "Hard", [2] = "VeryHard", [3] = "Story" })[n]
        end
        return name
      end,
      -- v1.03 BLAZE: EMERGENCY force-defeat whatever V is looking at (test lever / immortality bypass).
      -- Tries the script Kill(), then falls back to zeroing the Health pool. Won't touch companion Jackie.
      defeatLookAt = function()
        local pl = Game.GetPlayer(); if not pl then return false end
        local h; pcall(function() local ts = Game.GetTargetingSystem(); if ts then h = ts:GetLookAtObject(pl, false, false) end end)
        if not h then log("[Blaze] defeat-target: aim your crosshair at an NPC first."); return false end
        local mine = false
        pcall(function() mine = JL.summon.spawn and JL.summon.spawn.handle and h:GetEntityID().hash == JL.summon.spawn.handle:GetEntityID().hash end)
        if mine then log("[Blaze] that's your COMPANION Jackie — not killing."); return false end
        local ok = false
        pcall(function() if h.Kill then h:Kill(pl, false, false); ok = true end end)
        if not ok then pcall(function()
          local sps = Game.GetStatPoolsSystem()
          if sps and h.GetEntityID then sps:RequestSettingStatPoolValue(h:GetEntityID(), gamedataStatPoolType.Health, 0.0, pl, false); ok = true end
        end) end
        log("[Blaze] defeat-target: " .. (ok and "killed the targeted NPC." or "could not kill (see console)."))
        return ok
      end,
      -- v1.03 BLAZE: log the looked-at NPC's class / entityID / record / display name — how to grab the
      -- passive luggage-Jackie's identity (aim at him, click Identify, read the console line).
      identifyLookAt = function()
        local pl = Game.GetPlayer(); if not pl then return end
        local h; pcall(function() local ts = Game.GetTargetingSystem(); if ts then h = ts:GetLookAtObject(pl, false, false) end end)
        if not h then log("[Blaze] identify: aim your crosshair at an NPC first."); return end
        local cls, id, rec, disp = "?", "?", "?", "?"
        pcall(function() cls  = tostring(h:GetClassName().value) end)
        pcall(function() id   = tostring(h:GetEntityID().hash) end)
        pcall(function() rec  = tostring(h:GetRecordID()) end)
        pcall(function() disp = tostring(h:GetDisplayName()) end)
        log(string.format("[Blaze] IDENTIFY -> class=%s  entityID=%s  record=%s  name=%s", cls, id, rec, disp))
      end,
      -- Remove the NPC V is LOOKING AT (used to clear the scene's own passive Jackie — the luggage
      -- carrier — so only our fighting companion remains). Won't touch our companion. Tries a real
      -- delete, then falls back to hiding + teleporting him far below the map (quest NPCs resist delete).
      despawnLookAt = function()
        local pl = Game.GetPlayer(); if not pl then return false end
        local h
        pcall(function() local ts = Game.GetTargetingSystem(); if ts then h = ts:GetLookAtObject(pl, false, false) end end)
        if not h then log("[Blaze] remove-look-at: aim your crosshair AT the passive Jackie, then click."); return false end
        local mine = false
        pcall(function() mine = JL.summon.spawn and JL.summon.spawn.handle and h:GetEntityID().hash == JL.summon.spawn.handle:GetEntityID().hash end)
        if mine then log("[Blaze] that's your COMPANION Jackie — not removing."); return false end
        local cls = "?"; pcall(function() local c = h:GetClassName(); cls = tostring(c and (c.value or c)) end)
        pcall(function() Game.GetDynamicEntitySystem():DeleteEntity(h:GetEntityID()) end)   -- works for DES entities
        pcall(function() if h.Dispose then h:Dispose() end end)                              -- fallback
        pcall(function()                                                                     -- last resort: hide + sink
          local pp = pl:GetWorldPosition()
          Game.GetTeleportationFacility():Teleport(h, Vector4.new(pp.x, pp.y, pp.z - 500.0, 1.0), EulerAngles.new(0,0,0))
        end)
        log("[Blaze] remove-look-at: removed targeted NPC [" .. cls .. "].")
        return true
      end,
      -- v1.07 (Antonia): AUTO-remove the scene's passive luggage-Jackie by his PERSISTENT entity id
      -- (from Identify: 9001273, record Character.Jackie, name LocKey#47007). Same removal path as the
      -- look-at button, but targeted by id so it needs no aiming. Skips our companion. Returns true only
      -- when it actually found + removed him (so blaze.lua stops retrying). Quiet on "not found yet".
      despawnSceneJackie = function(id)
        if not id then return false end
        local pl = Game.GetPlayer(); if not pl then return false end
        local eid
        pcall(function() eid = EntityID.new({ hash = id }) end)
        if not eid then pcall(function() eid = EntityID.new(); eid.hash = id end) end
        local h; pcall(function() h = Game.FindEntityByID(eid) end)
        if not h then return false end                     -- not streamed in yet; blaze.lua retries
        -- never touch OUR companion (DES handle or spawn id)
        local mine = false
        pcall(function() mine = JL.summon.spawn and JL.summon.spawn.handle and h:GetEntityID().hash == JL.summon.spawn.handle:GetEntityID().hash end)
        if mine then return false end
        local cls = "?"; pcall(function() local c = h:GetClassName(); cls = tostring(c and (c.value or c)) end)
        pcall(function() Game.GetDynamicEntitySystem():DeleteEntity(h:GetEntityID()) end)
        pcall(function() if h.Dispose then h:Dispose() end end)
        pcall(function()                                   -- last resort: hide + sink below the map
          local pp = pl:GetWorldPosition()
          Game.GetTeleportationFacility():Teleport(h, Vector4.new(pp.x, pp.y, pp.z - 500.0, 1.0), EulerAngles.new(0,0,0))
        end)
        log("[Blaze] scene-Jackie removed by id " .. tostring(id) .. " [" .. cls .. "].")
        return true
      end,
      -- MVP-A objective/cutscene = native message band + caption. MVP-B swaps THESE TWO lines
      -- for real WolvenKit .journal calls / a real scene (docs/BLAZE_WOLVENKIT_OBJECTIVES.md).
      -- v1.x: blaze's green objective banners hold 1.6x LONGER (Antonia) — applied here so it covers every
      -- objective call regardless of the duration blaze.lua passes (8.0 -> 12.8, 6.0 -> 9.6, 4.0 -> 6.4).
      objective = function(text, dur) showOnscreenMsg(text, (dur or 8.0) * 1.6) end,
      -- v1.02: REAL fade to black -> hold -> back in (drawBlazeFade). finale() re-arms it with the
      -- teleport/quest-complete callback so those run at FULL BLACK (hidden). fade() alone = visual only.
      fade = function(caption) startBlazeFade(nil); if caption and caption ~= "" then log("[Blaze] fade: " .. caption) end end,
      -- ALTERNATE-TIMELINE WORLD UNLOCK (v-next MVP slice): the Watson prologue barrier reads the
      -- quest fact `watson_prolog_unlock` directly (proven in docs/research/q005_graph_findings.md —
      -- set by NO quest condition, only the prevention-area system). Vanilla sets it deep inside q101
      -- (Love Like Fire). Setting it here opens Watson WITHOUT entering q101 -> no Johnny, no biochip,
      -- no death. THIS SLICE = Watson only (test it in isolation first). The Act-2 content toggles are
      -- the NEXT slice, added here once Watson is confirmed in-game:
      --   apartment_on, victor_vector_default_on, misty_default_on, mq033_misty_dialogue_on,
      --   wat_lch_gunsmith_01_default_on, radio_on, tv_on, cyberspace_on  (all =1).
      -- v1.45: routed through jlWatsonApply(true) so it also stamps the `jl_watson_open` marker — the
      -- barrier facts are then re-asserted every 5 s for the rest of the save (jlWatsonHoldTick), in BOTH
      -- story modes. A one-shot write here could be undone by a later quest tick and shut the bridges.
      worldUnlock = function() pcall(function() jlWatsonApply(true) end) end,
      -- v1.05: kill the leftover Heist "gone wrong" scene music at the finale (Antonia item 10).
      -- Best-effort; the console tester blazeStopMusic('<event>') finds the exact name in-game.
      stopMusic = function() pcall(blazeStopMusic) end,
      -- v1.06: the full "escape the scene" teardown (combat clear + music reset + scene fast-forward).
      finaleTeardown = function() pcall(blazeFinaleTeardown) end,
      -- v1.07: force sunny weather at the escape (Antonia). Default approach; overlay has A/B buttons.
      setWeather = function() pcall(blazeSetWeather) end,
      -- v1.10: also jump to daytime at the escape (heist is at night, so sunny alone stays dark).
      setDay = function() pcall(function() blazeSetMidday(12) end) end,
      -- ⚠️ EXPERIMENTAL Yorinobu scenario helpers ----------------------------------
      -- Jackie speaks: play the voiced clip + show the text. Returns the clip length (s) so blaze.lua's
      -- VO queue can space a multi-line beat by its real duration.
      say = function(text, sfx)
        -- REAL voiced line: plays the clip + the game's REAL subtitle band + lip flap (not the blue
        -- notification band). Returns the clip length so blaze.lua's VO queue spaces the beats.
        local secs
        pcall(function() secs = speakJackieLine(text, sfx) end)
        return secs
      end,
      -- Takemura appears -> Jackie becomes a COMPANION (fights + auto combat barks) and the mod goes
      -- fully active. Bypasses the retrieval/main-quest gates (this is the Blaze route). Setting
      -- JL.summon.active gates scheduleTick, so no second idle Jackie can spawn while he's placed.
      becomeCompanion = function(appearance)           -- v1.07: appearance = AMM name (dirty heist suit for the fight)
        pcall(function() Retrieval.forceReunion() end)   -- mod fully active (unlocks summon/companion systems)
        if JL.summon.active then return end              -- already a companion -> schedule already gated
        local spawn = ammSpawn(1, appearance)            -- companion Jackie (in `appearance` if given)
        if spawn then
          JL.summon.spawn, JL.summon.active, JL.summon.companionSet = spawn, true, false
          log("[Blaze] Jackie -> companion (schedule gated).")
        else
          log("[Blaze] becomeCompanion: ammSpawn failed.")
        end
      end,
      -- The payoff: open Watson without q101 (world-unlock lever), SKIP the retrieval shard by marking
      -- Jackie already returned, stop the leftover Heist music, and teleport V to El Coyote Cojo (Jackie's
      -- family bar). Jackie is ALREADY a companion (from becomeCompanion at the start), so his catch-up
      -- logic brings him to the bar beside her — no second spawn. (Full q005/interlude/q101 graph
      -- autocompletion is the OTHER workstream's job — this
      -- delivers the playable result via the barrier lift + teleport; see docs/research/q005_graph_findings.md.)
      finale = function()
        -- Run everything AT FULL BLACK (via the fade's atBlack callback) so V never sees the teleport.
        -- If the fade isn't running yet, startBlazeFade starts it; if it is, this just re-arms the callback.
        startBlazeFade(function()
          -- 1) open Watson without q101 (world-unlock lever). v1.45: stamps the `jl_watson_open` marker so
          --    jlWatsonHoldTick keeps the barrier facts asserted for the rest of the save — a single write
          --    here can be silently undone by a later quest tick, and V is stuck behind the bridges.
          pcall(function() jlWatsonApply(true) end)
          -- 2) skip the Where's-Jackie shard, mark him returned
          pcall(function() Retrieval.forceReunion() end)
          -- 3) BEST-EFFORT mark the main quest complete + stop it nagging. We succeed + untrack the
          --    currently-tracked entry (q005 during the Heist). ⚠️ This is cosmetic/journal-level, NOT a
          --    real graph completion, and q101 hasn't started so there's nothing to succeed there. The
          --    proper q005/q101 completion (exact facts/journal paths) is an UPCOMING TASK for the q005-
          --    graph workstream — see TODO. Enum names are guarded so a mismatch just no-ops.
          pcall(function()
            local jm = Game.GetJournalManager()
            local tracked = jm and jm:GetTrackedEntry()
            if tracked then
              pcall(function() jm:ChangeEntryState(tracked, "gameJournalQuest", gameJournalEntryState.Succeeded, gameJournalNotifyOption.Notify) end)
              pcall(function() jm:UntrackEntry(tracked) end)
              log("[Blaze] finale: succeeded + untracked the tracked main quest (best-effort q005).")
            end
          end)
          -- 4) teleport V to the finale destination (Antonia's captured coords, v1.07). Jackie is placed
          --    next to her + the finale conversation runs from blazeFinaleSceneTick (below).
          local fp = (Blaze.yori and Blaze.yori.finalePos) or { x = -1787.921, y = -450.040, z = 7.747, yaw = -1.4 }
          pcall(function()
            local tf = Game.GetTeleportationFacility()
            if tf then tf:Teleport(Game.GetPlayer(), Vector4.new(fp.x, fp.y, fp.z, 1.0), EulerAngles.new(0.0, 0.0, fp.yaw or 0.0)) end
          end)
          -- 5) NOW (V is away from the fight) "escape the scene": clear V's combat state, reset the music
          --    mix, mute the stuck bed, and fast-forward the lingering heist scene. See blazeFinaleTeardown.
          if Blaze.bound and Blaze.bound.finaleTeardown then pcall(Blaze.bound.finaleTeardown) end
          -- 6) v1.11 (Antonia): flip weather->sunny + time->midday HERE, at full black (was too early at the
          --    heli). And put V in a calm state for the fade-in: holster, out of combat, stand (uncrouch).
          pcall(function() blazeSetWeather() end)
          pcall(function() blazeSetMidday(12) end)
          pcall(function() blazeTransportCalm() end)
          -- 7) arm the finale scene: (re)spawn Jackie next to V in his NORMAL outfit facing her, then run the
          --    finale conversation once the fade lifts + the scene settles (blazeFinaleSceneTick).
          JL.blazeFinale = { phase = "spawn", startedAt = JL.clock or 0 }
          log("[Blaze] FINALE (at black): Watson open, shard skipped, quest untracked, V at finale spot, day+sun, calm; convo armed.")
        end)
      end,
      -- DIAGNOSE test-spawn: drop Takemura ~5 m and Smasher ~7 m in front of V, loudly, so we can see if
      -- DES accepts the records at all (isolates the record/plumbing from the apartment coords).
      diagnose = function()
        local pt = pointAheadOfV(5.0)
        if not pt then log("[Blaze] DIAGNOSE: no player / no point ahead of V."); return end
        local id1 = spawnDynEntity("Character.Takemura", pt, 0.0, "JackieLives_blaze_diag")
        log("[Blaze] DIAGNOSE spawn Character.Takemura ~5m ahead -> id=" .. tostring(id1) .. "  (nil => DES refused the record)")
        local pt2 = pointAheadOfV(7.0) or pt
        local id2 = spawnDynEntity("Character.Smasher", pt2, 0.0, "JackieLives_blaze_diag")
        log("[Blaze] DIAGNOSE spawn Character.Smasher ~7m ahead -> id=" .. tostring(id2) .. "  (nil => DES refused the record)")
      end,
      persist = function() blazeDumpConfig() end,   -- auto-write blaze_config.txt on every capture/grab
    }
  end)
  pcall(blazeLoadConfig)   -- v0.96: re-apply captured records/positions from blaze_config.txt (survives reloads)
  log("Loaded v" .. tostring(Config.version or "?") .. ". AMM present: " .. tostring(JL.amm ~= nil) ..
      ". Blaze module v" .. tostring(Blaze and Blaze.VERSION or "?? (blaze.lua not loaded!)"))
end)

-- Track overlay visibility so the window only shows while the CET overlay is open.
registerForEvent("onOverlayOpen",  function() JL.ui.overlayOpen = true end)
registerForEvent("onOverlayClose", function() JL.ui.overlayOpen = false end)

-- ---------------------------------------------------------------------------
-- v0.42: PROXIMITY BARKS. While Jackie is idle at a location (NOT your companion), V walking up
-- triggers a ONE-SHOT greeting bark; getting right in his face triggers a grunt. Both are WWise voice
-- barks on his entity, each on its own cooldown. Distances + cooldowns are live-tunable from the CET
-- window (sliders) until the feel is dialed in. State lazily inits (JL.bark) so it never collides with
-- a concurrent edit to the JL table or config; promote to Config.bark once the values are locked.
-- ---------------------------------------------------------------------------
local function barkCfg()
  if not JL.bark then
    JL.bark = {
      enabled       = true,
      greetRange    = 6.0,    -- m: within this (and outside bumpRange) -> one greeting bark
      bumpRange     = 1.2,    -- m: within this -> a grunt
      greetCooldown = 120.0,  -- s: after a greeting, stay quiet this long
      bumpCooldown  = 8.0,    -- s: anti-spam on the grunt
      greetEvents   = { "ono_jackie_greet", "ono_jackie_curious", "ono_jackie_additional" },
      bumpEvent     = "ono_jackie_bump",
      greetRepeatCooldown = 300.0,  -- v0.48: s before a greet event may repeat (5 min); also never the last one used
      greetUsed = {}, lastGreetEvent = nil,  -- v0.48: per-event last-used clock for the no-repeat picker
      lastGreet = -999, lastBump = -999, checkT = 0, lastDist = nil,
      helloDay = nil,   -- v1.41: in-game day (jlGameDay) the spoken venue hello last fired on
    }
  end
  return JL.bark
end

-- v0.48: pick a greet event that is NOT the one used most recently and NOT used within greetRepeatCooldown
-- (5 min). Degrades gracefully: if every event is on cooldown, just avoid an immediate repeat; with a
-- single-event pool, return it. Records the pick so the next call steers away from it. `now` = JL.clock.
local function pickFreshGreet(b, now)
  local pool = (b.greetEvents and #b.greetEvents > 0) and b.greetEvents or { "ono_jackie_greet" }
  b.greetUsed = b.greetUsed or {}
  local cd = b.greetRepeatCooldown or 300.0
  local fresh = {}
  for _, ev in ipairs(pool) do
    local last = b.greetUsed[ev]
    if ev ~= b.lastGreetEvent and (not last or (now - last) >= cd) then fresh[#fresh + 1] = ev end
  end
  if #fresh == 0 then                       -- all on cooldown -> at least don't repeat the last one
    for _, ev in ipairs(pool) do if ev ~= b.lastGreetEvent then fresh[#fresh + 1] = ev end end
  end
  if #fresh == 0 then fresh = pool end       -- single-event pool: nothing else to pick
  local ev = fresh[1]; pcall(function() ev = fresh[math.random(1, #fresh)] end)
  b.greetUsed[ev]  = now
  b.lastGreetEvent = ev
  return ev
end

-- v0.52: no-repeat picker for arrival GREETING LINES (real jl_ clips + subtitle, NOT WWise grunt events).
-- Avoids the last-used line + any used within greetRepeatCooldown (5 min). State on JL.arrivalGreet (keyed by sfx).
local function pickArrivalGreetLine(now)
  local pool = (jlHermano() and Config.call and Config.call.arrivalGreetingsM)   -- v1.2: Hermano arrival greetings
               or (Config.call and Config.call.arrivalGreetings) or {}
  if #pool == 0 then return nil end
  JL.arrivalGreet = JL.arrivalGreet or { used = {}, last = nil }
  local st = JL.arrivalGreet
  local cd = (barkCfg().greetRepeatCooldown) or 300.0
  local fresh = {}
  for _, e in ipairs(pool) do
    local k = e.sfx or e.text
    local last = st.used[k]
    if k ~= st.last and (not last or (now - last) >= cd) then fresh[#fresh + 1] = e end
  end
  if #fresh == 0 then                       -- all on cooldown -> at least don't repeat the last one
    for _, e in ipairs(pool) do if (e.sfx or e.text) ~= st.last then fresh[#fresh + 1] = e end end
  end
  if #fresh == 0 then fresh = pool end       -- single-entry pool
  local e = fresh[1]; pcall(function() e = fresh[math.random(1, #fresh)] end)
  local k = e.sfx or e.text
  st.used[k] = now; st.last = k
  return e
end

-- v1.41: pick the spoken VENUE HELLO line (real jl_ clip + subtitle) for the first approach of the
-- in-game day. Gender-aware pool, same no-immediate-repeat rule as the arrival greeting so two
-- consecutive days don't open with the same line. GLOBAL -> costs no top-level local (200-cap).
function pickVenueHelloLine()
  local G = Config.venueGreet or {}
  local pool = (jlHermano() and G.greetingsM) or G.greetings or {}
  if #pool == 0 then return nil end
  JL.venueHello = JL.venueHello or { last = nil }
  local fresh = {}
  for _, e in ipairs(pool) do
    if (e.sfx or e.text) ~= JL.venueHello.last then fresh[#fresh + 1] = e end
  end
  if #fresh == 0 then fresh = pool end       -- single-entry pool: nothing else to pick
  local e = fresh[1]; pcall(function() e = fresh[math.random(1, #fresh)] end)
  JL.venueHello.last = e.sfx or e.text
  return e
end

-- v0.46/v0.48/v0.52: ARRIVAL GREETING. After ANY arrival hands off to companion (promoteToCompanion sets
-- JL.summon.arrivalGreetPending), Jackie says a one-shot real GREETING LINE (v0.52: a jl_ clip + subtitle, not
-- the old WWise grunt) the moment he closes to `Config.call.arrivalGruntDistance` (4 m). Picks via
-- pickArrivalGreetLine (no immediate repeat + 5-min cooldown). Safe / sprint / bike alike; once per arrival.
local function arrivalGreetTick()
  if not JL.summon.arrivalGreetPending then return end
  local sp = JL.summon.spawn
  local h  = sp and sp.handle
  if not h then return end
  local pp = playerPos(); if not pp then return end
  local jp; pcall(function() jp = h:GetWorldPosition() end)
  if not jp then return end
  local d = dist3(pp, jp)
  if d <= ((Config.call and Config.call.arrivalGruntDistance) or 4.0) then
    if Branch.open or Branch.busy or (dlg and dlg.active) then return end  -- don't talk over a convo; retry next tick
    JL.summon.arrivalGreetPending = false
    if JL.reunionPending then   -- v0.85: the FIRST-EVER meeting -> play the short reunion dialogue, then unlock
      JL.reunionPending = false
      pcall(function() Branch.start(Config.reunionMeetTree and Config.reunionMeetTree.start or nil, Config.reunionMeetTree) end)
      -- v0.93: arm the reunion SMILE BOOST — forced smile for the first N s, then 3x smile chance for
      -- the rest of the meet (see smileTick). Cleared by the reunion_complete action; `reunionSafety`
      -- is a hard expiry so an aborted meet can't leave him grinning forever.
      pcall(function()
        local now = JL.clock or 0
        local sc  = Config.smile or {}
        JL.smile.reunionActive     = true
        JL.smile.reunionForceUntil = now + (sc.reunionForceSeconds or 8.0)
        JL.smile.reunionSafety     = now + 180.0
        JL.smile.until_, JL.smile.cooldownUntil, JL.smile.nextRoll, JL.smile.nextApply = 0, 0, 0, 0
      end)
      log("Reunion: first-meeting dialogue started (reunionMeetTree) + smile boost armed.")
      return
    end
    local e = pickArrivalGreetLine(JL.clock or 0)
    if e then
      pcall(function() speakJackieLine(e.text, e.sfx) end)
      log(("Arrival: greeting line '%s' (d=%.1f m)."):format(tostring(e.text), d))
    end
  end
end

local function proximityBarkTick(dt)
  local b = barkCfg()
  if not b.enabled then return end
  if JL.summon.active then return end                         -- only when he's NOT your companion
  local sp = JL.idle.spawn
  if not sp or not sp.handle or JL.idle.leaving then return end
  if Branch.open or Branch.busy or (dlg and dlg.active) then return end  -- don't bark over a convo
  b.checkT = (b.checkT or 0) + dt                             -- throttle distance math to ~5x/s
  if b.checkT < 0.2 then return end
  b.checkT = 0
  local pp = playerPos(); if not pp then return end
  local jp; pcall(function() jp = sp.handle:GetWorldPosition() end)
  if not jp then return end
  local d = dist3(pp, jp); b.lastDist = d
  local now = JL.clock or 0
  -- v1.41: FIRST APPROACH OF THE IN-GAME DAY -> a real spoken hello, checked BEFORE the grunt chain so
  -- it still lands if V walks straight into bump range on the first sample. `day == nil` (TimeSystem not
  -- up yet) falls through to the ordinary grunt rather than firing a hello on an unknown day.
  local G = Config.venueGreet or {}
  if G.enabled and d <= (G.range or 5.0) then
    local day = jlGameDay()
    if day and b.helloDay ~= day then
      b.helloDay = day
      local e = pickVenueHelloLine()
      if e then
        b.lastGreet = now       -- the spoken hello counts as the greeting; don't grunt on top of it
        pcall(function() speakJackieLine(e.text, e.sfx) end)
        log(string.format("Bark: venue HELLO (day %d, d=%.2f m) '%s'", day, d, tostring(e.text)))
        return
      end
    end
  end
  if d <= (b.bumpRange or 1.2) then
    if (now - (b.lastBump or -999)) >= (b.bumpCooldown or 8.0) then
      b.lastBump = now
      pcall(function() playEventOn(sp.handle, b.bumpEvent or "ono_jackie_bump", "") end)
      log(string.format("Bark: BUMP grunt (d=%.2f m)", d))
    end
  elseif d <= (b.greetRange or 6.0) then
    if (now - (b.lastGreet or -999)) >= (b.greetCooldown or 120.0) then
      b.lastGreet = now
      local ev = pickFreshGreet(b, now)   -- v0.48: avoid the last-used + any used in the last 5 min
      pcall(function() playEventOn(sp.handle, ev, "") end)
      log(string.format("Bark: GREET '%s' (d=%.2f m)", tostring(ev), d))
    end
  end
end

-- v1.11 BLAZE finale scene: after the fade drops V at the finale spot (JL.blazeFinale armed by the finale
-- bind), RESPAWN Jackie fresh in his NORMAL outfit (the fight companion gets culled by the long teleport —
-- "Jackie didn't load in"), stand him BESIDE V facing her, then run the finale conversation once the fade
-- lifts AND the scene has settled (Antonia: it appeared too early, during the blackscreen). Reuses the
-- companion + branch engine. Global => 200-cap safe; defined here so it can see the late local helpers.
function blazeFinaleSceneTick()
  local f = JL.blazeFinale
  if not f or not f.phase then return end
  local app = (Blaze.yori and Blaze.yori.finaleAppearance) or "jackie_welles_default"

  if f.phase == "spawn" then
    -- v1.44: CANCEL ANY WALK-OFF IN PROGRESS. If the companion clock expired (e.g. the escape's midday
    -- jump on an older save) Jackie is mid "heading home" walk. Left alone, leavingTick would keep running
    -- and despawn the FRESH Jackie we're about to spawn — the finale would play to an empty spot. Clearing
    -- the leaving state also wipes the parting-line subtitle timer so "Catch you later" can't hang on
    -- screen over the finale conversation.
    if JL.leaving.phase then
      log("[Blaze] finale: Jackie was walking off (companion clock) -> cancelling the walk-off.")
      JL.leaving.phase, JL.leaving.deadline, JL.leaving.lastReissue = nil, nil, nil
      JL.leaving.subClearAt = nil
      pcall(hideSubtitle)
    end
    -- Drop the stale duration deadline too, so the fresh companion below re-arms from NOW instead of
    -- inheriting an already-expired one (belt-and-braces: the blaze gate in onUpdate should stop the
    -- auto-leave anyway, but the finale must not depend on JL.mode still being "blaze").
    JL.summon.companionExpiresGame, JL.summon.companionSinceGame = nil, nil
    -- v1.47: WAIT FOR THE WORLD before spawning. `finale()` teleports V at full black and arms us the same
    -- frame; AMM's SpawnNPC drops the body 1 m in front of V *at CreateEntity time*, so spawning too early
    -- can drop him at V's PRE-teleport spot (back at Konpeki) — and spawning into a not-yet-streamed world
    -- is the exact failure class companionPersistTick already guards with its `startupGrace`.
    if not playerPos() then return end                     -- V not in-world yet (load / fade)
    f.spawnReadyAt = f.spawnReadyAt or ((JL.clock or 0) + ((Blaze.yori and Blaze.yori.finaleSpawnDelay) or 0.6))
    if (JL.clock or 0) < f.spawnReadyAt then return end
    -- The fight companion (dirty suit) is likely culled by the teleport. Throw him out and spawn a FRESH
    -- companion in the normal outfit right here, so Jackie reliably appears at the finale.
    pcall(function() if JL.summon.spawn then ammDespawn(JL.summon.spawn) end end)
    JL.summon.spawn, JL.summon.active, JL.summon.companionSet = nil, false, false
    local sp = ammSpawn(1, app)
    if sp then
      f.tries = (f.tries or 0) + 1
      JL.summon.spawn, JL.summon.active, JL.summon.companionSet = sp, true, false
      f.phase, f.spawnAt, f.placeTries = "place", (JL.clock or 0), 0
      local vp = playerPos()
      log(("[Blaze] finale: fresh Jackie spawned (normal outfit) — attempt %d, V at (%.1f,%.1f,%.1f).")
          :format(f.tries, vp and vp.x or 0, vp and vp.y or 0, vp and vp.z or 0))
    elseif (JL.clock or 0) - (f.startedAt or 0) > 8.0 then
      f.phase, f.talkAt = "talk", (JL.clock or 0)         -- give up spawning; still run the convo
      log("[Blaze] finale: ammSpawn kept failing — running convo without a placed Jackie.")
    end
    return
  end

  if f.phase == "place" then
    local now = JL.clock or 0
    local h = resolveJackieHandle()
    if not h then
      -- v1.47: this used to fall through to "talk" SILENTLY after 8 s, which is exactly what an unplaced
      -- Jackie looked like in-game: "fresh Jackie spawned" in the log, no Jackie, no error, no walk-off.
      -- Now: say so, and RESPAWN rather than shrug — the body is either unresolvable or somewhere else.
      if now - (f.spawnAt or f.startedAt or 0) > ((Blaze.yori and Blaze.yori.finaleResolveTimeout) or 4.0) then
        if (f.tries or 0) < ((Blaze.yori and Blaze.yori.finaleSpawnRetries) or 3) then
          log(("[Blaze] finale: Jackie's handle NEVER RESOLVED (attempt %d) -> despawn + respawn."):format(f.tries or 0))
          f.phase, f.spawnReadyAt = "spawn", now + 0.3
        else
          log(("[Blaze] finale: GAVE UP placing Jackie after %d attempts — convo runs without him. " ..
               "Report this: the AMM spawn never produced a resolvable body."):format(f.tries or 0))
          f.phase, f.talkAt = "talk", now
        end
      end
      return
    end
    pcall(function() h:PrefetchAppearanceChange(CName.new(app)) end)   -- belt-and-suspenders normal outfit
    pcall(function() h:ScheduleAppearanceChange(CName.new(app)) end)
    -- v1.47: a concurrent respawn-at-V (catchUp / persist) may have armed the SETTLE window, which keeps the
    -- puppet INVISIBLE and non-colliding for ~2 s and re-asserts that every frame. If its reveal is missed,
    -- Jackie is present, a companion, and permanently unseeable — "companion: true, no Jackie around".
    -- Tear the window down and force him visible + solid before we place him.
    JL.settle.hideUntil, JL.settle.collideUntil, JL.settle.reposePending = nil, nil, nil
    setVisible(h, true)

    -- ── v1.50: THE FENCE CLIP. Two separate reasons he stood in front of V, inside the railing. ──
    -- (1) WRONG MOVER. This used `Game.GetTeleportationFacility():Teleport()` alone. Per placeAtExact's own
    --     note (and docs/research/spawn_at_distance_research.md): the facility **often no-ops on a spawned
    --     puppet** — `AITeleportCommand` is what actually relocates one. So the move never happened and he
    --     simply stayed where AMM dropped him: 1 m in FRONT of V, which at this spot is the fence.
    --     `placeAtExact` issues the AI command first and uses the facility only as a second write.
    -- (2) WRONG TARGET. `finaleSide` was a raw ±right-vector offset. If that one point is inside geometry,
    --     `snapToNavmesh` returns nil and the code shrugged (`or jp`) and used the bad point anyway.
    --     `frontSideArrivalPoint` is the helper that already solves exactly this for fast-travel/catch-up
    --     respawns ("he caught up straight into the geometry behind V"): it sweeps the walk-abreast side
    --     anchors, tries his current side first, then the other side, then straight ahead, over several
    --     angles and shrinking distances, navmesh-snapping and height-checking each. That is *why* a normal
    --     arrival lands him sideways and clean — the finale just wasn't calling it.
    -- Collision stays OFF until he's actually there, so the fence can't hold him mid-relocate.
    local pp = playerPos()
    local jp; pcall(function() jp = h:GetWorldPosition() end)
    if not f.placePt then
      local want = (Blaze.yori and Blaze.yori.finalePlaceDistance) or 2.5
      local how = "front-side search"
      f.placePt = frontSideArrivalPoint(want, jp)          -- proven side-point search (navmesh + height checked)
      if not f.placePt and pp then                          -- fallback: the old raw side offset, but only if it snaps
        local rt; pcall(function() rt = Game.GetPlayer():GetWorldRight() end)
        local side = (Blaze.yori and Blaze.yori.finaleSide) or 1.4
        local cand = rt and Vector4.new(pp.x + rt.x * side, pp.y + rt.y * side, pp.z, 1.0)
                        or Vector4.new(pp.x + side, pp.y, pp.z, 1.0)
        f.placePt = snapToNavmesh(cand)                     -- nil -> no valid ground; retry next tick
        how = "side fallback"
      end
      if f.placePt then
        setNpcCollision(h, false)
        log(("[Blaze] finale: place target (%.1f,%.1f,%.1f) via %s."):format(
            f.placePt.x, f.placePt.y, f.placePt.z, how))
      end
    end
    if not f.placePt then                                   -- no navmesh anywhere yet; keep trying briefly
      f.placeTries = (f.placeTries or 0) + 1
      if f.placeTries <= 20 then return end
      log("[Blaze] finale: no navmesh point beside V — leaving Jackie where he spawned.")
      setNpcCollision(h, true)
      f.placePt = nil
    else
      -- AITeleportCommand + facility, exact (no nav snap — the point is already snapped), facing V.
      pcall(function() placeAtExact(h, f.placePt, yawToward(f.placePt, pp) or 0.0) end)
    end

    -- v1.47/v1.50: VERIFY he actually arrived — measured against the TARGET POINT, not against V. Measuring
    -- distance-to-V could not catch this bug at all: standing inside the fence 1 m in front of her already
    -- passed a 6 m "close enough" test. aiTeleport is ASYNC (lands a frame or two later), so the first pass
    -- always reads his old position; we simply re-issue until he's on the mark.
    pcall(function() jp = h:GetWorldPosition() end)
    local d   = (jp and f.placePt) and dist3(f.placePt, jp) or nil
    local tol = (Blaze.yori and Blaze.yori.finalePlaceTolerance) or 1.5
    if d and d > tol then
      f.placeTries = (f.placeTries or 0) + 1
      if f.placeTries <= 12 then return end   -- stay in `place`, re-issue the AI teleport next tick
      log(("[Blaze] finale: Jackie STILL %.1f m off the mark after %d AI teleports — continuing anyway. " ..
           "If he's clipped again, raise Blaze.yori.finalePlaceDistance."):format(d, f.placeTries))
    elseif d then
      local dv = pp and jp and dist3(pp, jp) or -1
      log(("[Blaze] finale: Jackie placed on the mark (%.1f m off target, %.1f m from V)."):format(d, dv))
    end
    setNpcCollision(h, true)                 -- v1.50: he's on solid navmesh now — a follower must collide
    pcall(promoteToCompanion)                -- keep him a proper follower (living Jackie going forward)
    -- SETTLE: don't start the convo until the fade fully lifts AND a beat passes (Antonia: subtitle+picker
    -- showed during the blackscreen). Configurable via Blaze.yori.finaleSettle.
    f.phase, f.talkAt = "talk", (JL.clock or 0) + ((Blaze.yori and Blaze.yori.finaleSettle) or 1.8)
    return
  end

  if f.phase == "talk" then
    local fadeDone = not (JL.blazeFade and JL.blazeFade.phase)   -- wait until the screen is fully clear
    if fadeDone and (JL.clock or 0) >= (f.talkAt or 0) then
      f.phase, f.talkStartedAt = "talking", (JL.clock or 0)
      pcall(function() Branch.start(nil, Config.blazeFinaleTree) end)
      log("[Blaze] finale conversation started.")
    end
    return
  end
  if f.phase == "talking" then
    -- disarm when the convo ends OR after a hard safety cap (so a hung convo can't leave ForceStand on,
    -- which would block crouch for the rest of the session).
    if (not Branch.busy) or ((JL.clock or 0) - (f.talkStartedAt or 0) > 300.0) then
      pcall(blazeReleaseStand)   -- let V crouch again now the finale's over
      JL.blazeFinale = nil       -- convo done -> disarm
      -- v1.44: THE SET-PIECE IS OVER. Blaze.reset() nils `Blaze.st` (previously only ever cleared when a
      -- NEW run started, so `st.active` stayed true for the rest of the save) and despawns any leftover
      -- Smasher/Takemura/heli entities — including the heli we abandoned on the Konpeki roof.
      -- Clearing it is also what releases jlBlazeSceneLive(), handing Jackie back to the normal
      -- Quiet-Life rules: from here he can go home when his companion clock runs out, like any other day.
      pcall(function() Blaze.reset() end)
      log("[Blaze] finale complete -> set-piece reset; Jackie returns to normal companion rules.")
    end
  end
end

registerForEvent("onUpdate", function(dt)
  JL.clock = (JL.clock or 0) + dt
  -- v1.52 SESSION GUARD — MUST BE FIRST. onUpdate keeps ticking through a load screen, so on the frame a
  -- new session starts every handle below this line is a pointer into the world that just died. Nothing
  -- that can touch a handle may run before this. (`pcall` cannot save us from a native use-after-free.)
  pcall(function() Session.tick() end)
  -- nsTick touches no entity handles and must keep running at the main menu, or the Esc-menu settings
  -- panel never registers there. It's the one tick allowed above the session gate.
  pcall(nsTick)         -- v0.44: register the Esc-menu panel once nativeSettings has loaded (load-order safe)
  if Session.id == 0 then return end   -- main menu / load screen: no world, no session — touch nothing
  -- Retrieval questline (Vik reveal tip, Badlands shard, Misty/Mama post-reunion shards) is a QUIET-LIFE
  -- thing — in Blaze mode Jackie is handed to you by the set-piece, so none of those custom shards should
  -- fire (Antonia 2026-07-08). Blaze's finale calls Retrieval.forceReunion() directly for the unlock.
  if JL.mode ~= "blaze" then
    pcall(function() Retrieval.tick(dt) end)   -- retrieval questline: gate + Vik tip + Badlands shard + call/arrival/reunion sequence
  end
  if JL.mode == "blaze" then
    pcall(function() Blaze.tick(JL.clock, dt) end)   -- v0.96: Heist set-piece state machine (self-guards when idle)
    pcall(function() blazeFadeTick(dt) end)          -- v1.02: advance the fade-to-black animation (self-guards when idle)
    pcall(blazeSceneFFTick)                          -- v1.06: auto-deactivate scene fast-forward after the finale (self-guards)
    pcall(blazeFinaleSceneTick)                      -- v1.07: place Jackie + run the finale conversation (self-guards)
    pcall(function() Blaze.autoStartTick() end)      -- v1.0: auto-start when the start-fact flips (T-Bug opens the glass doors)
  end
  -- (v1.54: the per-frame jlDetectGenderOnce gender probe is gone — Hermano is now the flat default for
  --  every V and is applied once at load by jlDefaultHermano. Nothing to poll here any more.)
  -- (nsTick moved above the session gate — it must also run at the main menu; see there.)
  pcall(updateTalkPrompt, dt)
  pcall(dialogueTick)
  pcall(branchTick)
  pcall(subtitleWatchdogTick)  -- v0.80: GUARANTEE no dialogue subtitle can stick after a talk ends
  pcall(flapTick)       -- lip-movement: shuffle talking faces while a Jackie line plays
  pcall(smileTick)      -- v0.53: low-chance brief smile when V catches his eye
  pcall(ambientGruntTick)  -- v0.55: rare non-pained "feel alive" grunt while he's around
  pcall(callTick)       -- holocall: ring -> pick up
  pcall(vehicleArrivalTick)  -- v0.50: THE arrival state machine — foot (DES sprint-in) + bike, one tail
  pcall(bikeTestTick)        -- v0.63: read back what the bike-model test actually spawned
  pcall(arrivalGreetTick)    -- v0.46/v0.48: one-shot fresh greeting when an arrived Jackie closes to 4 m
  pcall(leavingTick)    -- v0.33: dismissed Jackie walking off -> despawn at distance
  -- v1.52: THE CRASH SITE. This block ran every frame against JL.summon.spawn.handle — including the
  -- frames right after a load-from-save, when that handle points into the world that was just torn down.
  -- SetNPCAsCompanion on freed memory is a native use-after-free, and the pcall below never caught it
  -- (pcall catches Lua errors, not native faults). Session.tick() should already have reset us; this
  -- stamp check is the belt to that braces, because this is where the dead handle was actually touched.
  if JL.summon.spawn and Session.stale(JL.summon.spawn) then
    log("[SESSION] promote: dropping stale spawn record from a previous session (not dereferenced).")
    JL.summon.spawn, JL.summon.active, JL.summon.companionSet = nil, false, false
  end
  if JL.summon.spawn and JL.summon.spawn.handle and not JL.summon.companionSet and not JL.summon.walkIn then
    local amm = getAMM()
    Session.mark("AMM SetNPCAsCompanion (promote)")
    pcall(function()
      if amm and amm.Spawn and amm.Spawn.SetNPCAsCompanion then
        amm.Spawn:SetNPCAsCompanion(JL.summon.spawn.handle)
      end
      local pl, h = Game.GetPlayer(), JL.summon.spawn.handle
      if pl and h and h.GetAttitudeAgent then
        h:GetAttitudeAgent():SetAttitudeTowards(pl:GetAttitudeAgent(), EAIAttitude.AIA_Friendly)
      end
    end)
    Session.clear()
    JL.summon.companionSet = true
    setCompanionFlag(true)   -- v0.72: persist "is companion" (this is the summon/respawn promote path)
    JL.ui.status = "Jackie is following."
    log("Companion role applied.")
  end

  -- v1.44: a SCRIPTED CLOCK JUMP (blazeSetMidday) must not eat Jackie's companion time. Re-arm the
  -- duration clock from the NEW `now` on the tick after the jump. Done before the expiry check below so
  -- the stale deadline can never fire in the same frame.
  if JL.rearmCompanionClock then
    JL.rearmCompanionClock = nil
    if JL.summon.active and JL.summon.companionSet then
      JL.summon.companionSinceGame = nil          -- treat the jump as "he just joined"
      armCompanionTimer()
      log("Companion: game clock was jumped -> duration timer re-armed (the jump doesn't count).")
    end
  end
  -- v0.39: companion-duration clock. Arm it once he's a confirmed companion (any path), and when
  -- it runs out (and autoLeaveOnExpiry) send him home via the same walk-off as a dismissal.
  if JL.summon.active and JL.summon.companionSet and not JL.summon.companionExpiresGame then
    armCompanionTimer()
  end
  -- v0.41: the auto-leave is PAUSED for the whole dinner outing (JL.dinner.phase) so he never
  -- bails mid-walk; dinnerTick does a full clock reset when the meal finishes.
  -- v1.44: and it is PAUSED FOR THE WHOLE BLAZE SET-PIECE + its finale. Blaze puts Jackie at V's side on
  -- purpose; "his shift ended" is a Quiet-Life rule with no business firing mid-set-piece. The escape jumps
  -- the clock to midday, which used to trip this and walk him off seconds before the finale needed him.
  -- NOTE: gated on the set-piece being LIVE (`Blaze.st.active` / the armed finale), NOT on `JL.mode`.
  -- JL.mode stays "blaze" for the rest of the save, so a mode check would disable his going-home behaviour
  -- forever on a Blaze playthrough. Blaze.reset() nils `st`, and blazeFinaleSceneTick nils `JL.blazeFinale`
  -- when the conversation ends — so normal Quiet-Life auto-leave resumes the moment the scene is over.
  if not jlBlazeSceneLive()
     and JL.summon.active and Config.companion and Config.companion.autoLeaveOnExpiry
     and not JL.dinner.phase
     and JL.summon.companionExpiresGame and JL.leaving.phase ~= "walking" then
    local g = getGameSeconds()
    if g and g >= JL.summon.companionExpiresGame and startLeaving then
      log("Companion: max in-game duration reached -> Jackie heads home.")
      pcall(startLeaving)
    end
  end
  -- v0.62: MAIN-QUEST / CUTSCENE EXIT. If V starts/tracks a main quest OR enters a cutscene while
  -- Jackie's tagging along, he excuses himself and walks off (he won't be dragged into the story, and
  -- once he's gone his cruise bike can't spawn either). Same guards as the expiry exit: not mid-dinner,
  -- not already walking off; fires once (summon.active clears on despawn).
  -- v0.98: EXCEPTION for Blaze of Glory — that mode PUTS Jackie in the main quest on purpose (he fights
  -- the Heist alongside V), so the main-quest/cutscene excuse must NOT fire, or our companion walks off.
  if JL.mode ~= "blaze"
     and JL.summon.active and JL.summon.companionSet and not JL.dinner.phase
     and JL.leaving.phase ~= "walking" and startLeaving and (isMainQuestActive() or jlInCutscene()) then
    log("Main quest / cutscene -> Jackie excuses himself and heads out.")
    pcall(function() startLeaving(Config.mainQuestExit) end)
  end
  pcall(jlCruiseTick)     -- v0.85: V on a BIKE -> Jackie trails on his Arch (gated before the foot ticks)
  pcall(followKeepCloseTick) -- v0.67: hold him a few m behind V (override AMM's long leash)
  pcall(abreastTick)      -- v0.84: OR (when enabled) hold him beside/ahead of V instead of trailing
  pcall(jlTakedownTick)   -- v1.48: watch an ordered takedown to a conclusion (grapple / down / timeout)
  pcall(blazeCalmHoldTick) -- v1.51: re-assert holster/uncrouch after the async finale teleport, and verify
  pcall(catchUpTick)      -- v0.66: settled companion fell behind (fast-travel/ran off) -> snap to V's side
  pcall(companionPersistTick)  -- v0.72: saved "is companion" but his body is gone (reload / culling FT) -> respawn at V
  pcall(settleTick)       -- v0.82: hide + no-collision for a beat after a respawn-at-V so he doesn't pop/clip in
  pcall(dinnerTick)       -- v0.41: dinner outing (walk to restaurant -> linger -> full reset)
  pcall(jackieDinnerOfferTick)  -- v0.48: Jackie proposes the outing himself after a random in-game gap

  pcall(jlLookAtTick)     -- v1.41: venue/seated Jackie turns his head to follow V (engine look-at overlay)
  pcall(wanderTick)       -- v0.35: idle Jackie free-roams between his location's waypoints
  pcall(idleLeavingTick)  -- v0.38: idle Jackie walking off to a venue exit before despawning
  pcall(function() proximityBarkTick(dt) end)  -- v0.42: greet on approach (6 m) + grunt on bump (1.2 m)

  JL.timer = JL.timer + dt
  if JL.timer >= Config.scheduleCheckInterval then
    JL.timer = 0
    pcall(scheduleTick)
  end

  -- v1.45: hold the Watson barrier open. Runs in BOTH story modes and regardless of whether the set-piece
  -- is still live — once a save has been marked `jl_watson_open`, switching back to Quiet Life (or a quest
  -- tick re-locking the fact) must never strand V behind the bridges. No marker -> instant no-op.
  pcall(function() jlWatsonHoldTick(dt) end)

  -- v0.97: mourning suppression. Re-assert the grief holds every ~5 s (cheap, and re-catches any fact
  -- the quest system flips back up). Quiet Life runs it only when the player opted in; Blaze ALWAYS runs
  -- it (v1.05: Blaze auto-suppresses grief + the ofrenda + forces El Coyote open — Antonia item).
  if (JL.mode == "quietlife" and JL.mourningSuppress) or JL.mode == "blaze" then
    JL.mourningTimer = (JL.mourningTimer or 0) + dt
    if JL.mourningTimer >= 5.0 then
      JL.mourningTimer = 0
      pcall(jlMourningApply, false)
    end
  end
end)

-- ---------------------------------------------------------------------------
-- v0.43 SEAT POSITION TUNER. Live X/Y/Z/yaw OFFSETS from a location's captured seat. Slide in-game
-- (with idle Jackie present at that venue) until he sits perfectly, then print the config-ready
-- line. Re-seating goes through the normal stop-workspot -> teleport -> deferred sit path, so the
-- v0.43 sit-time collision drop applies and he won't clip the chair.
-- ---------------------------------------------------------------------------
-- All of a location's SIT waypoints, in order (a venue can have several stools — e.g. noodle has 2).
local function tunerSitWaypoints(loc)
  local out = {}
  if loc and loc.waypoints then
    for _, wp in ipairs(loc.waypoints) do if wp.pose == "sit" then out[#out + 1] = wp end end
  end
  return out
end

-- The venue keys (in menu order) that actually have a sit waypoint — the tuner's dropdown list.
local TUNER_VENUE_ORDER = { "noodle", "misty", "coyote", "afterlife", "ginger", "redwood", "lizzies", "secret" }
local function tunerSitVenues()
  local out = {}
  for _, k in ipairs(TUNER_VENUE_ORDER) do
    local loc = Config.locations[k]
    if loc and #tunerSitWaypoints(loc) > 0 then out[#out + 1] = k end
  end
  return out
end

-- The specific seat waypoint the tuner is editing right now (location key + seat index).
local function tunerSeatWaypoint()
  local loc   = Config.locations[JL.tuner.key]
  local seats = tunerSitWaypoints(loc)
  if #seats == 0 then return nil, loc, seats end
  if JL.tuner.seatIdx > #seats then JL.tuner.seatIdx = 1 end
  return seats[JL.tuner.seatIdx], loc, seats
end

local function tunerInit()
  local t        = JL.tuner
  local wp, loc  = tunerSeatWaypoint()
  local p        = (wp and wp.pos) or (loc and loc.pos) or { 0, 0, 0 }
  local y        = (wp and wp.yaw) or (loc and loc.yaw) or 0.0
  t.baseX, t.baseY, t.baseZ, t.baseYaw = p[1], p[2], p[3], y
  t.dx, t.dy, t.dz, t.dyaw = 0, 0, 0, 0
  t.prevX, t.prevY, t.prevZ, t.prevYaw = 0, 0, 0, 0
  t.pendingApplyAt = nil
  t.init = true
end

local function tunerCoords()
  local t = JL.tuner
  return t.baseX + t.dx, t.baseY + t.dy, t.baseZ + t.dz, t.baseYaw + t.dyaw
end

local function tunerHere()   -- is idle Jackie present at the tuned venue?
  return JL.idle.spawn and JL.idle.spawn.handle and JL.idle.locationKey == JL.tuner.key
end

-- "Move Jackie here" — WALK-IN re-seat (v1.1, Antonia's design). Get him up out of the chair, walk
-- him a few metres out, then walk him back INTO the exact tuned coordinate and play the sit. NO
-- teleport on a seated puppet (that never took). Collisions off so he can walk into the bar-stool.
-- The state machine + logs live in wanderTick's TUNER WALK-IN block; here we just arm it.
local function tunerApply()
  if not tunerHere() then
    JL.ui.status = "Move ignored: Jackie's not idle here yet — walk up to him first."
    log(("TUNER: Move-here IGNORED — tuner key=%s but idle Jackie locationKey=%s (spawn=%s)."):format(
        tostring(JL.tuner.key), tostring(JL.idle.locationKey), tostring(JL.idle.spawn ~= nil)))
    return false
  end
  local h = JL.idle.spawn.handle
  local x, y, z, yaw   = tunerCoords()
  local wp, loc, seats = tunerSeatWaypoint()
  if not (wp and loc) then return false end
  -- stage the tuned coords onto the seat waypoint (persistence + fallback spot track it)
  wp.pos = { x, y, z }; wp.yaw = yaw
  if #seats <= 1 then loc.pos = { x, y, z }; loc.yaw = yaw end
  local seatVec = Vector4.new(x, y, z, 1.0)
  -- start point: ~2.5 m out FROM the seat toward V, so he walks in from your side (fallback: -X 2.5 m)
  local sx, sy = x - 2.5, y
  local pp = playerPos()
  if pp then
    local dx, dy = pp.x - x, pp.y - y
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 0.3 then sx, sy = x + (dx / len) * 2.5, y + (dy / len) * 2.5 end
  end
  JL.ui.forceVenue = JL.tuner.key                        -- pin him here so scheduleTick can't walk him off mid-tune
  stopWorkspotPose(h)                                    -- get him UP (this works — wander uses the same)
  setNpcCollision(h, false)                              -- collisions OFF so he can walk into the stool
  JL.idle.pendingPose, JL.idle.pendingSit = nil, nil     -- cancel any idle sit that would fight us
  JL.idle.phase = "tuning"                               -- freeze the normal dwell/wander loop
  JL.tuner.walk = { phase = "toStart", startVec = Vector4.new(sx, sy, z, 1.0), seatVec = seatVec,
                    yaw = yaw, poseAnim = wp.poseAnim, deadline = (JL.clock or 0) + 5.0, nextAt = 0 }
  pcall(function() sendMoveToPoint(h, JL.tuner.walk.startVec, "Walk", 0.6) end)
  log(("TUNER: Move-here PRESSED -> walking Jackie in. seat={%.2f,%.2f,%.2f} yaw=%.1f start={%.2f,%.2f}")
      :format(x, y, z, yaw, sx, sy))
  JL.ui.status = "Walking Jackie in to the seat... (watch the CET console / jackie_debug.log)"
  return true
end

-- Commit this seat: live-patch the in-memory config so he keeps sitting right this session, PERSIST
-- it to jl_seats.txt so it survives a reload (v1.1 old-S4 fix), AND print the config-ready line so
-- Antonia can still bake it into config.lua permanently. Updates THIS seat waypoint (key + seatIdx);
-- for a single-seat venue it also moves the anchor pos so his fall-back spot tracks the seat.
local function tunerPrint()
  local x, y, z, yaw = tunerCoords()
  local line = string.format("pos = { %.3f, %.3f, %.3f }, yaw = %.1f", x, y, z, yaw)
  JL.ui.lastCapture = line
  log(("%s seat %d tuned -> %s"):format(JL.tuner.key, JL.tuner.seatIdx, line))
  local wp, loc, seats = tunerSeatWaypoint()
  if wp then wp.pos = { x, y, z }; wp.yaw = yaw end
  if loc and #seats <= 1 then loc.pos = { x, y, z }; loc.yaw = yaw end  -- single-seat venue: anchor tracks it
  jlPersistSeat(JL.tuner.key, JL.tuner.seatIdx, x, y, z, yaw)           -- write-back so it survives a reload
  JL.ui.status = ("Saved %s seat %d — survives reload."):format(JL.tuner.key, JL.tuner.seatIdx)
end

registerForEvent("onDraw", function()
  pcall(drawDialogueBox)                      -- v0.24: the styled choice box draws DURING gameplay
  pcall(drawBlazeFade)                         -- v1.02: fade-to-black overlay draws DURING gameplay (covers HUD, not the ESC menu)
  if not JL.ui.overlayOpen then return end   -- the debug window only draws while the overlay is open
  if not JL.ui.open then return end
  ImGui.Begin("Jackie Lives")

  -- === MAIN INFO (top of window, v1.32) ==================================
  -- Reunion-quest status + the everyday "just unlock it" button, then the live diagnostics.
  ImGui.Text("Reunion quest: ")
  ImGui.SameLine()
  ImGui.TextColored(0.45, 0.85, 1.0, 1.0, Retrieval.stageName())
  -- The one button people actually want, right at the top so it's impossible to miss (only shown
  -- while the mod is still locked). Skips the whole retrieval quest -> Jackie is back, mod unlocked.
  if not Retrieval.isUnlocked() then
    if ImGui.Button("Unlock now — skip the quest, Jackie's back") then Retrieval.completeReunion() end
  end

  if ImGui.CollapsingHeader("Status & diagnostics") then
    local block, hour = currentScheduleBlock()
    ImGui.Text("AMM: " .. (JL.amm and "ok" or "MISSING") ..
               "   Jackie record: " .. (JL.jackie.record and "ok" or "?"))
    local hhmm = hour and string.format("%02d:%02d", math.floor(hour) % 24, math.floor((hour % 1) * 60)) or "?"
    ImGui.Text("Game time: " .. hhmm ..
               "   Day-type: " .. tostring(JL.day.template or "?"))
    if block then
      if block.state == "at_location" then
        local loc = Config.locations[block.locationKey]
        ImGui.Text("Scheduled: " .. (loc and loc.name or block.locationKey) ..
                   ((loc and loc.pos) and "" or "  (coords NOT captured)"))
      else
        ImGui.Text("Scheduled: unavailable (asleep / home / away)")
      end
    end
    ImGui.SameLine()
    if ImGui.Button("Cycle day-type") then          -- DEBUG: jump to the next day-type now
      JL.day.template = nextDayTemplate()
      log("Day-type forced -> " .. tostring(JL.day.template))
    end
    ImGui.Text("Companion: " .. tostring(JL.summon.active) ..
               "   Idle-spawned: " .. tostring(JL.idle.spawn ~= nil))
    if JL.idle.spawn then
      ImGui.Text(("Wander: %s  wp %s/%s   collision: %s"):format(
        tostring(JL.idle.phase or "-"),
        tostring(JL.idle.curIdx or "?"),
        tostring(JL.idle.tgtIdx or "-"),
        JL.idle.collisionOff and "OFF" or "on"))
    end
  end

  -- v0.95 STORY MODE selector (Quiet Life vs Blaze of Glory). Buttons + wrapped description, using
  -- only idioms already proven in this file (Button/Text/SameLine/TextWrapped/TextColored).
  -- The header carries the LIVE mode in its label so you can read it without opening the section.
  if ImGui.CollapsingHeader("Story mode — " .. (JL.mode == "blaze" and "BLAZE OF GLORY" or "QUIET LIFE")) then
    if ImGui.Button("Use Quiet Life") then jlSetMode("quietlife"); JL.ui.blazeConfirm = false end
    ImGui.SameLine()
    -- v1.x SAFETY: clicking here only ARMS Blaze — it does NOT switch mode. The irreversible switch
    -- happens only on the explicit "Yes" in the confirm prompt below (Blaze disables the main plot).
    if ImGui.Button("Use Blaze of Glory") then JL.ui.blazeConfirm = true end
    if JL.mode == "blaze" then
      ImGui.TextColored(1.0, 0.35, 0.2, 1.0, "Blaze of Glory  (EXTREMELY EXPERIMENTAL)")
      ImGui.TextWrapped(BLAZE_DESC)

      -- v0.96 MVP-A: Heist set-piece test controls (spawn Smasher+Goro+VTOL, run the
      -- kill-Smasher -> reach-VTOL -> cut-to-black flow). Positions/records are captured
      -- in-game; paste the console-logged values into blaze.lua M.cfg to make them stick.
      -- The Heist set-piece. It AUTO-STARTS when the start-fact flips (the T-Bug call ends): Smasher at
      -- the elevator -> defeat him -> sky clears -> roof-AV escape -> fade -> you wake at El Coyote Cojo
      -- with a LIVING Jackie. Weather/scene-Jackie/world-unlock are all automatic now; only the manual
      -- override + the diagnose dump are still worth a button. (Dev look-at + weather A/B tools removed —
      -- blazeSetWeather / blazeMuteMusic / Blaze.bound.* are still callable from the CET console.)
      ImGui.Separator()
      ImGui.Text("Blaze set-piece:")
      ImGui.TextWrapped(Blaze.status())
      -- Kill the boss without fighting him: aim at Smasher and press. Still the fastest way to step
      -- through the escape/ending without winning the fight first.
      if ImGui.Button("Defeat target (look at)") then
        local ok = false; pcall(function() ok = Blaze.bound.defeatLookAt and Blaze.bound.defeatLookAt() end)
        JL.ui.status = ok and "Defeated the targeted NPC." or "Aim at an NPC first (see console)."
      end
      -- v1.11: the q005 scene music is fired NATIVELY and can get stuck; a fast-travel/checkpoint reload
      -- black-screens (the live scene holds a world lock). MusicVolume->0 is the only thing that silences
      -- it from CET, so this pair stays as a player-facing rescue.
      if ImGui.Button("Mute ALL music (stuck heist music)") then
        blazeMuteMusic(true); JL.ui.status = "MusicVolume -> 0 (all music off; use Restore to bring it back)."
      end
      ImGui.SameLine()
      if ImGui.Button("Restore music") then
        blazeMuteMusic(false); JL.ui.status = "MusicVolume restored."
      end
      ImGui.TextWrapped("Use a THROWAWAY save. Manual override / testing:")
      if ImGui.Button("Start fight now (override)") then
        local ok, err = pcall(function() Blaze.startYorinobu() end)   -- surface any error to the console
        if ok then JL.ui.status = "Blaze: fight started (experimental)."
        else log("[Blaze] startYorinobu ERROR: " .. tostring(err)); JL.ui.status = "Blaze start ERROR (see console)." end
      end
      ImGui.SameLine()
      if ImGui.Button("DIAGNOSE (why no spawn?)") then
        local ok, err = pcall(function() Blaze.diagnose() end)
        if not ok then log("[Blaze] diagnose ERROR: " .. tostring(err)) end
      end
    elseif JL.ui.blazeConfirm then
      -- v1.x SECOND LAYER: the toggle is armed but not committed. Show the description + a hard
      -- confirm; only "Yes" actually flips to Blaze (jlSetMode). "Cancel" disarms.
      ImGui.TextColored(1.0, 0.35, 0.2, 1.0, "Blaze of Glory  (EXTREMELY EXPERIMENTAL)")
      ImGui.TextWrapped(BLAZE_DESC)
      ImGui.TextColored(1.0, 0.25, 0.15, 1.0, "Are you sure? This DISABLES the main plot and CANNOT be undone.")
      if ImGui.Button("Yes") then jlSetMode("blaze"); JL.ui.blazeConfirm = false; JL.ui.status = "Blaze of Glory ENABLED." end
      ImGui.SameLine()
      if ImGui.Button("Cancel") then JL.ui.blazeConfirm = false end
    else
      ImGui.TextWrapped("Quiet Life: the main story plays out as normal, but Jackie secretly survived and " ..
        "returns as a living Heywood NPC. Less invasive -- but Jackie can only join SIDE jobs, never the " ..
        "main plot.")

      -- v1.32: mourning suppression, minimal — just the two persisted settings + status. (The long
      -- help text and the dev Preview/Apply buttons were removed; ticking a box already applies it
      -- next tick via JL.mourningTimer. jlMourningApply still exists if we need it from the console.)
      ImGui.Separator()
      ImGui.Text("Mourning content:")
      ImGui.SameLine()
      ImGui.TextColored(0.6, 0.8, 1.0, 1.0, jlMourningStatus())
      local newVal = ImGui.Checkbox("Suppress 'Jackie is dead' grief (ofrenda / condolence calls)", JL.mourningSuppress)
      if newVal ~= JL.mourningSuppress then JL.mourningSuppress = newVal; jlSaveSettings(); JL.mourningTimer = 999 end  -- fire next tick
      local barVal = ImGui.Checkbox("Keep El Coyote / Mama's bar OPEN", JL.keepBarOpen)
      if barVal ~= JL.keepBarOpen then JL.keepBarOpen = barVal; jlSaveSettings(); JL.mourningTimer = 999 end
    end
  end

  if ImGui.CollapsingHeader("Companion — summon & dismiss") then
    if ImGui.Button("Summon Jackie (companion)") then summonJackie() end
    ImGui.SameLine()
    if ImGui.Button("Dismiss Jackie") then dismissJackie() end
  end

  -- v1.57 MOVEMENT TUNER. Was three sliders that reset on every reload; now every knob that shapes how
  -- Jackie moves with V is here, and "Save" writes them to jl_walk.txt so they survive (jlLoadWalk on
  -- onInit re-applies them over config.lua's baked defaults). Everything is LIVE the instant you drag it.
  -- Read the live line FIRST — it tells you which system currently owns him, so you know which group of
  -- sliders is even doing anything right now.
  if ImGui.CollapsingHeader("Movement tuning (walk beside / stand still)") then
    do
      local still = jlVLoitering()        -- ask FIRST: this is what refreshes the frame's speed EMA
      local vsp   = JL.abreast.vSpeed or 0.0
      ImGui.Text(("Live: V %.2f m/s  |  %s"):format(vsp,
        still and "V STANDING -> Jackie holds position"
          or ((not JL.customWalk) and "trailing (walk-beside OFF)"
          or (jlAbreastOn() and ((JL.abreast.catching == true) and "abreast: SPRINT (fell behind)" or "abreast: walk (free)")
          or "trailing (abreast stood down)"))))
      ImGui.Text(("Live: %s | %s"):format(
        jlVertical() and "STAIRS/SLOPE -> trailing" or "flat ground",
        jlVSneaking() and "V SNEAKING -> shadowing" or "V upright"))
    end
    ImGui.Separator()
    ImGui.TextWrapped("Drag to feel it change immediately. Press SAVE to keep it across reloads — " ..
      "otherwise config.lua's defaults come back next time the mod loads. The 'stand still' group works " ..
      "in BOTH follow modes; the rest only applies while 'Walk beside me' is ON.")
    if ImGui.Button("SAVE walk tuning") then
      JL.ui.status = jlSaveWalk() and "Walk tuning saved (survives reloads)." or "Could not write jl_walk.txt (see console)."
    end
    ImGui.SameLine()
    if ImGui.Button("Reset to config defaults") then
      jlResetWalk(); JL.ui.status = "Walk tuning file cleared — reload the mod to get the defaults back."
    end
    for _, d in ipairs(JL_WALK_BOOLS) do
      local tbl = Config[d.t]
      if tbl then tbl[d.k] = ImGui.Checkbox(d.label, tbl[d.k] and true or false) end
    end
    for _, d in ipairs(JL_WALK_KEYS) do
      local tbl = Config[d.t]
      if tbl then tbl[d.k] = ImGui.SliderFloat(d.label, tbl[d.k] or d.lo, d.lo, d.hi) end
    end
  end

  -- v1.47 MVP: prove AIFollowerTakedownCommand actually works from Lua before anything is built on it.
  -- No CET mod is known to construct this command, so it is unproven — this button is the experiment.
  -- Aim at an UNAWARE enemy (the grapple that plays is a stealth takedown) and press it.
  if ImGui.CollapsingHeader("Follower takedown (experimental)") then
    ImGui.TextWrapped("Aim at an unaware enemy and press. Jackie must already be your companion. This is the " ..
      "same AI command The Heist uses for his parallel takedown. If he grapples the target, the automatic " ..
      "'V takes one, Jackie takes the other' behaviour can be built on top of it.")
    if ImGui.Button("TEST: Jackie takedown (look at)") then
      local ok, msg = jlTakedownLookAt()
      JL.ui.status = (ok and "" or "Takedown refused: ") .. tostring(msg)
      log("Takedown (look-at test): " .. tostring(msg))
    end
  end

  -- v0.50: TWO arrival modes only — toggle FOOT <-> BIKE, live. Pick one, then Call Jackie (or hit
  -- "Test arrival now"). Both spawn via DES out at distance and share the sprint -> walk -> companion tail.
  if ImGui.CollapsingHeader("Arrival & main-quest gate") then
    local cc = Config.call
    local bikeOn = (cc.arrivalMethod == "bike")
    if ImGui.Button("Arrival method: " .. (bikeOn and "BIKE (ride in on his Arch)" or "FOOT (sprint -> walk in)")) then
      cc.arrivalMethod = bikeOn and "foot" or "bike"
      log("Arrival method -> " .. cc.arrivalMethod)
    end
    ImGui.SameLine()
    if ImGui.Button("Test arrival now") then
      -- fire the selected arrival immediately, no call needed (mirrors runCallAction's summon_arrival)
      if isMainQuestActive() then jlDeclineMainQuest()   -- v0.93: same blue notice the player gets
      elseif JL.summon.active then JL.ui.status = "Jackie's already with you."
      else
        JL.varrival.at = (JL.clock or 0) + 0.2; JL.varrival.useBike = (cc.arrivalMethod == "bike")
        JL.ui.status = ("Testing %s arrival..."):format(cc.arrivalMethod == "bike" and "BIKE" or "FOOT")
        log(("TEST: %s arrival armed."):format(cc.arrivalMethod == "bike" and "BIKE" or "FOOT"))
      end
    end
    -- DEBUG: pretend a main quest is active so you can test Jackie declining / excusing himself.
    JL.ui.forceMainQuest = ImGui.Checkbox("Force main-quest active (test decline)", JL.ui.forceMainQuest)
    ImGui.Text("Main quest detected: " .. (isMainQuestActive() and "YES (Jackie won't follow)" or "no"))
    ImGui.Text("In cutscene (tier>=4): " .. (jlInCutscene() and "YES (Jackie leaves)" or "no"))
  end

  -- v1.33 phone hijack. The mode contest is SETTLED — 'alive' won and is the default, so the mode
  -- picker, the delay/ring knobs and the raw single-phase buttons are gone (jlCallFix().mode and
  -- triggerNativeCall() are still there if a future experiment needs them from the console).
  -- What's left: is the hijack live right now, and one button to watch the whole alive call.
  if ImGui.CollapsingHeader("Phone call (Jackie answers alive)") then
    local cf = jlCallFix()
    -- The hijack only fires once the quest is "reachable" (shard read / reunited). Still seeing the DEAD
    -- card + voicemail? It's almost always a pre-shard stage OR Jackie being summoned/asleep. Watch
    -- jackie_debug.log for the [Hijack] lines.
    local reach = Retrieval.isUnlocked() or Retrieval.isAwaitingCall()
    ImGui.Text("Reunion stage: ")
    ImGui.SameLine(); ImGui.TextColored(0.45, 0.85, 1.0, 1.0, Retrieval.stageName())
    ImGui.Text("Phone hijack active: " .. ((reach or cf.forceHijack) and "YES (alive swap)" or "no — vanilla disconnected plays"))
    cf.forceHijack = ImGui.Checkbox("Force hijack even pre-shard (test the alive swap now)", cf.forceHijack and true or false)
    if ImGui.Button(">> Test full ALIVE call (with dialogue)") then jlStartAliveCall() end
    ImGui.TextWrapped("Rings, connects the see-through holo, then runs the branching call dialogue — " ..
      "exactly what happens when you phone Jackie from the in-game phone.")
  end

  -- v1.32: minimal reunion-quest DEV jumps (the everyday "Unlock now" button lives up top with the
  -- status). All the call-flow / bike-cruise / reunion-beats / shard TEST controls were removed.
  if ImGui.CollapsingHeader("Reunion quest — dev jumps") then
    ImGui.Text("Stage: " .. Retrieval.stageName())
    if ImGui.Button("Complete quest now (Jackie is back)") then Retrieval.completeReunion() end
    if ImGui.Button("Force tip (skip Vik)") then Retrieval.forceTip() end
    ImGui.SameLine(); if ImGui.Button("Force shard read") then Retrieval.forceShard() end
    if ImGui.Button("Reset to LOCKED") then Retrieval.reset() end
  end


  -- v1.55: position capture + the Reverend Flash easter egg. The egg is testable WITHOUT the real
  -- coords — "Fire now" ignores position entirely. To arm it for real: stand in the bar, hit "Capture
  -- current position", paste the x/y/z into Config.revflash.pos, set Config.revflash.enabled = true.
  if ImGui.CollapsingHeader("Position capture & easter egg") then
    if ImGui.Button("Capture current position") then capturePosition() end
    if JL.ui.lastCapture then
      ImGui.Text("Last capture (also in console — copy into config.lua):")
      ImGui.TextWrapped(JL.ui.lastCapture)
    end
    ImGui.Separator()
    local K = Config.revflash or {}
    ImGui.Text(("Reverend Flash easter egg: %s  (%d eddies + the Arch)")
               :format(K.enabled and "ARMED" or "off — needs the bar's coords", K.eddies or 0))
    if ImGui.Button("Fire Reverend Flash egg now (ignores coords)") then pcall(function() Retrieval.debugRevflash() end) end
    ImGui.SameLine()
    if ImGui.Button("Re-arm Reverend Flash egg") then pcall(function() Retrieval.resetRevflash() end) end
  end

  -- Consolidated "spots" tuning — idle collision, force-venue and the seat tuner, all in one place.
  if ImGui.CollapsingHeader("Jackie's spots fine tuning") then

    -- MASTER flip switch — collision off for idle Jackie's whole stay (so chairs/stalls can't block him).
    do
      local prev = Config.idleNoCollision
      Config.idleNoCollision = ImGui.Checkbox("Idle Jackie: collisions OFF (no chair-blocking)", Config.idleNoCollision and true or false)
      if Config.idleNoCollision ~= prev then
        applyIdleCollision()
        log("Idle collision master -> " .. (Config.idleNoCollision and "OFF (no collision)" or "ON (normal collision)"))
      end
    end
    do
      local setting = Config.idleNoCollision and "OFF" or "ON"
      local live
      if JL.dinner.collisionOff then
        live = "OFF — dinner seat (companion)"
      elseif JL.idle.spawn then
        live = JL.idle.collisionOff and "OFF — deactivated ✓" or "ON"
      else
        live = "— (no idle Jackie spawned yet)"
      end
      ImGui.Text(("Collision  setting: %s   |   live on Jackie: %s"):format(setting, live))
    end

    -- Force his schedule to a venue so you can go observe him (overrides time + secret).
    ImGui.Separator()
    ImGui.Text("Force venue:  " .. (JL.ui.forceVenue and ("-> " .. tostring(JL.ui.forceVenue)) or "OFF (following schedule)"))
    local venueKeys = { "noodle", "misty", "coyote", "afterlife", "ginger", "redwood", "lizzies", "secret", "test" }
    local perRow = 4
    for i, k in ipairs(venueKeys) do
      local loc = Config.locations[k]
      if loc then
        if ((i - 1) % perRow) ~= 0 then ImGui.SameLine() end
        local lbl = (loc.name or k) .. (JL.ui.forceVenue == k and " *" or "")
        if ImGui.Button(lbl .. "##fv_" .. k) then
          JL.ui.forceVenue = k
          log("Force venue -> " .. k .. " (go to " .. (loc.name or k) .. " to see him; overrides time).")
        end
      end
    end
    if ImGui.Button("Clear force (resume schedule)") then JL.ui.forceVenue = nil; log("Force venue cleared.") end

    -- v0.43 SEAT TUNER (v0.45: any venue + multi-seat): slide a seat until perfect, print for config.lua.
    ImGui.Separator()
    -- BUILD STAMP: confirm the deployed build actually loaded. If this doesn't say WALK-IN, the game
    -- had the mod files locked during deploy (deploy with the game CLOSED, then reload).
    ImGui.TextColored(0.45, 0.85, 1.0, 1.0, "Seat tuner build: v" .. tostring(Config.version) .. " (WALK-IN)")
    if not JL.tuner.init then tunerInit() end
    local t = JL.tuner

    -- v1.1: AUTO-POINT the tuner at the venue where idle Jackie ACTUALLY is, so you can just walk up to
    -- him and tune — no need to click the venue first (that trap gave "pick the venue, then walk over"
    -- even while you were staring right at him). Only adopts when he's SETTLED at a sit-capable venue,
    -- not while he's still walking to a venue you force-picked (locationKey != the forceVenue target).
    if JL.idle.spawn and JL.idle.spawn.handle and JL.idle.locationKey then
      local enroute = JL.ui.forceVenue and (JL.idle.locationKey ~= JL.ui.forceVenue)
      local hisLoc  = Config.locations[JL.idle.locationKey]
      if not enroute and JL.idle.locationKey ~= t.key
         and hisLoc and #tunerSitWaypoints(hisLoc) > 0 then
        t.key, t.seatIdx = JL.idle.locationKey, 1
        tunerInit()
      end
    end

    -- LOCATION picker — only venues that have a sit waypoint. Picking one also Force-venues Jackie there.
    ImGui.Text("Venue:")
    local venues = tunerSitVenues()
    for i, k in ipairs(venues) do
      if ((i - 1) % 4) ~= 0 then ImGui.SameLine() end
      local loc = Config.locations[k]
      if ImGui.Button(((loc and loc.name or k) .. (k == t.key and " *" or "")) .. "##tv_" .. k) then
        t.key, t.seatIdx = k, 1
        JL.ui.forceVenue = k                 -- send Jackie there so you can tune him on the spot
        tunerInit()
        log("Tuner -> " .. k .. " (Force venue set; go to " .. (loc and loc.name or k) .. ").")
      end
    end

    -- SEAT picker — only when this venue has more than one stool/chair.
    local _, _, seats = tunerSeatWaypoint()
    if seats and #seats > 1 then
      if ImGui.Button("< prev seat") then t.seatIdx = ((t.seatIdx - 2) % #seats) + 1; tunerInit() end
      ImGui.SameLine()
      if ImGui.Button("next seat >") then t.seatIdx = (t.seatIdx % #seats) + 1; tunerInit() end
      ImGui.SameLine(); ImGui.Text(("seat %d / %d"):format(t.seatIdx, #seats))
    end

    local here = tunerHere()
    ImGui.TextWrapped(here
      and ("Jackie is here — slide and he re-seats live (he blinks out/in each time — that's the " ..
           "respawn that guarantees he actually moves). Editing " .. t.key .. " seat " .. t.seatIdx .. ".")
      or  ((JL.idle.spawn and JL.idle.spawn.handle)
           and ("Jackie's still heading to " .. t.key .. " — walk over once he's settled on the seat.")
           or  "No idle Jackie nearby yet. Get within range of his venue (or Force-pick one above), then walk up to him."))
    ImGui.TextWrapped("Offsets from the captured seat. X/Y/Z = position (metres); YAW spins him to the " ..
                      "right seat angle (his facing is now forced from this, so it's the same no matter " ..
                      "which way he walked in). Yaw range is wider so you can flip him fully around.")
    t.dx   = ImGui.SliderFloat("X offset (m)",          t.dx,   -3.0, 3.0)
    t.dz   = ImGui.SliderFloat("Z offset — up/down (m)", t.dz,   -2.0, 2.0)
    t.dy   = ImGui.SliderFloat("Y offset (m)",          t.dy,   -3.0, 3.0)
    t.dyaw = ImGui.SliderFloat("Yaw offset (deg)",      t.dyaw, -180.0, 180.0)
    -- fine nudges for the two axes you care about
    if ImGui.Button("X -0.02") then t.dx = t.dx - 0.02 end ImGui.SameLine()
    if ImGui.Button("X +0.02") then t.dx = t.dx + 0.02 end ImGui.SameLine()
    if ImGui.Button("Z -0.02") then t.dz = t.dz - 0.02 end ImGui.SameLine()
    if ImGui.Button("Z +0.02") then t.dz = t.dz + 0.02 end
    local x, y, z, yaw = tunerCoords()
    ImGui.Text(string.format("Working coords: { %.3f, %.3f, %.3f }  yaw %.1f", x, y, z, yaw))

    -- Live re-seat RETIRED (it never took): slide freely, then press "Move Jackie here" to WALK him in.
    ImGui.TextWrapped("Slide to set the target, then press Move Jackie here — he gets up, walks in, and " ..
                      "sits at the exact spot. Redo as often as you like.")

    if ImGui.Button("Move Jackie here (walk in + sit)") then tunerApply() end
    ImGui.SameLine()
    if ImGui.Button("Reset offsets") then t.dx, t.dy, t.dz, t.dyaw = 0, 0, 0, 0 end
    ImGui.SameLine()
    if ImGui.Button("Save seat (survives reload)") then tunerPrint() end
    ImGui.TextWrapped("Saves this seat to jl_seats.txt so it sticks after a reload AND applies now. " ..
                      "The same line is printed to the console + the 'Last capture' box above — tell me " ..
                      "the numbers and I'll also bake them into config.lua permanently.")
  end

  ImGui.Separator()
  if JL.ui.status ~= "" then ImGui.TextWrapped("> " .. JL.ui.status) end

  ImGui.End()
end)

registerForEvent("onShutdown", function()
  pcall(closeNativeCallWindow)   -- never leave a holocall window stuck open
  pcall(hideJackieChoiceBox)
  pcall(hideSubtitle)
  pcall(jlLookAtStop)            -- v1.41: never leave a look-at overlay on a puppet we're about to drop
  pcall(clearIdle)
  pcall(clearVehicleArrival)     -- v0.34: never orphan the arrival bike
  pcall(bikeTestDespawn)         -- v0.63: never orphan the bike-model test spawn
  pcall(clearDinnerWaypoint)     -- v0.41: never leave a dinner map pin stuck
  pcall(function() if jlCruise and jlCruise.active then jlCruiseStop() end end)  -- v0.92: never orphan the cruise Arch
  -- v1.41: aiBikeKnockOffModifier is a GLOBAL TweakDB flat. Force it back to the captured original on
  -- unload regardless of what the ref-count believes — a mod reload mid-ride must not leave every NPC
  -- biker in Night City unknockable for the rest of the session.
  pcall(function()
    if type(JL.knockOrig) == "number" then
      TweakDB:SetFlat("AIGeneralSettings.aiBikeKnockOffModifier", JL.knockOrig)
      log(("Shutdown: knock-off modifier restored to %.1f."):format(JL.knockOrig))
    end
    JL.knockRefs = 0
  end)
  pcall(dismissJackie)
end)

registerHotkey("jl_summon",  "Summon Jackie",            function() summonJackie() end)
registerHotkey("jl_call",    "Call Jackie (holocall)",   function() startCall() end)
registerHotkey("jl_dismiss", "Dismiss Jackie",           function() dismissJackie() end)
registerHotkey("jl_capture", "Capture position",         function() capturePosition() end)
registerHotkey("jl_toggle",  "Show/Hide Jackie window",  function() JL.ui.open = not JL.ui.open end)
registerHotkey("jl_diag",    "Jackie diagnostics",       function() diagnostics() end)

-- Bind a key in CET -> Bindings for this. Look at Jackie + press it -> he talks.
-- (Fallback key; CET can't bind F, so Antonia used "=". The OnAction hook below ALSO
--  gives the real in-game Interact key (F) for free - see setupInteractHook.)
registerInput("jl_talk", "Talk to Jackie (look at him)", function(isDown) if isDown then talkToJackie() end end)

-- v0.42: the "-" cycle-choice fallback (jl_cycle_choice) is REMOVED. Arrow ↑/↓ now navigate the
-- choice box on every layer (release-edge handling in setupInteractHook), so the manual binding is
-- no longer needed. F still confirms the highlighted option.
