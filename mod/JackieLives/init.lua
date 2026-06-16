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
--]]

local Config = require("config")

local JL = {
  amm    = nil,
  jackie = { record = nil, name = nil },
  ui     = { open = true, overlayOpen = false, lastCapture = nil, forceMainQuest = false, status = "",
             voIndex = 0, voText = "" },
  summon = { spawn = nil, active = false, companionSet = false },
  idle   = { spawn = nil, locationKey = nil },
  arrival = { at = nil },   -- holocall: clock time at which a called-in Jackie spawns
  call    = { ringingAt = nil },  -- holocall: clock time he "picks up" after the ring
  timer  = 0,
  clock  = 0,        -- accumulated game seconds (for talk cooldowns)
  lastTalk = -999,
  lastSeen = -999,
}

local function log(msg) print("[JackieLives] " .. tostring(msg)) end

-- ---------------------------------------------------------------------------
-- AMM + Jackie record
-- ---------------------------------------------------------------------------
local function getAMM()
  if JL.amm == nil then JL.amm = GetMod("AppearanceMenuMod") end
  return JL.amm
end

local function getAMMCharacters()
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
local function discoverJackieFromSpawned(verbose)
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
local function diagnostics()
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
local function ammSpawn(companionFlag)
  local amm = getAMM()
  if not amm or not amm.Spawn or not amm.Spawn.NewSpawn then return nil, "AMM Spawn module not available" end
  if not resolveJackieRecord() then return nil, "Jackie record not found" end
  local recStr = tostring(JL.jackie.record)
  if companionFlag == 1 then
    pcall(function() if amm.userSettings then amm.userSettings.spawnAsCompanion = true end end)
  end
  local spawn
  local ok = pcall(function()
    spawn = amm.Spawn:NewSpawn(JL.jackie.name or "Jackie", recStr, { app = "random" }, companionFlag, recStr)
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
  -- 2) delete the entity directly via the dynamic entity system (reliable)
  pcall(function()
    local h = spawn.handle
    if h and h.GetEntityID then
      local des = Game.GetDynamicEntitySystem()
      if des then des:DeleteEntity(h:GetEntityID()) end
    end
  end)
  -- 3) last resort
  pcall(function() if spawn.handle and spawn.handle.Dispose then spawn.handle:Dispose() end end)
end

-- ---------------------------------------------------------------------------
-- Main-quest ban (MVP stub — real detection comes once we read quest IDs in-game)
-- ---------------------------------------------------------------------------
local function isMainQuestActive()
  if JL.ui.forceMainQuest then return true end
  return false
end

-- ---------------------------------------------------------------------------
-- Summon / dismiss
-- ---------------------------------------------------------------------------
local function summonJackie()
  if isMainQuestActive() then JL.ui.status = Config.declineLine; log(Config.declineLine); return end
  if JL.summon.active then JL.ui.status = "Jackie is already with you."; return end
  local spawn, err = ammSpawn(1)
  if not spawn then JL.ui.status = "Summon failed: " .. tostring(err); log("Summon failed: " .. tostring(err)); return end
  JL.summon.spawn, JL.summon.active, JL.summon.companionSet = spawn, true, false
  JL.ui.status = "Summoning Jackie..."
  log("Summon requested.")
end

local function dismissJackie()
  if JL.summon.spawn then ammDespawn(JL.summon.spawn) end
  JL.summon.spawn, JL.summon.active, JL.summon.companionSet = nil, false, false
  JL.ui.status = "Jackie dismissed."
  log("Dismissed.")
end

-- Despawn EVERY Jackie AMM knows about (clears orphans from failed dismisses / mod reloads).
local function dismissAllJackies()
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
  JL.summon.spawn, JL.summon.active, JL.summon.companionSet = nil, false, false
  JL.idle.spawn, JL.idle.locationKey = nil, nil
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
  if h then return h, "lookat" end
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

-- Play a named WWise event on Jackie (or on V, if the debug toggle is set).
local function playNamedEvent(name)
  if not name or name == "" then JL.ui.status = "No event name."; return end
  local emitter = (Config.talkTest and Config.talkTest.emitter) or ""
  local target, src
  if Config.talkTest and Config.talkTest.onPlayer then
    target, src = Game.GetPlayer(), "V"
  else
    target, src = getTalkTarget()   -- summoned/idle Jackie, else look-at, else player
  end
  local ok, err = playEventOn(target, name, emitter)
  if ok then
    JL.ui.status = "Played '" .. name .. "' on " .. tostring(src) .. " - listen!"
    log("VO: Play '" .. name .. "' on " .. tostring(src))
  else
    JL.ui.status = "VO failed: " .. tostring(err)
    log("VO failed: " .. tostring(err))
  end
