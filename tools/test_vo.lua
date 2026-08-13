-- tools/test_vo.lua — unit tests for the v1.66 native voice-over path.
--
-- Run from the repo root:   lua tools/test_vo.lua
-- Exits non-zero on failure. Needs only a stock Lua 5.x interpreter (no game, no CET).
--
-- This loads the REAL vo.lua, the REAL config.lua and the REAL generated duration table, against
-- a stub of the two game APIs it can touch. What it pins down:
--
--   * THE PRECISION RULE. A String ID is ~2e18 and a Lua number is a double, so an id must never
--     become a number — anywhere. This is the failure that would be invisible in game: the wrong
--     line, or no line, with no error. Asserted end to end, including that what reaches redscript
--     is character-for-character what the content wrote.
--   * THE BACKEND LADDER. native -> Audioware -> vocal effort, and every combination of what's
--     installed, because the whole point of v1.66 is that NOTHING is required.
--   * That a negative native probe is never cached (a companion who spoke before Jackie spawned
--     would otherwise be permanently mute for the session).
--   * That every voiced line the content references still resolves to a duration.

package.path = "mod/JackieLives/?.lua;" .. package.path

local fails, checks = 0, 0
local function check(name, ok, detail)
  checks = checks + 1
  if ok then print(("  ok   %s"):format(name))
  else fails = fails + 1; print(("  FAIL %s%s"):format(name, detail and ("\n         " .. detail) or "")) end
end

