--[[
  native.lua — THE FOLLOWER ROLE, DONE THE WAY THE ENGINE DOES IT  (JackieLives v1.67)

  Self-contained module (global `Native`, so it costs init.lua no top-level local — see the 200-local
  cap note at the top of init.lua). Depends on nothing but the base game's own script API.

  ---------------------------------------------------------------------------
  WHY THIS EXISTS
  ---------------------------------------------------------------------------
  Ported from NCLives v1.65, where it was written to fix "AMM-free companions spawn but stay
  planted". JackieLives has the same bug latent in it for a different reason: it hands the job to
  `amm.Spawn:SetNPCAsCompanion`, so the day AMM changes that function — or a player runs without it —
  Jackie stands still and nothing says why.

  What actually makes an NPC follow, from the decompiled scripts:

    aiComponent.script:520  IsPlayerCompanion() is true only if (a) the AI role is EAIRole.Follower
                            AND (b) the behaviour argument 'FriendlyTarget' is a live attached object.
    aiRole.script:209       AIFollowerRole.OnRoleSet(owner) is the ONLY thing that sets that argument
                            — plus the "Follower" sense preset, the follow-target squads, the
                            TargetTracking.FollowerPreset and the FollowerDamage status effect.
    aiComponent.script:468  OnRoleSet is reached through OnAIRoleChanged, which the engine fires off
                            SetAIRole / OnAttach — NOT off a queued AIAssignRoleCommand.
    aiComponent.script:486  AIHumanComponent.SetCurrentRole is the engine's own entry point: SetAIRole,
                            SetSenseObjectType(Follower), ResetCompanionRoleCacheTimeStamp, and a
                            queued NPCRoleChangeEvent.
    NPCPuppet.script:303    IsPlayerCompanion is CACHED for ten seconds. Skip the cache reset and a
                            fresh companion can read as "not a companion" long after the role is on.

  ⚠️ The whole point: "the role was assigned" is not the same as "they follow", and the call that
  assigns it returns success either way. Nothing here trusts a return value — Native.followerVerdict
  asks the ENGINE, and init.lua's watchdog re-applies until the engine agrees.

  ---------------------------------------------------------------------------
  CONTRACT
  ---------------------------------------------------------------------------
  Every function is pcall-guarded and returns a falsy value rather than throwing. A missing or renamed
  engine method degrades one feature; it never takes the mod down.
]]

local Native = {}

Native.VERSION = "1.67"

-- init.lua injects its logger so this module has no dependency on the file it lives beside.
local log = function() end
function Native.bind(fns)
  fns = fns or {}
  if type(fns.log) == "function" then log = fns.log end
end

-- ---------------------------------------------------------------------------
-- 2. FOLLOWER ROLE  (rewritten v1.65 — "they spawned but stayed planted")
-- ---------------------------------------------------------------------------
-- v1.64 assigned an AIFollowerRole through `AIAssignRoleCommand` and called it done. In game the
-- companion spawned, looked right, and NEVER MOVED. The decompiled scripts say exactly why, and it
-- is worth writing down because "the role is set" is NOT what makes an NPC follow:
--
--   aiComponent.script:520  AIHumanComponent.IsPlayerCompanion() returns true only if
--                           (a) GetAIRole().GetRoleEnum() == EAIRole.Follower  AND
--                           (b) the behaviour argument 'FriendlyTarget' is a live, attached object.
--   aiRole.script:209       AIFollowerRole.OnRoleSet(owner) is the ONLY thing that sets that
--                           argument — along with the "Follower" sense preset, the follow-target
--                           squads, the TargetTracking.FollowerPreset and the FollowerDamage effect.
--                           No OnRoleSet, no FriendlyTarget, and the follow behaviour has nobody to
--                           follow. That is the planted companion, precisely.
--   aiComponent.script:468  OnRoleSet is reached via OnAIRoleChanged, which the engine fires off
--                           SetAIRole / OnAttach — NOT off a queued AIAssignRoleCommand.
--
-- So the command form set a role object and skipped every consequence of setting it. (Night City
-- Allies uses the command form successfully — but its NPCs also go through
-- NPCPuppet.ChangeHighLevelState + its own per-frame tick, NpcHandle.reds:113. We had neither.)
--
-- THE ENGINE'S OWN PATH is the static `AIHumanComponent.SetCurrentRole` (aiComponent.script:486):
-- SetAIRole, then SetSenseObjectType(Follower), then ResetCompanionRoleCacheTimeStamp, then a
-- queued NPCRoleChangeEvent. The last two matter more than they look: NPCPuppet.script:303 caches
-- IsPlayerCompanion for TEN SECONDS, so without the reset a companion can read as "not a companion"
-- long after the role is on — which is its own class of "it works, eventually, sometimes".
--
-- Order below: engine path -> AMM's proven direct form -> the v1.64 command form. Each is verified,
-- not assumed (see Native.followerVerdict) — the whole bug was a call that returned success.

-- What the ENGINE thinks, asked fresh. `role` = the follower role is on; `companion` = the game
-- itself would answer IsPlayerCompanion() true, which is the one that gates following, enemies
-- ignoring them, and the minimap symbol. Diagnostics and the re-apply tick both read this.
function Native.followerVerdict(handle)
  local role, companion = false, false
  if not handle then return role, companion end
  pcall(function()
    local ai = handle:GetAIControllerComponent(); if not ai then return end
    local r = ai:GetAIRole()
    if r then
      local e; pcall(function() e = r:GetRoleEnum() end)
      -- Compare by name: the enum marshals as a userdata/number depending on the CET build, and a
      -- wrong-type compare here would silently report "no role" on a perfectly good companion.
      role = (e ~= nil) and (tostring(e):find("Follower") ~= nil)
    end
    pcall(function() companion = ai:IsPlayerCompanion() and true or false end)
  end)
  return role, companion
