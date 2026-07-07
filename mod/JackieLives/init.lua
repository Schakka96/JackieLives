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
Blaze     = require("blaze")       -- v0.96 GLOBAL (200-cap): "Blaze of Glory" Heist set-piece (see blaze.lua)
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
  settle  = { hideUntil = nil, collideUntil = nil, handle = nil },
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
function blazeDumpConfig()
  local c = Blaze.cfg
  local function q(s)   return s and string.format("%q", tostring(s)) or "nil" end
  local function pos(p) return p and string.format("{ x = %.3f, y = %.3f, z = %.3f, yaw = %.1f }", p.x, p.y, p.z, p.yaw or 0.0) or "nil" end
  local out = {
    "-- Blaze of Glory captured config (AUTO-WRITTEN; re-loaded on launch). Move to Mac to bake into blaze.lua.",
    "Blaze.cfg.smasherRecord = " .. q(c.smasherRecord),
    "Blaze.cfg.goroRecord    = " .. q(c.goroRecord),
    "Blaze.cfg.heliRecord    = " .. q(c.heliRecord),
    "Blaze.cfg.smasherPos    = " .. pos(c.smasherPos),
    "Blaze.cfg.goroPos       = " .. pos(c.goroPos),
    "Blaze.cfg.heliPos       = " .. pos(c.heliPos),
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
local function ammSpawn(companionFlag, appearance)
  local amm = getAMM()
  if not amm or not amm.Spawn or not amm.Spawn.NewSpawn then return nil, "AMM Spawn module not available" end
  if not resolveJackieRecord() then return nil, "Jackie record not found" end
  local recStr = tostring(JL.jackie.record)
  local app = (appearance and appearance ~= "") and appearance or (Config.defaultAppearance or "random")
  -- Force AMM's companion toggle to MATCH the flag. It was only ever set TRUE (for companion
  -- spawns) and never reset, so a "passive" arrival spawn following any companion summon still
  -- came out as a companion -> follower role -> catch-up TELEPORT to V's face. Resetting it to
  -- false makes companionFlag 0 truly passive (no follower role, no teleport).
  pcall(function() if amm.userSettings then amm.userSettings.spawnAsCompanion = (companionFlag == 1) end end)
  local spawn
  local ok = pcall(function()
    spawn = amm.Spawn:NewSpawn(JL.jackie.name or "Jackie", recStr, { app = app }, companionFlag, recStr)
  end)
  if not ok or not spawn then return nil, "NewSpawn failed" end
  local ok2 = pcall(function() amm.Spawn:SpawnNPC(spawn) end)
  if not ok2 then return nil, "SpawnNPC failed" end
  return spawn
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
    if hourInBlock(h, b.startHour, b.endHour) then return b, h end
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

-- Show text via the game's native on-screen message blackboard (reliable, no attach).
local function showOnscreenMsg(text, duration)
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
    showOnscreenMsg(tostring(speaker) .. ":   " .. tostring(text), (duration or 4.0) + 0.5)
  end
end

-- Show the prompt while looking at Jackie within talk range. Called (throttled) from onUpdate.
local function updateTalkPrompt(dt)
  talkUI.checkT = (talkUI.checkT or 0) + dt
  if talkUI.checkT < 0.2 then return end
  talkUI.checkT = 0
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
        showOnscreenMsg("Talk to Jackie   [ " .. key .. " ]", 3.0)
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
-- The two emotional beats that get length-scaled subtitles: the reunion phone call + first meeting.
local function isReunionBeat()
  return bstate.tree == Config.reunionCallTree or bstate.tree == Config.reunionMeetTree
end

-- Play a Jackie line: real voice (sfx, else the guaranteed jl_fallback WAV) + subtitle.
local function speakJackieLine(text, sfx)
  local spoke = false
  if sfx then spoke = playVoice(sfx) end
  if not spoke then spoke = playVoice("jl_fallback") end
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
  pcall(function() speakJackieLine(line, sfx) end)
  -- v0.64: flash the objective as the native neon-left on-screen message (not a persistent ImGui box).
  local fmt = (D.objectiveText) or "Grab some food with Jackie: Go to %s"
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

