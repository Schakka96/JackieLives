--[[
  JackieAnimTest — body-animation LIBRARY BUILDER (standalone; never touches JackieLives).
  ----------------------------------------------------------------------------
  GOAL: press a button, a RANDOM body animation plays on Jackie, and its NAME prints to the
  console (tag [JKAnim]). When one looks good on him, hit "Save to library" and it's appended to
  jackie_anim_library.txt in this mod's folder — so you build a curated list by trial.

  HOW ANIMATIONS PLAY (verified against AMM source, patch 2.x):
    There is NO "play anim X on this NPC" one-liner. Body anims run through the WORKSPOT system:
    an invisible device entity carries a .workspot that loads an animset + lists clips by name.
    AMM's Poses tab already ships those device .ent files + a DB mapping every clip to its
    ent/comp/name/rig. So instead of reinventing the plumbing we drive AMM's own Poses module:
      * AMM.Poses:GetAllAnimations()            -> { {id,name,rig,comp,ent,fav}, ... }
      * AMM.Poses:PlayAnimationOnTarget(t,a,..)  -> spawns the device + jumps to a.name
      * Game.GetWorkspotSystem():StopInDevice(h) -> stop
    (AMM.Poses is reachable at runtime as GetMod("AppearanceMenuMod").Poses. It is NOT part of
    AMM.API — that only covers appearances — but the module itself is public.)

  HOW TO USE (Windows / in-game):
    1) Summon Jackie via AMM (or any spawned Jackie), stand a few metres away and LOOK AT him.
    2) Open the CET overlay -> "Jackie Anim Test" window (or use the hotkeys under CET > Bindings).
    3) Press "Play RANDOM anim". Watch Jackie + read the [JKAnim] line in the console.
    4) Good one? Press "Save current to library". Bad one? Just press Random/Next again.

  REQUIREMENTS / GOTCHAS (from the research):
    * AMM + Codeware must be loaded (they are, in this stack).
    * Jackie must be IDLE — unmounted, alive, not in combat/ragdoll — or the workspot is ignored.
    * A workspot snaps him to a fixed facing when a pose starts (the device faces him). Normal.
    * RIG must match: Jackie is a big male puppet, so records whose rig fits him work; wrong-rig
      picks do nothing / look broken — that's the trial signal. Once you learn his rig from the
      log, "Lock to this rig" filters the random pool to only matching anims.
    * No engine success flag: we probe IsActorInWorkspot ~0.4s after playing as a soft check;
      the ground truth is your eyes.

  Console tag: [JKAnim].
--]]

local UI = { open = true, overlay = false, status = "" }

-- animation state
local A = {
  pool    = {},      -- full list of AMM anim records {id,name,rig,comp,ent,fav}
  loaded  = false,
  rig     = nil,     -- rig filter (nil = all rigs)
  current = nil,     -- the record we last played
  seqIdx  = 0,       -- cursor for sequential "Next" over the working list
  instant = true,    -- PlayAnimationOnTarget 'instant' arg (snap vs blend into the pose)
  history = {},      -- recent names played (newest first), for reference
  probeAt = nil,     -- clock time to run the deferred "did it take?" workspot probe
  auto    = false,   -- auto-shuffle browse mode
  interval = 2.0,    -- seconds between auto-shuffle picks
  nextAuto = 0,
}
local clock = 0
local LIB_FILE = "jackie_anim_library.txt"

local function log(m) print("[JKAnim] " .. tostring(m)) end

-- ── target: the NPC the player is looking at (summon Jackie, aim at him) ───────────────
local function lookAtTarget()
  local p = Game.GetPlayer(); if not p then return nil end
  local t
  pcall(function()
    local ts = Game.GetTargetingSystem()
    if ts then t = ts:GetLookAtObject(p, false, false) end
  end)
  return t
end

-- ── AMM Poses hookup ──────────────────────────────────────────────────────────────────
local function getPoses()
  local amm = GetMod("AppearanceMenuMod")
  if not amm then return nil, "AMM not loaded (GetMod returned nil)." end
  if not amm.Poses then return nil, "AMM loaded but AMM.Poses missing (AMM version?)." end
  return amm.Poses
end

