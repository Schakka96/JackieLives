-- tools/test_follower.lua — unit tests for the v1.67 FOLLOWER ROLE (mod/JackieLives/native.lua).
--
-- Run from the repo root:   lua tools/test_follower.lua
-- Exits non-zero on failure. Needs only a stock Lua 5.x / LuaJIT (no game, no CET, no Windows).
--
-- WHY THIS FILE EXISTS
-- Until v1.67 Jackie became a follower by way of `amm.Spawn:SetNPCAsCompanion`. That works, but it
-- is AMM's code doing the one thing this mod cannot do without — and the same job written against
-- the base game (NCLives v1.64) produced a companion who spawned, looked perfect, and NEVER MOVED.
-- The reason is worth pinning down in a test, because nothing about it is visible at the call site:
--
--   aiComponent.script:520  IsPlayerCompanion() is true only if (a) the AI role is EAIRole.Follower
--                           AND (b) the behaviour argument 'FriendlyTarget' is a live attached object.
--   aiRole.script:209       AIFollowerRole.OnRoleSet(owner) is the ONLY thing that sets that argument.
--   aiComponent.script:468  OnRoleSet is reached through OnAIRoleChanged, which the engine fires off
--                           SetAIRole / OnAttach — NOT off a queued AIAssignRoleCommand.
--   aiComponent.script:486  AIHumanComponent.SetCurrentRole is the engine's own entry point.
--   NPCPuppet.script:303    IsPlayerCompanion is CACHED for ten seconds; skip the reset and a fresh
--                           companion reads as "not a companion" long after the role is on.
--
-- ⚠️ THE TRAP THIS HARNESS AVOIDS. A permissive stub answers every call cheerfully, so asserting
-- `setCompanion(stub) == true` proves only that we called *something* — which is exactly how the
-- broken version passed its tests for eleven versions. So these tests assert THE SEQUENCE against a
-- recording puppet: which engine calls were made, in which form, and whether the old role was
-- cleared first. Same lesson as the `_G[name]` sandbox test in test_dialogui.lua.

package.path = "mod/JackieLives/?.lua;" .. package.path

local fails, checks = 0, 0
local function check(name, ok, detail)
  checks = checks + 1
  if ok then print(("  ok   %s"):format(name))
  else fails = fails + 1; print(("  FAIL %s%s"):format(name, detail and ("\n         " .. detail) or "")) end
end

-- ---------------------------------------------------------------------------
-- Stubs: only what native.lua actually reaches for.
-- ---------------------------------------------------------------------------
local attitude = { SetAttitudeGroup = function() end,
                   SetAttitudeTowards = function() end,
                   GetAttitudeGroup = function() return "player_group" end }

Game = {
  GetPlayer = function() return { GetAttitudeAgent = function() return attitude end } end,
  CreateEntityReference = function() return "#player" end,
}
EAIAttitude = { AIA_Friendly = "friendly" }
-- Real game enums (aiComponent.script:500, NpcHandle.reds:113). These must exist: indexing a nil
-- global throws inside the caller's pcall, so the call it guards silently never happens.
gamedataSenseObjectType   = { Follower = "Follower", Npc = "Npc" }
gamedataNPCHighLevelState = { Relaxed = "Relaxed", Combat = "Combat" }
NPCPuppet = { ChangeHighLevelState = function() end }
AIFollowerRole = { new = function()
  return { GetRoleEnum = function() return "Follower" end, SetFollowerRef = function() end }
end }
AINoRole = { new = function() return { GetRoleEnum = function() return "None" end } end }
function NewObject(t) return (t == "handle:AIAssignRoleCommand") and { role = nil } or nil end
function GetMod() return nil end

local Native = require("native")
Native.bind{ log = function() end }

-- A puppet that RECORDS what the engine was asked to do.
local function mkPuppet(opts)
  opts = opts or {}
  local rec = { calls = {}, role = nil }
  local function note(n) rec.calls[n] = (rec.calls[n] or 0) + 1 end
  local ai = {
    GetAIRole   = function() return rec.role end,
    SetAIRole   = function(_, r) note("SetAIRole"); rec.role = r end,
    OnAttach    = function() note("OnAttach") end,
    SendCommand = function() note("SendCommand") end,
    IsPlayerCompanion = function() return rec.role ~= nil end,
  }
  rec.ai = ai
  rec.handle = {
    GetAIControllerComponent = function() return ai end,
    GetAttitudeAgent = function() return attitude end,
    SetSenseObjectType = function() note("SetSenseObjectType") end,
    ResetCompanionRoleCacheTimeStamp = function() note("ResetCompanionRoleCacheTimeStamp") end,
    NPCManager = { ScaleToPlayer = function() note("ScaleToPlayer") end },
  }
  if opts.preRole then
    rec.role = { GetRoleEnum = function() return "Patrol" end,
                 OnRoleCleared = function() note("OnRoleCleared") end }
  end
  return rec
end

print("\nFOLLOWER ROLE (native.lua v" .. tostring(Native.VERSION) .. ")")

-- --- the assignment itself --------------------------------------------------------------------
local p1 = mkPuppet()
check("setCompanion reports success only when the role is really on",
      Native.setCompanion(p1.handle) == true)
