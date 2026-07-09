-- tools/test_blaze_calm.lua — unit tests for the v1.51 Blaze finale "transport calm".
--
-- Run from the repo root:  lua tools/test_blaze_calm.lua mod/JackieLives/init.lua
-- Exits non-zero on failure. Stock Lua 5.x; no game, no CET.
--
-- Like test_walk_gates.lua, this EXTRACTS the real functions out of init.lua and runs them against stubs,
-- so it cannot drift from the shipped code.
--
-- What it pins down — the exact bug this fixes:
--   The old blazeForceStand did `pcall(function() ApplyStatusEffect(pl, rec); ok = true end)` and treated
--   "nothing threw" as success. ApplyStatusEffect is a native import that silently does NOTHING when handed
--   an unknown TweakDBID — it does not raise. So the first record ALWAYS "succeeded", the stock fallback was
--   never tried, and the log claimed the effect was applied while V stayed crouched. These tests assert the
--   new record-selection is driven by TweakDB:GetRecord instead, and that total failure is reported.

local SRC = assert(arg[1], "usage: lua tools/test_blaze_calm.lua mod/JackieLives/init.lua")

-- ---- stubs ----------------------------------------------------------------
JL, Config, LOG = {}, {}, {}
function log(s) LOG[#LOG + 1] = tostring(s) end
local function loggedMatching(pat)
  for _, l in ipairs(LOG) do if l:find(pat, 1, true) then return true end end
  return false
end

-- TweakDB with a controllable set of present records.
PRESENT = {}
TweakDB = { GetRecord = function(_, id) return PRESENT[id] or nil end }

APPLIED = {}
StatusEffectHelper = { ApplyStatusEffect = function(_, rec) APPLIED[#APPLIED + 1] = rec end }

-- blazeForceStand calls ApplyStatusEffect(pl, rec) with TWO args (no colon), so shim accordingly.
StatusEffectHelper.ApplyStatusEffect = function(_pl, rec) APPLIED[#APPLIED + 1] = rec end

HOLSTERS, CROUCHED = 0, true
function blazeHolsterWeapon(_) HOLSTERS = HOLSTERS + 1; return true end
function jlVCrouched() return CROUCHED end
Game = { GetPlayer = function() return { name = "V" } end }

-- ---- extract the real functions -------------------------------------------
local src = io.open(SRC, "r"):read("a")
local function extract(name)
  local s = src:find("\nfunction " .. name .. "%(")
  assert(s, "could not find function " .. name)
  local e = src:find("\nend\n", s)
  assert(e, "could not find end of " .. name)
  return src:sub(s + 1, e + 4)
end
load(extract("blazeForceStand"))()
load(extract("blazeCalmHoldTick"))()

-- ---- helpers ---------------------------------------------------------------
local fails = 0
local function check(name, got, want)
  if got ~= want then
    fails = fails + 1
    print(("FAIL %-56s got=%s want=%s"):format(name, tostring(got), tostring(want)))
  else
    print(("ok   %-56s %s"):format(name, tostring(got)))
  end
end
local function reset()
  JL, LOG, APPLIED, HOLSTERS = {}, {}, {}, 0
  Config = { blazeCalm = { holdSeconds = 3.0, interval = 0.25, maxHolsterReasserts = 3 } }
  PRESENT, CROUCHED = {}, true
end

-- ===========================================================================
-- 1. Our TweakXL record is installed -> use it, don't touch the stock fallback.
reset(); PRESENT["GameplayRestriction.JLForceStand"] = {}
check("our record present -> returns true", blazeForceStand({}), true)
check("  applied exactly one effect", #APPLIED, 1)
check("  ...and it was JLForceStand", APPLIED[1], "GameplayRestriction.JLForceStand")
check("  remembered for release", JL.forceStandRec, "GameplayRestriction.JLForceStand")

-- 2. THE REGRESSION THIS FIXES. Our record is MISSING (r6\tweaks not deployed) but the stock one exists.
--    Old code applied JLForceStand, saw no throw, returned true, and never fell back. New code must skip it.
reset(); PRESENT["GameplayRestriction.ForceStand"] = {}
check("our record MISSING -> still returns true (fallback)", blazeForceStand({}), true)
check("  did NOT apply the missing record", APPLIED[1], "GameplayRestriction.ForceStand")
check("  applied exactly one effect", #APPLIED, 1)
check("  said it skipped the absent record", loggedMatching("is NOT in TweakDB"), true)

-- 3. Neither record exists -> must FAIL LOUDLY, not silently claim success.
reset()
check("no record at all -> returns false", blazeForceStand({}), false)
check("  applied nothing", #APPLIED, 0)
check("  named the missing yaml in the log", loggedMatching("jl_force_stand.yaml"), true)
check("  warned V will stay crouched", loggedMatching("STAY CROUCHED"), true)
check("  did NOT record a release target", JL.forceStandRec, nil)

-- ===========================================================================
-- 4. The hold: V is crouched, so it re-asserts; once she stands it stops and reports.
reset(); PRESENT["GameplayRestriction.JLForceStand"] = {}
JL.forceStandRec = "GameplayRestriction.JLForceStand"
JL.clock = 0
JL.blazeCalm = { startedAt = 0, deadline = 3.0, nextAt = 0, holsters = 0 }
JL.clock = 0.30; blazeCalmHoldTick()                       -- still crouched -> re-assert
check("crouched -> re-applied ForceStand", #APPLIED, 1)
check("crouched -> re-queued holster", HOLSTERS, 1)
check("crouched -> hold still armed", JL.blazeCalm ~= nil, true)

CROUCHED = false
JL.clock = 0.60; blazeCalmHoldTick()                       -- V stood up -> finish
check("V stands -> hold disarms", JL.blazeCalm, nil)
check("V stands -> reported success", loggedMatching("V is STANDING"), true)
check("V stands -> no extra effect applied", #APPLIED, 1)

-- 5. Holster re-asserts are capped (a running hold must not spam the equipment system).
reset(); JL.forceStandRec = "GameplayRestriction.JLForceStand"
JL.clock = 0; JL.blazeCalm = { startedAt = 0, deadline = 100.0, nextAt = 0, holsters = 0 }
for i = 1, 10 do JL.clock = i * 0.30; blazeCalmHoldTick() end
check("holster re-asserts capped at maxHolsterReasserts", HOLSTERS, 3)
check("ForceStand keeps being re-asserted though", #APPLIED >= 10, true)

-- 6. Window expires with V still crouched -> say so plainly, and blame the right thing.
reset(); JL.forceStandRec = "GameplayRestriction.JLForceStand"
JL.clock = 0; JL.blazeCalm = { startedAt = 0, deadline = 1.0, nextAt = 0, holsters = 0 }
JL.clock = 1.50; blazeCalmHoldTick()
check("expired while crouched -> disarms", JL.blazeCalm, nil)
check("expired -> reported STILL CROUCHED", loggedMatching("STILL CROUCHED"), true)
check("expired -> pointed at the tweaks yaml", loggedMatching("jl_force_stand.yaml"), true)

print(fails == 0 and "\nALL PASS" or ("\n" .. fails .. " FAILURE(S)"))
os.exit(fails == 0 and 0 or 1)
