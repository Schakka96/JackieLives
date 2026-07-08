--[[
  retrieval.lua — "Where's Jackie?" RETRIEVAL QUESTLINE + mod gate  (v0.2)
  ============================================================================
  Self-contained module. init.lua couples to it in only a few one-line spots
  (see PATCH LIST at the bottom). Nothing here depends on init.lua internals
  except OPTIONAL injected helpers (logger, tip popup, call/arrival/reunion
  starters), all passed via M.bind{} — so this file can't break the rest of
  the mod, and any unbound step gracefully no-ops (the quest still completes).

  THE QUEST (per-save game fact "jackielives_stage"):

    0 LOCKED  (default) — Jackie is "dead": schedule OFF, calls disconnected.   <- THE GATE
       │  precondition met (q101 "Playing for Time" done) AND V returns to Vik (4 m)
    1 TIP               — "Oh, didn't you hear?" popup + map pin on the Badlands hideout.
       │  V reaches the hideout (Rocky Ridge garage, 4 m)
    2 SHARD             — info-shard read; 1 s later Jackie RINGS V (one-time mute call:
       │                  "I made it / laid low / safe now / let's meet / wait there").
       │  call ends -> safe walk-in arrival at the garage
   (3 INCOMING)         — runtime-only sequence stage (not persisted; restarts on reload).
       │  Jackie arrives -> first-sight reunion dialogue (V lies about the Relic).
    4 REUNITED          — full mod UNLOCKED: schedule on, calls + summon work. Permanent.

  Stages 0/1/2/4 persist in the save; the call->arrival->reunion sequence runs
  while the fact == 2 and is driven by in-memory `seq` (so a save/reload mid-
  sequence just replays it cleanly rather than getting stuck half-done).

  WolvenKit: NOT required. The shard is on-screen text, not a real Codex entry.
--]]

local M = {}

