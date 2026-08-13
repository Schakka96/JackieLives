--[[
  dialogui.lua — THE NATIVE DIALOGUE PICKER  (v1.64.1)

  Self-contained module (global `DialogUI`, no top-level `local` in init.lua's main chunk ->
  respects the 200-local cap, same as Retrieval / Blaze / Session / Lang).

  ---------------------------------------------------------------------------
  WHAT THIS REPLACES
  ---------------------------------------------------------------------------
  v0.24..v1.62 drew V's dialogue choices as a CUSTOM ImGui window (`drawDialogueBox`,
  `drawNameChild`, `drawChoiceRows`, `Config.picker`). It was a hand-painted imitation of the
  game's dialogue box: our own yellow bar, our own cyan text, our own red "JACKIE" name plate,
  positioned by hand with topFrac/baseW/baseH/minScale/maxScale so it would land in roughly the
  right place at any resolution. It never quite matched, it needed re-tuning at every aspect
  ratio, and it rendered in CET's ImGui font — which is Latin-only, so the Japanese/Russian/
  Chinese translations came out as boxes (the caveat documented in lang.lua).

  This module deletes all of that and renders the choices through the GAME's own dialogue
  widget instead — the exact `dialogWidgetGameController` that draws V's lines in every vanilla
  conversation. Correct fonts (all languages), correct colours, correct placement, correct
  animations, correct scaling, for free, forever.

  ---------------------------------------------------------------------------
  HOW IT WORKS (and why the obvious approach fails)
  ---------------------------------------------------------------------------
  There are TWO different "choice hub" structs in this game and they are not interchangeable:

    * `InteractionChoiceHubData`      -> the small world PROMPT ("[F] Talk", "[F] Get in the AV").
      Driven by writing the UIInteractions.InteractionChoiceHub blackboard field. This is what
      init.lua's showJackieChoiceBox() and Blaze.showPrompt() use, and it is CORRECT there —
      those are untouched by this module.

    * `ListChoiceHubData` (inside a `DialogChoiceHubs`) -> the scrollable DIALOGUE list. THIS is
      the box we want. It is NOT driven by a blackboard write. v0.16/v0.17 assumed it was, which
      is why every attempt at a real dialogue box failed for forty versions.

  The dialogue list is driven by calling methods on the LIVE controller instance. From the
  decompiled scripts (scripts/cyberpunk/UI/interactions/interactionUIBase.script:52-61 and
  dialogUI.script:63-99), the render path is:

      OnDialogsData(variant)                       -- base handler
        m_AreDialogsOpen   = choiceHubs.Size() > 0 -- <-- THE GATE
        m_dialogIsScrollable = ... > 1
        UpdateDialogsData(data)                    -- dialogWidgetGameController: m_data = data
        OnInteractionsChanged()                    -- builds the widgets from m_data...
          m_root.SetVisible( m_AreDialogsOpen )    -- ...and hides the lot unless the gate is true
        UpdateListBlackboard()

  So three things must all be true or nothing appears:
    1. the controller has our `DialogChoiceHubs` in `m_data`,
    2. `m_AreDialogsOpen` is true (dialogUI.script:99 — the whole root is hidden otherwise),
    3. `ActiveChoiceHubID` == our hub id, or the hub renders with NO selection highlight
       (dialogUI.script:87 — `SetData(hubData, hubData.id == m_activeHubID, ...)`).

  ⚠️ (3) is the one that bites, and it shipped as the intermittent "the choices are there but nothing
  is highlighted" bug. Blocking the game's writes to it is NOT enough on its own: the id must also be
  owned in the `UIInteractions.ActiveChoiceHubID` blackboard (the controller re-seeds from there when
  it re-initialises — interactionUIBase.script:34) AND read back off the controller every frame, so a
  drift by any route we can't see is repaired rather than merely stared at. publishHub()/repairHub().

  And because the game keeps pushing its own (usually empty) dialogue data during normal play,
  we must OVERRIDE the handlers to leave ours alone while it is up. That last part is the bit
  nobody guesses; without it the box appears for a frame or two and vanishes.

  ---------------------------------------------------------------------------
  INPUT
  ---------------------------------------------------------------------------
  The native widget is DRAW-ONLY. It reports nothing back — no click, no callback, no selected
  index. Navigation and confirmation are entirely ours: init.lua's existing PlayerPuppet:OnAction
  hook forwards every action here (DialogUI.onAction) while the box is up, we track the index
  ourselves, and we publish it to `UIInteractions.SelectedIndex` so the widget highlights the
  right row (dialogUI.script:329 — `SetSelected(m_isSelected && m_selectedInd == i)`).

  ---------------------------------------------------------------------------
  CREDIT
  ---------------------------------------------------------------------------
  The controller-call sequence is the community recipe from Nexus article 413, as shipped in
  DVLP/QuestRunner's lib/interactionUI.lua (via 1dentity, originally psiberx). What is new here:
  we capture the controller ONLY from `dialogWidgetGameController` (see CONTROLLER CAPTURE
  below), we resolve the protected-field name instead of assuming it, and we yield to real
  in-game dialogue instead of fighting it.
--]]

local DialogUI = {}
DialogUI.VERSION = "1.64.2"

-- deps injected from init.lua (DialogUI.bind{...})
local deps = {}
local function log(msg) if deps.log then pcall(deps.log, "[DialogUI] " .. tostring(msg)) end end