-- ---------------------------------------------------------------------------
-- Stub the game. `spy` records exactly what each backend was asked to do.
-- ---------------------------------------------------------------------------
local spy
local function reset(opts)
  opts = opts or {}
  spy = { native = {}, audioware = {}, grunts = {}, shimPresent = opts.shim, bankPresent = opts.bank }

  CName = { new = function(s) return { name = s } end }

  local shim = {
    JLVO_Version = function() if not spy.shimPresent then error("no shim") end return 1 end,
    JLVO_PlayLine = function(_, idDec, ctx)
      if not spy.shimPresent then error("no shim") end
      spy.native[#spy.native + 1] = { id = idDec, ctx = ctx, type = type(idDec) }
      return true
    end,
    JLVO_PlayLineAs = function(_, idDec, ctx, tag, restore, dur)
      if not spy.shimPresent then error("no shim") end
      spy.native[#spy.native + 1] =
        { id = idDec, ctx = ctx, type = type(idDec), tag = tag.name, restore = restore.name, dur = dur }
      return true
    end,
  }
  spy.player = setmetatable({}, { __index = shim })

  Game = {
    GetPlayer = function() return spy.player end,
    GetAudioSystemExt = function()
      if not spy.bankPresent then error("no Audioware") end
      return {
        Play     = function(_, n) spy.audioware[#spy.audioware + 1] = n.name; return true end,
        Duration = function(_, n) return n.name == "jl_fallback" and 1.5 or 2.0 end,
      }
    end,
  }

  -- vo.lua caches a positive probe for the session, so each scenario needs a fresh module.
  package.loaded["vo"] = nil
  local VO = require("vo")
  local Config = require("config")
  VO.bind{
    log         = function() end,
    config      = function() return opts.config or Config.voice end,
    readingSecs = function(t) return #t * 0.05 end,
    playEvent   = function(_, ev) spy.grunts[#spy.grunts + 1] = ev end,
  }
  return VO, Config
end

-- The real id shape used throughout the content. 19 digits: not representable as a double.
local ID   = "1660220866564214792"
local SFX  = "jl_" .. ID

-- ---------------------------------------------------------------------------
print("1. id extraction — the precision rule")
-- ---------------------------------------------------------------------------
do
  local VO = reset{ shim = true }
  check("a jl_<digits> sfx yields its id", VO.lineId(SFX) == ID, tostring(VO.lineId(SFX)))
  check("the id stays a STRING", type(VO.lineId(SFX)) == "string")
  check("id is character-for-character the content's digits", VO.lineId(SFX) == ID)

  -- The bug this guards: tonumber() on a 19-digit id silently loses the low digits, so the mod
  -- would ask for a line that does not exist. Prove the danger is real, then prove we avoid it.
  check("tonumber() would corrupt this id (so we never call it)",
        string.format("%.0f", tonumber(ID)) ~= ID,
        "double round-trip gives " .. string.format("%.0f", tonumber(ID)))

  check("non-line events are not ids", VO.lineId("jl_fallback") == nil)
  check("test_tone is not an id", VO.lineId("test_tone") == nil)
  check("a wem-stem alias is not an id", VO.lineId("jl_jackie_q000_f_170a4a14f8405008") == nil)
  check("nil is handled", VO.lineId(nil) == nil)
  check("a short number is not an id", VO.lineId("jl_123") == nil)
end

-- ---------------------------------------------------------------------------
print("\n2. the backend ladder")
-- ---------------------------------------------------------------------------
do
  local VO = reset{ shim = true, bank = false }
  check("shim present -> native", VO.backend() == "native")
  check("a line plays natively", VO.play(SFX, spy.player) == true and #spy.native == 1)
  check("redscript received the id verbatim, as a string",
        spy.native[1].id == ID and spy.native[1].type == "string")
  check("nothing went to Audioware", #spy.audioware == 0)

  VO = reset{ shim = false, bank = true }
  check("no shim, bank present -> audioware", VO.backend() == "audioware")
  check("the line plays through the bank", VO.play(SFX, spy.player) == true and spy.audioware[1] == SFX)
  check("nothing went to the shim", #spy.native == 0)

  VO = reset{ shim = false, bank = false }
  check("neither -> grunt", VO.backend() == "grunt")
  check("an unvoiced line still makes a sound", VO.play(SFX, spy.player) == true and #spy.grunts == 1)
  check("the grunt is a real WWise ono event", spy.grunts[1]:match("^ono_") ~= nil, spy.grunts[1])

  VO = reset{ shim = true, bank = true }
  check("both installed -> native wins", VO.backend() == "native")
  VO.play(SFX, spy.player)
  check("Audioware is not double-played", #spy.audioware == 0 and #spy.native == 1)
end

-- ---------------------------------------------------------------------------
print("\n3. mode overrides")
-- ---------------------------------------------------------------------------
do
  local VO = reset{ shim = true, bank = true, config = { mode = "audioware", gruntPool = { "ono_x" } } }
  VO.play(SFX, spy.player)
  check("mode=audioware forces the old path", #spy.audioware == 1 and #spy.native == 0)

  VO = reset{ shim = true, bank = true, config = { mode = "native", gruntPool = { "ono_x" } } }
  VO.play("jl_fallback", spy.player)
  check("mode=native never touches Audioware on a non-line event", #spy.audioware == 0)

  VO = reset{ shim = true, bank = true, config = { mode = "off", gruntPool = { "ono_x" } } }
  check("mode=off reports off", VO.backend() == "off")
  check("mode=off plays nothing at all",
        VO.play(SFX, spy.player) == false and #spy.native == 0 and #spy.audioware == 0 and #spy.grunts == 0)
end

-- ---------------------------------------------------------------------------
print("\n4. mute — a genuinely silent line (v1.56 muteFallback)")
-- ---------------------------------------------------------------------------
do
  local VO = reset{ shim = false, bank = false }
  check("mute suppresses the vocal effort", VO.play(nil, spy.player, true) == false and #spy.grunts == 0)
  VO = reset{ shim = false, bank = false }
  check("without mute, an unvoiced line grunts", VO.play(nil, spy.player, false) == true and #spy.grunts == 1)
  VO = reset{ shim = true, bank = false }
  check("mute never suppresses a REAL voiced line", VO.play(SFX, spy.player, true) == true and #spy.native == 1)
end

-- ---------------------------------------------------------------------------
print("\n5. the voice-tag swap (how any body speaks any character's lines)")
-- ---------------------------------------------------------------------------
do
  local VO = reset{ shim = true, config = {
    mode = "auto", context = -1, voiceTag = "jackie", restoreVoiceTag = "v", gruntPool = {} } }
  VO.play(SFX, spy.player)
  check("a configured tag routes to PlayLineAs", spy.native[1].tag == "jackie")
  check("and asks for the original tag back", spy.native[1].restore == "v")
  check("with a real duration, not a guess", spy.native[1].dur and spy.native[1].dur > 0.5,
        tostring(spy.native[1].dur))

  VO = reset{ shim = true }
  VO.play(SFX, spy.player)
  check("Jackie's default config does NOT swap tags (he already sounds like himself)",
        spy.native[1].tag == nil)
end

-- ---------------------------------------------------------------------------
print("\n6. probe caching — the bug that would mute a whole session")
-- ---------------------------------------------------------------------------
do
  local VO = reset{ shim = false }
  check("probe fails while the shim looks absent", VO.hasNative(spy.player) == false)
  spy.shimPresent = true   -- e.g. the first line was spoken before a usable entity existed
  check("a later probe succeeds — a negative is never cached", VO.hasNative(spy.player) == true)
  spy.shimPresent = false
  check("a positive IS cached (no per-line RTTI round-trip)", VO.hasNative(spy.player) == true)
end

-- ---------------------------------------------------------------------------
print("\n7. durations")
-- ---------------------------------------------------------------------------
do
  local VO = reset{ shim = true, bank = false }
  local D = require("vo_durations")
  local n = 0
  for _ in pairs(D) do n = n + 1 end
  check("the generated table is present and populated", n > 40, tostring(n) .. " entries")

  local sane = true
  local badKey, badVal
  for id, secs in pairs(D) do
    if type(id) ~= "string" or not id:match("^%d+$") then sane = false; badKey = id end
    if type(secs) ~= "number" or secs < 0.2 or secs > 60 then sane = false; badVal = id .. "=" .. tostring(secs) end
  end
  check("every key is a digit STRING (not a number — precision again)", badKey == nil, tostring(badKey))
  check("every duration is a sane spoken length", badVal == nil, tostring(badVal))
  check("table is internally consistent", sane)

  local someId = next(D)
  check("a known line reports its exact duration", VO.duration("jl_" .. someId) == D[someId])
  check("an unknown line falls back to reading time",
        math.abs((VO.duration("jl_999999999999999999", "hello there") or 0) - 0.55) < 0.01)
  check("no text and no entry -> nil, so the caller keeps its own default",
        VO.duration("jl_999999999999999999") == nil)
end

-- ---------------------------------------------------------------------------
print("\n8. every voiced line the CONTENT references")
-- ---------------------------------------------------------------------------
do
  reset{ shim = true }
  local D = require("vo_durations")
  local referenced, missing = {}, {}
  for _, file in ipairs({ "config.lua", "init.lua", "retrieval.lua", "blaze.lua" }) do
    local fh = io.open("mod/JackieLives/" .. file, "r")
    if fh then
      for id in fh:read("*a"):gmatch("jl_(%d%d%d%d%d%d+)") do referenced[id] = true end
      fh:close()
    end
  end
  local total, have = 0, 0
  for id in pairs(referenced) do
    total = total + 1
    if D[id] then have = have + 1 else missing[#missing + 1] = id end
  end
  check("the content references voiced lines at all", total > 20, tostring(total))
  -- Not fatal: a line with no duration is paced by reading time and still PLAYS. But it should be
  -- rare and known, so the number is pinned rather than left to drift.
  check("at most 3 referenced lines lack a duration", #missing <= 3,
        tostring(#missing) .. " missing: " .. table.concat(missing, ", "))
  check("nearly all referenced lines have exact timing", have / math.max(total, 1) > 0.9,
        ("%d/%d"):format(have, total))
end

-- ---------------------------------------------------------------------------
print("\n9. init.lua wiring")
-- ---------------------------------------------------------------------------
-- JackieLives has no loadsim (NCLives does), so nothing here actually executes init.lua. These
-- are the structural invariants that would otherwise only fail in game, silently:
do
  local src = io.open("mod/JackieLives/init.lua", "r"):read("*a")

  check("vo.lua is required as a GLOBAL", src:match("\nVO%s*=%s*require%(\"vo\"%)") ~= nil,
        "a `local VO` would break the 200-local ceiling AND be invisible to the other modules")
  check("the module cache is cleared first, so a CET soft-reload re-reads it",
        src:match('package%.loaded%["vo"%]%s*=%s*nil') ~= nil)
  check("VO.bind is called at onInit", src:match("VO%.bind%s*{") ~= nil)

  local bindAt   = src:find("VO%.bind%s*{")
  local readingAt = src:find("local function readingSecs")
  local eventAt   = src:find("local function playEventOn")
  -- A file-local isn't in scope ABOVE its declaration: calling one early compiles to a nil
  -- GLOBAL and throws the first time that line runs. This shipped once in NCLives as a total
  -- no-spawn, so it is asserted rather than assumed.
  check("bind happens after readingSecs is declared", readingAt and bindAt and readingAt < bindAt)
  check("bind happens after playEventOn is declared", eventAt and bindAt and eventAt < bindAt)

  check("speakJackieLine routes through VO.play", src:match("VO%.play%(sfx, speaker, mute%)") ~= nil)
  check("nothing calls Audioware directly any more outside vo.lua",
        select(2, src:gsub("GetAudioSystemExt", "")) <= 3,
        "playVoice/voiceDuration should be the only Audioware callers, and they now delegate")
  check("the deploy script ships the shim",
        (io.open("deploy.ps1", "r"):read("*a")):find("r6\\scripts", 1, true) ~= nil)
end

-- ---------------------------------------------------------------------------
print("\n10. the in-game backend switch (v1.66)")
-- ---------------------------------------------------------------------------
do
  -- Switching backend in the CET window must take effect on the NEXT line, with no reload — the
  -- whole point of `config` being a closure. And the cached probes must be dropped, or "Audioware
  -- only" would still see a native path and "auto" would never re-log which backend it landed on.
  local cfg = { mode = "auto", gruntPool = { "ono_x" } }
  local VO = reset{ shim = true, bank = true, config = cfg }
  VO.play(SFX, spy.player)
  check("starts native", #spy.native == 1 and #spy.audioware == 0)

  cfg.mode = "audioware"; VO.forget()
  VO.play(SFX, spy.player)
  check("switch to audioware applies with NO reload", #spy.audioware == 1)
  check("...and reports the new backend", VO.backend(spy.player) == "audioware")

  cfg.mode = "native"; VO.forget()
  VO.play(SFX, spy.player)
  check("switch back to native applies immediately", #spy.native == 2)

  cfg.mode = "off"; VO.forget()
  check("switch to off applies immediately", VO.backend(spy.player) == "off")

  VO.forget()
  check("forget() clears the cached probes", VO.hasAudioware() ~= nil)

  local src = io.open("mod/JackieLives/init.lua", "r"):read("*a")
  check("the CET window has a Voice section", src:match('CollapsingHeader%("Voice') ~= nil)
  check("all four backends are offered", src:match('"auto"') and src:match('"native"')
        and src:match('"audioware"') and src:match('Config%.voice%.mode = "off"') ~= nil)
  check("switching calls VO.forget()", src:match("VO%.forget%(%)") ~= nil)
  -- The trap this guards: config.lua is re-required from disk on every reload, so a choice that
  -- lived only in Config would revert. Same failure the seat and walk tuners each shipped once.
  check("the choice is persisted", src:match('voiceMode=') ~= nil)
  check("...and re-applied at onInit", src:match("if JL%.voiceMode then Config%.voice%.mode = JL%.voiceMode end") ~= nil)
  check("only valid modes are accepted on load",
        src:match('v == "auto" or v == "native" or v == "audioware" or v == "off"') ~= nil)
end

print(("\n%d checks, %d failed"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