end

-- Make `handle` a genuine player companion. Returns true only if the engine AGREES afterwards.
function Native.setCompanion(handle)
  if not handle then return false end

  -- Level-scale first, so a companion spawned in a high-level district isn't a paper target.
  -- (AMM does this too — NPCManager:ScaleToPlayer, Modules/spawn.lua:697.)
  pcall(function()
    local m = handle.NPCManager
    if m and m.ScaleToPlayer then m:ScaleToPlayer() end
  end)

  -- Out of any leftover combat/alert state first. AIFollowerRole.OnRoleSet only requests the
  -- "Follower" sense preset when the puppet is NOT in Combat (aiRole.script:229), so a body that
  -- spawned alerted would take the role and still behave like a stranger. NC Allies does this too,
  -- before it attaches its follow behaviour (NpcHandle.reds:113).
  pcall(function()
    if NPCPuppet and NPCPuppet.ChangeHighLevelState then
      NPCPuppet.ChangeHighLevelState(handle, gamedataNPCHighLevelState.Relaxed)
    end
  end)

  -- A DES-spawned body arrives with whatever role its archetype gave it. Assigning over the top
  -- leaves the old role's package applied; AMM clears it first (Modules/spawn.lua) and so do we.
  pcall(function()
    local ai = handle:GetAIControllerComponent(); if not ai then return end
    local cur = ai:GetAIRole()
    if cur and cur.OnRoleCleared then cur:OnRoleCleared(handle) end
  end)

  local function freshRole()
    local role = AIFollowerRole.new()
    -- The role has to point at V. `#player` is the engine's own self-resolving reference; a raw
    -- entity ID goes stale across a load, this doesn't.
    local ref = Game.CreateEntityReference("#player", {})
    if role.SetFollowerRef then pcall(function() role:SetFollowerRef(ref) end)
    else pcall(function() role.followerRef = ref end) end
    return role
  end

  local how = nil

  -- 1. THE ENGINE'S OWN PATH (aiComponent.script:486). Does SetAIRole + SetSenseObjectType(Follower)
  --    + ResetCompanionRoleCacheTimeStamp + the NPCRoleChangeEvent, which is the full set.
  pcall(function()
    if AIHumanComponent and AIHumanComponent.SetCurrentRole then
      AIHumanComponent.SetCurrentRole(handle, freshRole())
      how = "SetCurrentRole"
    end
  end)

  -- 2. AMM's direct form — proven in game for exactly our spawn path. SetAIRole then OnAttach:
  --    OnAttach re-reads the role and drives OnAIRoleChanged -> OnRoleSet (aiComponent.script:247).
  if not select(1, Native.followerVerdict(handle)) then
    pcall(function()
      local ai = handle:GetAIControllerComponent(); if not ai then return end
      ai:SetAIRole(freshRole())
      ai:OnAttach()
      how = "SetAIRole+OnAttach"
    end)
    -- The two bookkeeping steps SetCurrentRole would have done for us. Without the cache reset the
    -- game can answer IsPlayerCompanion() from a stale `false` for up to 10 s (NPCPuppet.script:303).
    pcall(function() handle:SetSenseObjectType(gamedataSenseObjectType.Follower) end)
    pcall(function() handle:ResetCompanionRoleCacheTimeStamp() end)
    pcall(function()
      handle.isPlayerCompanionCached = true
      handle.isPlayerCompanionCachedTimeStamp = 0
    end)
  end

  -- 3. The v1.64 command form, last. It is what Night City Allies uses, so it is not wrong — it is
  --    just not sufficient on its own, which is the entire lesson of this bug.
  if not select(1, Native.followerVerdict(handle)) then
    pcall(function()
      local ai = handle:GetAIControllerComponent(); if not ai then return end
      local cmd = NewObject('handle:AIAssignRoleCommand')
      if not cmd then return end
      cmd.role = freshRole()
      ai:SendCommand(cmd)
      how = "AIAssignRoleCommand"
    end)
  end

  -- Ally attitude. Two separate things and both are needed: the GROUP makes the world's factions
  -- treat them as V's, the TOWARDS makes them personally friendly to V.
  pcall(function()
    local pl = Game.GetPlayer(); if not pl or not handle.GetAttitudeAgent then return end
    local mine, theirs = handle:GetAttitudeAgent(), pl:GetAttitudeAgent()
    if not (mine and theirs) then return end
    mine:SetAttitudeGroup(theirs:GetAttitudeGroup())
    mine:SetAttitudeTowards(theirs, EAIAttitude.AIA_Friendly)
  end)

  local role, companion = Native.followerVerdict(handle)
  if role then
    log(("Native.setCompanion: follower role ON via %s (engine says companion=%s).")
        :format(tostring(how), tostring(companion)))
  else
    log("Native.setCompanion: FAILED to assign the follower role (all three forms). " ..
        "They will spawn and stand still — report this with the log.")
  end
  return role
end

-- Drop the follower role (used when a companion goes passive — idle placement, dinner, dismissal).
-- AINoRole is the engine's explicit "no role" marker; clearing to nil leaves the AI in a bad state.
function Native.clearCompanion(handle)
  if not handle then return false end
  local ok = false
  pcall(function()
    local ai = handle:GetAIControllerComponent(); if not ai then return end
    local cmd = NewObject('handle:AIAssignRoleCommand')
    if not cmd then return end
    cmd.role = AINoRole.new()
    ai:SendCommand(cmd)
    ok = true
  end)
  return ok
end

return Native