-- The mod's monotonic clock (JL.clock), injected so this file never reaches into init.lua's state.
local function CLOCK()
  local t = 0
  if deps.clock then pcall(function() t = deps.clock() or 0 end) end
  return t
end

-- Live state. All module-level (init.lua's 200-local cap is per-chunk, so this file is free).
local S = {
  ctrl      = nil,     -- the live dialogWidgetGameController
  shown     = false,
  hubId     = 7732,    -- our hub's id; stable across opens. NOT 7731 - that's the "[F] Talk" prompt's.
  sel       = 0,       -- highlighted row, ZERO-BASED (the game's SelectedIndex is 0-based)
  count     = 0,
  title     = nil,     -- speaker plate text, kept for the heartbeat re-push
  choices   = nil,     -- the resolved choice list we were handed (for the confirm callback)
  fieldOpen = nil,     -- resolved property name for m_AreDialogsOpen (see resolveFields)
  fieldScroll = nil,   -- ...and for m_dialogIsScrollable
  fieldHub  = nil,     -- ...and for m_activeHubID (nil = unresolved, false = unreadable)
  fieldsTried = false,
  selfPush  = false,   -- re-entrancy flag: our own OnDialogsData call must not be blocked by our override
  consumed  = false,   -- one input per frame
  lastMove  = -999,
  lastPush  = -999,
  reassert  = false,   -- heartbeat re-push; auto-enabled only if an Override failed to register
  inited    = false,
  warned    = false,
}

-- Tuning, overridable via DialogUI.bind{}.
local OPT = {
  noCombat  = false,   -- apply GameplayRestriction.NoCombat while the box is up
  reassert  = 1.0,     -- heartbeat interval (s) when the re-push safety net is active
  debug     = false,   -- log every action name while the box is up
  moveDebounce = 0.12, -- collapse the same-frame burst of nav actions into one move
}

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

-- Localization chokepoint for V's choices (replaces the old drawChoiceRows one). Unlike the
-- ImGui box this renders in the GAME's font, so every shipping language displays properly.
local function T(s)
  local out = s
  if Lang and Lang.t then pcall(function() out = Lang.t(s) end) end
  return tostring(out or "")
end

-- Construct a game struct.
--
-- ⚠️ v1.63.1 — DO NOT go back to `_G[name].new()`. CET resolves RTTI type names through the
-- __index of the MOD SANDBOX environment, and a plain `_G[...]` table index can bypass that
-- resolution entirely and hand back nil. Every shipped mod that builds these structs
-- (QuestRunner, AMM, the Train/Metro mods) uses a BARE direct reference, and so must we. The
-- first cut of this file used `_G[full]`; it passed the offline harness (which defines real
-- globals, so `_G` lookup worked there) and produced an empty picker in-game.
--
-- Each candidate is a thunk, so an unresolved name is a caught pcall error rather than a crash.
-- Both spellings exist in the RTTI (`gameinteractionsvisListChoiceData` / `ListChoiceData`) and
-- which one CET exposes has moved between builds, so try the pair. `made` records which form won,
-- purely so DialogUI.diagnose() can report it.
local made = {}
local function tryNew(label, thunks)
  for i, f in ipairs(thunks) do
    local ok, v = pcall(f)
    if ok and v ~= nil then
      if made[label] == nil then made[label] = i end
      return v
    end
  end
  made[label] = false
  return nil
end

local function newListChoiceData()
  return tryNew("ListChoiceData", {
    function() return gameinteractionsvisListChoiceData.new() end,
    function() return ListChoiceData.new() end,
    function() return _G["gameinteractionsvisListChoiceData"].new() end,
  })
end

local function newListChoiceHubData()
  return tryNew("ListChoiceHubData", {
    function() return gameinteractionsvisListChoiceHubData.new() end,
    function() return ListChoiceHubData.new() end,
    function() return _G["gameinteractionsvisListChoiceHubData"].new() end,
  })
end

local function newDialogChoiceHubs()
  return tryNew("DialogChoiceHubs", {
    function() return gameinteractionsvisDialogChoiceHubs.new() end,
    function() return DialogChoiceHubs.new() end,
    function() return _G["gameinteractionsvisDialogChoiceHubs"].new() end,
  })
end

local function newChoiceTypeWrapper()
  return tryNew("ChoiceTypeWrapper", {
    function() return gameinteractionsChoiceTypeWrapper.new() end,
    function() return ChoiceTypeWrapper.new() end,
  })
end

local function newChoiceCaption()
  return tryNew("ChoiceCaption", {
    function() return gameinteractionsChoiceCaption.new() end,
    function() return InteractionChoiceCaption.new() end,
  })
end

-- ---------------------------------------------------------------------------
-- Building the hub
-- ---------------------------------------------------------------------------

-- One row. `c` is a resolved choice from init.lua's openChoiceMenu: { text, final, icon, dim }.
--   final = true -> gameinteractionsChoiceType.QuestImportant, the game's GOLD "point of no
--     return" styling (dialogUI.script:752). This is exactly what the old COL.barDim plate was
--     imitating by hand.
--   dim   = true -> Inactive, the greyed-out styling (dialogUI.script:328).
--   no type at all -> the default cyan (dialogUI.script:765 `iconColor = m_Active`), i.e. what a
--     normal V dialogue line looks like. Do NOT set Blueline here - that's the world-prompt style.
local function buildChoice(c)
  local choice = newListChoiceData()
  if not choice then return nil end

  local text = T(c.text)
  -- The widget parses a LEADING "[Tag] text" out of localizedName into a caption tag when the
  -- choice carries no captionParts (dialogUI.script:311-318). A line that legitimately opens with
  -- '[' would be silently eaten, so nudge it out of that pattern with a leading space.
  if text:sub(1, 1) == "[" then text = " " .. text end
  pcall(function() choice.localizedName = text end)

  -- "None" = no dedicated input glyph, so the row shows the normal selection hint instead of a
  -- key badge (dialogUI.script:735-743). Matches vanilla dialogue rows.
  pcall(function() choice.inputActionName = CName.new("None") end)

  if c.final or c.dim then
    pcall(function()
      local w = newChoiceTypeWrapper()
      if not w then return end
      w:SetType(c.dim and gameinteractionsChoiceType.Inactive or gameinteractionsChoiceType.QuestImportant)
      choice.type = w
    end)
  end

  -- Optional caption icon, e.g. c.icon = "PhoneCall" / "WaitIcon" / "OpenVendorIcon".
  if c.icon then
    pcall(function()
      local rec = TweakDBInterface.GetChoiceCaptionIconPartRecord("ChoiceCaptionParts." .. tostring(c.icon))
      if not rec then return end
      local cap = newChoiceCaption()
      if not cap then return end
      cap:AddPartFromRecord(rec)
      choice.captionParts = cap
    end)
  end

  return choice
end

-- The hub. `title` becomes the framed speaker plate: the widget upper-cases it and only draws the
-- frame when the hub is active and the title is non-empty (dialogUI.script:429-436) — which is the
-- native original of the red "JACKIE" box drawNameChild used to paint by hand.
local function buildHub(title, choices)
  local hub = newListChoiceHubData()
  if not hub then return nil end
  pcall(function() hub.id = S.hubId end)
  pcall(function() hub.title = T(title or "Jackie") end)
  pcall(function() hub.choices = choices end)
  pcall(function()
    hub.activityState = gameinteractionsvisEVisualizerActivityState.Active
  end)
  -- hubPriority is NOT a base-game field — Codeware adds it (cp2077-codeware
  -- scripts/Base/Addons/ListChoiceHubData.reds). Set it if present, shrug if Codeware is absent.
  pcall(function() hub.hubPriority = 1 end)
  return hub
end

-- ---------------------------------------------------------------------------
-- Talking to the controller
-- ---------------------------------------------------------------------------

-- `m_AreDialogsOpen` / `m_dialogIsScrollable` are `protected var`s on InteractionUIBase. CET does
-- expose them, but whether it strips the `m_` prefix has differed across CET builds — and getting
-- this wrong means the root stays invisible and NOTHING renders, with no error. So resolve it once,
-- empirically: whichever spelling reads back a boolean is the real one. If neither does we fall
-- back to driving the base OnDialogsData handler, which sets both fields itself.
local function resolveFields(ctrl)
  if S.fieldsTried then return end
  S.fieldsTried = true
  for _, n in ipairs({ "AreDialogsOpen", "m_AreDialogsOpen" }) do
    local ok, v = pcall(function() return ctrl[n] end)
    if ok and type(v) == "boolean" then S.fieldOpen = n; break end
  end
  for _, n in ipairs({ "dialogIsScrollable", "m_dialogIsScrollable" }) do
    local ok, v = pcall(function() return ctrl[n] end)
    if ok and type(v) == "boolean" then S.fieldScroll = n; break end
  end
  log("controller fields resolved: open=" .. tostring(S.fieldOpen) ..
      " scroll=" .. tostring(S.fieldScroll) ..
      (S.fieldOpen and "" or "  <- falling back to the OnDialogsData route"))
end

-- Push a hub list (possibly empty = hide) into the controller and force a redraw.
--
-- ⚠️ `selfPush` is not optional. The guards installed in DialogUI.init() block UpdateDialogsData /
-- OnDialogsData while our box is up — and they cannot tell the game's push from ours. Without this
-- flag the very first push of a NEW hub while one is already shown gets swallowed by our own
-- override, and the picker silently keeps displaying the previous node's choices.
local function pushHubs(hubs, now)
  local ctrl = S.ctrl
  if not ctrl then return false end
  resolveFields(ctrl)

  local data = newDialogChoiceHubs()
  if not data then log("DialogChoiceHubs.new() failed - cannot push"); return false end
  pcall(function() data.choiceHubs = hubs end)
  local n = #hubs

  -- v1.63.1: BOTH routes, every time, in this order. They are individually idempotent, and each
  -- covers the other's failure mode:
  --
  --  A) OnDialogsData is the game's OWN complete handler (interactionUIBase.script:52-61) — it sets
  --     m_AreDialogsOpen itself and makes the three follow-up calls. Preferred, because it needs no
  --     guess about what CET calls a protected field.
  --  B) Write the gate + make the three calls by hand. Covers the case where OnDialogsData can't be
  --     invoked from Lua at all.
  --
  -- The first cut ran B first and only fell back to A `if not ok`. That was a real hole: a protected
  -- field WRITE that silently no-ops raises no error, so B "succeeded" while doing nothing at all and
  -- A never ran. Running both removes the guesswork entirely for the price of a redundant redraw.
  S.selfPush = true
  local okA = pcall(function() ctrl:OnDialogsData(ToVariant(data)) end)
  local okB = pcall(function()
    if S.fieldOpen then
      ctrl[S.fieldOpen] = (n > 0)
      if S.fieldScroll then ctrl[S.fieldScroll] = (n > 1) end
    end
    ctrl:UpdateDialogsData(data)
    ctrl:OnInteractionsChanged()
    pcall(function() ctrl:UpdateListBlackboard() end)   -- `private`; nice-to-have, never fatal
  end)
  S.selfPush = false

  S.pushRoute = (okA and "OnDialogsData" or "-") .. "/" .. (okB and "fields+calls" or "-")
  S.lastPush = now or CLOCK()
  if not (okA or okB) then log("push FAILED on both routes (controller rejected every call)") end
  return (okA or okB)
