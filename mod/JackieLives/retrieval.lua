--[[
  retrieval.lua — "Where's Jackie?" RETRIEVAL QUESTLINE + mod gate  (v0.2)
  ============================================================================
  Self-contained module. init.lua couples to it in only a few one-line spots
  (see PATCH LIST at the bottom). Nothing here depends on init.lua internals
  except OPTIONAL injected helpers (logger, tip popup, call/arrival/reunion
  starters), all passed via M.bind{} — so this file can't break the rest of
  the mod, and any unbound step gracefully no-ops (the quest still completes).

  THE QUEST (per-save game fact "jackielives_stage"):

    0 LOCKED  (default) — Jackie is "dead": schedule OFF, calls disconnected.   <- THE GATE
       │  precondition met (q101 "Playing for Time" done) AND V returns to Vik (4 m)
    1 TIP               — "Oh, didn't you hear?" popup + map pin on the Badlands hideout.
       │  V reaches the hideout (Rocky Ridge garage, 4 m)
    2 SHARD             — info-shard read; 1 s later Jackie RINGS V (one-time mute call:
       │                  "I made it / laid low / safe now / let's meet / wait there").
       │  call ends -> safe walk-in arrival at the garage
   (3 INCOMING)         — runtime-only sequence stage (not persisted; restarts on reload).
       │  Jackie arrives -> first-sight reunion dialogue (V lies about the Relic).
    4 REUNITED          — full mod UNLOCKED: schedule on, calls + summon work. Permanent.

  Stages 0/1/2/4 persist in the save; the call->arrival->reunion sequence runs
  while the fact == 2 and is driven by in-memory `seq` (so a save/reload mid-
  sequence just replays it cleanly rather than getting stuck half-done).

  WolvenKit: NOT required. The shard is on-screen text, not a real Codex entry.
--]]

local M = {}

-- ---------------------------------------------------------------------------
-- TUNABLES
-- ---------------------------------------------------------------------------
M.Config = {
  -- Vik's ripperdoc clinic (Misty's Esoterica, Watson). Captured in-game.
  vikPos      = { -1546.551, 1229.270, 11.520 },   -- yaw 129.8
  vikRadius   = 4.0,                                 -- "can't be missed" trigger zone

  -- Rocky Ridge — abandoned-town garage in the Badlands, no hostiles. Captured in-game.
  hideoutPos  = { 2575.852, 0.291, 80.871 },
  hideoutYaw  = 129.8,
  hideoutRadius = 4.0,

  -- PRECONDITION GATE: don't offer the tip until V is canonically post-heist
  -- (Jackie dead + Vik patched V up + V left the clinic). That whole arc == the
  -- main quest "Playing for Time" (q101) being COMPLETE.
  --   mode = "off"    -> no precondition; tip fires on Vik proximity alone (TESTING).
  --   mode = "quest"  -> require the journal quest below to be Succeeded.
  -- Ships "off" so the chain is testable at Vik's without driving the prologue.
  -- Use M.debugQuestState() in-game to confirm the path, then flip to "quest".
  gate = {
    mode       = "off",
    questPaths = {            -- tried in order; first that resolves is used
      "playing_for_time", "q101_playing_for_time",
      "main_quests/prologue/q101_playing_for_time",
    },
    succeededOnly = true,     -- true = require Succeeded; false = Active-or-later also ok
  },

  -- Vik's tip line (delivered via the tutorial popup if bound, else on-screen msg).
  tipTitle    = "A message from Vik",
  tipText     = "Oh — you didn't hear? Jackie made it out. Vik patched him up and got "
              .. "him clear of the city before Arasaka came lookin'. He's layin' low out "
              .. "in the Badlands. Sendin' you the coordinates — go find him.",
  tipDuration = 10.0,

  -- The info-shard contents, read on reaching the hideout (one on-screen block for MVP).
  shardTitle  = "[ SHARD — Jackie Welles ]",
  shardLines  = {
    "If you're readin' this, mano, then you found me. Yeah. I made it.",
    "Vik patched me up and smuggled me out before 'Saka came knockin'.",
    "I'm done with the merc life, V — Mama Welles'd kill me herself if I wasn't.",
    "Sit tight. I'm comin' out to see you.",
  },
  shardDuration = 12.0,

  callDelay   = 1.0,          -- seconds after the shard is read before Jackie rings V
}

-- ---------------------------------------------------------------------------
-- Stage constants + module state
-- ---------------------------------------------------------------------------
local LOCKED, TIP, SHARD, REUNITED = 0, 1, 2, 4   -- persisted; 3=INCOMING is runtime-only
local USE_GAME_FACT = true
local FACT_NAME     = "jackielives_stage"

local deps  = {}              -- bound from init.lua: log, showTip, startCall, startArrival, startReunion, spawnAt
local state = { fallbackStage = 0, mappinId = nil, lastStage = -1, vikFired = false,
                clock = 0, callAt = nil, seq = nil }   -- seq: nil|"call"|"arrive"|"reunion"

local function log(msg) if deps.log then pcall(deps.log, "[Retrieval] " .. tostring(msg)) end end

