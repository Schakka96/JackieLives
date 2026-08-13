-- JackieLives — LOAD SIMULATOR (run on the Mac, no game needed)
-- =============================================================================
--   lua tools/loadsim.lua
--
-- WHY THIS EXISTS
-- `luac -p` proves the files COMPILE. The other tools/test_*.lua files each prove one
-- SUBSYSTEM behaves. None of them ever RUNS init.lua, so an error that only happens
-- when a code path executes ships happily to Windows and dies in front of a tester.
--
-- NCLives shipped exactly that as its v0.9.2: the summon gate called `playerPos()` from
-- line 1131, but `playerPos` is a file-LOCAL declared at line 1524. In Lua a local isn't
-- in scope before its declaration, so that call compiled to a lookup of the GLOBAL
-- `playerPos` (nil) and every summon threw "attempt to call a nil value" — before it
-- logged a single line. Two testers, every character, no spawn, an empty log.
--
-- ⚠️ JackieLives is the MOST exposed of the three engines to that bug and was the last to
-- get this harness (ported 2026-08-14). Its init.lua is ~9.6k lines and sits at Lua's hard
-- 200-local cap, which is precisely the pressure that produces "make it a local, it's only
-- used here" — the move that creates a forward reference.
--
-- This harness stubs the CET/game API, loads init.lua for real, runs onInit, and then
-- FIRES EVERY HOTKEY the mod registers — which is what a player actually does. Then it
-- statically scans for the same forward-reference mistake anywhere else in the file, and
-- draws the Esc panel.
--
-- ⚠️ WHAT IT CANNOT DO. The stubs answer everything cheerfully, so a check passing here is
-- never evidence the mod WORKS in game — only that the path didn't blow up on the way in.
-- Anything the mod wraps in pcall() is invisible by design. Do not add a check whose pass
-- depends on a stub returning something plausible; that teaches the reader to ignore the
-- tool, which is worse than not having it.
-- =============================================================================

local ROOT = (arg and arg[1]) or "mod/JackieLives/"
if ROOT:sub(-1) ~= "/" then ROOT = ROOT .. "/" end
package.path = ROOT .. "?.lua;" .. package.path

local fails, checks = 0, 0
local function check(name, ok, detail)
  checks = checks + 1
  if ok then print(("  ok   %s"):format(name))
  else fails = fails + 1; print(("  FAIL %s%s"):format(name, detail and ("\n         " .. detail) or "")) end
end

-- CET runs LuaJIT (5.1), where `math.atan2` exists; standard Lua 5.3+ dropped it in favour of the
-- two-argument math.atan. The engine's yawToward uses atan2, so without this shim every code path
-- that computes a facing throws HERE and nowhere in the game — a fake failure. Shim, don't rewrite.
if not math.atan2 then math.atan2 = function(y, x) return math.atan(y, x) end end