end

-- Publish the highlighted row. SetInt only signals on an actual change, so calling this every
-- frame is free; the delayed listener runs OnDialogsSelectIndex -> OnInteractionsChanged, which is
-- what repaints the highlight (dialogUI.script:57-61, 329).
local function publishIndex(force)
  pcall(function()
    local defs = GetAllBlackboardDefs()
    local bb   = Game.GetBlackboardSystem():Get(defs.UIInteractions)
    if bb then bb:SetInt(defs.UIInteractions.SelectedIndex, S.sel) end
  end)
  -- ...and drive the controller directly too, so a move repaints THIS frame rather than next.
  if force and S.ctrl then pcall(function() S.ctrl:OnDialogsSelectIndex(S.sel) end) end
end

-- ---------------------------------------------------------------------------
-- Publish WHICH HUB IS ACTIVE. (v1.3.1 — the missing half of publishIndex.)
--
-- THE BUG THIS FIXES: "the choices are there, but nothing shows which one I'm on", intermittently,
-- roughly three opens in four. Only the selection HIGHLIGHT is lost; the rows themselves are fine.
-- (Reported against NCLucy on 2026-08-14; the same file ships in NCLives and JackieLives.)
--
-- The widget decides that per hub, in one expression (dialogUI.script:87):
--     currentItem.SetData( hubData, hubData.id == m_activeHubID, m_selectedIndex, ... )
-- `isSelected` false makes every row in the hub paint unselected (dialogUI.script:328 —
-- `SetSelected( m_isSelected && m_selectedInd == i )`), which is EXACTLY the reported symptom: the
-- text is ours, the highlight is gone. So the whole bug is `m_activeHubID` drifting off our id.
--
-- Three pieces of controller state have to stay ours while the box is up, and until now they were
-- defended very unevenly:
--     m_data          two Overrides (OnDialogsData + UpdateDialogsData) AND both push routes.
--     m_selectedIndex an Override, PLUS this blackboard write every frame.
--     m_activeHubID   an Override, and a single direct call at open. Nothing else.  <-- the leak
--
-- Why the Override alone is not enough. `UIInteractions.ActiveChoiceHubID` is a real blackboard
-- field written NATIVELY by the interaction system — no script in the game writes it, so it moves
-- whenever the world's interactions change: a car, a door, a vendor, an NPC walking past, or our own
-- "[F] Talk" prompt going away as the conversation opens. Blocking the callback stops the controller
-- being updated, but it leaves the BLACKBOARD holding a foreign id — and the base controller re-seeds
-- itself straight from the blackboard on every re-initialise:
--     interactionUIBase.script:34   OnDialogsActivateHub( bb.GetInt( ActiveChoiceHubID ) )
-- The HUD re-initialises far more often than it looks (menu open/close, HUD rebuilds, scene and
-- camera transitions), and each one reloads that field. Whether it happens during any given
-- conversation is a coin toss, which fits an intermittent bug that never reproduced on a quiet test.
--
-- So: stop treating the blackboard as something to defend against and write it, exactly like
-- SelectedIndex. `SetInt` only signals on a real change, so the steady state costs nothing and the
-- widget's selection animation does NOT re-run every frame (the pulse that keeps the heartbeat
-- re-push switched off).
--
-- ⚠️ HONESTY, because the next person will want to know how sure we were: this is the mechanism the
-- evidence FITS, not one that was caught in the act. tools/test_dialogui.lua shows that the scripted
-- re-seed is in fact already stopped by guard 3, which means some other, unobservable route reached
-- the player — native code, or a window where `S.shown` was false. That is exactly why this write is
-- paired with repairHub() below, which fixes the drift whatever caused it and LOGS it. If the
-- highlight ever fails again, the log will finally name the route.
-- ---------------------------------------------------------------------------
local function publishHub()
  pcall(function()
    local defs = GetAllBlackboardDefs()
    local bb   = Game.GetBlackboardSystem():Get(defs.UIInteractions)
    if bb then bb:SetInt(defs.UIInteractions.ActiveChoiceHubID, S.hubId) end
  end)
