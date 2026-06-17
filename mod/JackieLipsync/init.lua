--[[
  JackieLipsync — mouth-flap test bench (standalone; no clash with the main mod).

  Two mechanisms, both via AMM's proven calls on a look-at NPC (summon Jackie, look AT him):

  (1) REAL VO + REAL lipsync  — PlayVoiceOver(context). The chosen design direction: convert
      dialogue to voiceset CONTEXT tokens where possible (real voice + baked lipsync, game assets).
      "greeting" confirmed working. Cycle "Talk: next context" to find which contexts Jackie answers.

  (2) FACIAL-ONLY flap (no audio) — ApplyFeature(AnimFeature_FacialReaction, {category, idle}).
      For testing AMM Expressions Overhaul's "Talking" facial anims as a flap over our Audioware
      lines. SWEEP category/idle, watch the mouth (NO VO fires here). When a pair moves the mouth,
      note category+idle. "Loop re-apply" restarts it every interval so a short anim sustains across
      a whole line. ResetFacial clears it.

  Console: [JKLip].
--]]

local UI = { open = true, overlay = false, status = "", ctxIdx = 0,
             cat = 7, idle = 231, loop = false, shuffle = false, interval = 0.6 }
local clock, lastApply = 0, -999
local function log(m) print("[JKLip] " .. tostring(m)) end

-- voiceset CONTEXT tokens (mechanism 1). "greeting" confirmed; rest are candidates.
local CONTEXTS = {
  "greeting", "goodbye", "agree", "disagree", "refuse", "question", "thankful",
  "curious", "afraid", "fear", "pain", "taunt", "alerted", "combat", "idle",
}