-- ---------------------------------------------------------------------------
-- 1. CET / game API stubs
-- ---------------------------------------------------------------------------
-- Deliberately permissive: any index returns another stub, any call succeeds. We are
-- testing OUR control flow, not the game's.
local events, hotkeys, inputs, hotkeyCb = {}, {}, {}, {}
function registerForEvent(n, f) events[n] = f end
function registerHotkey(n, d, f) hotkeys[#hotkeys + 1] = n; hotkeyCb[n] = f end
function registerInput(n, d, f) inputs[#inputs + 1] = n; hotkeyCb[n] = f end
function registerSetting() end

-- Numeric fields must answer with NUMBERS, not stubs: the mod does string.format("%.3f", pos.x)
-- and arithmetic on coordinates all over. A stub there produces a fake failure.
local NUMERIC = { x = true, y = true, z = true, w = true, i = true, j = true, k = true, r = true,
                  yaw = true, pitch = true, roll = true }
local stub
local function mkstub()
  return setmetatable({}, {
    __index    = function(_, key) return NUMERIC[key] and 0.0 or stub end,
    __call     = function() return stub end,
    __tostring = function() return "<stub>" end,
    __eq       = function() return false end,
    __pairs    = function() return function() return nil end, nil, nil end,   -- an empty collection
    __len      = function() return 0 end,
  })
end
stub = mkstub()

Game, TweakDB, GameOptions, Enum = stub, stub, stub, stub

-- Game ENUMS the companion code reads by name. These are real (aiComponent.script:500,
-- NpcHandle.reds:113) and a permissive stub cannot stand in for them: an enum member on a nil
-- global THROWS inside the caller's pcall, so the call it guards silently never happens and the
-- check passes for the wrong reason.
gamedataSenseObjectType   = { Follower = "Follower", Npc = "Npc" }
gamedataNPCHighLevelState = { Relaxed = "Relaxed", Combat = "Combat", Alerted = "Alerted", Stealth = "Stealth" }

local drewWindow = false   -- set by the Begin stub: proof the panel really drew
local imguiDepth = 0       -- Begin/End balance: a window left open is a broken frame

-- ImGui needs REAL return types, unlike the rest of the API. The window's code reads what widgets
-- return and feeds it straight back into config/settings, so a stub return value would be written
-- into the mod's own state and then serialized to disk — the harness would corrupt the player's
-- settings file just by running. Widgets echo the value they were given; CONTAINERS answer true so
-- every CollapsingHeader body actually executes, which is the only way a draw-path bug is reached.
ImGui = setmetatable({
  Checkbox     = function(_, v) return v and true or false end,
  SliderFloat  = function(_, v) return tonumber(v) or 0.0 end,
  SliderInt    = function(_, v) return tonumber(v) or 0 end,
  InputText    = function(_, v) return tostring(v or "") end,
  Button       = function() return false end,        -- nothing is "clicked" (that's the hotkey test's job)
  Selectable   = function() return false end,
  SmallButton  = function() return false end,
  CollapsingHeader = function() return true end,     -- OPEN every section -> draw every branch
  TreeNode     = function() return false end,
  BeginChild   = function() return true end,
  Begin        = function(name)
                   imguiDepth = imguiDepth + 1
                   drewWindow = drewWindow or (tostring(name) == "Jackie Lives")
                   return true
                 end,
  End          = function() imguiDepth = imguiDepth - 1 end,
  IsItemHovered = function() return true end,        -- exercise the tooltip branches too
  CalcTextSize = function() return 10.0, 10.0 end,
  GetDisplaySize = function() return 1920.0, 1080.0 end,
}, { __index = function() return function() end end })   -- every other ImGui call: harmless no-op

-- Flag/enum tables are INDEXED (ImGuiWindowFlags.NoTitleBar), so they must answer with numbers.
ImGuiWindowFlags = setmetatable({}, { __index = function() return 0 end })
ImGuiCol, ImGuiStyleVar, ImGuiCond, ImGuiTableFlags =
  ImGuiWindowFlags, ImGuiWindowFlags, ImGuiWindowFlags, ImGuiWindowFlags
EulerAngles, Quaternion, Ref, Descriptor  = stub, stub, stub, stub
DynamicEntitySpec, MountEventData, EntityID, Vector3, gameGodModeType, gameMountEventOptions =
  stub, stub, stub, stub, stub, stub
-- AI-ROLE TYPES. native.lua wraps the role assignment in a pcall, so these missing means
-- `AIFollowerRole.new()` throws, is swallowed, and setCompanion quietly returns false — a check
-- passing for the wrong reason. Same family as the `_G[name]` bug in dialogui.
AIFollowerRole, AINoRole = stub, stub
ToCName, ToTweakDBID, TweakDBID, ItemID, gameItemID = function(s) return s end, function(s) return s end, stub, stub, stub
CName        = { new = function(s) return s end }
Vector4      = setmetatable({ new = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end },
                            { __index = function() return stub end })
-- Native Settings UI is an OPTIONAL dependency, so the DEFAULT install does not have it. Answering
-- nil here is what exercises the no-Native-Settings path, where flag defaults must still be applied.
GetMod = function(name) return (tostring(name) == "nativeSettings") and nil or stub end
GetSingleton = function() return stub end
ModArchiveExists      = function() return false end
GameDump              = function() return "" end

-- Observe / Override + the DIALOGUE WIDGET.
-- dialogui.lua obtains the live dialogWidgetGameController by Observe-ing that class, so a no-op
-- Observe means it never gets one and every conversation path bails at "no controller" — which
-- says nothing about the mod. Observe records handlers; the harness fires the capture after onInit.
local observers = {}
Observe = function(cls, method, fn)
  local k = tostring(cls) .. "." .. tostring(method)
  observers[k] = observers[k] or {}
  table.insert(observers[k], fn)
end
ObserveAfter, Override = Observe, function() end

local dialogCtrl
dialogCtrl = {
  AreDialogsOpen = false, dialogIsScrollable = false,
  UpdateDialogsData    = function() end,
  OnInteractionsChanged = function() end,
  UpdateListBlackboard = function() end,
  OnDialogsActivateHub = function() end,
  OnDialogsSelectIndex = function() end,
  OnDialogsData        = function(self, _) self.AreDialogsOpen = true end,
}
local function fireDialogCapture()
  for _, fn in ipairs(observers["dialogWidgetGameController.OnInitialize"] or {}) do
    pcall(fn, dialogCtrl)
  end
  return observers["dialogWidgetGameController.OnInitialize"] ~= nil
end

-- The interaction structs the picker builds. Bare globals ON PURPOSE: CET resolves RTTI type names
-- through the mod sandbox's __index, so `_G[name]` is nil in a real mod — dialogui.lua must use
-- bare references and these mirror that.
local function mkStructType(extra)
  return { new = function()
    local t = {}
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
  end }
end
gameinteractionsvisListChoiceData    = mkStructType()
gameinteractionsvisListChoiceHubData = mkStructType()
gameinteractionsvisDialogChoiceHubs  = mkStructType()
gameinteractionsChoiceTypeWrapper    = mkStructType({ SetType = function() end })
gameinteractionsChoiceCaption        = mkStructType({ AddPartFromRecord = function() end })
gameinteractionsChoiceType                  = setmetatable({}, { __index = function(_, k) return k end })
gameinteractionsvisEVisualizerActivityState = gameinteractionsChoiceType
ToVariant   = function(v) return { __v = v } end
FromVariant = function(v) return v and v.__v end
NewObject, NewProxy   = function() return stub end, function() return stub end

-- ---------------------------------------------------------------------------
-- 2. Load, init, and press every button
-- ---------------------------------------------------------------------------
print("JackieLives load simulation  (" .. ROOT .. ")\n")
print("1. load + init")

local quiet = function() end
local realprint = print
_G.print = quiet                                  -- the mod logs a lot; keep this report readable
local okLoad, errLoad = pcall(dofile, ROOT .. "init.lua")
_G.print = realprint
check("init.lua loads", okLoad, errLoad)
if not okLoad then print("\n" .. checks .. " checks, " .. fails .. " failed"); os.exit(1) end

check("registers hotkeys", #hotkeys > 0, "no hotkey registered — CET would show no bindings")
check("registers an onInit handler", type(events.onInit) == "function")

if events.onInit then
  _G.print = quiet
  local okInit, errInit = pcall(events.onInit)
  _G.print = realprint
  check("onInit runs", okInit, errInit)
end

_G.print = quiet
local capturedDialog = fireDialogCapture()
_G.print = realprint
check("the native picker captured a dialogue controller",
      capturedDialog and DialogUI and DialogUI.hasController(),
      "DialogUI never Observed dialogWidgetGameController.OnInitialize — it cannot draw anything")

-- The engine holds its modules as GLOBALS on purpose: init.lua is at Lua's 200-local cap, so a
-- `local Blaze = require(...)` would not fit. That makes "is the global actually there after load"
-- a real check — a require that silently returned nil would only surface at the first call site.
print("\n1b. the engine's modules are loaded and global (the 200-local-cap contract)")
for _, m in ipairs({ "Retrieval", "Blaze", "Session", "Lang", "DialogUI", "VO", "Native" }) do
  check(m .. " is a live global table", type(_G[m]) == "table",
        "init.lua holds this as a global because it cannot afford a top-level local")
end

print("\n2. every registered hotkey / input fires without throwing")
-- THE regression test for the no-spawn class: pressing Summon must not throw.
for _, name in ipairs(hotkeys) do
  local f = hotkeyCb[name]
  _G.print = quiet
  local ok, err = pcall(f)
  _G.print = realprint
  check(name, ok, err)
end
for _, name in ipairs(inputs) do
  local f = hotkeyCb[name]
  _G.print = quiet
  local ok, err = pcall(f, true)                  -- inputs get a keydown argument
  _G.print = realprint
  check(name .. " (input)", ok, err)
end

-- Press everything a SECOND time. Several hotkeys are toggles, so the second press takes the other
-- branch — the teardown half, which is the half that touches handles the first press created.
for _, name in ipairs(hotkeys) do
  local f = hotkeyCb[name]
  _G.print = quiet
  local ok, err = pcall(f)
  _G.print = realprint
  check(name .. " (second press: the toggle-off branch)", ok, err)
end

if events.onUpdate then
  local ok, err
  _G.print = quiet
  for _ = 1, 60 do                                -- ~1 s of ticks, so timed paths actually advance
    ok, err = pcall(events.onUpdate, 0.016)
    if not ok then break end
  end
  _G.print = realprint
  check("60 onUpdate ticks", ok, err)
end

for _, e in ipairs({ "onOverlayOpen", "onOverlayClose", "onShutdown" }) do
  if events[e] then
    _G.print = quiet
    local ok, err = pcall(events[e])
    _G.print = realprint
    check(e, ok, err)
  end
end

-- ---------------------------------------------------------------------------
-- 3. Forward-reference scan
-- ---------------------------------------------------------------------------
-- The static half of the same bug the hotkey presses cover dynamically: a call to a file-local
-- from ABOVE its `local function` line compiles to a nil GLOBAL and throws the first time that
-- line runs. The hotkeys only reach the paths a press reaches; this reads the whole file.
print("\n3. forward-reference scan (calls to a file-local declared further down)")

local lines, defs, n = {}, {}, 0
for line in io.lines(ROOT .. "init.lua") do
  n = n + 1; lines[n] = line
  local name = line:match("^%s*local function ([%w_]+)%s*%(")
  if name and not defs[name] then defs[name] = n end
end

-- strip block comments (--[[ ]]), line comments and string literals before matching
local inBlock = false
local code = {}
for i = 1, n do
  local l = lines[i]
  if inBlock then
    local close = l:find("%]%]")
    if close then l = l:sub(close + 2); inBlock = false else l = "" end
  end
  local open = l:find("%-%-%[%[")
  if open then l = l:sub(1, open - 1); inBlock = true end
  l = l:gsub("%-%-.*$", ""):gsub('"[^"]*"', '""'):gsub("'[^']*'", "''")
  code[i] = l
end

local bad = 0
for name, defline in pairs(defs) do
  for i = 1, defline - 1 do
    local l = code[i]
    if l ~= "" and (l:find("[^%w_%.:]" .. name .. "%s*%(") or l:find("^" .. name .. "%s*%(")) then
      bad = bad + 1
      print(("  FAIL init.lua:%d calls local '%s', declared at line %d — this is a nil GLOBAL at runtime")
            :format(i, name, defline))
      print("         " .. (lines[i]:gsub("^%s+", "")))
      print("         fix: make the helper a GLOBAL defined lower down (globals resolve at call time)")
    end
  end
end
checks = checks + 1
if bad > 0 then fails = fails + 1 else print("  ok   no forward-reference calls") end

-- ---------------------------------------------------------------------------
-- 3b. Native Settings addButton arity
-- ---------------------------------------------------------------------------
-- The signature is addButton(path, label, desc, buttonText, TEXTSIZE, callback) — the font size sits
-- BEFORE the callback and is easy to leave out, because every other ns.addX takes the callback last.
-- Omit it and nothing complains at registration: nativeSettings stores textSize = <function> and
-- callback = nil. It dies later, at DRAW time, on `text:SetFontSize(option.textSize)` — and the
-- symptom is that the whole SUBCATEGORY silently fails to appear in the Esc menu. That shipped
-- twice in NCLives before this check existed, both times looking perfectly fine in the source.
print("\n3b. Native Settings buttons pass a font size")

local nsBad = 0
for i = 1, n do
  if code[i]:find("addButton%s*%(") then
    local sawSize = false
    for j = i, math.min(i + 12, n) do
      local l = code[j]
      if l:find("^%s*%-?%d+%s*,") then sawSize = true end
      if l:find("function%s*%(") then
        if not sawSize then
          nsBad = nsBad + 1
          print(("  FAIL init.lua:%d addButton has no font-size argument before its callback"):format(i))
          print("         " .. (lines[i + 1] or ""):gsub("^%s+", ""))
          print("         fix: add `18,` on the line above `function()`")
        end
        break
      end
    end
  end
end
checks = checks + 1
if nsBad > 0 then fails = fails + 1 else print("  ok   every addButton passes textSize before its callback") end

-- ---------------------------------------------------------------------------
-- 4. The developer panel actually draws
-- ---------------------------------------------------------------------------
-- onDraw is the one handler a hotkey press never reaches, and it is a long function full of
-- branches. Every CollapsingHeader answers true above, so this walks all of them.
--
-- The Begin/End balance is the check with teeth: onDraw returns early in several places, and an
-- early return that forgets its ImGui.End() leaves the window unterminated. ImGui does not report
-- that — the next frame's windows nest inside ours and the panel looks corrupted instead.
print("\n4. the developer panel draws, and balances every ImGui.Begin")
if events.onDraw then
  imguiDepth, drewWindow = 0, false
  _G.print = quiet
  local ok, err = pcall(events.onDraw)
  _G.print = realprint
  check("onDraw runs", ok, err)
  check("...and Begin/End are balanced", imguiDepth == 0,
        "depth left at " .. tostring(imguiDepth) .. " — an early return skipped an ImGui.End()")

  -- ...and again with the overlay open, which is the state the panel is actually looked at in.
  if events.onOverlayOpen then
    imguiDepth, drewWindow = 0, false
    _G.print = quiet
    pcall(events.onOverlayOpen)
    local ok2, err2 = pcall(events.onDraw)
    pcall(events.onOverlayClose)
    _G.print = realprint
    check("onDraw runs with the overlay open", ok2, err2)
    check("...and is still balanced", imguiDepth == 0,
          "depth left at " .. tostring(imguiDepth))
  end
else
  check("an onDraw handler is registered", false, "the developer panel would never appear")
end

print(("\n%d checks, %d failed"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