end

-- ---------------------------------------------------------------------------
-- ...and the belt to that pair of braces: WATCH `m_activeHubID` AND REPAIR IT.
--
-- Owning the blackboard closes the re-seed route, and the Override closes the scripted route. What
-- neither can close is a write we never see — native code, or a path that lands while `S.shown` is
-- briefly false. Since the symptom is silent (a highlight that simply isn't there) and the state is
-- one integer, the honest defence is to READ it back every frame and put it right when it is wrong.
--
-- Same trick as resolveFields(): CET's spelling of a protected/private field has moved between
-- builds, so resolve it empirically — whichever name reads back a number is the real one — and if
-- neither does, this whole check disables itself and we rely on the two guards above.
--
-- Repair is conditional, and that matters: re-activating the hub unconditionally would re-run
-- DialogHubLogicController's selection animation every single frame (dialogUI.script:334
-- `AnimateSelection()`), which is the visible pulse that keeps the heartbeat re-push switched off.
-- Only a wrong value costs anything.
-- ---------------------------------------------------------------------------
local function readHubField(ctrl)
  if S.fieldHub == false then return nil end
  if S.fieldHub == nil then
    S.fieldHub = false
    for _, n in ipairs({ "m_activeHubID", "activeHubID" }) do
      local ok, v = pcall(function() return ctrl[n] end)
      if ok and type(v) == "number" then S.fieldHub = n; break end
    end
    log("active-hub field resolved: " .. tostring(S.fieldHub) ..
        (S.fieldHub and "" or "  <- not readable; running on the guards alone"))
  end
  local ok, v = pcall(function() return ctrl[S.fieldHub] end)
  return ok and type(v) == "number" and v or nil