-- ---------------------------------------------------------------------------
-- Self-contained primitives (no init.lua locals needed)
-- ---------------------------------------------------------------------------
local function playerPos()
  local p = Game.GetPlayer(); if not p then return nil end
  local ok, v = pcall(function() return p:GetWorldPosition() end)
  return ok and v or nil
end

local function dist2(ax, ay, bx, by)   -- horizontal distance (forgiving outdoors)
  local dx, dy = ax - bx, ay - by
  return math.sqrt(dx * dx + dy * dy)
end

local function nearPoint(pt, radius)
  if not pt then return false end
  local pp = playerPos(); if not pp then return false end
  return dist2(pp.x, pp.y, pt[1], pt[2]) <= (radius or 4.0)
end

local function onscreen(text, duration)   -- native on-screen msg band (init.lua's path)
  pcall(function()
    local defs = GetAllBlackboardDefs()
    local bb = Game.GetBlackboardSystem():Get(defs.UI_Notifications)
    if not bb then return end
    local msg = SimpleScreenMessage.new()
    msg.isShown, msg.duration, msg.message = true, duration or 6.0, text
    bb:SetVariant(defs.UI_Notifications.OnscreenMessage, ToVariant(msg), true)
  end)
end

-- Show the tip via the bound tutorial popup if available, else the on-screen band.
local function showTip(title, text, duration)
  if deps.showTip and pcall(deps.showTip, title, text) then return end
  onscreen(text, duration)
end

-- ---------------------------------------------------------------------------
-- State (per-save game fact, with an in-session fallback)
-- ---------------------------------------------------------------------------
local function getStage()
  if USE_GAME_FACT then
    local v; local ok = pcall(function() v = Game.GetQuestsSystem():GetFactStr(FACT_NAME) end)
    if ok and type(v) == "number" then return v end
  end
  return state.fallbackStage or 0
end

local function setStage(n)
  state.fallbackStage = n
  if USE_GAME_FACT then pcall(function() Game.GetQuestsSystem():SetFactStr(FACT_NAME, n) end) end
  log("stage -> " .. tostring(n))
end

-- ---------------------------------------------------------------------------
-- Precondition: is V canonically post-heist (q101 done)?
-- ---------------------------------------------------------------------------
-- Best-effort journal lookup; fully guarded. Returns state string or nil.
local function questState(path)
  local result
  pcall(function()
    local jm = Game.GetJournalManager(); if not jm then return end
    local entry
    pcall(function() entry = jm:GetEntryByString(path) end)               -- common signature
    if not entry then pcall(function() entry = jm:GetEntryByString(path, "gameJournalQuest") end) end
    if not entry then return end
    local st; pcall(function() st = jm:GetEntryState(entry) end)
    if st ~= nil then result = tostring(st) end
  end)
  return result
end

local function preconditionMet()
  local g = M.Config.gate or {}
  if (g.mode or "off") ~= "quest" then return true end                    -- gate off -> always ok
  for _, p in ipairs(g.questPaths or {}) do
    local st = questState(p)
    if st then
      if st:find("Succeeded") then return true end
      if not g.succeededOnly and (st:find("Active") or st:find("Succeeded")) then return true end
      return false   -- the quest resolved but isn't done yet -> gate holds
    end
  end
  return false       -- couldn't resolve any path -> gate holds (use debug to fix the path)
end

-- Print candidate quest states so we can lock the gate path in-game.
function M.debugQuestState()
  log("---- quest-gate probe ----")
  for _, p in ipairs((M.Config.gate or {}).questPaths or {}) do
    log("  '" .. p .. "' -> " .. tostring(questState(p)))
  end
  log("  preconditionMet = " .. tostring(preconditionMet()))
  log("--------------------------")
end

-- ---------------------------------------------------------------------------
-- Map pin on the hideout (same mappin path as the dinner waypoint)
-- ---------------------------------------------------------------------------
local function placePin()
  if state.mappinId or not M.Config.hideoutPos then return end
  pcall(function()
    local h = M.Config.hideoutPos
    local pos  = ToVector4{ x = h[1], y = h[2], z = h[3], w = 1.0 }
    local data = NewObject("gamemappinsMappinData")
    data.mappinType = TweakDBID.new("Mappins.DefaultStaticMappin")
    data.variant    = gamedataMappinVariant.CustomPositionVariant
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
-- Post-shard sequence: call -> arrival -> reunion -> UNLOCK.
-- Each step uses a bound starter if present, else immediately advances (so the
-- quest always completes even before Phases 3-4 are wired).
-- ---------------------------------------------------------------------------
local onCallDone, onArrived, onReunionDone   -- forward decls

local function startSequence()
  if state.seq then return end                 -- already running
  state.seq = "call"
  log("post-shard: Jackie calls V")
  if deps.startCall then pcall(deps.startCall, onCallDone) else onCallDone() end
end

onCallDone = function()
  if state.seq ~= "call" then return end
  state.seq = "arrive"
  log("call done -> safe walk-in arrival")
  if deps.startArrival then pcall(deps.startArrival, M.Config.hideoutPos, M.Config.hideoutYaw, onArrived)
  else onArrived() end
end

onArrived = function()
  if state.seq ~= "arrive" then return end
  state.seq = "reunion"
  log("arrived -> reunion dialogue")
  if deps.startReunion then pcall(deps.startReunion, onReunionDone) else onReunionDone() end
end

onReunionDone = function()
  state.seq = "done"
  clearPin()
  setStage(REUNITED)
  log("REUNITED — mod unlocked.")
end

-- ---------------------------------------------------------------------------
-- Quest transitions
-- ---------------------------------------------------------------------------
function M.giveTip()                                   -- LOCKED -> TIP
  if getStage() >= TIP then return false end
  showTip(M.Config.tipTitle, M.Config.tipText, M.Config.tipDuration)
  setStage(TIP)
  return true
end

local function reachHideout()                          -- TIP -> SHARD
  if getStage() ~= TIP then return end
  showTip(M.Config.shardTitle, table.concat(M.Config.shardLines, "\n"), M.Config.shardDuration)
  log("Shard read at hideout.")
  setStage(SHARD)
  state.callAt, state.seq = state.clock + (M.Config.callDelay or 1.0), nil
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
function M.isUnlocked()    return getStage() >= REUNITED end
function M.getStage()      return getStage() end
-- Player-facing stage names (shown at the top of the CET window).
function M.stageName()
  local s = getStage()
  if s >= REUNITED then return "Jackie is back" end
  if s == SHARD    then return "Jackie's note was read at Rocky Ridge — he's on his way" end
  if s == TIP      then return "V heard the rumor — find Jackie in the Badlands" end
  return "Jackie revival not yet available"
end
function M.unavailableMsg() return "Number disconnected." end
function M.notifyUnavailable() onscreen(M.unavailableMsg(), 2.5) end   -- native band, no init.lua scope needed

-- Inject init.lua helpers. ALL optional:
--   log(msg)                              -- logger
--   showTip(title, text) -> bool          -- native tutorial popup (Phase 2)
--   startCall(onDone)                     -- one-time incoming call (Phase 3)
--   startArrival(pos, yaw, onArrive)      -- safe walk-in (Phase 4)
--   startReunion(onDone)                  -- first-sight dialogue (Phase 4)
function M.bind(opts)
  opts = opts or {}
  for _, k in ipairs({ "log", "showTip", "startCall", "startArrival", "startReunion", "spawnAt" }) do
    if opts[k] ~= nil then deps[k] = opts[k] end
  end
end

function M.reset()                                     -- debug: back to LOCKED
  clearPin(); state.vikFired, state.callAt, state.seq = false, nil, nil
  setStage(LOCKED)
end

-- Debug jumps for the CET window.
function M.forceTip()   M.reset(); M.giveTip() end     -- skip the Vik proximity
function M.forceShard() if getStage() < TIP then M.giveTip() end; reachHideout() end

-- Per-frame driver (call from init.lua onUpdate with the frame delta).
function M.tick(dt)
  state.clock = state.clock + (dt or 0)
  local s = getStage()

  if s ~= state.lastStage then                         -- pin follows the stage (survives reloads)
    if s == TIP then placePin() else clearPin() end
    state.lastStage = s
  end

  if s == LOCKED then
    if not state.vikFired and preconditionMet()
       and nearPoint(M.Config.vikPos, M.Config.vikRadius) then
      state.vikFired = true
      M.giveTip()
    end
  elseif s == TIP then
    if not state.mappinId then placePin() end
    if nearPoint(M.Config.hideoutPos, M.Config.hideoutRadius) then reachHideout() end
  elseif s == SHARD then
    if state.callAt and state.clock >= state.callAt then startSequence() end
  end
end

return M

--[[
  ============================================================================
  PATCH LIST for init.lua  (Phase 1 wiring — all surgical inserts)
  ============================================================================
  1) require (next to `local Config = require("config")`):
       local Retrieval = require("retrieval")
  2) onInit (near pcall(jlLoadSettings)):
       pcall(function() Retrieval.bind{ log = log } end)
  3) scheduleTick top (after the leaving check):
       if not Retrieval.isUnlocked() then clearIdle(); return end
  4) summonJackie / startCall — at the top:
       if not Retrieval.isUnlocked() then showOnscreenMsg(Retrieval.unavailableMsg(), 2.5); return end
     onPlayerCalledJackie — at the top (let the game's own call ring out):
       if not Retrieval.isUnlocked() then return end
  5) onUpdate (where pcall(scheduleTick) runs) — pass the frame delta:
       pcall(function() Retrieval.tick(deltaTime) end)
  6) (optional) CET debug UI:
       ImGui.Text("Retrieval: " .. Retrieval.stageName())
       if ImGui.Button("Force tip")   then Retrieval.forceTip()   end
       if ImGui.Button("Force shard") then Retrieval.forceShard() end
       if ImGui.Button("Quest probe") then Retrieval.debugQuestState() end
       if ImGui.Button("Reset quest") then Retrieval.reset()       end
  Phases 2-4 add more Retrieval.bind{} helpers (showTip / startCall / startArrival / startReunion).
--]]