-- AMM Expressions Overhaul "Talking" facial anims (read from Collabs/Extra_Expressions_AMM.lua):
-- category 7, idle 231..266 (242 intentionally skipped). 36 talking faces to shuffle for the flap.
local TALKING_CAT = 7
local TALKING_IDLES = {}
for i = 231, 266 do if i ~= 242 then TALKING_IDLES[#TALKING_IDLES + 1] = i end end
local function randTalkingIdle()
  if #TALKING_IDLES == 0 then return 231 end
  return TALKING_IDLES[math.random(1, #TALKING_IDLES)]
end

local function lookAtTarget()
  local p = Game.GetPlayer(); if not p then return nil end
  local t
  pcall(function()
    local ts = Game.GetTargetingSystem()
    if ts then t = ts:GetLookAtObject(p, false, false) end
  end)
  return t
end

-- (1) AMM Util:NPCTalk — VO drives visemes (real lipsync) + facial overlay.
local function talk(ctx)
  local npc = lookAtTarget()
  if not npc then UI.status = "Look AT Jackie first."; log(UI.status); return end
  local stim, anim
  pcall(function() stim = npc:GetStimReactionComponent() end)
  pcall(function() anim = npc:GetAnimationControllerComponent() end)
  pcall(function() if stim then stim:ActivateReactionLookAt(Game.GetPlayer(), false, 1, true, true) end end)
  local vook = pcall(function()
    Game["gameObject::PlayVoiceOver;GameObjectCNameCNameFloatEntityIDBool"](
      npc, CName.new(ctx), CName.new(""), 1, npc:GetEntityID(), true)
  end)
  pcall(function()
    if anim then
      local f = NewObject("handle:AnimFeature_FacialReaction")
      pcall(function() f.category = UI.cat end); pcall(function() f.idle = UI.idle end)
      anim:ApplyFeature(CName.new("FacialReaction"), f)
    end
  end)
  UI.status = "VO ctx='" .. ctx .. "' (ok=" .. tostring(vook) .. ") — mouth + voice?"
  log(UI.status)
end

local function talkNext()
  if #CONTEXTS == 0 then return end
  UI.ctxIdx = (UI.ctxIdx % #CONTEXTS) + 1
  talk(CONTEXTS[UI.ctxIdx])
  UI.status = string.format("[%d/%d] ctx='%s' — works? (mouth + voice)", UI.ctxIdx, #CONTEXTS, CONTEXTS[UI.ctxIdx])
end

-- (2) facial overlay ONLY, no VO — for sweeping the Expressions Overhaul "Talking" anims.
local function applyFacial(cat, idle)
  local npc = lookAtTarget()
  if not npc then UI.status = "Look AT Jackie first."; log(UI.status); return false end
  local ok = pcall(function()
    local anim = npc:GetAnimationControllerComponent()
    local f = NewObject("handle:AnimFeature_FacialReaction")
    pcall(function() f.category = cat end); pcall(function() f.idle = idle end)
    anim:ApplyFeature(CName.new("FacialReaction"), f)
  end)
  return ok
end

local function applyCurrent()
  local ok = applyFacial(UI.cat, UI.idle)
  UI.status = string.format("Facial cat=%d idle=%d (no VO, ok=%s) — mouth move?", UI.cat, UI.idle, tostring(ok))
  log(UI.status)
end

local function resetFacial()
  local npc = lookAtTarget(); if not npc then return end
  pcall(function() local s = npc:GetStimReactionComponent(); if s then s:ResetFacial(0); s:DeactiveLookAt(false) end end)
  UI.loop, UI.shuffle = false, false
  UI.status = "Facial reset."
  log(UI.status)
end

registerForEvent("onInit",         function() log("Loaded. Summon Jackie, look at him.") end)
registerForEvent("onOverlayOpen",  function() UI.overlay = true end)
registerForEvent("onOverlayClose", function() UI.overlay = false end)

-- one-click talking flap: shuffle random "Talking" faces (cat 7) for a duration.
local function talkingFlapStart()
  UI.loop, UI.shuffle = true, true
  UI.status = "Talking flap ON (shuffling cat 7 faces). Watch his mouth; Reset to stop."
  log(UI.status)
end

-- loop re-apply so a short 'talking' facial anim sustains across a whole line
registerForEvent("onUpdate", function(dt)
  clock = clock + dt
  if UI.loop and (clock - lastApply) >= (UI.interval or 0.6) then
    lastApply = clock
    if UI.shuffle then applyFacial(TALKING_CAT, randTalkingIdle())
    else applyFacial(UI.cat, UI.idle) end
  end
end)

registerForEvent("onDraw", function()
  if not UI.overlay or not UI.open then return end
  ImGui.Begin("Jackie Lipsync")
  local npc = lookAtTarget()
  ImGui.Text("Look-at: " .. (npc and "Jackie ok" or "none — aim at Jackie"))

  ImGui.Separator()
  ImGui.Text("(1) REAL VO + lipsync (voiceset context):")
  if ImGui.Button("Talk: greeting") then talk("greeting") end
  ImGui.SameLine()
  if ImGui.Button("Talk: next context") then talkNext() end

  ImGui.Separator()
  ImGui.Text("(2a) TALKING FLAP — shuffle Overhaul 'Talking' faces (cat 7, NO VO):")
  if ImGui.Button("Talking flap: START (shuffle)") then talkingFlapStart() end
  ImGui.SameLine()
  if ImGui.Button("one random talking face") then local i = randTalkingIdle(); applyFacial(TALKING_CAT, i); UI.status = "talking idle=" .. i end
  UI.interval = ImGui.SliderFloat("shuffle interval (s)", UI.interval, 0.2, 1.5)

  ImGui.Separator()
  ImGui.Text("(2b) MANUAL sweep — NO VO (find/verify any category/idle):")
  ImGui.Text(string.format("category = %d", UI.cat))
  if ImGui.Button("cat -") then UI.cat = math.max(0, UI.cat - 1) end ImGui.SameLine()
  if ImGui.Button("cat +") then UI.cat = UI.cat + 1 end
  ImGui.Text(string.format("idle = %d", UI.idle))
  if ImGui.Button("idle -") then UI.idle = math.max(0, UI.idle - 1) end ImGui.SameLine()
  if ImGui.Button("idle +") then UI.idle = UI.idle + 1 end
  if ImGui.Button("Apply facial (no VO)") then applyCurrent() end
  ImGui.SameLine()
  if ImGui.Button("idle+ & apply") then UI.idle = UI.idle + 1; applyCurrent() end
  UI.loop = ImGui.Checkbox("Loop re-apply (sustain flap)", UI.loop)

  ImGui.Separator()
  if ImGui.Button("Reset facial") then resetFacial() end
  if UI.status ~= "" then ImGui.TextWrapped("> " .. UI.status) end
  ImGui.End()
end)

registerHotkey("jklip_talk",  "Lipsync: talk greeting", function() talk("greeting") end)
registerHotkey("jklip_next",  "Lipsync: next context",  function() talkNext() end)
registerHotkey("jklip_apply", "Lipsync: apply facial",  function() applyCurrent() end)
registerHotkey("jklip_idle",  "Lipsync: idle+ & apply", function() UI.idle = UI.idle + 1; applyCurrent() end)
registerHotkey("jklip_flap",  "Lipsync: talking flap",  function() talkingFlapStart() end)
registerHotkey("jklip_reset", "Lipsync: reset facial",  function() resetFacial() end)
