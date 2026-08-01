--[[
  familiarity.lua — JACKIE OPENS UP OVER TIME  (v1.65)
  ============================================================================
  Ported from NCLives' NCL.fam, with a deliberately HARDER curve. Self-contained:
  init.lua couples to it in five one-line spots (see PATCH LIST at the bottom),
  and every dependency is injected via Fam.bind{} so an unbound helper no-ops
  rather than erroring.

  THE PROBLEM IT SOLVES. The mod shipped Jackie's whole conversation on day one:
  the first time you ever pressed F on him he'd tell you what nearly dying felt
  like. For the man who spent Act 1 keeping things light in front of V, that's
  backwards — it hands you the ending in the first minute, and it makes every
  later conversation a repeat.

  ONE NUMBER, per save, that only goes up. Topics and individual LINES carry a
  minimum tier, so the conversation GROWS:

     "How you holdin' up, Jackie?"
       tier 0 -> "Can't complain, chica."
       tier 3 -> "Some mornings I forget. Then I stand up too fast and the
                  ribs remind me. ...Don't tell Mama I said that."

  ⚠️ WHY THIS CURVE IS SLOWER THAN NCLIVES' (Antonia, 2026-08-01: "the progression
  should be slow though, you really have to know jackie and spend a lot of time
  with him"). NCLives shipped { 0, 5, 14, 28 } with a topic paying 1 point EACH,
  so a single good conversation could be worth five. That's right for meeting
  Panam. It is wrong for Jackie, for two reasons:
    * he is not a stranger — the distance the player is closing isn't "do we know
      each other", it's "will you tell me the truth about what happened to you",
      and that should cost real time;
    * he has a whole mod's worth of story behind him, so the deep tiers are the
      payoff of the mod, not an early-game convenience.
  So this uses the FIRST shape NCLives tried (one point per CONVERSATION, not per
  topic) and then puts the bar higher still. See Config.familiarity.

  Stored as the per-save game fact `jackielives_familiarity`, so it rides the
  save exactly like the retrieval stage does, and a new playthrough starts over.
--]]

local M = {}

M.VERSION = "1.65"

-- ---------------------------------------------------------------------------
-- Injected from init.lua (Fam.bind{...}). All optional.
-- ---------------------------------------------------------------------------
--   log(msg)                 -> console + log file
--   factGet(name) -> number  -> read a per-save numeric game fact
--   factSet(name, n)         -> write one
--   config() -> table        -> the LIVE Config.familiarity (re-read every call, because
--                               config.lua is re-required from disk on every reload)
local deps = {}

function M.bind(t)
  for _, k in ipairs({ "log", "factGet", "factSet", "config" }) do
    if t and t[k] ~= nil then deps[k] = t[k] end
  end
  return M
end

local function log(msg) if deps.log then pcall(deps.log, "[Fam] " .. tostring(msg)) end end

M.FACT = "jackielives_familiarity"

-- Fallback used only if config.lua somehow has no familiarity block, so the mod can never
-- hard-fail on a missing table. These mirror the shipped values.
local DEFAULTS = {
  enabled = true,
  tiers   = { 0, 10, 30, 65 },
  names   = { "Choom", "Close", "Trusted", "Family" },
  award   = { talk = 1, dinner = 4, call = 1 },
  max     = 999,
}

local function cfg()
  local c
  if deps.config then pcall(function() c = deps.config() end) end
  if type(c) ~= "table" then return DEFAULTS end
  return c
end

-- ---------------------------------------------------------------------------
-- Points
-- ---------------------------------------------------------------------------
function M.points()
  local v = 0
  if deps.factGet then pcall(function() v = deps.factGet(M.FACT) or 0 end) end
  return (type(v) == "number" and v >= 0) and v or 0
end

function M.setPoints(n)
  local c = cfg()
  n = math.max(0, math.min(math.floor(tonumber(n) or 0), c.max or 999))
  if deps.factSet then pcall(function() deps.factSet(M.FACT, n) end) end
  return n
end