local function drawNameChild(name)
  ImGui.PushStyleColor(ImGuiCol.Border, COL.frame[1], COL.frame[2], COL.frame[3], 1.0)
  ImGui.PushStyleVar(ImGuiStyleVar.ChildBorderSize, 1.0)   -- thin frame
  ImGui.BeginChild("##jkname", 128, 34, true)
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
    -- selected = recolored text (no bar); for comparison
    for i, c in ipairs(menu.choices) do
      local col = (i == menu.sel) and COL.bar or COL.unsel
      ImGui.PushStyleColor(ImGuiCol.Text, col[1], col[2], col[3], 1.0)
      ImGui.Text(tostring(c.text or ""))
      ImGui.PopStyleColor(1)
    end
  else
    -- styles 1 & 3: SOLID yellow bar behind the selected row, sized to the TEXT width
    -- (explicit Selectable size -> no more growing bar).
    ImGui.PushStyleColor(ImGuiCol.Header,        COL.bar[1], COL.bar[2], COL.bar[3], 1.0)
    ImGui.PushStyleColor(ImGuiCol.HeaderHovered, COL.bar[1], COL.bar[2], COL.bar[3], 1.0)
    ImGui.PushStyleColor(ImGuiCol.HeaderActive,  COL.bar[1], COL.bar[2], COL.bar[3], 1.0)
    for i, c in ipairs(menu.choices) do
      local label = " " .. tostring(c.text or "") .. " "
      local tw    = ImGui.CalcTextSize(label)            -- reflects the window font scale (set in Begin)
      local col   = (i == menu.sel) and COL.selTx or COL.unsel
      ImGui.PushStyleColor(ImGuiCol.Text, col[1], col[2], col[3], 1.0)
      ImGui.Selectable(label, i == menu.sel, 0, tw, 0)   -- width = text width -> bar fits the text
      ImGui.PopStyleColor(1)
    end
    ImGui.PopStyleColor(3)
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
    -- v0.33: centre the box on the screen's X axis and sit it a little lower than before.
    local W, H = 620, 240
    local sw, sh = 1920, 1080
    pcall(function() local x, y = ImGui.GetDisplaySize(); if x and x > 0 then sw, sh = x, y end end)
    local px = (sw - W) * 0.5 - 150      -- centred, then nudged left (v0.33e)
    local py = sh * 0.46                 -- a bit below mid-screen (was a fixed 360)
    ImGui.SetNextWindowPos(px, py, ImGuiCond.Always)
    ImGui.SetNextWindowSize(W, H, ImGuiCond.Always)       -- fixed (transparent) -> stable layout
    ImGui.Begin("##jkpicker", pickerWindowFlags())
    ImGui.SetWindowFontScale(1.45)
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
  local shown = {}
  for _, c in ipairs(choices or {}) do
    local appear = true
    if c.chance then local r = 1.0; pcall(function() r = math.random() end); appear = (r < c.chance) end
    if appear then
      if c.textPool and #c.textPool > 0 then
        local i = 1; pcall(function() i = math.random(1, #c.textPool) end)
        c.text = c.textPool[i]
      end
      shown[#shown + 1] = c
    end
  end
  if #shown == 0 then shown = choices end   -- safety: never open an empty menu
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
  local secs = speakJackieLine(jline and jline.text, jline and jline.sfx)
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
  triggerNativeCall((Config.nativeCall and Config.nativeCall.id) or "jackie_dead", "StartCall", 2)
  JL.call.nativeOpen = true
end

-- Close the native holocall window (EndCall). Safe to call when none is open.
local function closeNativeCallWindow()
  if not JL.call.nativeOpen then return end
  JL.call.nativeOpen = false
  triggerNativeCall((Config.nativeCall and Config.nativeCall.id) or "jackie_dead", "EndCall", 3)
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
  if name == "reunion_arrival" then   -- v0.85: the reunion CALL ended -> he comes to V on foot
    if jlReturnJackiesBike then pcall(jlReturnJackiesBike) end                 -- his Arch is his again
    pcall(function() Game.GetQuestsSystem():SetFactStr("jackielives_daemon", 1) end)  -- launch daemon-removal quest (stub)
    local delay = (Config.call and Config.call.vehicleSpawnDelay) or 2.0
    JL.varrival.at      = (JL.clock or 0) + delay
    JL.varrival.useBike = false          -- FOOT walk-in (reuse the standard foot arrival)
    JL.reunionPending   = true           -- arrivalGreetTick plays reunionMeetTree instead of a greeting
    JL.ui.status = "Jackie's on his way in..."
    log("Reunion: bike returned + FOOT walk-in armed; reunionMeet pending.")
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

-- Begin a holocall. With useNativeWindow: fire the native RING (IncomingCall) now; callTick
-- then aborts it (STOP) and switches to the CONNECT window before running our convo.
local function startCall()
  -- v0.85: in AWAITING_CALL (shard read, reunion not done) V CAN call — Jackie always answers.
  if not Retrieval.isUnlocked() and not Retrieval.isAwaitingCall() then
    JL.ui.status = Retrieval.unavailableMsg(); Retrieval.notifyUnavailable(); return       -- gated until the retrieval quest is done
  end
  if Branch.open or Branch.busy or dlg.active then JL.ui.status = "Busy - finish the current talk first."; return end
  if JL.summon.active then JL.ui.status = "Jackie's already with you."; return end
  if isMainQuestActive() then jlDeclineMainQuest(); return end
  Branch.busy = true                       -- reserve so the look-prompt / talk don't fight the ring
  pcall(hideJackieChoiceBox)
  local id   = (Config.nativeCall and Config.nativeCall.id) or "jackie_dead"
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
  local id  = (Config.nativeCall and Config.nativeCall.id) or "jackie_dead"
  local native = Config.nativeCall and Config.nativeCall.useNativeWindow

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

-- The player dialled Jackie from the in-game phone (the game fired IncomingCall). Route it into
-- our flow: the native ring is already playing, so we just arm callTick (STOP -> CONNECT -> convo)
-- without re-firing IncomingCall ourselves.
local function onPlayerCalledJackie()
  if not Retrieval.isUnlocked() and not Retrieval.isAwaitingCall() then return end  -- gated: let the game's own call ring out (no hijack)
  if Branch.open or Branch.busy or dlg.active then return end   -- already talking
  if JL.summon.active then return end                          -- already with you
  if isMainQuestActive() then jlDeclineMainQuest(); return end  -- v0.93: tell the player WHY (blue notice)
  -- v0.55: asleep -> DON'T hijack. The game's own ring just plays out and auto-hangs-up; Jackie
  -- never "picks up" (our connect hook never arms). Matches "rings until it auto hangs up".
  if jackieAsleep() and not Retrieval.isAwaitingCall() then   -- v0.85: reunion call always connects
    JL.ui.status = "Jackie's not pickin' up (asleep)."
    log("Hijack: player called Jackie while asleep -> left it ringing (no pickup).")
    return
  end
  Branch.busy = true
  local ring = (Config.call and Config.call.ringEvent) or ""
  if ring ~= "" then pcall(function() playVoice(ring) end) end
  JL.call.ringingAt = (JL.clock or 0) + ((Config.call and Config.call.ringSeconds) or 2.0)
  JL.ui.status = "Jackie picking up..."
  log("Hijack: player called Jackie from the phone -> running our flow.")
end

-- Observe PhoneSystem:TriggerCall; when the PLAYER calls Jackie's contact (IncomingCall on a
-- 'jackie' call id, not one of our own TriggerCalls), hand off to onPlayerCalledJackie.
local function setupCallHijack()
  if not (Config.nativeCall and Config.nativeCall.hijackPlayerCalls) then return end
  local ok, err = pcall(function()
    Observe("PhoneSystem", "TriggerCall", function(self, mode, b1, callId, b2, phase)
      if JL.call.selfTriggering then return end                -- ignore our own TriggerCalls
      local nm = tostring(callId)
      if not nm:find("jackie") then return end                 -- only Jackie's contact
      if not tostring(phase):find("IncomingCall") then return end
      pcall(onPlayerCalledJackie)
    end)
  end)
  log("Call hijack " .. (ok and "registered (player phone calls to Jackie -> our flow)." or ("FAILED: " .. tostring(err))))
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
local function sendWalkToPlayer(handle, movementType, desiredDistance)
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
  opts = opts or {}
  -- 1) parting line (real VO + subtitle), like any Jackie line. Capture its duration so we can WIPE the
  --    subtitle afterwards - a one-off speakJackieLine has no follow-up hide, so the line stuck forever.
  local secs = 4.0
  -- v0.94: parting line is a POOL (Config.dismiss.partingPool) picked at random each dismiss; falls back to
  -- the single partingText/partingSfx. An explicit opts.text (e.g. mainQuestExit) still overrides the pool.
  -- These are function-local (NOT main-chunk locals) so they don't count toward init.lua's 200-local cap.
  local pText, pSfx = D.partingText, D.partingSfx
  if D.partingPool and #D.partingPool > 0 then
    local pick = D.partingPool[math.random(#D.partingPool)]
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

-- Clean up a leftover arrival bike (called from dismiss paths + on handoff).
local function despawnArrivalBike()
  if JL.varrival.bikeId then deleteEntityById(JL.varrival.bikeId) end
  JL.varrival.bikeId, JL.varrival.bikeHandle = nil, nil
end

-- Resolve the DES-spawned Jackie's handle from his entity id (stored on JL.summon.spawn).
local function resolveJackieHandle()
  local sp = JL.summon.spawn
  if not sp then return nil end
  if sp.handle then return sp.handle end
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
  JL.summon.spawn = { id = jid, handle = nil }
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
  JL.summon.spawn = { id = jid, handle = nil }
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
    JL.summon.spawn = { id = jid, handle = nil }
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
  if va.bikeId and not va.bikeHandle then pcall(function() va.bikeHandle = Game.FindEntityByID(va.bikeId) end) end
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
local function catchUpTick()
  local C = Config.catchUp or {}
  if C.enabled == false then return end
  -- settled companion only: active + role applied, and NOT mid-arrival / dinner / walking-off.
  if not (JL.summon.active and JL.summon.companionSet) then JL.catchUp.farSince, JL.catchUp.teleTries = nil, nil; return end
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

  -- moderate gap, body still local: land him a few metres to V's SIDE on the navmesh (never ON V), then
  -- re-assert follow. Count the attempt so a no-op teleport escalates to a respawn on the next eligible tick.
  local pt = navmeshArrivalPoint(C.placeDistance or 3.0) or arrivalPoint()
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

-- v0.67 KEEP-CLOSE FOLLOW. After handoff we issue ONE tight follow (followDistance), but AMM's own
-- companion follow then takes over with a much LONGER leash, so Jackie trails far behind V. This
-- re-asserts our tight AIFollowTargetCommand on a throttle so he holds `Config.follow.distance` (a few
-- metres) instead. Gated to the settled companion state only (not mid-arrival/dinner/walk-off) so it
-- never fights the scripted movement. If it ever looks jittery in-game, raise `interval` or set
-- enabled=false. Tiering: this owns ~handoff..catchUp.distance; catchUpTick teleports beyond that.
local function followKeepCloseTick()
  local F = Config.follow or {}
  if F.enabled == false then return end
  -- v0.85b: abreast owns positioning ONLY while V walks; at jog/sprint the trail takes back over.
  if Config.abreast and Config.abreast.enabled and jlVWalking() then return end
  if not (JL.summon.active and JL.summon.companionSet) then return end
  if JL.dinner.phase or JL.leaving.phase or (JL.varrival and JL.varrival.phase)
     or (jlCruise and jlCruise.active) then return end   -- v0.85: leave him on his cruising bike
  local h = JL.summon.spawn and JL.summon.spawn.handle
  if not h then return end
  local now = JL.clock or 0
  if (now - (JL.follow.lastAt or -1e9)) < (F.interval or 1.5) then return end
  JL.follow.lastAt = now
  -- don't fight the catch-up teleport: if he's far enough for that to own him, leave it.
  local pp = playerPos(); if not pp then return end
  local jp; pcall(function() jp = h:GetWorldPosition() end); if not jp then return end
  if dist3(pp, jp) > ((Config.catchUp and Config.catchUp.distance) or 25.0) then return end
  sendWalkToPlayer(h, F.movement or "Run", F.distance or 2.5)
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
--  * GET INTO POSITION, gently. When OUT of position (>`catchUpDist`) he moves at `catchUpMovement` (Run)
--    to close in, then eases to `movement` (Walk, matching V's walk pace) to hold the pocket.
--  * WALK-ONLY. Only active while V WALKS (jlVWalking); at jog/sprint abreastTick yields and the trail
--    (followKeepCloseTick) takes over — V has 3 speeds, Jackie 2, so he can't out-pace a jogging V.
-- Command re-issue is throttled to `interval` (short, so he tracks the drifting anchor). Global -> cap safe.
function abreastTick()
  local A = Config.abreast or {}
  if not A.enabled or not (JL.summon.active and JL.summon.companionSet)
     or JL.dinner.phase or JL.leaving.phase or (JL.varrival and JL.varrival.phase)
     or (jlCruise and jlCruise.active)                      -- v0.85: not while cruising on his bike
     or not jlVWalking() then
    JL.abreast.smFwdX = nil   -- reset the heading EMA so it re-seeds cleanly when abreast resumes
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
  local tau   = A.smoothSeconds or 3.3
  local alpha = (tau > 0) and math.min(math.max(dt / tau, 0.0), 1.0) or 1.0
  local sx = JL.abreast.smFwdX + alpha * (fx - JL.abreast.smFwdX)
  local sy = JL.abreast.smFwdY + alpha * (fy - JL.abreast.smFwdY)
  local sm = math.sqrt(sx * sx + sy * sy); if sm > 1e-4 then sx, sy = sx / sm, sy / sm end
  JL.abreast.smFwdX, JL.abreast.smFwdY = sx, sy

  -- --- two candidate anchors off the smoothed heading; pick the side closest to Jackie --------------
  local rad  = A.radius or 3.5
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
  local dest = Vector4.new(tx, ty, pp.z, 1.0)

  -- --- issue on a short throttle; move in when out of position, ease when holding it ---------------
  if (now - (JL.abreast.lastAt or -1e9)) < (A.interval or 0.3) then return end
  JL.abreast.lastAt = now
  local outOfPos = gap > (A.catchUpDist or 2.0)
  local mv  = outOfPos and (A.catchUpMovement or "Run") or (A.movement or "Walk")
  local tol = outOfPos and (A.catchUpTolerance or 0.35) or (A.tolerance or 0.5)
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
    local startIdx = math.random(1, #wps)
    JL.idle.curIdx     = startIdx
    applyIdlePose(h, wps[startIdx], true)              -- force-teleport him onto the spot
    JL.idle.placed     = true
    JL.idle.phase      = "dwelling"
    JL.idle.dwellUntil = now + dwellFor(wps[startIdx])
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
  local ok, err = pcall(function()
    ns.addTab("/jackielives", "Jackie Lives")

    ns.addSubcategory("/jackielives/relationship", "Relationship")
    ns.addSwitch(
      "/jackielives/relationship",
      "Husbando mode",
      "OFF = Hermano (canon): Jackie's your brother-in-arms and he's with Misty. " ..
      "ON = Husbando: Jackie and V are closer/together and he's broken up with Misty. " ..
      "(Mode-specific dialogue and venue schedules are WIP — toggling this only sets the flag for now.)",
      JL.husbando,   -- current state
      false,         -- default (Hermano)
      function(state)
        JL.husbando = state
        pcall(jlSaveSettings)
        JL.ui.status = "Jackie mode: " .. (state and "Husbando" or "Hermano")
        log("Jackie relationship mode -> " .. (state and "Husbando" or "Hermano"))
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
JL_SETTINGS_KEYS = { "husbando", "disableVehicleArrivals", "mourningSuppress" }  -- persisted JL.* boolean flags

function jlSaveSettings()
  local f = io.open(JL_SETTINGS_FILE, "w")
  if not f then log("settings: could not write " .. JL_SETTINGS_FILE); return end
  for _, k in ipairs(JL_SETTINGS_KEYS) do f:write(k .. "=" .. tostring(JL[k] == true) .. "\n") end
  f:write("mode=" .. tostring(JL.mode or "quietlife") .. "\n")  -- v0.95 string setting (not a boolean)
  f:close()
end

function jlLoadSettings()
  local f = io.open(JL_SETTINGS_FILE, "r")
  if not f then return end
  for line in f:lines() do
    local k, v = line:match("^(%w+)=(%w+)$")
    if k then
      if k == "mode" and (v == "quietlife" or v == "blaze") then JL.mode = v end  -- v0.95
      for _, want in ipairs(JL_SETTINGS_KEYS) do
        if k == want then JL[k] = (v == "true") end
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
  -- "Heroes" ofrenda side quest (sq018). Pinning sq018_active to 0 stops the whole
  -- ofrenda arming without touching the body-choice above. Heroes is a narrative
  -- dead-end (not a prerequisite), so pinning it is low-risk.
  { name = "sq018_active",                  hold = 0, note = "Heroes/ofrenda quest arm flag" },        -- CONFIRM value
  { name = "sq018_01_funeral_preparations", hold = 0, note = "ofrenda prep phase" },                   -- CONFIRM value
  -- Grief holocalls (Mama Welles / Misty phone their condolences). Fact NAMES are
  -- guesses — the holocall questphases didn't expose a clean *_on token via strings.
  -- { name = "mama_welles_holocall_on",    hold = 0, note = "Mama grief call" },                       -- CONFIRM name+value
  -- { name = "misty_holocall_on",          hold = 0, note = "Misty grief call" },                      -- CONFIRM name+value
  -- World-bark grief (Misty at Esoterica / Mama at El Coyote switch to mourning
  -- state). Tier-3 / ambient — leave COMMENTED until confirmed safe; some of these
  -- may be desirable to keep (a somber-but-alive Misty is not lore-breaking).
  -- { name = "misty_default_grief_on",     hold = 0, note = "Misty ambient grief state" },             -- CONFIRM name+value
}

-- Apply the mourning holds (or, dryRun=true, just LOG what it would do). Returns
-- the number of facts it changed/would-change. Skips rows already at target and
-- refuses any protected (body-choice) fact.
function jlMourningApply(dryRun)
  if JL.mode ~= "quietlife" then return 0 end
  local qs; pcall(function() qs = Game.GetQuestsSystem() end)
  if not qs then return 0 end
  local n = 0
  for _, e in ipairs(JL_MOURNING_FACTS) do
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

-- Short menu status line.
function jlMourningStatus()
  if JL.mode ~= "quietlife" then return "n/a — Blaze mode auto-suppresses grief" end
  if not JL.mourningSuppress then return "OFF" end
  local active = 0
  for _, e in ipairs(JL_MOURNING_FACTS) do if not JL_MOURNING_PROTECTED[e.name] then active = active + 1 end end
  return "ON — holding " .. tostring(active) .. " grief fact(s)"
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
  jlCruise.active, jlCruise.bikeId, jlCruise.bikeHandle, jlCruise.mountAt = false, nil, nil, nil
  pcall(promoteToCompanion)                          -- resume normal on-foot follow
  log("Cruise: ended -> Jackie back on foot.")
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
  if JL.summon.spawn then ammDespawn(JL.summon.spawn) end
  JL.summon.spawn, JL.summon.active, JL.summon.companionSet, JL.summon.walkIn = nil, false, false, false
  local spawn, err = ammSpawn(1)
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
  if not (s and (s.hideUntil or s.collideUntil)) then return end
  local now = JL.clock or 0
  local h = JL.summon.spawn and JL.summon.spawn.handle
  -- still hiding? keep him invisible + collision-off (re-assert each frame; handle may have just resolved).
  if s.hideUntil and now < s.hideUntil then
    if h then setVisible(h, false) end
  elseif s.hideUntil then
    if h then setVisible(h, true) end     -- window's up -> reveal him where he settled
    s.hideUntil = nil
  end
  if s.collideUntil and now < s.collideUntil then
    if h then setNpcCollision(h, false) end
  elseif s.collideUntil then
    if h then setNpcCollision(h, true) end  -- restore collision (a follower must always collide)
    s.collideUntil = nil
  end
end

-- Per-frame guard: keep the saved companion fact in sync with reality, and if the save says Jackie
-- should be with V but his body is gone (fresh load wiped Lua state, or a load-screen fast-travel
-- culled him), bring him back. Reuses JL.clock for all timing (no dt needed).
function companionPersistTick()
  local P = Config.persist or {}
  if P.enabled == false then return end
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
  local live = false
  if JL.summon.active and JL.summon.companionSet and JL.summon.spawn and JL.summon.spawn.handle then
    local jp; pcall(function() jp = JL.summon.spawn.handle:GetWorldPosition() end)
    live = (jp ~= nil)
  end

  if live then
    if not companionFlagSet() then setCompanionFlag(true) end   -- self-heal: he's here, record it
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
  pcall(function() local f = io.open("jackie_debug.log", "w"); if f then f:close() end end)  -- v0.76: fresh log each load
  pcall(function() math.randomseed((os.time and os.time() or 0)) end)  -- v0.36: random day-bag shuffle
  getAMM()
  setupInteractHook()   -- v0.15: native F (Interact) triggers Talk-to-Jackie, no binding
  pcall(setupCallHijack)   -- v0.30: player phone-calls to Jackie route into our flow
  pcall(jlLoadSettings)    -- v0.51: restore persisted Esc-menu toggles (husbando / disableVehicleArrivals)
  pcall(jlLoadSeats)       -- v1.1: restore tuned sit coords into Config so they survive a reload (old-S4 fix)
  pcall(function() Retrieval.bind{ log = log } end)   -- retrieval questline: inject the logger (more helpers bound in Phases 2-4)
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
      -- MVP-A objective/cutscene = native message band + caption. MVP-B swaps THESE TWO lines
      -- for real WolvenKit .journal calls / a real scene (docs/BLAZE_WOLVENKIT_OBJECTIVES.md).
      objective = function(text, dur) showOnscreenMsg(text, dur or 8.0) end,
      fade = function(caption) showOnscreenMsg(caption or "CUT TO BLACK", 8.0) end,
      -- ALTERNATE-TIMELINE WORLD UNLOCK (v-next MVP slice): the Watson prologue barrier reads the
      -- quest fact `watson_prolog_unlock` directly (proven in docs/research/q005_graph_findings.md —
      -- set by NO quest condition, only the prevention-area system). Vanilla sets it deep inside q101
      -- (Love Like Fire). Setting it here opens Watson WITHOUT entering q101 -> no Johnny, no biochip,
      -- no death. THIS SLICE = Watson only (test it in isolation first). The Act-2 content toggles are
      -- the NEXT slice, added here once Watson is confirmed in-game:
      --   apartment_on, victor_vector_default_on, misty_default_on, mq033_misty_dialogue_on,
      --   wat_lch_gunsmith_01_default_on, radio_on, tv_on, cyberspace_on  (all =1).
      worldUnlock = function()
        pcall(function()
          local qs = Game.GetQuestsSystem()
          if qs then
            qs:SetFactStr("watson_prolog_unlock", 1)
            qs:SetFactStr("watson_prolog_lock", 0)
          end
        end)
        log("[Blaze] world unlock -> watson_prolog_unlock=1, watson_prolog_lock=0 (Watson barrier lifted)")
      end,
      -- ⚠️ EXPERIMENTAL Yorinobu scenario helpers ----------------------------------
      -- Jackie speaks: play the clip if an sfx id is set (none yet), and show the text on-screen.
      say = function(text, sfx)
        if sfx and sfx ~= "" then pcall(function() playVoice(sfx) end) end
        if text and text ~= "" then showOnscreenMsg(text, 4.0) end
      end,
      -- The payoff: open Watson without q101 (world-unlock lever), SKIP the retrieval shard by marking
      -- Jackie already returned, teleport V to Vik's clinic, and spawn a living Jackie there beside her.
      -- (Full q005/interlude/q101 graph autocompletion is the OTHER workstream's job — this delivers the
      -- playable result now via the barrier lift + teleport; see docs/research/q005_graph_findings.md.)
      finale = function()
        pcall(function()
          local qs = Game.GetQuestsSystem()
          if qs then qs:SetFactStr("watson_prolog_unlock", 1); qs:SetFactStr("watson_prolog_lock", 0) end
        end)
        pcall(function() Retrieval.forceReunion() end)   -- Blaze: skip the Where's-Jackie shard, mark him returned
        local vik = (Retrieval.Config and Retrieval.Config.vikPos) or { -1546.551, 1229.270, 11.520 }
        pcall(function()
          local tf = Game.GetTeleportationFacility()
          if tf then tf:Teleport(Game.GetPlayer(), Vector4.new(vik[1], vik[2], vik[3], 1.0), EulerAngles.new(0.0, 0.0, 129.8)) end
        end)
        pcall(function() ammSpawn(0) end)   -- living Jackie appears at V (now standing in Vik's clinic)
        log("[Blaze] FINALE: Watson open, retrieval shard skipped, V + living Jackie at Vik's.")
      end,
      persist = function() blazeDumpConfig() end,   -- auto-write blaze_config.txt on every capture/grab
    }
  end)
  pcall(blazeLoadConfig)   -- v0.96: re-apply captured records/positions from blaze_config.txt (survives reloads)
  log("Loaded v" .. tostring(Config.version or "?") .. ". AMM present: " .. tostring(JL.amm ~= nil))
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

registerForEvent("onUpdate", function(dt)
  JL.clock = (JL.clock or 0) + dt
  pcall(function() Retrieval.tick(dt) end)   -- retrieval questline: gate + Vik tip + Badlands shard + call/arrival/reunion sequence
  if JL.mode == "blaze" then pcall(function() Blaze.tick(JL.clock, dt) end) end   -- v0.96: Heist set-piece state machine (self-guards when idle)
  pcall(nsTick)         -- v0.44: register the Esc-menu panel once nativeSettings has loaded (load-order safe)
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
  if JL.summon.spawn and JL.summon.spawn.handle and not JL.summon.companionSet and not JL.summon.walkIn then
    local amm = getAMM()
    pcall(function()
      if amm and amm.Spawn and amm.Spawn.SetNPCAsCompanion then
        amm.Spawn:SetNPCAsCompanion(JL.summon.spawn.handle)
      end
      local pl, h = Game.GetPlayer(), JL.summon.spawn.handle
      if pl and h and h.GetAttitudeAgent then
        h:GetAttitudeAgent():SetAttitudeTowards(pl:GetAttitudeAgent(), EAIAttitude.AIA_Friendly)
      end
    end)
    JL.summon.companionSet = true
    setCompanionFlag(true)   -- v0.72: persist "is companion" (this is the summon/respawn promote path)
    JL.ui.status = "Jackie is following."
    log("Companion role applied.")
  end

  -- v0.39: companion-duration clock. Arm it once he's a confirmed companion (any path), and when
  -- it runs out (and autoLeaveOnExpiry) send him home via the same walk-off as a dismissal.
  if JL.summon.active and JL.summon.companionSet and not JL.summon.companionExpiresGame then
    armCompanionTimer()
  end
  -- v0.41: the auto-leave is PAUSED for the whole dinner outing (JL.dinner.phase) so he never
  -- bails mid-walk; dinnerTick does a full clock reset when the meal finishes.
  if JL.summon.active and Config.companion and Config.companion.autoLeaveOnExpiry
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
  if JL.summon.active and JL.summon.companionSet and not JL.dinner.phase
     and JL.leaving.phase ~= "walking" and startLeaving and (isMainQuestActive() or jlInCutscene()) then
    log("Main quest / cutscene -> Jackie excuses himself and heads out.")
    pcall(function() startLeaving(Config.mainQuestExit) end)
  end
  pcall(jlCruiseTick)     -- v0.85: V on a BIKE -> Jackie trails on his Arch (gated before the foot ticks)
  pcall(followKeepCloseTick) -- v0.67: hold him a few m behind V (override AMM's long leash)
  pcall(abreastTick)      -- v0.84: OR (when enabled) hold him beside/ahead of V instead of trailing
  pcall(catchUpTick)      -- v0.66: settled companion fell behind (fast-travel/ran off) -> snap to V's side
  pcall(companionPersistTick)  -- v0.72: saved "is companion" but his body is gone (reload / culling FT) -> respawn at V
  pcall(settleTick)       -- v0.82: hide + no-collision for a beat after a respawn-at-V so he doesn't pop/clip in
  pcall(dinnerTick)       -- v0.41: dinner outing (walk to restaurant -> linger -> full reset)
  pcall(jackieDinnerOfferTick)  -- v0.48: Jackie proposes the outing himself after a random in-game gap

  pcall(wanderTick)       -- v0.35: idle Jackie free-roams between his location's waypoints
  pcall(idleLeavingTick)  -- v0.38: idle Jackie walking off to a venue exit before despawning
  pcall(function() proximityBarkTick(dt) end)  -- v0.42: greet on approach (6 m) + grunt on bump (1.2 m)

  JL.timer = JL.timer + dt
  if JL.timer >= Config.scheduleCheckInterval then
    JL.timer = 0
    pcall(scheduleTick)
  end

  -- v0.97: Quiet-Life mourning suppression. Re-assert the grief holds every ~5 s
  -- (cheap, and re-catches any fact the quest system flips back up). Gated so it
  -- never runs in Blaze mode or when the player left it off.
  if JL.mode == "quietlife" and JL.mourningSuppress then
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

-- Re-seat Jackie at the current working coords (stop pose -> teleport -> deferred sit).
local function tunerApply()
  if not tunerHere() then
    JL.ui.status = "Tuner: Force venue -> " .. JL.tuner.key .. ", go stand near him first."
    return false
  end
  local h = JL.idle.spawn.handle
  local x, y, z, yaw = tunerCoords()
  local v = Vector4.new(x, y, z, 1.0)
  local wp = tunerSeatWaypoint()                 -- carry this seat's anim override (e.g. Misty's deep chair)
  -- v0.45: he's currently SEATED (pinned by the workspot). Get him OUT first; the teleport+re-sit then
  -- run via the two-step deferred path in wanderTick (placeAtExact -> gap -> workspot). Teleporting THIS
  -- frame would be ignored (still pinned) — that was why the tuner did nothing. The 0.45s delay lets
  -- StopInDevice actually release him before placeAtExact moves him.
  stopWorkspotPose(h)
  JL.idle.pendingSit = nil   -- cancel any in-flight sit so this re-seat wins
  JL.idle.pendingPose = { pose = "sit", name = wp and wp.poseAnim, vec = v, yaw = yaw,
                          at = (JL.clock or 0) + 0.45 }
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
  if not JL.ui.overlayOpen then return end   -- the debug window only draws while the overlay is open
  if not JL.ui.open then return end
  ImGui.Begin("Jackie Lives")

  -- v0.95 STORY MODE selector (Quiet Life vs Blaze of Glory). Buttons + wrapped description, using
  -- only idioms already proven in this file (Button/Text/SameLine/TextWrapped/TextColored).
  ImGui.Text("Story mode:  ")
  ImGui.SameLine()
  ImGui.TextColored(1.0, 0.6, 0.2, 1.0, JL.mode == "blaze" and "BLAZE OF GLORY" or "QUIET LIFE")
  if ImGui.Button("Use Quiet Life") then jlSetMode("quietlife") end
  ImGui.SameLine()
  if ImGui.Button("Use Blaze of Glory") then jlSetMode("blaze") end
  if JL.mode == "blaze" then
    ImGui.TextColored(1.0, 0.6, 0.2, 1.0, "Blaze of Glory  (WORK IN PROGRESS)")
    ImGui.TextWrapped("You and Jackie fight out of the Heist -- kill Smasher & Takemura, escape by " ..
      "helicopter, sell the Relic, and retire as legends. DISABLES the main plot (no Relic, no Johnny, " ..
      "no dying). Most invasive. Choose this BEFORE the Heist -- it can't be undone mid-save.")

    -- v0.96 MVP-A: Heist set-piece test controls (spawn Smasher+Goro+VTOL, run the
    -- kill-Smasher -> reach-VTOL -> cut-to-black flow). Positions/records are captured
    -- in-game; paste the console-logged values into blaze.lua M.cfg to make them stick.
    ImGui.Separator()
    ImGui.Text("Heist set-piece (MVP-A):")
    ImGui.TextWrapped(Blaze.status())
    ImGui.TextWrapped("1. RECORDS -- spawn Smasher/Takemura (and an AV) via AMM's menu, then grab:")
    if ImGui.Button("Grab Smasher record") then local r = discoverBlazeRecord("smasher");  if r then Blaze.setRecord("smasher", r) end end
    ImGui.SameLine()
    if ImGui.Button("Grab Takemura record") then local r = discoverBlazeRecord("takemura"); if r then Blaze.setRecord("goro", r) end end
    ImGui.TextWrapped("Heli is a VEHICLE (not in AMM's NPC list) -- aim your crosshair AT the floating heli, then:")
    if ImGui.Button("Grab heli record (look at it)") then local r = discoverBlazeRecordFromTarget(); if r then Blaze.setRecord("heli", r) end end
    ImGui.TextWrapped("2. POSITIONS -- stand on each spot (FACE the right way) & capture:")
    if ImGui.Button("Capture Goro / elevator spot")  then Blaze.setPos("goro",    blazeCapture()) end
    if ImGui.Button("Capture Smasher / balcony spot") then Blaze.setPos("smasher", blazeCapture()) end
    if ImGui.Button("Capture Heli / hover spot")      then Blaze.setPos("heli",    blazeCapture()) end
    ImGui.TextWrapped("3. RUN:")
    if ImGui.Button("Start set-piece") then Blaze.start() end
    ImGui.SameLine()
    if ImGui.Button("Reset set-piece") then Blaze.reset(); JL.ui.status = "Blaze set-piece reset." end
    ImGui.TextWrapped("TEST: fire the world-unlock directly (same as the set-piece's ending) -- lifts the " ..
      "Watson barrier via watson_prolog_unlock. Use on a THROWAWAY save.")
    if ImGui.Button("TEST: World unlock now (Watson barrier)") then
      local ok = Blaze.testWorldUnlock()
      JL.ui.status = ok and "Fired world unlock (watson_prolog_unlock=1, watson_prolog_lock=0)." or "World unlock helper not bound."
    end
    ImGui.TextWrapped("Records + positions AUTO-SAVE to blaze_config.txt (in the mod folder) and reload " ..
      "on launch -- no console copying, no re-capturing. Grab a Smasher record via AMM's menu FIRST, though.")
    if ImGui.Button("Re-write blaze_config.txt now") then blazeDumpConfig(); JL.ui.status = "Wrote blaze_config.txt in the mod folder." end

    -- v0.97 EXPERIMENTAL: one-button Yorinobu-apartment fight (hardcoded, WIP, not further developed).
    ImGui.Separator()
    ImGui.TextColored(1.0, 0.35, 0.2, 1.0, "EXPERIMENTAL — Yorinobu apartment fight")
    ImGui.TextWrapped("WIP / not further developed. Flips to Blaze mode and runs a scripted encounter at " ..
      "Yorinobu's apartment (HARDCODED coords): Takemura appears -> defeat him (lethal or not) -> Smasher " ..
      "appears -> defeat him -> escape heli appears -> reach it (5 m) -> fade -> world opens & you wake at " ..
      "Vik's with a LIVING Jackie (the retrieval shard is skipped). Jackie barks along the way. Stand IN the " ..
      "apartment before starting; grab the heli record (look-at, above) first if you want the heli to appear. " ..
      "Use a THROWAWAY save.")
    if ImGui.Button("EXPERIMENTAL: Start Yorinobu fight") then jlSetMode("blaze"); Blaze.startYorinobu(); JL.ui.status = "Blaze: Yorinobu fight started (experimental)." end
  else
    ImGui.TextWrapped("Quiet Life: the main story plays out as normal, but Jackie secretly survived and " ..
      "returns as a living Heywood NPC. Less invasive -- but Jackie can only join SIDE jobs, never the " ..
      "main plot.")

    -- v0.97 mourning suppression (WIP: fact list still being confirmed from WolvenKit).
    ImGui.Separator()
    ImGui.Text("Mourning content:")
    ImGui.SameLine()
    ImGui.TextColored(0.6, 0.8, 1.0, 1.0, jlMourningStatus())
    ImGui.TextWrapped("Suppress the 'Jackie is dead' grief (the ofrenda / condolence calls) so they don't " ..
      "contradict a living Jackie. WORK IN PROGRESS -- the fact list isn't fully confirmed yet, so PREVIEW " ..
      "first (logs to jackie_debug.log without changing anything) and test on a throwaway save.")
    local newVal = ImGui.Checkbox("Suppress mourning content", JL.mourningSuppress)  -- CET: 1st return = new value
    if newVal ~= JL.mourningSuppress then JL.mourningSuppress = newVal; jlSaveSettings(); JL.mourningTimer = 999 end  -- fire next tick
    if ImGui.Button("Preview (log only, no changes)") then
      local n = jlMourningApply(true)
      JL.ui.status = "Mourning preview: " .. tostring(n) .. " fact(s) would change -- see jackie_debug.log."
    end
    ImGui.SameLine()
    if ImGui.Button("Apply once now") then
      local n = jlMourningApply(false)
      JL.ui.status = "Mourning: applied " .. tostring(n) .. " grief hold(s)."
    end
  end
  ImGui.Separator()

  -- Reunion-quest status, always shown at the very top of the window.
  ImGui.Text("Reunion quest: ")
  ImGui.SameLine()
  ImGui.TextColored(0.45, 0.85, 1.0, 1.0, Retrieval.stageName())
  ImGui.Separator()

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

  ImGui.Separator()

  -- v0.7: LIVE companion-spacing tunables. These edit Config.follow / Config.catchUp in place, and the
  -- follow/catch-up ticks read them every frame, so dragging a slider changes his behaviour instantly —
  -- no redeploy. (Live-only: they reset to the config.lua defaults on reload; once a value feels right,
  -- tell Claude and we bake it into config.lua.) Follow gap = how far he trails V; catch-up trigger =
  -- how far he can drift before he teleports back; catch-up drop = how far to V's side he lands.
  if Config.follow and Config.catchUp then
    ImGui.Text("Companion spacing (live tuning):")
    Config.follow.distance       = ImGui.SliderFloat("Follow gap (m behind V)",      Config.follow.distance or 2.5,       1.0, 8.0)
    Config.catchUp.distance      = ImGui.SliderFloat("Catch-up trigger (m from V)",  Config.catchUp.distance or 25.0,     8.0, 60.0)
    Config.catchUp.placeDistance = ImGui.SliderFloat("Catch-up drop (m beside V)",   Config.catchUp.placeDistance or 3.0, 1.5, 8.0)
    ImGui.Separator()
  end

  -- v0.85b: WALK-ABREAST live tuner (now ON by default for a companion). He walks beside V when she WALKS,
  -- trails when she jogs/sprints, and takes whichever near-front side (right/left) is closest to him. The
  -- two Position sliders are the right/left anchors (fractional dial steps); Radius = how far out; Smoothing
  -- = heading lag. Live-only (resets to config.lua defaults on reload) — tell Claude any value to bake in.
  if Config.abreast then
    local A = Config.abreast
    if ImGui.Button("Walk abreast: " .. (A.enabled and "ON (beside V when walking)" or "OFF (always trails)")) then
      A.enabled = not A.enabled
      JL.abreast.lastAt, JL.abreast.side = nil, nil   -- re-issue + re-pick side immediately on toggle
      log("Walk-abreast -> " .. (A.enabled and "ON" or "OFF"))
    end
    if A.enabled then
      A.angleRight = ImGui.SliderFloat("Right position (near-front)", A.angleRight or 0.85, 0.0, 3.0)
      A.angleLeft  = ImGui.SliderFloat("Left position (near-front)",  A.angleLeft or 11.25, 9.0, (A.positions or 12))
      A.radius     = ImGui.SliderFloat("Abreast radius (m from V)",   A.radius or 3.5, 1.0, 6.0)
      A.smoothSeconds = ImGui.SliderFloat("Heading smoothing (s)",    A.smoothSeconds or 3.3, 0.2, 6.0)
      -- v0.93: report the real state — WALKING (abreast) vs the trail, split into STILL vs jog/sprint, plus
      -- live speed and how long the walk band has held (so the walkSustainSeconds gate is visible).
      local walk = jlVWalking()
      local held = JL.abreast.walkSince and ((JL.clock or 0) - JL.abreast.walkSince) or 0
      local state = walk and "WALKING (abreast)"
                    or (JL.abreast.inBand and ("walk band, holding %.1fs..."):format(held) or "STILL/jog (trailing)")
      ImGui.Text(("Live: V %s | %.2f m/s | side=%s"):format(state, JL.abreast.vSpeed or 0.0,
        tostring(JL.abreast.side or "-")))
    end
    ImGui.Separator()
  end

  if ImGui.Button("Summon Jackie (companion)") then summonJackie() end
  ImGui.SameLine()
  if ImGui.Button("Dismiss Jackie") then dismissJackie() end

  -- v0.50: TWO arrival modes only — toggle FOOT <-> BIKE, live. Pick one, then Call Jackie (or hit
  -- "Test arrival now"). Both spawn via DES out at distance and share the sprint -> walk -> companion tail.
  local cc = Config.call
  ImGui.Separator()
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

  ImGui.Separator()
  -- Retrieval questline gate: stage readout + debug jumps (the "Where's Jackie?" quest).
  if ImGui.CollapsingHeader("Retrieval quest (Where's Jackie?)") then
    ImGui.Text("Stage: " .. Retrieval.stageName())
    -- v0.94: one-click "done" — jumps straight to REUNITED (Jackie back, calls/summon/schedule live).
    if ImGui.Button("Complete quest now (Jackie is back)") then Retrieval.completeReunion() end
    if ImGui.Button("Force tip (skip Vik)") then Retrieval.forceTip() end
    ImGui.SameLine(); if ImGui.Button("Force shard read") then Retrieval.forceShard() end
    if ImGui.Button("Probe quest gate (console)") then Retrieval.debugQuestState() end
    ImGui.SameLine(); if ImGui.Button("Reset to LOCKED") then Retrieval.reset() end
    ImGui.TextWrapped("v0.85 flow: Vik's clinic -> tip + Badlands pin -> Rocky Ridge shard -> AWAITING " ..
      "(CALL Jackie, he always answers) -> long reunion call -> he walks in -> short first-meeting -> UNLOCK.")

    ImGui.Separator()
    ImGui.Text("v0.85 reunion flow test:")
    if ImGui.Button("Force AWAITING (then call Jackie)") then Retrieval.forceAwaiting() end
    ImGui.SameLine(); if ImGui.Button("Call Jackie now") then startCall() end
    ImGui.TextWrapped("  In AWAITING, press 'Call Jackie now' (or use the phone) -> the reunion call plays; " ..
      "its end walks him in on foot -> the first-meeting dialogue -> mod unlocks.")
    if ImGui.Button("Force REUNITED (skip, unlock)") then Retrieval.forceReunion() end

    ImGui.Separator()
    ImGui.Text("v0.85 bike CRUISE (companion + V on a bike -> Jackie trails on his Arch):")
    ImGui.Text("  enabled: " .. tostring((Config.cruise or {}).enabled) .. "   active: " .. tostring(jlCruise and jlCruise.active))
    if ImGui.Button((Config.cruise and Config.cruise.enabled == false) and "Cruise: OFF (enable)" or "Cruise: ON (disable)") then
      Config.cruise = Config.cruise or {}
      Config.cruise.enabled = (Config.cruise.enabled == false)
      if not Config.cruise.enabled and jlCruise and jlCruise.active then jlCruiseStop() end
    end
    ImGui.SameLine()
    if ImGui.Button("Force start cruise") then jlCruiseStart() end
    ImGui.SameLine()
    if ImGui.Button("Force stop") then jlCruiseStop() end
    ImGui.TextWrapped("  Be his companion, then get on a BIKE -> his Arch spawns + he trails you (AI follow). " ..
      "In a CAR, AMM seats him as passenger. Set Config.cruise.enabled=false to disable entirely.")

    ImGui.Separator()
    ImGui.Text("v0.84 reunion beats:")
    ImGui.Text("  Bike returned: " .. tostring(jlBikeReturned and jlBikeReturned() or "?"))
    if ImGui.Button("Give bike back now") then jlReturnJackiesBike() end
    ImGui.SameLine(); if ImGui.Button("Restore bike (undo)") then jlRestoreJackiesBike() end
    ImGui.TextWrapped("  (Or just call Jackie for the FIRST time after he's back — he asks for his Arch; " ..
      "agreeing removes it from your garage.)")
    if ImGui.Button("Show Misty + Mama shards") then Retrieval.debugPostShards() end
    ImGui.SameLine(); if ImGui.Button("Reset post-shard flags") then Retrieval.resetPostShards() end
  end


  ImGui.Separator()
  if ImGui.Button("Capture current position") then capturePosition() end
  if JL.ui.lastCapture then
    ImGui.Text("Last capture (also in console — copy into config.lua):")
    ImGui.TextWrapped(JL.ui.lastCapture)
  end

  -- Mouth-flap live tuner: how fast the talking faces shuffle while Jackie speaks (default 0.82).
  ImGui.Separator()
  flap.interval = ImGui.SliderFloat("Mouth-flap shuffle interval (s)", flap.interval or 0.82, 0.4, 1.5)

  -- Consolidated "spots" tuning — idle collision, force-venue and the seat tuner, all in one place.
  ImGui.Separator()
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
    if not JL.tuner.init then tunerInit() end
    local t = JL.tuner

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
      and ("Jackie is here — slide and he re-seats live. (Editing " .. t.key .. " seat " .. t.seatIdx .. ".)")
      or  ("Jackie NOT at " .. t.key .. " yet — he's heading there (Force venue set). Walk over once he arrives."))
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

    t.live = ImGui.Checkbox("Live: re-seat him as I slide", t.live)
    -- debounced live apply: only fire ~0.25 s after the last slider movement (avoids per-frame re-sit)
    if t.live and here then
      local moved = math.abs(t.dx - t.prevX) > 1e-4 or math.abs(t.dy - t.prevY) > 1e-4
                 or math.abs(t.dz - t.prevZ) > 1e-4 or math.abs(t.dyaw - t.prevYaw) > 1e-4
      if moved then t.pendingApplyAt = (JL.clock or 0) + 0.25 end
    end
    t.prevX, t.prevY, t.prevZ, t.prevYaw = t.dx, t.dy, t.dz, t.dyaw
    if t.pendingApplyAt and (JL.clock or 0) >= t.pendingApplyAt then
      t.pendingApplyAt = nil; tunerApply()
    end

    if ImGui.Button("Move Jackie here (re-sit)") then tunerApply() end
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
  pcall(clearIdle)
  pcall(clearVehicleArrival)     -- v0.34: never orphan the arrival bike
  pcall(bikeTestDespawn)         -- v0.63: never orphan the bike-model test spawn
  pcall(clearDinnerWaypoint)     -- v0.41: never leave a dinner map pin stuck
  pcall(function() if jlCruise and jlCruise.active then jlCruiseStop() end end)  -- v0.92: never orphan the cruise Arch
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
