-- tools/test_blaze_calm.lua — unit tests for the v1.51 Blaze finale "transport calm".
--
-- Run from the repo root:  lua tools/test_blaze_calm.lua mod/JackieLives/init.lua
-- Exits non-zero on failure. Stock Lua 5.x; no game, no CET.
--
-- Like test_walk_gates.lua, this EXTRACTS the real functions out of init.lua and runs them against stubs,
-- so it cannot drift from the shipped code.
--
-- What it pins down:
--
--  * The silent-success bug (v1.51). The old blazeForceStand did
--    `pcall(function() ApplyStatusEffect(pl, rec); ok = true end)` and treated "nothing threw" as success.
--    ApplyStatusEffect is a native import that silently does NOTHING when handed an unknown TweakDBID — it
--    does not raise. So the first record ALWAYS "succeeded", the fallback was never tried, and the log
--    claimed the effect was applied while V stayed crouched. Record selection is now driven by
--    TweakDB:GetRecord, and total failure is reported.
--
--  * The runtime-minted record (v1.53). The uncrouch switch is a status effect carrying the gameplay TAG
--    `ForceStand`. Rather than ship a TweakXL yaml (and make players install TweakXL), we clone the stock
--    `GameplayRestriction.ForceCrouch` and swap its tag, at runtime, via CET's TweakDB API. If that can't be
--    done we DEGRADE: no uncrouch, V stays crouched, the finale runs normally. Never a crash, never a new
--    dependency. The tests cover all four paths: mint · already-supplied · fall back · degrade.

local SRC = assert(arg[1], "usage: lua tools/test_blaze_calm.lua mod/JackieLives/init.lua")

