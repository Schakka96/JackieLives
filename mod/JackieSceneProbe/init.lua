--[[
  JackieSceneProbe — Track A: can we make a SPAWNED Jackie speak a SPECIFIC line by its
  VO string id, WITH the game's own baked lipsync, WITHOUT authoring a .scene file?

  Test line: "Ka-ching, baby!"  string_id = 1927336253241237504  lipsync = f_1ABF461C612D2000
             vo_wem = base/localization/.../jackie_q005_..._1abf461c612d2000.wem

  Strategy (same workflow that cracked the native phone system):
    STEP 1 — DUMP. Reflection-dump every candidate scene / voiceset / dialog / VO class so we
             learn the REAL method names + signatures on THIS patch. Written to scene_methods.txt.
             Also dumps the methods of gameObject / NPCPuppet / scnVoicesetComponent (the most
             likely places a "play this line id with lipsync" entry point lives), and what
             components we can find on the looked-at Jackie.
    STEP 2 — ATTEMPT. A few cheap best-guess "play the line" calls on the looked-at Jackie, each
             wrapped in pcall, ok/err logged to scene_attempts.txt. These are PLACEHOLDERS — after
             you paste scene_methods.txt back, the real call gets wired here with correct names.

  HOW TO USE: summon Jackie (AMM), stand close, LOOK AT him, open this overlay (CET hotkeys/overlay),
  press "1) DUMP scene/VO reflection", then press the attempt buttons and WATCH/LISTEN.
  Both .txt files land in this mod's folder:
    <game>\bin\x64\plugins\cyber_engine_tweaks\mods\JackieSceneProbe\
  Paste scene_methods.txt (and note what each attempt did) back to Claude.

  Console tag: [JKScn].
--]]

local LINE = {
  text     = "Ka-ching, baby!",
  stringId = "1927336253241237504",     -- VO String ID (decimal, as scraped)
  lipsync  = "f_1ABF461C612D2000",      -- baked facial-anim token (== wem hash)
  wemStem  = "jackie_q005_f_1abf461c612d2000",
}

local UI = { open = true, overlay = false, status = "" }
local function log(m) print("[JKScn] " .. tostring(m)) end

-- ── target: the NPC the player is looking at (summon Jackie, aim at him) ──────────────
local function lookAtTarget()
  local p = Game.GetPlayer(); if not p then return nil end
  local t
  pcall(function()
    local ts = Game.GetTargetingSystem()
    if ts then t = ts:GetLookAtObject(p, false, false) end
  end)
  return t
end

-- ── reflection helpers (mirror JackieLives dumpPhoneReflection) ───────────────────────
-- CET serializes CName as: ToCName{...--[[ ReadableName --]] }. Pull the readable part out.
local function readable(x)
  local s = tostring(x)
  local r = s:match("%-%-%[%[%s*(.-)%s*%-%-%]%]")
  return r or s
end
local function methodName(m)
  local nm
  pcall(function() nm = m:GetFullName() end)   -- includes param/return types — what we want
  if not nm then pcall(function() nm = m:GetName() end) end
  return readable(nm)
end

