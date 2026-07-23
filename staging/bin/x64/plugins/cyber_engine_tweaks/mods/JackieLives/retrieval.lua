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
  -- v1.56: SHIPS "quest" NOW (was "off" — a testing default that should never have gone public).
  -- With the gate off, Vik's "Jackie didn't die on my table" reveal fired on PROXIMITY ALONE. Every
  -- new-game player visits Vik in Act 1 (The Ripperdoc) — so they got the reveal BEFORE Jackie had even
  -- died. That's both a spoiler and nonsense.
  --
  -- The gate is now THREE-STATE (questGateState), not a boolean, because "I can't read the journal" is a
  -- genuinely different situation from "the heist hasn't happened yet", and conflating them is what forced
  -- the old unsafe default:
  --    "met"     -> post-heist. The reveal may fire, and the welcome card shows.
  --    "notyet"  -> the quest resolved and ISN'T done. Stay silent. (This is the case that was spoiling.)
  --    "unknown" -> NO path resolved, so we know nothing. STAY SILENT — never guess and spoil — and let
  --                 the player start the questline themselves from Esc -> Settings ("Start the search for
  --                 Jackie"). That button is why turning the gate on can't brick the mod for anyone.
  -- The journal paths below are still best-guesses (the real ones live in .journal resources, not in the
  -- decompiled scripts, so they can't be confirmed off-Windows). "unknown" exists precisely so that a wrong
  -- guess degrades to "the player presses a button", not to "the mod is dead" and not to "the mod spoils".
  gate = {
    mode       = "quest",
    questPaths = {            -- tried in order; first that resolves is used
      "playing_for_time", "q101_playing_for_time",
      "main_quests/prologue/q101_playing_for_time",
      "main_quests/prologue/q101_playing_for_time/q101_playing_for_time",
      "quests/main_quests/prologue/q101_playing_for_time",
    },
    succeededOnly = true,     -- true = require Succeeded; false = Active-or-later also ok
  },

  -- v1.56 WELCOME CARD (Antonia). Shown ONCE, on the first load after installing, and ONLY to a player who
  -- is already post-"Playing for Time" — i.e. only when the gate says "met", so it can never appear in a
  -- pre-heist game and spoil Jackie's death. It tells them Vik's been trying to reach them, and — crucially
  -- — that the questline can be started from the mod menu if it doesn't fire at Vik's. That last sentence is
  -- the safety net for anyone whose journal path we failed to resolve.
  welcome = {
    fact  = "jackielives_welcome",
    title = "Jackie Lives — installed",
    text  = "Vik called. Left a message. Says he's got somethin' to tell you about Jackie — somethin' he "
         .. "wouldn't say over the phone.\n\n"
         .. "Go see him at his clinic.\n\n"
         .. "(For mod settings go to Esc -> Mods -> JackieLives) ",
    duration = 16.0,
  },

  -- Vik's tip — the reveal, shown as the lower-left tutorial popup when V returns to the clinic.
  -- v1.54: no Misty, and no "whatever's between you two" (Antonia — the pining is gone). Vik reports the
  -- one thing he'd actually report: the boy shouldn't have lived, he asked for V, go bring him home.
  -- tipText = Husbando (base, a shade warmer); tipTextM = Hermano (canon). init.lua picks via mvar().
  tipTitle    = "Vik:",
  tipText     = "I shoulda told you a long time ago, and I'm sorry I didn't. Jackie didn't die on "
              .. "my table that night. I got a pulse back, called in a favor, moved him out before "
              .. "Arasaka came lookin' for the body. "
              .. "He's alive, V — layin' low out in the Badlands, "
              .. "and it's gotta stay that way. Kid had no business survivin' what he survived. And when "
              .. "he could talk again, the first thing he asked was whether you got out. "
              .. "It just wasn't safe before to tell you V. I'm sorry. "
              .. "I'm markin' the spot on your map. Go bring him back.",
  tipTextM    = "I shoulda told you a long time ago, and I'm sorry I didn't. Jackie didn't die on "
              .. "my table that night. I got a pulse back, called in a favor, moved him out before "
              .. "Arasaka came lookin' for the body. "
              .. "It just wasn't safe before to tell you, V. "
              .. "He's alive. Layin' low out in the Badlands — and it's gotta stay that way. "
              .. "He's been waitin' on you. I'm markin' the spot on your map. Go bring him back.",
  tipDuration = 10.0,

  -- Jackie's note — read on reaching the Badlands hideout (Rocky Ridge garage).
  -- v1.54: Jackie's note does NOT mention Misty, in either track (Antonia). The old base version had him
  -- brooding over her "story" and pining after V from the desert; both are gone. What's left is the thing
  -- the note is actually for: he's alive, he's out of the life, and he wants V to call him.
  shardTitle  = "Shard — Jackie Welles",
  -- shardLines are the same for both genders now
  -- Picked by the mode selector in reachHideout().
  shardLines  = {
    "If you're readin' this, V, then the doc kept his word and sent you out here. It's me. I'm alive.",
    "Vik patched me up and smuggled me out before 'Saka could stamp my name on a slab. Been layin' low ever since.",
    "Mama Welles was so mad when she heard. Think she'd kill me if I went back doin' gigs "
      .. "— maybe she's right. I'm done with the merc life, V. For real. But I couldn't "
      .. "let you go on thinkin' you buried me.",
    "Give me a call when you read this. — Jackie",
  },
  shardLinesM = {
    "If you're readin' this, V, then the doc kept his word and sent you out here. It's me. I'm alive.",
    "Vik patched me up and smuggled me out before 'Saka could stamp my name on a slab. Been layin' low ever since.",
    "Mama Welles was so mad when she heard. Think she'd kill me if I went back doin' gigs "
      .. "— maybe she's right. I'm done with the merc life, V. For real. But I couldn't "
      .. "let you go on thinkin' you buried me.",
    "Give me a call when you read this. — Jackie",
  },
  shardDuration = 12.0,

  callDelay   = 1.0,          -- seconds after the shard is read before Jackie rings V

  -- OBJECTIVE BANNERS (v1.54). The retrieval quest had NO on-screen objectives at all — the tip popup
  -- and the shard fired, and then the player was simply expected to know to drive to the Badlands, and
  -- later to phone Jackie and then stand still while he walked in. These are the game's neon on-screen
  -- message band (the same "DIY objective" path the dinner outing already uses via showOnscreenMsg), so
  -- they LOOK native without needing a real journal quest (which would mean WolvenKit + a .quest graph).
  --
  -- They're FLASHES, not a persistent tracker: each fires once on the transition into its step, and is
  -- re-asserted once a few seconds after a save is loaded (see tick(), first-observation branch) so a
  -- returning player is told what they're supposed to be doing. Set an entry to nil to silence that step.
  objectives = {
    tip      = "Find Jackie — Rocky Ridge, the Badlands",   -- Vik's just told you he's alive; pin is on the map
    awaiting = "Call Jackie",                               -- the note's been read — he's waiting on YOUR call
    arriving = "Wait for Jackie",                           -- the call's over; he's on his way to you on foot
    done     = "Jackie's back.",                            -- reunited: the mod is unlocked
  },
  objectiveDuration = 8.0,
  -- Delay before an objective lands, so it doesn't collide with the tip/shard popup that triggered it.
  objectiveDelay    = 3.5,

  -- POST-REUNION shards (v0.84). Once Jackie's back (REUNITED), V comes across notes from the two
  -- people who took his "death" hardest — Misty and Mama Welles. These REPLACE the mourning
  -- conversations (see TODO: those base-game/mourning dialogue options are to be blocked). Each
  -- shard shows ONCE, on proximity to that person's spot, persisted via its own game fact.
  -- Coords: Misty's Esoterica + El Coyote Cojo, lifted from Config.locations (misty/coyote).
  -- v1.54: BOTH notes are now single-track (no `linesM`) — mvar() falls through to `lines` when there's no
  -- masculine variant, so one text serves every V. The old Husbando versions were the romance arc in
  -- letter form (Misty releasing Jackie and blessing V; Mama warning V not to toy with her son's heart)
  -- and Antonia cut it: Misty and Jackie are TOGETHER, and neither woman is writing about V's love life.
  postShards = {
    {
      fact  = "jackielives_shard_misty",
      pos   = { -1541.777, 1196.792, 15.905 }, radius = 8.0,
      title = "Shard — Misty",
      lines = {
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
      lines = {
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
                clock = 0, callAt = nil, seq = nil,    -- seq: nil|"call"|"arrive"|"reunion"
                objText = nil, objAt = nil }           -- v1.54: the one pending objective banner + when it lands

local function log(msg) if deps.log then pcall(deps.log, "[Retrieval] " .. tostring(msg)) end end

-- v1.2: relationship-mode selector. init.lua binds `isHermano` (a function -> bool). When it returns
-- true the male-V (Hermano) track is active, so a recovery text shows its `*M` variant; otherwise the
-- base (Husbando) text is used. mvar(husbando, hermano) picks the active one — and the hermano arg is
-- OPTIONAL: a text with no `*M` variant (both post-reunion shards, as of v1.54) serves every V.
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

-- v1.60 LOCALIZATION CHOKEPOINT 5 of 5. retrieval.lua does NOT go through init.lua's
-- showOnscreenMsg for its own cards (only objectives do, via deps.showObjective), so the
-- questline's popups/banners need the translation applied here too. Required directly
-- rather than injected via bind() so a card can never render English just because the
-- module was used before init.lua bound its deps.
local Lang = require("lang")

local function onscreen(text, duration)   -- native on-screen msg band (init.lua's path)
  pcall(function()
    local defs = GetAllBlackboardDefs()
    local bb = Game.GetBlackboardSystem():Get(defs.UI_Notifications)
    if not bb then return end
    local msg = SimpleScreenMessage.new()
    msg.isShown, msg.duration, msg.message = true, duration or 6.0, Lang.t(text)
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
  title, text = Lang.t(title), Lang.t(text)
  if tutorialPopup(title, text) then return end
  if deps.showTip and pcall(deps.showTip, title, text) then return end
  onscreen(text, duration)
end

-- v1.60: the shard / postShard notes are TABLES of lines joined with "\n". Translate each line
-- INDIVIDUALLY, then join — so the translation key is one shard line, not the whole multi-line note.
-- Line-level keys stay stable when a single line is edited and match the mod's authored granularity;
-- the joined-whole string would be one brittle key that breaks on any edit. showTip's own Lang.t then
-- no-ops on the assembled (already-translated) text.
local function concatT(lines)
  local out = {}
  for _, ln in ipairs(lines or {}) do out[#out + 1] = Lang.t(ln) end
  return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- OBJECTIVE BANNERS (v1.54) — the blue/neon on-screen band that tells the player what to do next.
-- Prefers init.lua's showOnscreenMsg (bound as `showObjective`) because that one also plays the UI
-- sound cue, so the banner isn't silent; falls back to our own local band if it isn't bound.
-- ---------------------------------------------------------------------------
local function showObjective(text)
  if not text or text == "" then return end
  local dur = M.Config.objectiveDuration or 8.0
  if not (deps.showObjective and pcall(deps.showObjective, text, dur)) then onscreen(text, dur) end
  log("Objective: " .. tostring(text))
end

-- Queue an objective to land `delay` seconds from now (default objectiveDelay). Deferred rather than
-- immediate so it doesn't fight the tutorial popup / shard text that triggered it for the player's eye.
-- Only ONE objective is ever pending — a newer step always supersedes an older one that hasn't shown yet.
local function queueObjective(text, delay)
  if not text or text == "" then return end
  state.objText = text
  state.objAt   = state.clock + (delay or M.Config.objectiveDelay or 3.5)
end

local function objectiveTick()
  if not state.objAt or state.clock < state.objAt then return end
  local t = state.objText
  state.objAt, state.objText = nil, nil
  showObjective(t)
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
-- Numeric game facts (persist in the save). Declared HERE, above the quest gate, because the welcome card
-- and the manual start both need them — and a Lua local is only visible to code written below it.
-- ---------------------------------------------------------------------------
local function factNum(name)
  local v; pcall(function() v = Game.GetQuestsSystem():GetFactStr(name) end)
  return (type(v) == "number") and v or 0
end
local function setFactNum(name, n)
  pcall(function() Game.GetQuestsSystem():SetFactStr(name, n) end)
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

-- v1.56: THREE states, not a boolean. See the essay on M.Config.gate.
--   "met"     -> post-heist: the reveal may fire, the welcome card may show.
--   "notyet"  -> the quest resolved and isn't Succeeded: STAY SILENT (this is the spoiler case).
--   "unknown" -> no path resolved: we know nothing, so STAY SILENT and rely on the manual start button.
-- The old code collapsed "notyet" and "unknown" into a single `false`, which is why the only way to make
-- the mod usable was to disable the gate entirely — and that's what leaked the spoiler into a new game.
local function questGateState()
  local g = M.Config.gate or {}
  if (g.mode or "off") ~= "quest" then return "met" end                   -- gate off -> no precondition
  for _, p in ipairs(g.questPaths or {}) do
    local st = questState(p)
    if st then
      if st:find("Succeeded") then return "met" end
      if not g.succeededOnly and st:find("Active") then return "met" end
      return "notyet"                    -- the quest resolved but isn't done -> pre-heist. Say nothing.
    end
  end
  return "unknown"                       -- couldn't resolve ANY path -> never guess. Say nothing.
end

local function preconditionMet() return questGateState() == "met" end

-- Print candidate quest states so we can lock the gate path in-game.
function M.debugQuestState()
  log("---- quest-gate probe ----")
  for _, p in ipairs((M.Config.gate or {}).questPaths or {}) do
    log("  '" .. p .. "' -> " .. tostring(questState(p)))
  end
  log("  gate state = " .. tostring(questGateState()))
  log("--------------------------")
end

-- v1.56: MANUAL START — the safety net that lets the gate be ON without any risk of bricking the mod.
-- Wired to Esc -> Settings -> Jackie Lives -> "Start the search for Jackie", and to a CET button. It
-- BYPASSES the gate entirely: the player is explicitly telling us they've already lost Jackie. So even if
-- every journal path we guess is wrong ("unknown"), nobody is ever stuck — they press this and play.
-- No-op once the questline has started, so it can't rewind anyone's progress.
function M.startSearch()
  if getStage() >= TIP then
    log("Manual start: the search is already under way (stage " .. tostring(getStage()) .. ") — nothing to do.")
    return false
  end
  setFactNum((M.Config.welcome or {}).fact or "jackielives_welcome", 1)   -- don't also pop the welcome card
  log("Manual start: player started the search for Jackie from the menu (gate bypassed).")
  M.giveTip()
  return true
end

-- v1.56 WELCOME CARD — once per save, first load after install, and ONLY when the gate says "met" (so it
-- can never appear pre-heist and spoil Jackie's death). Tells the player Vik's looking for them, and how to
-- start the questline by hand if it doesn't fire at his clinic.
local function welcomeTick()
  local W = M.Config.welcome
  if not (W and W.fact) then return end
  if factNum(W.fact) >= 1 then return end             -- already shown (persisted)
  if getStage() >= TIP then                            -- questline already started -> card is pointless
    setFactNum(W.fact, 1); return
  end
  if questGateState() ~= "met" then return end         -- pre-heist, or we can't tell -> say NOTHING
  setFactNum(W.fact, 1)
  showTip(W.title, W.text, W.duration or 16.0)
  log("Welcome card shown (post-'Playing for Time', first load after install).")
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
  queueObjective((M.Config.objectives or {}).tip)      -- v1.54: "Find Jackie — Rocky Ridge, the Badlands"
  return true
end

local function reachHideout()                          -- TIP -> AWAITING_CALL
  if getStage() ~= TIP then return end
  showTip(M.Config.shardTitle, concatT(mvar(M.Config.shardLines, M.Config.shardLinesM)), M.Config.shardDuration)
  -- v1.54: the note is long — let the player actually READ it before the "Call Jackie" banner lands.
  queueObjective((M.Config.objectives or {}).awaiting, (M.Config.shardDuration or 12.0) * 0.6)
  log("Shard read at hideout -> AWAITING_CALL (V must call Jackie; he always answers now).")
  -- v0.85: no more auto-ring. Jackie now WAITS for V to call him (he always picks up in this
  -- stage — no schedule, never 'asleep'). init.lua plays Config.reunionCallTree, whose ending
  -- walks him in on foot; the first-meeting dialogue then calls M.completeReunion() -> REUNITED.
  setStage(AWAITING)
end

-- ---------------------------------------------------------------------------
-- Post-reunion shards (Misty / Mama Welles) — one-time each, on proximity
-- ---------------------------------------------------------------------------
-- (v1.56: factNum/setFactNum moved UP, above the quest gate — the welcome card and the manual start need
--  them, and a Lua local is only visible to code written BELOW it. Left here, they resolved as nil globals.)

-- ---------------------------------------------------------------------------
-- REVEREND FLASH EASTER EGG (v1.55) — see Config.revflash in config.lua for the story + the coords.
-- Proximity-driven, one-time-per-save, and deliberately INDEPENDENT of the questline: it does not care
-- what retrieval stage you're at. Two separately-latched triggers on the same spot (payout at `radius`,
-- the tribute card at a 0.5 m `noticeRadius`), so finding the money doesn't spend the hidden thank-you.
-- Everything is pcall-guarded and the whole block no-ops when Config.revflash.enabled is false — which it is
-- until the real bar coordinates land.
-- ---------------------------------------------------------------------------

-- Re-enable Jackie's Arch on V's vehicle list, undoing jlReturnJackiesBike's EnablePlayerVehicle(rec,false).
-- "If the arch is already there skip that step" (Antonia): we ASK first via IsVehiclePlayerUnlocked. If that
-- query isn't available on this build we just re-enable anyway — enabling an already-enabled vehicle is a
-- harmless no-op, so the skip is an optimisation, never a correctness requirement.
local function revflashRestoreBike()
  -- the Arch's TweakDB record — bound from init.lua (Config.bikeReturn.bikeRecord) so the removal and the
  -- restore can never drift apart and start naming two different bikes.
  local rec = deps.bikeRecord or "Vehicle.v_sportbike2_arch_jackie_player"
  local already = false
  pcall(function()
    already = Game.GetVehicleSystem():IsVehiclePlayerUnlocked(TweakDBID.new(rec)) == true
  end)
  if already then
    log("Reverend Flash: V already has the Arch — skipping the vehicle restore.")
    return false
  end
  local ok = pcall(function()
    Game.GetVehicleSystem():EnablePlayerVehicle(rec, true, true)   -- (id, enable=TRUE, updateGarage)
  end)
  log("Reverend Flash: restored '" .. rec .. "' to V's vehicle list (ok=" .. tostring(ok) .. ").")
  return ok
end

local function revflashTick()
  local K = M.Config and M.Config.revflash
  if not (K and K.enabled and K.pos) then return end

  -- (1) THE PAYOUT — room-sized zone. Eddies + the Arch, once.
  if K.factMoney and factNum(K.factMoney) < 1 and nearPoint(K.pos, K.radius or 6.0) then
    setFactNum(K.factMoney, 1)                       -- latch FIRST: a failed payout must never retry forever
    local amount = K.eddies or 38470
    local paid = pcall(function()
      Game.AddToInventory(K.moneyItem or "Items.money", amount)
    end)
    if K.restoreBike then pcall(revflashRestoreBike) end
    onscreen(K.bannerText or "Something's been left here for you...", 6.0)
    log(("Reverend Flash easter egg: paid %d eddies (ok=%s)."):format(amount, tostring(paid)))
  end

  -- (2) THE TRIBUTE CARD — the tight 0.5 m spot. Separately latched, so it survives the payout.
  if K.factNotice and factNum(K.factNotice) < 1 and nearPoint(K.pos, K.noticeRadius or 0.5) then
    setFactNum(K.factNotice, 1)
    showTip(K.noticeTitle or "Thank you, Reverend Flash", K.noticeText or "", 16.0)
    log("Reverend Flash easter egg: tribute card shown.")
  end
end

-- Debug: re-arm the easter egg so it can be walked into again.
function M.resetRevflash()
  local K = M.Config and M.Config.revflash; if not K then return end
  if K.factMoney  then setFactNum(K.factMoney, 0) end
  if K.factNotice then setFactNum(K.factNotice, 0) end
  log("Reverend Flash easter egg re-armed (walk back in to re-trigger).")
end

-- Debug: fire it right now, wherever you're standing (ignores the coords entirely).
function M.debugRevflash()
  local K = M.Config and M.Config.revflash; if not K then return end
  pcall(function() Game.AddToInventory(K.moneyItem or "Items.money", K.eddies or 38470) end)
  if K.restoreBike then pcall(revflashRestoreBike) end
  showTip(K.noticeTitle or "Thank you, Reverend Flash", K.noticeText or "", 16.0)
  log("Reverend Flash easter egg: FORCED (debug).")
end

local function postShardTick()
  if getStage() < REUNITED then return end             -- only after Jackie's back
  for _, sh in ipairs(M.Config.postShards or {}) do
    if sh.fact and factNum(sh.fact) < 1 and nearPoint(sh.pos, sh.radius or 8.0) then
      showTip(sh.title, concatT(mvar(sh.lines, sh.linesM)), sh.duration or 14.0)
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
    showTip(sh.title, concatT(mvar(sh.lines, sh.linesM)), sh.duration or 14.0)
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
-- v1.54: called by init.lua's `reunion_arrival` action, i.e. the moment the reunion CALL hangs up and
-- Jackie starts walking in. This is the step Antonia specifically flagged as missing — without it the
-- player just stands there after the call with no idea they're supposed to wait.
function M.notifyArrivalPending()
  queueObjective((M.Config.objectives or {}).arriving, 1.0)
end

-- Called by init.lua when the first-meeting dialogue ends: unlock the whole mod. Permanent.
function M.completeReunion()
  clearPin()
  setStage(REUNITED)
  queueObjective((M.Config.objectives or {}).done, 1.5)   -- v1.54: quest-complete banner
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
  for _, k in ipairs({ "log", "showTip", "startCall", "startArrival", "startReunion", "spawnAt", "isHermano",
                       "showObjective",   -- v1.54: showObjective(text, secs) -> init.lua's showOnscreenMsg (banner + UI sound)
                       "bikeRecord" }) do -- v1.55: the Arch's TweakDB id (string), for the Reverend Flash bike restore
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
    -- v1.54: RE-ASSERT the objective on the first tick of a session (lastStage is only -1 straight after
    -- a load). These banners are flashes, not a persistent tracker, so a player who quits mid-quest and
    -- comes back tomorrow gets told what they were doing. Live transitions queue their own banner in
    -- giveTip / reachHideout / notifyArrivalPending — hence the first-observation guard, so they don't
    -- fire twice.
    if state.lastStage == -1 then
      local o = M.Config.objectives or {}
      if s == TIP then queueObjective(o.tip)
      elseif s == SHARD or s == AWAITING then queueObjective(o.awaiting) end   -- SHARD = the legacy stage 2
    end
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

  welcomeTick()     -- v1.56: the one-time "Vik's been callin'" card (only post-heist; never pre-heist)
  objectiveTick()   -- v1.54: land any queued objective banner once its delay is up
  postShardTick()   -- v0.84: Misty / Mama Welles notes, once Jackie's back
  revflashTick()       -- v1.55: the Reverend Flash refund at Rocky Ridge (self-gating; off until its coords land)
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
