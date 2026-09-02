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
pcall(function() package.loaded["lang"] = nil; package.loaded["translations"] = nil end)  -- like blaze: re-read on CET soft-reload so a language/text edit takes effect
Lang      = require("lang")        -- v1.60 GLOBAL (200-cap): localization; Lang.t(s) at the text chokepoints (see lang.lua + translations.lua)
pcall(function() package.loaded["dialogui"] = nil end)   -- re-read on CET soft-reload, like blaze/lang
DialogUI  = require("dialogui")    -- v1.63 GLOBAL (200-cap): V's choices in the GAME's own dialogue widget (see dialogui.lua)
Allies    = require("nca")         -- OPTIONAL Night City Allies bridge (see nca.lua + NCLucy's
                                   -- docs/research/nca_integration.md). GLOBAL for the 200-local cap.
                                   -- Does nothing unless NCA is installed, which is the normal case.
pcall(function() package.loaded["zengine"] = nil end)     -- re-read on CET soft-reload, like blaze/lang
ZEngine   = require("zengine")     -- OPTIONAL 0-Engine integration (see zengine.lua + NCLives'
                                   -- docs/research/zero_engine.md). GLOBAL for the 200-local cap —
                                   -- ⚠️ this file is AT Lua's 200-local ceiling, so never make it a
                                   -- `local`. Automatic: if 0-Engine is installed we take its
                                   -- once-per-frame state instead of polling the same blackboard
                                   -- again; if it isn't, every reader falls back to ours and nothing
                                   -- changes. No user switch.
Fam       = require("familiarity") -- v1.65 GLOBAL (200-cap): Jackie opens up over time (see familiarity.lua)
pcall(function() package.loaded["vo"] = nil; package.loaded["vo_durations"] = nil end)  -- re-read on CET soft-reload, like blaze/lang
VO        = require("vo")          -- v1.66 GLOBAL (200-cap): the game's OWN voice-over, no shipped audio (see vo.lua)
Native    = require("native")      -- v1.67 GLOBAL (200-cap): the follower role done the engine's way (see native.lua)
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
  -- v1.59 lastDist/graceSince back the progress grace: lastDist is the previous check's gap (is it closing?),
  -- graceSince caps how long "he's still closing" may keep deferring the rescue.
  catchUp = { farSince = nil, lastAt = nil, teleTries = nil, lastDist = nil, graceSince = nil },
  -- v1.61 weapon mirror: since = when V first went unarmed+calm this episode; reasserts = holster tries so
  -- far; lastAt = throttle. Reset whenever V draws again or combat starts.
  weaponMirror = { since = nil, reasserts = nil, lastAt = nil },
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
  -- v1.62 paused: talking to him mid-walk-off halts the retreat (leavingTick skips re-issuing) until
  -- the conversation resolves — resume() clears it, dinner/accept leaves it cleared for good.
  leaving = { phase = nil, deadline = nil, lastReissue = 0, paused = false },
  -- v1.62 main-quest GRACE: when a main quest goes active he WARNS and waits Config.mainExitGrace.seconds
  -- instead of leaving at once; if V drops it he stays. activeSince = when main FIRST went active this
  -- episode (debounces a transient auto-track before we warn); until_ = real-clock leave deadline;
  -- warned/reminded gate the one-shot beats.
  mainExit = { activeSince = nil, until_ = nil, warned = false, reminded = false },
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

-- v1.8.3 OFFLINE TEST HOOK. `JL` is a file-local, which is correct for the mod and is also why
-- tools/loadsim.lua here is a fraction of the size of NCLives' — that harness reaches the state table
-- through `NCL.env.NCS` and can therefore drive the actual state machines (catch-up, respawn, the
-- appearance verify); this one could only ever call functions with no state behind them. NCLives has
-- twice shipped a bug that its own tests caught and this repo's could not even express, so: one global
-- alias to the SAME table. No copy, no behaviour, no local slot spent.
JL_ENV = JL


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

-- v1.56 BLAZE: print the CURRENT difficulty and the Smasher tuning row it selects. Type `blazeDifficulty()`
-- in the CET console, change the difficulty in Settings > Gameplay, and run it again — that empirically
-- settles the enum-name-vs-menu-label mapping documented on Blaze.bound.difficulty, which is inferred from
-- the decompiled scripts rather than observed. If the menu label and the row below ever disagree, re-key
-- Blaze.yori.diffScale to whatever this prints; nothing else needs to change.
-- Global (no top-level local) -> 200-local cap safe.
function blazeDifficulty()
  local name = (Blaze and Blaze.bound and Blaze.bound.difficulty) and Blaze.bound.difficulty() or nil
  local row  = name and Blaze.yori.diffScale[name] or nil
  if not name then
    log("[Blaze] difficulty: COULD NOT READ it (StatsDataSystem missing or the enum didn't unwrap).")
  elseif not row then
    log("[Blaze] difficulty enum = '" .. tostring(name) .. "' -> NO matching diffScale row! " ..
        "Add that key to Blaze.yori.diffScale; the fight is falling back to the '" ..
        tostring(Blaze.yori.diffScaleFallback) .. "' tier.")
  else
    log(string.format("[Blaze] difficulty enum = '%s' -> Smasher Health x%.2f, damage x%.2f, %d Arasaka add(s). " ..
                      "Check that against the label in Settings > Gameplay.",
                      name, row.hp or 1.0, row.dmg or 1.0, row.adds or 0))
  end
  return name
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
  -- Night City Allies bridge, one line. When the Talk row is missing from their menu this is
  -- the line that says WHICH of the four things went wrong: not installed, never attached,
  -- attached but our row got dropped by their loader, or attached and present (so the problem
  -- is the per-npc condition instead).
  -- Night City Allies bridge: the FULL probe, not a summary. When the Talk row is missing this
  -- prints their whole interaction list with each row's condition evaluated against the npc
  -- their menu is currently open on — which separates "we were never added" from "we were
  -- added and their renderer rejected our condition". Open their menu on the companion first,
  -- then press Diagnostics.
  pcall(function() for _, l in ipairs(Allies.probe()) do log(l) end end)
  -- 0-Engine: ONE line here, not the full probe (the panel button writes that). It belongs in every
  -- bug report because it changes where a stale scene-tier answer could have come from — theirs or
  -- ours — and that is the first fork in diagnosing "Jackie froze mid-cutscene" from a user's log.
  pcall(function() log(ZEngine.status()) end)
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
-- v1.68 WHICH BACKEND? — and why AMM is still here
-- ---------------------------------------------------------------------------
-- AMM stopped being REQUIRED in v1.68 (before it, summoning without it failed outright with "AMM
-- Spawn module not available"). It is deliberately still SUPPORTED: a player already running AMM,
-- with a Jackie who behaves the way they expect, should not be moved onto a different code path by
-- an update they didn't ask for. Esc -> Settings -> JackieLives -> Compatibility.
--
-- Answers false unless the player asked for AMM *and* AMM is actually there — so the toggle can never
-- strand someone who turns it on and then uninstalls AMM. It says so once when that happens.
-- GLOBAL, not a top-level local: init.lua is at Lua's 200-local cap.
function jlUseAMM()
  if not JL.useAMM then return false end
  local amm = getAMM()
  if amm and amm.Spawn and amm.Spawn.NewSpawn then return true end
  if not JL.ammMissingWarned then
    JL.ammMissingWarned = true
    log("Spawn backend: AMM is selected but not installed — using the native backend instead. " ..
        "(Turn the switch off in Esc -> Settings -> JackieLives to stop seeing this.)")
  end
  return false
end

-- Make a resolved body a real companion, on whichever backend the player chose. The follower role is
-- the thing that makes enemies ignore him and the minimap symbol appear — see native.lua's header.
-- Either way jlFollowerWatchTick VERIFIES the result against the engine, so a backend that quietly
-- fails to apply the role is caught rather than shipped.
function jlMakeCompanion(h)
  if not h then return false end
  if jlUseAMM() then
    local amm, ok = getAMM(), false
    pcall(function()
      if amm and amm.Spawn and amm.Spawn.SetNPCAsCompanion then
        amm.Spawn:SetNPCAsCompanion(h); ok = true
      end
    end)
    if ok then return true end
    log("Spawn backend: AMM's SetNPCAsCompanion was unavailable — falling back to the native role.")
  end
  return Native.setCompanion(h)
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
  if not resolveJackieRecord() then return nil, "Jackie record not found" end
  local recStr = tostring(JL.jackie.record)
  -- Fall back to a REAL appearance name, never "random": an unknown name is a silent no-op (leaving him in
  -- whatever he had), and AMM's random-cycle path would put him in a different outfit every spawn.
  local app = (appearance and appearance ~= "") and appearance or (Config.defaultAppearance or "jackie_welles_default")
  -- v1.68 — TWO BACKENDS, AND THE PLAYER PICKS. The old path was `amm.Spawn:NewSpawn` +
  -- `amm.Spawn:SpawnNPC`, and without AMM installed it failed right here with "AMM Spawn module not
  -- available" — Jackie simply could not be summoned. AMM's SpawnNPC is itself just
  -- `DynamicEntitySystem:CreateEntity` 1 m in front of V (Modules/spawn.lua:582), so the native path
  -- is the same spawn minus the dependency.
  --
  -- The AMM path is KEPT, not replaced: someone who already runs AMM and is happy with how Jackie
  -- behaves shouldn't be moved onto new code by an update. Esc -> Settings -> JackieLives -> "Use AMM
  -- for spawning". Default OFF (native), because that is the one that works for everybody.
  if jlUseAMM() then
    local amm = getAMM()
    -- Force AMM's companion toggle to MATCH the flag. It was only ever set TRUE (for companion
    -- spawns) and never reset, so a "passive" arrival spawn following any companion summon still
    -- came out as a companion -> follower role -> catch-up TELEPORT to V's face.
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
    spawn.companionFlag = companionFlag
    Session.stamp(spawn)
    if companionFlag == 1 then JL.summon.appearance = app end
    return spawn
  end

  -- NATIVE (default). Appearance rides on the spec instead of being applied afterwards through AMM's
  -- ChangeAppearanceTo — a better order: there is no window where the body wears the wrong clothes.
  --
  -- The returned shape is `{ id = <EntityID>, handle = nil }`. resolveJackieHandle() already resolves
  -- that shape (the vehicle-arrival Jackie has always been a DES spawn), so nothing downstream
  -- changed — EXCEPT the promote path, which used to wait for a `.handle` only AMM ever wrote. See
  -- the note there; missing it is what cost NCLives a release (their v1.64 respawn loop).
  --
  -- companionFlag is no longer a spawn parameter: there is no AMM user setting to flip. The follower
  -- role is applied AFTER the body resolves, by promoteToCompanion / the promote block. That is an
  -- improvement, not just a port — the old code set `amm.userSettings.spawnAsCompanion` and hoped,
  -- which is how a "passive" arrival spawn came out as a follower and teleported to V's face.
  Session.mark("Native spawn " .. tostring(app))
  local spawn, serr = Native.spawn(recStr, nil, nil, "JackieLives_jackie", app)
  Session.clear()
  if not spawn then return nil, serr or "native spawn failed" end
  spawn.companionFlag = companionFlag
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

