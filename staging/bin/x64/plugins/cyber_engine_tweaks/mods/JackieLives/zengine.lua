-- zengine.lua — OPTIONAL integration with 0-Engine (global `ZEngine`)
-- =============================================================================
-- ⚠️ READ docs/research/zero_engine.md BEFORE CHANGING ANY OF THIS.
--
-- WHAT 0-ENGINE IS. A shared runtime service layer for CET mods (DigitalVixen, Nexus 27967). Every
-- CET mod otherwise runs its OWN onUpdate, its own player-position read, its own PlayerStateMachine
-- blackboard poll and its own Cron list; install fifteen such mods and the game does the same work
-- fifteen times a frame. 0-Engine does it ONCE per frame and hands the result out through
-- `GetMod("0-Engine")`. Its folder is named with a leading 0 because CET loads mods alphabetically,
-- so it is always initialised before any consumer.
--
-- WHY WE BOTHER, HONESTLY. Mostly stack citizenship, not speed. What it buys:
--   1. we stop being a SECOND copy of work the stack already did (the scene-tier blackboard poll),
--   2. we appear in 0-Engine's overlay with a live callback count, which is what users asking for
--      "0-Engine compatibility" actually want to see,
--   3. one place to hang future shared state instead of another private poller.
-- Users who don't have 0-Engine lose nothing: every accessor here answers nil and the caller falls
-- back to the reader it always used.
--
-- HOW WE ATTACH. Their init.lua ends `return Engine`, so `GetMod("0-Engine")` IS the published API
-- table (unlike the NCA bridge, which reaches into an unpublished field — see nca.lua). We use:
--     Engine.GetVersion()            -> "0.18.6"
--     Engine.Register("JackieLives")     -> scoped handle; also lists us in their overlay
--     Engine.GetState()              -> read-only per-frame state (.blackboard.scene.tier, .inMenu,
--                                       .inCombat, .inVehicle, .derived.district)
-- Everything is pcall'd and any failure detaches us for good rather than retrying into a broken API.
--
-- ⚠️ WE DO NOT MOVE OUR TICK INTO Engine.OnUpdate. Their UpdateFrame returns early unless a session
-- is loaded AND the player is valid — but `nsTick` and `Session.tick` MUST keep running at the main
-- menu or the Esc-menu settings panel never registers there (init.lua's onUpdate says so at the
-- session guard). We keep our own onUpdate and merely CONSUME their state.
--
-- ⚠️ WE DO NOT TAKE V's POSITION FROM THEM. Cross-mod tick order is CET load order, which is not
-- ours to control; a position read one frame stale makes the follow logic drift by a frame (see the
-- FRAME BOUNDARY comment at the top of onUpdate). `playerPos()` stays on our own reader forever.
-- Scene tier is safe to take: it changes when a scene starts, not per frame, and every consumer
-- already treats it as "are we in a cutscene", not as a coordinate.
--
-- ⚠️ NOTE FOR THIS REPO. Unlike NCLives/NCLucy, JackieLives has NO `Perf` frame cache — `jlInCutscene`
-- pays the full three cross-boundary calls plus a fresh pcall closure on EVERY call, several times a
-- frame while Jackie is out. So here 0-Engine's value replaces an uncached read, not a memoised one,
-- and it is the one place in this mod where the integration is worth more than tidiness. Do not "fix"
-- that by caching their value on our side: theirs is already per-frame, and a second cache would just
-- add a staleness window of our own.
--
-- ⚠️ THEIR OVERLAY CHECKBOX DOES NOT DISABLE NCLIVES. `Engine.DisableMod` only silences callbacks
-- REGISTERED THROUGH the engine, and ours is one heartbeat. That is deliberate: a player unticking a
-- box must not kill a mod with a companion spawned and a conversation open. `ZEngine.status()` says
-- so out loud, so nobody diagnoses that as our bug.
-- =============================================================================

local M = { version = "1.0" }

-- The oldest 0-Engine whose API shape this file was written against. Older ones are refused rather
-- than probed field-by-field: `GetState().blackboard.scene` only exists from 0.18 on, and attaching
-- to something without it would answer tier=nil forever while reporting "attached".
M.minEngine = "0.18"

local S = {
  attached = false,
  mod      = nil,      -- the Engine table itself
  handle   = nil,      -- our scoped handle from Engine.Register
  ver      = nil,
  tries    = 0,
  nextTry  = 0,
  reads    = 0,        -- how many times a caller actually took a value from them (proof, for the probe)
  refused  = nil,      -- why we declined to attach, if we did
  frame    = nil,      -- the heartbeat's unsubscribe handle (detach owes it back — see detach)
  heartbeat= nil,      -- has their dispatcher actually called us once
}

M.env = {}