end

local function repairHub()
  local ctrl = S.ctrl
  if not ctrl then return end
  local live = readHubField(ctrl)
  if live == nil or live == S.hubId then return end
  -- Loud on purpose: this line is the proof of WHAT moves the id, which four days of reading the
  -- decompiled scripts could not settle. If a bug report ever shows the highlight failing again,
  -- the log now says whether the id drifted and to what.
  log("active hub drifted to " .. tostring(live) .. " while our box was up — restoring " ..
      tostring(S.hubId) .. ". (This is the highlight bug; please send the log.)")
  publishHub()
  pcall(function() ctrl:OnDialogsActivateHub(S.hubId) end)
end

-- Hand the field back when we close. Only if it is still OURS: on the preempt path a real
-- conversation is opening in the same breath, and stomping its hub id with -1 would break the
-- game's own highlight — the very bug we are fixing, aimed at the base game.
local function unpublishHub()
  pcall(function()
    local defs = GetAllBlackboardDefs()
    local bb   = Game.GetBlackboardSystem():Get(defs.UIInteractions)
    if not bb then return end
    if bb:GetInt(defs.UIInteractions.ActiveChoiceHubID) == S.hubId then
      bb:SetInt(defs.UIInteractions.ActiveChoiceHubID, -1)
    end
  end)
end

-- ---------------------------------------------------------------------------
-- CONTROLLER CAPTURE
-- ---------------------------------------------------------------------------
-- `InteractionUIBase` is ABSTRACT and has several subclasses (the interactions hub, the looting
-- list, the dialogue widget). Observing OnInitialize on the BASE captures whichever one happened
-- to initialise last — and if that isn't the dialogue widget, UpdateDialogsData resolves to the
-- base no-op (interactionUIBase.script:71-74) and nothing ever renders. That is almost certainly
-- the real cause of the "press Esc twice after a reload" wart in the reference implementations.
--
-- So we only ever capture from methods DECLARED ON `dialogWidgetGameController` itself, which
-- guarantees the instance is the right one. OnInteractionsChanged is the useful one in practice:
-- it fires whenever ANY interaction data changes — including our own "[F] Talk" world prompt — so
-- by the time V is close enough to press F, the controller is already captured.
local function capture(this) if this then S.ctrl = this end end