local function buildPool()
  local poses, err = getPoses()
  if not poses then UI.status = err; log(err); return end
  local list
  local ok = pcall(function() list = poses:GetAllAnimations() end)
  if not ok or type(list) ~= "table" then
    UI.status = "GetAllAnimations() failed — tell Claude (AMM DB not ready?)."
    log(UI.status); return
  end
  A.pool, A.loaded = list, true
  UI.status = string.format("Loaded %d AMM animations.", #list)
  log(UI.status)
end

-- the working list = pool filtered by the optional rig lock
local function workingList()
  if not A.rig then return A.pool end
  local out = {}
  for _, r in ipairs(A.pool) do if r.rig == A.rig then out[#out + 1] = r end end
  return out
end

-- minimal target table AMM.Poses:PlayAnimationOnTarget needs (it only reads .handle and .hash)
local function targetFor(h)
  local hash
  pcall(function() hash = tostring(h:GetEntityID().hash) end)
  return { handle = h, hash = hash or tostring(h) }
end

local function pushHistory(name)
  table.insert(A.history, 1, name)
  while #A.history > 8 do table.remove(A.history) end
end

-- core: play one record on the looked-at Jackie
local function playRecord(rec)
  local h = lookAtTarget()
  if not h then UI.status = "Look AT Jackie first."; log(UI.status); return false end
  if not rec then UI.status = "No animation selected (pool empty?)."; log(UI.status); return false end
  local poses = getPoses(); if not poses then return false end
  A.current = rec
  local ok, err = pcall(function()
    poses:PlayAnimationOnTarget(targetFor(h), rec, A.instant, nil)  -- caller=nil -> AMM auto-stops previous
  end)
  pushHistory(rec.name)
  A.probeAt = clock + 0.4   -- deferred "did he actually enter the workspot?" check
  UI.status = string.format("PLAY '%s'  (rig=%s comp=%s) ok=%s",
    tostring(rec.name), tostring(rec.rig), tostring(rec.comp), tostring(ok))
  log(string.format("PLAY  name='%s'  rig=%s  comp=%s  ent=%s  ok=%s%s",
    tostring(rec.name), tostring(rec.rig), tostring(rec.comp), tostring(rec.ent),
    tostring(ok), ok and "" or ("  ERR=" .. tostring(err))))
  return ok
end

local function playRandom()
  if not A.loaded then buildPool() end
  local list = workingList()
  if #list == 0 then UI.status = "Pool empty (rig filter too strict?)."; log(UI.status); return end
  local i = math.random(1, #list)
  A.seqIdx = i
  playRecord(list[i])
end

local function playNext()
  if not A.loaded then buildPool() end
  local list = workingList()
  if #list == 0 then UI.status = "Pool empty."; log(UI.status); return end
  A.seqIdx = (A.seqIdx % #list) + 1
  log(string.format("[%d/%d] sequential", A.seqIdx, #list))
  playRecord(list[A.seqIdx])
end

local function replayCurrent()
  if A.current then playRecord(A.current) else playRandom() end
end

local function stopAnim()
  local h = lookAtTarget(); if not h then return end
  pcall(function() Game.GetWorkspotSystem():StopInDevice(h) end)
  local poses = getPoses()
  if poses and A.current then pcall(function() poses:StopAnimation(A.current, false, nil) end) end
  UI.status = "Stopped."; log(UI.status)
end

-- lock the random pool to the rig of whatever we just played (learn Jackie's rig by trial)
local function lockToCurrentRig()
  if not (A.current and A.current.rig) then UI.status = "Play one first, then lock its rig."; return end
  A.rig = A.current.rig
  UI.status = "Locked to rig '" .. tostring(A.rig) .. "' (" .. #workingList() .. " anims)."
  log(UI.status)
end
local function clearRigLock()
  A.rig = nil; UI.status = "Rig lock cleared (all rigs)."; log(UI.status)
end

-- ── the LIBRARY: append the current anim to jackie_anim_library.txt ────────────────────
local function saveCurrent()
  if not A.current then UI.status = "Nothing to save — play one first."; log(UI.status); return end
  local r = A.current
  local line = string.format("%s\t| rig=%s\t| comp=%s\t| ent=%s",
    tostring(r.name), tostring(r.rig), tostring(r.comp), tostring(r.ent))
  local f = io.open(LIB_FILE, "a")
  if f then
    f:write(line .. "\n"); f:close()
    UI.status = "SAVED '" .. tostring(r.name) .. "' to " .. LIB_FILE
  else
    UI.status = "ERROR: could not write " .. LIB_FILE
  end
  log(UI.status)
end

-- ── lifecycle ───────────────────────────────────────────────────────────────────────
registerForEvent("onInit", function()
  math.randomseed(os.time and os.time() or 1)
  -- header once, so the library file is self-describing (appended, never wiped)
  local f = io.open(LIB_FILE, "a")
  if f then f:write("# Jackie animation library — one saved anim per line (name | rig | comp | ent)\n"); f:close() end
  log("Loaded. Summon Jackie (AMM), LOOK at him, press 'Play RANDOM anim'.")
  buildPool()
end)
registerForEvent("onOverlayOpen",  function() UI.overlay = true end)
registerForEvent("onOverlayClose", function() UI.overlay = false end)

registerForEvent("onUpdate", function(dt)
  clock = clock + dt
  -- deferred success probe
  if A.probeAt and clock >= A.probeAt then
    A.probeAt = nil
    local h = lookAtTarget()
    local inWs = "?"
    if h then pcall(function() inWs = tostring(Game.GetWorkspotSystem():IsActorInWorkspot(h)) end) end
    log("  -> inWorkspot=" .. inWs .. (inWs == "false" and "  (nothing played — wrong rig / he's mounted or in combat?)" or ""))
  end
  -- auto-shuffle browse
  if A.auto and clock >= A.nextAuto then
    A.nextAuto = clock + (A.interval or 2.0)
    playRandom()
  end
end)

registerForEvent("onDraw", function()
  if not UI.overlay or not UI.open then return end
  ImGui.Begin("Jackie Anim Test")

  local npc = lookAtTarget()
  ImGui.Text("Look-at: " .. (npc and "Jackie ok" or "none — aim at Jackie"))
  ImGui.Text(string.format("Pool: %d anims%s   rig lock: %s",
    #A.pool, A.rig and (" (" .. #workingList() .. " after filter)") or "", tostring(A.rig or "off")))
  if not A.loaded then
    if ImGui.Button("Load AMM animation list") then buildPool() end
  end
  ImGui.Separator()

  ImGui.Text("PLAY:")
  if ImGui.Button("Play RANDOM anim") then playRandom() end
  ImGui.SameLine()
  if ImGui.Button("Next (in order)") then playNext() end
  ImGui.SameLine()
  if ImGui.Button("Replay current") then replayCurrent() end
  if ImGui.Button("STOP animation") then stopAnim() end
  A.instant = ImGui.Checkbox("instant (snap into pose)", A.instant)

  ImGui.Separator()
  ImGui.Text("CURRENT:")
  if A.current then
    ImGui.TextWrapped(string.format("name = %s", tostring(A.current.name)))
    ImGui.Text(string.format("rig=%s  comp=%s", tostring(A.current.rig), tostring(A.current.comp)))
    if ImGui.Button("SAVE current to library") then saveCurrent() end
    ImGui.SameLine()
    if ImGui.Button("Lock random pool to this rig") then lockToCurrentRig() end
  else
    ImGui.Text("(play one to see its name)")
  end
  if A.rig then if ImGui.Button("Clear rig lock") then clearRigLock() end end

  ImGui.Separator()
  ImGui.Text("Auto-shuffle (browse):")
  A.auto = ImGui.Checkbox("auto-shuffle on", A.auto)
  A.interval = ImGui.SliderFloat("interval (s)", A.interval, 0.5, 5.0)

  if #A.history > 0 then
    ImGui.Separator()
    ImGui.Text("Recently played:")
    for _, nm in ipairs(A.history) do ImGui.BulletText(tostring(nm)) end
  end

  ImGui.Separator()
  if UI.status ~= "" then ImGui.TextWrapped("> " .. UI.status) end
  ImGui.Text("Library file: " .. LIB_FILE .. " (this mod's folder)")
  ImGui.End()
end)

-- Hotkeys (bind under CET > Bindings if you want them off the panel)
registerHotkey("jkanim_random", "Anim: play RANDOM",       function() playRandom() end)
registerHotkey("jkanim_next",   "Anim: play NEXT in order", function() playNext() end)
registerHotkey("jkanim_replay", "Anim: replay current",    function() replayCurrent() end)
registerHotkey("jkanim_save",   "Anim: SAVE current",      function() saveCurrent() end)
registerHotkey("jkanim_stop",   "Anim: stop",              function() stopAnim() end)
registerHotkey("jkanim_lockrig","Anim: lock to this rig",  function() lockToCurrentRig() end)