-- Bound from init.lua. ⚠️ Like NCL.bind / Allies.bind, this copies only the keys it NAMES.
function M.bind(t)
  for _, k in ipairs({
    "log",       -- function(msg)
    "enabled",   -- function() -> bool   the A/B switch (Config.zeroEngine.enabled)
  }) do if t[k] ~= nil then M.env[k] = t[k] end end
end

local function log(m) if M.env.log then pcall(M.env.log, "[0-Engine] " .. tostring(m)) end end

local function switchedOn()
  if not M.env.enabled then return true end        -- unbound (offline tests) = on
  local ok, v = pcall(M.env.enabled)
  return (not ok) or (v ~= false)
end

function M.present() return S.attached end

-- ---------------------------------------------------------------------------
-- Version compare — "0.18.6" >= "0.18". Numeric per segment, so 0.9 < 0.18.
-- ---------------------------------------------------------------------------
-- A plain string compare would read "0.9" as NEWER than "0.18" and attach to an API that predates
-- the blackboard scene table.
function M.versionAtLeast(have, want)
  if type(have) ~= "string" or type(want) ~= "string" then return false end
  local h, w = {}, {}
  for n in have:gmatch("%d+") do h[#h + 1] = tonumber(n) end
  for n in want:gmatch("%d+") do w[#w + 1] = tonumber(n) end
  for i = 1, #w do
    local a, b = h[i] or 0, w[i]
    if a > b then return true end
    if a < b then return false end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- STATE READS. Contract: nil means "ask the engine yourself" — never a guess.
-- ---------------------------------------------------------------------------
-- Every one of these is a table lookup into a value 0-Engine already computed this frame, so they
-- are cheap enough to call from a tick without going through Perf.cached. They must NEVER throw:
-- their state proxy errors on WRITE, and a nested field can be absent mid-session-transition.
local function state()
  if not S.attached then return nil end
  local ok, st = pcall(S.mod.GetState)
  if not ok or type(st) ~= "table" then return nil end
  return st
end

-- 1 = full gameplay ... 4/5 = cinematic. Same integer our own nclReadSceneTier returns.
function M.sceneTier()
  local st = state(); if not st then return nil end
  local ok, tier = pcall(function() return st.blackboard.scene.tier end)
  if not ok or type(tier) ~= "number" then return nil end
  -- 0-Engine reports tier 0 before its first successful poll (its initial cached value). Our readers
  -- treat "< 4" as "not in a cutscene", so handing 0 back would ANSWER a question they haven't
  -- answered yet — and at exactly the wrong moment, the first frames of a load. nil = ask yourself.
  if tier <= 0 then return nil end
  S.reads = S.reads + 1
  return tier
end

function M.inMenu()
  local st = state(); if not st then return nil end
  local ok, v = pcall(function() return st.inMenu end)
  if not ok or type(v) ~= "boolean" then return nil end
  S.reads = S.reads + 1
  return v
end

function M.inCombat()
  local st = state(); if not st then return nil end
  local ok, v = pcall(function() return st.inCombat end)
  if not ok or type(v) ~= "boolean" then return nil end
  S.reads = S.reads + 1
  return v
end

function M.inVehicle()
  local st = state(); if not st then return nil end
  local ok, v = pcall(function() return st.inVehicle end)
  if not ok or type(v) ~= "boolean" then return nil end
  S.reads = S.reads + 1
  return v
end

-- Their district name ("Watson", "Kabuki", ...). We have no district logic today; this exists
-- because schedules will want it and it is free while attached.
function M.district()
  if not S.attached then return nil end
  local ok, d = pcall(S.mod.GetDistrict)
  if not ok or type(d) ~= "string" or d == "" or d == "Unknown" then return nil end
  S.reads = S.reads + 1
  return d
end

-- ---------------------------------------------------------------------------
-- ATTACH
-- ---------------------------------------------------------------------------
function M.attach(mod)
  if S.attached then return true end
  if type(mod) ~= "table" then return false end

  local ver
  pcall(function() ver = mod.GetVersion and mod.GetVersion() end)
  if type(ver) ~= "string" then
    S.refused = "no GetVersion() — not the API we know"
    log("refusing to attach: " .. S.refused)
    return false
  end
  if not M.versionAtLeast(ver, M.minEngine) then
    S.refused = ("v%s is older than v%s"):format(ver, M.minEngine)
    log("refusing to attach: " .. S.refused .. " (integration off; JackieLives runs on its own readers)")
    return false
  end
  if type(mod.GetState) ~= "function" or type(mod.Register) ~= "function" then
    S.refused = "GetState/Register missing — their layout changed"
    log("refusing to attach: " .. S.refused)
    return false
  end

  S.mod, S.ver = mod, ver
  S.attached = true

  -- Register so we show up in their overlay's Registered Mods list. A nil handle is not fatal —
  -- the state reads above go through Engine.*, not through the handle.
  local h
  pcall(function() h = mod.Register("JackieLives") end)
  S.handle = (type(h) == "table") and h or nil

  -- One registered callback, purely so the overlay's callback count is honest and their frame
  -- dispatcher has something of ours to show. Every 300 frames ≈ every 5 s at 60 fps: it costs
  -- nothing and proves the wiring end to end in the log after a fresh load.
  if S.handle and type(S.handle.OnFrame) == "function" then
    pcall(function()
      -- Keep the handle: detach() must be able to hand it back, or their dispatcher keeps calling a
      -- closure owned by a mod that has been unloaded (their emitter holds the only reference).
      S.frame = S.handle.OnFrame(300, function()
        if not S.heartbeat then
          S.heartbeat = true
          log("frame dispatcher reached us (heartbeat) — integration live")
        end
      end)
    end)
  end

  -- Prove the read path NOW rather than trusting it: if their state shape moved, we want that in the
  -- log at attach time, not as a silent nil forever.
  local st = state()
  local shapeOk = (st ~= nil) and (pcall(function() return st.blackboard.scene.tier end))
  log(("attached to v%s (registered=%s, state shape %s)")
      :format(ver, tostring(S.handle ~= nil), shapeOk and "ok" or "UNRECOGNISED — reads will fall back"))
  return true
end

function M.detach()
  if not S.attached then return end
  -- Give the heartbeat back FIRST, while their table is still reachable. An unsubscribe that throws
  -- must not leave us "attached" — hence pcall around it and the unconditional clear below.
  if S.frame and type(S.frame.unsubscribe) == "function" then
    pcall(function() S.frame.unsubscribe() end)
  end
  S.frame, S.heartbeat = nil, nil
  S.attached, S.mod, S.handle = false, nil, nil
  log("detached")
end

-- ---------------------------------------------------------------------------
-- tick — find them, once, without spinning
-- ---------------------------------------------------------------------------
-- ⚠️ NOT AT onInit. Alphabetical load order says 0-Engine is up before us, but that is THEIR folder
-- name, not a guarantee we control, and CET can soft-reload a single mod at any time. So: same slow
-- retry as the NCA bridge, then stop for good. A player without 0-Engine pays 20 GetMod calls in the
-- first minute and nothing ever again.
M.maxTries     = 20
M.retrySeconds = 3.0

function M.tick(now)
  now = now or 0
  if S.attached then return end
  if not switchedOn() then return end
  if S.tries >= M.maxTries then return end
  if now < S.nextTry then return end
  S.nextTry = now + M.retrySeconds
  S.tries = S.tries + 1

  local mod
  pcall(function() mod = GetMod("0-Engine") end)
  if not mod then
    if S.tries == M.maxTries then log("0-Engine is not installed — integration off (this is normal)") end
    return
  end
  M.attach(mod)
end

-- ---------------------------------------------------------------------------
-- status / probe — one line and one page for the Diagnostics hotkey
-- ---------------------------------------------------------------------------
function M.status()
  local installed
  pcall(function() installed = GetMod("0-Engine") ~= nil end)
  return ("0-Engine: installed=%s attached=%s theirVer=%s registered=%s reads=%d tries=%d switch=%s%s")
         :format(tostring(installed == true), tostring(S.attached), tostring(S.ver or "?"),
                 tostring(S.handle ~= nil), S.reads, S.tries, switchedOn() and "on" or "OFF",
                 S.refused and (" refused=" .. S.refused) or "")
end

function M.probe()
  local out = {}
  local function add(l) out[#out + 1] = l end
  add("----- 0-ENGINE PROBE -----")
  add(M.status())

  local mod
  pcall(function() mod = GetMod("0-Engine") end)
  if not mod then
    add("0-Engine is not loaded. JackieLives runs on its own readers — nothing is wrong.")
    add("----- END -----")
    return out
  end
  if not S.attached then
    add("Their mod is loaded but we are not attached. If refused= is empty above, the retry")
    add("window may simply not have elapsed yet (up to " .. tostring(M.maxTries * M.retrySeconds) .. " s after load).")
    add("----- END -----")
    return out
  end

  -- What we actually get from them, right now, spelled out. Each line is a value some tick uses.
  add(("sceneTier=%s  (ours: nclInCutscene reads this)"):format(tostring(M.sceneTier())))
  add(("inMenu=%s inCombat=%s inVehicle=%s district=%s")
      :format(tostring(M.inMenu()), tostring(M.inCombat()), tostring(M.inVehicle()), tostring(M.district())))
  add("NOTE: their overlay's JackieLives checkbox does NOT disable JackieLives — it only silences the")
  add("      callbacks we registered through them (one heartbeat). Ours is our own onUpdate,")
  add("      because our main-menu ticks must run when their loop is asleep.")
  add("----- END -----")
  return out
end

return M