function DialogUI.init()
  if S.inited then return end
  S.inited = true

  local captured = 0
  for _, m in ipairs({ "OnInitialize", "OnInteractionsChanged", "OnMenuVisibilityChange" }) do
    if pcall(function() Observe("dialogWidgetGameController", m, capture) end) then captured = captured + 1 end
  end

  local overrides = 0

  -- 1) PRIMARY GUARD. The game pushes DialogChoiceHubs constantly during play (usually empty, at
  --    the end of a scene). Letting the base handler run would set m_AreDialogsOpen = false and
  --    hide our box. Blocked while ours is up — EXCEPT for a real conversation starting, which
  --    must always win: we stand down and let it through.
  if pcall(function()
    Override("InteractionUIBase", "OnDialogsData", function(this, value, wrapped)
      if S.shown and not S.selfPush then
        local incoming = 0
        pcall(function() incoming = #(FromVariant(value).choiceHubs) end)
        if incoming > 0 then
          -- A real in-game dialogue is opening. Yield the widget to it and end our conversation.
          log("real dialogue opening (" .. incoming .. " hubs) — standing down.")
          DialogUI.hide(true)
          if deps.onPreempt then pcall(deps.onPreempt) end
          return wrapped(value)
        end
        return                      -- swallow the empty push that would have hidden us
      end
      -- NOTE: deliberately NO capture(this) here. This override is on the ABSTRACT base, so `this`
      -- is just as likely to be the looting or interactions controller — capturing it would
      -- reintroduce the exact wrong-subclass bug the capture list above exists to avoid.
      return wrapped(value)
    end)
  end) then overrides = overrides + 1 end

  -- 2) BACKSTOP for (1): even if the base override above fails to register on some build, this one
  --    still stops the game's data from replacing m_data.
  if pcall(function()
    Override("dialogWidgetGameController", "UpdateDialogsData", function(this, data, wrapped)
      capture(this)
      if S.shown and not S.selfPush then return end
      return wrapped(data)
    end)
  end) then overrides = overrides + 1 end

  -- 3) Keep OUR hub the active one — the active id is what gives the list its selection highlight
  --    (dialogUI.script:87). NOTE this guard is necessary but NOT sufficient on its own: it stops
  --    the controller being updated, but the blackboard behind it keeps the foreign id and re-seeds
  --    the controller on the next re-initialise. publishHub() in tick() is the other half.
  if pcall(function()
    Override("dialogWidgetGameController", "OnDialogsActivateHub", function(this, id, wrapped)
      capture(this)
      if S.shown and id ~= S.hubId then return end
      return wrapped(id)
    end)
  end) then overrides = overrides + 1 end

  -- 4) Keep OUR highlighted row — the game also writes SelectedIndex.
  if pcall(function()
    Override("dialogWidgetGameController", "OnDialogsSelectIndex", function(this, idx, wrapped)
      capture(this)
      if S.shown and idx ~= S.sel then return end
      return wrapped(idx)
    end)
  end) then overrides = overrides + 1 end

  -- If any guard failed to register the box can be clobbered by the game at any moment, so turn on
  -- the heartbeat re-push as a safety net. When all four registered (the normal case) it stays off,
  -- because a re-push re-runs the widget's selection animation and would visibly pulse.
  S.reassert = (overrides < 4)
  S.diagCaptures, S.diagOverrides = captured, overrides   -- for DialogUI.diagnose()

  log("init: captures=" .. captured .. "/3  overrides=" .. overrides .. "/4" ..
      (S.reassert and "  <- GUARD MISSING, heartbeat re-push ENABLED" or ""))
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function DialogUI.bind(opts)
  for k, v in pairs(opts or {}) do
    if OPT[k] ~= nil then OPT[k] = v else deps[k] = v end
  end
end

function DialogUI.isShown() return S.shown end
function DialogUI.hasController() return S.ctrl ~= nil end

-- ---------------------------------------------------------------------------
-- DIAGNOSE — the one-button "why is there no box?" report.
-- ---------------------------------------------------------------------------
-- The picker has four independent ways to fail silently, and from the player's chair all four look
-- identical (nothing appears). This walks them in order and names the FIRST one that's broken, so a
-- Windows test session produces an answer instead of "it didn't work". Everything is pcall'd; it is
-- safe to run any time, in or out of a conversation.
--
-- Reads the log at:  bin\x64\plugins\cyber_engine_tweaks\mods\JackieLives\jackie_debug.log
function DialogUI.diagnose()
  log("================ DIALOGUE PICKER DIAGNOSE (v" .. DialogUI.VERSION .. ") ================")

  -- 1. Can we even construct the structs? This is the failure that shipped in the first cut.
  local t = {
    { "ListChoiceData",    newListChoiceData },
    { "ListChoiceHubData", newListChoiceHubData },
    { "DialogChoiceHubs",  newDialogChoiceHubs },
    { "ChoiceTypeWrapper", newChoiceTypeWrapper },
    { "ChoiceCaption",     newChoiceCaption },
  }
  local structsOk = true
  for _, e in ipairs(t) do
    local v = e[2]()
    local how = made[e[1]]
    local form = (how == 1 and "full name") or (how == 2 and "alias") or (how == 3 and "_G lookup") or "NONE"
    log(("1. struct %-18s %s   (resolved via: %s)"):format(e[1], v ~= nil and "OK" or "*** FAILED ***", form))
    if v == nil then structsOk = false end
  end
  if not structsOk then
    log("VERDICT: the game structs can't be constructed -> every choice fails to build -> empty box.")
    log("         This is an RTTI-name / CET-version problem, not a logic problem. Send this log.")
    log("=====================================================================")
    return false
  end

  -- 2. Do we hold the dialogue controller? Without it there is nothing to draw into.
  log("2. controller captured: " .. tostring(S.ctrl ~= nil))
  if not S.ctrl then
    log("   The dialogWidgetGameController was never handed to us. Observe() may not have registered,")
    log("   or its methods never fired. Open+close the ESC menu once and run this again.")
    log("VERDICT: no controller. Nothing can render.")
    log("=====================================================================")
    return false
  end
  resolveFields(S.ctrl)
  log("   protected-field spelling: open=" .. tostring(S.fieldOpen) .. " scroll=" .. tostring(S.fieldScroll))

  -- 3. Did the hooks register? A missing guard means the game can wipe the box a frame later, which
  --    looks exactly like "it never appeared".
  log("3. hooks: captures=" .. tostring(S.diagCaptures) .. "/3  overrides=" .. tostring(S.diagOverrides) .. "/4" ..
      (S.reassert and "   (heartbeat re-push ON)" or ""))

  -- 4. Actually push a hub and report which route the controller accepted. This is the real test:
  --    if it prints two OKs and you still see nothing, the problem is downstream of us (the widget
  --    itself), which is a completely different investigation.
  local probe = { { text = "DIAGNOSE row 1" }, { text = "DIAGNOSE row 2", final = true } }
  local before = S.shown
  local shown  = DialogUI.show("Jackie", probe, function(i) log("   diagnose: row " .. i .. " confirmed") end)
  log("4. live push: show()=" .. tostring(shown) .. "  routes=" .. tostring(S.pushRoute))
  if shown then
    log("VERDICT: the picker was driven successfully. A 2-row test box should be ON SCREEN NOW.")
    log("         If you can SEE it -> the plumbing is fine; the problem is in the conversation flow.")
    log("         If you CANNOT see it -> the controller accepted our calls but drew nothing.")
    log("         Leaving it up for 10 s so you can close the overlay and look, then closing it.")
    S.diagUntil = CLOCK() + 10.0
  else
    log("VERDICT: show() refused. The log lines above this one say why.")
    if not before then DialogUI.hide() end
  end
  log("=====================================================================")
  return shown