check("...via SetAIRole + OnAttach, the only form that reaches OnRoleSet (aiComponent.script:468)",
      p1.calls["SetAIRole"] == 1 and p1.calls["OnAttach"] == 1,
      "SetAIRole=" .. tostring(p1.calls["SetAIRole"]) .. " OnAttach=" .. tostring(p1.calls["OnAttach"]))
check("...and the IsPlayerCompanion cache is reset (NPCPuppet.script:303 holds it 10 s)",
      p1.calls["ResetCompanionRoleCacheTimeStamp"] == 1)
check("...and he is marked a Follower sense object (aiComponent.script:500)",
      p1.calls["SetSenseObjectType"] == 1)
check("...and level-scaled, so a companion in a high-level district isn't a paper target",
      p1.calls["ScaleToPlayer"] == 1)

-- --- the old role has to go first -------------------------------------------------------------
-- A spawned body arrives with its archetype's own role. Assigning over the top leaves the old
-- role's gameplay package applied; AMM clears it first (Modules/spawn.lua) and so must we.
local p2 = mkPuppet{ preRole = true }
Native.setCompanion(p2.handle)
check("an existing role is CLEARED before the follower role goes on", p2.calls["OnRoleCleared"] == 1)

-- --- the engine's own entry point wins when the build has it ------------------------------------
local p3 = mkPuppet()
local usedEnginePath = false
AIHumanComponent = { SetCurrentRole = function(h, r)
  usedEnginePath = true; h:GetAIControllerComponent():SetAIRole(r)
end }
Native.setCompanion(p3.handle)
check("AIHumanComponent.SetCurrentRole is preferred (aiComponent.script:486)", usedEnginePath)
check("...and the OnAttach fallback is then NOT also run", p3.calls["OnAttach"] == nil,
      "both paths ran — the role would be assigned twice")
AIHumanComponent = nil

-- --- the verdict is the ENGINE's answer, not ours ------------------------------------------------
-- This is the whole point of the rewrite: the watchdog in init.lua re-applies until the ENGINE
-- agrees, so `followerVerdict` must report what the game thinks, including when that is "no".
local p4 = mkPuppet()
local role, companion = Native.followerVerdict(p4.handle)
check("a puppet with no role reports role=false", role == false)
check("...and companion=false", companion == false)
Native.setCompanion(p4.handle)
role, companion = Native.followerVerdict(p4.handle)
check("once the role is on, the verdict flips to true", role == true and companion == true)

-- --- it must never take the mod down -------------------------------------------------------------
check("setCompanion tolerates a nil handle", Native.setCompanion(nil) == false)
check("followerVerdict tolerates a nil handle", (Native.followerVerdict(nil)) == false)
check("clearCompanion assigns AINoRole rather than clearing to nil",
      Native.clearCompanion(mkPuppet().handle) == true)
check("clearCompanion tolerates a nil handle", Native.clearCompanion(nil) == false)

-- A puppet whose AI controller is missing entirely (a body mid-teardown) must degrade, not throw.
local broken = { GetAIControllerComponent = function() return nil end }
local okCall = pcall(Native.setCompanion, broken)
check("a handle with no AI controller degrades instead of throwing", okCall)

-- ---------------------------------------------------------------------------
-- SPAWN (v1.68 — ported from NCLives v1.64)
-- ---------------------------------------------------------------------------
-- Before v1.68, summoning without AMM failed with "AMM Spawn module not available". AMM's own
-- SpawnNPC is just DynamicEntitySystem:CreateEntity 1 m in front of V (Modules/spawn.lua:582), so
-- this is the same spawn without the dependency.
print("\nSPAWN")

local created = nil
DynamicEntitySpec = { new = function() return {} end }
EulerAngles = { new = function() return { ToQuat = function() return "quat" end } end }
CName = { new = function(n) return n end }
Vector4 = { new = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end }
Game.GetDynamicEntitySystem = function()
  return { CreateEntity = function(_, spec) created = spec; return "entity-id-1" end,
           DeleteEntity = function() end }
end

local sp = Native.spawn("Character.Jackie", { x = 1, y = 2, z = 3, w = 1 }, 0.0,
                        "JackieLives_jackie", "jackie_welles_default")
check("Native.spawn returns a spawn record", type(sp) == "table" and sp.id ~= nil)
check("...tagged `native`, so despawn and diagnostics can tell the backends apart", sp.native == true)
check("...and the appearance rides on the SPEC, not applied afterwards",
      created and created.appearanceName == "jackie_welles_default",
      "appearanceName = " .. tostring(created and created.appearanceName))
check("Native.spawn refuses a record-less call", Native.spawn(nil) == nil)

-- The v1.43 outfit bug, one layer down: AMM silently no-opped on a TABLE appearance and Jackie came
-- out in the record default. spec.appearanceName does exactly the same thing, so the type is checked.
created = nil
Native.spawn("Character.Jackie", { x = 0, y = 0, z = 0, w = 1 }, 0.0, "t", { app = "suit" })
check("a TABLE appearance is rejected rather than passed to the spec",
      created and created.appearanceName == "default",
      "appearanceName = " .. tostring(created and created.appearanceName))

print("")
print(("%d checks, %d failed"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
