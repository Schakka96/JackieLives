-- tools/test_dialogui.lua — unit tests for the v1.63 NATIVE DIALOGUE PICKER.
--
-- Run from the repo root:   lua tools/test_dialogui.lua
-- Exits non-zero on failure. Needs only a stock Lua 5.x / LuaJIT (no game, no CET, no Windows).
--
-- This is NOT a copy of the logic: it `require`s the SHIPPED mod/JackieLives/dialogui.lua and runs
-- the real code against a stubbed CET + a stub `dialogWidgetGameController` that mirrors the
-- decompiled render path (interactionUIBase.script:52-61, dialogUI.script:63-99) — including the
-- one line everything hinges on, `m_root.SetVisible(m_AreDialogsOpen)`. So `screen ~= nil` in these
-- tests means "the player would actually see the box", not merely "no error was raised".
--
-- What it pins down:
--   * the three conditions that must ALL hold or nothing renders (data, gate, active hub id);
--   * THE SELF-PUSH INVARIANT — our own guards must not swallow our own push, or opening a new
--     node's choices leaves the PREVIOUS node's list on screen (a real bug, caught here);
--   * `final = true` -> QuestImportant (the game's gold point-of-no-return styling);
--   * a leading "[" is escaped, so a choice isn't silently parsed into a caption tag;
--   * navigation on BOTH input edges (v0.41: pressed on the first layer, released on deeper ones),
--     debounced to one move per burst, wrapping at both ends, 0-based on the wire / 1-based to us;
--   * the game's empty DialogChoiceHubs push must NOT hide us...
--   * ...but a REAL conversation must preempt us and win the widget;
--   * the box drops itself when the world goes away.
--
-- Run it twice, effectively: `resolveFields` picks the readable spelling of the protected
-- `m_AreDialogsOpen` field, and if none reads back it falls back to driving OnDialogsData. Delete
-- the two gate fields from the stub controller below and every test still passes — that's the
-- fallback route.

-- resolve mod/JackieLives/ relative to the repo root (where this is meant to be run from)
package.path = "mod/JackieLives/?.lua;" .. package.path

local fails, checks = 0, 0
local function ok(cond, msg)
  checks = checks + 1
  if not cond then fails = fails + 1; print("  FAIL: " .. msg) else print("  ok  : " .. msg) end
end

-- ---------------------------------------------------------------- struct stubs
local function struct(fields)
  return { new = function() local t = {}; for k, v in pairs(fields or {}) do t[k] = v end; return t end }
end
gameinteractionsvisListChoiceData    = struct{ localizedName = "", inputActionName = "", type = nil, captionParts = nil }
gameinteractionsvisListChoiceHubData = struct{ id = 0, title = "", choices = {}, activityState = nil }
gameinteractionsvisDialogChoiceHubs  = struct{ choiceHubs = {} }
gameinteractionsChoiceTypeWrapper    = { new = function() return { SetType = function(self, t) self.t = t end } end }
gameinteractionsChoiceCaption        = { new = function() return { parts = {}, AddPartFromRecord = function(self, r) self.parts[#self.parts+1] = r end } end }
gameinteractionsChoiceType           = { QuestImportant = "QuestImportant", Inactive = "Inactive", Blueline = "Blueline" }
gameinteractionsvisEVisualizerActivityState = { Active = "Active" }
-- hubPriority is Codeware-only: leave it absent so the pcall path is exercised.

CName = { new = function(s) return s end }
function ToVariant(v) return { __v = v } end
function FromVariant(v) return v and v.__v end

TweakDBInterface = { GetChoiceCaptionIconPartRecord = function(p) return { path = p } end }
StatusEffectHelper = { ApplyStatusEffect = function() end, RemoveStatusEffect = function() end }
PlayerGameplayRestrictions = { PushForceRefreshInputHintsEventToPSM = function() end }

-- ---------------------------------------------------------------- blackboard
local BB = { SelectedIndex = -1 }
local DEFS = { UIInteractions = { SelectedIndex = "SelectedIndex" } }
function GetAllBlackboardDefs() return DEFS end
Game = {
  GetPlayer = function() return { alive = true } end,
  GetAllBlackboardDefs = GetAllBlackboardDefs,
  GetBlackboardSystem = function()
    return { Get = function() return { SetInt = function(_, k, v) BB[k] = v end } end }
  end,
}

-- ---------------------------------------------------------------- Observe/Override
local OBS, OVR = {}, {}
function Observe(cls, m, fn) OBS[cls .. "." .. m] = OBS[cls .. "." .. m] or {}; table.insert(OBS[cls .. "." .. m], fn) end
function Override(cls, m, fn) OVR[cls .. "." .. m] = fn end

-- ---------------------------------------------------------------- the controller
-- Mirrors interactionUIBase.script / dialogUI.script closely enough to catch wiring bugs.
local C = {
  AreDialogsOpen = false, dialogIsScrollable = false,
  m_data = { choiceHubs = {} }, m_activeHubID = -1, m_selectedIndex = 0,
  screen = nil,          -- what the player would actually see
}
local function fire(key, ...) for _, f in ipairs(OBS[key] or {}) do f(C, ...) end end

-- raw implementations (what `wrapped` calls)
local RAW = {}
RAW.UpdateDialogsData    = function(self, data) self.m_data = data end
RAW.OnDialogsActivateHub = function(self, id)   self.m_activeHubID = id;  self:OnInteractionsChanged() end
RAW.OnDialogsSelectIndex = function(self, idx)  self.m_selectedIndex = idx; self:OnInteractionsChanged() end
RAW.OnDialogsData = function(self, variant)
  local data = FromVariant(variant)
  self.AreDialogsOpen = #data.choiceHubs > 0
  self.dialogIsScrollable = #data.choiceHubs > 1
  self:UpdateDialogsData(data)
  self:OnInteractionsChanged()
  self:UpdateListBlackboard()
end

-- dispatch through the override table, exactly as CET would
local function dispatch(name)
  return function(self, a)
    local o = OVR["dialogWidgetGameController." .. name] or OVR["InteractionUIBase." .. name]
    fire("dialogWidgetGameController." .. name, a)
    if o then return o(self, a, function(x) return RAW[name](self, x) end) end
    return RAW[name](self, a)
  end
end
C.UpdateDialogsData    = dispatch("UpdateDialogsData")
C.OnDialogsActivateHub = dispatch("OnDialogsActivateHub")
C.OnDialogsSelectIndex = dispatch("OnDialogsSelectIndex")
C.OnDialogsData        = dispatch("OnDialogsData")
C.UpdateListBlackboard = function() end
C.OnInteractionsChanged = function(self)
  fire("dialogWidgetGameController.OnInteractionsChanged")
  -- dialogUI.script:99 — the whole root is hidden unless the gate is true
  if not self.AreDialogsOpen or #self.m_data.choiceHubs == 0 then self.screen = nil; return end
  local hub = self.m_data.choiceHubs[1]
  local rows = {}
  for i, c in ipairs(hub.choices) do
    rows[i] = { text = c.localizedName, sel = (hub.id == self.m_activeHubID) and (self.m_selectedIndex == i - 1), t = c.type and c.type.t }
  end
  self.screen = { title = hub.title, rows = rows, id = hub.id }
end

-- ---------------------------------------------------------------- run
local DialogUI = require("dialogui")
local logs = {}
DialogUI.bind{ log = function(m) logs[#logs+1] = m end, clock = function() return 0 end }
DialogUI.init()

print("\n== init ==")
ok(#logs > 0 and logs[#logs]:match("overrides=4/4"), "all 4 guards registered ("..tostring(logs[#logs])..")")

print("\n== no controller yet ==")
ok(DialogUI.show("Jackie", {{text="hi"}}) == false, "show() refuses without a controller")

-- capture the controller the way the game would (our [F] Talk prompt fires this)
fire("dialogWidgetGameController.OnInitialize")
ok(DialogUI.hasController(), "controller captured from OnInitialize")

print("\n== show ==")
local picked
local shown = DialogUI.show("Jackie", {
  { text = "Good to see you." },
  { text = "Gotta run." , final = true },
  { text = "[bracket] guard" },
}, function(i) picked = i end)
ok(shown, "show() succeeded")
ok(C.screen ~= nil, "something is on screen")
ok(C.screen and C.screen.title == "Jackie", "title is the speaker plate")
ok(C.screen and #C.screen.rows == 3, "3 rows rendered")
ok(C.screen and C.screen.rows[1].sel == true, "row 1 starts highlighted")
ok(C.screen and C.screen.rows[2].t == "QuestImportant", "final=true -> QuestImportant (gold)")
ok(C.screen and C.screen.rows[3].text:sub(1,1) == " ", "leading '[' escaped so it isn't parsed as a tag")
ok(C.AreDialogsOpen == true, "m_AreDialogsOpen gate set")
ok(C.m_activeHubID == 7732, "our hub is the active one")

print("\n== re-show while already open (the self-push regression) ==")
DialogUI.show("Jackie", { { text = "second node A" }, { text = "second node B" } }, function(i) picked = i end)
ok(C.screen and #C.screen.rows == 2, "new node's choices replaced the old ones")
ok(C.screen and C.screen.rows[1].text == "second node A", "showing the NEW list, not the stale one")

print("\n== navigation ==")
DialogUI.move(1)
ok(DialogUI.index() == 2, "down -> row 2")
ok(BB.SelectedIndex == 1, "SelectedIndex published (0-based)")
ok(C.screen.rows[2].sel == true, "highlight repainted on row 2")
DialogUI.move(1)
ok(DialogUI.index() == 1, "wraps past the end back to row 1")
DialogUI.move(-1)
ok(DialogUI.index() == 2, "up from row 1 wraps to the last row")

print("\n== input routing ==")
DialogUI.tick(1)                                   -- clears the per-frame consumed flag
DialogUI.onAction("up_button", false, true, 1)     -- RELEASED edge (deeper-layer names)
ok(DialogUI.index() == 1, "released-edge arrow moves the highlight")
DialogUI.onAction("up_button", false, true, 1)     -- same frame
ok(DialogUI.index() == 1, "same-frame burst debounced to one move")
DialogUI.tick(2); DialogUI.onAction("ChoiceScrollDown", true, false, 2)
ok(DialogUI.index() == 2, "pressed-edge ChoiceScrollDown also works")

print("\n== confirm ==")
DialogUI.tick(3)
DialogUI.onAction("ChoiceApply", true, false, 3)
ok(picked == 2, "onConfirm got the 1-based index (" .. tostring(picked) .. ")")
ok(DialogUI.isShown() == false, "box closed on confirm")
ok(C.screen == nil, "screen cleared")
ok(C.AreDialogsOpen == false, "gate dropped")

print("\n== the game's empty push must NOT hide us ==")
DialogUI.show("Jackie", { { text = "still here" } }, function() end)
C:OnDialogsData(ToVariant({ choiceHubs = {} }))
ok(C.screen ~= nil and C.screen.rows[1].text == "still here", "empty game push swallowed; box survives")

print("\n== a REAL conversation preempts us ==")
local preempted = false
DialogUI.bind{ onPreempt = function() preempted = true end }
C:OnDialogsData(ToVariant({ choiceHubs = { { id = 99, title = "Panam", choices = { { localizedName = "real line" } } } } }))
ok(preempted, "onPreempt fired")
ok(DialogUI.isShown() == false, "we stood down")
ok(C.screen ~= nil and C.screen.title == "Panam", "the game's dialogue rendered instead of ours")

print("\n== world torn down ==")
DialogUI.show("Jackie", { { text = "x" } }, function() end)
Game.GetPlayer = function() return nil end
DialogUI.tick(9)
ok(DialogUI.isShown() == false, "tick() drops the box when the player is gone")

print(("\n%d/%d checks passed"):format(checks - fails, checks))
os.exit(fails == 0 and 0 or 1)