-- ===========================================================================
-- v1.77 THE NAKED COMPANION — re-assert the outfit after the body exists
-- ===========================================================================
-- Antonia, 2026-08-17: *"I often saw Kerry spawn naked."*
--
-- The appearance rides on the spawn spec (`Native.spawn` -> `spec.appearanceName`), which is the
-- right place for it and usually works. But it is a REQUEST, not a guarantee: the appearance's
-- garment meshes have to be streamed in, and a body built before they are resident renders with the
-- meshes it has — which, on a character with a big wardrobe, is the bare body. That is why this is
-- intermittent ("often", not "always") and why it picks on some characters and not others.
--
-- AMM never relied on the spec. It applies the appearance AFTER the body exists, and it PREFETCHES
-- first: `PrefetchAppearanceChange` then `ScheduleAppearanceChange`
-- (reference_mods/Appearance Menu Mod-790-2-12-5-1749642728/.../AppearanceMenuMod/init.lua:5268,
-- reached from Modules/spawn.lua's `AMM:ChangeAppearanceTo`). We now do BOTH: keep the spec, and
-- re-assert AMM-style once the handle resolves — then VERIFY and repeat until the engine agrees.
--
-- ⚠️ The read-back is the point, not a nicety. An unknown appearance name is a SILENT no-op in this
-- engine, so "wrong name" and "lost streaming race" look identical in game and identical in the log.
-- `GetCurrentAppearanceName()` is what tells them apart, and the warning below is what a future bug
-- report needs to be answerable at all.
--
-- ⚠️ Two naming levels, and the read-back may report either. An entity template declares appearance
-- names like `kerry_eurodyne_kerry_eurodyne_old`, each pointing at an appearance INSIDE the .app,
-- which is named `kerry_eurodyne_old` (verified on the local install: the .ent carries both). AMM's
-- menu shows the template name, which is what the roster stores and what we ask for. So a read-back
-- of the shorter .app name means SUCCESS, not failure — hence the substring match rather than `==`.
JL_APPFIX_WINDOW = 8.0   -- seconds we keep verifying after the body resolves
JL_APPFIX_TRIES  = 4     -- re-asserts before we give up and warn

-- v1.8.3: the readable name out of a CName. `tostring` on a CName gives the whole struct —
-- `ToCName{ hash_lo = 0x..., hash_hi = 0x... --[[ jackie_welles_default --]] }` — so anything that
-- compares a CName read-back to a plain string is comparing against that, and fails forever. The name
-- is only inside the `--[[ ... --]]` comment. (NCLives has this as `NCL.recordPath` in ncl.lua; this
-- repo has no ncl.lua, so it lives here.) Global -> 200-local cap safe.
function jlCNameName(v)
  local s; pcall(function() s = tostring(v) end)
  if type(s) ~= "string" or s == "" then return nil end
  return s:match("%-%-%[%[%s*(.-)%s*%-%-%]%]") or s
end

-- Arm the verify/re-assert loop for a freshly resolved body. `sp.appearance` is stamped by ammSpawn
-- with the RESOLVED name (so a nil arg records "default" and still reads back correctly).
function jlArmAppearanceFix(h, sp, why)
  if not (h and sp) then return false end
  local want = sp.appearance
  if not want or want == "" or want == "default" then return false end
  JL.appfix = { handle = h, want = want, why = why or "spawn", tries = 0, nextAt = 0,
                 until_ = (JL.clock or 0) + (JL_APPFIX_WINDOW or 8.0) }
  return true
end

-- Stepped from onUpdate. Costs one native read per second for a few seconds after a spawn, then nils
-- itself — it is not a standing per-frame cost.
function jlAppearanceTick()
  local A = JL.appfix
  if not (A and A.handle and A.want) then return end
  local now = JL.clock or 0
  if now < (A.nextAt or 0) then return end
  A.nextAt = now + 1.0

  -- ⚠️ v1.8.3 (ported from NCLives v1.83) — THIS READ-BACK COULD NEVER MATCH.
  -- GetCurrentAppearanceName() returns a CName, and `tostring` on a CName is not the name — it is the
  -- whole struct: `ToCName{ hash_lo = 0x..., hash_hi = 0x... --[[ jackie_welles_default --]] }`.
  -- Comparing THAT against 'jackie_welles_default' is false forever, so every spawn re-asserted four
  -- times and then logged "⚠ APPEARANCE NOT APPLIED" — including the ones wearing exactly the right
  -- body. A diagnostic that cries wolf on every spawn is worse than none: in NCLives it hid a companion
  -- who really WAS undressed for weeks. The readable name lives in the `--[[ ... --]]` comment.
  local cur
  pcall(function() cur = jlCNameName(A.handle:GetCurrentAppearanceName()) end)
  -- Success = the engine reports the name we asked for, OR the .app-level name it maps to (see the
  -- two-naming-levels note above). `cur` is the shorter of the pair, so it is the needle.
  if cur and cur ~= "" and cur ~= "None"
     and (cur == A.want or (#cur >= 4 and A.want:find(cur, 1, true) ~= nil)) then
    log(("Appearance OK: wearing '%s' (%s; %d re-assert(s))."):format(tostring(cur), tostring(A.why), A.tries or 0))
    JL.appfix = nil
    return
  end

  if now >= (A.until_ or 0) or (A.tries or 0) >= (JL_APPFIX_TRIES or 4) then
    log(("⚠ APPEARANCE NOT APPLIED: asked for '%s', the body reports '%s' after %d attempt(s). "
      .. "An unknown appearance name no-ops silently — check it against AMM's list for this record "
      .. "(config.lua `Config.defaultAppearance` / the venue `appearance`). This is what a naked companion looks like in the log.")
      :format(tostring(A.want), tostring(cur), A.tries or 0))
    JL.appfix = nil
    return
  end

  A.tries = (A.tries or 0) + 1
  -- PREFETCH FIRST. Scheduling a change whose meshes are not loaded is exactly the race we are here
  -- to lose less often; this is the half our spec-based path never had.
  pcall(function() A.handle:PrefetchAppearanceChange(CName.new(A.want)) end)
  pcall(function() A.handle:ScheduleAppearanceChange(CName.new(A.want)) end)
  log(("Appearance re-assert %d/%d: '%s' (body reported '%s')."):format(
      A.tries, (JL_APPFIX_TRIES or 4), A.want, tostring(cur)))
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

-- v1.8.2 SEND-OFF -> IDLE COOLDOWN. Stamp "the schedule may not put a body in front of V yet".
-- Read at the top of scheduleTick. See Config.dismiss.idleCooldown for the whole story (short
-- version: dismissing the companion opens the gate on the idle/schedule body, and if V is standing
-- at the venue the schedule wants him at, a second Jackie spawns in V's face a second later).
-- Global, not a top-level local — init.lua is at Lua's 200-local cap.
function jlStampIdleCooldown(why)
  local secs = (Config.dismiss or {}).idleCooldown or 180.0
  if secs <= 0 then return end
  JL.idle.blockUntil = (JL.clock or 0) + secs
  log(("Idle: schedule re-spawn held off for %.0f s (%s)."):format(secs, tostring(why or "?")))
end

local function dismissJackie()
  pcall(function() jlManualUnseat("dismiss") end)   -- v1.77: NEVER despawn a seated puppet — stand a hand-seated Jackie up first
  setCompanionFlag(false)   -- v0.72: V let him go -> clear the persisted companion intent
  pcall(function() jlStampIdleCooldown("dismissed") end)   -- v1.8.2: no instant idle Jackie in V's face
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
  pcall(function() jlManualUnseat("dismiss all") end)   -- v1.77: ...including one the player seated by hand
  setCompanionFlag(false)   -- v0.72: a full wipe clears the persisted companion intent too
  pcall(function() jlStampIdleCooldown("dismiss all") end)   -- v1.8.2: a full wipe must not re-fill on the next tick
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

-- ===========================================================================
-- CROSS-SAVE LOAD CRASH FIX (v1.61) — purge Jackie's body BEFORE a load tears it down.
-- A LIVE companion Jackie present when you load a save = a native crash: the game frees his
-- companion/party link against the dying player puppet, and no `pcall` can catch a native fault.
-- Proven in jackie_debug.log — DISMISS him first (which despawns his body) and the very same load
-- never crashes; leave him following and it crashes every time. So on a load we do exactly what a
-- manual dismiss does to the body — via the same proven `ammDespawn` path — but WITHOUT clearing the
-- companion FACT. The per-save fact is the intent ("he belongs with V in this save"); a later
-- persist-respawn reads it to bring him back. Losing the body is fine; losing the fact is not.
-- Globals (no top-level `local` -> 200-cap safe). See setupDetachPurge for the trigger.
-- ===========================================================================
function jlPurgeJackieBodies(reason)
  local amm = getAMM()
  local n = 0
  if amm and amm.Spawn and amm.Spawn.spawnedNPCs then
    for _, sp in pairs(amm.Spawn.spawnedNPCs) do
      local nm   = tostring(sp.name or "")
      local path = tostring(sp.path or sp.id or "")
      if nm:lower():find("jackie") or path:lower():find("jackie") then ammDespawn(sp); n = n + 1 end
    end
  end
  if JL.summon.spawn then ammDespawn(JL.summon.spawn); n = n + 1 end
  if JL.idle.spawn   then ammDespawn(JL.idle.spawn) end
  -- Drop the Lua handles (the world they point into is about to die). Leave the companion FACT intact.
  JL.summon.spawn, JL.summon.active, JL.summon.companionSet, JL.summon.walkIn = nil, false, false, false
  JL.idle.spawn, JL.idle.locationKey = nil, nil
  JL.settle.hideUntil, JL.settle.collideUntil, JL.settle.handle = nil, nil, nil
  clearVehicleArrival()
  pcall(function() if jlCruise and jlCruise.active then jlCruiseStop() end end)
  log(("[SESSION] OnDetach: purged Jackie's body before load teardown (%s), n=%d — companion fact kept.")
        :format(tostring(reason), n))
end

-- v1.61: run the purge the instant a load begins tearing the world down. PlayerPuppet.OnDetach fires at
-- the START of a load (and on game exit / Johnny swaps) but NOT on fast-travel — fast-travel only teleports
-- the existing puppet (fastTravelSystem.script:444), it never detaches — so a following Jackie survives a
-- fast-travel exactly as before. We touch NOTHING on the detaching puppet (no `self:` deref); the callback
-- is wrapped in a Session breadcrumb so if the purge itself ever dies mid-despawn, jackie_debug.log.prev names
-- it. Global fn + JL flag (no new top-level local -> 200-cap safe). Registered once from onInit.
function setupDetachPurge()
  if JL.detachHooked then return end
  local ok = pcall(function()
    Observe("PlayerPuppet", "OnDetach", function()
      Session.mark("OnDetach purge Jackie bodies (pre-load)")
      pcall(function() jlPurgeJackieBodies("player OnDetach") end)
      Session.clear()
    end)
  end)
  JL.detachHooked = ok
  log("Detach purge hook (PlayerPuppet:OnDetach) registered: " .. tostring(ok))
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

-- v1.72 HOW FAR AWAY IS HE? Returns metres + which body it measured ("summoned" / "idle"), or nil
-- when nobody is out. This is the readout for the failure everyone eventually hits: the spawn
-- SUCCEEDS, the log says so, and there is nobody there — because he landed under the map, on a roof,
-- or back at the venue he was standing in. One number separates the cases at a glance: a few metres
-- means he is here and something else is wrong; tens of metres means he spawned wrong and is walking
-- in; hundreds means the spawn point was garbage. (Same readout as NCLives, same reason.)
--
-- GLOBAL (200-local cap) and side-effect free: it is called from onDraw, and drawing a panel must
-- never change the game — so it reads the spawn records directly rather than going through any
-- handle resolver that re-applies the follower role as a side effect of being asked.
function jlDistanceToV()
  local h, which = nil, nil
  if JL.summon and JL.summon.spawn then h, which = JL.summon.spawn.handle, "summoned" end
  if not h and JL.idle and JL.idle.spawn then h, which = JL.idle.spawn.handle, "idle" end
  if not h then return nil end
  local pp = playerPos(); if not pp then return nil end
  local hp; pcall(function() hp = h:GetWorldPosition() end)   -- a despawned handle throws; that is "unknown"
  if not hp then return nil end
  local okD, d = pcall(dist3, pp, hp)
  if not okD or type(d) ~= "number" then return nil end
  return d, which
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

-- ⚠️ IS THIS BODY ONE **WE** PUT IN THE WORLD? (2026-08-14)
-- lookedAtJackie() deliberately also claims a body it did not spawn, as long as the RECORD is his —
-- that is what lets the mod talk to a Jackie some other system placed. Night City Allies is exactly
-- such a system, and the moment its bridge is attached that generosity becomes a bug: the player
-- presses [F] on an NCA-hired companion, NCA opens its own hub, and a beat later our box opens on
-- top of it. Reported in game 2026-08-14 (NCLives, Goro through NCA): "the NCA hub is shown shortly,
-- then immediately covered/replaced by ours".
-- GLOBAL on purpose: called from Branch.kick, far above this line, and a file-local is not in scope
-- above its own declaration (see the 200-cap note at the top of this file).
function jlIsOurBody(target)
  if not target then return false end
  local ours = false
  pcall(function()
    if JL.summon and JL.summon.spawn and sameEntity(target, JL.summon.spawn.handle) then ours = true end
    if not ours and JL.idle and JL.idle.spawn and sameEntity(target, JL.idle.spawn.handle) then ours = true end
  end)
  return ours
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

-- (v1.63: the CYCLE_UP_ACTIONS / CYCLE_DOWN_ACTIONS tables that used to sit here moved into
--  dialogui.lua's INPUT section along with the rest of the picker's navigation — v0.41's
--  hard-won list of the action names this build actually emits went with them verbatim. Two
--  fewer top-level locals here, which the 200-cap appreciates.)

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
      -- ⚠️ v1.63a — THE BLAZE ESCAPE [F] OUTRANKS AN OPEN CHOICE MENU. This check MUST stay above the
      -- `Branch.open` block below, which `return`s unconditionally: with a conversation open, F is
      -- handed to the picker and Blaze.tryEscapePress is NEVER reached. So if V had a Jackie exchange
      -- open when they walked up to the AV, the "[F]: Get in the AV" prompt was on screen and pressing
      -- F just picked a dialogue line — no way to leave except answering the conversation first.
      -- (Pre-existing since v0.41, not caused by the v1.63 native picker — but the escape is the one
      -- moment where losing F is unrecoverable-feeling, so it wins.) Narrow by construction:
      -- escapePromptActive() is only true in the escape stage with V already in reach.
      if JL.mode == "blaze" and INTERACT_ACTIONS[name] and actionJustPressed(action) then
        local esc = false
        pcall(function() esc = Blaze.escapePromptActive and Blaze.escapePromptActive() end)
        if esc then
          local consumed = false
          pcall(function() consumed = Blaze.tryEscapePress and Blaze.tryEscapePress() end)
          if consumed then return end
        end
      end
      -- While a choice menu is open: hand the action to the native picker (v1.63). DialogUI owns
      -- the highlight, the debounce and the both-edges handling now (dialogui.lua, INPUT section) —
      -- it keeps the v0.41 finding that navigation arrives PRESSED on the first choice layer but
      -- only RELEASED on deeper ones, so both edges are accepted and debounced.
      -- v1.63.1: `or DialogUI.isShown()` so the STANDALONE test picker ("Show test picker" /
      -- DialogUI.selfTest()) is navigable too. It runs with no conversation, so Branch.open is false
      -- and the old condition routed nothing to it — which would have made a perfectly working picker
      -- look input-dead. It's also simply more correct: if the native box is up, it owns the input.
      if Branch.open or DialogUI.isShown() then
        -- v0.40 DEBUG: log EVERY action while the box is open (name + type + value) so an arrow that
        -- arrives as an AXIS on some layer is still visible. Turn cycleDebug off once locked.
        if Config.dialogue and Config.dialogue.cycleDebug then
          log(string.format("CYCLE action: %s  type=%s value=%s pressed=%s",
            tostring(name), tostring(actionType(action)), tostring(actionValue(action)),
            tostring(actionJustPressed(action))))
        end
        pcall(function()
          DialogUI.onAction(name, actionJustPressed(action), actionReleased(action), JL.clock or 0)
        end)
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
    pcall(function() choice.localizedName = Lang.t("Talk") end)
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
    msg.message = Lang.t(text)   -- v1.60 LOCALIZATION CHOKEPOINT 2 of 4: every notice banner
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
    -- v1.60 LOCALIZATION CHOKEPOINT 1 of 4: every spoken line in the mod reaches the subtitle
    -- band through here, so one Lang.t translates them all (English falls through unchanged).
    line.text         = tostring(Lang.t(text) or "")
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
    -- v1.60: translate BEFORE the concat — showOnscreenMsg would otherwise look up the whole
    -- "Jackie:   <line>" string, which is not a key, and the line would stay English here.
    showOnscreenMsg(tostring(speaker) .. ":   " .. tostring(Lang.t(text)), (duration or 4.0) + 0.5, true)  -- silent: subtitle fallback, not a notice banner
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
  -- v1.8.7 ⚠️ NEVER ADVERTISE A KEY THAT DOES NOTHING. Branch.kick already stands down on a body Night
  -- City Allies owns (see the note there): our conversation reaches that companion through the `Talk`
  -- row the bridge appends to THEIR menu, not through our own box. THE PROMPT NEVER LEARNED THAT. So
  -- on an NCA-hired Jackie we kept pushing our "[F] Talk" hub anyway — which on a controller draws as a
  -- permanent (X) hint sitting on top of NCA's own, and which, when pressed, opens THEIR menu rather
  -- than ours. Reported against NCLucy on 2026-08-18 by a controller player; the engine is shared, so
  -- the bug was here word for word.
  -- Same gate, same body test as Branch.kick, so the two can never disagree: a Jackie WE summoned still
  -- gets the prompt exactly as before, bridge attached or not.
  if j and Allies and Allies.present and Allies.present() and not jlIsOurBody(j) then
    if choiceBox.shown then hideJackieChoiceBox() end
    talkUI.shown       = false
    JL.talkPromptShown = false
    return
  end
  local within, gap = false, nil
  if j then
    within = true
    local pp = playerPos()
    if pp then
      local jp; pcall(function() jp = j:GetWorldPosition() end)
      if jp then
        gap = dist3(pp, jp)                              -- v1.8.9: kept — the TEXT prompt wants its own limit
        if gap > (Config.talk and Config.talk.range or 4.0) then within = false end
      end
    end
  end
  if within then
    -- v1.8.7 ⚠️ "off" MEANS OFF — checked before anything is drawn, and it is the ONE state with no
    -- exception clause. A player running a HUD-hider mod wants a clean screen; a player who knows the
    -- key wants their reminder gone. Neither is served by a prompt that reappears "just this once".
    -- The KEY ITSELF IS UNTOUCHED: look at him and press it and he talks exactly as before. This hides
    -- the reminder, and only the reminder.
    if Config.talk and Config.talk.prompt == "off" then
      if choiceBox.shown then hideJackieChoiceBox() end
      talkUI.shown       = true      -- we ARE in range and looking; only the DRAWING is suppressed
      JL.talkPromptShown = true
      return
    end
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
      -- ⚠️ v1.8.9 — ONE SHOWING PER LOOK, NOT A HEARTBEAT. This used to re-push the banner every 2.5 s
      -- for as long as you kept looking, and `showOnscreenMsg` writes a FRESH SimpleScreenMessage to
      -- the UI_Notifications blackboard every time — so the game replayed the slide-in animation over
      -- and over. Reported 2026-08-22 (and in the Nexus comments): *"it's spamming continuously every
      -- few seconds when you hover over the NPC."*
      -- Worse than ugly: that blackboard slot is the game's OWN notice band, so a prompt re-pushed
      -- every 2.5 s also stomps whatever the game was trying to tell you — a level-up, a quest update.
      -- A reminder is read once. Show it when the look BEGINS and then be quiet; the key keeps working
      -- whether the banner is up or not.
      -- ⚠️ v1.8.9 — AND NOT FROM ACROSS THE ROOM. Reported 2026-08-22, by the same player who turned the
      -- F switch off: *"then I had a message 'Talk to Jackie [F]' showing on the left of the screen
      -- whenever I'm looking at her, from a distance of several meters away as well."*
      -- Both prompt styles share `Config.talk.range` (6 m), but they were never equally visible at
      -- it: the native box is a blackboard offer the GAME still filters through its own interaction
      -- range before drawing, so it only ever appeared close up. Our banner has no such filter — we
      -- draw it ourselves — so switching styles moved the prompt from ~2 m to the full 6 m, and it
      -- read as a new bug rather than the same setting.
      -- `textRange` gives the banner the close-up feel the box had. THE KEY IS UNCHANGED: it still
      -- works out to `range`, and that asymmetry is fine — a reminder you have already read does not
      -- need to follow you back across the room.
      local textRange = (Config.talk and Config.talk.textRange) or 3.0
      if gap and gap > textRange then
        talkUI.shown  = true                             -- in talk range, just not in REMINDER range
        talkUI.lostAt = nil
        JL.talkPromptShown = true
        return
      end
      if not talkUI.promptArmed then
        local key = (Config.talk and Config.talk.keyLabel) or "="
        showOnscreenMsg(Lang.t("Talk to Jackie   [ ") .. key .. " ]", 3.0, true)  -- silent: a reminder, not an alert
        talkUI.promptArmed = true
        talkUI.lastShow    = JL.clock or 0
      end
    end
    talkUI.shown  = true
    talkUI.lostAt = nil          -- still looking: the re-arm countdown has not started
  else
    if choiceBox.shown then hideJackieChoiceBox() end
    talkUI.shown = false
    -- RE-ARM ONLY AFTER A SUSTAINED LOOK-AWAY. `lookedAt...` is a raycast at a moving body, so it
    -- flickers false for a frame or two while they walk. Re-arming on the first false frame would
    -- put the spam straight back — with extra steps. Look away and MEAN it.
    local now = JL.clock or 0
    if talkUI.promptArmed then
      talkUI.lostAt = talkUI.lostAt or now
      if (now - talkUI.lostAt) >= ((Config.talk and Config.talk.textRearmSeconds) or 2.0) then
        talkUI.promptArmed, talkUI.lostAt = false, nil
      end
    end
  end
  -- v1.8.6: mirror onto JL so jlPromptProbeTick (and loadsim) can read it — talkUI is a file-local.
  JL.talkPromptShown = talkUI.shown
end

-- ---------------------------------------------------------------------------
-- v1.8.6 PROMPT PROBE — "no [F] overlay since I installed Night City Allies"
-- ---------------------------------------------------------------------------
-- Antonia, 2026-08-17: *"I'm currently not seeing the [F] key overlay for Lucy or NCLives or Jackie...
-- This is ever since I got NCA, when I uninstall night city allies, the button shows normally."*
--
-- Reading both mods gives three candidates and they need DIFFERENT fixes, so guessing is expensive:
--
--   (1) THEY SWALLOW IT. NCA overrides `InteractionUIBase::OnInteractionData` — which is the handler
--       for the very blackboard field our prompt writes (UIInteractions.InteractionChoiceHub) — and
--       returns without calling wrapped while `ui.hubShown and ui.customHubSelected`
--       (their Application/Lib/interactionUI.lua:382). If those flags are ever left set — an ally
--       despawned, a hub not hidden — every prompt we push is dropped before it is drawn, and no
--       amount of re-pushing on our side can help.
--   (2) THEY OVERWRITE IT. Their `ui.update()` runs EVERY FRAME and, while their hub is shown, writes
--       ActiveChoiceHubID and SelectedIndex to force a UI refresh. Our box is re-asserted only every
--       `Config.talk.boxRefresh` (1 s), so a per-frame writer beats a per-second one and the fix is
--       on our side (push faster, or push into the list they use).
--   (3) NEITHER — our push already failed, and NCA is a red herring. `showCompanionChoiceBox` only
--       logs `ok`/`pushed`, which say the SetVariant returned, not that the value survived.
--
-- So: read the blackboard BACK, a beat after we wrote it, and print what is actually in it next to
-- what we asked for and next to their two flags. One look at the log names the culprit.
-- Logs only when the picture CHANGES (this runs while the player looks at a companion, which is a lot
-- of frames), and only while we believe the prompt should be up.
-- Global -> 200-local cap safe.
function jlPromptProbeTick()
  local P = Config.promptProbe or {}
  if P.enabled == false then return end
  local st = JL.promptProbe; if not st then st = {}; JL.promptProbe = st end
  local now = JL.clock or 0
  if (now - (st.lastAt or -1e9)) < (P.interval or 1.0) then return end
  st.lastAt = now
  if not JL.talkPromptShown then st.sig = nil; return end

  -- what the blackboard is holding NOW (i.e. ~1 s after our last push)
  local heldId, heldActive, heldChoices, activeHub, nHubs
  pcall(function()
    local idef = GetAllBlackboardDefs().UIInteractions
    local bb   = Game.GetBlackboardSystem():Get(idef)
    if not bb then return end
    pcall(function()
      local h = FromVariant(bb:GetVariant(idef.InteractionChoiceHub))
      if h then
        heldId, heldActive = h.id, h.active
        pcall(function() heldChoices = h.choices and #h.choices or nil end)
      end
    end)
    pcall(function() if idef.ActiveChoiceHubID then activeHub = bb:GetInt(idef.ActiveChoiceHubID) end end)
    pcall(function()
      local d = FromVariant(bb:GetVariant(idef.DialogChoiceHubs))
      nHubs = d and d.choiceHubs and #d.choiceHubs or nil
    end)
  end)

  -- ...and THEIR two flags, read straight off the table our bridge already reaches (nca.lua's note on
  -- `app` being reachable-not-published applies here too: every read is pcall'd and optional).
  local ncaShown, ncaCustom
  pcall(function()
    local m   = GetMod("NightCityAllies")
    local aui = m and m.app and m.app.ui
    if aui then ncaShown, ncaCustom = aui.hubShown, aui.customHubSelected end
  end)

  local sig = table.concat({ tostring(heldId), tostring(heldActive), tostring(heldChoices),
                             tostring(activeHub), tostring(nHubs),
                             tostring(ncaShown), tostring(ncaCustom), tostring(choiceBox.shown) }, "|")
  if sig == st.sig then return end
  st.sig = sig

  -- Name the verdict in the line itself, so the log answers the question instead of posing it.
  local verdict
  if heldId == nil then
    verdict = "the field is EMPTY — our push did not survive (someone cleared it, or it never landed)"
  elseif heldId ~= choiceBox.id then
    verdict = ("another hub (id=%s) is in the field — ours was REPLACED"):format(tostring(heldId))
  elseif heldActive == false then
    verdict = "our hub is there but INACTIVE — something deactivated it"
  else
    verdict = "our hub is in the field and active — so the loss is DOWNSTREAM of the blackboard " ..
              "(a swallowed OnInteractionData is the candidate; see NCA's flags)"
  end
  st.verdict = verdict   -- v1.8.6: kept on NCS so loadsim can assert it (`log` is a file-local here)
  log(("[PromptProbe] we asked for id=%d | field holds id=%s active=%s choices=%s | " ..
       "ActiveChoiceHubID=%s DialogChoiceHubs=%s | NCA hubShown=%s customHubSelected=%s | %s")
      :format(choiceBox.id, tostring(heldId), tostring(heldActive), tostring(heldChoices),
              tostring(activeHub), tostring(nHubs), tostring(ncaShown), tostring(ncaCustom), verdict))
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
  -- SPAWN-IN BOOST: for the first `spawnBoostSeconds` after idle Jackie spawns in, he's much more
  -- likely to grin back (fresh-arrival warmth). Guard sp>0 so a fresh mod load doesn't false-boost.
  local sp = JL.idle.spawnedAt or 0
  if sp > 0 and (now - sp) < (cfg.spawnBoostSeconds or 10.0) then
    chance = chance * (cfg.spawnBoostMult or 3.0)
  end
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

-- v1.66: both of these now go through vo.lua, which prefers the GAME'S OWN voice-over
-- (no shipped audio, no Audioware) and falls back to an Audioware bank for anyone who
-- already built one. The signatures are unchanged so the ~20 call sites below didn't
-- have to move; `name` is still an Audioware-style event name, and "jl_<digits>" is
-- recognised as a real line id. See vo.lua.
local function playVoice(name, target, mute)
  if not name or name == "" then return false end
  local ok, spoke = pcall(function() return VO.play(name, target, mute) end)
  return (ok and spoke) or false
end

-- Line length in seconds, for subtitle + flap pacing. Exact where the game told us
-- (vo_durations.lua), Audioware's own answer when that's the backend, else nil.
local function voiceDuration(name, text)
  if not name or name == "" then return nil end
  local d
  pcall(function() d = VO.duration(name, text) end)
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
-- In Hermano mode an inline `m = {...}` on the entry replaces it. No `m` -> the entry is returned
-- unchanged. nil-safe.
--
-- v1.69: the old second step — a central sfx-keyed `Config.hermanoLines` map — is GONE, and the
-- reason is worth keeping. `m` is for lines WE wrote, which have no recording and are therefore
-- ours to word. A line with an `sfx` is CDPR's recording, and where CDPR cut two takes of it the
-- game picks between them from V's body gender before a mod gets a vote. Rewording that line by
-- our relationship switch is how the subtitle ended up saying "chica" over audio saying "mano".
-- Voiced lines are handled by jlLineText/vo_gender.lua instead. See config.lua's header there.
function jlVar(entry)
  if entry and jlHermano() and entry.m then return entry.m end
  return entry
end

-- ---------------------------------------------------------------------------
-- v1.69: is V's BODY male? Not the Husbando/Hermano switch — the actual character in the save,
-- which is what the audio engine reads when it chooses between the two takes of a gendered line.
-- Cached after the first successful read (the body can't change mid-session) and NEVER cached on
-- a failed one: on a slow load Game.GetPlayer() isn't up yet, and locking in a wrong answer there
-- would mis-subtitle every line for the rest of the session. Global — the 200-local cap.
-- ---------------------------------------------------------------------------
function jlVBodyMale()
  if JL.vBodyMale ~= nil then return JL.vBodyMale end
  local pl = Game.GetPlayer(); if not pl then return false end
  local g
  pcall(function() g = pl:GetResolvedGenderName() end)
  if g == nil then return false end
  JL.vBodyMale = (g ~= CName.new("Female"))
  log("V's body reads as " .. (JL.vBodyMale and "MALE" or "FEMALE")
      .. " — gendered lines will be subtitled to match the take the game plays.")
  return JL.vBodyMale
end

-- The words to PUT ON SCREEN for a line about to be spoken. Almost always the authored text; the
-- exception is the handful of lines CDPR recorded twice under one String ID, where the game plays
-- the take matching V's body and config.lua's text was written from the FEMALE one. For a male V
-- we swap in CDPR's own wording of the take he's actually about to hear, so the subtitle can't
-- contradict the audio. Unvoiced lines never reach the table — they have no take to match.
--
-- ⚠️ FEMALE V IS LEFT ALONE ON PURPOSE, even though the table holds her wording too. The authored
-- text already IS the female take (give or take a "Heheh"), and it is what translations.lua is
-- keyed on — swapping in CDPR's punctuation instead would silently drop nine languages back to
-- English to fix nothing. `e.f` stays in the generated file as the reference that shows WHY each
-- entry is there; only `e.m` is ever substituted.
-- ⚠️ v1.71 — THIS NOW FOLLOWS THE AUDIO, NOT THE BODY, AND THAT IS THE POINT.
--
-- Six Jackie lines were recorded twice under one String ID: "chica" to a female V, "mano" to a male
-- one. config.lua ships the FEMALE wording, and this swaps in the male one when the male take is
-- what plays. The old test was `jlVBodyMale()` — V's body — which was right only because the engine
-- always played the male take. It doesn't any more: with the archive merged we substitute the female
-- recording, and for a male-preference or archive-less session we don't.
--
-- So ask the same question the speaking path asks. VO.femaleTakeId is the single source of truth for
-- "which recording will actually come out", and routing the subtitle through it is what closes the
-- 2026-08-13 report for good — "the subtitles now say chica but his voice says mano".
--
-- Note the female-bodied, archive-less case: we now show "mano", because "mano" is what she will
-- HEAR. Reading the wrong word is the bug; reading the true one is not.
function jlLineText(text, sfx)
  local map = Config.voGender
  if not map or not sfx then return text end
  local id = VO.lineId(sfx)
  local e  = id and map[id]
  if not e then return text end
  local female = false
  pcall(function() female = VO.femaleTakeId(id) ~= nil end)
  if female then return text end          -- female take -> the female wording config.lua ships
  return e.m or text                      -- male take   -> the male wording, whatever V's body is
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
  local d = JL.followGap
  if type(d) ~= "number" then d = Config.followDistanceDefault or 1.5 end
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

-- v1.74 FIRST DINNER: seating is a work in progress, and here is the manual control.
-- Fired from dinnerTick the moment V reaches the seat marker (see Config.seatTip for the why and
-- the two gates). `force` = the CET button, which re-shows it without consuming either gate.
--
-- ⚠️ The card is rendered by `Retrieval.showTip` — the SAME renderer as Vik's message and Jackie's
-- note. It is not a second popup implementation, and it must not become one: that path already
-- knows about the delayed Popup_Data listener and the Lang.t chokepoint, and it degrades to the
-- on-screen band by itself when the native push fails.
function jlShowSeatTip(force)
  local T = Config.seatTip
  if not T then return false end
  if not force then
    if JL.seatTipDone == true then return false end             -- per INSTALL (jl_settings.txt)
    if jlFactNum(T.fact or "jackielives_seat_tip") >= 1 then    -- per SAVE (survives reloads)
      JL.seatTipDone = true                                     -- an old save already taught it
      pcall(jlSaveSettings)
      return false
    end
    jlSetFactNum(T.fact or "jackielives_seat_tip", 1)
    -- Written NOW, not at the next settings change: a "shown" record that only reaches disk if
    -- something else happens afterwards is the bug NCLives' welcome card shipped once.
    JL.seatTipDone = true
    pcall(jlSaveSettings)
    log("Seat tip shown (first dinner) — marked done in " .. tostring(JL_SETTINGS_FILE))
  end
  -- ⚠️ v1.8.5 SAY IT WHEN IT IS TRUE. Antonia, 2026-08-17: *"does the seating tutorial card say
  -- that this works only with AMM installed?"* It did not, and it needed to: the sit/lean animations
  -- are AMM's workspots, so without AMM every button in the panel the card sends you to does nothing.
  -- Her own log is 29 consecutive `PUPPET: pose 'sit' -> false` under `AMM present: false` — a player
  -- reading that card without AMM is being sent to a dead end and left to think it is their aim.
  --
  -- Appended CONDITIONALLY rather than written into Config.seatTip, because the card is meant to stay
  -- very short (the whole point of the v1.8.2 rewrite) and this line is noise for players who have AMM.
  local text = T.text
  if not getAMM() then
    text = text .. "\n\nNote: the sit animation comes from AppearanceMenuMod. Without AMM they can "
                .. "still be placed and turned, but \"Seat them\" will not play."
  end
  local ok = pcall(function() Retrieval.showTip(T.title, text, T.duration or 22.0) end)
  if not ok then log("Seat tip: Retrieval.showTip failed") end
  return ok
end

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
  -- v1.69: for the handful of lines CDPR recorded twice under one String ID, the subtitle follows
  -- the take the game is about to play (V's body gender) rather than the one this file was
  -- written from. Everything else passes straight through. This is the ONE place it happens, so
  -- every caller — hub, barks, calls, arrival greetings — is covered by the same rule.
  text = jlLineText(text, sfx)
  -- v1.66: the line comes out of HIS body now, not out of a 2D bank, so the speaker has to
  -- be resolved before the audio rather than only for the subtitle. Jackie if he's spawned,
  -- else the player — on a phone call he isn't in the world yet, and a null speaker makes
  -- the subtitle band skip the line entirely.
  local speaker = dialogueTarget() or Game.GetPlayer()
  -- One call: the game's own VO if we have the line, Audioware if someone has a bank, and a
  -- vocal effort if neither — VO.play walks that ladder itself, honouring `mute`.
  local spoke = false
  pcall(function() spoke = VO.play(sfx, speaker, mute) end)
  -- pace by the real line length when we know it; on an unvoiced line, scale to text length
  -- for the reunion beats (v0.94), else the old flat 3 s.
  local secs = voiceDuration(sfx, text) or (isReunionBeat() and readingSecs(text)) or 3.0
  hideSubtitle()
  showDialogueText("Jackie", text or "", secs + 0.6, speaker)
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
  JL.dinner.dwellSince, JL.dinner.seatTipTried = nil, nil   -- v1.8.2: a fresh outing gets a fresh arrival-dwell clock and may re-offer the seat card
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

-- v1.63: THE PICKER IS NATIVE NOW. Everything that used to live here — the hand-matched COL
-- palette, pickerWindowFlags(), drawNameChild(), drawChoiceRows() and the three style variants —
-- was an ImGui imitation of the game's dialogue box. It is all gone; V's choices are rendered by
-- the game's own dialogue widget instead, driven from dialogui.lua (global `DialogUI`).
--
-- What that buys us, beyond it finally looking right:
--   * the speaker plate, the cyan/gold row colours, the selection bar and the fade animations are
--     the REAL ones, not approximations that drifted at every aspect ratio;
--   * it draws in the GAME's font, so the Japanese / Russian / Chinese translations render properly
--     (the ImGui box was Latin-only — that was the caveat documented in lang.lua);
--   * Config.picker's whole geometry block (topFrac / baseW / baseH / min-maxScale / xOffset) is
--     obsolete: the game positions and scales its own widget.
-- The `menu` table survives as the CHOICE MODEL (menu.choices / menu.sel / menu.title) that Branch.*
-- works against; only the drawing moved.

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

-- v1.63: drawDialogueBox() is gone with the rest of the ImGui picker — the native widget draws
-- itself, so there is nothing to render from onDraw any more. Its two safety behaviours moved:
--   * "close if we've left to the main menu"  -> DialogUI.tick()
--   * "don't draw over the pause/ESC menu"    -> free; the game's own dialogWidgetGameController
--     listens to UI_System.IsInMenu and hides itself (dialogUI.script:31, OnMenuVisibilityChange).

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
  -- ⚠️ v1.69 `pin = true` ON BOTH INJECTED ROWS — Antonia: *"there's now sometimes no dismiss option
  -- in the dialogue hub? it must always be the bottom option of the hub pls."* Two separate ways the
  -- hub's `pick` sampler was eating them, and BOTH need the pin:
  --
  --   1. They were samplable. Unpinned rows go into the draw, and the hub offers 4–5 of ~20 — so
  --      "Head home, Jackie" was competing with the small talk for a slot and usually losing. v1.69's
  --      new topics didn't cause this, they just made the odds bad enough to notice.
  --   2. The CACHED draw dropped them every single time. A held draw is replayed by looking each row
  --      up in `hd.set`, which is keyed by TABLE IDENTITY — and these two tables are built fresh on
  --      every openChoiceMenu call, so they could never match a set recorded on an earlier open. Any
  --      engine-injected row is invisible to that cache by construction; `pin` is what exempts it.
  --
  -- Pinned rows also never count against `want`, so the small talk keeps its full 4–5 slots.
  -- ORDER: these are appended LAST and the sampler only ever drops rows, never reorders them, so
  -- dismiss stays the bottom row of the hub — which is what she asked for and where muscle memory
  -- expects it.
  -- v0.39: dinner invite (gated by dateUnlocked; for now always shown). Starts the date tree.
  if Config.date and dateUnlocked() then
    out[#out + 1] = {
      text   = Config.date.inviteText or "Hey - you hungry?",
      to     = nil,
      action = "start_date",
      pin    = true,
    }
  end
  out[#out + 1] = {
    text   = (Config.dismiss and Config.dismiss.choiceText) or "Head home, Jackie.",
    -- v1.70: the send-off is one of V's own recordings now (Config.dismiss.choiceSfx). It is
    -- the row that ENDS a companion session, so it is heard as often as the greeting is.
    sfx    = Config.dismiss and Config.dismiss.choiceSfx,
    to     = nil,
    action = "dismiss_walkaway",
    pin    = true,
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

local function openChoiceMenu(choices, title, node)
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
  local shown, srcOf = {}, {}
  for _, c in ipairs(choices or {}) do
    local appear = true
    if c.chance then local r = 1.0; pcall(function() r = math.random() end); appear = (r < c.chance) end
    if c.once and bstate.taken and bstate.taken[c.once] then appear = false end   -- v1.54: already walked this branch
    -- v1.65 FAMILIARITY GATE. `minFam = <tier 0..3>`: the topic only appears once Jackie has opened up
    -- that far (familiarity.lua). No minFam = always eligible, so every tree written before this is
    -- untouched. Checked BEFORE `cond`, and mirrored in the empty-menu fallback below, so a topic he
    -- hasn't earned can never be resurrected by the safety net — that would leak the whole character.
    if appear and c.minFam ~= nil then
      local ok = true
      pcall(function() ok = Fam.allows(c.minFam) end)
      appear = ok and true or false
    end
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
        -- v1.70: a textPool entry may be a plain STRING (as it always was) or a
        -- { text =, sfx = } row, so V's exit lines can carry one of her own recordings the
        -- same way a normal choice row does. Both shapes coexist in one pool on purpose —
        -- most written lines will never have a recording behind them, and a pool should not
        -- have to be all-or-nothing to gain a voice.
        local e = pool[i]
        if type(e) == "table" then
          sc.text = e.text
          if e.sfx then sc.sfx = e.sfx end
        else
          sc.text = e
        end
      elseif src.text then
        sc.text = src.text
      end
      -- v1.77 `variants` (array of {text=, sfx=, to=}) — a textPool that also carries the VOICE and
      -- (optionally) the node that answers it. Ported from NCLives v1.76.
      --
      -- `textPool` shuffles the words alone, which is all a written line needs. A VOICED line can't
      -- work that way: the row the player reads, the recording V speaks, and the reply that lands
      -- have to be the same choice, and they are decided at three different moments (here, at
      -- confirm, and when the next node opens). So the variant is picked ONCE, right here, and its
      -- `sfx` and `to` ride along in the same copy the rest of the flow already reads.
      --
      -- ⚠️ `to` is an OVERRIDE, not a default: a variant that omits it keeps the choice's own.
      local vs = src.variants
      if vs and #vs > 0 then
        local vi = 1; pcall(function() vi = math.random(1, #vs) end)
        local v = vs[vi]
        if v then
          if v.text then sc.text = v.text end
          if v.sfx  then sc.sfx  = v.sfx  end
          if v.to   then sc.to   = v.to   end
        end
      end
      shown[#shown + 1] = sc
      srcOf[#shown]     = c              -- the ORIGINAL choice, for the hub-refresh cache below
    end
  end
  -- =========================================================================
  -- v1.65 RANDOM SUBSET (`pick` on the NODE) + HUB REFRESH
  -- =========================================================================
  -- Once Jackie has three tiers of topics unlocked, showing all of them at once is a wall of text that
  -- makes him feel like a menu. With `pick` set, only some eligible topics are offered per draw:
  --   • `pin = true` on a choice exempts it — it ALWAYS shows and never counts. The way OUT of the hub
  --     must be pinned, or a sampled menu can strand the player with no exit.
  --   • authored ORDER is preserved: rows are dropped, never reordered, so `last = true` and the
  --     engine-injected dinner rows keep their positions.
  --   • `pick` may be a RANGE `{min, max}` — the row COUNT is re-rolled too, so the menu changes shape
  --     as well as contents. A fixed number reads as a form to fill in.
  --   • nothing happens unless the node asks for it, so every existing tree is untouched.
  -- The draw is NOT re-rolled on every open: the hub is re-entered after every topic, so re-rolling
  -- would let a player reopen the menu until the whole pool had scrolled past. A draw STICKS for
  -- Config.dialogue.hubRefreshMin..Max seconds, measured from when the hub was last SEEN. Cached on JL
  -- (not bstate) precisely because it must OUTLIVE the conversation. Choices that stopped being eligible
  -- meanwhile are dropped from the cached set rather than resurrected.
  if node and node.pick and #shown > 0 then
    local want
    if type(node.pick) == "table" then
      local lo = math.floor(tonumber(node.pick[1]) or 1)
      local hi = math.floor(tonumber(node.pick[2]) or lo)
      if hi < lo then lo, hi = hi, lo end
      want = lo
      pcall(function() want = math.random(lo, hi) end)
    else
      want = tonumber(node.pick) and math.floor(tonumber(node.pick)) or nil
    end
    want = want and math.max(1, want)
    JL.hubDraw = JL.hubDraw or {}
    local hd, now = JL.hubDraw[node], (JL.clock or 0)
    if want and hd and hd.set and now < (hd.until_ or 0) then
      local out = {}
      for i, c in ipairs(shown) do
        if c.pin or hd.set[srcOf[i]] then out[#out + 1] = c end
      end
      local nonPinned = 0
      for _, c in ipairs(out) do if not c.pin then nonPinned = nonPinned + 1 end end
      if nonPinned > 0 then                       -- only honour a cache that still leaves something to say
        shown, want = out, nil
        hd.until_ = now + (hd.hold or 20.0)       -- reopening keeps the topics put; walking away refreshes
      end
    end
    if want then
      local free = {}                             -- indices of the samplable (unpinned) rows
      for i, c in ipairs(shown) do if not c.pin then free[#free + 1] = i end end
      if #free > want then
        for i = #free, 2, -1 do                   -- Fisher-Yates over the INDEX list, then re-sort
          local j = 1; pcall(function() j = math.random(1, i) end)
          free[i], free[j] = free[j], free[i]
        end
        local keep = {}
        for i = 1, want do keep[free[i]] = true end
        local out, set = {}, {}
        for i, c in ipairs(shown) do
          if c.pin or keep[i] then out[#out + 1] = c; if not c.pin then set[srcOf[i]] = true end end
        end
        local D = Config.dialogue or {}
        local lo, hi = D.hubRefreshMin or 20.0, D.hubRefreshMax or 45.0
        local hold = lo
        pcall(function() hold = lo + math.random() * math.max(0, hi - lo) end)
        JL.hubDraw[node] = { set = set, until_ = (JL.clock or 0) + hold, hold = hold }
        shown = out
      end
    end
  end
  -- safety: never open an empty menu. Fall back only to choices that are still LEGAL (a spent `once`
  -- branch must stay spent — resurrecting it would let the player replay a hub topic).
  if #shown == 0 then
    for _, c in ipairs(choices or {}) do
      local locked = false                                  -- v1.65: ...and a topic behind minFam stays behind it
      if c.minFam ~= nil then pcall(function() locked = not Fam.allows(c.minFam) end) end
      if not locked and not (c.once and bstate.taken and bstate.taken[c.once]) then shown[#shown + 1] = c end
    end
    if #shown == 0 then shown = choices end   -- everything was spent -> last resort, show the raw list
  end
  menu.choices, menu.sel, menu.title = shown, 1, title or "Jackie"
  -- v1.63: hand the resolved list to the GAME's dialogue widget (dialogui.lua). DialogUI owns the
  -- highlight while it's up and calls Branch.confirm(idx) on select; `menu` stays the model Branch.*
  -- reads. If the widget can't be driven for any reason we DON'T open a phantom menu that the player
  -- can't see but that still swallows their input — we log and end the beat cleanly.
  if not DialogUI.show(menu.title, shown, function(idx) menu.sel = idx; Branch.confirm(idx) end) then
    menu.shown, menu.choices, Branch.open = false, nil, false
    -- Almost always "the dialogue controller hasn't been captured yet", which resolves itself within
    -- a frame or two. Re-arm openAt and try again for ~2 s rather than dropping the conversation on
    -- the floor. Only if it never comes back do we end the beat — cleanly, and never by leaving an
    -- INVISIBLE menu open that silently eats the player's movement and fire input.
    bstate.pickerTries = (bstate.pickerTries or 0) + 1
    if bstate.pickerTries <= 8 then bstate.openAt = (JL.clock or 0) + 0.25; return end
    bstate.pickerTries = nil
    log("Branch: NATIVE PICKER UNAVAILABLE after 8 tries — ending the conversation. See the [DialogUI] lines above.")
    if Branch.finish then pcall(Branch.finish) end
    return
  end
  bstate.pickerTries = nil
  menu.shown, Branch.open = true, true
  -- Log the ROWS, not just how many (ported from NCLives v0.9.10). "menu open (5 choices)" said
  -- nothing about WHICH rows, so a menu that was built wrong — topics at the top level, a sign-off
  -- sorted under the injected send-off, a gated choice that leaked — looked identical in the log to
  -- a correct one. The rows are the part a bug report actually needs.
  local rows = {}
  for i, c in ipairs(shown) do rows[i] = i .. "." .. tostring(c.text) end
  log("Branch: menu open (" .. tostring(#shown) .. " choices) [" .. table.concat(rows, " | ")
      .. "]. Arrows/scroll=move, F=select.")
end

local function closeChoiceMenu()
  menu.shown, Branch.open, menu.choices = false, false, nil
  pcall(DialogUI.hide)                          -- v1.63: take the native hub back down with it
end

-- Branch.finish (v0.80): the ONE authoritative "a conversation has ENDED" tool. Every path that ends a
-- talk should funnel through here so the on-screen overlay/menu AND the bottom subtitle band are ALWAYS
-- cleaned up together — no more per-branch bookkeeping. It's idempotent (safe to call twice) and is
-- backed by subtitleWatchdogTick (onUpdate) as a guaranteed safety net for any path that still forgets.
Branch.finish = function(reason)
  -- v1.62: a conversation opened mid-walk-off PAUSED his retreat. If it's still paused now (V didn't pick
  -- dinner — a dinner accept/invite calls jlAbortDeparture, which clears leaving.phase, so this won't fire),
  -- RESUME the walk-off: re-issue the retreat and let leavingTick carry him out as before.
  if JL.leaving.phase == "walking" and JL.leaving.paused then
    JL.leaving.paused = false
    JL.leaving.lastReissue = 0        -- force leavingTick to re-issue the move on its next tick
    local h = JL.summon.spawn and JL.summon.spawn.handle
    if h then
      local D = Config.dismiss or {}
      pcall(function() jlRetreatFollow(h, D.movement or "Walk", (D.despawnDistance or 30.0) + 4.0) end)
    end
    log("Departure RESUMED — conversation ended without a dinner; Jackie carries on out.")
  end
  closeChoiceMenu()                 -- close the ImGui choice picker + drop Branch.open
  Branch.open, Branch.busy = false, false
  pcall(hideJackieChoiceBox)        -- clear the native "[F] Talk" prompt
  bstate.node, bstate.openAt = nil, nil
  bstate.pending, bstate.pendingAt, bstate.pendingAction = nil, nil, nil
  bstate.tree, bstate.talkCooldownKey = nil, nil
  bstate.taken = nil                -- v1.54: drop the one-time-choice ledger with the conversation
  bstate.seen  = nil                -- v1.69: ...and the greetOnce ledger, so the NEXT talk opens with a hello
  bstate.pickerTries = nil          -- v1.63: reset the native-picker retry counter with it
  hideSubtitle()                    -- wipe the bottom band NOW (watchdog would catch it too)
  if reason then JL.ui.status = reason end
end

-- Pick a line from a node's jackiePool. Entries may carry `chance` (0..1) = an independent roll
-- for that RARE line (e.g. chance=0.01 -> ~1% of the time). If no chance-gated line hits, pick
-- uniformly among the normal (non-chance) lines. So common lines stay common and a flagged line
-- only slips in occasionally. (v0.34b)
-- v1.65: entries may ALSO carry `minFam = <tier>` — the SAME question, answered at more length once
-- Jackie has opened up. This is the half of the familiarity system that matters most: not "new topics
-- appear" (that's a menu growing) but "the thing you already asked gets a real answer" (that's a person
-- letting you in). An entry above V's tier is simply not eligible, so a pool that mixes tiers degrades
-- to its shortest answer for a player he barely knows.
--   ⚠️ Highest EARNED tier wins, and ties are random. Without the "highest wins" rule a tier-0 filler
--   line would keep coming up alongside the tier-3 confession and the growth would read as randomness.
local function pickPoolLine(pool)
  -- 1) rare chance-gated lines still get first refusal, but only if V has earned them
  local eligible = {}
  local best = -1
  for _, e in ipairs(pool) do
    local ok = true
    if e.minFam ~= nil then pcall(function() ok = Fam.allows(e.minFam) end) end
    if ok then
      eligible[#eligible + 1] = e
      local t = tonumber(e.minFam) or 0
      if t > best then best = t end
    end
  end
  if #eligible == 0 then eligible, best = pool, -1 end     -- safety: nothing earned yet -> old behaviour
  -- 2) among the eligible, keep only the HIGHEST tier V has reached (see the note above)
  local top = {}
  for _, e in ipairs(eligible) do
    if (tonumber(e.minFam) or 0) == math.max(best, 0) then top[#top + 1] = e end
  end
  if #top == 0 then top = eligible end
  local normal = {}
  for _, e in ipairs(top) do
    if e.chance then
      local r = 1.0; pcall(function() r = math.random() end)
      if r < e.chance then return e end
    else
      normal[#normal + 1] = e
    end
  end
  if #normal == 0 then normal = top end                    -- safety: every entry was chance-gated
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
  if bstate.tree ~= tree then bstate.taken, bstate.seen = nil, nil end
  bstate.tree = tree
  nodeKey = nodeKey or tree.start
  local node = tree.nodes[nodeKey]
  if not node then log("Branch: node '" .. tostring(nodeKey) .. "' missing"); return end
  Branch.busy = true
  Branch.open = false
  closeChoiceMenu()
  pcall(hideJackieChoiceBox)        -- clear the native "[F] Talk" prompt while we talk
  bstate.node = node
  -- v1.69 GREET ONCE PER CONVERSATION. Every topic in the hub ends in `to = "open"`, so re-entering
  -- the hub used to replay its greeting pool — and that pool is his ARRIVAL lines ("Talk to me,
  -- choomba", "¿Qué onda?"). Antonia: he "throws an arrival line EVERY time V returns to the main
  -- dialogue picker hub, not good". Right: you say hello once, then you're talking. A node marked
  -- `greetOnce = true` speaks its line the first time it is entered in a conversation and goes
  -- straight to the choices every time after, so the hub feels like ONE conversation with topics
  -- rather than a loop of re-introductions. Cleared with `taken` when the tree changes.
  local revisit = node.greetOnce and bstate.seen and bstate.seen[nodeKey]
  if node.greetOnce then
    bstate.seen = bstate.seen or {}
    bstate.seen[nodeKey] = true
  end
  if revisit then
    -- No line, no lip flap, no grunt roll — just re-open the picker. The short beat keeps the
    -- box from snapping back in the same frame V confirmed a choice.
    bstate.openAt = (JL.clock or 0) + 0.25
    log("Branch: re-entered '" .. tostring(nodeKey) .. "' (greetOnce) — straight to the choices.")
    return
  end
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
-- ---------------------------------------------------------------------------
-- v1.70 — V SPEAKS TOO. A choice row (or a callFarewells entry, or a textPool
-- row) may carry `sfx = "jl_<String ID>"` naming one of **V's own** recordings.
-- It plays out of V's body the moment the player picks it, under the subtitle we
-- were already showing.
--
-- ⚠️ WHY THIS DOES NOT GO THROUGH VO.play. That path exists to make JACKIE speak,
-- and it honours Config.voice.voiceTag — which would inject Jackie's voice tag
-- into whatever entity it is handed. Hand it the player and V answers Jackie in
-- Jackie's voice. V's body already carries V's own tag and the game picks the
-- male or female take from it, so the correct call is the one with NO tag
-- injection, which is exactly what JLVO_SpeakAsPlayer is and why it has no tag
-- argument to get wrong.
--
-- ⚠️ A GLOBAL, not a `local`. init.lua sits on Lua's 200-local ceiling (see
-- CLAUDE.md), and a global also resolves at CALL time, so Branch.confirm below
-- may reference it regardless of where in the file it ends up.
--
-- Returns how long to hold the subtitle (the recording's real length), or nil if
-- nothing played — no shim installed, no player, or not a line id. Every failure
-- is silent by design: the subtitle is the content, the voice is the bonus.
-- ---------------------------------------------------------------------------
-- v1.70.1 — WHICH EVENT SHAPE V'S LINE IS SENT AS, AND WHY IT IS NOT A FIXED NUMBER.
--
-- ⚠️ READ THIS BEFORE "FIXING" THE V-VOICE GENDER. The Esc-menu control does NOT tell
-- the game what sex V is. The game already knows — it is in the save, and
-- `GetResolvedGenderName()` reports it. There is exactly ONE String ID per line and the
-- ENGINE picks the male or female take from V's BODY before a mod gets a vote
-- (locVoiceoverMap: of 15,187 genuinely gendered pairs, zero differ in the id). So the
-- only thing any of this can change is the SHAPE of the DialogLineEvent, in the hope
-- that a differently-shaped event makes the engine resolve the take differently:
--     0  isPlayer = true,  no voice tag       <- what NCLives shipped and heard
--     1  isPlayer = false, inject V's tag n"v"   (how V Voice Framework speaks)
--     2  isPlayer = true,  inject V's tag
--
-- "auto" is the default and it routes on V's BODY, not on a preference:
--     male body   -> 0   the shape with in-game evidence behind it
--     female body -> 1   because 0 is the shape a female-V player was reported hearing
--                        MALE audio from (NCLives, 2026-08-13)
-- ⚠️ The female half is a HYPOTHESIS and has not been heard yet. That is exactly what
-- the "Test V's voice (A/B)" button in the CET window is for — it plays one line both
-- ways, back to back, and names each in the log. Whatever wins goes in the Esc switch.
--
-- ⚠️ NEVER read jlHermano() near this. The Husbando/Hermano switch picks which authored
-- set of JACKIE's lines plays — a story preference. It says nothing about V's body, and
-- wiring the two together is exactly how v1.69 shipped male audio under a female
-- subtitle. Voice follows the body; the body is the save's to report.
-- ---------------------------------------------------------------------------
function jlPlayerVariant()
  -- ⚠️ v1.71 — DEAD LEVER, PINNED. This used to map the Esc-menu choice onto a different SHAPE of
  -- the DialogLineEvent (isPlayer / voice-tag combinations) in the hope the engine would pick the
  -- other take. It cannot: the shape carries no gender at all, and all three shapes were confirmed
  -- male in game against a female V (../NCLives/docs/research/vo_gender.md §6.5). The player's
  -- choice now reaches a REAL lever — VO.femaleTakeId, which substitutes a String ID of our own
  -- whose voiceover-map row points at the female recording. Kept as a function, returning the one
  -- shape we know works, so no caller has to change and nobody re-derives the dead theory.
  return 0
end

-- Is the installed archive the one this Lua was generated against?
--
-- ⚠️ "IS AN ARCHIVE LOADED" IS THE WRONG QUESTION, and getting it wrong is silent. NCLives shipped
-- that mistake on 2026-08-17: new voiced lines were added, the player deployed the Lua but not a
-- rebuilt archive, and every new line played SILENT — the presence probe passed while the archive
-- had never heard of the ids being spoken, and the redscript shim returns true for any id it can
-- parse. No error, no log line, nothing to grep.
--
-- So the archive carries a TOKEN fingerprinting exactly which substitutions it can serve, and we
-- refuse to substitute unless it matches the token generated beside vo_female_ids.lua. A stale
-- archive then degrades to the MALE take — wrong, but audible and instantly diagnosable.
--
-- Cached for the session on BOTH answers: archives load at startup only, so a "no" is permanent.
-- Global -> 200-local cap safe.
function jlArchiveLoaded()
  if JL.archiveOk ~= nil then return JL.archiveOk end

  local want
  pcall(function() want = (require("vo_female_ids") or {}).__token end)
  if not want then JL.archiveOk = false; return false end

  local got
  pcall(function() got = Game.GetLocalizedTextByKey(CName.new("jl_vomap_token")) end)
  got = got and tostring(got) or ""

  JL.archiveOk = (got == want)
  if JL.archiveOk then
    log("Archive: voice map is CURRENT (token " .. want .. ") — V's female takes are available.")
  elseif got == "" then
    log("Archive: JackieLives.archive is NOT loaded (no voice-map token). V and Jackie will use the "
        .. "MALE takes. Check that ArchiveXL is installed and that BOTH JackieLives.archive and "
        .. "JackieLives.archive.xl are in <game>\\archive\\pc\\mod\\.")
  else
    log(("Archive: the installed voice map is STALE (archive says %s, this build needs %s). Using "
         .. "the MALE takes so nothing goes silent. Fix: run build_archive.bat on Windows, then "
         .. "restart the game — archives load at startup only."):format(got, want))
  end
  return JL.archiveOk
end

-- The player's answer to "does V sound like the V on my screen", for VO.femaleTakeId.
-- Persisted as JL.vVoice; read through a function rather than parked in Config.voice because
-- config.lua is re-required from disk on every reload and would wipe it. Global -> 200-cap safe.
function jlTakePref()
  local pick = JL.vVoice or "auto"
  if pick ~= "male" and pick ~= "female" then pick = "auto" end
  return pick
end

-- V'S GENDER, ONCE PER SESSION, INTO THE LOG. "V's voice sounds wrong" has four possible
-- causes and three of them are answerable without hearing anything, so the log answers them
-- before Antonia has to describe a sound:
--   shim    if this is < 3 the redscript deploy did not land and THAT is the whole bug.
--   body    GetResolvedGenderName() -> 'Male'/'Female'. What every gender-aware system in
--           the game reads, and what "V's physiology" means.
--   brain   the character creator's separate VOICE slider (SetIsBrainGenderMale). A
--           female-bodied V with a masculine voice is a legal character — if that is the
--           save, male audio is CORRECT and there is nothing to fix.
--   take    v1.71: WHICH RECORDING actually played, and why. `female` means we substituted a
--           synthetic String ID pointing at the female .wem; `male` means we did not, and the
--           three reasons are reported beside it — pref (the Esc setting), mapped (is this line
--           gendered at all? four in five are not), archive (is JackieLives.archive merged?).
function jlLogPlayerVoice(p, ver, variant, realId, spokenId)
  if JL.vVoiceLogged then return end
  JL.vVoiceLogged = true
  local body, brain = "?", "?"
  pcall(function()
    local g = p:GetResolvedGenderName()
    body = tostring(g and g.value or g)
  end)
  pcall(function()
    local st = Game.GetCharacterCustomizationSystem():GetState()
    if st then brain = st:IsBrainGenderMale() and "Male" or "Female" end
  end)
  local mapped, archive = false, false
  pcall(function() mapped = (require("vo_female_ids") or {})[realId] ~= nil end)
  pcall(function() archive = jlArchiveLoaded() end)
  local take = (spokenId and realId and spokenId ~= realId) and "female" or "male"
  log(("VO: V SPOKE — shim=v%d bodyGender=%s brainGender=%s take=%s "
       .. "(pref=%s mapped=%s archive=%s id=%s). If shim<3 the redscript deploy didn't land and "
       .. "that is the whole bug. If bodyGender is Female and take=male, the reason is one of "
       .. "pref/mapped/archive above — mapped=false just means this line isn't gendered, which is "
       .. "true of most of them.")
      :format(ver, body, brain, take, jlTakePref(), tostring(mapped), tostring(archive),
              tostring(spokenId)))
end

function jlSpeakPlayerLine(sfx, text)
  local id
  pcall(function() id = VO.lineId(sfx) end)
  if not id then return nil end
  if (Config.voice or {}).mode == "off" then return nil end
  local p
  pcall(function() p = Game.GetPlayer() end)
  if not p then return nil end

  -- v1.71: the id we SPEAK. For a female V on a gendered line, with the archive merged, this is our
  -- synthetic id whose voiceover-map row points at the FEMALE .wem — the only way to select a take,
  -- because a line's two takes share one String ID and the engine picks the column natively. Falls
  -- back to the real id whenever any condition fails, so it can never mute a line. Everything else
  -- below stays keyed on the REAL id: durations, subtitles, the log.
  local speakId = id
  pcall(function() speakId = VO.femaleTakeId(id) or id end)

  local secs = 0
  pcall(function() secs = VO.duration(sfx, text) or 0 end)
  local ctx = (Config.voice or {}).context or -1
  -- A call is in V's head; a conversation is in front of her. 1 = Vo_Expression_Phone,
  -- 0 = Vo_Expression_Spoken. Passed as an Int32 for the same reason the context is:
  -- naming an enum member that doesn't exist is a COMPILE error, and that takes down
  -- every redscript mod the player has, not just this one.
  local expr = (bstate.tree ~= nil
                and (bstate.tree == Config.callTree or bstate.tree == Config.reunionCallTree)) and 1 or 0
  local variant = jlPlayerVariant()

  local played, shim = false, 0
  pcall(function()
    local ver = p:JLVO_Version()
    ver = (type(ver) == "number") and ver or 0
    shim = ver
    if ver >= 3 then
      played = p:JLVO_SpeakAsPlayer(speakId, ctx, expr, variant, secs)
    elseif ver >= 2 then
      -- Stale .reds next to a new .lua: still speak, just without the isPlayer flag.
      -- Empty tags — V is V, and this is the one call that must never borrow a voice.
      played = p:JLVO_Speak(speakId, ctx, expr, CName.new(""), CName.new(""), secs)
    else
      played = p:JLVO_PlayLine(speakId, ctx)
    end
  end)
  -- ⚠️ SAY IT OUT LOUD WHEN NOTHING PLAYED. A silent V is the failure this feature will
  -- actually be reported as ("she still doesn't talk"), and it has exactly one common cause:
  -- the .reds didn't deploy, so JLVO_Version is nil and every V line no-ops. Without this the
  -- log looked identical to a working build with no voiced rows on screen.
  if not played then
    if not JL.vVoiceFailLogged then
      JL.vVoiceFailLogged = true
      log(("VO: V did NOT speak — sfx=%s shim=v%s. If shim=v0 the redscript shim is missing: "
           .. "check r6\\scripts\\JackieLives\\JackieLivesVO.reds is in your GAME folder and that "
           .. "redscript is installed. Everything else still works; V is just silent.")
          :format(tostring(sfx), tostring(shim)))
    end
    return nil
  end
  pcall(jlLogPlayerVoice, p, shim, variant, id, speakId)
  log(("Branch: V spoke '%s' sfx=%s secs=%.2f expr=%d variant=%d")
      :format(tostring(text), tostring(sfx), secs, expr, variant))
  return (secs > 0) and secs or nil
end

-- ---------------------------------------------------------------------------
-- THE A/B TEST, AS ONE BUTTON PRESS. (v1.70.1)
--
-- The one question nobody has been able to answer from a Mac: does variant 1 actually give a
-- FEMALE take, or does the engine ignore the event shape entirely and read V's body no matter
-- what? NCLives built a "gender lab" as a config flag that replayed the first line of every
-- session — which is why it shipped switched off and never got its session.
--
-- This is the same experiment as a deliberate act instead: press once, hear the SAME line
-- twice, ~3 s apart, each named in the log. Nothing is armed, nothing persists, no ordinary
-- conversation is affected.
--
-- ⚠️ The two takes must be heard back to back with nothing on top of them, or the comparison
-- is worthless. Do it with Jackie NOT mid-conversation.
function jlVoiceABTest(sfx)
  sfx = sfx or "jl_2015663563352219656"   -- "How's your mom?" — V's own line, to Jackie, 1.5 s
  local p
  pcall(function() p = Game.GetPlayer() end)
  if not p then return false, "no player" end
  local ver = 0
  pcall(function() ver = p:JLVO_Version() or 0 end)
  if (tonumber(ver) or 0) < 3 then
    return false, "the redscript shim isn't loaded (JLVO_Version < 3) — nothing can play"
  end
  local id = VO.lineId(sfx)
  if not id then return false, "not a line id: " .. tostring(sfx) end
  local secs = VO.duration(sfx) or 2.0

  pcall(function() p:JLVO_SpeakAsPlayer(id, 0, 0, 0, secs) end)
  log("VO A/B: take 1 of 2 — variant 0 (isPlayer, no tag). This is what a male V is meant to sound like.")
  -- Arm the second take. jlVoiceABTick fires it; a plain clock deadline, no coroutine.
  JL.vAB = { id = id, secs = secs, at = (JL.clock or 0) + secs + 1.0 }
  return true
end

-- Fires the armed second take. Self-guards, so it costs one nil check per frame otherwise.
function jlVoiceABTick()
  local ab = JL.vAB
  if not ab or (JL.clock or 0) < ab.at then return end
  JL.vAB = nil
  local p
  pcall(function() p = Game.GetPlayer() end)
  if not p then return end
  pcall(function() p:JLVO_SpeakAsPlayer(ab.id, 0, 0, (Config.voice or {}).femaleVariant or 1, ab.secs) end)
  log("VO A/B: take 2 of 2 — variant 1 (no isPlayer, V's tag injected). "
      .. "WHICHEVER of the two sounds like the V on your screen is the winner: set Esc -> Settings -> "
      .. "Jackie Lives -> Voice -> \"V's voice\" to Male for take 1 or Female for take 2. "
      .. "If BOTH sounded the same, the engine is reading V's body and ignoring the event shape — "
      .. "say so, because that retires this switch entirely and there is nothing left to fix.")
end

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
  -- v1.65 `fam = <n>`: this specific reply moves the needle. Almost always NEGATIVE — V saying the wrong
  -- thing, not a bonus for saying the right one, because the base award already covers "you talked to
  -- him". Floors at 0 in Fam.add: you can cool Jackie off, you can never make him a stranger again.
  if c.fam then pcall(function() Fam.add("choice", c.fam) end) end
  hideSubtitle()
  -- v1.70: if this row carries one of V's OWN recordings, play it — and let the recording
  -- decide how long the subtitle stays. Reading time is a guess; the game told us the real
  -- length (vo_durations.lua), and a subtitle that clears while V is still talking is the
  -- single most obvious way a voiced line reads as broken. Falls through to the old
  -- reading-time behaviour whenever nothing played, so an unvoiced row is untouched.
  local spoke = nil
  pcall(function() spoke = jlSpeakPlayerLine(c.sfx, c.text) end)
  -- v0.94: on the reunion beats, scale V's chosen line to its length too (so long picks aren't cut off).
  local hold = spoke
               or (isReunionBeat() and readingSecs(c.text))
               or (Config.dialogue and Config.dialogue.choiceHold) or 2.5
  -- v1.70: run V's own line through jlLineText too. Same reason it exists for Jackie — CDPR
  -- recorded ~2,000 of V's lines TWICE under one String ID with different words, the engine
  -- picks the take from V's body, and a subtitle written from the female take would contradict
  -- the audio a male V hears. No V line currently in the trees is one of those, which is
  -- exactly why the guard belongs here now rather than after somebody ships one.
  showDialogueText("V", jlLineText(c.text or "", c.sfx), hold, Game.GetPlayer())  -- V's pick, shown before Jackie replies
  bstate.pending       = c.to or "__end__"
  bstate.pendingAction = c.action                              -- e.g. "summon_arrival" (fires at call end)
  bstate.pendingAt     = (JL.clock or 0) + hold                -- wait out V's line before Jackie replies
end

-- move the highlight (wraps). v1.63: DialogUI is the source of truth while the native box is up —
-- it publishes the row to UIInteractions.SelectedIndex, which is what actually repaints the
-- highlight — so delegate and mirror the result back onto menu.sel for anything still reading it.
Branch.move = function(delta)
  if not Branch.open or not menu.choices then return end
  if #menu.choices == 0 then return end
  pcall(function() DialogUI.move(delta); menu.sel = DialogUI.index() end)
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
  local looked = lookedAtJackie()
  if not looked then return false end
  -- ⚠️ HANDS OFF A BODY NIGHT CITY ALLIES OWNS. His conversation reaches that companion through the
  -- `Talk` row the bridge adds to THEIR menu (nca.lua), so opening our own box here as well is not a
  -- second route to the same content — it is our box landing on top of theirs, which is precisely the
  -- bug the bridge exists to remove. Only stands down for a body we did NOT spawn: our own summoned
  -- companion is talked to exactly as before, bridge or no bridge.
  if Allies and Allies.present and Allies.present() and not jlIsOurBody(looked) then return false end
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
  -- v1.62: if he's mid-walk-off, PAUSE it the instant V opens the conversation (not later, at the dinner
  -- pick) — halt him and turn to face V. Branch.finish resumes the walk-off unless a dinner cancels it.
  if JL.leaving.phase == "walking" and not JL.leaving.paused then
    JL.leaving.paused = true
    JL.leaving.subClearAt = nil
    pcall(hideSubtitle)                 -- drop the parting line; a fresh conversation is starting
    pcall(jlFaceV)                      -- stop (placeAtExact cancels the retreat move) + look at V
    log("Departure PAUSED — V opened a conversation mid-walk-off.")
  elseif JL.summon.active and JL.summon.companionSet
         and not JL.dinner.phase and not JL.summon.walkIn
         and not (JL.arrival and JL.arrival.phase) and not (JL.varrival and JL.varrival.phase) then
    -- Standing companion turns his whole body to face V when a face-to-face conversation opens.
    -- (Skip the SEATED / venue-idle / mid-arrival Jackie — a placeAtExact would eject him from a sit
    --  workspot or fight the walk-in; jlLookAtTick's head-tracking already covers those cases.)
    pcall(jlFaceV)
  end
  -- v1.65 FAMILIARITY: ONE point per CONVERSATION, awarded here — the moment a talk tree actually
  -- opens, not on the [F] prompt (which fires whenever V looks at him). Deliberately not per topic:
  -- paying per row would make "click every option before leaving" the optimal play, and at this curve
  -- that would collapse months of intended progression into an afternoon. Walking six topics in one
  -- sitting is still one conversation, because it is.
  pcall(function() Fam.add("talk") end)
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
  -- v1.61: this is the arrival's LAST-RESORT point (callers try navmeshArrivalPoint first). It used to be
  -- returned RAW — the forward point at V's own z, which over a balcony is mid-air. Ground it: jlGrounded
  -- snaps it to navmesh, or drops back to V's own position. Never air.
  local grounded = jlGrounded(pt)
  log(("Call: arrival point via %s -> { %.2f, %.2f, %.2f } grounded { %.2f, %.2f, %.2f } (V at %.2f, %.2f, %.2f)")
      :format(tostring(how), pt.x, pt.y, pt.z,
              (grounded or pt).x, (grounded or pt).y, (grounded or pt).z, pp.x, pp.y, pp.z))
  return grounded or pt
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

-- A random V hang-up sign-off. v1.70: V HAS a voice now — the entries may be
-- { text =, sfx = } rows carrying one of her own recordings, or plain strings as before.
-- Returns text, sfx (sfx nil for a written line), so the caller can speak it and hold the
-- subtitle for the recording's real length instead of a flat 1.8 s.
local function pickFarewell()
  local f = Config.callFarewells
  if not f or #f == 0 then return "Later.", nil end
  local i = 1
  pcall(function() i = math.random(1, #f) end)
  local e = f[i] or f[1]
  if type(e) == "table" then return e.text or "Later.", e.sfx end
  return e, nil
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
      -- v1.77: LOG WHICH BRANCH RAN. "They just despawn" was reported against this row, and the two
      -- branches fail in ways that look identical from the pavement — so name the branch, every time.
      local returned = false
      if returnToPost then local ok, res = pcall(returnToPost); returned = ok and res == true end
      if returned then
        log("Dismiss: return-to-post — they stay in the world and re-join their venue.")
      elseif startLeaving then
        pcall(startLeaving)
      end
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
    -- v1.65: the dinner PAYS OFF here, at the stand-up — so an outing V abandons halfway (walks away,
    -- reloads, gets shot at) doesn't count. It's the biggest single award in the system on purpose:
    -- it's the one thing that costs real time, and time is what this whole curve is measuring.
    pcall(function() Fam.add("dinner") end)
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
  -- v1.65: he dropped what he was doing and came out. Small — answering the phone isn't intimacy — and
  -- awarded only past the two refusals above, so a declined call pays nothing.
  pcall(function() Fam.add("call") end)
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

-- v1.61 THE NEVER-IN-AIR FLOOR. Ground a candidate world point, GUARANTEEING the result is real walkable
-- ground (or nil only if the game itself is unqueryable). Snap the candidate to navmesh; if nothing snaps
-- (the candidate hangs over a void — a balcony, a railing, a rooftop edge), fall back to V's OWN position,
-- which is by definition on the human navmesh because she is standing on it. This is the hard floor under
-- EVERY spawn/teleport placement in the mod. The bug it kills: the old fallbacks were `snapToNavmesh(x) or x`
-- — when the snap failed they handed back the RAW ungrounded point, and over a balcony that point is thin
-- air (Antonia: "he spawns in the air in front of V if V is looking over a balcony"). There is no safe raw
-- point; the worst acceptable outcome is "on V, then he sorts himself out", never "floating".
-- Global -> 200-local cap safe.
function jlGrounded(candidate)
  local g = candidate and snapToNavmesh(candidate)
  if g then return g end
  local pp = playerPos()
  if pp then return snapToNavmesh(pp) or pp end   -- V's spot: snapped, else her exact pos (still real ground)
  return candidate                                 -- V unresolvable (≈never): last resort, original point
end

-- v1.59 "CAN HE ACTUALLY WALK THERE FROM V?" — the check snapToNavmesh cannot make.
-- snapToNavmesh only proves a point sits on SOME human navmesh. It says nothing about whether that navmesh
-- is connected to the patch V is standing on, so a point across a railing, a canal, or one storey down
-- passes it happily — and that is how a "recovered" Jackie ends up somewhere he can never path back from,
-- which simply re-triggers the recovery. NavigationSystem.CalculatePathOnlyHumanNavmesh
-- (`scripts/core/systems/navigationSystem.script:55`) answers the real question: it returns a NavigationPath
-- whose `path` array is non-empty only when a walkable route exists.
-- DEGRADES TO "YES": if the call can't be made on this build (renamed, or the NavGenAgentSize enum doesn't
-- marshal from CET), we return true — i.e. pre-v1.59 behaviour — and log it ONCE. A reachability test that
-- silently rejected everything would block every recovery and strand him, which is far worse than the bug
-- it fixes. Global -> 200-local cap safe.
function jlPathReachable(fromPt, toPt)
  if not (fromPt and toPt) then return true end
  local C = Config.catchUp or {}
  if C.requirePath == false then return true end
  local nav = Game.GetNavigationSystem(); if not nav then return true end
  local path, ok
  ok = pcall(function()
    -- NavGenAgentSize has the single member Human; fall back to the raw 0 if the enum doesn't marshal.
    local sz = NavGenAgentSize and NavGenAgentSize.Human
    path = nav:CalculatePathOnlyHumanNavmesh(fromPt, toPt, sz or 0, C.pathTolerance or 1.0)
  end)
  if not ok or path == nil then
    if not JL.pathApiWarned then
      JL.pathApiWarned = true
      log("Recovery: CalculatePathOnlyHumanNavmesh unavailable on this build -> reachability check SKIPPED " ..
          "(candidates are navmesh+height checked only, as before v1.59).")
    end
    return true
  end
  local n = 0
  pcall(function() n = #(path.path or {}) end)
  return n > 0
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
-- v1.59 `behindFirst`: flip the search order to BEHIND V -> her sides -> the front, and widen each sweep by
-- Config.catchUp.stillAngleSpread. Used by catchUpTick when V is STANDING STILL, for two reasons Antonia hit
-- in-game: a stationary V is usually looking straight at the front-side spot (so the recovery pops into
-- shot), and if she's at a railing there may be no walkable ground in front at all — which used to end with
-- him materialising in mid-air. A standing V doesn't care whether he's at the tuned abreast angle, so the
-- constraint is dropped exactly when it stops earning anything. While she's MOVING the front-side order
-- stands: dropping him behind a walking V only makes him chase her again.
function frontSideArrivalPoint(distance, jp, behindFirst)
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
  -- v1.59: BEHIND (out of a standing V's view, and usually the ground she just walked over) goes first when
  -- the caller asks for it; the near-front anchors stay first otherwise.
  local bases
  if behindFirst then
    bases = rightFirst and { fwdAng + math.pi, rAng, lAng, fwdAng } or { fwdAng + math.pi, lAng, rAng, fwdAng }
  else
    bases = rightFirst and { rAng, lAng, fwdAng } or { lAng, rAng, fwdAng }
  end
  -- v1.59: widen the per-base sweep when V is still — "he's allowed to be outside the abreast angles".
  local offs = { 0, 12, -12, 24, -24 }
  if behindFirst then
    local spread = (Config.catchUp or {}).stillAngleSpread or 75.0
    offs = { 0, 12, -12, 24, -24, spread * 0.5, -spread * 0.5, spread, -spread }
  end
  local maxZ  = (Config.vehicle and Config.vehicle.maxSpawnZDelta) or 4.0
  for _, baseAng in ipairs(bases) do
    for _, df in ipairs({ 1.0, 0.8, 0.6 }) do
      local d = distance * df
      for _, deg in ipairs(offs) do
        local a    = baseAng + math.rad(deg)
        local cand = Vector4.new(pp.x + math.cos(a) * d, pp.y + math.sin(a) * d, pp.z, 1.0)
        local snapped = snapToNavmesh(cand)
        -- v1.59: navmesh + height + REACHABLE ON FOOT FROM V. The third test is the one that keeps him off
        -- the wrong side of a railing (see jlPathReachable); it degrades to "accept" if the API is absent.
        if snapped and math.abs(snapped.z - pp.z) <= maxZ and jlPathReachable(pp, snapped) then
          log(("Recovery: %s point base=%+.0f off=%+.0f d=%.1f dZ=%+.1f -> { %.2f, %.2f, %.2f }")
              :format(behindFirst and "behind-first" or "front-side",
                      math.deg(baseAng), deg, d, snapped.z - pp.z, snapped.x, snapped.y, snapped.z))
          return snapped
        end
      end
    end
  end
  log(("Recovery: NO %s navmesh point found (navmesh + dZ<=%.0f + reachable-on-foot)."):format(
      behindFirst and "behind-first" or "front-side", maxZ))
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
-- ---------------------------------------------------------------------------
-- IS THIS BODY STILL THERE? — ask BEFORE writing to it. (ported from NCLives v1.78)
-- ---------------------------------------------------------------------------
-- ⚠️ THE FAST-TRAVEL CRASH. A load-screen fast travel tears the companion's body down while the
-- handle still resolves for a frame or two, and every write primitive below ends in SendCommand (or,
-- for Native.setCompanion, ScaleToPlayer / ChangeHighLevelState / SetAIRole / ai:OnAttach) on that
-- puppet. Those are NATIVE calls: the pcalls wrapped around them catch a Lua error and do nothing
-- whatsoever about the game falling over.
--
-- `if not handle` is a NIL check, NOT liveness. A handle outlives its entity by a frame or two, which
-- is precisely the window a fast travel lands in.
--
-- ⚠️ Guard the PRIMITIVES, not the callers. NCLives spent three rounds guarding call sites inferred
-- from the last line of a crash log — which is the last FLUSHED line, not necessarily the crashing
-- call — while sendWalkToPlayer, driven by the follow trail EVERY TICK, went unguarded the whole time.
--
-- ⚠️ FAILS OPEN. Unknown means "assume alive": skipping a body that IS there costs a companion who
-- stops following, and that trade is only worth making on a clear no.
-- GLOBAL -> 200-local cap safe.
function jlBodyAlive(h, key)
  if not h then return false end
  local attached
  pcall(function() attached = h:IsAttached() end)
  if attached == true  then return true  end
  if attached == false then return false end
  if key then return (function() local p; pcall(function() p = h:GetWorldPosition() end); return p ~= nil end)() end
  local pos
  pcall(function() pos = h:GetWorldPosition() end)
  return pos ~= nil
end

local function sendWalkToPlayer(handle, movementType, desiredDistance, stealth)
  if not handle then return false end
  -- ⚠️ v1.8.5 THE SEAT TUNER OUTRANKS EVERY MOVE ORDER, AND THIS IS WHERE THAT IS ENFORCED.
  -- Antonia, 2026-08-17: *"the fix for taking over control over her from her AI did not work...
  -- when I mean turn off the AI I mean OUR AI behavior, of which we have plenty"* — and she found
  -- the specific one: *"Goro seemed to want to move away from where I slid him to... because he
  -- wanted to be within the allowed leash around V distance?"* Exactly that. v1.84 took the GAME's
  -- command slot with jlHalt and stopped there, but our own ticks were re-issuing straight over the
  -- top of it. followKeepCloseTick, dinnerTick, the arrival machine, the rendezvous placer and the
  -- passenger/cruise ticks had no tuner guard at all.
  --
  -- Guarding each tick is how it was done before, and it is how this came back: the list is long,
  -- nobody can hold it in their head, and a new tick joins it silently. So the latch is enforced HERE
  -- instead — at the three functions that are the only way to tell this body to go somewhere. A tick
  -- that forgets the guard now simply cannot move a held puppet, including one written next year.
  -- ⚠️ jlHalt, placeAtExact and aiTeleport are deliberately NOT guarded: the tuner itself drives them.
  if jlPuppetHolds(handle) then return false end
  if not jlBodyAlive(handle) then return false end
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
  if jlPuppetHolds(handle) then return false end   -- v1.8.5: the seat tuner outranks every move order (see sendWalkToPlayer)
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
  if jlPuppetHolds(handle) then return false end   -- v1.8.5: the seat tuner outranks every move order (see sendWalkToPlayer)
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
  -- v1.77: this used to return SILENTLY with no handle, so a dismissal did nothing at all and left no
  -- trace. If the body can't be reached there is no walk-off to give — say so, so the log distinguishes
  -- "never started" from "walked off and despawned at distance" (leavingTick logs the latter).
  if not h then
    log("Dismiss: NO BODY to walk off (handle unresolved) — nothing to send home.")
    return
  end
  JL.leaving.paused = false            -- v1.62: a fresh walk-off never inherits a stale conversation-pause
  local D = Config.dismiss or {}
  opts = jlVar(opts or {})   -- v1.2: Hermano swap for an explicit parting line (e.g. mainQuestExit's "...mamita.")
  -- 1) parting line (real VO + subtitle), like any Jackie line. Capture its duration so we can WIPE the
  --    subtitle afterwards - a one-off speakJackieLine has no follow-up hide, so the line stuck forever.
  local secs = 4.0
  -- v0.94: parting line is a POOL (Config.dismiss.partingPool) picked at random each dismiss; falls back to
  -- the single partingText/partingSfx. An explicit opts.text (e.g. mainQuestExit) still overrides the pool.
  -- These are function-local (NOT main-chunk locals) so they don't count toward init.lua's 200-local cap.
  local pText, pSfx = D.partingText, D.partingSfx
  -- v1.69: one pool for both Vs. The old `partingPoolM` was a male duplicate whose "male clips" were
  -- wem stems the native path can't speak — so Hermano, the DEFAULT track, was the one that walked
  -- off in silence. These lines say "V", not a pet name, and the two that are gendered are gendered
  -- by the engine (vo_gender.lua subtitles them). See Config.dismiss.
  local ppool = D.partingPool
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
  -- v1.62: V opened a conversation mid-walk-off -> FREEZE the retreat (it's rude to keep walking away).
  -- No re-issue and no despawn while paused; Branch.finish resumes (or dinner cancels it for good).
  -- Safety net: if the choice box is no longer open (a close path that skipped Branch.finish), unpause so
  -- he can't get stuck frozen forever — leavingTick then re-issues the retreat on this very tick.
  if JL.leaving.paused then
    -- Branch.busy covers the gap while Jackie speaks his opening line (open flips true only once the
    -- choices appear); either being set means a conversation is still live, so stay frozen.
    if Branch and (Branch.open or Branch.busy) then return end
    JL.leaving.paused, JL.leaving.lastReissue = false, 0
    log("Departure auto-resumed — conversation box closed without Branch.finish.")
  end
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
    -- v1.8.2: THIS is the path Antonia hit — he walks off, vanishes, and scheduleTick (ungated the
    -- moment JL.summon.active goes false) spawns a fresh idle Jackie at the venue V is standing in.
    pcall(function() jlStampIdleCooldown("walked off") end)
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
  JL.leaving.subClearAt, JL.leaving.paused = nil, false   -- v1.62: drop any conversation-pause too
  JL.mainExit.activeSince, JL.mainExit.until_, JL.mainExit.warned, JL.mainExit.reminded = nil, nil, false, false
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
  if not jlBodyAlive(handle) then return false end   -- see jlBodyAlive
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
-- v1.77 `rejoin`: they were ALREADY with V and are simply going back on follow — after a meal, off
-- a bike, out of a cutscene. Pass true and they say nothing. Without it every re-promotion fires the
-- ARRIVAL GREETING below, so a companion who has been sitting across a table from V for an in-game
-- hour stands up and greets her like they have just turned up (Antonia, 2026-08-17). Omitting the
-- argument keeps the old behaviour, which is correct for every genuine arrival.
local function promoteToCompanion(rejoin)
  local h = JL.summon.spawn and JL.summon.spawn.handle
  if not h then return end
  -- v0.62: SAFETY dismount. On a bike arrival Jackie is sometimes STILL in the seat when he's
  -- promoted (the walk-phase unmount didn't take). Re-issue one unmount, but ONLY if he's really
  -- still mounted — so a foot arrival or an already-grounded Jackie never plays a phantom get-off.
  if unmountDriver and isMounted(h) then
    log("promoteToCompanion: Jackie still mounted -> safety dismount.")
    pcall(function() unmountDriver(h, JL.varrival and JL.varrival.bikeHandle) end)
  end
  -- v1.67: was `amm.Spawn:SetNPCAsCompanion(h)`. That call is AMM's, and AMM's version of it is the
  -- only reason Jackie has ever followed anyone. Native.setCompanion is the same job done against the
  -- base game's own API — and, unlike the AMM call, it VERIFIES the result instead of returning
  -- success either way. Mechanism and the script citations: native.lua's header.
  jlMakeCompanion(h)
  setFriendly(h)
  setVisible(h, true)   -- never leave him invisible
  setNpcCollision(h, true)   -- v0.44: a FOLLOWER must always collide (defensive: clears any idle/dinner
                             -- collision-off that could otherwise leak in and make him clip inside V)
  -- companion follow spacing so he holds ~followDistance and doesn't clip into V
  sendWalkToPlayer(h, (Config.call and Config.call.approachMovement) or "Run",
                      (Config.call and Config.call.followDistance) or 1.6)
  JL.summon.companionSet, JL.summon.walkIn = true, false
  JL.summon.arrivalGreetPending = not rejoin   -- v0.46/v0.48/v0.52: say a fresh greeting LINE once he closes to
                                              -- arrivalGruntDistance. v1.77: ...unless this is a REJOIN (see above).
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

-- ===========================================================================
-- v1.8.3 THE ARRIVAL SPAWN — ported from NCLives v1.83 (where it was Kerry turning up naked)
-- ===========================================================================
-- v1.77 armed the outfit re-assert at `resolveCompanionHandle()`, the chokepoint every spawn passes
-- through — and it still did nothing on the ARRIVAL paths, because `jlArmAppearanceFix` needs
-- `sp.appearance` and the three arrival spawns never set one. They called `spawnDynEntity(...)` with no
-- appearance argument at all, which becomes `spec.appearanceName = "default"`, and stamped a spawn
-- record of `{ id, handle }`. So the summon-by-phone path asked the engine for the record's bare
-- default body and then had nothing to verify against.
--
-- ⚠️ Jackie has been getting away with this: `Character.Jackie`'s own default IS his normal outfit, so
-- it looked fine. It is the same latent bug that shipped NCLives' Kerry naked — his record's default is
-- a bare body — and it also means his outfit was never actually verified. Fixed here for both reasons.
-- GLOBAL (200-local cap) — captures the spawnDynEntity local declared above; defined below it.
function jlSpawnArrivalBody(pt, yawDeg)
  local app = jlCompanionAppearance()
  local rec = Config.jackieRecord or "Character.Jackie"
  local jid = spawnDynEntity(rec, pt, yawDeg, "JackieLives_jackie", app)
  if not jid then return nil end
  -- v1.52: stamp so a post-load stale ref is dropped, not dereferenced. The appearance/record fields
  -- are what ammSpawn has always recorded; the arrival paths simply never did.
  return Session.stamp({ id = jid, handle = nil, appearance = app, record = rec })
end

-- Yaw (deg) so an entity at `from` faces V (so the bike points the way it will drive).
local function yawToward(from, to)
  if not from or not to then return 0.0 end
  return math.deg(math.atan2(to.y - from.y, to.x - from.x)) - 90.0
end

-- v1.62: rotate spawned Jackie IN PLACE to look at V (no move — same spot, new yaw). Used when a
-- conversation opens (it's rude to keep facing away) and by the main-quest warning. GLOBAL (200-local
-- cap) — captures the placeAtExact/yawToward/playerPos locals declared above.
function jlFaceV(handle)
  if not handle then
    local sp = JL.summon and JL.summon.spawn
    handle = sp and sp.handle
  end
  if not handle then return false end
  local jp; pcall(function() jp = handle:GetWorldPosition() end)
  local pp = playerPos()
  if not (jp and pp) then return false end
  return placeAtExact(handle, jp, yawToward(jp, pp))
end

-- v1.62: MAIN-QUEST GRACE. Called every tick while Jackie is an active, undismissed companion who
-- isn't at dinner or already walking off (the caller guards those). Instead of bolting the instant a
-- main quest goes active — which the game loves to auto-track the moment a side job ends — he WARNS and
-- waits Config.mainExitGrace.seconds. Drop the big fish inside that window and he STAYS; stay on it and
-- he leaves when the timer runs out. A cutscene still ejects him immediately. GLOBAL (200-local cap);
-- jlInCutscene is itself global so its later definition is fine (name resolved at call time).
function jlMainExitTick()
  local G  = Config.mainExitGrace or {}
  local me = JL.mainExit
  -- v1.62: don't arm/warn/expire while V is mid-conversation with him — the countdown FREEZES until the
  -- talk ends, so a grace timeout can't interrupt an open dialogue with a walk-off. (Branch.busy covers
  -- the gap while he speaks; Branch.open once the choices are up.)
  if Branch and (Branch.open or Branch.busy) then return end
  local cut  = false; pcall(function() cut  = jlInCutscene()      end)
  local main = false; pcall(function() main = isMainQuestActive() end)

  local now = JL.clock or 0

  -- Cutscene -> eject now (a cinematic is playing; no point counting down through it).
  if cut and G.immediateOnCutscene ~= false then
    me.activeSince, me.until_, me.warned, me.reminded = nil, nil, false, false
    log("Main-exit: cutscene -> Jackie leaves immediately.")
    pcall(function() startLeaving(Config.mainQuestExit) end)
    return
  end

  -- Grace switched off -> restore the old v0.62 behaviour (leave the instant a main quest is active).
  if not G.enabled then
    if main then
      log("Main quest -> Jackie excuses himself (grace disabled).")
      pcall(function() startLeaving(Config.mainQuestExit) end)
    end
    return
  end

  if main then
    -- Debounce: the game briefly auto-TRACKS a main quest the moment a side job ends. Wait armDelay
    -- seconds of *continuous* main-quest tracking before we warn, so a transient auto-select that V
    -- immediately replaces never triggers a bark.
    if not me.activeSince then me.activeSince = now end
    if not me.until_ then
      if (now - me.activeSince) < (G.armDelay or 2.0) then return end   -- still debouncing
      me.until_, me.warned, me.reminded = now + (G.seconds or 60.0), true, false
      if G.faceVOnWarn ~= false then pcall(jlFaceV) end
      pcall(function() speakJackieLine(G.warnText, G.warnSfx) end)
      if G.warnBanner then pcall(function() showOnscreenMsg(G.warnBanner, 8.0) end) end
      JL.ui.status = "Jackie: main-quest grace (~" .. tostring(math.floor(G.seconds or 60)) .. "s)."
      log(string.format("Main-exit: grace armed (%.0fs) — warn + wait.", G.seconds or 60.0))
      return
    end
    local left = me.until_ - now
    if not me.reminded and G.remindAt and G.remindAt > 0 and left <= G.remindAt then
      me.reminded = true
      pcall(function() speakJackieLine(G.remindText, G.remindSfx) end)
      log(string.format("Main-exit: reminder (%.0fs left).", left))
    end
    if left <= 0 then
      me.activeSince, me.until_, me.warned, me.reminded = nil, nil, false, false
      log("Main-exit: grace expired, still on the main quest -> Jackie heads out.")
      pcall(function() startLeaving(Config.mainQuestExit) end)
    end
    return
  end

  -- Main quest NOT active. Reset the debounce; if we'd actually WARNED (until_ set), V dropped the big
  -- fish in time -> he STAYS with a reassurance line. (A debounce that never armed clears silently.)
  me.activeSince = nil
  if me.until_ then
    me.until_, me.warned, me.reminded = nil, false, false
    pcall(function() speakJackieLine(G.stayText, G.staySfx) end)
    JL.ui.status = "Jackie: stayed (main quest dropped)."
    log("Main-exit: main quest dropped within grace -> Jackie stays.")
  end
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
  return jlGrounded(pt)   -- v1.61: never a raw ungrounded point (was `snapToNavmesh(pt) or pt`)
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
-- v1.68 — THIS IS ALSO WHERE THE FOLLOWER ROLE GETS APPLIED, and it has to be.
-- AMM used to make the body a follower AT SPAWN (`userSettings.spawnAsCompanion`), so the respawn
-- paths below — vehicleArrivalFootFallback's two fallbacks in particular — just set
-- `companionSet = (spawn ~= nil)` and never called promoteToCompanion(). The native backend can't do
-- that: a DES spawn has no handle for a frame or two, and you cannot assign an AI role to a body that
-- doesn't exist yet. So the flag rides on the spawn record (`companionFlag`, set by ammSpawn) and is
-- cashed in HERE, the one chokepoint every path goes through to first get a handle. One-shot, latched
-- on `sp.roleSet`. Miss this and those paths silently produce a Jackie who stands still.
local function resolveJackieHandle()
  local sp = JL.summon.spawn
  if not sp then return nil end
  local h = sp.handle
  if not h and sp.entityID then                           -- AMM shape: set synchronously by SpawnNPC
    pcall(function() h = Game.FindEntityByID(sp.entityID) end)
    if h then sp.handle = h end
  end
  if not h and sp.id then
    pcall(function() h = Game.FindEntityByID(sp.id) end)
    if h then sp.handle = h end
  end
  if h and sp.companionFlag == 1 and not sp.roleSet then
    sp.roleSet = true                                     -- latch FIRST: a failed call must not retry every frame
    jlMakeCompanion(h)
  end
  -- v1.77: the body exists now, so this is the first moment the outfit can be re-asserted AMM-style
  -- (the spec asked for it at CreateEntity, which is the request that loses the streaming race).
  -- Latched like roleSet: once per spawn record, never once per frame.
  if h and not sp.appArmed then
    sp.appArmed = true
    pcall(function() jlArmAppearanceFix(h, sp, "companion spawn") end)
  end
  return h
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
  local sp = jlSpawnArrivalBody(pt, yaw)   -- v1.8.3: WITH an outfit, and a record the appfix can verify
  if not sp then
    log("VehArrival: foot fallback fresh spawn FAILED -> companion fallback.")
    local spawn = ammSpawn(1, Config.defaultAppearance)
    JL.summon.spawn = spawn or nil
    JL.summon.active, JL.summon.companionSet, JL.summon.walkIn = true, (spawn ~= nil), false
    va.phase = nil; return
  end
  JL.summon.spawn = sp
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
  local sp = jlSpawnArrivalBody(pt, yawToward(pt, pp))   -- v1.8.3: WITH an outfit (see jlSpawnArrivalBody)
  if not sp then JL.ui.status = "Arrival spawn failed (see console)."; log("FootApproach: spawn failed."); return false end
  JL.summon.spawn = sp
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
    local sp   = jlSpawnArrivalBody(jpos, yaw)   -- v1.8.3: WITH an outfit
    if not va.bikeId or not sp then
      JL.ui.status = "Vehicle arrival spawn failed (see console)."
      log("VehArrival: spawn failed (bike=" .. tostring(va.bikeId ~= nil) .. ", jackie=" .. tostring(sp ~= nil) .. ")")
      despawnArrivalBike(); if sp and sp.id then deleteEntityById(sp.id) end; return
    end
    JL.summon.spawn = sp
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

-- v1.61: does this GameObject currently have a weapon DRAWN? Reads it the game's own way — the active
-- weapon in the WeaponRight/WeaponLeft attachment slots (GameObject.GetActiveWeapon, gameObject.script:757).
-- Non-nil AND not fists => armed. Any failure -> false ("assume holstered"), so a bad read never makes us
-- keep nagging him to holster. Global -> 200-local cap safe.
function jlWeaponDrawn(handle)
  if not handle then return false end
  local drawn = false
  pcall(function()
    local w = GameObject.GetActiveWeapon(handle)
    if not w then return end
    -- fists aren't a "drawn weapon" — GetActiveWeapon returns the fists object when empty-handed-combat.
    local isFists = false
    pcall(function() isFists = WeaponObject.IsFists(w:GetItemID()) end)
    drawn = not isFists
  end)
  return drawn
end

-- v1.61 HOLSTER JACKIE — issue AIUnequipCommand (aiCommand.script:383) for the right hand then the left,
-- the game's documented "put this slot's item away" command. ⚠️ The dump proves the command and its handler
-- (EquipItemCommandDelegate, aiEquipItemCommand.script) EXIST; it does NOT prove the follower behaviour tree
-- runs that task, so this is the in-game unknown (like the loiter hold command). It is the only holster lever
-- I could verify as constructible from CET — if it proves inert in testing, the fallback to research is an
-- UpperBody "ForceEmptyHands" animation event, which isn't cleanly constructible here yet.
-- pcall-guarded; returns true if a command issued without erroring (NOT proof it took — the caller re-checks
-- jlWeaponDrawn and keeps re-issuing). Global -> 200-local cap safe.
function jlHolster(handle)
  if not handle then return false end
  if not jlBodyAlive(handle) then return false end   -- see jlBodyAlive
  local any = false
  for _, slot in ipairs({ "AttachmentSlots.WeaponRight", "AttachmentSlots.WeaponLeft" }) do
    local ok = pcall(function()
      local cmd = NewObject('handle:AIUnequipCommand')
      cmd.slotId = TweakDBID.new(slot)
      handle:GetAIControllerComponent():SendCommand(cmd)
    end)
    any = any or ok
  end
  return any
end

-- v1.61 WEAPON MIRROR TICK. "Jackie puts his guns away when V does." If V's weapon is holstered and neither
-- of them is in combat, but Jackie's is still drawn, holster him — and keep re-issuing (throttled) until his
-- hands read empty, because a single command often loses a race with his combat-exit animation. An episode
-- resets the moment V draws again or a fight starts, so this never fights a legitimate armed moment.
-- Global -> 200-local cap safe.
function jlWeaponMirrorTick()
  local W = Config.weaponMirror or {}
  if W.enabled == false then return end
  local st = JL.weaponMirror
  if W.onlyWhenCompanion ~= false and not (JL.summon.active and JL.summon.companionSet) then
    st.since, st.reasserts, st.lastAt = nil, nil, nil; return
  end
  local h = JL.summon.spawn and JL.summon.spawn.handle
  if not h then st.since, st.reasserts, st.lastAt = nil, nil, nil; return end
  local pl = Game.GetPlayer(); if not pl then return end
  local now = JL.clock or 0
  -- Only act in the calm case: V's weapon away, and nobody fighting. Any of these false -> reset the episode
  -- so we start clean next time V holsters (and never nag him mid-fight or while V herself is armed).
  if jlInCombat() or jlWeaponDrawn(pl) then st.since, st.reasserts, st.lastAt = nil, nil, nil; return end
  -- V is peaceful and unarmed. Is Jackie still holding a gun?
  if not jlWeaponDrawn(h) then st.since, st.reasserts, st.lastAt = nil, nil, nil; return end
  -- start the grace timer; let a brief lull settle before insisting (V may re-draw within a second).
  st.since = st.since or now
  if (now - st.since) < (W.graceSeconds or 1.0) then return end
  if (st.reasserts or 0) >= (W.maxReasserts or 6) then return end        -- gave it a fair few tries
  if (now - (st.lastAt or -1e9)) < (W.interval or 0.5) then return end
  st.lastAt    = now
  st.reasserts = (st.reasserts or 0) + 1
  jlHolster(h)
  log(("WeaponMirror: V unarmed + calm but Jackie armed -> holster (try %d/%d)."):format(
      st.reasserts, W.maxReasserts or 6))
end

-- v1.8.3 (ported from NCLives v1.83): the blind-body branch, lifted OUT of catchUpTick so it can be
-- asked BEFORE the combat/phase guards (see ceiling #2 there). Returns true when it has consumed this
-- tick — the companion has no readable position, so nothing below it has anything to reason about.
-- Global -> 200-local cap safe.
-- v1.8.5 WHICH DINNER PHASES ACTUALLY OWN THE BODY — and it is not all of them.
-- Antonia, 2026-08-17: *"she did follow me slowly again after fast travel... I even sprinted... it
-- just seems that she's not under full control of our mod?"* Both of her slow-follow reports were
-- during a dinner outing, and that is not a coincidence.
--
-- `dinnerTick`'s `walking` branch issues NO movement command at all — read it: it only watches V's
-- distance to `dest` and waits. The companion is supposed to be an ordinary follower for the whole
-- walk to the restaurant. But catch-up, walk-beside, the keep-close leash and the follower-role
-- watchdog all stood down on a bare `dinner.phase`, so for that entire walk NOTHING in this mod was
-- commanding them and they coasted on the base-game follower trail — which is slow, and which no
-- amount of sprinting by V can speed up. The walk probe had already said so in as many words:
-- "⚠ STUCK PHASE ... Nothing is actually moving them".
--
-- Only `seating` and `seated` genuinely own the body: seating sends its own move-to-the-seat and may
-- snap+pose, and seated is a posed puppet nothing else may touch.
-- ⚠️ This is deliberately NOT used by the auto-leave pause (which must stay off for the WHOLE outing,
-- walking included) — that one wants "is a meal happening at all", a different question.
-- Global -> 200-local cap safe.
function jlDinnerOwnsBody()
  local p = JL.dinner and JL.dinner.phase
  return p == "seating" or p == "seated"
end

function jlCatchUpBlind(C)
  C = C or Config.catchUp or {}
  local h = JL.summon.spawn and JL.summon.spawn.handle
  if not h then return false end
  local now = JL.clock or 0
  local jp = nil; pcall(function() jp = h:GetWorldPosition() end)
  if jp then JL.catchUp.blindSince = nil; return false end
  -- ⚠️ v1.74 — PORTED FROM NCLIVES. THE HOLE THAT ATE A COMPANION ON A FAST TRAVEL (Antonia,
  -- 2026-08-14, NCLives: "she vanished, distance to V 1165 m in red, companion true", and NOT ONE
  -- CatchUp line in the log).
  --
  -- This used to be `if not jp then return end`. Every escalation below — including the
  -- respawn-when-stranded ladder written specifically for district-scale fast travel — is gated on
  -- `d`, the distance to their body. So the one case it could never handle was the case where THERE
  -- IS NO BODY TO MEASURE: a load-screen fast travel culls the spawned NPC outright, the handle stays
  -- valid (which is why the window still says "companion: true"), and the position read returns nil
  -- forever. The function then returned on this line every tick, silently, and nobody ever came back.
  -- Travelling back did not fix it either, because nothing re-armed.
  --
  -- ⚠️ It is NOT about AMM. This code path is the same one AMM installs ran; AMM only ever supplied
  -- the spawn call. The bug is that "far away" and "gone" were treated as the same question and only
  -- one of them had an answer.
  --
  -- So: an unreadable position is its OWN stranded condition. Sustain it briefly (a stream hiccup
  -- while crossing a district boundary reads identically for a frame or two, and respawning on that
  -- would visibly duplicate them), then take exactly the escalation the distance ladder would have
  -- taken. `blindSustain` is deliberately longer than `sustainSeconds`: a wrong answer here costs a
  -- despawn+respawn the player can see.
  do
    -- ⚠️ THE LOAD-SCREEN CRASH GUARD, and it is load-bearing now that this runs ABOVE the rest of the
    -- tick (it used to inherit catchUpTick's own `local pp = playerPos(); if not pp then return end`).
    -- The body becomes unreadable AT THE START of a load, so `blindSustain` can elapse while the world
    -- is still streaming — and respawning into a not-yet-streamed world is the v0.84 load crash,
    -- verbatim. While the PLAYER is not in the world this is a load screen, not a stranding.
    if not playerPos() then JL.catchUp.blindSince = nil; return true end
    JL.catchUp.blindSince = JL.catchUp.blindSince or now
    if (now - JL.catchUp.blindSince) < ((C.blindSustain or 6.0)) then return true end
    if (now - (JL.catchUp.lastAt or -1e9)) < (C.cooldown or 3.0) then return true end
    JL.catchUp.lastAt, JL.catchUp.farSince, JL.catchUp.teleTries = now, nil, nil
    JL.catchUp.lastDist, JL.catchUp.graceSince, JL.catchUp.blindSince = nil, nil, nil
    log(("CatchUp: companion body is UNREADABLE for %.0fs (culled by a load screen / fast travel) " ..
         "-> respawning at V. A teleport cannot reach a body that no longer exists.")
        :format(C.blindSustain or 6.0))
    pcall(respawnCompanionAtV)
    return true
  end
end

-- ⚠️ GLOBAL, not a file-local (ported from NCLives v1.75's reasoning): loadsim can only drive a global,
-- and this is the function that decides whether a stranded companion is ever recovered — the one
-- behaviour that has cost the most in-game sessions, so it must be testable offline. Making it global
-- also FREES a local slot against init.lua's 200-local cap rather than spending one.
function catchUpTick()
  if jlPuppetHolds() then return end   -- v1.9: seat tuner owns this body (catch-up would snap him back to V's side mid-slide)
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
  -- ⚠️ THE CEILING ON EVERY GUARD BELOW (ported from NCLives v1.75). Read the distance FIRST, and if
  -- it is district-scale, nothing under this line gets a vote: not combat, not a phase, not the
  -- patience timers. A companion 1800 m away is not fighting beside V and is not walking to a
  -- restaurant — they were left behind by a fast travel, and the only thing that closes that gap is a
  -- respawn. Deliberately BEFORE the combat and phase guards, because those are the two that swallow
  -- it: the reported case stood down on "a phase owns their movement" forever.
  -- ⚠️ Unseat BEFORE despawning. A dinner means a seated puppet, and every dismiss path in this file
  -- already stands one up first.
  do
    local hh = JL.summon.spawn and JL.summon.spawn.handle
    local ppq = playerPos()
    if hh and ppq and jlBodyAlive(hh) then
      local jq; pcall(function() jq = hh:GetWorldPosition() end)
      local dq = jq and dist3(ppq, jq) or nil
      if dq and dq >= ((Config.catchUp or {}).hardRespawnDistance or 300.0)
         and ((JL.clock or 0) - (JL.catchUp.lastAt or -1e9)) >= ((Config.catchUp or {}).cooldown or 3.0) then
        JL.catchUp.lastAt = (JL.clock or 0)
        JL.catchUp.farSince, JL.catchUp.teleTries = nil, nil
        JL.catchUp.lastDist, JL.catchUp.graceSince, JL.catchUp.blindSince = nil, nil, nil
        -- ⚠️ v1.8.5 A FAST TRAVEL MUST NOT EAT THE DINNER. Antonia, 2026-08-17: *"when I just fast
        -- travelled with Lucy to get to the Ginger Panda (on a mission to have a dinner with her
        -- there) she forgot and the white marker disappeared from the map and I couldn't start the
        -- dinner."* This path fires on every district-scale fast travel and used to abort the outing
        -- outright. For a SEATED companion that is correct — despawning a posed puppet is the
        -- documented hard crash. For one still WALKING to the venue it is pure loss: the destination
        -- is a fixed world coordinate, the pin points at a restaurant that has not moved, and the
        -- respawn only puts their body back beside V. It was self-defeating in her exact case, too —
        -- she fast-travelled TO the venue, so keeping the outing lands her straight in the seating
        -- phase instead of losing the marker. `seating`/`seated` still abort: V has already arrived,
        -- and those are the phases where a posed body can exist.
        local keepDinner = (JL.dinner.phase == "walking") and JL.dinner.dest ~= nil
        pcall(function() jlManualUnseat("catch-up respawn") end)
        if not keepDinner then
          pcall(function() clearDinnerWaypoint() end)
          JL.dinner.phase, JL.dinner.dest = nil, nil
        else
          log("CatchUp: KEEPING the walk to " .. tostring(JL.dinner.destName or "the venue") .. ".")
        end
        JL.leaving.phase = nil
        if JL.varrival then JL.varrival.phase = nil end
        log(("CatchUp: %.0f m is beyond anything that can be walked or teleported back " ..
             "-> respawning at V regardless of what else is running."):format(dq))
        pcall(respawnCompanionAtV)
        return
      end
    end
  end

  -- ⚠️ CEILING #2, PORTED FROM NCLIVES v1.83 — the OTHER half of the ceiling above, and the half that
  -- was missing here too. (Antonia, 2026-08-17, on NCLives: "Kerry didn't follow my fast travel after I
  -- started the dinner objective." Panam, same save, same travel, DID — the only difference being that
  -- her body was still readable and his was not.)
  --
  -- Ceiling #1 ranks a district-scale DISTANCE above every guard. But a load-screen fast travel has two
  -- endings and only one of them is a distance: the body survives far away (readable -> #1 fires) or it
  -- is CULLED (unreadable -> there is nothing to measure at all). The v1.74 blind-body branch handles
  -- the second case perfectly — and it sat BELOW the phase guard, so a companion who was mid-dinner-walk
  -- when V travelled stood down on "a phase owns their movement" forever, exactly the case #1 exists for.
  if jlCatchUpBlind(C) then return end

  if jlInCombat() then JL.catchUp.farSince, JL.catchUp.teleTries = nil, nil; return end
  if jlDinnerOwnsBody() or JL.leaving.phase or (JL.varrival and JL.varrival.phase)
     or (jlCruise and jlCruise.active) then   -- v0.85: don't teleport him off his cruising bike
    JL.catchUp.farSince, JL.catchUp.teleTries = nil, nil; return
  end
  local h = JL.summon.spawn and JL.summon.spawn.handle
  if not h then JL.catchUp.farSince = nil; return end
  local pp = playerPos(); if not pp then return end
  local now = JL.clock or 0
  local jp = nil; pcall(function() jp = h:GetWorldPosition() end)
  if not jp then return end   -- v1.8.3: handled by jlCatchUpBlind, above every other guard
  JL.catchUp.blindSince = nil
  local d   = dist3(pp, jp)
  -- back within range -> the last teleport (if any) took; clear the retry counter.
  if d <= (C.distance or 25.0) then
    JL.catchUp.farSince, JL.catchUp.teleTries = nil, nil
    JL.catchUp.lastDist, JL.catchUp.graceSince = nil, nil
    return
  end
  -- he's far. Require it to PERSIST a beat (a fast-travel/load gap, not a momentary stream hiccup).
  JL.catchUp.farSince   = JL.catchUp.farSince or now
  JL.catchUp.graceSince = JL.catchUp.graceSince or now
  -- v1.59 PROGRESS GRACE. A bare timer treats "stuck behind a fence" and "sprinting back, 8 m closer than
  -- last tick" identically, so a Jackie who only needed a few more seconds got yanked — and a teleport in
  -- front of V is exactly what Antonia was seeing. While the gap is genuinely CLOSING, push the timer back
  -- and let him run. `maxGraceSeconds` caps it from graceSince, so a Jackie inching forward against geometry
  -- (or one who closes 0.6 m then stalls, over and over) still gets rescued rather than deferring forever.
  if C.progressGrace ~= false then
    local prev = JL.catchUp.lastDist
    if prev and (prev - d) >= (C.progressEpsilon or 0.5)
       and (now - JL.catchUp.graceSince) < (C.maxGraceSeconds or 20.0) then
      JL.catchUp.farSince = now                 -- he's closing: restart the patience clock
    end
  end
  JL.catchUp.lastDist = d
  if (now - JL.catchUp.farSince) < (C.sustainSeconds or 4.0) then return end
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
    JL.catchUp.lastDist, JL.catchUp.graceSince = nil, nil
    log(("CatchUp: Jackie stranded %.0f m from V (teleport can't cross) -> respawning at her side."):format(d))
    pcall(respawnCompanionAtV)   -- despawns the orphaned body + spawns fresh at V; onUpdate re-promotes next frame
    return
  end

  -- moderate gap, body still local: land him a few metres AHEAD/beside V on the navmesh (never ON V, never
  -- BEHIND into the wall at a fast-travel point), then re-assert follow. v1.40: prefer the front-side point
  -- (reuses the walk-abreast angles, picks the side he's already on via `jp`); fall back to the old
  -- side/behind navmesh sweep, then a plain forward point. Count the attempt so a no-op teleport escalates
  -- to a respawn on the next eligible tick.
  -- v1.59: when V is STANDING STILL, search BEHIND her first (out of shot, and real ground — the front-side
  -- spot is both what she's looking at and, at a railing, often thin air), with a widened angle sweep.
  -- "Is V standing still?" must NOT depend on the loiter-halt feature being switched on (jlVLoitering short-
  -- circuits to false when Config.loiter.enabled is off), so fall back to the raw smoothed speed.
  local behindFirst = false
  if C.preferBehindWhenStill ~= false then
    jlVWalking()          -- refresh the shared per-frame speed EMA before reading it
    behindFirst = jlVLoitering()
                  or ((JL.abreast.vSpeed or 0.0) <= ((Config.loiter or {}).stopSpeed or 0.55))
  end
  local pt = frontSideArrivalPoint(C.placeDistance or 3.0, jp, behindFirst)
             or navmeshArrivalPoint(C.placeDistance or 3.0)
  -- v1.59: the old third fallback was `arrivalPoint()`, which ends in `snapToNavmesh(pt) or pt` — i.e. it
  -- hands back a RAW, unvalidated forward point when nothing snaps. That is precisely how he materialised in
  -- mid-air in front of a V leaning over a balcony. There is no safe unvalidated point: if nothing walkable
  -- was found, do NOTHING this tick. He keeps walking (the trail is sprinting him home), the cooldown holds,
  -- and we try again shortly — or, if he really is stuck, the teleTries ladder escalates to a clean respawn.
  if not pt then
    log(("CatchUp: %.0f m out but NO reachable landing point near V -> not teleporting (he keeps walking)."):format(d))
    return
  end
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
  return jlAbreastWhy() == nil
end

-- v1.8.3 THE SAME PREDICATE, BUT IT SAYS WHY (ported from NCLives v1.83). Eleven gates, and the failure
-- looks identical from outside all of them: the companion trails. So the gates live here, each returning
-- a stable one-line reason, and jlAbreastOn is just "no reason". jlWalkProbeTick prints the reason
-- whenever it CHANGES, which turns "sometimes he walks wrong" into a named guard in the log.
-- ⚠️ The reasons are CONSTANT strings on purpose — this runs several times a frame, and building a
-- message with the numbers in it would allocate every frame for a line nobody reads. The numbers are the
-- probe's job; this only names the guard. Global -> 200-local cap safe.
function jlAbreastWhy()
  local A = Config.abreast or {}
  if not A.enabled then return "walk-beside disabled in config" end -- v1.57: opt-in; default = plain trailing follower
  if not JL.walkAbreast then return "walk-beside switched OFF in settings" end
  if not (JL.summon.active and JL.summon.companionSet) then return "not a settled companion" end
  -- v1.8.5: only seating/seated own the body — see jlDinnerOwnsBody. A `walking` dinner falls THROUGH
  -- to the gates below, so the probe keeps naming the guard that is really refusing.
  if jlDinnerOwnsBody() then return "the DINNER phase owns his movement" end
  if JL.leaving.phase then return "the LEAVING phase owns his movement" end
  if JL.varrival and JL.varrival.phase then return "the ARRIVAL phase owns his movement" end
  if jlCruise and jlCruise.active then return "cruising on the bike" end   -- not while cruising on his bike
  if jlTakedownBusy() then return "mid-takedown" end                       -- v1.48: a takedown owns him
  if jlInCombat() then return "V is in combat" end                         -- fighting -> free him to fight
  if jlVertical() then return "stairs/slope -> single file" end            -- v1.46
  if jlVSneaking() then return "V is crouched" end                         -- v1.46: shadow her, never lead
  -- v1.57: V is basically standing -> the TRAIL owns him, because that's where the loiter halt lives. With
  -- stock values jlVWalking() already says no here (stopSpeed sits below walkMinSpeed), but the two are
  -- independently tunable now, so state it explicitly rather than rely on the bands not overlapping — if
  -- both ticks thought they owned him he'd be shoved to a side anchor and told to hold still at once.
  if jlVLoitering() then return "V is standing still (loiter)" end
  if not jlVWalking() then return "V isn't in the steady-walk band" end
  return nil
end

-- ---------------------------------------------------------------------------
-- v1.8.3 WALK PROBE (ported from NCLives v1.83)
-- ---------------------------------------------------------------------------
-- A companion who trails when he should be beside V looks the same whichever of the eleven gates above
-- refused, and the phase guards can be STUCK — a dinner/arrival flag that was never cleared reads as
-- "something owns his movement" forever, and catch-up stands down on the same flag. So this writes the
-- one fact that separates them, to the log, with no console and no hotkey:
--   * EDGE — every time the reason changes: "beside OFF -> the ARRIVAL phase owns his movement".
--   * HEARTBEAT — every `interval` s while he is out and V is moving: the numbers.
--   * STUCK — once per episode, if a phase guard has held for `stuckSeconds` while he stands next to V.
--     A phase that owns his movement while he is 2 m away and idle is not owning anything; that line IS
--     the bug report.
-- Global -> 200-local cap safe.
function jlWalkProbeTick()
  local P = Config.walkProbe or {}
  if P.enabled == false then return end
  local st = JL.walkProbe; if not st then st = {}; JL.walkProbe = st end
  local now = JL.clock or 0
  local h   = JL.summon.spawn and JL.summon.spawn.handle
  if not (JL.summon.active and h) then
    st.why, st.whySince, st.stuckLogged, st.lastBeat = nil, nil, nil, nil
    return
  end
  local why = jlAbreastWhy()

  local function readout()
    local pp, jp = playerPos(), nil
    pcall(function() jp = h:GetWorldPosition() end)
    local d = (pp and jp) and dist3(pp, jp) or nil
    return ("V=%.2f m/s | d=%s m | phases: arrival=%s dinner=%s leaving=%s | catching=%s waiting=%s")
      :format(JL.abreast.vSpeed or 0.0, d and ("%.1f"):format(d) or "?",
              tostring(JL.varrival and JL.varrival.phase), tostring(JL.dinner.phase),
              tostring(JL.leaving.phase), tostring(JL.abreast.catching), tostring(JL.abreast.waiting))
  end

  if why ~= st.why then
    st.why, st.whySince, st.stuckLogged = why, now, nil
    log(("[WalkProbe] beside %s | %s"):format(why and ("OFF -> " .. why) or "ON", readout()))
  end

  if why and why:find("owns his movement", 1, true) and not st.stuckLogged
     and (now - (st.whySince or now)) >= (P.stuckSeconds or 45.0) then
    local pp, jp = playerPos(), nil
    pcall(function() jp = h:GetWorldPosition() end)
    local d = (pp and jp) and dist3(pp, jp) or nil
    if d and d <= (P.stuckNearMetres or 15.0) then
      st.stuckLogged = true
      log(("[WalkProbe] ⚠ STUCK PHASE: %s and has for %.0f s, while he stands %.1f m from V. " ..
           "Nothing is actually moving him — walk-beside AND catch-up are both standing down on this " ..
           "flag, which is why a fast travel is ignored and why only a catch-up respawn 'fixes' it. %s")
          :format(why, now - (st.whySince or now), d, readout()))
    end
  end

  if (now - (st.lastBeat or -1e9)) >= (P.interval or 15.0) then
    st.lastBeat = now
    if (JL.abreast.vSpeed or 0.0) > (P.beatMinSpeed or 0.3) then
      log(("[WalkProbe] %s | %s"):format(why and ("off: " .. why) or "beside", readout()))
    end
  end
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
  if jlDinnerOwnsBody() or JL.leaving.phase or (JL.varrival and JL.varrival.phase)
     or (jlCruise and jlCruise.active) then return end   -- v0.85: leave him on his cruising bike
  local h = JL.summon.spawn and JL.summon.spawn.handle
  if not h then return end
  local now = JL.clock or 0
  -- v1.57: the geometry reads moved ABOVE the re-issue throttle so the loiter halt below can react within
  -- its own sustain window instead of waiting out F.interval (1.5 s) as well.
  -- don't fight the catch-up teleport: if he's far enough for that to own him, leave it.
  local pp = playerPos(); if not pp then return end
  local jp; pcall(function() jp = h:GetWorldPosition() end); if not jp then return end
  -- v1.59 RUN HIM HOME. This used to be a bare `return` — "catch-up owns him out here". It didn't: catch-up
  -- only ever TELEPORTS, so beyond this distance nobody was commanding him at all and he coasted on a stale
  -- order. That is a large part of why the teleport looked necessary so often. Now the trail keeps issuing a
  -- SPRINT follow while he's out there, which is what gives Config.catchUp.progressGrace something to
  -- measure — he closes the gap himself, and the teleport stays the last resort it was meant to be.
  if dist3(pp, jp) > ((Config.catchUp and Config.catchUp.distance) or 25.0) then
    if (now - (JL.follow.lastAt or -1e9)) >= (F.interval or 1.5) then
      JL.follow.lastAt = now
      sendWalkToPlayer(h, (Config.catchUp and Config.catchUp.chaseMovement) or "Sprint", jlFollowDistance())
    end
    return
  end
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
--  * DEFAULT-ON (v1.61; was opt-in in v1.57). `JL.walkAbreast` (Esc -> Settings -> Jackie Lives -> Gameplay) turns this whole
--    behaviour ON. It is OFF by default — out of the box Jackie is the plain trailing follower.
-- Command re-issue is throttled to `interval` (short, so he tracks the drifting anchor). Global -> cap safe.
function abreastTick()
  if jlPuppetHolds() then return end   -- v1.9: seat tuner owns this body (walk-abreast re-issues a position every tick)
  local A = Config.abreast or {}
  -- v1.46: every gate now lives in jlAbreastOn() (shared with followKeepCloseTick's yield test), so the
  -- trail picks him up in exactly the cases abreast declines him — stairs and slopes included.
  if not jlAbreastOn() then
    JL.abreast.smFwdX = nil     -- reset the heading EMA so it re-seeds cleanly when abreast resumes
    JL.abreast.catching = nil   -- v1.36: re-engage re-evaluates behind/hold from scratch
    JL.abreast.waiting, JL.abreast.waitHoldAt = nil, nil   -- v1.8.3: and never resume mid-wait
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
  -- AHEAD of the anchor along V's heading so he strolls FORWARD with V inside the wide leash instead of
  -- stop-starting on the exact spot.
  --
  -- ---- v1.8.3 (A) THE LOOKAHEAD IS A TIME, NOT A DISTANCE (ported from NCLives v1.67) ----------------
  -- Antonia, 2026-08-17: *"Jackie often very aggressively walks ahead too fast and then is stuck at the
  -- edge of his leash and doesn't fall back well. This aspect of his movement looks broken."*
  --
  -- `leadDistance` was a flat 2 m, which is only correct at one walking speed. Slow V down and that
  -- constant point sits permanently in front of a companion who already out-walks her: he can never
  -- arrive, he steps forward on every re-issue, and once he is ahead the rear-arc test (which only fires
  -- BEHIND) can never pull him back. `V's speed x leadSeconds` is the standard pure-pursuit lookahead —
  -- scale-invariant, and it collapses to nothing by itself as she slows to a stop.
  local lead = A.leadDistance or 2.0
  if A.leadSeconds then
    lead = math.min((JL.abreast.vSpeed or 0.0) * A.leadSeconds, A.leadMax or 2.5)
  end
  local destX = sprinting and tx or (tx + sx * lead)
  local destY = sprinting and ty or (ty + sy * lead)

  -- ---- v1.8.3 (B) AND WHEN HE IS ALREADY AHEAD, HE WAITS --------------------------------------------
  -- (A) alone stops him RUNNING ahead; it cannot bring back one who already is. NCLives brakes with a
  -- sub-1.0 time dilation, and this repo deliberately has no dilation channel at all (v1.39: "scaling his
  -- time made his stride float and broke the angular leash"), so the only honest brake here is to stop
  -- giving him somewhere to go. `aerr` is the along-track error — how far ahead of HIM his spot is,
  -- measured along V's heading. Negative means he has overrun it. Past `waitAhead` he plants himself and
  -- lets V walk up, which is what a person does; the hysteresis (release at the smaller `waitRelease`)
  -- is what stops that becoming a stutter, and it re-issues on the loiter hold interval because the hold
  -- command is time-limited — the same shape the loiter halt in followKeepCloseTick already uses.
  if not sprinting and (A.waitWhenAhead ~= false) then
    local aerr = (destX - jp.x) * sx + (destY - jp.y) * sy
    local st   = JL.abreast
    if st.waiting then
      if aerr >= -(A.waitRelease or 0.4) then st.waiting = false end
    elseif aerr <= -(A.waitAhead or 1.2) then
      st.waiting = true
    end
    if st.waiting then
      if (now - (st.waitHoldAt or -1e9)) >= ((Config.loiter or {}).holdInterval or 2.0) then
        st.waitHoldAt = now
        jlHalt(h)
      end
      return
    end
    st.waitHoldAt = nil
  end

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
      openChoiceMenu(withCompanionExtras(withDateChoices(bstate.node, bstate.node.choices)), "Jackie", bstate.node)
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
          -- v1.70: the sign-off is spoken now, and the hang-up waits for the RECORDING rather
          -- than a flat 1.8 s. Cutting the line off mid-word is the whole reason the old
          -- fixed hold could not stay.
          local fText, fSfx = pickFarewell()
          local fHold = nil
          pcall(function() fHold = jlSpeakPlayerLine(fSfx, fText) end)
          fHold = (fHold and (fHold + 0.4)) or 1.8
          showDialogueText("V", jlLineText(fText, fSfx), fHold, Game.GetPlayer())
          JL.call.hangupAction = act
          JL.call.hangupAt = (JL.clock or 0) + fHold
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

-- v1.77: is AUTOMATIC sit/lean on? Ships FALSE (Config.poses.enabled) — see the long note on that
-- config block. Every engine-driven sit asks this first; the player's "Seat them here" button is the
-- one caller allowed past it, and it says so by passing `force`.
-- GLOBAL on purpose: read from dinnerTick, applyIdlePose and onDraw, and init.lua is at the 200-local cap.
function jlSitPosesOn()
  local P = Config.poses
  return (P and P.enabled) and true or false
end

-- Play a real sit/lean animation on Jackie using AMM's proven Poses pipeline. Returns true if
-- the call went through (no guarantee it visually took — guarded; falls back to standing).
-- v1.77 `force`: play it even though automatic sitting is off. ONLY the manual "Seat them here"
-- button passes this — it is the player looking at the chair and saying "there".
local function tryWorkspotPose(handle, pose, nameOverride, force)
  local P = Config.poses
  if not P then return false end
  if not (P.enabled or (force and P.manual ~= false)) then return false end
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
  -- v1.77: with automatic sitting off, a sit/lean waypoint is just a STANDING spot. Skip the
  -- poseOffset (it lowers him onto a seat plane he's no longer using) and skip the pendingPose chain
  -- below — that chain ends in placeAtExact, which does NOT nav-snap, and is exactly how a standing
  -- NPC ends up hovering. aiTeleport's nav test keeps him on the floor.
  local sitOn = jlSitPosesOn()
  local v = wpVec4(wp)
  if sitOn and (wp.pose == "sit" or wp.pose == "lean") and wp.poseOffset then
    v = Vector4.new(wp.pos[1] + (wp.poseOffset.x or 0), wp.pos[2] + (wp.poseOffset.y or 0),
                    wp.pos[3] + (wp.poseOffset.z or 0), 1.0)
  end
  if forceSnap or W.faceYawOnArrive ~= false then
    pcall(function() aiTeleport(handle, v, wp.yaw or 0.0) end)   -- nav-snap walk to roughly the spot
  end
  if sitOn and (wp.pose == "sit" or wp.pose == "lean") then
    -- v0.45: carry the EXACT pos + yaw so the deferred fire can lock his seat position AND facing
    -- (placeAtExact) right before the workspot plays — fixes the wrong-seat-angle on arrival.
    JL.idle.pendingPose = { pose = wp.pose, name = wp.poseAnim, vec = v, yaw = wp.yaw or 0.0,
                            at = (JL.clock or 0) + ((Config.poses and Config.poses.delay) or 0.5) }
  else
    JL.idle.pendingPose, JL.idle.pendingSit = nil, nil
  end
end

-- ===========================================================================
-- v1.9 THE SEAT TUNER — a puppet manipulation tool
-- ===========================================================================
-- Antonia, 2026-08-17: *"the seat tuner menu is just a puppet manipulation tool: make them dumb,
-- shove them forward/backward/left and right and play their seating animation."* That is the whole
-- design, and it replaces v1.77's split into a "sitting" section and a "tuner" section — one job,
-- one panel.
--
-- Automatic sitting is off (Config.poses.enabled ships false): AMM's sit is a FREESTANDING animation
-- rooted at whatever point we drop the NPC on, so on an untuned venue seat it reads as sitting in
-- mid-air. Aligning it is a job for someone LOOKING at the chair, which is the player. So the panel
-- hands them the three things that job actually needs, in the order it needs them:
--
--   1. MAKE THEM DUMB.  A companion is running follow AI. It re-issues a move command every couple of
--      seconds and re-asserts the follower role, and both of those FIGHT the pose: the NPC drifts back
--      toward V and the workspot is cancelled from under you. Nothing else here works until the AI is
--      off, which is why "take control" is step one and not a footnote.
--   2. DROP COLLISION.  A chair is solid. A collided NPC shoved into one is pushed straight back out,
--      so the seat you tuned is not the seat they end up in.
--   3. MOVE AND POSE.   Then, and only then, sliding them around and playing the animation is honest.
--
-- ⚠️ WHY MOVING DROPS THE POSE FIRST. A puppet pinned in a workspot CANNOT BE TELEPORTED — the call
-- returns success and the body does not move. That is this repo's oldest tuner finding (v1.1's
-- "solid as a rock" failure, and the reason the retired live re-seat never took). So a live slider
-- cannot simply place them: `jlPuppetPlace` stops the workspot, moves the standing body, and
-- re-plays the pose a beat after the last change. You watch them slide on their feet and sit down
-- when you let go, which is both live AND correct.
-- ===========================================================================

-- Who the tuner acts on: the summoned companion first, else the NPC idling at a venue.
function jlSeatTargetHandle()
  if JL.summon.active and JL.summon.spawn and JL.summon.spawn.handle then
    return JL.summon.spawn.handle, "companion"
  end
  if JL.idle.spawn and JL.idle.spawn.handle then return JL.idle.spawn.handle, "idle" end
  return nil, nil
end

-- STEP 1 — TAKE CONTROL. Clear the follower role, stop the move commands, drop collision, and latch
-- `JL.puppet.on` so the rest of the engine leaves them alone (see jlPuppetHolds below). Captures
-- their CURRENT position as the origin the sliders are offsets from, so the numbers always start at 0
-- wherever they happen to be standing.
function jlPuppetTake()
  local h, which = jlSeatTargetHandle()
  if not h then
    JL.ui.status = "Nobody's out — call a companion, or find one at their venue."
    return false
  end
  local p; pcall(function() p = h:GetWorldPosition() end)
  if not p then JL.ui.status = "Can't read where they are — try again in a second."; return false end
  local yaw = 0.0
  pcall(function() yaw = h:GetWorldOrientation():ToEulerAngles().yaw end)

  pcall(function()                                   -- the AI has to stop, or it fights every step
    local role = h:GetAIControllerComponent():GetAIRole()
    if role then role:OnRoleCleared(h) end
    h.isPlayerCompanionCached = false
  end)
  -- ⚠️ v1.8.4 CLEARING THE ROLE IS NOT STOPPING THEM, AND THAT WAS THE WHOLE BUG.
  -- Antonia, 2026-08-17: *"they can be slided around, but then start moving away and snap back
  -- again - as if the AI tries to move to another spot every few ticks and is not truly disabled."*
  -- Exactly right, and the two halves of it are:
  --   * `OnRoleCleared` retires the follower ROLE. It does not cancel the AIMoveToCommand that is
  --     already IN_PROGRESS in the command slot, so whatever they were last told to walk to, they
  --     carry on walking to — role or no role.
  --   * jlPuppetTick's hold then yanked them back, which is the "snap back" she saw. The hold was
  --     fighting a live command instead of there being no command to fight.
  -- `jlHalt` is the existing answer (v1.57): it OCCUPIES the command slot with a stand-still, which
  -- is how you cancel a command in this engine — you replace it. Issued here, and re-issued on a
  -- heartbeat in the tick, because AIHoldPositionCommand expires by `duration` and the drift comes
  -- straight back when it does.
  pcall(function() jlHalt(h) end)
  setNpcCollision(h, false)                          -- a chair shoves a collided NPC back out
  JL.idle.pendingPose, JL.idle.pendingSit = nil, nil   -- cancel any scheduled idle pose
  pcall(function() stopWorkspotPose(h) end)

  JL.puppet = { on = true, handle = h, which = which,
                 bx = p.x, by = p.y, bz = p.z, byaw = yaw,
                 dx = 0, dy = 0, dz = 0, dyaw = 0,
                 pose = "sit", posed = false, replayAt = nil }
  JL.ui.status = "Control taken — their AI is off. Slide them into the chair."
  log(("PUPPET: took control of the %s at {%.2f, %.2f, %.2f} yaw %.1f — AI off, collision off.")
      :format(tostring(which), p.x, p.y, p.z, yaw))
  return true
end

-- Is the tuner holding this body? Read by the ticks that would otherwise re-assert follow AI.
function jlPuppetHolds(h)
  local P = JL.puppet
  if not (P and P.on and P.handle) then return false end
  if h == nil then return true end
  return sameEntity(h, P.handle)
end

-- The tuner's working coordinate: the captured origin plus the sliders. FORWARD/RIGHT are relative to
-- the NPC's own facing, not to world X/Y — "shove them forward" has to mean forward from where the
-- player is looking at them, or the sliders are a coordinate puzzle instead of a control.
function jlPuppetCoords()
  local P = JL.puppet; if not P then return 0, 0, 0, 0 end
  -- ⚠️ v1.8.4 THE OFFSET BASIS IS THE *CAPTURED* FACING (`byaw`), NEVER `byaw + dyaw`.
  -- It used to be the live, slider-adjusted yaw, and that quietly made Turn a second MOVE control:
  -- forward/right are derived from it, so rotating the slider rotated the AXES too and the point
  -- `base + forward*dy + right*dx` swept along an ARC around the capture point. On screen the body
  -- slid sideways and barely appeared to turn. Antonia, 2026-08-17: *"the turning their attitude
  -- (different facing angle) slider does not work. It just moves them along an axis rather than
  -- rotating them."*
  -- Freezing the basis at take-control makes the four controls orthogonal — Forward/Right/Up move,
  -- Turn only turns — which is the only way a seat is tunable without chasing your own tail.
  -- (It also means the offsets keep meaning what they meant when you dragged them: re-deriving the
  -- axes mid-tune would silently redefine every slider you had already set.)
  local base = P.byaw or 0
  local r    = math.rad(base)
  local fx, fy = -math.sin(r), math.cos(r)          -- the game's yaw 0 faces +Y
  local rx, ry =  math.cos(r), math.sin(r)
  return P.bx + fx * (P.dy or 0) + rx * (P.dx or 0),
         P.by + fy * (P.dy or 0) + ry * (P.dx or 0),
         P.bz + (P.dz or 0),
         base + (P.dyaw or 0)
end

-- Place them at the current coordinate. LIVE: called on every slider change.
-- The pose is dropped first (a workspot-pinned puppet cannot be teleported — see the header) and
-- re-armed for `replayAt`, so a continuous drag never fights a re-play mid-move.
function jlPuppetPlace(replay)
  local P = JL.puppet
  if not (P and P.on and P.handle) then return false end
  local x, y, z, yaw = jlPuppetCoords()
  if P.posed then
    pcall(function() stopWorkspotPose(P.handle) end)
    P.posed = false
  end
  placeAtExact(P.handle, Vector4.new(x, y, z, 1.0), yaw)
  if replay ~= false then
    P.replayAt = (JL.clock or 0) + ((Config.poses and Config.poses.delay) or 0.5)
  end
  return true
end

-- Play the pose now (the "Seat them" button, and the debounced re-play after a slide).
function jlPuppetPose(pose)
  local P = JL.puppet
  if not (P and P.on and P.handle) then
    JL.ui.status = "Take control first — their AI would cancel the animation."
    return false
  end
  if pose then P.pose = pose end
  P.replayAt = nil
  local ok = false
  pcall(function() ok = tryWorkspotPose(P.handle, P.pose == "lean" and "lean" or "sit", P.anim, true) end)
  P.posed = ok and true or false
  JL.ui.status = ok and "Playing the animation. Slide them until it lines up."
                     or  "The animation didn't play — AMM isn't loaded (it owns the poses)."
  log("PUPPET: pose '" .. tostring(P.anim or P.pose) .. "' -> " .. tostring(ok))
  return ok
end

-- Stepped from onUpdate. Two jobs, both cheap and both only while the tuner is live:
--   * fire the debounced re-play once the player stops dragging;
--   * hold the body where we put it. The engine has several paths that nudge an NPC (catch-up,
--     settle, the follower watchdog) and one of them getting a frame in is what makes a tuned seat
--     drift while you are looking at it.
function jlPuppetTick()
  local P = JL.puppet
  if not (P and P.on and P.handle) then return end
  local now = JL.clock or 0
  if P.replayAt and now >= P.replayAt then
    P.replayAt = nil
    jlPuppetPose(nil)
    return
  end
  if P.posed then return end                          -- a played workspot pins them; don't fight it

  -- v1.8.4 KEEP THE STAND-STILL ALIVE. AIHoldPositionCommand ends after its `duration` (6 s by
  -- default) and jlHalt's fallback is a move-to-own-spot that completes on arrival — so BOTH rungs
  -- of that ladder stop holding after a few seconds and the old behaviour resumes underneath us.
  -- That is the "every few ticks" in the report. The heartbeat is what makes "AI off" mean off.
  -- ⚠️ Only while UNPOSED: a workspot already pins them, and pushing a command at a posed puppet can
  -- eject them from it (the jlHalt fallback is a move command).
  local every = (Config.poses and Config.poses.tunerHalt) or 2.0
  if (now - (P.haltAt or -1e9)) >= every then
    P.haltAt = now
    pcall(function() jlHalt(P.handle) end)
  end

  -- ...and hold the ground every frame, not twice a second. The old 0.5 s / 0.15 m deadband WAS the
  -- visible snap: it let them walk up to 15 cm away and then teleported them back, which reads as a
  -- fight rather than as control. With the halt above there should be nothing to correct, so this is
  -- now a tight safety net — cheap, because it only teleports when there is real drift to undo.
  local slack = (Config.poses and Config.poses.tunerSlack) or 0.05
  local jp; pcall(function() jp = P.handle:GetWorldPosition() end)
  local x, y, z, yaw = jlPuppetCoords()
  if jp and dist3(jp, { x = x, y = y, z = z }) > slack then
    placeAtExact(P.handle, Vector4.new(x, y, z, 1.0), yaw)
  end
end

-- RELEASE. Stand them up, give collision back, and hand a companion to the follow engine as a REJOIN
-- (no arrival greeting — they never left). Safe to call blind: it is also the "never despawn a posed
-- puppet" guard, so it must never throw.
function jlPuppetRelease(reason)
  local P = JL.puppet
  if not P then return false end
  JL.puppet = nil
  local h = P.handle
  if h then
    pcall(function() stopWorkspotPose(h) end)
    pcall(function() setNpcCollision(h, true) end)
    if P.which == "companion" and JL.summon.active then
      pcall(function() promoteToCompanion(true) end)
    end
  end
  JL.ui.status = "Control released — they're back on their feet."
  log("PUPPET: released (" .. tostring(reason or "button") .. ").")
  return true
end

-- ⚠️ NEVER DESPAWN A POSED PUPPET — it is a hard crash. NCL.unseatIfSeated only knows about the
-- dinner, so the tuner carries its own latch and this is called from every dismiss/despawn path.
-- Adding a new one? Call it there too.
function jlManualUnseat(reason) return jlPuppetRelease(reason) end

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
  -- v1.8.5: the seat tuner owns this body. The move commands below are already refused centrally
  -- (see sendWalkToPlayer), but this tick ALSO calls placeAtExact and the workspot pose directly,
  -- and those are deliberately unguarded because the tuner itself drives them. Stand down whole.
  if jlPuppetHolds() then return end
  local h = JL.summon.spawn and JL.summon.spawn.handle
  if not JL.summon.active or not h then               -- dismissed / gone -> abort cleanly
    pcall(clearDinnerWaypoint)
    if h then
      pcall(function() stopWorkspotPose(h) end)
      if D.collisionOff then setNpcCollision(h, true) end   -- never leave a freed entity collision-less
    end
    D.phase, D.collisionOff, D.seatDeadline, D.sitFireAt = nil, false, nil, nil
    D.dwellSince, D.seatTipTried = nil, nil   -- v1.8.2: arrival-dwell clock + seat-card latch
    return
  end
  local C   = Config.date or {}
  local now = JL.clock or 0
  local pp  = playerPos()

  -- v1.8.2 THE SEAT CARD FIRES AT THE TABLE, NOT ON THE WAY TO IT.
  -- It used to go up on the walking -> seating hand-off, which happens `seatTriggerRadius` (12 m)
  -- from the seat — so the player read a card about a chair they could not see yet. Antonia,
  -- 2026-08-17: *"it should appear once V reaches the actual coordinate (3m radius) not sooner."*
  -- Checked every tick for the whole outing (not just in `walking`) because V can drift out and
  -- back in, and it is `jlShowSeatTip` itself that keeps it once-ever — `seatTipTried` only stops us
  -- re-asking sixty times a second.
  if pp and D.dest and not D.seatTipTried then
    local tipR = (Config.seatTip and Config.seatTip.radius) or 3.0
    if dist3(pp, D.dest) <= tipR then
      D.seatTipTried = true
      pcall(function() jlShowSeatTip(false) end)
    end
  end

  if D.phase == "walking" then
    -- arrived = V within seatTriggerRadius of the seat. Then Jackie drops follow + heads to his seat.
    if pp and D.dest and dist3(pp, D.dest) <= (C.seatTriggerRadius or 12.0) then
      pcall(clearDinnerWaypoint)                       -- reached -> drop pin + objective
      pcall(function()                                 -- drop follower role so he obeys move+sit
        local role = h:GetAIControllerComponent():GetAIRole()
        if role then role:OnRoleCleared(h) end
        h.isPlayerCompanionCached = false
      end)
      -- v0.44: collision OFF so the chair can't block him reaching the seat.
      -- v1.77: only when he's actually going to SIT. Standing at the table with collision off means
      -- standing INSIDE the table, so with automatic sitting disabled he keeps his normal collider
      -- and stops wherever the navmesh lets him — which is a chair's width from the table, i.e. right.
      if jlSitPosesOn() then
        setNpcCollision(h, false)
        D.collisionOff = true
      end
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
          if jlSitPosesOn() then
            placeAtExact(h, D.dest, D.destYaw or 0.0)
            D.sitFireAt = now + ((Config.poses and Config.poses.delay) or 0.5)
            if not reached then log("Dinner: seat reach timed out -> snapping him onto the seat.") end
          else
            -- v1.77 AUTOMATIC SITTING OFF: no snap, no workspot. placeAtExact is a NAV-SNAP-FREE
            -- teleport onto the seat plane — the one thing that will float a standing NPC — and the
            -- seat plane is ~0.45 m up. So he simply stops where he walked to and stands at the
            -- table. The meal (and the whole `seated` phase after it) runs exactly as before.
            D.sitFireAt = now
            log("Dinner: sitting is off -> he stays on his feet at the table.")
          end
        end
        return
      end
      -- (b) he's settled at the exact seat now -> just play the sit (NO teleport here).
      if now >= D.sitFireAt then
        if jlSitPosesOn() then pcall(function() tryWorkspotPose(h, "sit") end) end
        D.satAt, D.sitFireAt = now, nil
        log("Dinner: Jackie " .. (jlSitPosesOn() and "seated." or "settled at the table (standing)."))
      end
      return
    end
    -- v1.8.2 THE ARRIVAL LINE WAITS FOR THEM TO ACTUALLY ARRIVE.
    -- `D.satAt` is stamped when the SEAT ROUTINE finishes, and that is not the same event as the
    -- companion getting to the table: it also fires on the `seatTimeout` give-up path, and with
    -- automatic sitting off (the v1.77 default) it fires on the very next tick, before they have
    -- taken a step. Counting `sitWaitSeconds` from it therefore had them say "here we are" while
    -- still walking in. Antonia, 2026-08-17: *"the NPC says a line once they arrive - this line
    -- currently also fires too early. Should only fire once NPC reached 2m radius of the
    -- coordinate and has been there for 2s."*
    -- So the gate is geometry now, not bookkeeping: within `lineRadius` of the seat, and STAYED
    -- there for `sitWaitSeconds` — the dwell clock resets if they get shoved back out, so a
    -- crowd bumping past cannot buy them credit for standing still.
    -- ⚠️ `lineTimeout` is the fail-open and it is not optional: an unreachable seat (blocked
    -- navmesh, a chair in the doorway) would otherwise park the state machine in `seating`
    -- forever — no line, no clock reset, and no way out of the meal.
    local sp_; pcall(function() sp_ = h:GetWorldPosition() end)
    if sp_ and D.dest and dist3(sp_, D.dest) <= (C.lineRadius or 2.0) then
      D.dwellSince = D.dwellSince or now
    else
      D.dwellSince = nil
    end
    local dwelled = D.dwellSince and (now - D.dwellSince) >= (C.sitWaitSeconds or 2.0)
    local gaveUp  = (now - D.satAt) >= (C.lineTimeout or 30.0)
    if dwelled or gaveUp then
      if not dwelled then log("Dinner: never settled within reach of the seat -> speaking the arrival line anyway.") end
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
      -- v1.77 THE MEAL IS OVER -> they are your companion again, on a FULL clock.
      -- Three things had to happen here and only the third one did:
      --   (1) if their shift expired mid-meal they are already walking off (JL.leaving.phase ==
      --       "walking"), and promoteToCompanion does not cancel that — V says "let's go" and they
      --       stroll away instead. jlAbortDeparture is the one call that stops it, and it fails
      --       closed on the main-quest exit (which genuinely isn't coming back).
      --   (2) the companion clock. It was reset when he SAT DOWN, which is a whole meal ago.
      --       Clearing companionExpiresGame first forces armCompanionTimer to mint a fresh deadline
      --       rather than keep the stale one.
      --   (3) promoteToCompanion — the follower role + the follow command.
      do
        local hrs = (Config.companion and Config.companion.maxGameHours) or 6.0
        pcall(function() jlAbortDeparture(hrs, "dinner over") end)
        JL.summon.companionExpiresGame = nil
        pcall(function() armCompanionTimer(hrs) end)
        log(("Dinner: companion clock re-armed for %.1f game-hours at the stand-up."):format(hrs))
      end
      pcall(function() promoteToCompanion(true) end)    -- re-add follower role + follow (also re-enables collision).
                                                        -- REJOIN: no greeting — they never left (v1.77)
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

-- ⚠️ v1.8.8 — THE VENUE BODY HAD NO HANDLE, SO IT WAS NEVER PLACED. This is the v1.68 native-spawn
-- trap for a SECOND time, on the path nobody re-checked. `Native.spawn` returns
-- `{ id = <EntityID>, handle = nil }` and resolves a frame or two later; `resolveJackieHandle()` does
-- that resolving, but it only ever looks at `JL.summon.spawn` — the COMPANION. Nothing in the whole
-- mod ever wrote `JL.idle.spawn.handle`, so on the native backend (the default since v1.68) every
-- reader of it saw nil forever, wanderTick returned at its first line, and the body was never
-- teleported onto a waypoint, never posed, never wandered.
--
-- The visible symptom is NOT "no Jackie": ammSpawn(0, ...) passes no position, so Native.spawn falls
-- back to `inFrontOfPlayer(1.0)` — the venue body is created 1 m in front of V and left standing
-- there, because the thing that moves him to the venue is wanderTick's placement step. "He doesn't
-- spawn at Misty's / the Afterlife" (reported 2026-08-21) is that.
--
-- Mirrors resolveJackieHandle's shape exactly, including the AMM `entityID` field, so an AMM-backend
-- spawn (which already carries its handle) costs one nil-test. Global -> 200-cap safe.
function jlResolveIdleHandle()
  local sp = JL.idle.spawn
  if not sp then return nil end
  local h = sp.handle
  if not h and sp.entityID then                        -- AMM shape
    pcall(function() h = Game.FindEntityByID(sp.entityID) end)
    if h then sp.handle = h end
  end
  if not h and sp.id then                              -- native shape
    pcall(function() h = Game.FindEntityByID(sp.id) end)
    if h then sp.handle = h end
  end
  -- Say it ONCE per spawn record, both ways. A venue body that never resolves is invisible in the
  -- log otherwise — which is exactly how this survived from v1.68 to v1.8.8.
  if h and not sp.idleResolved then
    sp.idleResolved = true
    log("Idle body resolved — placing him at " .. tostring(JL.idle.locationKey) .. ".")
  elseif not h and not sp.idleWarned
     and ((JL.clock or 0) - (JL.idle.spawnedAt or 0)) > 5.0 then
    sp.idleWarned = true
    log("⚠ Idle body never resolved 5 s after spawn (id=" .. tostring(sp.id) .. "). He cannot be "
        .. "placed at " .. tostring(JL.idle.locationKey) .. " — report this with the log.")
  end
  return h
end

local function wanderTick()
  if jlPuppetHolds() then return end   -- v1.9: seat tuner owns this body (the venue wander walks him to the next waypoint)
  if not (Config.wander and Config.wander.enabled) then return end
  if JL.summon.active then return end                  -- following V -> not idle-wandering
  if JL.idle.leaving then return end                   -- walking off to despawn -> idleLeavingTick owns him
  local sp = JL.idle.spawn
  local h  = jlResolveIdleHandle()                     -- v1.8.8: nothing else ever filled this (see above)
  if not h then return end
  -- v1.77: same outfit re-assert for a VENUE body — they get a per-location appearance, so they have
  -- the same streaming race as a summoned one (see jlArmAppearanceFix).
  if not sp.appArmed then
    sp.appArmed = true
    pcall(function() jlArmAppearanceFix(h, sp, "idle spawn") end)
  end
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
  -- (v1.9: the TUNER WALK-IN state machine was DELETED here with tunerApply, the only thing that
  -- ever armed `JL.tuner.walk`. The tuner no longer walks anyone anywhere.)

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
  -- ⚠️ v1.77 — "THEY JUST DESPAWN" (Antonia, 2026-08-17). The two radii here have to AGREE, and they
  -- did not. This hand-off gives the body to the idle system out to `returnRadius` (100 m), but
  -- scheduleTick only KEEPS an idle body while V is within `Config.proximityRadius` (45 m) of that
  -- venue — past it, `clearIdle()` deletes them on the spot, with no walk-off and no parting line.
  -- So dismissing a companion 45-100 m from their scheduled venue popped them out of existence,
  -- which is exactly the report: no walk-away, they just vanish.
  --
  -- Taking the MIN means the 45-100 m band now FAILS this check, falls through to startLeaving, and
  -- gets the proper walk-off — while a dismissal right on their doorstep still hands them back to
  -- the schedule as intended. Do not raise this above proximityRadius without changing scheduleTick
  -- to match; the despawn is on that side.
  local radius = math.min((Config.transitions and Config.transitions.returnRadius) or 100.0,
                          Config.proximityRadius or 45.0)
  if not ref then return false end
  local away = dist3(ref, anchor)
  if away > radius then                                                 -- too far -> normal dismiss
    log(("Return-to-post declined: %.1f m from %s (keep-radius %.0f m) -> proper walk-off instead.")
        :format(away, tostring(block.locationKey), radius))
    return false
  end
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
  -- v1.8.2: V JUST SENT HIM OFF. Hold the schedule back so the send-off actually reads as one —
  -- see Config.dismiss.idleCooldown and jlStampIdleCooldown. clearIdle() (not a bare return) so a
  -- body that somehow survived the dismiss is removed rather than left standing.
  if JL.idle.blockUntil then
    if (JL.clock or 0) < JL.idle.blockUntil then clearIdle(); return end
    JL.idle.blockUntil = nil
  end
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
  if JL.walkAbreast == nil then JL.walkAbreast = true end                         -- v1.61 (true = walk-abreast ON by default). RENAMED from customWalk (v1.57's opt-in flag) so every old `customWalk=...` line in jl_settings.txt simply stops being read — restoring default-ON for everyone, the same invalidate-by-rename trick v1.57 used to flip it OFF.
  if type(JL.followGap) ~= "number" then JL.followGap = Config.followDistanceDefault or 1.5 end  -- v1.55 slider
  if JL.vVoice == nil then JL.vVoice = "auto" end                                -- v1.70.1 V's voice
  if JL.talkPrompt == nil then JL.talkPrompt = "native" end                      -- v1.8.7 talk-prompt style
  local ok, err = pcall(function()
    ns.addTab("/jackielives", "Jackie Lives")

    -- LANGUAGE, in the Esc menu (2026-08-19). It had been CET-window-only, which put the one
    -- setting a non-English player needs FIRST behind a debug overlay most of them never open.
    -- First subcategory on purpose: it changes every other line the mod puts on screen.
    -- ⚠️ TEXT ONLY, and the description says so — Jackie's voice is the game's own recording and stays in the game's language.
    -- ⚠️ This panel's OWN labels stay English: Native Settings rows are registered once at load
    -- and are not routed through Lang.t, so re-translating them would need a re-registration
    -- the API does not offer. Don't claim otherwise in the description.
    -- The list is built from Lang.LANGUAGES so a language added there shows up here for free.
    -- Wrapped in do...end: the locals are released at the end of the block, so the registration
    -- function's register budget is untouched (200-local cap, see the note at the top).
    -- ⚠️ v1.8.8 — ISOLATED IN ITS OWN pcall, and it is the only block here that is. Everything below
    -- registers fixed, hand-written rows; this one BUILDS its rows from Lang.LANGUAGES at load time,
    -- which makes it the one block whose contents can change without anyone editing this function.
    -- The whole registration shares a single pcall, so a throw ANYWHERE in it abandons the rest —
    -- and since this block was moved to the FRONT of the panel (2026-08-19), a throw here would take
    -- Voice, Relationship, Compatibility and Recovery down with it and leave the player with a tab
    -- that isn't there. Reported against v1.91 (2026-08-20): "the settings for Jackie Lives isn't
    -- showing up". Cost of being wrong about the cause: nothing. Cost of not isolating it: the page.
    local okLang, errLang = pcall(function()
    ns.addSubcategory("/jackielives/language", "Language")
    do
      local labels, codes = { "Auto (follow the game's language)" }, { "auto" }
      for _, L in ipairs(Lang.LANGUAGES) do
        labels[#labels + 1] = L.label
        codes[#codes + 1]   = L.code
      end
      local cur = 1
      for i, c in ipairs(codes) do if c == (JL.langChoice or "auto") then cur = i end end
      ns.addSelectorString(
        "/jackielives/language",
        "Mod language",
        "Which language this mod's own text appears in — the subtitles it writes, its notices " ..
        "and its prompts. AUTO (default) follows the game's own language setting, which is " ..
        "right for almost everyone; pick a language here only to override that. " ..
        "⚠️ SUBTITLES, NOT AUDIO: Jackie's voice is the game's own recording and stays in the game's language. " ..
        "Anything not translated yet falls back to English rather than going blank, and this " ..
        "settings panel itself stays English.",
        labels, cur, 1,
        function(i)
          JL.langChoice = codes[i] or "auto"
          if JL.langChoice == "auto" then
            Lang.auto = true;  Lang.load(Lang.detect())
          else
            Lang.auto = false; Lang.load(JL.langChoice)
          end
          pcall(jlSaveSettings)
          JL.ui.status = "Language: " .. Lang.labelFor(Lang.code) .. (Lang.auto and " (auto)" or "")
          log("Language -> " .. tostring(JL.langChoice) .. " (active " .. Lang.code .. ")")
        end
      )
    end
    end)
    if not okLang then
      log("Native Settings: the Language row could not be registered (" .. tostring(errLang)
          .. ") — the REST of the panel is unaffected. Language is still selectable in the CET window.")
    end


    -- v1.70.1 — V'S VOICE. V speaks her own dialogue choices now, and this is the one control
    -- for it. ⚠️ It does NOT tell the game what sex V is: the game reads that from the save
    -- (GetResolvedGenderName), and a line's male and female takes share ONE String ID, so the
    -- ENGINE picks the take. All this changes is the SHAPE of the event we send, which is the
    -- only lever a mod has. See jlPlayerVariant.
    ns.addSubcategory("/jackielives/voice", "Voice")
    ns.addSelectorString(
      "/jackielives/voice",
      "V's voice",
      "Which recording of V's line the game reaches for when V speaks a dialogue choice. " ..
      "AUTO (default) follows V's BODY as the save reports it, which is right for almost " ..
      "everyone — leave it alone unless V sounds like the wrong person. " ..
      "MALE / FEMALE force it, for the two cases Auto can't cover: a V whose voice was set " ..
      "differently from their body in the character creator, and any save where Auto simply " ..
      "guesses wrong. Not sure? Open the CET window (the mod's own panel), Voice, and press " ..
      "\"Test V's voice (A/B)\" — it plays the same line both ways so you can pick by ear.",
      { "Auto (follow V's body)", "Male", "Female" },
      ({ auto = 1, male = 2, female = 3 })[JL.vVoice] or 1,
      1,             -- 'reset to default' = Auto
      function(i)
        JL.vVoice = ({ "auto", "male", "female" })[i] or "auto"
        JL.vVoiceLogged = nil       -- re-arm the one-shot diagnostic so the next line logs the new choice
        pcall(jlSaveSettings)
        JL.ui.status = "V's voice: " .. JL.vVoice
        log("V's voice -> " .. JL.vVoice .. " (take=" .. jlTakePref()
            .. "). Takes effect on the next spoken line; no reload needed.")
      end
    )

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

    -- v1.68 COMPATIBILITY. AMM used to be REQUIRED; it is optional now, and this is where a player who
    -- already runs it can keep the old behaviour rather than being moved onto a new code path by an
    -- update. Default OFF = the native backend, which is the one that works with or without AMM.
    -- v1.8.7 CONTROLS. New subcategory, placed to match NCLives/NCLucy so the three mods' panels read the
    -- same way. Reported against NCLucy on 2026-08-18 by a controller player: with Night City Allies
    -- installed the native box drew a permanent (X) hint that could not be turned off. The engine is
    -- shared, so JackieLives had it too — and here it is worse, because this mod has no "release F to
    -- another mod" switch, so before this there was no way to quieten the prompt at all.
    -- ⚠️ This is a DISPLAY switch, not a control switch. Whichever state it is in, F still talks to him.
    ns.addSubcategory("/jackielives/controls", "Controls")
    ns.addSelectorString(
      "/jackielives/controls",
      "Talk prompt",
      "What you see when you look at Jackie, close enough to talk. GAME PROMPT (default) = the game's " ..
      "own interaction box, the one that reads [F] on a keyboard and draws the (X) glyph on a " ..
      "controller. TEXT = a plain line on the left of the screen. NONE = no prompt at all, for " ..
      "HUD-hider setups. F still talks to him in every setting — this only changes what is drawn.",
      { "Game prompt ([F] / (X))", "Text on screen", "None" },
      ({ native = 1, text = 2, off = 3 })[JL.talkPrompt] or 1,
      1,             -- 'reset to default' = the game prompt
      function(i)
        JL.talkPrompt = ({ "native", "text", "off" })[i] or "native"
        pcall(jlSaveSettings)
        jlApplyTalkPrompt()   -- into the LIVE Config, now
        JL.ui.status = "Talk prompt: " .. JL.talkPrompt .. " (F still works)."
        log("Talk prompt -> " .. JL.talkPrompt)
      end
    )

    ns.addSubcategory("/jackielives/compat", "Compatibility")
    ns.addSwitch(
      "/jackielives/compat",
      "Use AMM for spawning",
      "OFF (default) = JackieLives spawns Jackie itself, using the base game. AppearanceMenuMod is " ..
      "NOT needed. ON = use AppearanceMenuMod's spawn system instead, the way JackieLives worked " ..
      "before v1.68 — for players who already run AMM and would rather not change what works. " ..
      "If AMM isn't installed this switch does nothing and the mod says so in its log. " ..
      "AMM is still what provides the sit/lean poses at venues, whichever way this is set.",
      JL.useAMM,   -- current state (persisted in jl_settings.txt)
      false,       -- default: native
      function(state)
        JL.useAMM = state
        JL.ammMissingWarned = nil          -- re-arm the "you asked for AMM but it isn't there" notice
        pcall(jlSaveSettings)
        JL.ui.status = "Spawn backend: " .. (state and "AMM" or "native (no AMM needed)")
        log("Spawn backend -> " .. (state and "AMM (player choice)" or "native") ..
            ". Takes effect on the next summon; re-summon Jackie to switch a body that's already out.")
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
      "ON (default) = when you're WALKING, Jackie holds a spot BESIDE you (the walk-abreast style) — nice " ..
      "on a stroll, but he needs room, so it can look awkward in tight interiors. OFF = he trails you like " ..
      "a normal companion. Turn it off if you prefer him on your tail.",
      JL.walkAbreast,   -- current state (ON = walk-abreast enabled; persisted)
      true,            -- 'reset to default' value: ON (walk abreast) — v1.61 default-on again
      function(state)
        JL.walkAbreast = state
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
      Config.followDistanceDefault or 1.5,      -- 'reset to default'
      function(value)
        JL.followGap = value
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
      "Start",     -- button text
      18,          -- font size (Native Settings' addButton takes textSize BEFORE the callback)
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
-- v1.69: the Voice-lab test line. 9.3 s of Jackie ("'Ey, let Dex know we got his toy for him...")
-- chosen because it is the LONGEST clip in vo_durations.lua — you need time to turn your head and
-- work out where the sound is actually coming from. A global, not a local: the 200-local cap.
JL_VO_TESTLINE = "1790891785270616064"

JL_SETTINGS_FILE = "jl_settings.txt"
JL_SETTINGS_KEYS = { "useAMM", "husbando", "disableVehicleArrivals", "mourningSuppress", "keepBarOpen", "modeChosen", "allowMainGigs", "walkAbreast", "seatTipDone", "fallbackMenu" }  -- persisted JL.* boolean flags (walkAbreast v1.61: walk-abreast is DEFAULT-ON again. Renamed from customWalk (v1.57's opt-in flag) so any old `customWalk=...` line stops being read and re-defaults to ON for everyone — same invalidate-by-rename trick v1.57 used, now reversed. The v1.57 chain was: pre-v1.57 `disableCustomWalk` (default-on) → v1.57 `customWalk` (opt-in/off) → v1.61 `walkAbreast` (default-on again)) (modeChosen v1.54: did the player EXPLICITLY flip the Husbando switch? until they do, jlDefaultHermano forces Hermano on every load. Replaces the old `genderLock`, whose auto-detect is gone — an old save carrying genderLock just stops being read, so it re-defaults to Hermano exactly as intended)

-- v1.55: NUMERIC settings. The file used to serialize booleans only (plus the one `mode` string), which is
-- precisely why a slider could never be added — its value didn't survive a reload. These keys round-trip as
-- floats. Kept as a separate list so the boolean loop below stays untouched.
-- ⚠️ RENAMED followDistance -> followGap (2026-08-14) TO INVALIDATE THE OLD SAVED VALUE.
-- This file is read back on every load, so a settings file written under the 3.5 m default
-- would keep winning forever and the new 1.5 m default would reach nobody who had ever
-- launched the mod. An unknown key is simply ignored on load, so the rename resets this one
-- slider once, for everyone, and nothing else in the file is touched. Same trick as v1.61's
-- customWalk -> walkAbreast; see the note on JL_SETTINGS_KEYS.
JL_SETTINGS_NUMS = { "followGap" }

function jlSaveSettings()
  local f = io.open(JL_SETTINGS_FILE, "w")
  if not f then log("settings: could not write " .. JL_SETTINGS_FILE); return end
  for _, k in ipairs(JL_SETTINGS_KEYS) do f:write(k .. "=" .. tostring(JL[k] == true) .. "\n") end
  for _, k in ipairs(JL_SETTINGS_NUMS) do                        -- v1.55 floats
    if type(JL[k]) == "number" then f:write(k .. "=" .. string.format("%.3f", JL[k]) .. "\n") end
  end
  f:write("mode=" .. tostring(JL.mode or "quietlife") .. "\n")  -- v0.95 string setting (not a boolean)
  -- v1.66 voice backend: "auto" | "native" | "audioware" | "off". Persisted for the same reason every
  -- other tuner here is — config.lua is re-required from disk on reload, so an in-game choice that
  -- lived only in Config would be silently reverted by the next reload (see the seat/walk tuners).
  f:write("voiceMode=" .. tostring(JL.voiceMode or "auto") .. "\n")
  -- v1.70.1 V's voice: "auto" (route on V's BODY gender) | "male" | "female". Persisted for the
  -- same reason voiceMode is — config.lua is re-required from disk on every reload, so a choice
  -- that lived only in Config would be silently reverted the next time the mod reloaded.
  f:write("vVoice=" .. tostring(JL.vVoice or "auto") .. "\n")
  -- v1.8.7 talk prompt: also a STRING ("native" | "text" | "off"), same reason as vVoice above.
  f:write("talkPrompt=" .. tostring(JL.talkPrompt or "native") .. "\n")
  -- v1.60 language: "auto" = follow the game's own language setting, else a code from Lang.LANGUAGES.
  f:write("lang=" .. tostring(JL.langChoice or "auto") .. "\n")
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
      if k == "lang" then JL.langChoice = v end                                   -- v1.60
      if k == "voiceMode" and (v == "auto" or v == "native" or v == "audioware" or v == "off") then
        JL.voiceMode = v                                                         -- v1.66
      end
      if k == "vVoice" and (v == "auto" or v == "male" or v == "female") then
        JL.vVoice = v                                                            -- v1.70.1
      end
      if k == "talkPrompt" and (v == "native" or v == "text" or v == "off") then
        JL.talkPrompt = v                                                        -- v1.8.7
      end
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
  -- --- v1.59 catch-up patience: how long he may be lost before we stop trusting his own legs ---
  { t = "catchUp", k = "distance",             lo = 8.0,  hi = 60.0, label = "Counts as LEFT BEHIND beyond (m)" },
  { t = "catchUp", k = "sustainSeconds",       lo = 1.0,  hi = 15.0, label = "...for this long before we step in (s)" },
  { t = "catchUp", k = "progressEpsilon",      lo = 0.1,  hi = 3.0,  label = "Gap must close this much to count (m)" },
  { t = "catchUp", k = "maxGraceSeconds",      lo = 5.0,  hi = 60.0, label = "Max grace while he's still closing (s)" },
  { t = "catchUp", k = "cooldown",             lo = 1.0,  hi = 15.0, label = "Min gap between teleports (s)" },
  { t = "catchUp", k = "placeDistance",        lo = 1.0,  hi = 8.0,  label = "Teleport lands him this far from V (m)" },
  { t = "catchUp", k = "stillAngleSpread",     lo = 0.0,  hi = 120.0,label = "Extra placement sweep while V is still (deg)" },
}
-- The BOOLEAN walk knobs. Same file, written as 1/0.
JL_WALK_BOOLS = {
  { t = "loiter",  k = "enabled",              label = "Loiter halt ON (Jackie stands still when V does)" },
  { t = "loiter",  k = "useHoldCommand",       label = "Use AIHoldPositionCommand (off = move-to-own-spot fallback)" },
  { t = "catchUp", k = "progressGrace",        label = "Be patient while he's visibly closing the gap" },
  { t = "catchUp", k = "preferBehindWhenStill",label = "Teleport him BEHIND a standing V (out of shot)" },
  { t = "catchUp", k = "requirePath",          label = "Only place him where he can walk to V on foot" },
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
-- v1.8.7 — HOW THE "look at Jackie" PROMPT IS DRAWN, or whether it is drawn at all. Same
-- config-is-re-required-from-disk reason as every other jlApply* here: the live value has to be
-- copied back into Config after jlLoadSettings or a reload silently resets the player's choice.
--   "native" (default) = the game's own interaction box, "[F] Talk". On a controller it draws the
--                        (X) glyph, because that box hard-codes the Choice1 input action.
--   "text"             = the plain on-screen line "Talk to Jackie [ <key> ]".
--   "off"              = no prompt at all. For HUD-hider setups, and for players who already know
--                        the key. The KEY STILL WORKS — this hides the reminder, nothing else.
-- ⚠️ JackieLives has no "release F to another mod" hatch (NCLives/NCLucy v1.45 added one; here F is
-- the only way in), which makes "off" the ONLY way to quieten this prompt — so it matters more here,
-- not less. Global -> 200-cap safe.
function jlApplyTalkPrompt()
  Config.talk = Config.talk or {}
  local pick = JL.talkPrompt or "native"
  if pick ~= "native" and pick ~= "text" and pick ~= "off" then pick = "native" end
  Config.talk.prompt       = pick
  Config.talk.useChoiceBox = (pick == "native")
end

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

-- ---------------------------------------------------------------------------
-- CAR PASSENGER — the NCLives v1.64 method, ported 2026-09-02
-- ---------------------------------------------------------------------------
-- V gets in a car -> Jackie walks over and gets in the passenger seat. The follower role does NOT do
-- this; vanilla only seats followers through scripted quest commands, which is why every companion
-- mod has to do it itself. AMM did it in `Scan:AutoAssignSeats` (Modules/scan.lua:781), but that
-- loop iterates `AMM.Spawn.spawnedNPCs` — and since v1.68 Jackie is spawned NATIVELY, so AMM has
-- never heard of him. That is the whole gap this closes.
--
-- ⚠️⚠️ READ `../research/vehicle_passenger_ladder_postmortem.md` BEFORE YOU CHANGE A LINE OF THIS.
-- Between 2026-08-19 and 2026-08-22 this tick was an ESCALATION LADDER — walk, verify, walk again,
-- teleport, with a busy gate and five latches to steady it. It produced the worst bug this mod has
-- shipped: Jackie climbing in and out of a moving car for the length of the journey, reported by
-- players against all three mods, and three separate fixes did not cure it. It was reverted whole.
--
-- What is here now is the version NCLives has run since v1.64, and it is deliberately tiny:
--
--   ONE `AIMountCommand`, sent ONCE per vehicle, and then we stop caring.
--
-- That is the entire safety property. Nothing re-issues the command, so nothing can eject him from a
-- seat he is already in (`Native.mount` opens with `StopInDevice`, and a car seat IS a workspot — a
-- "retry" is an eject). Nothing polls his seat status, so no flickering engine read can flip a latch.
-- Its one failure mode is a walk that does not land, and he then simply follows on foot.
--
-- ⚠️ ONE HONEST CAVEAT, and it is why the probe below exists. This method is proven in the engine —
-- JackieVehicleTest step 7a seated him "perfectly WITH the walk-to-door + get-in animation" on
-- 2026-07-02 — but that Jackie was AMM-summoned. In NCLives it has shipped AMM-free since 2026-08-04
-- and was NEVER confirmed working in game (NCLives' own TODO still lists "the car passenger walk-in"
-- as not verified). So it is honest to call this UNTESTED on a natively-spawned body until somebody
-- drives with him and reads the log.
--
-- Deliberately NOT handled here:
--   * BIKES. V on a bike is `jlCruiseTick`'s job — Jackie gets his own Arch and trails.
--     `jlCruiseTick` is gated ahead of this in onUpdate; this tick stands down on two wheels.
--   * V's own seat. Native.SEATS never offers seat_front_left (see native.lua).
--
-- State lives on a GLOBAL rather than JL so a soft-reload can't strand a live command — and because
-- init.lua is at Lua's 200-local cap and cannot afford another top-level local.
jlPassenger = { veh = nil, cmd = nil, sentAt = -999, probeAt = nil }

function jlPassengerTick()
  if (Config.follow or {}).passenger == false then return end   -- opt-out; default is on
  -- ⚠️ AMM OWNS THE SEAT WHEN IT IS INSTALLED. Its Scan:AutoAssignSeats has done this for years and
  -- players report it working perfectly; two systems mounting one body is how the in-out loop starts.
  -- So with AMM present we do nothing at all. See Config.follow.passengerOnlyWithoutAMM.
  -- ⚠️ Note the one case this costs: AMM only seats bodies AMM ITSELF spawned, so an AMM user running
  -- the NATIVE spawn backend gets nobody in the passenger seat. Flip the config switch if that is you.
  if (Config.follow or {}).passengerOnlyWithoutAMM ~= false and Native.ammPresent() then
    if not JL.passengerAMMLogged then
      JL.passengerAMMLogged = true
      log("Passenger: AMM is installed — leaving the car seat to AMM's own AutoAssignSeats.")
    end
    return
  end
  if jlCruise and jlCruise.active then return end               -- bikes belong to the cruise system

  -- ⚠️ The early-out has to survive a STANDING command: if V is driving with Jackie aboard and he is
  -- then dismissed, `jlPassenger.veh` is still set and needs clearing. So bail only when there is
  -- nothing to clean up either.
  if not (JL.summon.active and JL.summon.companionSet) and not jlPassenger.veh then return end

  if jlCruise and jlCruise.active then return end               -- bikes belong to the cruise system

  -- ⚠️ The early-out has to survive a STANDING command: if V is driving with Jackie aboard and he is
  -- then dismissed, `jlPassenger.veh` is still set and needs clearing. So bail only when there is
  -- nothing to clean up either.
  if not (JL.summon.active and JL.summon.companionSet) and not jlPassenger.veh then return end

  local veh = jlPlayerVehicleObj()

  -- V got out (or swapped vehicles): drop the standing command so Jackie resumes following on foot
  -- instead of walking to a car that's driving away.
  if jlPassenger.veh and veh ~= jlPassenger.veh then
    local h = JL.summon.spawn and JL.summon.spawn.handle
    if h and jlPassenger.cmd then Native.cancelMount(h, jlPassenger.cmd) end
    jlPassenger.veh, jlPassenger.cmd, jlPassenger.probeAt = nil, nil, nil
  end

  if not veh then return end
  -- THE PROBE (read-only). Once, ~8 s after the command went out, write down whether he actually made
  -- it. This answers the open question above and nothing else: it never retries, never teleports,
  -- never touches a gate. ⚠️ If you find yourself wanting to ACT on this line, you are rebuilding the
  -- reverted ladder — read the postmortem instead.
  if jlPassenger.veh == veh then
    if jlPassenger.probeAt and (JL.clock or 0) >= jlPassenger.probeAt then
      jlPassenger.probeAt = nil
      local h = JL.summon.spawn and JL.summon.spawn.handle
      local aboard = h and Native.isMountedTo(h, veh) or false
      log(("[PassengerProbe] 8 s after the mount command: Jackie is %s. (Read-only — the mod does "
           .. "NOT retry. If this says NOT ABOARD often, report it; do not add a retry loop.)")
          :format(aboard and "IN THE CAR" or "NOT ABOARD"))
    end
    return                                            -- already sent for this vehicle
  end
  if jlIsBikeVeh(veh) then return end

  -- Only a real, promoted companion rides along — not a mid-arrival one still walking in (he'd
  -- abandon the arrival to chase the car), and not one the dinner or the leaving machine owns.
  if not (JL.summon.active and JL.summon.companionSet) then return end
  if JL.varrival and JL.varrival.phase then return end
  if jlDinnerOwnsBody() or JL.leaving.phase then return end
  local h = resolveJackieHandle(); if not h then return end

  -- Throttle: the slot scan isn't free, and a failed mount must not be retried every frame for as
  -- long as V sits in the car.
  local now = JL.clock or 0
  if now - (jlPassenger.sentAt or -999) < 2.0 then return end
  jlPassenger.sentAt = now

  local cmd = Native.mount(h, veh)
  if cmd then jlPassenger.veh, jlPassenger.cmd, jlPassenger.probeAt = veh, cmd, now + 8.0 end
end

-- True only during a real locked cutscene (PlayerStateMachine SceneTier >= 4 = FPPCinematic/Cinematic).
-- NO false positives on holocalls / dialogue / vendors / braindance (those stay tier 1-3). Verified
-- against psiberx/cp2077-cet-kit GameUI (the base AMM + most companion mods use). Global -> cap-safe.
function jlInCutscene()
  -- 0-ENGINE. If 0-Engine is installed it has ALREADY read this exact blackboard field this frame,
  -- for the whole mod stack — so we take its answer instead of running the same three cross-boundary
  -- calls beside it. This mod has no frame cache, so unlike NCLives this replaces an UNCACHED read
  -- that fires several times a frame while Jackie is out. nil means "not installed / not yet polled /
  -- shape unrecognised", and then we read it ourselves exactly as before. Safe to source cross-mod
  -- (unlike V's position, see zengine.lua's header): the tier changes when a scene starts, and every
  -- caller here asks "are we in a cutscene", not "where is V".
  local shared; pcall(function() shared = ZEngine.sceneTier() end)
  if type(shared) == "number" then return shared >= 4 end
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
  pt = jlGrounded(pt)   -- v1.61: never spawn the Arch in mid-air (was `snapToNavmesh(pt) or pt`)
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
  pcall(function() promoteToCompanion(true) end)     -- resume normal on-foot follow (REJOIN: they were riding WITH V,
                                                     -- so no arrival greeting — v1.77)
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
  pt = jlGrounded(pt)   -- v1.61: never spawn the Arch in mid-air (was `snapToNavmesh(pt) or pt`)
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
  -- only cruise a SETTLED companion (not mid-arrival / mid-seating / walk-off)
  -- ⚠️ v1.8.6 — `jlDinnerOwnsBody()`, NOT a bare `JL.dinner.phase`. (Antonia, 2026-08-17: *"I
  -- tried riding a bike before asking someone out for dinner and after. After did NOT work!"*)
  -- The `walking` phase issues no commands whatsoever — it only watches V's distance to the
  -- restaurant — so treating it as "something owns the body" switched the whole cruise system off
  -- for the entire walk: no bike, no companion on it, V rides away alone.
  local settled = companion and JL.summon.companionSet
    and not (jlDinnerOwnsBody() or JL.leaving.phase or (JL.varrival and JL.varrival.phase))
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
  if jlPuppetHolds() then return end   -- v1.9: seat tuner owns this body (settle re-hides and re-places him for a beat)
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
  -- v1.67: the follower-role watchdog counts attempts against ONE body. A new session means a new
  -- body, so a session that ended mid-retry must not start the next one already out of tries.
  jlFollowerWatch = { at = -999, tries = 0, ok = false }
  JL.summon   = { spawn = nil, active = false, companionSet = false, walkIn = false }
  JL.idle     = { spawn = nil, locationKey = nil, placed = false, phase = nil, curIdx = nil, tgtIdx = nil,
                  spawnedAt = 0, dwellUntil = 0, arriveBy = 0, lastReissue = 0,
                  leaving = false, leaveTarget = nil, leaveDeadline = 0, leaveReissue = 0,
                  collisionOff = false,
                  blockUntil = nil }   -- v1.8.2: JL.clock deadline before the schedule may re-spawn him (post-dismiss)
  JL.settle   = { hideUntil = nil, collideUntil = nil, handle = nil,
                  reposePending = nil, reposeAt = nil, reposeLast = nil }
  JL.smile    = { until_ = 0, nextRoll = 0, nextApply = 0, cooldownUntil = 0, handle = nil,
                  reunionActive = false, reunionForceUntil = 0, reunionSafety = 0, idle = nil }
  JL.varrival = { at = nil, phase = nil, pt = nil, bikeId = nil, bikeHandle = nil,
                  placeAt = nil, driveAt = nil, sprintAt = nil, lastReissue = 0, deadline = nil, driveCmd = nil }
  JL.arrival  = { at = nil, phase = nil, pt = nil, placeAt = nil, moveAt = nil, deadline = nil, lastReissue = 0 }
  JL.leaving  = { phase = nil, deadline = nil, lastReissue = 0 }
  JL.catchUp  = { farSince = nil, lastAt = nil, teleTries = nil, lastDist = nil, graceSince = nil }
  JL.follow   = { lastAt = nil }
  JL.abreast  = { lastAt = nil }
  JL.persist  = { gapSince = nil, lastRespawn = nil, worldReadyAt = nil }
  -- The car-passenger latch holds a VEHICLE HANDLE and a live AI command from the world that just
  -- died. Nothing here needs cancelling — that world is gone — but the refs must not survive, or the
  -- first tick of the new session compares a fresh vehicle against a dead pointer and tries to cancel
  -- a command on a corpse. It lives on a global rather than JL (200-cap), which is exactly why it
  -- would otherwise be missed by this function.
  jlPassenger = { veh = nil, cmd = nil, sentAt = -999, probeAt = nil }
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
-- ---------------------------------------------------------------------------
-- v1.67 FOLLOWER-ROLE WATCHDOG — "he spawns but stands there"
-- ---------------------------------------------------------------------------
-- Two independent things make Jackie move: our own AIFollowTargetCommand trail (followTick ->
-- sendWalkToPlayer) and the ENGINE's follower role. Only the second makes him a real ally — it is
-- what enemies read to ignore him, what the minimap symbol follows from, and what the follow
-- behaviour tree needs a FriendlyTarget for. Mechanism + script citations: native.lua's header.
--
-- Why a watchdog and not just a better one-shot: AIFollowerRole.OnRoleSet RETURNS SILENTLY if the
-- puppet can't answer for its attitude agent or if `#player` doesn't resolve yet (aiRole.script:222,
-- :234). The role is applied the moment we first get a handle — which is the frame the body appeared,
-- not necessarily the frame it finished attaching. A one-shot that lands in that window leaves a
-- perfectly healthy-looking Jackie standing still, with nothing in the log.
--
-- So: ask the ENGINE whether it agrees, and re-apply until it does. Bounded, and it says so either
-- way. GLOBAL, not a top-level local: init.lua is at Lua's 200-local cap.
jlFollowerWatch = { at = -999, tries = 0, ok = false }

function jlFollowerWatchTick()
  local F = Config.follow or {}
  if F.roleWatch == false then return end
  if not (JL.summon.active and JL.summon.companionSet) then
    jlFollowerWatch.tries, jlFollowerWatch.ok = 0, false
    return
  end
  if JL.varrival and JL.varrival.phase then return end
  if jlDinnerOwnsBody() then return end   -- v1.8.5: a WALKING dinner is an ordinary follow; only seating/seated own him
  if JL.leaving and JL.leaving.phase then return end
  -- v1.9: ...and neither is a body the SEAT TUNER is holding. This watchdog re-applies the follower
  -- role every 2 s, and the role is exactly what drags him back toward V and cancels the pose — so
  -- without this the tuner is unusable and it looks like the sliders don't work.
  if jlPuppetHolds() then return end

  local now = JL.clock or 0
  if (now - (jlFollowerWatch.at or -999)) < (F.roleWatchInterval or 2.0) then return end
  jlFollowerWatch.at = now

  local h = resolveJackieHandle(); if not h then return end
  local role, companion = Native.followerVerdict(h)

  if role and companion then
    if not jlFollowerWatch.ok then
      jlFollowerWatch.ok = true
      log("Follower role: the ENGINE agrees Jackie is a companion (IsPlayerCompanion=true).")
    end
    jlFollowerWatch.tries = 0
    return
  end

  if (jlFollowerWatch.tries or 0) >= (F.roleWatchTries or 5) then return end
  jlFollowerWatch.tries = (jlFollowerWatch.tries or 0) + 1
  log(("Follower role NOT active (role=%s companion=%s) -> re-applying, attempt %d/%d.")
      :format(tostring(role), tostring(companion), jlFollowerWatch.tries, (F.roleWatchTries or 5)))
  jlMakeCompanion(h)
  if jlFollowerWatch.tries >= (F.roleWatchTries or 5) then
    log("Follower role: gave up after " .. tostring(jlFollowerWatch.tries) .. " attempts. He will " ..
        "still walk (our own follow trail is separate), but he is not a true ally — no enemy " ..
        "immunity, no minimap symbol. Report this log.")
  end
end

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
  -- ⚠️ v1.8.6: `jlDinnerOwnsBody()` for the same reason as the cruise tick above — a `walking`
  -- dinner places nobody, so a body culled on the way to the restaurant was never restored.
  -- seating/seated DO place him, and this must keep its hands off those.
  if (JL.varrival and JL.varrival.phase) or JL.leaving.phase or jlDinnerOwnsBody() or JL.summon.walkIn then
    JL.persist.gapSince = nil; return
  end

  -- v0.84 CRASH FIX: don't spawn until AMM has re-initialised post-load and Jackie's record resolves.
  -- After a load AMM re-inits a beat later than us; calling its Spawn path before it's ready was the other
  -- half of the load crash. Bail (and reset the gap timer) until both are live, then spawn is the same
  -- proven path the confirmed catch-up respawn (bug 2f) already uses safely.
  -- ⚠️ v1.68 — this used to ALSO require `amm.Spawn.NewSpawn`, from when the respawn went through AMM.
  -- The respawn is Native.spawn now and touches no AMM at all, so on a machine without AMM that gate
  -- returned every tick and a Jackie whose body was culled or lost to a fast travel was NEVER brought
  -- back. resolveJackieRecord() below is the real readiness signal.

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
  Native.bind{ log = log }   -- v1.67: the follower-role module logs through us
  Session.rotateLog()
  Session.header(JL.mode)
  pcall(function() math.randomseed((os.time and os.time() or 0)) end)  -- v0.36: random day-bag shuffle
  getAMM()
  setupInteractHook()   -- v0.15: native F (Interact) triggers Talk-to-Jackie, no binding
  pcall(setupDetachPurge)  -- v1.61: despawn a following Jackie at load-teardown START -> no cross-save load crash
  pcall(setupCallHijack)   -- v0.30: player phone-calls to Jackie route into our flow
  pcall(jlLoadSettings)    -- v0.51: restore persisted Esc-menu toggles (husbando / disableVehicleArrivals)
  pcall(jlApplyTalkPrompt) -- v1.8.7: ...and how (or whether) the "look at Jackie" prompt is drawn
  pcall(jlDefaultHermano)  -- v1.54: Hermano for everyone unless the player explicitly flipped the switch
  -- v1.60: pick the language. AFTER jlLoadSettings so an explicit player choice beats autodetect;
  -- nil/"auto" (the default, and every existing jl_settings.txt) follows the game's own language.
  pcall(function() Lang.init(JL.langChoice) end)
  -- v1.63: the native dialogue picker. bind BEFORE init so the very first log line is attributed,
  -- and init registers the controller capture + the four guards that keep our hub on screen.
  -- onPreempt: a REAL in-game conversation is opening (a quest scene, a phone call) — the game's
  -- dialogue always wins, so end whatever we were saying rather than fight it for the widget.
  pcall(function()
    DialogUI.bind{
      log      = log,
      clock    = function() return JL.clock or 0 end,
      onPreempt = function() if Branch.finish then Branch.finish("Conversation ended — a scene took over.") end end,
      noCombat = (Config.dialogue and Config.dialogue.pickerNoCombat) or false,
      debug    = (Config.dialogue and Config.dialogue.cycleDebug) or false,
    }
    DialogUI.init()
  end)
  -- ⚠️ The bridge needs the conversation runner's INTERNALS (speakJackieLine, pickPoolLine are
  -- file-locals here), which is why it takes a bind table rather than reaching for globals. Adding a
  -- key here means adding it to the allow-list inside Allies.bind too.
  pcall(function()
    Allies.bind{
      log          = log,
      speak        = function(text, sfx, mute) return speakJackieLine(text, sfx, mute) end,
      sayPlayer    = function(text) pcall(showSubtitle, text, "V") end,   -- (text, speakerName)
      pickLine     = function(pool) return pickPoolLine(pool) end,
      var          = function(entry) return jlVar(entry) end,
      talkTree     = function() return Config.dialogueTree end,
      personaName  = function() return Config.jackieName or "Jackie" end,
      activeKey    = function() return "jackie" end,
      -- ⚠️ There is no jlRecordIsOurs() here — that predicate is NCLives', where it resolves the
      -- ACTIVE persona out of a roster. This mod has exactly one companion, so the check is a
      -- straight compare against his record. (Writing `jlRecordIsOurs and ...` would have looked
      -- like a check and always returned false, leaving only the display-name fallback.)
      recordIsOurs = function(r)
        local want = tostring(Config.jackieRecord or "Character.Jackie"):lower()
        return tostring(r or ""):lower():find(want, 1, true) ~= nil
      end,
      -- One companion here, so the roster search is a single compare — but the SHAPE matches the
      -- other two engines on purpose, so a fix in one ports to all three unchanged.
      personaFor   = function(s)
        if type(s) ~= "string" or s == "" then return nil end
        local low  = s:lower()
        local nm   = tostring(Config.jackieName or "Jackie"):lower()
        local rec  = tostring(Config.jackieRecord or "Character.Jackie"):lower()
        if low:find(nm, 1, true) or low:find(rec, 1, true) then return "jackie" end
        return nil
      end,
      treeForKey   = function() return Config.dialogueTree end,
      nameForKey   = function() return Config.jackieName or "Jackie" end,
      famAllows    = function(minFam) return Fam and Fam.allows(minFam) end,
      famAdd       = function(award) if Fam then Fam.add("choice", award) end end,
      endHook      = function() pcall(showJackieChoiceBox) end,
      now          = function() return JL.clock or 0 end,
      hubRefresh   = function()
        local D = Config.dialogue or {}
        return D.hubRefreshMin or 10.0, D.hubRefreshMax or 30.0
      end,
    }
  end)
  -- OPTIONAL 0-Engine. Only two keys: it consumes their state, it never drives ours.
  -- ⚠️ `enabled` is read from Config on every call, NOT captured — config.lua is re-required from disk
  -- on reload, so capturing the value would pin a stale copy (the config-reload trap the seat/walk
  -- tuners hit). It is also NOT a persisted setting, so it needs no entry in JL_SETTINGS_KEYS.
  pcall(function()
    ZEngine.bind{
      log     = log,
      enabled = function() return (Config.zeroEngine or {}).enabled ~= false end,
    }
  end)
  pcall(jlLoadSeats)       -- v1.1: restore tuned sit coords into Config so they survive a reload (old-S4 fix)
  pcall(jlLoadWalk)        -- v1.57: same for the walk/loiter tuner's knobs (they used to die on every reload)
  -- retrieval questline: logger + v1.2 relationship-mode selector (Husbando/Hermano recovery text)
  -- + v1.54 showObjective -> the native banner (with its UI sound), so the quest's steps actually
  -- tell the player what to do next ("Find Jackie...", "Call Jackie", "Wait for Jackie").
  -- v1.65: familiarity. `config` is a CLOSURE, not the table — config.lua is re-required from disk on
  -- every reload, so handing over the table itself would pin a stale copy and the player's tuning would
  -- stop taking effect (the config-reload-wipes-it trap, same one the seat/walk tuners hit).
  pcall(function()
    Fam.bind{
      log      = log,
      factGet  = jlFactNum,
      factSet  = jlSetFactNum,
      config   = function() return Config.familiarity end,
    }
    log("Familiarity: " .. Fam.status())
  end)

  -- v1.66 VOICE: same closure rule as above — Config.voice is read live, so mode/context
  -- changes take effect on reload instead of pinning whatever was loaded first.
  pcall(function()
    VO.bind{
      log         = log,
      config      = function() return Config.voice end,
      readingSecs = readingSecs,
      playEvent   = function(target, event) return playEventOn(target, event, "") end,
      -- v1.71: the three questions VO.femaleTakeId needs before it may speak a female-take id.
      bodyMale    = function() return jlVBodyMale() end,
      archiveOk   = function() return jlArchiveLoaded() end,
      takePref    = function() return jlTakePref() end,
    }
    -- Re-apply the persisted backend choice BEFORE the first line: config.lua came fresh off disk
    -- with its shipped default, so without this a player who picked "Native only" would silently be
    -- back on "auto" after every reload.
    if JL.voiceMode then Config.voice.mode = JL.voiceMode end
    log("Voice: " .. VO.status())
  end)

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
      -- v1.62: HORIZONTAL (X/Y) distance + the raw vertical gap, as two numbers. The roof-AV exit needs a
      -- footprint check (a flat radius on the deck) plus a generous vertical tolerance, because the AV's
      -- origin sits above the deck V stands on — a 3-D sphere leaks that dz and never fires (see the
      -- roofHeli notes in blaze.lua). Returns (horizontalDist, |verticalGap|).
      distToPlayerXY = function(p)
        local pp = playerPos(); if not pp or not p then return 1e9, 1e9 end
        local dx, dy = pp.x - p.x, pp.y - p.y
        return math.sqrt(dx * dx + dy * dy), math.abs(pp.z - p.z)
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
          pcall(function() choice.localizedName = tostring(Lang.t(label) or "Interact") end)
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
      -- v1.63a: end any open Jackie conversation. Called by Blaze.tryEscapePress, because the escape
      -- [F] can now fire WHILE a choice menu is up (see the OnAction hook) and that menu must not
      -- survive into the fade — an open picker nothing is listening to still eats the player's input.
      closeDialogue = function()
        pcall(function() if Branch and Branch.open and Branch.finish then Branch.finish() end end)
        -- v1.64.1: also drop a STANDALONE native picker (the "Show test picker" diagnostic), which is
        -- shown without Branch.open — so the check above would miss it and it would ride into the fade
        -- still swallowing input, which is exactly what this hook exists to prevent.
        pcall(function() if DialogUI and DialogUI.isShown() then DialogUI.hide() end end)
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
      -- v1.56 BLAZE: a spawned NPC's CURRENT health as a 0..1 fraction (nil if it can't be read).
      -- Stat pools answer the `perc` form on a 0..100 scale — adamSmasherComponent.script:299-311 compares
      -- this exact call against the literals 80.0 / 50.0 / 30.0 / 5.0 — so divide by 100 here.
      healthFrac = function(h)
        if not h then return nil end
        local v
        pcall(function()
          v = Game.GetStatPoolsSystem():GetStatPoolValue(h:GetEntityID(), gamedataStatPoolType.Health, true)
        end)
        if type(v) ~= "number" then return nil end
        return v / 100.0
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
  -- v1.69: one pool (the male duplicate is gone — see Config.call.arrivalGreetings).
  local pool = (Config.call and Config.call.arrivalGreetings) or {}
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
-- in-game day. Same no-immediate-repeat rule as the arrival greeting so two consecutive days don't
-- open with the same line. GLOBAL -> costs no top-level local (200-cap).
-- v1.69: no longer picks a pool by relationship mode — where a line has two takes the ENGINE picks,
-- and vo_gender.lua matches the subtitle. See Config.venueGreet.
function pickVenueHelloLine()
  local G = Config.venueGreet or {}
  local pool = G.greetings or {}
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
    pcall(function() promoteToCompanion(true) end)  -- keep him a proper follower (REJOIN: a conversation starts a
                                             -- beat from now; a greeting would talk over it — v1.77)
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
  -- OPTIONAL Night City Allies bridge. Self-limiting: looks for their mod on a 3 s timer, gives up
  -- after 20 tries, and does nothing once attached. Safe above the session guard because it touches
  -- no world handle — it only reads another mod's Lua table.
  pcall(function() Allies.tick(JL.clock or 0) end)
  -- OPTIONAL 0-Engine attach. Same self-limiting shape as the Allies bridge above and safe in the
  -- same place for the same reason: it touches no world handle, only another mod's Lua table. Stops
  -- calling GetMod for good after 20 tries, and does nothing at all once attached.
  pcall(function() ZEngine.tick(JL.clock or 0) end)
  -- v1.52 SESSION GUARD — MUST BE FIRST. onUpdate keeps ticking through a load screen, so on the frame a
  -- new session starts every handle below this line is a pointer into the world that just died. Nothing
  -- that can touch a handle may run before this. (`pcall` cannot save us from a native use-after-free.)
  pcall(function() Session.tick() end)
  -- nsTick touches no entity handles and must keep running at the main menu, or the Esc-menu settings
  -- panel never registers there. It's the one tick allowed above the session gate.
  pcall(nsTick)         -- v0.44: register the Esc-menu panel once nativeSettings has loaded (load-order safe)
  if Session.id == 0 then return end   -- main menu / load screen: no world, no session — touch nothing
  pcall(jlVoiceABTick)  -- v1.70.1: the armed second take of the V-voice A/B test (no-op unless armed)
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
  pcall(jlPromptProbeTick)  -- v1.8.6: read the interaction blackboard BACK (the missing [F] with NCA)
  pcall(updateTalkPrompt, dt)
  pcall(function() DialogUI.tick(JL.clock or 0) end)  -- v1.63: republish the highlighted row + drop the box if the world went away
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
  -- ⚠️ v1.68 — THE ONE THAT COST NCLIVES A RELEASE. This block used to read `JL.summon.spawn.handle`
  -- DIRECTLY, which worked only because AMM populated that field from its own Cron a few frames after
  -- SpawnNPC. Now that ammSpawn goes through Native.spawn, the record is `{ id = <EntityID>, handle =
  -- nil }` and the only thing that fills the field is resolveJackieHandle() — which the arrival tick
  -- and the Blaze finale call, but a plain summon does not. Left as it was, the handle stays nil, this
  -- block never fires, `companionSet` stays false, and companionPersistTick reads that as "he isn't
  -- here" and respawns him every few seconds, forever. That is exactly what shipped as NCLives v1.64.
  -- RESOLVE the handle here rather than waiting for someone else to.
  local promoteH = resolveJackieHandle()
  if promoteH and not JL.summon.companionSet and not JL.summon.walkIn then
    Session.mark("promote to companion")
    jlMakeCompanion(promoteH)   -- v1.67: was amm.Spawn:SetNPCAsCompanion; v1.68: backend-aware
    pcall(function()
      local pl, h = Game.GetPlayer(), promoteH
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
  -- v1.62: hand off to jlMainExitTick (grace period + warning convo). Called every tick while he's an
  -- active, undismissed, non-dinner companion who isn't already walking off — the function decides
  -- whether to warn, wait, leave, or (V dropped the main quest in time) stay. Same guards as before.
  if JL.mode ~= "blaze"
     and JL.summon.active and JL.summon.companionSet and not JL.dinner.phase
     and JL.leaving.phase ~= "walking" and startLeaving then
    pcall(jlMainExitTick)
  end
  pcall(jlCruiseTick)     -- v0.85: V on a BIKE -> Jackie trails on his Arch (gated before the foot ticks)
  pcall(jlPassengerTick)  -- 2026-09-02: V in a CAR -> Jackie gets in (NCLives' v1.64 method; ONE command, no retries)
  pcall(followKeepCloseTick) -- v0.67: hold him a few m behind V (override AMM's long leash)
  pcall(abreastTick)      -- v0.84: OR (when enabled) hold him beside/ahead of V instead of trailing
  pcall(jlWalkProbeTick)  -- v1.8.3: log WHICH gate is refusing walk-beside (self-guards; edge + heartbeat)
  pcall(jlTakedownTick)   -- v1.48: watch an ordered takedown to a conclusion (grapple / down / timeout)
  pcall(blazeCalmHoldTick) -- v1.51: re-assert holster/uncrouch after the async finale teleport, and verify
  pcall(jlWeaponMirrorTick) -- v1.61: Jackie holsters when V does (after combat he lingered armed too long)
  pcall(catchUpTick)      -- v0.66: settled companion fell behind (fast-travel/ran off) -> snap to V's side
  pcall(jlFollowerWatchTick)   -- v1.67: the engine must AGREE he's a companion, or he stands still
  pcall(companionPersistTick)  -- v0.72: saved "is companion" but his body is gone (reload / culling FT) -> respawn at V
  pcall(settleTick)       -- v0.82: hide + no-collision for a beat after a respawn-at-V so he doesn't pop/clip in
  pcall(dinnerTick)       -- v0.41: dinner outing (walk to restaurant -> linger -> full reset)
  pcall(jackieDinnerOfferTick)  -- v0.48: Jackie proposes the outing himself after a random in-game gap
  pcall(jlPuppetTick)           -- v1.9: seat tuner — debounced pose re-play + hold them where we put them
  pcall(jlAppearanceTick)       -- v1.77: verify the spawned body is actually WEARING the outfit we asked for

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

-- (v1.9: `tunerApply` and `tunerPrint` were DELETED here, together with the WALK-IN re-seat they
-- drove. Both are superseded by the puppet tuner, which places the body directly and saves from
-- the same coordinates it is showing you. Git is the archive; a dead second path that still
-- compiles is how a panel grows two ways to do one thing.)

-- ---------------------------------------------------------------------------
-- v1.8.8 THE FALLBACK SETTINGS MENU — every Esc-menu control, here in the CET window
-- ---------------------------------------------------------------------------
-- WHY THIS EXISTS. Every setting below lives in the Esc -> Settings -> Jackie Lives panel, which is
-- drawn by Native Settings UI — a SEPARATE mod. When that panel doesn't appear (reported 2026-08-20)
-- the player doesn't just lose a nicety: Husbando mode, the follow distance, the talk prompt, the
-- spawn backend and "Go Home Jackie" have no other home, so the mod becomes unconfigurable and the
-- one recovery button that unsticks him is unreachable. This is the way back in, and it is a plain
-- checkbox at the TOP of this window because someone who is already lost will not go hunting.
--
-- ⚠️ EVERY ROW HERE MUST DO EXACTLY WHAT ITS ESC-MENU TWIN DOES — write the same JL field, call
-- jlSaveSettings, and run the same side effect (jlApplyTalkPrompt, the re-armed AMM warning). Two
-- controls for one setting that quietly disagree is worse than one control that is hard to find.
--
-- Global (no top-level local) -> 200-cap safe.
function jlDrawFallbackMenu()
  ImGui.Separator()
  ImGui.TextColored(1.0, 0.85, 0.4, 1.0, "Settings — the same ones as Esc -> Settings -> Jackie Lives")
  ImGui.TextDisabled("Saved immediately, exactly as in the Esc menu.")

  -- ---- Relationship -------------------------------------------------------
  -- ⚠️ ImGui.Checkbox returns the VALUE, not a "changed" flag — same idiom as the mourning
  -- switches further down this window. Compare against what we had.
  local was, now_ = JL.husbando and true or false, nil
  now_ = ImGui.Checkbox("Husbando mode (off = Hermano, the canon default)", was)
  if now_ ~= was then
    JL.husbando   = now_
    JL.modeChosen = true            -- an EXPLICIT player choice — jlDefaultHermano stops forcing Hermano
    pcall(jlSaveSettings)
    JL.ui.status = "Jackie mode: " .. (now_ and "Husbando" or "Hermano")
    log("Jackie relationship mode -> " .. (now_ and "Husbando" or "Hermano") .. " (player choice; remembered)")
  end

  -- ---- Controls: the talk prompt ------------------------------------------
  ImGui.Text("Talk prompt when you look at him:")
  local pick = JL.talkPrompt or "native"
  local function promptBtn(label, value, sameLine)
    if sameLine then ImGui.SameLine() end
    if pick == value then
      ImGui.TextDisabled("[" .. label .. "]")
    elseif ImGui.SmallButton(label) then
      JL.talkPrompt = value
      pcall(jlSaveSettings)
      jlApplyTalkPrompt()           -- into the LIVE Config, now
      JL.ui.status = "Talk prompt: " .. value .. " (F still works)."
      log("Talk prompt -> " .. value)
    end
  end
  promptBtn("Game prompt", "native")
  promptBtn("Text", "text", true)
  promptBtn("None", "off", true)
  ImGui.SameLine(); ImGui.TextDisabled("(F always talks to him)")

  -- ---- Gameplay -----------------------------------------------------------
  was = JL.walkAbreast and true or false
  now_ = ImGui.Checkbox("Walk beside me (off = he trails you)", was)
  if now_ ~= was then
    JL.walkAbreast = now_
    pcall(jlSaveSettings)
    JL.ui.status = "Walk-beside style: " .. (now_ and "ON (walk abreast)" or "OFF (default trailing follower)")
    log("Custom walk-beside -> " .. (now_ and "ON" or "OFF (default follower)"))
  end

  was = JL.allowMainGigs and true or false
  now_ = ImGui.Checkbox("Allow Jackie on main missions (not recommended)", was)
  if now_ ~= was then
    JL.allowMainGigs = now_
    pcall(jlSaveSettings)
    JL.ui.status = "Jackie on main missions: " .. (now_ and "ALLOWED (not recommended)" or "blocked (Quiet Life)")
    log("Allow main-mission summons -> " .. tostring(now_))
  end

  -- Reads jlFollowDistance() exactly as the Esc-menu row does, so the two can never show a
  -- different number for the same setting.
  local gap, gapChg = ImGui.SliderFloat("Follow distance (m)", jlFollowDistance(),
                                        Config.followDistanceMin or 1.2,
                                        Config.followDistanceMax or 8.0, "%.1f")
  if gapChg then
    JL.followGap = gap
    pcall(jlSaveSettings)
    JL.ui.status = string.format("Jackie's follow distance: %.1f m", gap)
    log(string.format("Follow distance -> %.1f m (trail + walk-abreast)", gap))
  end

  -- ---- Arrivals -----------------------------------------------------------
  was = JL.disableVehicleArrivals and true or false
  now_ = ImGui.Checkbox("Disable vehicle arrivals (he always walks in)", was)
  if now_ ~= was then
    JL.disableVehicleArrivals = now_
    pcall(jlSaveSettings)
    JL.ui.status = "Vehicle arrivals: " .. (now_ and "DISABLED (foot only)" or "allowed")
    log("Vehicle arrivals -> " .. (now_ and "DISABLED (foot only)" or "allowed"))
  end

  -- ---- Compatibility ------------------------------------------------------
  was = JL.useAMM and true or false
  now_ = ImGui.Checkbox("Use AMM for spawning (off = the base game, no AMM needed)", was)
  if now_ ~= was then
    JL.useAMM = now_
    JL.ammMissingWarned = nil       -- re-arm the "you asked for AMM but it isn't there" notice
    pcall(jlSaveSettings)
    JL.ui.status = "Spawn backend: " .. (now_ and "AMM" or "native (no AMM needed)")
    log("Spawn backend -> " .. (now_ and "AMM (player choice)" or "native") ..
        ". Takes effect on the next summon; re-summon Jackie to switch a body that's already out.")
  end

  -- ---- The two buttons with no other home ---------------------------------
  -- The escape hatch for a questline that never started. It shipped unreachable once already
  -- (found 2026-08-14); with the Esc panel missing it would be unreachable again.
  if not Retrieval.isUnlocked() then
    if ImGui.Button("Start the search for Jackie") then
      local started = false
      pcall(function() started = Retrieval.startSearch() end)
      JL.ui.status = started and "The search for Jackie has begun — go see Vik."
                              or "The search is already under way."
    end
    ImGui.SameLine(); ImGui.TextDisabled("(use if his questline never started)")
  end
  if ImGui.Button("Go Home Jackie") then pcall(hardReset) end
  ImGui.SameLine(); ImGui.TextDisabled("(despawns every copy, sends a fresh one to his schedule)")
  ImGui.Separator()
end

registerForEvent("onDraw", function()
  -- (v1.63: the choice box is drawn by the GAME now — see dialogui.lua. Nothing to render here.)
  pcall(drawBlazeFade)                      -- v1.02: fade-to-black overlay draws DURING gameplay (covers HUD, not the ESC menu)
  if not JL.ui.overlayOpen then return end   -- the debug window only draws while the overlay is open
  if not JL.ui.open then return end
  ImGui.Begin("Jackie Lives")

  -- === THE WAY BACK IN (v1.8.8) — FIRST THING IN THE WINDOW ================
  -- Deliberately above everything, including the reunion-quest line: a player reading this has
  -- already failed to find the settings once, and making them scroll past the diagnostics to reach
  -- the fix would be the same mistake twice. See jlDrawFallbackMenu for why it exists at all.
  ImGui.TextColored(1.0, 0.85, 0.4, 1.0, "Can't see Esc -> Settings -> Jackie Lives? Tick this box:")
  do
    -- ⚠️ ImGui.Checkbox hands back the VALUE, not a "changed" flag (house idiom — see the mourning
    -- switches further down). Read it, compare, and only then save.
    local was = JL.fallbackMenu and true or false
    local now_ = ImGui.Checkbox("Bring the old menu back (all settings here in this window)", was)
    if now_ ~= was then
      JL.fallbackMenu = now_
      pcall(jlSaveSettings)
      log("Fallback settings menu -> " .. (now_ and "ON (settings shown in the CET window)" or "OFF"))
    end
  end
  if JL.fallbackMenu then
    -- pcall'd because this is the EMERGENCY menu: a bad row here must not take down the window a
    -- stuck player opened to fix things. But it says so once rather than just vanishing — a menu
    -- that silently isn't there is the exact failure this whole feature exists to answer.
    local okFb, errFb = pcall(jlDrawFallbackMenu)
    if not okFb and not JL.fallbackMenuWarned then
      JL.fallbackMenuWarned = true
      log("Fallback settings menu failed to draw: " .. tostring(errFb))
    end
  end

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

  -- === STATUS & DIAGNOSTICS: always visible (no header) — this is the at-a-glance state you
  -- read every time you open the window, so it must never need a click to see.
  local block, hour = currentScheduleBlock()
  ImGui.Text("AMM: " .. (JL.amm and "ok" or "MISSING") ..
             "   Jackie record: " .. (JL.jackie.record and "ok" or "?"))
  -- v1.63: is the native dialogue picker actually able to draw? "controller MISSING" is the one
  -- state that stops a conversation from opening, and it's invisible without this line.
  ImGui.Text("Dialogue picker: " .. (DialogUI.hasController() and "native, controller ok" or "native, controller MISSING") ..
             (DialogUI.isShown() and ("   [open, row " .. tostring(DialogUI.index()) .. "]") or ""))
  -- v1.63.1: the two buttons that turn "the box didn't appear" into an actual answer. Both write to
  -- jackie_debug.log (in this mod's folder), which is the file to send when reporting a failure.
  -- The native widget is GAME UI, so it draws out in the world (behind this window), not inside it.
  -- "Diagnose" leaves its probe box up for ~10 s so you can close the overlay and look; the test
  -- picker stays up until you select a row or hit "Close test picker".
  if ImGui.Button("Diagnose picker") then pcall(function() DialogUI.diagnose() end) end
  ImGui.SameLine()
  if ImGui.Button("Show test picker") then pcall(function() DialogUI.selfTest() end) end
  ImGui.SameLine()
  if ImGui.Button("Close test picker") then pcall(function() DialogUI.hide() end) end
  -- v1.72 DISTANCE. Colour-coded, because the number needs a scale to be read fast: green is normal
  -- following range, amber is "on his way / lost the trail", red is a spawn that went somewhere it
  -- shouldn't have. "no body out" is not an error.
  do
    local dV, whichBody = jlDistanceToV()
    if dV then
      local r, g, b = 0.5, 0.9, 0.5
      if dV > 60.0 then r, g, b = 1.0, 0.45, 0.45
      elseif dV > 15.0 then r, g, b = 1.0, 0.85, 0.4 end
      ImGui.TextColored(r, g, b, 1.0, ("Distance to V: %.1f m   (%s body)"):format(dV, whichBody))
    else
      ImGui.TextDisabled("Distance to V: no body out")
    end
  end
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
  ImGui.Separator()

  -- v1.60 LANGUAGE selector. Every local here is function-scoped (inside onDraw) so the main
  -- chunk's 200-local budget is untouched — the third safe pattern from the cap note up top.
  -- "Auto" follows the game's own language setting; an explicit pick persists to jl_settings.txt.
  if ImGui.CollapsingHeader("Language — " .. Lang.labelFor(Lang.code) .. (Lang.auto and " (auto)" or "")) then
    if ImGui.Button("Auto (follow game language)") then
      JL.langChoice = "auto"; Lang.auto = true; Lang.load(Lang.detect()); jlSaveSettings()
    end
    for i, L in ipairs(Lang.LANGUAGES) do
      if (i % 3) ~= 1 then ImGui.SameLine() end
      if ImGui.Button(L.label) then
        JL.langChoice = L.code; Lang.auto = false; Lang.load(L.code); jlSaveSettings()
      end
    end
    ImGui.Text(string.format("translated %d / fell back to English %d (this session)", Lang.hits, Lang.miss))
    ImGui.TextWrapped("Best results: leave this on Auto and run the GAME in your language. Subtitles, "
      .. "banners and shards use the GAME's font, which only carries the glyphs of the language the "
      .. "GAME is set to -- so forcing e.g. Japanese while the game runs in English shows blanks. "
      .. "V's choice box + this menu are drawn by CET, whose font is Latin-only until you point it at "
      .. "a CJK/Cyrillic font (see docs/localization.md).")
  end
  ImGui.Separator()

  -- v1.66 VOICE BACKEND selector. Every local here is function-scoped (inside onDraw), so the main
  -- chunk's 200-local budget is untouched.
  --
  -- ⚠️ WHY THIS EXISTS AT ALL. With mode="auto" the mod tries the native path and, if the redscript
  -- shim didn't load, SILENTLY falls back to an Audioware bank. For a player that is exactly right.
  -- For testing it is a trap: Jackie still speaks, out of the old bank, and you conclude the new path
  -- works when it doesn't. "Native only" removes the ambiguity — he either speaks, or he only grunts.
  if ImGui.CollapsingHeader("Voice — " .. string.upper(tostring(VO.backend(dialogueTarget())))) then
    ImGui.Text(VO.status(dialogueTarget()))
    ImGui.Separator()

    if ImGui.Button("Auto (recommended)") then
      Config.voice.mode = "auto"; JL.voiceMode = "auto"; VO.forget(); jlSaveSettings()
      JL.ui.status = "Voice: auto — the game's own VO, falling back to Audioware if present."
    end
    ImGui.SameLine()
    if ImGui.Button("Native only") then
      Config.voice.mode = "native"; JL.voiceMode = "native"; VO.forget(); jlSaveSettings()
      JL.ui.status = "Voice: NATIVE only — Audioware is locked out. Silence now means the shim isn't loaded."
    end
    ImGui.SameLine()
    if ImGui.Button("Audioware only") then
      Config.voice.mode = "audioware"; JL.voiceMode = "audioware"; VO.forget(); jlSaveSettings()
      JL.ui.status = "Voice: AUDIOWARE only — the pre-v1.66 path, for comparing the two by ear."
    end
    ImGui.SameLine()
    if ImGui.Button("Off") then
      Config.voice.mode = "off"; JL.voiceMode = "off"; VO.forget(); jlSaveSettings()
      JL.ui.status = "Voice: OFF — subtitles only."
    end

    ImGui.TextWrapped("Takes effect on the NEXT line he speaks — no reload needed, because vo.lua reads "
      .. "this setting live. The choice is saved to jl_settings.txt, so it also survives a reload. "
      .. "(You only need 'Reload all mods' if you edited config.lua on disk by hand.)")
    ImGui.Separator()
    ImGui.TextWrapped("native = the GAME's own recording of the line. Nothing shipped, nothing extracted. "
      .. "Needs redscript + r6\\scripts\\JackieLives\\JackieLivesVO.reds.\n"
      .. "audioware = the old path: a bank YOU built from your own game files.\n"
      .. "If neither is available he falls back to his own vocal efforts, which need nothing at all.")
    if VO.backend(dialogueTarget()) == "grunt" then
      ImGui.TextColored(1, 0.4, 0.4, 1, "No voice backend. Check that redscript is installed and that "
        .. "r6\\scripts\\JackieLives\\JackieLivesVO.reds is in your game folder.")
    end

    -- v1.70.1 V'S OWN VOICE. Everything above is about Jackie; V speaks her dialogue choices now.
    -- This block exists to answer ONE question by ear that cannot be answered from a Mac: whether
    -- the event shape changes which gendered take the engine plays, or whether the engine reads
    -- V's body and ignores us. One press, two takes, both named in the log.
    ImGui.Separator()
    ImGui.Text("V's voice — " .. string.upper(tostring(JL.vVoice or "auto"))
               .. "  (variant " .. tostring(jlPlayerVariant()) .. ")")
    if ImGui.Button("Test V's voice (A/B)") then
      local okAB, whyAB = jlVoiceABTest()
      JL.ui.status = okAB
        and "V voice A/B: take 1 now, take 2 in ~3 s. Listen — then set Esc > Settings > Jackie Lives > Voice."
        or ("V voice A/B failed: " .. tostring(whyAB))
    end
    ImGui.SameLine()
    if ImGui.Button("Auto") then
      JL.vVoice = "auto"; JL.vVoiceLogged = nil; jlSaveSettings()
      JL.ui.status = "V's voice: AUTO (follows V's body)"
    end
    ImGui.SameLine()
    if ImGui.Button("Male##v") then
      JL.vVoice = "male"; JL.vVoiceLogged = nil; jlSaveSettings()
      JL.ui.status = "V's voice: MALE (variant 0)"
    end
    ImGui.SameLine()
    if ImGui.Button("Female##v") then
      JL.vVoice = "female"; JL.vVoiceLogged = nil; jlSaveSettings()
      JL.ui.status = "V's voice: FEMALE (variant " .. tostring((Config.voice or {}).femaleVariant or 1) .. ")"
    end
    ImGui.TextWrapped("Plays ONE line (\"How's your mom?\") twice, ~3 s apart: first as variant 0 "
      .. "(male-V shape), then as variant 1 (female-V shape). Do it while Jackie is NOT mid-"
      .. "conversation so nothing lands on top. Whichever sounds like the V on your screen is the "
      .. "winner — pick it above, or in Esc > Settings > Jackie Lives > Voice.\n"
      .. "If BOTH takes sound identical, the engine is reading V's body and ignoring the event "
      .. "shape entirely: say so, and this switch gets retired instead of tuned.")

    -- v1.69 VOICE LAB. The dialogue event carries NO position field (verified against the RTTI
    -- dump), so if a line comes out of the wrong place the only variables are the ENTITY it was
    -- queued on and the context/expression it carried. These buttons fire the same line through
    -- each variant so you can hear which one puts Jackie's voice in Jackie's mouth. Summon him
    -- first — with nobody spawned every variant falls back to V and they all sound identical.
    ImGui.Separator()
    if ImGui.CollapsingHeader("Voice lab (positional audio A/B)") then
      local jackie = dialogueTarget()
      if not jackie then
        ImGui.TextColored(1, 0.8, 0.3, 1, "Summon Jackie first — with nobody spawned every test "
          .. "below plays on V and they all sound the same.")
      end
      ImGui.TextWrapped("Same line, four ways. Walk a few steps away from him before clicking, so "
        .. "'from his mouth' and 'from your head' are easy to tell apart. Each click also writes "
        .. "the receiving entity to the console.")

      -- A long line, so there is time to turn your head and locate it while it plays.
      if ImGui.Button("1. On Jackie (what ships)") then
        local ok, who = VO.probe(JL_VO_TESTLINE, jackie, 0, 0, "")
        JL.ui.status = "Lab 1 -> " .. tostring(who) .. " ok=" .. tostring(ok)
      end
      ImGui.SameLine()
      if ImGui.Button("2. On Jackie + his voice tag") then
        local ok, who = VO.probe(JL_VO_TESTLINE, jackie, 0, 0, "jackie")
        JL.ui.status = "Lab 2 -> " .. tostring(who) .. " ok=" .. tostring(ok)
      end
      if ImGui.Button("3. On Jackie, context Combat") then
        local ok, who = VO.probe(JL_VO_TESTLINE, jackie, 2, 0, "")
        JL.ui.status = "Lab 3 -> " .. tostring(who) .. " ok=" .. tostring(ok)
      end
      ImGui.SameLine()
      if ImGui.Button("4. On V (the control)") then
        local ok, who = VO.probe(JL_VO_TESTLINE, Game.GetPlayer(), 0, 0, "")
        JL.ui.status = "Lab 4 -> " .. tostring(who) .. " ok=" .. tostring(ok)
      end
      ImGui.TextWrapped("4 is the CONTROL: that is what 'coming from V' sounds like. If 1 sounds "
        .. "the same as 4, the entity isn't placing the voice and 2 is the next thing to try. "
        .. "Tell me which number sounded right and I'll make it the default.")
      ImGui.Text("context 0=Quest 1=Community 2=Combat 3=MinorActivity 5=Default")
      ImGui.Text("expression 0=Spoken 1=Phone 2=InnerDialog 6=Radio 11=Helmet")
    end
  end
  ImGui.Separator()

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
          or ((not JL.walkAbreast) and "trailing (walk-beside OFF)"
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
    -- v1.61: prove the holster command in isolation. Reads V + Jackie weapon state, then forces a holster.
    ImGui.Separator()
    do
      local pl = Game.GetPlayer()
      local jh = JL.summon.spawn and JL.summon.spawn.handle
      ImGui.Text(("Weapon drawn — V: %s | Jackie: %s"):format(
        (pl and jlWeaponDrawn(pl)) and "YES" or "no",
        (jh and jlWeaponDrawn(jh)) and "YES" or "no"))
      if ImGui.Button("TEST: force Jackie to holster now") then
        if jh then
          local ok = jlHolster(jh)
          JL.ui.status = ok and "Holster command sent — watch if his gun goes away." or "Holster command errored (see console)."
          log("WeaponMirror TEST: manual holster issued (ok=" .. tostring(ok) .. ").")
        else
          JL.ui.status = "Summon Jackie first."
        end
      end
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

  -- ===========================================================================
  -- v1.9 SEAT TUNER — one panel, and it is a puppet manipulation tool
  -- ===========================================================================
  -- Replaces v1.77's split into a "Sitting" section and a "Seat tuner" section. They were one job
  -- pretending to be two, and the split is what produced the duplicate-id bug in the first place.
  --
  -- The ORDER of this panel is the order the job actually has to happen in, and it is not cosmetic:
  -- take the AI off them, drop collision, THEN move and pose. Slide them before taking control and
  -- the follow AI drags them back while you watch, which reads as "the sliders don't work".
  if ImGui.CollapsingHeader("Seat tuner — pose them by hand##jlseattuner") then
    local P = JL.puppet
    local held = (P and P.on) and true or false

    ImGui.TextWrapped("Companions stand at tables — the sit animation isn't tied to real furniture, "
      .. "so an automatic sit floats. Place them yourself and it lands exactly where you put it.")
    -- v1.8.5: name the dependency BEFORE they press a dead button, not after. Placing them and
    -- turning them is ours and always works; the sit/lean ANIMATION is AMM's workspot system.
    if not getAMM() then
      ImGui.TextColored(0.95, 0.80, 0.35, 1.0, "AppearanceMenuMod is not loaded.")
      ImGui.TextWrapped("Placing and turning them still works. \"Seat them\" will not — the sit and "
        .. "lean animations are AMM's, and there is no substitute for them in this mod.")
      ImGui.Separator()
    end
    ImGui.Text("1. Stand where you can SEE them.")
    ImGui.Text("2. Take control - this switches their AI off.")
    ImGui.Text("3. Slide them into the chair. They move as you drag.")
    ImGui.Text("4. Press Seat them to play the animation.")
    ImGui.Text("5. Nudge until it looks right, then Save this seat.")
    ImGui.Text("6. Release them when you're done.")
    ImGui.Separator()

    -- ── 1. CONTROL. Nothing below works until the AI is off, so it is the first control. ──
    do
      local h, which = jlSeatTargetHandle()
      if held then
        ImGui.TextColored(0.45, 0.95, 0.55, 1.0, "IN CONTROL - their AI is off (" .. tostring(P.which) .. ")")
      elseif h then
        ImGui.TextColored(0.95, 0.80, 0.35, 1.0, "Their AI is RUNNING - it will fight the pose. Take control first.")
      else
        ImGui.TextDisabled("Nobody's out. Call a companion, or find one at their venue.")
      end
      if not held then
        if ImGui.Button("Take control (AI off)##jlpup") then jlPuppetTake() end
      else
        if ImGui.Button("Release them (AI back on)##jlpup") then jlPuppetRelease("button") end
      end
      ImGui.SameLine()
      if ImGui.Button("What's this? (show card)##jlpup") then
        JL.ui.status = jlShowSeatTip(true)
          and "Seating card shown (bottom-left; press any key to dismiss)."
          or  "Native popup unavailable - shown on the notice band instead."
      end
    end

    -- ── 2. COLLISION. High up because a solid chair shoves a collided NPC straight back out. ──
    ImGui.Separator()
    do
      local prev = Config.idleNoCollision
      Config.idleNoCollision = ImGui.Checkbox("Collisions OFF (they can be pushed into furniture)",
                                              Config.idleNoCollision and true or false)
      if Config.idleNoCollision ~= prev then
        applyIdleCollision()
        log("Idle collision master -> " .. (Config.idleNoCollision and "OFF (no collision)" or "ON (normal collision)"))
      end
      local live = "-"
      if held then live = "OFF - the tuner holds them"
      elseif JL.dinner.collisionOff then live = "OFF - dinner seat"
      elseif JL.idle.spawn then live = JL.idle.collisionOff and "OFF" or "ON" end
      ImGui.TextDisabled(("live on them: %s"):format(live))
    end

    -- ── 3. MOVE. LIVE: every change places them immediately. ──
    -- ⚠️ Forward/Right are relative to the NPC'S OWN FACING, not world X/Y. "Shove them forward" has
    -- to mean forward from where you are looking at them, or these are a coordinate puzzle.
    -- ⚠️ Moving DROPS the pose and re-plays it a beat after you stop: a puppet pinned in a workspot
    -- cannot be teleported (this repo's "solid as a rock" finding). So you see them slide on their
    -- feet and sit again when you let go. That is deliberate, not a glitch.
    ImGui.Separator()
    if not held then
      ImGui.TextDisabled("Take control to move them.")
    else
      local ch
      P.dy,   ch = ImGui.SliderFloat("Forward / back (m)##jlpup", P.dy or 0, -3.0, 3.0)
      if ch then jlPuppetPlace(true) end
      P.dx,   ch = ImGui.SliderFloat("Left / right (m)##jlpup",   P.dx or 0, -3.0, 3.0)
      if ch then jlPuppetPlace(true) end
      P.dz,   ch = ImGui.SliderFloat("Up / down (m)##jlpup",      P.dz or 0, -2.0, 2.0)
      if ch then jlPuppetPlace(true) end
      P.dyaw, ch = ImGui.SliderFloat("Turn (deg)##jlpup",         P.dyaw or 0, -180.0, 180.0)
      if ch then jlPuppetPlace(true) end

      if ImGui.Button("fwd -0.05##jlpup") then P.dy = (P.dy or 0) - 0.05; jlPuppetPlace(true) end ImGui.SameLine()
      if ImGui.Button("fwd +0.05##jlpup") then P.dy = (P.dy or 0) + 0.05; jlPuppetPlace(true) end ImGui.SameLine()
      if ImGui.Button("up -0.05##jlpup")  then P.dz = (P.dz or 0) - 0.05; jlPuppetPlace(true) end ImGui.SameLine()
      if ImGui.Button("up +0.05##jlpup")  then P.dz = (P.dz or 0) + 0.05; jlPuppetPlace(true) end
      if ImGui.Button("Reset to where they stood##jlpup") then
        P.dx, P.dy, P.dz, P.dyaw = 0, 0, 0, 0; jlPuppetPlace(true)
      end
      local x, y, z, yaw = jlPuppetCoords()
      ImGui.TextDisabled(("world { %.3f, %.3f, %.3f }  yaw %.1f"):format(x, y, z, yaw))
    end

    -- ── 4. POSE. The animation set, so a barstool and a low chair aren't the same button. ──
    ImGui.Separator()
    if held then
      if ImGui.Button("Seat them##jlpup") then jlPuppetPose("sit") end
      ImGui.SameLine()
      if ImGui.Button("Stand them up##jlpup") then
        pcall(function() stopWorkspotPose(P.handle) end); P.posed = false
        JL.ui.status = "Standing. They stay under your control."
      end
      ImGui.SameLine()
      if ImGui.Button("Lean##jlpup") then jlPuppetPose("lean") end
      -- Per-anim: the venue seats are not all the same furniture.
      local PZ = Config.poses or {}
      local anims = { { "Barstool", PZ.sit }, { "Chair (low)", PZ.sitChair }, { "Wall lean", PZ.lean } }
      for i, a in ipairs(anims) do
        if a[2] then
          if i > 1 then ImGui.SameLine() end
          if ImGui.Button(a[1] .. "##jlpupanim" .. i) then
            P.anim = a[2]
            jlPuppetPose(a[1] == "Wall lean" and "lean" or "sit")
          end
        end
      end
      ImGui.TextDisabled("playing: " .. tostring(P.anim or PZ.sit or "-") .. (P.posed and "  (posed)" or "  (standing)"))
    else
      ImGui.TextDisabled("Take control to pose them.")
    end

    -- ── 5. STORE. A tuned spot is worth nothing until it survives a reload. ──
    ImGui.Separator()
    if not JL.tuner.init then tunerInit() end
    local t = JL.tuner
    ImGui.Text("Save as a venue seat:")
    local venues = tunerSitVenues()
    for i, k in ipairs(venues) do
      if ((i - 1) % 4) ~= 0 then ImGui.SameLine() end
      local loc = Config.locations[k]
      if ImGui.Button(((loc and loc.name or k) .. (k == t.key and " *" or "")) .. "##tv_" .. k) then
        t.key, t.seatIdx = k, 1
        log("Seat tuner -> " .. k .. " (" .. (loc and loc.name or k) .. ").")
      end
    end
    local _, _, seats = tunerSeatWaypoint()
    if seats and #seats > 1 then
      if ImGui.Button("< prev seat##jlpup") then t.seatIdx = ((t.seatIdx - 2) % #seats) + 1 end
      ImGui.SameLine()
      if ImGui.Button("next seat >##jlpup") then t.seatIdx = (t.seatIdx % #seats) + 1 end
      ImGui.SameLine(); ImGui.Text(("seat %d / %d"):format(t.seatIdx, #seats))
    end
    if held then
      if ImGui.Button(("Save this seat as %s #%d##jlpup"):format(tostring(t.key), t.seatIdx)) then
        local x, y, z, yaw = jlPuppetCoords()
        local wp, loc, sl = tunerSeatWaypoint()
        if wp then wp.pos = { x, y, z }; wp.yaw = yaw end
        if loc and (#(sl or {}) <= 1) then loc.pos = { x, y, z }; loc.yaw = yaw end
        jlPersistSeat(t.key, t.seatIdx, x, y, z, yaw)
        JL.ui.lastCapture = string.format("pos = { %.3f, %.3f, %.3f }, yaw = %.1f", x, y, z, yaw)
        JL.ui.status = ("Saved %s seat %d - survives a reload."):format(tostring(t.key), t.seatIdx)
        log(("%s seat %d saved -> %s"):format(tostring(t.key), t.seatIdx, JL.ui.lastCapture))
      end
      ImGui.TextDisabled("Writes jl_seats.txt and applies now. Automatic sitting stays off until "
        .. "you turn it on below.")
    else
      ImGui.TextDisabled("Take control and place them, then save.")
    end

    -- ── 6. The escape hatch, for anyone who HAS tuned their venues. ──
    ImGui.Separator()
    do
      local prev = (Config.poses and Config.poses.enabled) and true or false
      local now  = ImGui.Checkbox("Let them sit down automatically (off by default - often floats)", prev)
      if Config.poses and now ~= prev then
        Config.poses.enabled = now
        log("Automatic sit/lean -> " .. (now and "ON" or "OFF (they stand)"))
        JL.ui.status = now and "Automatic sitting ON - expect floating on untuned seats."
                            or  "Automatic sitting OFF - they stand."
      end
    end
    ImGui.TextDisabled("Not saved across a reload on purpose - set Config.poses.enabled in config.lua "
      .. "to make it permanent.")
  end



  ImGui.Separator()
  if JL.ui.status ~= "" then ImGui.TextWrapped("> " .. JL.ui.status) end

  ImGui.End()
end)

registerForEvent("onShutdown", function()
  -- ⚠️ FIRST: our Talk row lives inside ANOTHER MOD'S table. Unloading without removing it leaves
  -- NCA rendering a row whose callback belongs to a mod that no longer exists.
  pcall(function() Allies.detach() end)
  -- Same reasoning, milder consequence: our heartbeat callback lives in 0-Engine's frame dispatcher.
  -- Dropping our reference stops their overlay listing a mod that is no longer loaded.
  pcall(function() ZEngine.detach() end)
  pcall(closeNativeCallWindow)   -- never leave a holocall window stuck open
  pcall(DialogUI.hide)           -- v1.63: never leave the native dialogue hub stuck on screen
  pcall(hideJackieChoiceBox)
  pcall(hideSubtitle)
  pcall(jlLookAtStop)            -- v1.41: never leave a look-at overlay on a puppet we're about to drop
  pcall(clearIdle)
  pcall(clearVehicleArrival)     -- v0.34: never orphan the arrival bike
  pcall(bikeTestDespawn)         -- v0.63: never orphan the bike-model test spawn
  pcall(function() jlManualUnseat("shutdown") end)  -- v1.77: never leave a hand-seated puppet in a workspot we no longer own
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