-- Full, UNFILTERED method list for one class (the over-filter hid scnVoicesetComponent's 1 method).
local function dumpClassFull(cn, w)
  local cls; pcall(function() cls = Reflection.GetClass(cn) end)
  if not cls then w("=== " .. cn .. " : CLASS NOT FOUND ==="); w(""); return end
  local parent = "?"; pcall(function() local p = cls:GetParent(); if p then parent = readable(p:GetName()) end end)
  w("=== " .. cn .. "  (parent: " .. parent .. ")  [ALL METHODS] ===")
  local methods; pcall(function() methods = cls:GetMethods() end)
  if not methods then pcall(function() methods = cls:GetFunctions() end) end
  if methods then
    for _, m in ipairs(methods) do w("    " .. methodName(m)) end
    w("    (total: " .. #methods .. ")")
  else w("    (could not list methods)") end
  w("")
end

-- Global (static) functions — PlayVoiceOver lives here, NOT on gameObject:GetMethods().
local function dumpGlobals(w)
  w("=== GLOBAL FUNCTIONS (voice/vo/dialog/line/speak/play/scene) ===")
  local fns
  for _, getter in ipairs({ "GetGlobalFunctions", "GetFunctions" }) do
    if not fns then pcall(function() fns = Reflection[getter] and Reflection[getter]() end) end
  end
  if not fns then w("    (no global-function accessor on Reflection — Codeware version?)"); w(""); return end
  local hits = 0
  for _, fn in ipairs(fns) do
    local nm = methodName(fn); local low = nm:lower()
    if low:find("voiceover") or low:find("voiceset") or low:find("dialog") or low:find("speak")
       or low:find("playvo") or low:find("playline") or low:find("scnplay") or low:find("playdialog") then
      w("    " .. nm); hits = hits + 1
    end
  end
  w("    (matched " .. hits .. " of " .. #fns .. " globals)")
  w("")
end

-- Candidate classes. Unknowns are fine — "CLASS NOT FOUND" tells us which names are real.
local PROBE_CLASSES = {
  -- scene system + playback
  "scnSceneSystem", "gameSceneSystem", "scnISceneSystem",
  "scnSceneInstance", "scnInteractiveSceneInstance", "scnSceneWorkspotInstance",
  -- voiceset / voice
  "scnVoicesetComponent", "scnVoiceComponent", "gameVoiceManager", "VoiceManager",
  -- audio side
  "AudioSystem", "gameaudioSoundSystem", "gameaudioeventsPlayVoiceOver",
  "gameaudioeventsVoiceEvent", "gameaudioeventsVoicePlayedEvent", "audioPlayVoiceOver",
  -- dialog line data / events
  "scnDialogLineData", "scnDialogLineEvent", "scnPlayVoiceEvent", "scnPlaySkAnimEvent",
  "scnscreenplayDialogLine", "scnscreenplayStore", "scnscreenplayItemId",
  -- the puppet itself (we KNOW PlayVoiceOver lives on gameObject)
  "gameObject", "NPCPuppet", "gamePuppet", "gamePuppetBase",
  -- localization (stringId -> line)
  "LocalizationManager", "gameuiLocalizationManager", "gameLocalizationSystem",
}

local function dumpReflection()
  if not Reflection then
    UI.status = "Codeware Reflection global missing — is Codeware loaded?"; log(UI.status); return
  end
  local out, n = {}, 0
  local function w(s) n = n + 1; out[n] = tostring(s) end

  w("# JackieSceneProbe reflection dump")
  w("# test line: \"" .. LINE.text .. "\"  stringId=" .. LINE.stringId .. "  lipsync=" .. LINE.lipsync)
  w("")

  for _, cn in ipairs(PROBE_CLASSES) do
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
        for _, m in ipairs(methods) do
          local nm = methodName(m)
          -- keep the signal high: only methods that look line/voice/dialog/anim/play related
          local low = nm:lower()
          if low:find("voice") or low:find("dialog") or low:find("line") or low:find("play")
             or low:find("speak") or low:find("scene") or low:find("lipsync") or low:find("vo")
             or low:find("anim") or low:find("sound") or low:find("audio") then
            w("    " .. nm)
          end
        end
        w("    (… full method count: " .. tostring(#methods) .. " — filtered above to voice/line/play/etc.)")
      else
        w("    (could not list methods)")
      end
    end
    w("")
  end

  -- What can we see on the looked-at Jackie right now?
  w("=== LIVE TARGET (look-at) ===")
  local npc = lookAtTarget()
  if not npc then
    w("    no look-at target — aim at summoned Jackie and re-run the dump")
  else
    local cn = "?"; pcall(function() cn = tostring(npc:GetClassName()) end)
    w("    target class: " .. cn)
    -- try to fetch likely components by name
    local compNames = { "voiceset", "VoiceSet", "scnVoicesetComponent", "VoicesetComponent",
                        "voice", "face_rig", "AnimationController" }
    for _, c in ipairs(compNames) do
      local comp
      pcall(function() comp = npc:FindComponentByName(CName.new(c)) end)
      if comp then
        local ccn = "?"; pcall(function() ccn = tostring(comp:GetClassName()) end)
        w("    FOUND component '" .. c .. "' -> " .. ccn)
      end
    end
  end
  w("")

  local f = io.open("scene_methods.txt", "w")
  if f then f:write(table.concat(out, "\n")); f:close()
    UI.status = "Wrote scene_methods.txt (" .. n .. " lines). Paste it to Claude."
  else
    UI.status = "ERROR: could not open scene_methods.txt for writing."
  end
  log(UI.status)
end

-- Focused FULL dump: every method of the key small classes + matching globals -> scene_full.txt
local FULL_CLASSES = {
  "scnVoicesetComponent",            -- the 1 method we MUST see
  "scnSceneSystem", "scnISceneSystem",
  "scnDialogLineEvent", "scnDialogLineData",
  "ScriptedPuppet", "NPCPuppet",
  "AIHumanComponent",
}
local function dumpFull()
  if not Reflection then UI.status = "Reflection missing — Codeware loaded?"; log(UI.status); return end
  local out, n = {}, 0
  local function w(s) n = n + 1; out[n] = tostring(s) end
  w("# JackieSceneProbe FULL dump (key classes, unfiltered, + globals)")
  w("")
  dumpGlobals(w)
  for _, cn in ipairs(FULL_CLASSES) do dumpClassFull(cn, w) end
  -- also: the live look-at target's exact class, dumped in full
  local npc = lookAtTarget()
  if npc then
    local cn = readable(npc:GetClassName())
    w("=== LIVE TARGET class full dump ===")
    dumpClassFull(cn, w)
    -- and the voiceset component instance's class
    local comp; pcall(function() comp = npc:FindComponentByName(CName.new("VoicesetComponent")) end)
    if comp then dumpClassFull(readable(comp:GetClassName()), w) end
  else
    w("(no look-at target — aim at Jackie for the live-class dump)")
  end
  local f = io.open("scene_full.txt", "w")
  if f then f:write(table.concat(out, "\n")); f:close()
    UI.status = "Wrote scene_full.txt (" .. n .. " lines). Paste it to Claude."
  else UI.status = "ERROR: could not write scene_full.txt." end
  log(UI.status)
end

-- ── attempts (placeholders, refined after we read the dump) ───────────────────────────
local function attemptLog(tag, ok, extra)
  local line = ("%s  ok=%s%s"):format(tag, tostring(ok), extra and ("  | " .. extra) or "")
  log("ATTEMPT " .. line)
  local f = io.open("scene_attempts.txt", "a")
  if f then f:write(line .. "\n"); f:close() end
  UI.status = line
end

-- A1: PlayVoiceOver, but feed the line's identifiers as the first CName instead of a context
--     token. Long shot (the known signature wants a voiceset CONTEXT), but free to try and tells
--     us if the VO event resolver accepts a raw id / hash / wem stem.
local function attemptPlayVoiceOverByIds()
  local npc = lookAtTarget()
  if not npc then attemptLog("A1 PlayVoiceOver", false, "NO look-at target — aim at Jackie"); return end
  pcall(function()
    local stim = npc:GetStimReactionComponent()
    if stim then stim:ActivateReactionLookAt(Game.GetPlayer(), false, 1, true, true) end
  end)
  local tries = { LINE.stringId, LINE.lipsync, LINE.wemStem, "vo_" .. LINE.stringId }
  for _, tok in ipairs(tries) do
    local ok = pcall(function()
      Game["gameObject::PlayVoiceOver;GameObjectCNameCNameFloatEntityIDBool"](
        npc, CName.new(tok), CName.new(""), 1, npc:GetEntityID(), true)
    end)
    attemptLog("PlayVoiceOver tok='" .. tok .. "'", ok, "watch mouth/listen")
  end
end

-- A2: locate the voiceset component on Jackie and report it (so we know it's reachable);
--     real play-by-id call gets wired after we read its method list from the dump.
local function attemptFindVoiceset()
  local npc = lookAtTarget()
  if not npc then attemptLog("A2 FindVoiceset", false, "NO look-at target — aim at Jackie"); return end
  local found = {}
  for _, c in ipairs({ "voiceset", "VoiceSet", "scnVoicesetComponent", "VoicesetComponent", "voice" }) do
    local comp; pcall(function() comp = npc:FindComponentByName(CName.new(c)) end)
    if comp then
      local ccn = "?"; pcall(function() ccn = tostring(comp:GetClassName()) end)
      found[#found + 1] = c .. "->" .. ccn
    end
  end
  attemptLog("FindVoiceset", #found > 0, #found > 0 and table.concat(found, ", ") or "none found by name")
end

-- ── CET wiring ───────────────────────────────────────────────────────────────────────
registerForEvent("onInit", function()
  -- fresh attempts log each load
  local f = io.open("scene_attempts.txt", "w")
  if f then f:write("# scene play attempts (tag  ok=..  | note)\n"); f:close() end
  log("Loaded. Summon Jackie, look at him, press '1) DUMP', then the attempt buttons.")
end)
registerForEvent("onOverlayOpen",  function() UI.overlay = true end)
registerForEvent("onOverlayClose", function() UI.overlay = false end)

registerForEvent("onDraw", function()
  if not UI.overlay or not UI.open then return end
  ImGui.Begin("Jackie Scene Probe")
  local npc = lookAtTarget()
  ImGui.Text("Look-at: " .. (npc and "Jackie ok" or "none — aim at Jackie"))
  ImGui.Text('Line: "' .. LINE.text .. '"')
  ImGui.Text("stringId: " .. LINE.stringId)

  ImGui.Separator()
  ImGui.Text("STEP 1 — discover the API:")
  if ImGui.Button("1) DUMP scene/VO reflection -> scene_methods.txt") then dumpReflection() end
  if ImGui.Button("1b) FULL dump key classes + globals -> scene_full.txt") then dumpFull() end

  ImGui.Separator()
  ImGui.Text("STEP 2 — best-guess attempts (watch mouth / listen):")
  if ImGui.Button("A1: PlayVoiceOver by id/hash/stem") then attemptPlayVoiceOverByIds() end
  if ImGui.Button("A2: find voiceset component on Jackie") then attemptFindVoiceset() end

  ImGui.Separator()
  if UI.status ~= "" then ImGui.TextWrapped("> " .. UI.status) end
  ImGui.End()
end)

registerHotkey("jkscn_dump", "SceneProbe: DUMP reflection", function() dumpReflection() end)
registerHotkey("jkscn_full", "SceneProbe: FULL dump", function() dumpFull() end)
registerHotkey("jkscn_a1",   "SceneProbe: A1 PlayVoiceOver", function() attemptPlayVoiceOverByIds() end)
registerHotkey("jkscn_a2",   "SceneProbe: A2 find voiceset", function() attemptFindVoiceset() end)
