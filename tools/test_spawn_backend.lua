-- tools/test_spawn_backend.lua — the v1.68 SPAWN BACKEND SWITCH.
--
-- Run from the repo root:   lua tools/test_spawn_backend.lua mod/JackieLives/init.lua
-- Exits non-zero on failure. Needs only a stock Lua 5.x / LuaJIT (no game, no CET, no Windows).
--
-- WHY THIS FILE EXISTS
-- Before v1.68, summoning Jackie without AppearanceMenuMod failed outright: ammSpawn bailed with
-- "AMM Spawn module not available". v1.68 spawns him with the base game instead — but the AMM path is
-- KEPT and selectable, because a player already running AMM with a Jackie who behaves the way they
-- expect should not be moved onto different code by an update they didn't ask for.
--
-- Two switches with three states between them, which is exactly where a silent wrong answer hides:
--   * the player's choice (Esc -> Settings -> JackieLives -> Compatibility -> "Use AMM for spawning")
--   * whether AMM is actually installed right now
-- The dangerous cell is "player chose AMM, AMM is gone" — answer that wrong and the mod is back to
-- being unsummonable, which is the bug v1.68 exists to fix.
--
-- Like test_walk_gates.lua, the functions are EXTRACTED from the shipped init.lua rather than copied,
-- so this cannot drift away from what actually runs.

local path = arg[1] or "mod/JackieLives/init.lua"
local src  = io.open(path, "r"):read("a")
local function extract(name)
  local s = src:find("\nfunction " .. name .. "%(")
  assert(s, "could not find " .. name)
  local e = src:find("\nend\n", s)
  return src:sub(s + 1, e + 4)
end

local T = dofile("tools/tcheck.lua")
local check = T.check

-- ---------------------------------------------------------------------------
-- The world the extracted functions run in.
-- ---------------------------------------------------------------------------
JL = { useAMM = false }
local logged = {}
function log(m) logged[#logged + 1] = tostring(m) end
local function loggedMatching(pat)
  local n = 0
  for _, m in ipairs(logged) do if m:find(pat, 1, true) then n = n + 1 end end
  return n
end

-- AMM, present or not, with or without the calls we need.
AMM_PRESENT, AMM_HAS_COMPANION_CALL = false, true
local ammSetCompanionCalls = 0
function getAMM()
  if not AMM_PRESENT then return nil end
  local amm = { Spawn = { NewSpawn = function() end } }
  if AMM_HAS_COMPANION_CALL then
    amm.Spawn.SetNPCAsCompanion = function(_, _) ammSetCompanionCalls = ammSetCompanionCalls + 1 end
  end
  return amm
end

local nativeSetCompanionCalls = 0
Native = { setCompanion = function() nativeSetCompanionCalls = nativeSetCompanionCalls + 1; return true end }

load(extract("jlUseAMM"))()
load(extract("jlMakeCompanion"))()

print("\nSPAWN BACKEND SWITCH (v1.68)")

-- --- which backend? ----------------------------------------------------------------------------
JL.useAMM, AMM_PRESENT = false, false
check("default: native, and AMM is not consulted", jlUseAMM() == false)

JL.useAMM, AMM_PRESENT = false, true
check("AMM installed but not chosen -> still native (an update must not switch anyone over)",
      jlUseAMM() == false)

JL.useAMM, AMM_PRESENT = true, true
check("the player chose AMM and AMM is there -> AMM", jlUseAMM() == true)

-- THE DANGEROUS CELL. Answering `true` here sends the summon down a path whose calls do not exist,
-- which is precisely the "AMM Spawn module not available" failure v1.68 removes.
JL.useAMM, AMM_PRESENT, JL.ammMissingWarned = true, false, nil
logged = {}
check("the player chose AMM but AMM is GONE -> native, not a dead end", jlUseAMM() == false)
check("...and it says so, once", loggedMatching("AMM is selected but not installed") == 1)
for _ = 1, 20 do jlUseAMM() end
check("...and does NOT repeat it every summon", loggedMatching("AMM is selected but not installed") == 1,
      "logged " .. loggedMatching("AMM is selected but not installed") .. " times — that is log spam per frame")

-- --- the follower role follows the same switch -------------------------------------------------
JL.useAMM, AMM_PRESENT, AMM_HAS_COMPANION_CALL = false, true, true
ammSetCompanionCalls, nativeSetCompanionCalls = 0, 0
jlMakeCompanion({})
check("native backend -> the role goes through Native.setCompanion",
      nativeSetCompanionCalls == 1 and ammSetCompanionCalls == 0)

JL.useAMM = true
ammSetCompanionCalls, nativeSetCompanionCalls = 0, 0
jlMakeCompanion({})
check("AMM backend -> the role goes through AMM, as it did before v1.67",
      ammSetCompanionCalls == 1 and nativeSetCompanionCalls == 0)

-- AMM present but that particular call missing (an AMM version bump). Must not silently leave Jackie
-- without a role — that is the "he spawns but stays planted" bug, arriving by a different door.
JL.useAMM, AMM_PRESENT, AMM_HAS_COMPANION_CALL = true, true, false
ammSetCompanionCalls, nativeSetCompanionCalls = 0, 0
logged = {}
jlMakeCompanion({})
check("AMM chosen but its companion call is missing -> falls back to the native role",
      nativeSetCompanionCalls == 1,
      "no role was assigned at all — he would spawn and stand still")
check("...and says which backend actually ran", loggedMatching("falling back to the native role") == 1)

check("jlMakeCompanion tolerates a nil handle", jlMakeCompanion(nil) == false)

print("")
T.finish()
