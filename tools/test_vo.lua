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
    JLVO_Version = function() if not spy.shimPresent then error("no shim") end
      return opts.v2 and 2 or 1 end,
    JLVO_PlayLine = function(self, idDec, ctx)
      if not spy.shimPresent then error("no shim") end
      spy.native[#spy.native + 1] = { id = idDec, ctx = ctx, type = type(idDec), on = self }
      return true
    end,
    JLVO_PlayLineAs = function(self, idDec, ctx, tag, restore, dur)
      if not spy.shimPresent then error("no shim") end
      spy.native[#spy.native + 1] =
        { id = idDec, ctx = ctx, type = type(idDec), tag = tag.name, restore = restore.name,
          dur = dur, on = self }
      return true
    end,
    -- v2: one entry point, and it carries `expression` — the field v1 never set.
    JLVO_Speak = function(self, idDec, ctx, expr, tag, restore, dur)
      if not spy.shimPresent then error("no shim") end
      if not opts.v2 then error("no JLVO_Speak on a v1 shim") end
      spy.native[#spy.native + 1] =
        { id = idDec, ctx = ctx, expr = expr, type = type(idDec),
          tag = (tag.name ~= "" and tag.name or nil), restore = restore.name, dur = dur, on = self }
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

-- v1.69: the vocal-effort fallback is now a 15% roll (Config.voice.gruntChance), so any check
-- that asserts "a grunt happened" has to pin the roll or it is a coin flip in CI.
local ALWAYS_GRUNT = { mode = "auto", gruntChance = 1.0,
                       gruntPool = { "ono_jackie_greet", "ono_jackie_curious" } }

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

  -- gruntChance = 1 here on purpose: the SHIPPED value is 0.15 (v1.69), so without pinning it
  -- these two checks would fail 85% of runs. The chance gate itself is section 4b.
  VO = reset{ shim = false, bank = false, config = ALWAYS_GRUNT }
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
  local VO = reset{ shim = false, bank = false, config = ALWAYS_GRUNT }
  check("mute suppresses the vocal effort", VO.play(nil, spy.player, true) == false and #spy.grunts == 0)
  VO = reset{ shim = false, bank = false, config = ALWAYS_GRUNT }
  check("without mute, an unvoiced line grunts", VO.play(nil, spy.player, false) == true and #spy.grunts == 1)
  VO = reset{ shim = true, bank = false }
  check("mute never suppresses a REAL voiced line", VO.play(SFX, spy.player, true) == true and #spy.native == 1)
end

-- ---------------------------------------------------------------------------
print("\n4b. gruntChance — the vocal effort is RARE now (v1.69)")
-- ---------------------------------------------------------------------------
do
  -- Antonia: "he grunts EVERY time V hits a dialogue selection ... a small chance (15%) is ok."
  -- Most hub small talk is written text with no CDPR recording, so "unvoiced" is the COMMON
  -- case and an always-on fallback turned every menu pick into a grunt.
  local VO = reset{ shim = false, bank = false, config = { mode = "auto", gruntChance = 0,
                                                           gruntPool = { "ono_x" } } }
  check("chance 0 -> never grunts", VO.play(nil, spy.player) == false and #spy.grunts == 0)

  VO = reset{ shim = false, bank = false, config = ALWAYS_GRUNT }
  check("chance 1 -> always grunts", VO.play(nil, spy.player) == true and #spy.grunts == 1)

  -- Statistical, so make it wide enough never to flake: 2000 rolls at p=0.15 lands in
  -- [200, 400] with overwhelming probability (sd ~16, so these are ~+-6 sd).
  VO = reset{ shim = false, bank = false, config = { mode = "auto", gruntChance = 0.15,
                                                     gruntPool = { "ono_x" } } }
  for _ = 1, 2000 do VO.play(nil, spy.player) end
  check("chance 0.15 -> roughly one line in seven",
        #spy.grunts > 200 and #spy.grunts < 400, "got " .. #spy.grunts .. " grunts in 2000 lines")

  local _, Config = reset{ shim = false, bank = false }
  check("the shipped config actually carries the knob", Config.voice.gruntChance == 0.15,
        tostring(Config.voice.gruntChance))
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

-- ---------------------------------------------------------------------------
print("\n11. positional audio — the v2 shim and the Voice lab")
-- ---------------------------------------------------------------------------
do
  -- The event carries no position field, so the entity it is queued on is the ONLY thing that can
  -- place the voice in the world. Every path must therefore preserve the caller's target rather
  -- than quietly defaulting to the player — which is exactly how a line ends up coming out of V.
  -- ⚠️ `jackie` must be rebuilt after EVERY reset(): each reset installs a fresh stub whose
  -- closures capture that reset's `spy`, so a companion carried over from a previous scenario
  -- silently reports into the OLD spy and the current one looks empty.
  local function companion() return setmetatable({}, getmetatable(spy.player)) end

  local VO = reset{ shim = true, v2 = true }
  local jackie = companion()
  VO.play(SFX, jackie)
  check("v2 shim is used when present", #spy.native == 1 and spy.native[1].expr ~= nil)
  check("the line is queued on the TARGET, not the player", spy.native[1].on == jackie)

  VO = reset{ shim = true, v2 = true }
  VO.play(SFX, nil)
  check("no target -> falls back to the player (and only then)", spy.native[1].on == spy.player)

  VO = reset{ shim = true, v2 = true, config = { mode = "auto", context = 0, expression = 0 } }
  jackie = companion()
  VO.play(SFX, jackie)
  check("context and expression are passed through", spy.native[1].ctx == 0 and spy.native[1].expr == 0)

  VO = reset{ shim = true, v2 = false }
  jackie = companion()
  VO.play(SFX, jackie)
  check("a STALE v1 .reds still speaks (no expression)", #spy.native == 1 and spy.native[1].expr == nil)

  VO = reset{ shim = true, v2 = true }
  jackie = companion()
  local ok, who = VO.probe(ID, jackie, 0, 0, "")
  check("probe() plays on the entity it was given", ok == true and spy.native[1].on == jackie)
  check("probe() reports who received it", type(who) == "string")
  local _, who2 = VO.probe(ID, spy.player, 0, 0, "")
  check("probe() names the player as the player", who2:find("PLAYER") ~= nil, who2)

  local src = io.open("mod/JackieLives/init.lua", "r"):read("*a")
  check("the CET window has a Voice lab", src:match("Voice lab") ~= nil)
  check("the lab has a control that plays on V", src:match("On V %(the control%)") ~= nil)
  check("the lab uses a real, long test line",
        src:match('JL_VO_TESTLINE = "(%d+)"') ~= nil)
  do
    local id = src:match('JL_VO_TESTLINE = "(%d+)"')
    local D = require("vo_durations")
    check("...and that line has a duration long enough to locate by ear",
          D[id] and D[id] > 5, tostring(id) .. " = " .. tostring(D[id]))
  end
end

-- ---------------------------------------------------------------------------
print("\n12. gendered lines — the subtitle must match the take the game plays (v1.69)")
-- ---------------------------------------------------------------------------
do
  -- Antonia: "the subtitles now say chica (husbando mode) but his voice says mano often."
  -- CDPR recorded some Jackie lines twice under ONE String ID and the game picks the take from
  -- V's BODY GENDER. Our subtitle was hard-coded from the female take, so a male-bodied V read
  -- one word and heard another. Nothing to fix in the audio; everything to fix on screen.
  local VO, Config = reset{ shim = true }
  local G = Config.voGender
  check("vo_gender.lua is loaded by config.lua", type(G) == "table")

  local n = 0
  for id, e in pairs(G or {}) do
    n = n + 1
    check("id " .. id .. " is a STRING of digits (the precision rule)",
          type(id) == "string" and id:match("^%d%d%d%d%d%d+$") ~= nil)
    check("id " .. id .. " carries both takes",
          type(e.f) == "string" and type(e.m) == "string" and e.f ~= e.m)
  end
  check("the table is not empty", n > 0, tostring(n) .. " entries")

  -- The line she actually reported, end to end.
  local SIGNATURE = "1777946122915868672"
  check("the reported line is covered", G[SIGNATURE] ~= nil)
  if G[SIGNATURE] then
    check("...female V reads 'chica'", G[SIGNATURE].f:find("chica") ~= nil, G[SIGNATURE].f)
    check("...male V reads 'mano'",    G[SIGNATURE].m:find("mano")  ~= nil, G[SIGNATURE].m)
  end

  -- Every key must be reachable: an id that no `sfx` in config.lua names would never be looked up.
  local cfgsrc = io.open("mod/JackieLives/config.lua", "r"):read("*a")
  local orphan = nil
  for id in pairs(G or {}) do
    if not cfgsrc:find("jl_" .. id, 1, true) then orphan = id end
  end
  check("every entry is a line config.lua actually speaks", orphan == nil, tostring(orphan))

  local src = io.open("mod/JackieLives/init.lua", "r"):read("*a")
  check("speakJackieLine resolves the subtitle through jlLineText",
        src:match("local function speakJackieLine.-jlLineText%(text, sfx%)") ~= nil)
  check("the swap keys off V's BODY, not the Husbando switch",
        src:match("function jlLineText.-jlVBodyMale%(%)") ~= nil)
  check("a failed gender read is never cached",
        src:match("function jlVBodyMale.-if g == nil then return false end") ~= nil)

  -- The regression that started it: an sfx-keyed override table rewrote voiced lines by the
  -- relationship switch, and pointed them at wem stems the native path can't even speak.
  check("Config.hermanoLines is gone", Config.hermanoLines == nil)
  check("...and jlVar no longer consults it", src:match("Config%.hermanoLines\n") == nil)
  local badstem = nil
  for stem in cfgsrc:gmatch('sfx%s*=%s*"(jl_jackie[%w_]+)"') do
    if VO.lineId(stem) == nil then badstem = stem end
  end
  check("no config sfx is a wem stem the native path would refuse", badstem == nil,
        tostring(badstem) .. " is not a jl_<digits> String ID — it can never play natively")
end

-- ---------------------------------------------------------------------------
print("\n13. the hub greets once per conversation (v1.69)")
-- ---------------------------------------------------------------------------
do
  -- Antonia: "He throws an arrival line (time we were on our way for example) EVERY time V
  -- returns to the main dialogue picker hub, not good." Every topic ends `to = "open"`, and
  -- "open" opens with his ARRIVAL greeting pool — so one conversation played as six hellos.
  local _, Config = reset{ shim = true }
  local src = io.open("mod/JackieLives/init.lua", "r"):read("*a")

  check("Branch.start honours greetOnce", src:match("node%.greetOnce") ~= nil)
  check("a revisit skips the line entirely (no speak, no grunt roll)",
        src:match("if revisit then.-bstate%.openAt.-return") ~= nil)
  check("the ledger is dropped when the conversation ends",
        src:match("bstate%.seen%s+= nil") ~= nil)
  check("...and when the tree changes",
        src:match("bstate%.taken, bstate%.seen = nil, nil") ~= nil)

  -- The hubs themselves: a node is a hub if anything routes back INTO it.
  local hub = Config.locationDialogue and Config.locationDialogue.everywhere
  check("the main hub exists", hub ~= nil and hub.nodes ~= nil)
  check("the main hub greets once", hub and hub.nodes.open.greetOnce == true)
  check("the seated-dinner hub greets once",
        Config.date and Config.date.seatedTree.nodes.open.greetOnce == true)

  -- The flag belongs on the node a conversation keeps COMING BACK TO, and in a tree shaped like
  -- these that is the START node — it is the one whose line is a greeting, and it is on a cycle
  -- precisely because every topic routes home to it. (Topic nodes can technically be revisited too,
  -- but replaying a topic's ANSWER when you ask again is correct; replaying hello is not.) So the
  -- rule is narrow on purpose: a cyclic start node must greet once. Add a new looping tree and
  -- forget the flag, and this fails instead of shipping the bug again.
  local function onCycle(tree, start)
    local seen, stack = {}, { start }
    while #stack > 0 do
      local key = table.remove(stack)
      for _, c in ipairs((tree.nodes[key] or {}).choices or {}) do
        if c.to and tree.nodes[c.to] then
          if c.to == start then return true end
          if not seen[c.to] then seen[c.to] = true; stack[#stack + 1] = c.to end
        end
      end
    end
    return false
  end

  -- Every talk tree in the mod, so a NEW one can't quietly reintroduce the bug.
  local trees = { hub, Config.date and Config.date.seatedTree, Config.dialogueTree,
                  Config.reunionCallTree, Config.reunionMeetTree, Config.blazeFinaleTree,
                  Config.callTree, Config.date and Config.date.tree }
  for key, t in pairs(Config.locationDialogue or {}) do trees[#trees + 1] = t end

  local unflagged, loops = nil, 0
  for _, tree in pairs(trees) do
    local root = tree.nodes and tree.start
    if root and tree.nodes[root] and onCycle(tree, root) then
      loops = loops + 1
      if not tree.nodes[root].greetOnce then unflagged = root end
    end
  end
  check("the detector found the looping hubs", loops >= 2, tostring(loops) .. " found")
  check("every hub a conversation returns to greets once", unflagged == nil,
        tostring(unflagged) .. " is returned to mid-conversation but still replays its greeting")
end

-- ---------------------------------------------------------------------------
print("\n14. the talk trees hold together (v1.69 small talk)")
-- ---------------------------------------------------------------------------
do
  -- The hub roughly doubled in size, and the two ways a hand-written tree breaks are boring and
  -- silent: a choice pointing at a node that isn't there (Branch.start logs "node missing" and the
  -- conversation dead-ends), and a node nothing can reach (content that never ships). Neither shows
  -- up until someone picks that exact row in game, so check it here instead.
  local VO, Config = reset{ shim = true }
  local D = require("vo_durations")

  local trees = { { "everywhere", Config.locationDialogue.everywhere },
                  { "seated", Config.date.seatedTree } }
  for key, t in pairs(Config.locationDialogue or {}) do
    if key ~= "everywhere" then trees[#trees + 1] = { key, t } end
  end

  local dangling, orphan, unvoiced = nil, nil, nil
  for _, pair in ipairs(trees) do
    local name, tree = pair[1], pair[2]
    local reached = { [tree.start] = true }
    local stack = { tree.start }
    while #stack > 0 do
      local k = table.remove(stack)
      for _, c in ipairs((tree.nodes[k] or {}).choices or {}) do
        if c.to then
          if not tree.nodes[c.to] then dangling = name .. "." .. k .. " -> " .. c.to
          elseif not reached[c.to] then reached[c.to] = true; stack[#stack + 1] = c.to end
        end
      end
    end
    for k in pairs(tree.nodes) do
      if not reached[k] then orphan = name .. "." .. k end
    end
    -- Every voiced line must be a line the game actually knows, or he opens his mouth and nothing
    -- comes out. vo_durations.lua is generated from the install, so "has a duration" == "is real".
    for k, node in pairs(tree.nodes) do
      for _, e in ipairs(node.jackiePool or { node.jackie }) do
        local id = e and e.sfx and VO.lineId(e.sfx)
        if e and e.sfx and (not id or not D[id]) then unvoiced = name .. "." .. k .. " " .. e.sfx end
      end
    end
  end

  check("no choice points at a node that doesn't exist", dangling == nil, tostring(dangling))
  check("every node is reachable from the tree's start", orphan == nil, tostring(orphan))
  check("every voiced line is a real line of the game's", unvoiced == nil,
        tostring(unvoiced) .. " has no duration — the id isn't in the install")

  -- The small talk itself: it only counts as small talk if he SAYS it.
  local hub, voiced, topics = Config.locationDialogue.everywhere, 0, 0
  for _, node in pairs(hub.nodes) do
    topics = topics + 1
    for _, e in ipairs(node.jackiePool or {}) do
      if e.sfx then voiced = voiced + 1 end
    end
  end
  check("the hub has real breadth", topics >= 20, tostring(topics) .. " nodes")
  check("...and a lot of it is his actual voice, not subtitles",
        voiced >= 25, tostring(voiced) .. " voiced lines in the hub")
end

-- ---------------------------------------------------------------------------
print("\n15. the way OUT of the hub can never be sampled away (v1.69.1)")
-- ---------------------------------------------------------------------------
do
  -- Antonia: "there's now sometimes no dismiss option in the dialogue hub? it must always be the
  -- bottom option of the hub pls." The hub offers 4–5 of ~20 rows, and the engine-injected
  -- "Head home, Jackie" / dinner-invite rows were samplable like any topic — so they lost their
  -- slot most draws. Worse, the CACHED draw dropped them EVERY time: the cache is keyed by table
  -- identity and these rows are rebuilt on every open, so they could never match. `pin` fixes both.
  local src = io.open("mod/JackieLives/init.lua", "r"):read("*a")
  local extras = src:match("local function withCompanionExtras.-\nend")
  check("withCompanionExtras was found", extras ~= nil)

  -- anchored to the start of a line, so the `pin = true` inside the explanatory comment above the
  -- function doesn't get counted as a third row
  local pins = 0
  for _ in (extras or ""):gmatch("\n%s*pin%s*=%s*true,") do pins = pins + 1 end
  check("both injected rows are pinned", pins == 2, tostring(pins) .. " pins")
  check("the dismiss row is pinned",
        (extras or ""):match('action%s*=%s*"dismiss_walkaway",%s*\n%s*pin%s*=%s*true') ~= nil)
  check("the dinner-invite row is pinned",
        (extras or ""):match('action%s*=%s*"start_date",%s*\n%s*pin%s*=%s*true') ~= nil)

  -- Bottom of the hub: the sampler only ever DROPS rows, so authored order decides. Dismiss is
  -- appended after everything, including the invite, so it is the last row on screen.
  local iInvite = (extras or ""):find('"start_date"', 1, true)
  local iBye    = (extras or ""):find("dismiss_walkaway", 1, true)
  check("dismiss is appended last, so it renders at the bottom",
        iBye ~= nil and (iInvite == nil or iBye > iInvite))
  check("the sampler drops rows but never reorders them",
        src:match("for i, c in ipairs%(shown%) do\n%s*if c%.pin or keep%[i%] then") ~= nil)

  -- And the sampler must genuinely exempt pinned rows from the count, or pinning them would just
  -- steal slots from the small talk instead.
  check("pinned rows are excluded from the sample pool",
        src:match("for i, c in ipairs%(shown%) do if not c%.pin then free%[#free %+ 1%] = i end end") ~= nil)
  check("...and are re-added on a cached draw",
        src:match("if c%.pin or hd%.set%[srcOf%[i%]%] then") ~= nil)
end

print(("\n%d checks, %d failed"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
