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
-- ⚠️ NOT `(name == "nativeSettings") and nil or stub`. In Lua `a and nil or b` can NEVER yield nil —
-- the `and` produces nil, and `nil or b` then hands back b. That one-liner (inherited from NCLives,
-- fixed in both on 2026-08-14) returned a LIVE stub for nativeSettings, so the mod always believed
-- Native Settings was installed: the no-Native-Settings path this comment claims to exercise was
-- never once executed, and nsTick latched `done` against a stub that recorded nothing.
-- 0-Engine gets the same treatment for the same reason: it is OPTIONAL and most players do not have
-- it, so the default run here must exercise the WITHOUT-it path. A live stub would have answered
-- GetVersion() with a stub object, zengine.lua would have refused it, and the 0-Engine section below
-- would have been testing the refusal path while claiming to test the default install.
GetMod = function(name)
  local n = tostring(name)
  if n == "nativeSettings" then return nil end   -- the DEFAULT install: NS is optional
  if n == "0-Engine" then return nil end         -- the DEFAULT install: 0-Engine is optional
  return stub
end
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
  -- Readable, because dialogui.lua's repair path reads them back every frame and silently disables
  -- itself when it cannot ("active-hub field resolved: false"). Without these the 2026-08-14 highlight
  -- fix is never exercised here at all.
  m_activeHubID = -1, m_selectedIndex = 0,
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
-- 3c. Headroom against Lua's 200-local cap
-- ---------------------------------------------------------------------------
-- A Lua chunk may declare at most 200 locals. init.lua is a single chunk and lives near that
-- ceiling, which is WHY the engine's modules are globals (Retrieval / Blaze / Session / Lang /
-- DialogUI / VO / Native) rather than the locals they would obviously otherwise be.
--
-- Exceeding it is a COMPILE error, so it cannot ship silently — `check("init.lua loads")` above would
-- go red. The problem is what it does to the person who hits it: the message names a line at the END
-- of the file that is perfectly innocent, and the fix ("make it a global") is unguessable if you do
-- not already know the rule. Worse, the tempting workaround under local pressure — "it is only used
-- here, make it a local" — is exactly what creates the forward-reference bug §3 exists to catch.
--
-- ⚠️ MEASURED, NOT COUNTED. Counting `^local ` lines with a pattern gets this wrong: a `do ... end`
-- block frees its slots again, one line can declare several names, and `local function` is one. That
-- estimate said 221/200 for a file that compiles fine. So ask the compiler instead — append N throwaway
-- top-level locals and find the largest N that still parses. That is Lua's own accounting, exactly.
print("\n3c. headroom under Lua's 200-local cap")

do
  local fh = io.open(ROOT .. "init.lua", "r")
  local src = fh and fh:read("a") or ""
  if fh then fh:close() end

  local function fits(k)
    local pad = {}
    for i = 1, k do pad[i] = ("local _pad%d = 1"):format(i) end
    return load(src .. "\n" .. table.concat(pad, "\n"), "headroom") ~= nil
  end

  local lo, hi = 0, 256                     -- binary search: ~8 parses, not 256
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if fits(mid) then lo = mid else hi = mid - 1 end
  end

  local HEADROOM = 5
  check(("%d spare top-level local slots"):format(lo), lo >= HEADROOM,
        "fewer than " .. HEADROOM .. " left. Do NOT add another top-level local: make it a GLOBAL, or " ..
        "move it into a module like the seven the engine already holds globally.")
end

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

-- ---------------------------------------------------------------------------
-- 5. The Esc-menu panel, registered through a real Native Settings stub
-- ---------------------------------------------------------------------------
-- §3b reads the SOURCE for the addButton arity mistake. This runs the registration for real against
-- a stub that enforces Native Settings' actual arities, and then PRESSES every control — which is the
-- half source-reading cannot do.
--
-- The stub is deliberately STRICTER than the game: real Native Settings accepts the bad addButton
-- happily (it stores textSize = <function>, callback = nil) and only dies later, at DRAW time, taking
-- that subcategory off the menu. Here it throws at registration instead, so the failure lands on the
-- line that caused it rather than three layers away in a UI we cannot run.
--
-- ⚠️ This section is why the dead "Start the search for Jackie" button was found (2026-08-14). It had
-- been shipping unreachable — the one escape hatch for a player whose questline never started, named
-- on the welcome card, absent from the menu. Keep the arity asserts fatal.
print("\n5. the Esc-menu panel registers, completely")