end

-- Play the event currently selected in the dropdown.
local function playVO()
  local list = Config.jackieEvents or {}
  local name = list[(JL.ui.voIndex or 0) + 1] or (Config.talkTest and Config.talkTest.event)
  playNamedEvent(name)
end

local function playRandomJackieEvent()
  local list = Config.jackieEvents or {}
  if #list == 0 then return end
  JL.ui.voIndex = math.random(0, #list - 1)
  playNamedEvent(list[JL.ui.voIndex + 1])
end

-- ---------------------------------------------------------------------------
-- Time + position
-- ---------------------------------------------------------------------------
local function callMethod(obj, name)
  local r
  pcall(function() local f = obj[name]; if f then r = f(obj) end end)
  return r
end

local function getGameHour()
  local ts = Game.GetTimeSystem(); if not ts then return nil end
  local gt; pcall(function() gt = ts:GetGameTime() end)
  if gt == nil then return nil end
  -- direct hour methods
  for _, m in ipairs({ "GetHour", "GetHours" }) do
    local r = callMethod(gt, m)
    if type(r) == "number" then return r % 24 end
  end
  -- seconds-of-day methods
  for _, m in ipairs({ "ToSeconds", "GetSeconds", "GetTotalSeconds" }) do
    local r = callMethod(gt, m)
    if type(r) == "number" then return math.floor((r % 86400) / 3600) end
  end
  return nil
end

local function hourInBlock(h, s, e)
  if s <= e then return h >= s and h < e else return h >= s or h < e end
end

local function currentScheduleBlock()
  local h = getGameHour(); if not h then return nil, nil end
  for _, b in ipairs(Config.schedule) do
    if hourInBlock(h, b.startHour, b.endHour) then return b, h end
  end
  return nil, h
end

local function playerPos()
  local p = Game.GetPlayer(); if not p then return nil end
  return p:GetWorldPosition()
end

local function dist3(a, b)
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function capturePosition()
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
local Branch = { open = false }

-- Action names the interact / choice-confirm key (F by default) fires under. We accept
-- several because the exact CName varies by build; harmless extras just never match.
local INTERACT_ACTIONS = {
  ["Interact"] = true, ["Choice1"] = true, ["UI_Apply"] = true,
  ["click"] = false,                      -- (placeholder; mouse, ignore)
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

local function setupInteractHook()
  if interactHook.registered then return end
  local ok = pcall(function()
    Observe("PlayerPuppet", "OnAction", function(self, action, consumer)
      local name = actionName(action)
      if not actionJustPressed(action) then return end
      -- While a choice menu is open: log EVERY pressed action (so we can discover which
      -- CName each key fires on this build) and route the selection.
      if Branch.open then
        if INTERACT_ACTIONS[name] then pcall(function() Branch.confirm() end) end    -- F -> highlighted row
        return
      end
      if Config.talk and Config.talk.logActions then log("OnAction: " .. tostring(name)) end
      if not INTERACT_ACTIONS[name] then return end
      pcall(talkToJackie)                                  -- grunt (look/range/cooldown gated inside)
      if Branch.kick then pcall(function() Branch.kick() end) end  -- v0.23: F starts the branching convo
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
local function probeChoiceBoxAPI()
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
  choiceBox.shown = ok and pushed
  if choiceBox.shown then choiceBox.lastPush = JL.clock or 0 end
  log("choice box: show -> ok=" .. tostring(ok) .. " pushed=" .. tostring(pushed))
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

-- ---------------------------------------------------------------------------
-- NATIVE subtitles (v0.22): the REAL bottom subtitle band, via the UIGameData
-- blackboard fields ShowDialogLine / HideDialogLine. This is the exact path
-- Audioware uses internally (r6/scripts/Audioware/Codeware.reds -> PropagateSubtitle,
-- Callback.reds -> hide). Replaces the on-screen NOTIFICATION (the blue objective-style
-- field) for spoken dialogue, so lines render as proper subtitles at the bottom.
-- ---------------------------------------------------------------------------
local subtitle = { line = nil, seq = 700, warned = false }

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
  if ok then subtitle.line = line; return true end
  if not subtitle.warned then
    log("SUBTITLE push FAILED -> falling back to on-screen msg. Error: " .. tostring(err))
    subtitle.warned = true
  end
  return false
end

local function hideSubtitle()
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
local bstate = { node = nil, openAt = nil, pending = nil, pendingAt = nil }

-- Play a Jackie line: real voice (sfx, else the guaranteed jl_fallback WAV) + subtitle.
local function speakJackieLine(text, sfx)
  local spoke = false
  if sfx then spoke = playVoice(sfx) end
  if not spoke then spoke = playVoice("jl_fallback") end
  local secs = voiceDuration(sfx) or 3.0
  hideSubtitle()
  -- carrier entity for the subtitle band: Jackie if spawned, else the player (on a phone
  -- call Jackie isn't in the world yet, and a null speaker can make the band skip the line).
  showDialogueText("Jackie", text or "", secs + 0.6, dialogueTarget() or Game.GetPlayer())
  log("Branch: Jackie '" .. tostring(text) .. "' sfx=" .. tostring(sfx) .. " spoke=" .. tostring(spoke))
  return secs
end

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

local function drawDialogueBox()
  if not menu.shown or not menu.choices then return end
  local style = JL.ui.pickerStyle or 1
  local ok, err = pcall(function()
    ImGui.SetNextWindowPos(340, 360, ImGuiCond.Always)
    ImGui.SetNextWindowSize(620, 240, ImGuiCond.Always)   -- fixed (transparent) -> stable layout
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

local function openChoiceMenu(choices, title)
  menu.choices, menu.sel, menu.title = choices, 1, title or "Jackie"
  menu.shown, Branch.open = true, true
  log("Branch: menu open (" .. tostring(#choices) .. " choices). Cycle key=move, F=select.")
end

local function closeChoiceMenu()
  menu.shown, Branch.open, menu.choices = false, false, nil
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
  -- a node may give a single `jackie` line OR a `jackiePool` (array) we pick from at random
  local jline = node.jackie
  if node.jackiePool and #node.jackiePool > 0 then
    local i = 1; pcall(function() i = math.random(1, #node.jackiePool) end)
    jline = node.jackiePool[i]
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
  local hold = (Config.dialogue and Config.dialogue.choiceHold) or 2.5
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

-- start at the tree root if looking at Jackie (called from the F hook)
Branch.kick = function()
  if Branch.busy then return end
  if not lookedAtJackie() then return end
  Branch.start(nil, Config.dialogueTree)   -- always the talk tree, never a leftover call tree
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

-- Run an action attached to a finished call choice. "summon_arrival" -> schedule the
-- delayed spawn-at-distance (the actual spawn happens in arrivalTick).
local function runCallAction(name)
  if name ~= "summon_arrival" then return end
  if isMainQuestActive() then JL.ui.status = Config.declineLine; log(Config.declineLine); return end
  if JL.summon.active then JL.ui.status = "Jackie's already with you."; return end
  local delay = (Config.call and Config.call.spawnDelay) or 5.0
  JL.arrival.at = (JL.clock or 0) + delay
  JL.ui.status = ("Jackie's on his way (%.0fs)..."):format(delay)
  log("Call: arrival scheduled in " .. tostring(delay) .. "s.")
end

-- Begin a holocall. With useNativeWindow: fire the native RING (IncomingCall) now; callTick
-- then aborts it (STOP) and switches to the CONNECT window before running our convo.
local function startCall()
  if Branch.open or Branch.busy or dlg.active then JL.ui.status = "Busy - finish the current talk first."; return end
  if JL.summon.active then JL.ui.status = "Jackie's already with you."; return end
  if isMainQuestActive() then JL.ui.status = Config.declineLine; log(Config.declineLine); return end
  Branch.busy = true                       -- reserve so the look-prompt / talk don't fight the ring
  pcall(hideJackieChoiceBox)
  local id   = (Config.nativeCall and Config.nativeCall.id) or "jackie_dead"
  local ring = (Config.call and Config.call.ringEvent) or ""
  if ring ~= "" then pcall(function() playVoice(ring) end) end
  if Config.nativeCall and Config.nativeCall.useNativeWindow then
    triggerNativeCall(id, "IncomingCall", 1)   -- native ring (avatar + ringtone)
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
    local tree = Config.callTree
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
  if Branch.open or Branch.busy or dlg.active then return end   -- already talking
  if JL.summon.active then return end                          -- already with you
  if isMainQuestActive() then return end
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

-- Stepped from onUpdate. Two phases:
--  (1) at JL.arrival.at  -> spawn Jackie as a companion, then arm a teleport ~0.8s later.
--  (2) at JL.arrival.teleportAt -> teleport him to the distant arrival point (AMM has by
--      now finished placing him, so our teleport sticks); companion AI then walks him to V.
local function arrivalTick()
  if JL.arrival.at and (JL.clock or 0) >= JL.arrival.at then
    JL.arrival.at = nil
    local spawn, err = ammSpawn(1)
    if not spawn then JL.ui.status = "Arrival spawn failed: " .. tostring(err); log("Arrival spawn failed: " .. tostring(err)); return end
    JL.summon.spawn, JL.summon.active, JL.summon.companionSet = spawn, true, false
    JL.arrival.teleportAt = (JL.clock or 0) + 0.8
    JL.ui.status = "Jackie arriving - walking in."
    log("Call: Jackie spawned; teleport-to-distance armed (+0.8s).")
  end
  if JL.arrival.teleportAt and (JL.clock or 0) >= JL.arrival.teleportAt then
    JL.arrival.teleportAt = nil
    local h = JL.summon.spawn and JL.summon.spawn.handle
    if h then teleportEntity(h, arrivalPoint())
    else log("Call: arrival teleport skipped (no handle yet).") end
  end
end

-- stepped from onUpdate: (1) reveal the menu once Jackie's line has played; (2) after the
-- player's chosen line has shown ~1s, advance to the next node or end the conversation.
local function branchTick()
  if bstate.openAt and (JL.clock or 0) >= bstate.openAt then
    bstate.openAt = nil
    if bstate.node and bstate.node.choices then openChoiceMenu(bstate.node.choices, "Jackie") end
  end
  if bstate.pendingAt and (JL.clock or 0) >= bstate.pendingAt then
    bstate.pendingAt = nil
    local nxt = bstate.pending; bstate.pending = nil
    if nxt and nxt ~= "__end__" then
      Branch.start(nxt)
    else
      Branch.busy = false
      local wasCall = (bstate.tree == Config.callTree)
      bstate.tree = nil
      local act = bstate.pendingAction; bstate.pendingAction = nil
      if wasCall then
        -- end of a call strand: V's random sign-off shows, THEN we hang up (callTick.hangupAt)
        hideSubtitle()
        showDialogueText("V", pickFarewell(), 1.8, Game.GetPlayer())
        JL.call.hangupAction = act
        JL.call.hangupAt = (JL.clock or 0) + 1.8
        JL.ui.status = "Call wrapping up..."
      else
        hideSubtitle()
        JL.ui.status = "Dialogue ended."; log("Branch: end.")
        if act then pcall(function() runCallAction(act) end) end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Schedule tick (instant spawn/despawn MVP)
-- ---------------------------------------------------------------------------
local function clearIdle()
  if JL.idle.spawn then ammDespawn(JL.idle.spawn) end
  JL.idle.spawn, JL.idle.locationKey = nil, nil
end

local function scheduleTick()
  if JL.summon.active then clearIdle(); return end
  if not Config.enableSchedule then clearIdle(); return end

  local block = currentScheduleBlock()
  if not block or block.state ~= "at_location" then clearIdle(); return end

  local loc = Config.locations[block.locationKey]
  if not loc or not loc.pos then clearIdle(); return end

  local pp = playerPos(); if not pp then return end
  local near = dist3(pp, { x = loc.pos[1], y = loc.pos[2], z = loc.pos[3] }) <= Config.proximityRadius

  if near then
    if JL.idle.spawn and JL.idle.locationKey ~= block.locationKey then clearIdle() end
    if not JL.idle.spawn then
      local spawn, err = ammSpawn(0)
      if spawn then
        JL.idle.spawn, JL.idle.locationKey = spawn, block.locationKey
        log("Idle Jackie at " .. loc.name)
      else
        log("Idle spawn failed: " .. tostring(err))
      end
    end
  else
    clearIdle()
  end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
-- DEBUG (Config.probeNativePhone). Two parts, both writing to files in the mod folder so the
-- output can be read back without OCR / fragile console copy:
--  1) dumpPhoneReflection() -> uses Codeware's Reflection to write the REAL method names of the
--     phone/holocall classes to  phone_methods.txt  (so we stop guessing method names).
--  2) hooks that, when they fire, append to  probe_fires.txt  (open phone, call Jackie -> we see
--     exactly which methods drive the call).
local PROBE_CANDIDATE_CLASSES = {
  "PhoneSystem", "HolocallSystem",
  "PhoneDialerGameController", "PhoneDialerLogicController", "PhoneDialerNPCDataView",
  "PhoneConversationManager", "PhoneMessagePopupGameController",
  "gameuiHolocallReceiverGameController", "HolocallReceiverGameController",
  "ContactsListItemVirtualController", "gameuiContactsListGameController",
  "PhoneContactsManagerGameController", "JournalManager",
}

local function methodName(m)
  local nm
  pcall(function() nm = m:GetFullName() end)
  if not nm then pcall(function() nm = m:GetName() end) end
  return tostring(nm)
end

local function dumpPhoneReflection()
  if not Reflection then log("PROBE: Codeware Reflection global missing — is Codeware loaded?"); return end
  local out = {}
  local function w(s) out[#out + 1] = tostring(s) end
  for _, cn in ipairs(PROBE_CANDIDATE_CLASSES) do
    local cls
    pcall(function() cls = Reflection.GetClass(cn) end)
    if not cls then
      w("=== " .. cn .. " : CLASS NOT FOUND ===")
    else
      local parent = "?"
      pcall(function() local p = cls:GetParent(); if p then parent = tostring(p:GetName()) end end)
      w("=== " .. cn .. "  (parent: " .. parent .. ") ===")
      local methods
      pcall(function() methods = cls:GetMethods() end)
      if not methods then pcall(function() methods = cls:GetFunctions() end) end
      if methods then
        for _, m in ipairs(methods) do w("    " .. methodName(m)) end
      else
        w("    (could not list methods)")
      end
    end
    w("")
  end
  local f = io.open("phone_methods.txt", "w")
  if f then f:write(table.concat(out, "\n")); f:close(); log("PROBE: wrote phone_methods.txt (" .. #out .. " lines).")
  else log("PROBE: could not open phone_methods.txt for writing.") end
end

local function probeFire(tag, detail)
  local line = tag .. (detail and ("  | " .. detail) or "")
  log("PROBE FIRED  " .. line)
  local f = io.open("probe_fires.txt", "a")
  if f then f:write(("%.1f  %s\n"):format(JL.clock or 0, line)); f:close() end
end

-- Real method names (from phone_methods.txt). argfmt(self, ...) -> a string of captured args,
-- so we learn e.g. Jackie's call CName passed to TriggerCall. Uses Observe (before-call).
local function setupNativePhoneProbe()
  pcall(dumpPhoneReflection)
  local f = io.open("probe_fires.txt", "w")   -- truncate stale fires
  if f then f:write("# probe fires (t  Class::Method | args) - open phone, call Jackie\n"); f:close() end

  local function hook(cls, method, argfmt)
    local cb = function(self, ...)
      local detail
      if argfmt then local ok, d = pcall(argfmt, self, ...); if ok then detail = d end end
      probeFire(cls .. "::" .. method, detail)
    end
    pcall(function() Observe(cls, method, cb) end)
  end

  hook("PhoneSystem", "TriggerCall", function(self, a1, a2, a3, a4, a5, a6, a7, a8, a9)
    return ("args: %s | %s | %s | %s | %s | %s | %s | %s | %s"):format(
      tostring(a1), tostring(a2), tostring(a3), tostring(a4), tostring(a5),
      tostring(a6), tostring(a7), tostring(a8), tostring(a9))
  end)
  hook("PhoneSystem", "OnPickupPhone")
  hook("PhoneDialerGameController", "CallSelectedContact")
  hook("PhoneMessagePopupGameController", "TryCallContact")
  hook("PhoneMessagePopupGameController", "CallContact")
  log("PROBE armed (real names). Open phone, call Jackie -> probe_fires.txt.")
end

registerForEvent("onInit", function()
  getAMM()
  setupInteractHook()   -- v0.15: native F (Interact) triggers Talk-to-Jackie, no binding
  if Config.probeNativePhone then pcall(setupNativePhoneProbe) end
  pcall(setupCallHijack)   -- v0.30: player phone-calls to Jackie route into our flow
  log("Loaded v0.30. AMM present: " .. tostring(JL.amm ~= nil))
end)

-- Track overlay visibility so the window only shows while the CET overlay is open.
registerForEvent("onOverlayOpen",  function() JL.ui.overlayOpen = true end)
registerForEvent("onOverlayClose", function() JL.ui.overlayOpen = false end)

registerForEvent("onUpdate", function(dt)
  JL.clock = (JL.clock or 0) + dt
  pcall(updateTalkPrompt, dt)
  pcall(dialogueTick)
  pcall(branchTick)
  pcall(callTick)       -- holocall: ring -> pick up
  pcall(arrivalTick)    -- holocall: scheduled spawn-at-distance
  if JL.summon.spawn and JL.summon.spawn.handle and not JL.summon.companionSet then
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
    JL.ui.status = "Jackie is following."
    log("Companion role applied.")
  end

  JL.timer = JL.timer + dt
  if JL.timer >= Config.scheduleCheckInterval then
    JL.timer = 0
    pcall(scheduleTick)
  end
end)

registerForEvent("onDraw", function()
  pcall(drawDialogueBox)                      -- v0.24: the styled choice box draws DURING gameplay
  if not JL.ui.overlayOpen then return end   -- the debug window only draws while the overlay is open
  if not JL.ui.open then return end
  ImGui.Begin("Jackie Lives")

  local block, hour = currentScheduleBlock()
  ImGui.Text("AMM: " .. (JL.amm and "ok" or "MISSING") ..
             "   Jackie record: " .. (JL.jackie.record and "ok" or "?"))
  ImGui.Text("Game hour: " .. (hour and tostring(hour) or "?"))
  if block then
    if block.state == "at_location" then
      local loc = Config.locations[block.locationKey]
      ImGui.Text("Scheduled: " .. (loc and loc.name or block.locationKey) ..
                 ((loc and loc.pos) and "" or "  (coords NOT captured)"))
    else
      ImGui.Text("Scheduled: unavailable (asleep)")
    end
  end
  ImGui.Text("Companion: " .. tostring(JL.summon.active) ..
             "   Idle-spawned: " .. tostring(JL.idle.spawn ~= nil))
  ImGui.Separator()

  if ImGui.Button("Summon Jackie (companion)") then summonJackie() end
  ImGui.SameLine()
  if ImGui.Button("Dismiss Jackie") then dismissJackie() end
  if ImGui.Button("Call Jackie (holocall)") then startCall() end
  ImGui.SameLine()
  ImGui.TextWrapped("ring -> choices -> ask onto a gig -> he spawns at distance + walks in")

  ImGui.Separator()
  ImGui.Text("NATIVE phone test (drives the real call UI via PhoneSystem:TriggerCall):")
  ImGui.Text("Call id: '" .. tostring(Config.nativeCall and Config.nativeCall.id) .. "'  (edit Config.nativeCall.id)")
  local id = (Config.nativeCall and Config.nativeCall.id) or "jackie"
  if ImGui.Button("Native: RING (IncomingCall)") then triggerNativeCall(id, "IncomingCall", 1) end
  ImGui.SameLine()
  if ImGui.Button("Native: CONNECT (StartCall)") then triggerNativeCall(id, "StartCall", 2) end
  ImGui.SameLine()
  if ImGui.Button("Native: END (EndCall)") then triggerNativeCall(id, "EndCall", 3) end
  if ImGui.Button("Force hang up (clear stuck call)") then
    JL.call.nativeOpen = false
    triggerNativeCall(id, "EndCall", 3)
    triggerNativeCall("jackie", "EndCall", 3)   -- clear either call id
  end
  ImGui.TextWrapped("Click RING -> does Jackie's avatar + ringtone show? Then CONNECT -> does he appear " ..
                    "connected, and does the game play its OWN canned Jackie call, or stay silent (so we add ours)? END hangs up.")
  JL.ui.forceMainQuest = ImGui.Checkbox("Force main-quest active (test decline)", JL.ui.forceMainQuest)

  ImGui.Separator()
  if ImGui.Button("Capture current position") then capturePosition() end
  if JL.ui.lastCapture then
    ImGui.Text("Last capture (also in console — copy into config.lua):")
    ImGui.TextWrapped(JL.ui.lastCapture)
  end

  ImGui.Separator()
  ImGui.Text("ISOLATED UI TESTS (no Jackie / no audio - debug the two UI mechanisms):")
  if ImGui.Button("TEST: push subtitle (look at BOTTOM of screen)") then
    local ok = showSubtitle("SUBTITLE TEST - can you read this at the BOTTOM of the screen?", "JACKIE", 6.0, nil)
    JL.ui.status = "showSubtitle -> " .. tostring(ok) .. (ok and "  (pushed; if nothing shows, native subs may be OFF in settings)" or "  - SEE CONSOLE for the error")
  end
  ImGui.Text("Picker styles (click one - they differ in name-frame + highlight):")
  local function showPicker(styleN)
    JL.ui.pickerStyle = styleN
    openChoiceMenu({ { text = "Maelstrom - we gotta meet 'em." },
                     { text = "Been waitin' long?" },
                     { text = "What's the word on T-Bug?" } }, "JACKIE")
  end
  if ImGui.Button("testV1") then showPicker(1) end ImGui.SameLine()
  if ImGui.Button("testV2") then showPicker(2) end ImGui.SameLine()
  if ImGui.Button("testV3") then showPicker(3) end ImGui.SameLine()
  if ImGui.Button("hide picker") then closeChoiceMenu() end
  if menu.shown then
    if ImGui.Button("cycle (->)") then Branch.move(1) end
    ImGui.SameLine(); if ImGui.Button("select") then Branch.confirm() end
    ImGui.Text(("Showing style %d. Compare V1/V2/V3. Then CLOSE the overlay:"):format(JL.ui.pickerStyle or 1))
    ImGui.Text("if the box stays visible in gameplay -> render works; if it vanishes -> CET can't draw it in-game.")
  end

  ImGui.Separator()
  ImGui.Text("Dialogue (summon Jackie first so his voice plays on him):")
  if ImGui.Button("Play test dialogue (linear)") then startDialogue(Config.testDialogue) end
  ImGui.SameLine()
  if ImGui.Button("Play branching dialogue") then pcall(function() Branch.start(nil, Config.dialogueTree) end) end
  ImGui.TextWrapped("Branch: F=confirm highlighted choice; bind 'Jackie dialogue: next choice' to move highlight.")

  ImGui.Separator()
  Config.enableSchedule = ImGui.Checkbox("Enable schedule", Config.enableSchedule)
  if JL.ui.status ~= "" then ImGui.TextWrapped("> " .. JL.ui.status) end

  ImGui.End()
end)

registerForEvent("onShutdown", function()
  pcall(closeNativeCallWindow)   -- never leave a holocall window stuck open
  pcall(hideJackieChoiceBox)
  pcall(hideSubtitle)
  pcall(clearIdle)
  pcall(dismissJackie)
end)

registerHotkey("jl_summon",  "Summon Jackie",            function() summonJackie() end)
registerHotkey("jl_call",    "Call Jackie (holocall)",   function() startCall() end)
registerHotkey("jl_dismiss", "Dismiss Jackie",           function() dismissJackie() end)
registerHotkey("jl_capture", "Capture position",         function() capturePosition() end)
registerHotkey("jl_toggle",  "Show/Hide Jackie window",  function() JL.ui.open = not JL.ui.open end)
registerHotkey("jl_diag",    "Jackie diagnostics",       function() diagnostics() end)
registerHotkey("jl_votest",  "Jackie: play random voice", function() playRandomJackieEvent() end)

-- Bind a key in CET -> Bindings for this. Look at Jackie + press it -> he talks.
-- (Fallback key; CET can't bind F, so Antonia used "=". The OnAction hook below ALSO
--  gives the real in-game Interact key (F) for free - see setupInteractHook.)
registerInput("jl_talk", "Talk to Jackie (look at him)", function(isDown) if isDown then talkToJackie() end end)

-- Branch dialogue: move the highlighted choice down (wraps). Bind in CET -> Bindings to
-- a convenient key (e.g. mouse wheel down, or Tab). F confirms the highlighted option.
registerInput("jl_cycle_choice", "Jackie dialogue: next choice", function(isDown)
  if isDown then pcall(function() Branch.move(1) end) end
end)
