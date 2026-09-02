-- test_zengine.lua — the 0-Engine integration, against a stub of THEIR API
-- =============================================================================
--   lua tools/test_zengine.lua
--
-- The stub mirrors the real shapes read out of 0-Engine 0.18.6 Pure CET
-- (NCLives' docs/research/zero_engine.md — one write-up, three consumers): a table with
-- GetVersion / GetState / Register / GetDistrict, a
-- Register that hands back a scoped handle with OnFrame, and a GetState whose nested tables are
-- behind a READ-ONLY proxy that errors on write, exactly as their DeepReadOnly does.
--
-- ⚠️ WHY THIS TEST EXISTS. The integration is invisible when it works and invisible when it fails —
-- a wrong scene tier does not look like a 0-Engine bug, it looks like the companion freezing in a
-- cutscene. So what is pinned here is BOTH paths with equal weight: every accessor must answer nil
-- (never a guess, never a throw) when 0-Engine is absent, refuses to attach, or changes shape, and
-- the mod must be provably no worse off than before this file existed.
-- =============================================================================

local here = arg and arg[0] and arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/../mod/JackieLives/?.lua;" .. package.path

local ZE = require("zengine")

local T = dofile("tools/tcheck.lua")
local check = T.check

-- reload the module between scenarios: it is a singleton with attach state
local function fresh()
  package.loaded["zengine"] = nil
  local M = require("zengine")
  local logged = {}
  M.bind{ log = function(m) logged[#logged + 1] = tostring(m) end }
  return M, logged
end

-- ---------------------------------------------------------------------------
-- A stub of their side, with their real semantics.
-- ---------------------------------------------------------------------------
-- readOnly() is their DeepReadOnly: reads pass through, WRITES ERROR. If this file ever starts
-- assigning into their state, this is what catches it.
local function readOnly(t)
  return setmetatable({}, {
    __index = function(_, k)
      local v = t[k]
      if type(v) == "table" then return readOnly(v) end
      return v
    end,
    __newindex = function() error("[0-Engine] Attempt to modify read-only state") end,
  })
end

local function fakeEngine(opts)
  opts = opts or {}
  local raw = {
    inMenu = opts.inMenu or false,
    inCombat = opts.inCombat or false,
    inVehicle = opts.inVehicle or false,
    blackboard = { scene = { tier = opts.tier == nil and 1 or opts.tier } },
    derived = { district = opts.district or "Watson" },
  }
  local E = { raw = raw, registered = {}, frames = {} }
  function E.GetVersion() return opts.version or "0.18.6" end
  function E.GetState() return readOnly(raw) end
  function E.GetDistrict() return raw.derived.district end
  function E.Register(name)
    E.registered[#E.registered + 1] = name
    local h = {}
    function h.OnFrame(interval, fn)
      local entry = { interval = interval, fn = fn, live = true }
      E.frames[#E.frames + 1] = entry
      return { unsubscribe = function() entry.live = false end }
    end
    return h
  end
  return E
end

local function installEngine(E)
  _G.GetMod = function(name) if tostring(name) == "0-Engine" then return E end return nil end
end

-- how many times the mod asked for them (the "does it stop spinning" proof)
local function countingGetMod()
  local n = 0
  _G.GetMod = function() n = n + 1; return nil end
  return function() return n end
end

-- ---------------------------------------------------------------------------
print("== version compare (a string compare would call 0.9 newer than 0.18) ==")
-- ---------------------------------------------------------------------------
do
  local M = fresh()
  check("0.18.6 >= 0.18",  M.versionAtLeast("0.18.6", "0.18") == true)
  check("0.18 >= 0.18",    M.versionAtLeast("0.18", "0.18") == true)
  check("0.9 is NOT >= 0.18", M.versionAtLeast("0.9", "0.18") == false)
  check("0.17.9 is NOT >= 0.18", M.versionAtLeast("0.17.9", "0.18") == false)
  check("1.0 >= 0.18",     M.versionAtLeast("1.0", "0.18") == true)
  check("nonsense is refused", M.versionAtLeast(nil, "0.18") == false)
end

-- ---------------------------------------------------------------------------
print("== NOT INSTALLED: the normal case must be a silent, finite no-op ==")
-- ---------------------------------------------------------------------------
do
  local M, logged = fresh()
  local calls = countingGetMod()
  local t = 0
  for _ = 1, 200 do t = t + 1; M.tick(t) end        -- 200 seconds of ticking
  check("never attaches", M.present() == false)
  check("stops asking after maxTries", calls() == M.maxTries, calls() .. " GetMod calls")
  check("sceneTier() is nil, not a guess", M.sceneTier() == nil)
  check("inMenu/inCombat/inVehicle/district all nil",
        M.inMenu() == nil and M.inCombat() == nil and M.inVehicle() == nil and M.district() == nil)
  check("status() still answers", (M.status() or ""):find("installed=false") ~= nil, M.status())
  check("probe() says nothing is wrong",
        table.concat(M.probe(), "\n"):find("nothing is wrong") ~= nil)
  local saidSo = 0
  for _, l in ipairs(logged) do if l:find("not installed") then saidSo = saidSo + 1 end end
  check("said so exactly once in the log", saidSo == 1, saidSo .. " lines")
end

-- ---------------------------------------------------------------------------
print("== INSTALLED: attach, register, and read their state ==")
-- ---------------------------------------------------------------------------
do
  local M = fresh()
  local E = fakeEngine{ tier = 4, inMenu = true, inVehicle = true, district = "Kabuki" }
  installEngine(E)
  M.tick(0)
  check("attached", M.present() == true)
  check("registered as JackieLives", E.registered[1] == "JackieLives")
  check("registered exactly once", #E.registered == 1)
  check("sceneTier comes from their blackboard", M.sceneTier() == 4)
  check("inMenu from them", M.inMenu() == true)
  check("inCombat from them", M.inCombat() == false)
  check("inVehicle from them", M.inVehicle() == true)
  check("district from them", M.district() == "Kabuki")
  check("status shows their version", (M.status() or ""):find("theirVer=0%.18%.6") ~= nil, M.status())
  check("reads are counted (proof for the probe)", (M.status() or ""):find("reads=[1-9]") ~= nil, M.status())

  -- their state follows the world, so ours must not be a snapshot taken at attach time
  E.raw.blackboard.scene.tier = 1
  check("re-reads every call (not cached at attach)", M.sceneTier() == 1)

  -- one registered callback, and their dispatcher can call it
  check("one frame callback registered", #E.frames == 1)
  check("heartbeat interval is throttled, not per-frame", (E.frames[1].interval or 0) >= 60)
  local okFire = pcall(E.frames[1].fn, 300)
  check("their dispatcher can call it without throwing", okFire)

  -- and we hand it back on unload
  M.detach()
  check("detached", M.present() == false)
  check("heartbeat unsubscribed", E.frames[1].live == false)
  check("accessors are nil again after detach", M.sceneTier() == nil)
end

-- ---------------------------------------------------------------------------
print("== tier 0 means 'they have not polled yet' — never answer it ==")
-- ---------------------------------------------------------------------------
-- 0-Engine's cached tier starts at 0 and their readers treat "< 4" as gameplay. Passing 0 through
-- would answer "not in a cutscene" on the first frames of a load, which is exactly when a fresh
-- session is mid-scene. nil hands the question back to our own reader.
do
  local M = fresh()
  installEngine(fakeEngine{ tier = 0 })
  M.tick(0)
  check("attached", M.present() == true)
  check("tier 0 is withheld", M.sceneTier() == nil)
end

-- ---------------------------------------------------------------------------
print("== REFUSALS: an API we don't recognise is declined, not probed ==")
-- ---------------------------------------------------------------------------
do
  local M = fresh()
  installEngine(fakeEngine{ version = "0.9.1" })
  for i = 1, 40 do M.tick(i * 4) end
  check("too old -> never attached", M.present() == false)
  check("status says why", (M.status() or ""):find("refused=") ~= nil, M.status())
  check("accessors nil", M.sceneTier() == nil)
end
do
  local M = fresh()
  local E = fakeEngine{}
  E.GetState = nil                                  -- their layout changed
  installEngine(E)
  M.tick(0)
  check("no GetState -> refused", M.present() == false)
  check("nothing registered", #E.registered == 0)
end
do
  local M = fresh()
  local E = fakeEngine{}
  E.GetVersion = nil
  installEngine(E)
  M.tick(0)
  check("no GetVersion -> refused", M.present() == false)
end

-- ---------------------------------------------------------------------------
print("== THEIR SIDE THROWS: we degrade, we never propagate ==")
-- ---------------------------------------------------------------------------
do
  local M = fresh()
  local E = fakeEngine{}
  installEngine(E)
  M.tick(0)
  check("attached", M.present() == true)
  E.GetState = function() error("boom") end
  check("GetState throwing -> nil", M.sceneTier() == nil)
  check("and inMenu -> nil", M.inMenu() == nil)
  E.GetState = function() return readOnly({}) end   -- shape gone
  check("missing nested shape -> nil", M.sceneTier() == nil)
  E.GetState = function() return readOnly({ blackboard = { scene = { tier = "four" } } }) end
  check("wrong TYPE -> nil (not the string)", M.sceneTier() == nil)
  E.GetDistrict = function() return "Unknown" end
  check("their 'Unknown' district is not a district", M.district() == nil)
  local okProbe = pcall(M.probe)
  check("probe() survives a broken engine", okProbe)
end

-- ---------------------------------------------------------------------------
print("== the A/B switch (Config.zeroEngine.enabled = false) ==")
-- ---------------------------------------------------------------------------
do
  package.loaded["zengine"] = nil
  local M = require("zengine")
  local on = false
  M.bind{ log = function() end, enabled = function() return on end }
  installEngine(fakeEngine{ tier = 4 })
  for i = 1, 40 do M.tick(i * 4) end
  check("switch off -> never attaches even though they are installed", M.present() == false)
  check("switch off -> readers fall back", M.sceneTier() == nil)
  check("status says the switch is off", (M.status() or ""):find("switch=OFF") ~= nil, M.status())
  on = true
  M.tick(1000)
  check("switch back on -> attaches", M.present() == true)
  check("and reads", M.sceneTier() == 4)
end

-- ---------------------------------------------------------------------------
print("== unbound (no init.lua) must not crash — offline harness safety ==")
-- ---------------------------------------------------------------------------
do
  package.loaded["zengine"] = nil
  local M = require("zengine")                      -- deliberately NOT bound
  installEngine(fakeEngine{ tier = 5 })
  local ok = pcall(M.tick, 0)
  check("tick() without bind()", ok)
  check("treated as switched on", M.present() == true)
  check("reads", M.sceneTier() == 5)
  check("status() without bind()", (M.status() or ""):find("attached=true") ~= nil)
end

T.finish()