-- ---- stubs ----------------------------------------------------------------
JL, Config, LOG = {}, {}, {}
function log(s) LOG[#LOG + 1] = tostring(s) end
local function loggedMatching(pat)
  for _, l in ipairs(LOG) do if l:find(pat, 1, true) then return true end end
  return false
end

-- TweakDB with a controllable set of present records, and a working CloneRecord/SetFlat/Update.
-- CLONE_OK=false simulates a build where the runtime clone can't be done (CET API missing/changed).
PRESENT, CLONE_OK, CLONED = {}, true, {}
TweakDB = {
  GetRecord   = function(_, id) return PRESENT[id] or nil end,
  CloneRecord = function(_, newId, srcId)
    if not CLONE_OK then error("CloneRecord unavailable") end
    assert(PRESENT[srcId], "cannot clone a source record that doesn't exist: " .. tostring(srcId))
    PRESENT[newId] = { clonedFrom = srcId, tags = {} }
    CLONED[#CLONED + 1] = newId
  end,
  SetFlat = function(_, path, val)
    if not CLONE_OK then error("SetFlat unavailable") end
    local rec = path:match("^(.*)%.gameplayTags$")
    if rec and PRESENT[rec] then PRESENT[rec].tags = val end
  end,
  Update = function(_, _) if not CLONE_OK then error("Update unavailable") end end,
}
CName = { new = function(s) return s end }

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
load(extract("blazeEnsureForceStandRecord"))()
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
  JL, LOG, APPLIED, HOLSTERS, CLONED = {}, {}, {}, 0, {}
  Config = { blazeCalm = { holdSeconds = 3.0, interval = 0.25, maxHolsterReasserts = 3 } }
  -- ForceCrouch is the stock record we clone from; it always exists in the real game.
  PRESENT, CROUCHED, CLONE_OK = { ["GameplayRestriction.ForceCrouch"] = { tags = { "ForceCrouch" } } }, true, true
end

-- ===========================================================================
-- 1. v1.53 DEFAULT PATH: nothing but the stock ForceCrouch exists. We must MINT the record at runtime,
--    tag it ForceStand, and use it — with no TweakXL and no extra dependency.
reset()
check("no JLForceStand -> ensure() builds it", blazeEnsureForceStandRecord(), true)
check("  cloned exactly one record", #CLONED, 1)
check("  ...named JLForceStand", CLONED[1], "GameplayRestriction.JLForceStand")
check("  ...cloned from the stock ForceCrouch", PRESENT["GameplayRestriction.JLForceStand"].clonedFrom,
      "GameplayRestriction.ForceCrouch")
check("  ...with the tag swapped to ForceStand", PRESENT["GameplayRestriction.JLForceStand"].tags[1], "ForceStand")
check("  said it needed no TweakXL", loggedMatching("no TweakXL required"), true)

reset()
check("forceStand uses the minted record", blazeForceStand({}), true)
check("  applied exactly one effect", #APPLIED, 1)
check("  ...and it was JLForceStand", APPLIED[1], "GameplayRestriction.JLForceStand")
check("  remembered it for release", JL.forceStandRec, "GameplayRestriction.JLForceStand")

-- 2. A TweakXL yaml already supplied the record -> use it, don't clone over the top.
reset(); PRESENT["GameplayRestriction.JLForceStand"] = { tags = { "ForceStand" } }
check("record already present -> ensure() returns true", blazeEnsureForceStandRecord(), true)
check("  cloned nothing", #CLONED, 0)
check("  said a yaml supplied it", loggedMatching("TweakXL yaml supplied it"), true)

-- 3. THE OLD SILENT-SUCCESS BUG. Runtime clone unavailable, but a stock ForceStand record exists.
--    Old code applied the absent JLForceStand, saw no throw, returned true, never fell back.
reset(); CLONE_OK = false; PRESENT["GameplayRestriction.ForceStand"] = {}
check("clone impossible, stock exists -> falls back", blazeForceStand({}), true)
check("  did NOT apply the absent record", APPLIED[1], "GameplayRestriction.ForceStand")
check("  applied exactly one effect", #APPLIED, 1)
check("  said it skipped the absent record", loggedMatching("is NOT in TweakDB"), true)

-- 4. Nothing works at all -> DEGRADE quietly and correctly: no effect, no crash, honest log.
--    Antonia's explicit fallback: "if that's not workable, no un-sneak at all."
reset(); CLONE_OK = false
check("nothing available -> returns false", blazeForceStand({}), false)
check("  applied nothing", #APPLIED, 0)
check("  reported V stays crouched", loggedMatching("V stays crouched"), true)
check("  called it harmless (not an error)", loggedMatching("Harmless"), true)
check("  did NOT record a release target", JL.forceStandRec, nil)
check("  never mentions TweakXL as a requirement", loggedMatching("install TweakXL"), false)

-- ===========================================================================
-- 5. The hold: V is crouched, so it re-asserts; once she stands it stops and reports.
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

-- 6. Holster re-asserts are capped (a running hold must not spam the equipment system).
reset(); JL.forceStandRec = "GameplayRestriction.JLForceStand"
JL.clock = 0; JL.blazeCalm = { startedAt = 0, deadline = 100.0, nextAt = 0, holsters = 0 }
for i = 1, 10 do JL.clock = i * 0.30; blazeCalmHoldTick() end
check("holster re-asserts capped at maxHolsterReasserts", HOLSTERS, 3)
check("ForceStand keeps being re-asserted though", #APPLIED >= 10, true)

-- 7. Window expires with V still crouched -> say so plainly, and blame the right thing.
reset(); JL.forceStandRec = "GameplayRestriction.JLForceStand"
JL.clock = 0; JL.blazeCalm = { startedAt = 0, deadline = 1.0, nextAt = 0, holsters = 0 }
JL.clock = 1.50; blazeCalmHoldTick()
check("expired while crouched -> disarms", JL.blazeCalm, nil)
check("expired -> reported STILL CROUCHED", loggedMatching("STILL CROUCHED"), true)
check("expired -> called it cosmetic, not fatal", loggedMatching("finale runs normally"), true)

print(fails == 0 and "\nALL PASS" or ("\n" .. fails .. " FAILURE(S)"))
os.exit(fails == 0 and 0 or 1)
