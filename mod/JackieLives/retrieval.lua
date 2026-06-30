--[[
  retrieval.lua — "Where's Jackie?" RETRIEVAL QUESTLINE + mod gate  (v0.1, MVP)
  ============================================================================
  Self-contained module. init.lua couples to it in only a few one-line spots
  (see PATCH LIST at the bottom of this file). Nothing here depends on init.lua
  internals except an OPTIONAL injected logger + an OPTIONAL reunion spawner,
  both passed via M.bind{} — so this file can't break the rest of the mod.

  WHAT IT DOES
    A 3-state quest that GATES the whole Jackie experience until V learns he's
    alive and goes to find him in the Badlands:

      0 hidden  (default) — Jackie is "dead": schedule OFF (he never appears),
                            calling him = number disconnected. THE GATE.
        │  V gets the tip at Vik's  (proximity to the clinic, OR debug button)
      1 rumor             — Vik's "shard" line shows + a map pin drops on the
                            Badlands hideout. Still gated (can't call / no schedule).
        │  V reaches the pin
      2 found             — at the spot: the info-shard text is read + (optional)
                            Jackie is spawned for the reunion → flag set → MOD UNLOCKS.

    Splitting "pick up shard" and "find Jackie" into two separate pins later is
    trivial: add a stage 1.5 between rumor and found (see NOTE in tick()).

  PERSISTENCE
    State lives in a PER-SAVE game fact ("jackielives_stage") via QuestsSystem,
    so it travels inside each save and does NOT leak across saves. If that API
    ever misbehaves in-game, flip USE_GAME_FACT=false to fall back to an
    in-session-only value (resets on game restart) — or wire init.lua's
    jl_settings.txt store instead (note: that store is GLOBAL across all saves).

  WolvenKit: NOT required. The "shard" is delivered as on-screen text, not a
  real Shards/Codex menu entry (that would need TweakXL + localization).
--]]

local M = {}

-- ---------------------------------------------------------------------------
-- TUNABLES — capture coords in-game with the CET window's "Capture position"
-- button, then paste them here. Vik coords are OPTIONAL (the debug button can
-- advance the quest without them); the Badlands spot is REQUIRED for arrival.
-- ---------------------------------------------------------------------------
M.Config = {
  -- Vik's clinic (Misty's Esoterica / ripperdoc, Watson). Leave nil to disable
  -- the proximity tip and use only the debug "Receive Vik's tip" button.
  vikPos      = nil,                       -- e.g. { -1300.0, 1234.0, 12.3 }
  vikRadius   = 8.0,                        -- metres; how close V must get to Vik

  -- The Badlands hideout where Jackie is lying low + the shard is waiting.
  hideoutPos  = nil,                        -- REQUIRED: { x, y, z }  (capture in-game)
  hideoutYaw  = 0.0,                        -- facing for the reunion spawn
  hideoutRadius = 12.0,                     -- metres; trigger radius (generous outdoors)

  -- Vik's tip (shown when V gets near him / hits the debug button).
  tipText     = "Vik: Oh — you didn't hear? Jackie made it out. He's layin' low "
              .. "out in the Badlands. Sendin' you what I got.",
  tipDuration = 9.0,

  -- The info-shard's contents, read on reaching the hideout (joined into one
  -- on-screen block for MVP; can be split into timed subtitle beats later).
  shardLines  = {
    "[SHARD — from Jackie]",
    "If you're readin' this, mano, then you found me. Yeah. I made it.",
    "Vik patched me up, smuggled me outta the city before Arasaka came lookin'.",
    "I'm done with the merc life, V. Mama Welles'd kill me herself if I wasn't.",
    "Come find me. We got a lotta catchin' up to do.",
  },
  shardDuration = 13.0,

  spawnReunion = true,   -- if a spawner is bound, place Jackie at the hideout on arrival
}

-- ---------------------------------------------------------------------------
-- Injected dependencies (all optional) + module state
-- ---------------------------------------------------------------------------
local USE_GAME_FACT = true
local FACT_NAME     = "jackielives_stage"

local deps  = { log = nil, spawnAt = nil }    -- bound from init.lua via M.bind{}
local state = { fallbackStage = 0, mappinId = nil, lastStage = -1, vikFired = false }