-- ---------------------------------------------------------------------------
-- TUNABLES
-- ---------------------------------------------------------------------------
M.Config = {
  -- Vik's ripperdoc clinic (Misty's Esoterica, Watson). Captured in-game.
  vikPos      = { -1546.551, 1229.270, 11.520 },   -- yaw 129.8
  vikRadius   = 4.0,                                 -- "can't be missed" trigger zone

  -- Rocky Ridge — abandoned-town garage in the Badlands, no hostiles. Captured in-game.
  hideoutPos  = { 2575.852, 0.291, 80.871 },
  hideoutYaw  = 129.8,
  hideoutRadius = 4.0,

  -- PRECONDITION GATE: don't offer the tip until V is canonically post-heist
  -- (Jackie dead + Vik patched V up + V left the clinic). That whole arc == the
  -- main quest "Playing for Time" (q101) being COMPLETE.
  --   mode = "off"    -> no precondition; tip fires on Vik proximity alone (TESTING).
  --   mode = "quest"  -> require the journal quest below to be Succeeded.
  -- Ships "off" so the chain is testable at Vik's without driving the prologue.
  -- Use M.debugQuestState() in-game to confirm the path, then flip to "quest".
  gate = {
    mode       = "off",
    questPaths = {            -- tried in order; first that resolves is used
      "playing_for_time", "q101_playing_for_time",
      "main_quests/prologue/q101_playing_for_time",
    },
    succeededOnly = true,     -- true = require Succeeded; false = Active-or-later also ok
  },

  -- Vik's tip — the reveal, shown as the lower-left tutorial popup when V returns to the clinic.
  -- v1.2: TWO versions. tipText = Husbando (base, charged — Jackie couldn't stop asking about V);
  -- tipTextM = Hermano (canon, brotherly). init.lua picks via the mode selector (mvar).
  tipTitle    = "Viktor Vektor",
  tipText     = "I shoulda told you a long time ago, and I'm sorry I didn't. Jackie didn't die on "
              .. "my table that night. Got a pulse back, called in a favor, moved him out before "
              .. "Arasaka came lookin' for the body. He's alive, V — layin' low out in the Badlands, "
              .. "and it's gotta stay that way. Truth is... he's been askin' after you nonstop. Half-dead "
              .. "and still your name was the first thing outta his mouth. Whatever's between you two kept "
              .. "that boy fightin' when he had no business survivin'. I'm markin' the spot. Go get him.",
  tipTextM    = "I shoulda told you a long time ago, and I'm sorry I didn't. Jackie didn't die on "
              .. "my table that night. I got a pulse back, called in a favor, and moved him out "
              .. "before Arasaka came lookin' for the body. It just wasn't safe before to tell you, V. "
              .. "He's alive, V. Layin' low out in the Badlands — and it's gotta stay that way. "
              .. "He's been waitin' on you. I'm markin' the spot on your map. Go bring him home.",
  tipDuration = 10.0,

  -- Jackie's note — read on reaching the Badlands hideout (Rocky Ridge garage).
  shardTitle  = "Shard — Jackie Welles",
  -- v1.2: shardLines = Husbando (base — the desert gave him time to think, about Misty AND about V);
  -- shardLinesM = Hermano (canon, brotherly). Picked by the mode selector in reachHideout().
  shardLines  = {
    "If you're readin' this, V, then the doc kept his word and you made it all the way out here. It's me. I'm alive.",
    "Vik patched me up and smuggled me out 'fore 'Saka could stamp my name on a slab. Been layin' low ever "
      .. "since — nothin' but a whole lotta desert an' too much time to think.",
    "Thinkin' 'bout the heist. 'Bout Mama. 'Bout Misty — that's... that's its own story, one I gotta tell "
      .. "you face to face. And thinkin' 'bout you, V. More'n I got any right to, all the way out here.",
    "I'm done with the merc life for real this time. But I couldn't let you go on believin' you buried me. "
      .. "Call me when you read this. Been countin' the days, chica. — Jackie",
  },
  shardLinesM = {
    "If you're readin' this, V, then the doc kept his word and you made it out here. It's me. I'm alive.",
    "Vik patched me up and smuggled me out before 'Saka could stamp my name on a slab. Been layin' low ever since.",
    "Mama Welles was so mad when she heard. Think she'd kill me if I went back runnin' the streets again "
      .. "— and this time, maybe she's right. I'm done with the merc life, V. For real. But I couldn't "
      .. "let you go on thinkin' you buried me.",
    "Give me a call when you read this. — Jackie",
  },
  shardDuration = 12.0,

  callDelay   = 1.0,          -- seconds after the shard is read before Jackie rings V

  -- POST-REUNION shards (v0.84). Once Jackie's back (REUNITED), V comes across notes from the two
  -- people who took his "death" hardest — Misty and Mama Welles. These REPLACE the mourning
  -- conversations (see TODO: those base-game/mourning dialogue options are to be blocked). Each
  -- shard shows ONCE, on proximity to that person's spot, persisted via its own game fact.
  -- Coords: Misty's Esoterica + El Coyote Cojo, lifted from Config.locations (misty/coyote).
  postShards = {
    {
      fact  = "jackielives_shard_misty",
      pos   = { -1541.777, 1196.792, 15.905 }, radius = 8.0,
      title = "Shard — Misty",
      -- v1.2: lines = Husbando (Misty as the ex — hurt, but releasing him, and she sees the V of it);
      --       linesM = Hermano (canon — she's still his, grateful you brought him home). mvar() picks.
      lines = {
        "You're the one who went out and found him. 'Course you were. He used to talk about you like the sun came up outta your smile — even back when it was still him an' me.",
        "I won't lie to you, V. Some part of me knew long before that heist went sideways. Felt him driftin'. Every spread I turned showed two threads pullin' apart, and no shuffle in the world changed it.",
        "We ended it gentle as two people can. I told him a heart can't live half in what's gone. He needs somethin' that makes him feel alive NOW — and I finally stopped pretendin' that was still me.",
        "So whatever this is between you two — I'm not standin' in it. I turned the Lovers face-up for you both and left it there.",
        "Just be good to him, V. He's been broken enough for three lifetimes. — Misty",
      },
      linesM = {
        "I keep the Death card turned face-down now. Couldn't look at it — for months it was all I saw when I shut my eyes.",
        "When Vik told me he'd made it, that he was out there breathin' in the Badlands, I sat down on the shop floor and cried till the incense burned out.",
        "I won't pretend I'm only happy, V. Some nights I'm so angry I could scream. He walked into that heist knowin' the risk. He almost left us. Almost left me.",
        "But the cards weren't wrong. His thread didn't cut. It just frayed... and held.",
        "Go easy on him. And thank you — for goin' to bring him home. — Misty",
      },
      duration = 15.0
    },
    {
      fact  = "jackielives_shard_mama",
      pos   = { -1262.463, -1002.345, 12.037 }, radius = 9.0,
      title = "Shard — Mama Welles",
      -- v1.2: lines = Husbando (Mama's not blind to how her boy says V's name now); linesM = Hermano (canon).
      lines = {
        "So. My Jackie is alive, and I am the last to hear of it. You wait until you are a mother, V, and someone keeps a thing like this from you — then we will talk about forgiveness.",
        "I lit a candle for that boy every single day. I cooked for a ghost. And all the while he is out in the dust, breathin', lettin' me grieve. Dios mío.",
        "And yet — he is ALIVE. My boy is alive. I have not stopped thankin' the Virgin since I heard. My knees are sore from it.",
        "And do not think a mother is blind, mija. The way that boy says your name now — since Misty, since that desert — dios mío. I have eyes. So hear me: do not toy with my son's heart, and if he ever runs a gig like that heist again I will kill him myself before this city can.",
        "Bring him to my table. Bring yourself. There has always been a plate waitin' — now set out two. — Mama Welles",
      },
      linesM = {
        "So. My Jackie is alive, and I am the last to hear of it. You wait until you are a mother, V, and someone keeps a thing like this from you — then we will talk about forgiveness.",
        "I lit a candle for that boy every single day. I cooked for a ghost. And all the while he is out in the dust, breathin', lettin' me grieve. Dios mío.",
        "And yet — he is ALIVE. My boy is alive. I have not stopped thankin' the Virgin since I heard. My knees are sore from it.",
        "But hear me once, V: if he ever takes a gig like that heist again — risks his life for eddies and glory one more time — I will not wait for this city to take him. I will kill him myself.",
        "Bring him to my table. There is a plate waitin'. There has always been a plate waitin'. — Mama Welles",
      },
      duration = 15.0,
    },
  },
}

-- ---------------------------------------------------------------------------
-- Stage constants + module state
-- ---------------------------------------------------------------------------
-- v0.85: AWAITING(3) is now a REAL persisted stage — shard read, Jackie has no world presence yet
-- and ALWAYS answers V's call; the reunion call + walk-in drive the jump to REUNITED.
local LOCKED, TIP, SHARD, AWAITING, REUNITED = 0, 1, 2, 3, 4
local USE_GAME_FACT = true
-- ⚠️ NEVER RENAME THIS. The player's quest progress lives in this per-save game fact, NOT in the mod
-- files — which is exactly why updating the mod does NOT make them redo the recovery quest. Rename it
-- and every existing save reads as stage 0 (LOCKED), i.e. Jackie "dead" again. Keep it "jackielives_stage".
local FACT_NAME     = "jackielives_stage"

local deps  = {}              -- bound from init.lua: log, showTip, startCall, startArrival, startReunion, spawnAt
local state = { fallbackStage = 0, mappinId = nil, lastStage = -1, vikFired = false,
                clock = 0, callAt = nil, seq = nil }   -- seq: nil|"call"|"arrive"|"reunion"

local function log(msg) if deps.log then pcall(deps.log, "[Retrieval] " .. tostring(msg)) end end

-- v1.2: relationship-mode selector. init.lua binds `isHermano` (a function -> bool). When it
-- returns true the male-V (Hermano) track is active, so the recovery texts show their canon /
-- brotherly `*M` variant; otherwise the Husbando (base) text — flirtier, and Jackie's split with
-- Misty — is shown. mvar(husbando, hermano) picks the active one (the hermano arg is optional).
local function hermanoMode() return deps.isHermano and deps.isHermano() == true end
local function mvar(h, m) if m ~= nil and hermanoMode() then return m end return h end

-- ---------------------------------------------------------------------------
-- Self-contained primitives (no init.lua locals needed)
-- ---------------------------------------------------------------------------
local function playerPos()
  local p = Game.GetPlayer(); if not p then return nil end
  local ok, v = pcall(function() return p:GetWorldPosition() end)
  return ok and v or nil
end

local function dist2(ax, ay, bx, by)   -- horizontal distance (forgiving outdoors)
  local dx, dy = ax - bx, ay - by
  return math.sqrt(dx * dx + dy * dy)
end

local function nearPoint(pt, radius)
  if not pt then return false end
  local pp = playerPos(); if not pp then return false end
  return dist2(pp.x, pp.y, pt[1], pt[2]) <= (radius or 4.0)
end

local function onscreen(text, duration)   -- native on-screen msg band (init.lua's path)
  pcall(function()
    local defs = GetAllBlackboardDefs()
    local bb = Game.GetBlackboardSystem():Get(defs.UI_Notifications)
    if not bb then return end
    local msg = SimpleScreenMessage.new()
    msg.isShown, msg.duration, msg.message = true, duration or 6.0, text
    bb:SetVariant(defs.UI_Notifications.OnscreenMessage, ToVariant(msg), true)
  end)
end

-- Native LOWER-LEFT tutorial popup (the "Dark Future" method): the game's own
-- generic popup, driven by the UIGameData blackboard's Popup_Settings + Popup_Data
-- fields (the same blackboard our subtitles use). Field/enum names confirmed against
-- the game's reflection data (gamePopupData: title/message/isModal; gamePopupSettings:
-- position/closeAtInput/pauseGame/hideInMenu; gamePopupPosition.LowerLeft = 3).
-- Returns true only if the whole push succeeds, so showTip() can fall back cleanly.
local function lowerLeftPosition()
  -- Enum global is `gamePopupPosition`; tolerate a lowercase alias + a numeric last resort.
  if gamePopupPosition and gamePopupPosition.LowerLeft ~= nil then return gamePopupPosition.LowerLeft end
  if gamepopupPosition and gamepopupPosition.LowerLeft ~= nil then return gamepopupPosition.LowerLeft end
  return 3   -- LowerLeft = 3 in the reflection data
end

local function tutorialPopup(title, text)
  local ok = pcall(function()
    local defs = GetAllBlackboardDefs()
    local bb   = Game.GetBlackboardSystem():Get(defs.UIGameData)
    if not bb then error("UIGameData blackboard nil") end
    if not defs.UIGameData.Popup_Data or not defs.UIGameData.Popup_Settings then
      error("Popup_Data / Popup_Settings field nil")
    end

    local data = gamePopupData.new()
    data.title   = tostring(title or "")
    data.message = tostring(text or "")
    pcall(function() data.isModal = false end)

    local settings = gamePopupSettings.new()
    pcall(function() settings.position     = lowerLeftPosition() end)
    pcall(function() settings.closeAtInput = true end)   -- player dismisses it, like a real tutorial card
    pcall(function() settings.pauseGame    = false end)
    pcall(function() settings.hideInMenu   = true end)
    pcall(function() settings.fullscreen   = false end)

    bb:SetVariant(defs.UIGameData.Popup_Settings, ToVariant(settings, "gamePopupSettings"), true)
    bb:SetVariant(defs.UIGameData.Popup_Data,     ToVariant(data,     "gamePopupData"),     true)
    -- NO SignalVariant here: popupManager.script registers a DELAYED listener on Popup_Data, so the
    -- SetVariant above already fires ShowTutorial() next frame. On the live build SignalVariant THREW,
    -- which failed this whole pcall and (wrongly) fell back to the blue band even though the popup had
    -- shown. The v0.74 in-game probe confirmed all marshalling variants render the same lower-left card.
  end)
  if not ok then log("tutorial popup push failed -> falling back to on-screen band") end
  return ok
end

-- Show the tip via the native lower-left tutorial popup; fall back to an injected
-- showTip helper (if init.lua ever binds one) and finally the on-screen band.
local function showTip(title, text, duration)
  if tutorialPopup(title, text) then return end
  if deps.showTip and pcall(deps.showTip, title, text) then return end
  onscreen(text, duration)
end

-- ---------------------------------------------------------------------------
-- State (per-save game fact, with an in-session fallback)
-- ---------------------------------------------------------------------------
local function getStage()
  if USE_GAME_FACT then
    local v; local ok = pcall(function() v = Game.GetQuestsSystem():GetFactStr(FACT_NAME) end)
    if ok and type(v) == "number" then return v end
  end
  return state.fallbackStage or 0
end

local function setStage(n)
  state.fallbackStage = n
  if USE_GAME_FACT then pcall(function() Game.GetQuestsSystem():SetFactStr(FACT_NAME, n) end) end
  log("stage -> " .. tostring(n))
end

-- ---------------------------------------------------------------------------
-- Precondition: is V canonically post-heist (q101 done)?
-- ---------------------------------------------------------------------------
-- Best-effort journal lookup; fully guarded. Returns state string or nil.
local function questState(path)
  local result
  pcall(function()
    local jm = Game.GetJournalManager(); if not jm then return end
    local entry
    pcall(function() entry = jm:GetEntryByString(path) end)               -- common signature
    if not entry then pcall(function() entry = jm:GetEntryByString(path, "gameJournalQuest") end) end
    if not entry then return end
    local st; pcall(function() st = jm:GetEntryState(entry) end)
    if st ~= nil then result = tostring(st) end
  end)
  return result
end

local function preconditionMet()
  local g = M.Config.gate or {}
  if (g.mode or "off") ~= "quest" then return true end                    -- gate off -> always ok
  for _, p in ipairs(g.questPaths or {}) do
    local st = questState(p)
    if st then
      if st:find("Succeeded") then return true end
      if not g.succeededOnly and (st:find("Active") or st:find("Succeeded")) then return true end
      return false   -- the quest resolved but isn't done yet -> gate holds
    end
  end
  return false       -- couldn't resolve any path -> gate holds (use debug to fix the path)
end

-- Print candidate quest states so we can lock the gate path in-game.
function M.debugQuestState()
  log("---- quest-gate probe ----")
  for _, p in ipairs((M.Config.gate or {}).questPaths or {}) do
    log("  '" .. p .. "' -> " .. tostring(questState(p)))
  end
  log("  preconditionMet = " .. tostring(preconditionMet()))
  log("--------------------------")
end

-- ---------------------------------------------------------------------------
-- Map pin on the hideout (same mappin path as the dinner waypoint)
-- ---------------------------------------------------------------------------
local function placePin()
  if state.mappinId or not M.Config.hideoutPos then return end
  pcall(function()
    local h = M.Config.hideoutPos
    local pos  = ToVector4{ x = h[1], y = h[2], z = h[3], w = 1.0 }
    local data = NewObject("gamemappinsMappinData")
    data.mappinType = TweakDBID.new("Mappins.DefaultStaticMappin")
    data.variant    = gamedataMappinVariant.CustomPositionVariant
    state.mappinId  = Game.GetMappinSystem():RegisterMappin(data, pos)
  end)
  log("Badlands pin set (id=" .. tostring(state.mappinId) .. ")")
end

local function clearPin()
  if not state.mappinId then return end
  pcall(function() Game.GetMappinSystem():UnregisterMappin(state.mappinId) end)
  state.mappinId = nil
end

-- ---------------------------------------------------------------------------
-- Post-shard sequence: call -> arrival -> reunion -> UNLOCK.
-- Each step uses a bound starter if present, else immediately advances (so the
-- quest always completes even before Phases 3-4 are wired).
-- ---------------------------------------------------------------------------
local onCallDone, onArrived, onReunionDone   -- forward decls

local function startSequence()
  if state.seq then return end                 -- already running
  state.seq = "call"
  log("post-shard: Jackie calls V")
  if deps.startCall then pcall(deps.startCall, onCallDone) else onCallDone() end
end

onCallDone = function()
  if state.seq ~= "call" then return end
  state.seq = "arrive"
  log("call done -> safe walk-in arrival")
  if deps.startArrival then pcall(deps.startArrival, M.Config.hideoutPos, M.Config.hideoutYaw, onArrived)
  else onArrived() end
end

onArrived = function()
  if state.seq ~= "arrive" then return end
  state.seq = "reunion"
  log("arrived -> reunion dialogue")
  if deps.startReunion then pcall(deps.startReunion, onReunionDone) else onReunionDone() end
end

onReunionDone = function()
  state.seq = "done"
  clearPin()
  setStage(REUNITED)
  log("REUNITED — mod unlocked.")
end

-- ---------------------------------------------------------------------------
-- Quest transitions
-- ---------------------------------------------------------------------------
function M.giveTip()                                   -- LOCKED -> TIP
  if getStage() >= TIP then return false end
  showTip(M.Config.tipTitle, mvar(M.Config.tipText, M.Config.tipTextM), M.Config.tipDuration)
  setStage(TIP)
  return true
end

local function reachHideout()                          -- TIP -> AWAITING_CALL
  if getStage() ~= TIP then return end
  showTip(M.Config.shardTitle, table.concat(mvar(M.Config.shardLines, M.Config.shardLinesM), "\n"), M.Config.shardDuration)
  log("Shard read at hideout -> AWAITING_CALL (V must call Jackie; he always answers now).")
  -- v0.85: no more auto-ring. Jackie now WAITS for V to call him (he always picks up in this
  -- stage — no schedule, never 'asleep'). init.lua plays Config.reunionCallTree, whose ending
  -- walks him in on foot; the first-meeting dialogue then calls M.completeReunion() -> REUNITED.
  setStage(AWAITING)
end

-- ---------------------------------------------------------------------------
-- Post-reunion shards (Misty / Mama Welles) — one-time each, on proximity
-- ---------------------------------------------------------------------------
local function factNum(name)
  local v; pcall(function() v = Game.GetQuestsSystem():GetFactStr(name) end)
  return (type(v) == "number") and v or 0
end
local function setFactNum(name, n)
  pcall(function() Game.GetQuestsSystem():SetFactStr(name, n) end)
end

local function postShardTick()
  if getStage() < REUNITED then return end             -- only after Jackie's back
  for _, sh in ipairs(M.Config.postShards or {}) do
    if sh.fact and factNum(sh.fact) < 1 and nearPoint(sh.pos, sh.radius or 8.0) then
      showTip(sh.title, table.concat(mvar(sh.lines, sh.linesM) or {}, "\n"), sh.duration or 14.0)
      setFactNum(sh.fact, 1)
      log("Post-shard shown: " .. tostring(sh.title))
    end
  end
end

-- Debug: clear the post-shard flags so they can be re-triggered by walking up again.
function M.resetPostShards()
  for _, sh in ipairs(M.Config.postShards or {}) do if sh.fact then setFactNum(sh.fact, 0) end end
  log("Post-shard flags reset (walk up to Misty / El Coyote to re-read).")
end

-- Debug: show both post-reunion shards right now (regardless of location / flags).
function M.debugPostShards()
  for _, sh in ipairs(M.Config.postShards or {}) do
    showTip(sh.title, table.concat(mvar(sh.lines, sh.linesM) or {}, "\n"), sh.duration or 14.0)
  end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
function M.isUnlocked()    return getStage() >= REUNITED end
function M.getStage()      return getStage() end
-- v0.85: true once the shard's read and before the reunion completes. init.lua uses this to let
-- V call Jackie (he ALWAYS answers — no schedule/asleep gate) and to pick Config.reunionCallTree.
function M.isAwaitingCall() return getStage() == AWAITING end
-- Called by init.lua when the first-meeting dialogue ends: unlock the whole mod. Permanent.
function M.completeReunion()
  clearPin()
  setStage(REUNITED)
  log("REUNITED — mod fully unlocked (schedule + calls + summon live).")
end
-- Player-facing stage names (shown at the top of the CET window).
function M.stageName()
  local s = getStage()
  if s >= REUNITED then return "Jackie is back" end
  if s == AWAITING then return "Jackie's alive — CALL him (he's waitin')" end
  if s == SHARD    then return "Jackie's note was read at Rocky Ridge — he's on his way" end
  if s == TIP      then return "V heard the rumor — find Jackie in the Badlands" end
  return "Mod not yet available"
end
function M.unavailableMsg() return "Number disconnected." end
function M.notifyUnavailable() onscreen(M.unavailableMsg(), 2.5) end   -- native band, no init.lua scope needed

-- Inject init.lua helpers. ALL optional:
--   log(msg)                              -- logger
--   showTip(title, text) -> bool          -- native tutorial popup (Phase 2)
--   startCall(onDone)                     -- one-time incoming call (Phase 3)
--   startArrival(pos, yaw, onArrive)      -- safe walk-in (Phase 4)
--   startReunion(onDone)                  -- first-sight dialogue (Phase 4)
function M.bind(opts)
  opts = opts or {}
  for _, k in ipairs({ "log", "showTip", "startCall", "startArrival", "startReunion", "spawnAt", "isHermano" }) do
    if opts[k] ~= nil then deps[k] = opts[k] end
  end
end

function M.reset()                                     -- debug: back to LOCKED
  clearPin(); state.vikFired, state.callAt, state.seq = false, nil, nil
  setStage(LOCKED)
end

-- Debug jumps for the CET window.
function M.forceTip()   M.reset(); M.giveTip() end     -- skip the Vik proximity
function M.forceShard() if getStage() < TIP then M.giveTip() end; reachHideout() end  -- -> AWAITING_CALL
function M.forceAwaiting() M.reset(); setStage(AWAITING) end  -- jump straight to "call Jackie"
function M.forceReunion()  M.completeReunion() end            -- skip to REUNITED (unlock)

-- Per-frame driver (call from init.lua onUpdate with the frame delta).
function M.tick(dt)
  state.clock = state.clock + (dt or 0)
  local s = getStage()

  if s ~= state.lastStage then                         -- pin follows the stage (survives reloads)
    if s == TIP then placePin() else clearPin() end
    state.lastStage = s
  end

  if s == LOCKED then
    if not state.vikFired and preconditionMet()
       and nearPoint(M.Config.vikPos, M.Config.vikRadius) then
      state.vikFired = true
      M.giveTip()
    end
  elseif s == TIP then
    if not state.mappinId then placePin() end
    if nearPoint(M.Config.hideoutPos, M.Config.hideoutRadius) then reachHideout() end
  end
  -- s == AWAITING: nothing to poll here — the reunion is driven by V calling Jackie
  -- (init.lua: always-answer + Config.reunionCallTree -> walk-in -> M.completeReunion()).

  postShardTick()   -- v0.84: Misty / Mama Welles notes, once Jackie's back
end

return M

--[[
  ============================================================================
  PATCH LIST for init.lua  (Phase 1 wiring — all surgical inserts)
  ============================================================================
  1) require (next to `local Config = require("config")`):
       local Retrieval = require("retrieval")
  2) onInit (near pcall(jlLoadSettings)):
       pcall(function() Retrieval.bind{ log = log } end)
  3) scheduleTick top (after the leaving check):
       if not Retrieval.isUnlocked() then clearIdle(); return end
  4) summonJackie / startCall — at the top:
       if not Retrieval.isUnlocked() then showOnscreenMsg(Retrieval.unavailableMsg(), 2.5); return end
     onPlayerCalledJackie — at the top (let the game's own call ring out):
       if not Retrieval.isUnlocked() then return end
  5) onUpdate (where pcall(scheduleTick) runs) — pass the frame delta:
       pcall(function() Retrieval.tick(deltaTime) end)
  6) (optional) CET debug UI:
       ImGui.Text("Retrieval: " .. Retrieval.stageName())
       if ImGui.Button("Force tip")   then Retrieval.forceTip()   end
       if ImGui.Button("Force shard") then Retrieval.forceShard() end
       if ImGui.Button("Quest probe") then Retrieval.debugQuestState() end
       if ImGui.Button("Reset quest") then Retrieval.reset()       end
  Phases 2-4 add more Retrieval.bind{} helpers (showTip / startCall / startArrival / startReunion).
--]]