-- `JL` is a file-LOCAL of init.lua, so unlike NCLives (which exposes NCS through NCL.env) there is no
-- handle on the engine state from out here. We don't need one: nsTick polls every frame and only
-- latches `done` once it has actually registered or given up after 1200 attempts, so swapping GetMod
-- and ticking once more is enough to make it register now.
if events.onUpdate then
  local reg = { tabs = {}, subs = {}, switches = {}, buttons = {}, floats = {}, selectors = {} }
  local realGetMod = GetMod
  GetMod = function(name)
    if tostring(name) ~= "nativeSettings" then return realGetMod(name) end
    return {
      pathExists     = function() return false end,
      addTab         = function(p, l) reg.tabs[#reg.tabs + 1] = { path = p, label = l } end,
      addSubcategory = function(p, l) reg.subs[#reg.subs + 1] = { path = p, label = l } end,
      addSwitch = function(p, label, desc, cur, def, cb)
        assert(type(cb) == "function", "addSwitch without a callback: " .. tostring(label))
        reg.switches[#reg.switches + 1] = { path = p, label = label, desc = desc, cur = cur, def = def, cb = cb }
      end,
      addButton = function(p, label, desc, btn, size, cb)
        assert(type(size) == "number", "addButton textSize must come BEFORE the callback: " .. tostring(label))
        assert(type(cb) == "function", "addButton without a callback: " .. tostring(label))
        reg.buttons[#reg.buttons + 1] = { path = p, label = label, desc = desc, btn = btn, cb = cb }
      end,
      addRangeFloat = function(p, label, desc, lo, hi, step, fmt, cur, def, cb)
        assert(type(cb) == "function", "addRangeFloat without a callback: " .. tostring(label))
        reg.floats[#reg.floats + 1] = { path = p, label = label, cur = cur, def = def, cb = cb }
      end,
      -- v1.70.1. Deliberately STRICTER than the real API on the two things that are silent
      -- failures in game: a current index outside the options list draws a blank row, and a
      -- non-table `options` throws at DRAW time — which takes the whole subcategory with it,
      -- exactly like the addButton arity trap in §3b.
      addSelectorString = function(p, label, desc, options, cur, def, cb)
        assert(type(options) == "table" and #options > 0,
               "addSelectorString needs a non-empty options table: " .. tostring(label))
        assert(type(cur) == "number" and cur >= 1 and cur <= #options,
               ("addSelectorString current index %s is outside its %d options: %s")
                 :format(tostring(cur), #options, tostring(label)))
        assert(type(def) == "number" and def >= 1 and def <= #options,
               "addSelectorString default index is outside its options: " .. tostring(label))
        assert(type(cb) == "function", "addSelectorString without a callback: " .. tostring(label))
        reg.selectors[#reg.selectors + 1] =
          { path = p, label = label, options = options, cur = cur, def = def, cb = cb }
      end,
    }
  end

  -- Flipping a switch calls jlSaveSettings, which writes JL_SETTINGS_FILE relative to the CWD — i.e.
  -- straight into the repo root. Point it at a temp file: a build gate must not leave droppings in
  -- the working tree, and it must never overwrite the tester's own tuning.
  local realSettingsFile = JL_SETTINGS_FILE
  JL_SETTINGS_FILE = os.tmpname()

  _G.print = quiet
  local okReg, errReg = pcall(events.onUpdate, 0.016)
  _G.print = realprint
  GetMod = realGetMod

  check("registration runs without throwing", okReg, errReg)
  check("the panel registers its tab", #reg.tabs == 1 and reg.tabs[1].path == "/jackielives",
        "nsTick registered " .. #reg.tabs .. " tabs — the whole panel would be missing")

  local controls = #reg.switches + #reg.buttons + #reg.floats + #reg.selectors
  check("...and every control on it survived registration", controls >= 6,
        ("only %d controls registered — a throw part-way through takes the REST of the panel with it")
          :format(controls))

  local function findButton(needle)
    for _, b in ipairs(reg.buttons) do if b.label:lower():find(needle, 1, true) then return b end end
  end

  -- THE REGRESSION. Both of these were written the same way and only one had its font size.
  local search = findButton("start the search")
  check("the 'start the search' button is on the menu", search ~= nil,
        "this is the manual escape hatch for a questline that never started — it must be reachable")
  local home = findButton("go home")
  check("the 'Go Home Jackie' recovery button is on the menu", home ~= nil)

  -- Every button's callback must survive a press. They are recovery actions: a player reaches for
  -- them when something is already wrong, which is the worst moment for a second error.
  for _, b in ipairs(reg.buttons) do
    _G.print = quiet
    local ok, err = pcall(b.cb)
    _G.print = realprint
    check("pressing '" .. b.label .. "' doesn't throw", ok, err)
  end

  -- ...and every switch must survive being flipped BOTH ways. The off branch is the one that tears
  -- down whatever the on branch built, and it is the one nobody tries by hand.
  for _, s in ipairs(reg.switches) do
    _G.print = quiet
    local okOn,  errOn  = pcall(s.cb, true)
    local okOff, errOff = pcall(s.cb, false)
    _G.print = realprint
    check("flipping '" .. s.label .. "' both ways doesn't throw", okOn and okOff, errOn or errOff)
  end

  -- ---------------------------------------------------------------------------
  -- 5b. V's voice: the Esc control, and the variant it resolves to (v1.70.1)
  -- ---------------------------------------------------------------------------
  -- V speaks her own dialogue choices now, and the ONE thing a player can change about it is
  -- this selector. Two failure modes it guards, both invisible without the game:
  --   · the selector never registered (a throw here drops the rest of the Voice subcategory);
  --   · the setting is stored but nothing reads it, so the switch appears to do nothing.
  -- The second is why this asserts on jlPlayerVariant()'s OUTPUT rather than on JL.vVoice.
  --
  -- ⚠️ It cannot test what the engine DOES with a variant. That is audible-only and is what
  -- the in-game A/B button exists for. This proves the wiring, not the sound.
  print("\n5b. V's voice control")
  local vSel
  for _, s in ipairs(reg.selectors) do
    if tostring(s.label):lower():find("v's voice", 1, true) then vSel = s end
  end
  check("the \"V's voice\" selector registered", vSel ~= nil,
        "V speaks but the player has no way to change how — " .. #reg.selectors .. " selectors found")

  if vSel and jlPlayerVariant then
    check("...with Auto / Male / Female", #vSel.options == 3, tostring(#vSel.options) .. " options")
    check("...and defaults to Auto", vSel.def == 1)

    -- v1.71 — WHAT THIS CONTROL DOES NOW. It used to pick a different SHAPE of the DialogLineEvent
    -- and hope the engine chose the other take; it never did, because the shape carries no gender at
    -- all (../NCLives/docs/research/vo_gender.md §6.5). jlPlayerVariant is therefore pinned to 0 and
    -- the choice rides on jlTakePref -> VO.femaleTakeId, which substitutes a String ID of our own
    -- whose voiceover-map row points at the female recording.
    --
    -- `JL` is a file-LOCAL in init.lua, so the harness cannot reach into it to fake V's body or the
    -- archive. Both are global FUNCTIONS looked up at call time, though, so swapping them is both
    -- possible and closer to what we mean ("suppose the game reported a female body").
    local realBody, realArchive = jlVBodyMale, jlArchiveLoaded
    _G.print = quiet
    jlVBodyMale     = function() return true end
    jlArchiveLoaded = function() return true end

    pcall(vSel.cb, 3); local prefFemale = jlTakePref()
    pcall(vSel.cb, 2); local prefMale   = jlTakePref()
    pcall(vSel.cb, 1); local prefAuto   = jlTakePref()
    local variantPinned = jlPlayerVariant()

    -- Now the real lever, through VO, on a line we know is gendered.
    local FEM = require("vo_female_ids")
    local realId, synthId
    for k, v in pairs(FEM) do realId, synthId = k, v break end

    pcall(vSel.cb, 1)                                    -- Auto, male body -> no substitution
    local autoMale = VO.femaleTakeId(realId)
    jlVBodyMale = function() return false end
    local autoFemale = VO.femaleTakeId(realId)           -- Auto, female body -> substitute
    pcall(vSel.cb, 2)
    local forcedMale = VO.femaleTakeId(realId)           -- Male never substitutes
    jlVBodyMale = function() return true end
    pcall(vSel.cb, 3)
    local forcedFemale = VO.femaleTakeId(realId)         -- Female wins over a male body
    jlArchiveLoaded = function() return false end
    local noArchive = VO.femaleTakeId(realId)            -- ...but never without the archive
    _G.print = realprint
    jlVBodyMale, jlArchiveLoaded = realBody, realArchive

    check("the setting reaches jlTakePref", prefFemale == "female" and prefMale == "male"
          and prefAuto == "auto",
          ("female=%s male=%s auto=%s"):format(tostring(prefFemale), tostring(prefMale), tostring(prefAuto)))
    check("...and the dead event variant stays pinned to 0", variantPinned == 0,
          "leaving it varying would be harmless today and misleading forever")
    check("vo_female_ids.lua is generated and non-empty", realId ~= nil and type(synthId) == "string")
    check("Auto on a MALE body -> his own take", autoMale == nil)
    check("Auto on a FEMALE body -> the female take", autoFemale == synthId, tostring(autoFemale))
    check("forcing Male never substitutes", forcedMale == nil)
    check("forcing Female wins over a male body (the creator-voice case)",
          forcedFemale == synthId, tostring(forcedFemale))
    check("...but no setting can override a missing archive", noArchive == nil,
          "speaking an id the archive lacks is SILENCE, which is worse than the male take")

    -- The subtitle must follow the AUDIO, not the body — that is the 2026-08-13 report
    -- ("subtitles say chica, his voice says mano") and the reason jlLineText was rewritten.
    -- `Config` is a file-local in init.lua, so read the generated table directly — it is the same
    -- one config.lua exposes as Config.voGender.
    local sub = nil
    pcall(function() sub = require("vo_gender") end)
    local gid = nil
    for k in pairs(sub or {}) do if FEM[k] then gid = k break end end
    if gid then
      local realBody2, realArchive2 = jlVBodyMale, jlArchiveLoaded
      jlVBodyMale     = function() return false end
      jlArchiveLoaded = function() return true end
      _G.print = quiet; pcall(vSel.cb, 1); _G.print = realprint
      local femaleSub = jlLineText(sub[gid].f, "jl_" .. gid)
      jlArchiveLoaded = function() return false end
      local noArchSub = jlLineText(sub[gid].f, "jl_" .. gid)
      jlVBodyMale, jlArchiveLoaded = realBody2, realArchive2
      check("a gendered Jackie line reads FEMALE when the female take plays",
            femaleSub == sub[gid].f, tostring(femaleSub))
      check("...and MALE when the male take plays, even on a female body",
            noArchSub == sub[gid].m,
            "reading the wrong word is the bug; reading the true one is not")
    end

    pcall(vSel.cb, 1)   -- leave the harness on the default
  end

  -- The speak path itself: with no redscript shim behind the stubs, it must fail SILENTLY and
  -- say nil — never throw, and never claim a hold that would freeze the subtitle.
  if jlSpeakPlayerLine then
    _G.print = quiet
    local okSpeak, res = pcall(jlSpeakPlayerLine, "jl_2015663563352219656", "How's your mom?")
    local okNoId       = pcall(jlSpeakPlayerLine, nil, "written line")
    local okAB, whyAB  = pcall(jlVoiceABTest)
    local okTick       = pcall(jlVoiceABTick)
    _G.print = realprint
    check("jlSpeakPlayerLine survives a missing shim", okSpeak, res)
    check("...and an unvoiced row is a no-op, not a hold", okNoId)
    check("the A/B test refuses cleanly with no shim", okAB and whyAB == false,
          "it must report WHY rather than appear to work: " .. tostring(whyAB))
    check("the A/B tick is a no-op when nothing is armed", okTick)
  end

  os.remove(JL_SETTINGS_FILE)
  JL_SETTINGS_FILE = realSettingsFile
else
  check("the settings panel is reachable", false, "no onUpdate handler")
end

-- ---------------------------------------------------------------------------
-- 6. Drive a whole phone call, from the hotkey to a choice the player picks
-- ---------------------------------------------------------------------------
-- The deepest path available without the game, and the one that matters most: it runs the CALL state
-- machine, `Branch` (a file-local — reachable only through this flow), the voice ladder and the native
-- picker together. Everything above proves a path doesn't throw on the way in; this proves the pieces
-- still fit each other.
--
-- The gate is `Retrieval.isUnlocked()`, and Retrieval is one of the engine's globals — so the harness
-- can unlock it honestly rather than reaching into private state. `isAwaitingCall` is forced false so
-- we get the ordinary call tree and not the one-off reunion.
--
-- ⚠️ The stubs make every game call succeed, so this says nothing about whether the box is VISIBLE in
-- game. It says the conversation assembled and the input routing agreed with it.
print("\n6. a phone call runs from hotkey to picked choice")

if hotkeyCb["jl_call"] and events.onUpdate and Retrieval and DialogUI then
  local realUnlocked, realAwaiting = Retrieval.isUnlocked, Retrieval.isAwaitingCall
  Retrieval.isUnlocked     = function() return true end
  Retrieval.isAwaitingCall = function() return false end

  _G.print = quiet
  local ok, err = pcall(function()
    hotkeyCb["jl_call"]()
    for _ = 1, 600 do events.onUpdate(0.05) end   -- 30 s: ring -> connect -> his line -> the menu
  end)
  _G.print = realprint
  check("the call runs without throwing", ok, err)
  check("...and it ends at an open choice menu", DialogUI.isShown() == true,
        "Branch never handed off to the picker — the player would be on a silent call")

  local rows = DialogUI.isShown() and 0 or nil
  if DialogUI.isShown() then
    -- Navigation and confirm are the mod's own (the widget is draw-only), so they are worth exercising
    -- against a REAL menu rather than the synthetic one in test_dialogui.lua.
    local first = DialogUI.index()
    DialogUI.move(1)
    check("...arrows move the highlight", DialogUI.index() ~= first,
          "index stuck at " .. tostring(first) .. " — the menu has fewer than 2 rows, or move() is dead")
    _G.print = quiet
    local okPick, errPick = pcall(function() DialogUI.confirm() end)
    _G.print = realprint
    check("...and confirming a choice doesn't throw", okPick, errPick)
    check("...and the picker closed behind it", DialogUI.isShown() == false)
  end

  -- v1.69.2: the log must name the ROWS. A menu built wrong (a gated topic that leaked, a sign-off
  -- sorted into the wrong place) is indistinguishable from a correct one in "menu open (5 choices)",
  -- and the log is the only thing a bug report can carry.
  local fh = io.open("jackie_debug.log", "r")
  local logged = fh and fh:read("a") or ""
  if fh then fh:close() end
  check("the menu logged WHICH rows it opened, not just how many",
        logged:find("menu open %(%d+ choices%) %[") ~= nil,
        "openChoiceMenu logged only a count — a wrong menu reads identically to a right one")

  Retrieval.isUnlocked, Retrieval.isAwaitingCall = realUnlocked, realAwaiting
else
  check("the call flow is reachable", false, "jl_call / onUpdate / Retrieval / DialogUI missing")
end

print("\n7. 0-Engine — the WIRING, not the adapter (tools/test_zengine.lua owns the adapter)")
-- test_zengine.lua proves zengine.lua in isolation. What only THIS harness can prove is that
-- init.lua actually consults it: that `jlInCutscene` prefers their value, and — the part that
-- matters most — that the DEFAULT install (no 0-Engine, which is what the GetMod stub answers)
-- still reads the tier off the blackboard exactly as before.
do
  -- (a) THE DEFAULT INSTALL. GetMod answers nil for 0-Engine, so onUpdate's ZEngine.tick has been
  -- running all through this harness and must have given up quietly. ⚠️ It also means the retry
  -- budget (maxTries) is SPENT by now — that is why (b) attaches directly instead of via tick();
  -- driving tick() here would silently test nothing.
  check("without 0-Engine the adapter never attached", ZEngine.present() == false)
  -- ⚠️ NOT "tries == maxTries". This harness ticks onUpdate for ~30 simulated seconds, which at one
  -- try per 3 s is 11 of the 20 — the budget is not spent here, unlike in NCLives' longer run. The
  -- invariant that actually matters is that the retry is BOUNDED: a player without 0-Engine must never
  -- pay a GetMod call forever. So assert the ceiling, not a specific count.
  local tries = tonumber((ZEngine.status() or ""):match("tries=(%d+)")) or -1
  check("...and its retries are bounded", tries >= 1 and tries <= ZEngine.maxTries,
        "tries=" .. tostring(tries) .. " (max " .. tostring(ZEngine.maxTries) .. ")")
  -- ⚠️ THIS is the check that protects every player who does NOT have 0-Engine: the reader must still
  -- answer a boolean off its own blackboard read, exactly as it did before the adapter existed.
  local okOwn, ownCut = pcall(jlInCutscene)
  check("...and jlInCutscene still answers on its own", okOwn and type(ownCut) == "boolean",
        tostring(ownCut))

  -- (b) 0-Engine present, reporting a CINEMATIC tier (5). The stub blackboard cannot produce one, so
  -- a passing check can only mean the value came from them.
  local shared = { blackboard = { scene = { tier = 5 } }, inMenu = false, inCombat = false, inVehicle = false }
  local fake = {
    GetVersion  = function() return "0.18.6" end,
    GetState    = function() return shared end,
    GetDistrict = function() return "Watson" end,
    Register    = function() return { OnFrame = function() return { unsubscribe = function() end } end } end,
  }
  check("0-Engine present -> attaches", ZEngine.attach(fake) == true)
  check("a cinematic tier from THEM is believed", jlInCutscene() == true)

  -- (c) their value must be re-read, not latched at attach — leaving a cutscene has to land, or Jackie
  -- never comes back.
  shared.blackboard.scene.tier = 1
  check("gameplay tier lands immediately", jlInCutscene() == false)

  -- (d) tier 0 means "they have not polled yet". Serving it as `< 4` would answer "not in a cutscene"
  -- during the first frames of a load, which is exactly when a fresh session may be mid-scene.
  shared.blackboard.scene.tier = 0
  local ok0, cut0 = pcall(jlInCutscene)
  check("tier 0 falls back to our own reader", ok0 and type(cut0) == "boolean", tostring(cut0))

  -- (e) and if they vanish mid-session (CET reloaded them), we must not wedge.
  ZEngine.detach()
  local okAfter, cutAfter = pcall(jlInCutscene)
  check("after detach our own reader takes over again", okAfter and type(cutAfter) == "boolean")
end

-- ---------------------------------------------------------------------------
-- 9. THE v1.8.3 ENGINE FIXES, PORTED FROM NCLIVES v1.83
-- ---------------------------------------------------------------------------
-- ⚠️ These are the first checks in this file that drive a STATE MACHINE rather than a pure function,
-- and they are only possible because init.lua now exposes `JL_ENV` (read the note there). Both bugs
-- were found in NCLives and both live in code this repo carries verbatim — which is exactly the drift
-- CLAUDE.md warns about, so they are pinned here rather than trusted to have been ported correctly.
do
  print("\n9. the v1.8.3 engine fixes (culled-body catch-up, CName read-back, arrival outfit)")
  local S = JL_ENV

  -- (a) A load-screen fast travel either leaves the body far away (a DISTANCE — the hard-respawn
  -- ceiling already outranks every guard) or CULLS it (no distance at all). The blind-body branch
  -- handles the second, and it used to sit BELOW the phase guard, so a companion who was mid-dinner
  -- when V travelled stood down on "a phase owns his movement" forever.
  local keep = { spawn = S.summon.spawn, active = S.summon.active, set = S.summon.companionSet,
                 dinner = S.dinner.phase }
  local respawned = 0
  local realRespawn = respawnCompanionAtV
  respawnCompanionAtV = function() respawned = respawned + 1; return true end
  S.summon.active, S.summon.companionSet = true, true
  S.summon.spawn = { handle = { GetWorldPosition = function() return nil end } }  -- handle lives, position doesn't
  S.dinner.phase = "walking"
  S.catchUp.lastAt, S.catchUp.blindSince = nil, (S.clock or 0) - 999
  local ranOk, err = pcall(catchUpTick)
  check("catchUpTick survives an unreadable body", ranOk, tostring(err))
  check("a culled body mid-dinner is respawned, not swallowed by the phase guard", respawned > 0,
        "the blind branch is below the phase guard again")
  respawned = 0
  S.summon.spawn = { handle = { GetWorldPosition = function() return { x = 0, y = 0, z = 0 } end } }
  S.catchUp.blindSince = (S.clock or 0) - 999
  pcall(catchUpTick)
  check("...but a readable body next to V is left alone", respawned == 0)
  check("...and the blind timer clears once the body reads again", S.catchUp.blindSince == nil)
  respawnCompanionAtV = realRespawn
  S.summon.spawn, S.summon.active, S.summon.companionSet = keep.spawn, keep.active, keep.set
  S.dinner.phase = keep.dinner

  -- (b) The appearance read-back tostring()'d a CName, which is the whole struct, so it could never
  -- match the wanted name and warned on EVERY spawn — including correctly dressed ones.
  local keepFix = S.appfix
  local cnameish = setmetatable({}, { __tostring = function()
    return "ToCName{ hash_lo = 0x1, hash_hi = 0x2 --[[ jackie_welles_default --]] }" end })
  S.appfix = { handle = { GetCurrentAppearanceName = function() return cnameish end },
               want = "jackie_welles_default", why = "test", tries = 0, nextAt = 0,
               until_ = (S.clock or 0) + 8.0 }
  jlAppearanceTick()
  check("a CName read-back of the WANTED name counts as success", S.appfix == nil,
        "the tostring(CName) struct is being compared verbatim again")
  local wrong = setmetatable({}, { __tostring = function()
    return "ToCName{ hash_lo = 0x3, hash_hi = 0x4 --[[ someone_else --]] }" end })
  S.appfix = { handle = { GetCurrentAppearanceName = function() return wrong end,
                          PrefetchAppearanceChange = function() end,
                          ScheduleAppearanceChange = function() end },
               want = "jackie_welles_default", why = "test", tries = 0, nextAt = 0,
               until_ = (S.clock or 0) + 8.0 }
  jlAppearanceTick()
  check("...but a DIFFERENT appearance is still re-asserted", S.appfix ~= nil and (S.appfix.tries or 0) > 0)
  S.appfix = keepFix

  -- (c) Every arrival spawn record must carry the outfit the appfix verifies against.
  local sp = jlSpawnArrivalBody({ x = 0, y = 0, z = 0 }, 0.0)
  check("jlSpawnArrivalBody produces a spawn record", sp ~= nil)
  if sp then
    check("...carrying the appearance (without it jlArmAppearanceFix returns false)",
          type(sp.appearance) == "string" and sp.appearance ~= "" and sp.appearance ~= "default",
          tostring(sp.appearance))
  end
end

print(("\n%d checks, %d failed"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