local function log(msg)
  if deps.log then pcall(deps.log, "[Retrieval] " .. tostring(msg)) end
end

-- ---------------------------------------------------------------------------
-- Small self-contained primitives (no init.lua locals needed)
-- ---------------------------------------------------------------------------
local function playerPos()
  local p = Game.GetPlayer(); if not p then return nil end
  local ok, v = pcall(function() return p:GetWorldPosition() end)
  return ok and v or nil
end

-- horizontal (XY) distance — forgiving for a large outdoor trigger; ignores
-- small Z differences between V's feet and a captured ground point.
local function dist2(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return math.sqrt(dx * dx + dy * dy)
end

local function nearPoint(pt, radius)
  if not pt then return false end
  local pp = playerPos(); if not pp then return false end
  return dist2(pp.x, pp.y, pt[1], pt[2]) <= (radius or 8.0)
end

-- the game's native on-screen message band (same path init.lua uses).
local function onscreen(text, duration)
  pcall(function()
    local defs = GetAllBlackboardDefs()
    local bb = Game.GetBlackboardSystem():Get(defs.UI_Notifications)
    if not bb then return end
    local msg = SimpleScreenMessage.new()
    msg.isShown  = true
    msg.duration = duration or 6.0
    msg.message  = text
    bb:SetVariant(defs.UI_Notifications.OnscreenMessage, ToVariant(msg), true)
  end)
end

-- ---------------------------------------------------------------------------
-- State get/set (per-save game fact, with an in-session fallback)
-- ---------------------------------------------------------------------------
local function getStage()
  if USE_GAME_FACT then
    local v
    local ok = pcall(function() v = Game.GetQuestsSystem():GetFactStr(FACT_NAME) end)
    if ok and type(v) == "number" then return v end
  end
  return state.fallbackStage or 0
end

local function setStage(n)
  state.fallbackStage = n
  if USE_GAME_FACT then
    pcall(function() Game.GetQuestsSystem():SetFactStr(FACT_NAME, n) end)
  end
  log("stage -> " .. tostring(n))
end

-- ---------------------------------------------------------------------------
-- Map pin on the Badlands hideout (same mappin path as the dinner waypoint)
-- ---------------------------------------------------------------------------
local function placePin()
  if state.mappinId or not M.Config.hideoutPos then return end
  pcall(function()
    local h = M.Config.hideoutPos
    local pos  = ToVector4{ x = h[1], y = h[2], z = h[3], w = 1.0 }
    local data = NewObject("gamemappinsMappinData")
    data.mappinType = TweakDBID.new("Mappins.DefaultStaticMappin")
    data.variant    = gamedataMappinVariant.CustomPositionVariant  -- proven in init.lua;
                                                                   -- swap to QuestVariant for a quest look
    state.mappinId  = Game.GetMappinSystem():RegisterMappin(data, pos)
  end)
  log("Badlands pin set (id=" .. tostring(state.mappinId) .. ")")
end

local function clearPin()
  if not state.mappinId then return end
  pcall(function() Game.GetMappinSystem():UnregisterMappin(state.mappinId) end)
  state.mappinId = nil
end

-- ---------------------------------------------------------------------------
-- Quest transitions
-- ---------------------------------------------------------------------------
-- hidden -> rumor : V learned Jackie's alive (proximity to Vik OR debug button).
function M.giveTip()
  if getStage() >= 1 then return false end
  onscreen(M.Config.tipText, M.Config.tipDuration)
  setStage(1)
  return true
end

-- rumor -> found : V reached the hideout; read the shard + optional reunion spawn.
local function reachHideout()
  if getStage() ~= 1 then return end
  onscreen(table.concat(M.Config.shardLines, "\n"), M.Config.shardDuration)
  log("Shard read at hideout.")
  if M.Config.spawnReunion and deps.spawnAt and M.Config.hideoutPos then
    pcall(deps.spawnAt, M.Config.hideoutPos, M.Config.hideoutYaw)   -- optional: see PATCH LIST #2
  end
  clearPin()
  setStage(2)
end

-- ---------------------------------------------------------------------------
-- Public API used by init.lua
-- ---------------------------------------------------------------------------
-- THE GATE. Everything else in the mod asks this before letting Jackie appear.
function M.isUnlocked() return getStage() >= 2 end

function M.getStage()  return getStage() end
function M.stageName()
  local s = getStage()
  return (s >= 2 and "found (unlocked)") or (s == 1 and "rumor (pin placed)") or "hidden (gated)"
end

-- A friendly line for the call/summon gates when he's still "dead".
function M.unavailableMsg() return "Number disconnected." end

-- Inject init.lua helpers. spawnAt(pos, yaw) is OPTIONAL — without it the
-- reunion is text-only (still completes the quest).
function M.bind(opts)
  opts = opts or {}
  deps.log     = opts.log     or deps.log
  deps.spawnAt = opts.spawnAt or deps.spawnAt
end

-- Debug helper for the CET window.
function M.reset()
  clearPin(); state.vikFired = false; setStage(0)
  log("reset to hidden.")
end

-- Per-frame driver (call from init.lua's onUpdate). Cheap + fully guarded.
function M.tick()
  local s = getStage()

  -- one-shot side effects on a state change (also re-establishes the pin after a reload)
  if s ~= state.lastStage then
    if s == 1 then placePin() else clearPin() end
    state.lastStage = s
  end

  if s == 0 then
    -- learn he's alive by getting near Vik (debug button is the other route)
    if M.Config.vikPos and not state.vikFired and nearPoint(M.Config.vikPos, M.Config.vikRadius) then
      state.vikFired = true
      M.giveTip()
    end
  elseif s == 1 then
    if not state.mappinId then placePin() end
    -- NOTE: to split shard-pickup from finding Jackie, add a stage 1.5 here:
    -- reach shard pin -> show shard text + move pin to Jackie -> on reaching THAT, spawn + found.
    if nearPoint(M.Config.hideoutPos, M.Config.hideoutRadius) then reachHideout() end
  end
end

return M

--[[
  ============================================================================
  PATCH LIST — apply these ~6 one-line touches to init.lua once it's free.
  (Nothing here is destructive; each is an insert or a tiny guard.)
  ============================================================================

  1) REQUIRE the module (next to `local Config = require("config")`, ~line 51):
       local Retrieval = require("retrieval")

  2) BIND helpers in onInit (~line 3801, near `pcall(jlLoadSettings)`).
     `log` is the init.lua logger. spawnAt is OPTIONAL — pass a small spawner
     only if you want Jackie physically waiting at the hideout (reuses ammSpawn):
       pcall(function()
         Retrieval.bind{
           log = log,
           spawnAt = function(pos, yaw)
             -- minimal reunion spawn; promote/idle handling can be added later
             local sp = ammSpawn(0)            -- passive idle Jackie
             -- (optionally teleport sp.handle to pos/yaw here once spawned)
           end,
         }
       end)

  3) GATE the schedule (scheduleTick, ~line 3501, right after the `leaving` check):
       if not Retrieval.isUnlocked() then clearIdle(); return end

  4) GATE calling him — add at the TOP of each of:
        summonJackie()            (~line 364)
        startCall()               (~line 1889)
        onPlayerCalledJackie()    (~line 1978)
     the guard:
       if not Retrieval.isUnlocked() then
         showOnscreenMsg(Retrieval.unavailableMsg(), 2.5)   -- (skip showOnscreenMsg in onPlayerCalledJackie:
         return                                              --  just `return` so the game's own call plays out)
       end

  5) DRIVE the quest — in onUpdate where `pcall(scheduleTick)` runs (~line 4000):
       pcall(Retrieval.tick)

  6) (OPTIONAL) CET debug UI — add a collapsing header in onDraw:
       ImGui.Text("Retrieval: " .. Retrieval.stageName())
       if ImGui.Button("Receive Vik's tip") then Retrieval.giveTip() end
       if ImGui.Button("Reset quest")       then Retrieval.reset()   end

  AFTER PATCHING: capture the Badlands spot in-game ("Capture position" button)
  and paste it into M.Config.hideoutPos above (and optionally vikPos for Vik's clinic).
--]]