end

-- Standalone picker test: put a real 3-row box up with no conversation, no Jackie, no cooldowns.
-- Decouples "is the picker broken" from "is the dialogue tree broken" — the single most useful thing
-- to know first, and it works from the main menu... er, from anywhere V exists.
function DialogUI.selfTest()
  local rows = {
    { text = "Test choice one" },
    { text = "Test choice two" },
    { text = "Test choice three (final)", final = true },
  }
  local ok = DialogUI.show("Jackie", rows, function(i)
    log("selfTest: you picked row " .. tostring(i) .. " - input routing WORKS.")
  end)
  log("selfTest: show()=" .. tostring(ok) .. "  routes=" .. tostring(S.pushRoute) ..
      "  (arrows/wheel to move, F to select)")
  return ok
end

-- 1-based index of the highlighted row (init.lua / Branch think in 1-based).
function DialogUI.index() return S.sel + 1 end

-- Open the picker.
--   title   : speaker plate text ("Jackie")
--   choices : array of { text = "...", final = bool, dim = bool, icon = "..." }
--   onConfirm(idx1) : called with the 1-BASED index when the player confirms
-- Returns true if the box actually went up.
function DialogUI.show(title, choices, onConfirm)
  if not choices or #choices == 0 then return false end
  if not S.ctrl then
    -- Should be unreachable in practice: the "[F] Talk" prompt fires OnInteractionsChanged on this
    -- exact controller every time V looks at Jackie, long before she can press F. Logged loudly
    -- (once) rather than silently swallowing the conversation.
    if not S.warned then
      S.warned = true
      log("NO CONTROLLER YET — dialogue widget never initialised. If this persists, open and close " ..
          "the ESC menu once (that re-fires OnMenuVisibilityChange and captures it).")
    end
    return false
  end

  local rows = {}
  for _, c in ipairs(choices) do
    local row = buildChoice(c)
    if row then rows[#rows + 1] = row end
  end
  if #rows == 0 then log("show: every choice failed to build"); return false end

  local hub = buildHub(title, rows)
  if not hub then log("show: hub build failed"); return false end

  S.choices, S.count, S.sel = choices, #rows, 0
  S.title     = title
  S.onConfirm = onConfirm
  S.consumed  = false

  -- Order matters: select row 0 and activate OUR hub, then push the data. (Activating first means
  -- the very first paint already has the highlight, so the box never flashes up unselected.)
  -- Both go out TWICE, by design: straight into the controller so this frame is already right, and
  -- into the blackboard so the controller re-seeds from OUR values if it re-initialises later.
  -- PROBE (v1.3.1): what the interaction system had parked in the field before we took it. A value
  -- other than -1 is the highlight bug's fingerprint — that id would have come back on the next
  -- re-seed and un-highlighted the box. Logged at every open so the fix can be confirmed from the
  -- log rather than by squinting at the screen.
  pcall(function()
    local defs = GetAllBlackboardDefs()
    local bb   = Game.GetBlackboardSystem():Get(defs.UIInteractions)
    local was  = bb and bb:GetInt(defs.UIInteractions.ActiveChoiceHubID)
    if was ~= nil and was ~= S.hubId then
      log("hub id was " .. tostring(was) .. " (not ours) — taking it. Highlight would have been lost on a re-seed.")
    end
  end)
  publishHub()
  pcall(function() S.ctrl:OnDialogsSelectIndex(0) end)
  pcall(function() S.ctrl:OnDialogsActivateHub(S.hubId) end)

  S.shown = true                      -- set BEFORE the push so the guards are already armed
  if not pushHubs({ hub }) then
    S.shown = false
    log("show: push failed")
    return false
  end
  publishIndex(false)
  S.warned = false        -- it worked; re-arm the "no controller" warning for a future session

  -- Refresh the on-screen input hints so the dialogue prompts appear rather than the world ones.
  pcall(function() PlayerGameplayRestrictions.PushForceRefreshInputHintsEventToPSM(Game.GetPlayer()) end)
  if OPT.noCombat then
    pcall(function() StatusEffectHelper.ApplyStatusEffect(Game.GetPlayer(), "GameplayRestriction.NoCombat") end)
  end

  log("open (" .. S.count .. " choices) — arrows/scroll move, F selects.")
  return true
end

-- Close the picker. `keepGuards` is used by the preempt path, where the caller is about to let the
-- game's own dialogue data through and must NOT have us push an empty hub over the top of it.
function DialogUI.hide(keepGuards)
  if not S.shown then return end
  S.shown = false                     -- drop the guards first, or our own empty push gets swallowed
  if not keepGuards then pushHubs({}) end
  pcall(function() if S.ctrl then S.ctrl:OnDialogsActivateHub(-1) end end)
  unpublishHub()                      -- ...and in the blackboard too, unless someone else took it
  S.sel, S.count, S.choices, S.onConfirm = 0, 0, nil, nil
  if OPT.noCombat then
    pcall(function() StatusEffectHelper.RemoveStatusEffect(Game.GetPlayer(), "GameplayRestriction.NoCombat") end)
  end
end

-- Move the highlight (wraps), exactly like the old Branch.move.
function DialogUI.move(delta)
  if not S.shown or S.count == 0 then return end
  S.sel = (S.sel + delta) % S.count
  publishIndex(true)
end

function DialogUI.confirm()
  if not S.shown then return end
  local idx = S.sel + 1
  local cb  = S.onConfirm
  DialogUI.hide()
  if cb then pcall(cb, idx) end
end

-- ---------------------------------------------------------------------------
-- INPUT — the native widget reports nothing back, so navigation is entirely ours.
-- ---------------------------------------------------------------------------
-- ChoiceScrollUp/Down + ChoiceApply are the interaction-context actions the reference
-- implementation uses. The rest are the names Antonia's build was CONFIRMED to emit while a
-- choice box is open (v0.41 investigation, carried over from init.lua's old CYCLE_* tables) —
-- deeper dialogue layers deliver the arrows under different names, so accept the lot.
local UP = {
  ChoiceScrollUp = true, UI_MoveUp = true, up_button = true, popup_moveUp = true,
  popup_navigate_up = true, navigate_up = true, MoveUp = true, up = true, UI_Up = true,
  menu_up = true, NavigateUp = true, IK_Up = true,
}
local DOWN = {
  ChoiceScrollDown = true, UI_MoveDown = true, down_button = true, popup_moveDown = true,
  popup_navigate_down = true, navigate_down = true, MoveDown = true, down = true, UI_Down = true,
  menu_down = true, NavigateDown = true, IK_Down = true,
}
local APPLY = { ChoiceApply = true, Interact = true, Choice1 = true, UI_Apply = true }

-- Called from init.lua's PlayerPuppet:OnAction hook while the box is up.
-- Returns true when the action was ours (the caller then stops processing it).
function DialogUI.onAction(name, pressed, released, now)
  if not S.shown then return false end
  if OPT.debug then
    log(("action %s  pressed=%s released=%s"):format(tostring(name), tostring(pressed), tostring(released)))
  end

  if UP[name] or DOWN[name] then
    -- Accept EITHER edge: on the first choice layer the arrows arrive as BUTTON_PRESSED, on deeper
    -- layers only as BUTTON_RELEASED (v0.41 finding). One press emits several matching names in the
    -- same frame, so debounce — the per-frame `consumed` flag plus the time gate collapse the burst
    -- into a single move.
    if not (pressed or released) then return true end
    if S.consumed then return true end
    now = now or 0
    if (now - S.lastMove) < OPT.moveDebounce then return true end
    S.lastMove, S.consumed = now, true
    DialogUI.move(UP[name] and -1 or 1)     -- UP = toward the top row
    return true
  end

  if APPLY[name] then
    -- Confirm stays on the PRESS edge (F has always arrived pressed on every layer).
    if pressed and not S.consumed then
      S.consumed = true
      DialogUI.confirm()
    end
    return true
  end

  -- Anything else: report "handled" so init.lua's hook stops processing it (no stray grunt, no
  -- second conversation starting under this one). Note this does NOT consume the input at the game
  -- level — an Observe can't — so V can still move while the box is up, exactly as with the old
  -- ImGui picker. Set Config.dialogue.pickerNoCombat if you want her weapon locked out too.
  return true
end

-- ---------------------------------------------------------------------------
-- Per-frame. Called from init.lua's onUpdate.
-- ---------------------------------------------------------------------------
function DialogUI.tick(now)
  S.consumed = false
  if not S.shown then return end

  -- Left to the main menu / lost the world: the box cannot survive the session.
  if not Game.GetPlayer() then
    S.shown = false
    S.sel, S.count, S.choices, S.onConfirm = 0, 0, nil, nil
    return
  end

  -- DialogUI.diagnose() leaves its probe box up for a few seconds so you can actually look at it.
  if S.diagUntil and (now or 0) >= S.diagUntil then
    S.diagUntil = nil
    log("diagnose: closing the test box.")
    DialogUI.hide()
    return
  end

  publishIndex(false)
  publishHub()          -- v1.3.1: re-take the hub id the moment the interaction system moves it
  repairHub()           -- ...and put the controller right if something moved it anyway

  -- Safety net, active only when one of the four guards failed to register (see DialogUI.init).
  if S.reassert and OPT.reassert > 0 and (now or 0) - S.lastPush >= OPT.reassert then
    local rows = {}
    for _, c in ipairs(S.choices or {}) do
      local row = buildChoice(c)
      if row then rows[#rows + 1] = row end
    end
    local hub = (#rows > 0) and buildHub(S.title or "Jackie", rows) or nil
    if hub then pushHubs({ hub }, now) end
  end
end

return DialogUI