-- Add points for a REASON ("talk" / "dinner" / "call"), or an explicit amount.
-- A negative amount is allowed (V can say the wrong thing) but the floor is 0:
-- you can cool Jackie off, you can never make him a stranger again.
function M.add(why, explicit)
  local c = cfg()
  if c.enabled == false then return M.points(), false end
  local n = tonumber(explicit)
  if n == nil then n = tonumber((c.award or {})[why]) end
  if n == nil or n == 0 then return M.points(), false end
  local before = M.points()
  local after  = M.setPoints(before + n)
  local t0, t1 = M.tier(before), M.tier(after)
  if t1 > t0 then
    log(("%+d (%s) -> %d points. TIER UP: %s -> %s"):format(n, tostring(why), after, M.tierName(t0), M.tierName(t1)))
  else
    log(("%+d (%s) -> %d points (%s)"):format(n, tostring(why), after, M.tierName(t1)))
  end
  return after, (t1 > t0)
end

-- ---------------------------------------------------------------------------
-- Tiers
-- ---------------------------------------------------------------------------
-- Highest tier whose threshold `points` has reached. Tier 0 always qualifies.
function M.tier(points)
  local c = cfg()
  -- ⚠️ Disabled must mean "show EVERYTHING", never "show nothing". Turning the system off is a
  -- debug/accessibility switch; if it hid the writing it would look like the content vanished.
  if c.enabled == false then return #(c.tiers or DEFAULTS.tiers) - 1 end
  local p = points or M.points()
  local t = 0
  for i, need in ipairs(c.tiers or DEFAULTS.tiers) do
    if p >= need then t = i - 1 end
  end
  return t
end

function M.tierName(t)
  local c = cfg()
  local names = c.names or DEFAULTS.names
  return names[(t or M.tier()) + 1] or ("tier " .. tostring(t))
end

-- The gate every piece of content asks. `need` is a tier (0..3); nil = ungated.
function M.allows(need)
  if need == nil then return true end
  local n = tonumber(need)
  if n == nil then return true end          -- malformed gate -> show it, don't silently eat content
  return M.tier() >= n
end

-- Points still needed for the next tier, and that tier's name. nil when maxed.
function M.toNext()
  local c = cfg()
  local tiers = c.tiers or DEFAULTS.tiers
  local p, t = M.points(), M.tier()
  local nextNeed = tiers[t + 2]
  if not nextNeed then return nil, nil end
  return math.max(0, nextNeed - p), M.tierName(t + 1)
end

-- One-line readout for the CET window / diagnostics.
function M.status()
  local c = cfg()
  if c.enabled == false then return "familiarity OFF (all content shown)" end
  local left, nextName = M.toNext()
  if not left then
    return ("%s — %d pts (max)"):format(M.tierName(), M.points())
  end
  return ("%s — %d pts (%d more for %s)"):format(M.tierName(), M.points(), left, nextName)
end

-- Debug/testing: jump straight to a tier's threshold.
function M.setTier(t)
  local c = cfg()
  local tiers = c.tiers or DEFAULTS.tiers
  t = math.max(0, math.min(math.floor(tonumber(t) or 0), #tiers - 1))
  local n = M.setPoints(tiers[t + 1] or 0)
  log(("tier forced to %s (%d points)"):format(M.tierName(t), n))
  return n
end

function M.reset()
  M.setPoints(0)
  log("familiarity reset to 0 (Choom).")
end

--[[
  PATCH LIST — how init.lua couples to this file
  ----------------------------------------------------------------------------
  1. Fam = require("familiarity")            -- GLOBAL (200-local cap), next to Retrieval/Blaze/Session
  2. Fam.bind{ log = log, factGet = jlFactNum, factSet = jlSetFactNum,
               config = function() return Config.familiarity end }
  3. drawChoiceRows' filter:  `if appear and c.minFam ~= nil then appear = Fam.allows(c.minFam) end`
     — BEFORE the `cond` check, so a locked topic can't be resurrected by the empty-menu fallback.
  4. Line variants: a jackiePool entry may carry minFam; pick the highest-tier entry V has earned.
  5. Awards: Fam.add("talk") once per conversation, Fam.add("dinner") at the dinner stand-up,
     Fam.add("call") when he comes out on a call. Plus per-choice `fam = <n>` for the wrong thing said.
--]]

return M
