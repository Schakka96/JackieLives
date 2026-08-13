--[[
  vo.lua — JACKIE'S REAL VOICE, WITHOUT SHIPPING A SINGLE AUDIO FILE  (v1.66)
  ============================================================================
  Global `VO`. Dependency-injected like familiarity.lua / retrieval.lua, so an
  unbound helper no-ops instead of erroring, and the whole file is testable on
  the Mac with no game running (tools/test_vo.lua).

  WHAT CHANGED, AND WHY IT MATTERS
  For a year this mod believed the game could not be told to play one CHOSEN
  voice line. That belief cost us Audioware, a 940 MB extraction every player
  had to perform by hand, a WolvenKit tutorial, and a failure mode where one
  missing .wav silenced Jackie completely. It was wrong. The game will play any
  line you name — you ask the DIALOGUE system, not the audio system:

      DialogLineEvent{ data = audioDialogLineEventData{ stringId = <CRUID> } }

  queued on the entity that should speak. The audio is already on the player's
  disk, because it is the game's own. See docs/research/native_vo_dialogline.md
  and reds/JackieLivesVO.reds.

  NO CONTENT CHANGES. Our voiced lines are already written as
      sfx = "jl_1660220866564214792"
  and those digits ARE the line's String ID (the trailing hex of its .wem stem,
  in decimal — verified against the game's own screenplay data, where
  screenplayStore.lines[].locstringId.ruid is exactly this number). So every
  line already in the trees routes to the native path with nothing rewritten.

  ⚠️ THE ONE THING THAT MUST NOT DRIFT: a String ID is ~2e18, and Lua numbers
  are doubles — they cannot hold it exactly above 2^53. Never `tonumber()` an
  id, never do arithmetic on one, never round-trip it through a number. It is a
  STRING here and a string all the way into redscript, which parses it with
  StringToUint64. test_vo.lua asserts this and will fail if anyone "tidies" it.

  BACKENDS, in the order VO.play tries them:
    1. native     — the shim above. Nothing to install, nothing to extract.
    2. audioware  — the old path, kept working for anyone who already built a
                    bank. Never required; if Audioware is absent it is skipped.
    3. ono grunt  — a real WWise vocal-effort event on Jackie's own body. Works
                    with NO dependency at all, which is why the "unvoiced line"
                    fallback is no longer silence-or-Audioware.
--]]

local M = {}

M.VERSION = "1.66"

-- Durations, in seconds, read out of the game's own .scene files by
-- tools/gen_vo_durations.py. Optional: a missing table or a missing entry just
-- means we pace by reading time instead.
local DUR = nil
pcall(function() DUR = require("vo_durations") end)

-- ---------------------------------------------------------------------------
-- Injected from init.lua (VO.bind{...}). All optional.
-- ---------------------------------------------------------------------------
--   log(msg)                    -> console + log file
--   config() -> table           -> the LIVE Config.voice (re-read every call, because
--                                  config.lua is re-required from disk on every reload)
--   readingSecs(text) -> number -> how long that text takes to read
--   playEvent(target, event)    -> fire a WWise event on an entity (the ono grunts)
local deps = {}

function M.bind(t)
  for _, k in ipairs({ "log", "config", "readingSecs", "playEvent" }) do
    if t and t[k] ~= nil then deps[k] = t[k] end
  end
  return M
end

local function log(msg)
  if deps.log then pcall(deps.log, "[VO] " .. tostring(msg)) end
end

local function cfg()
  local c
  if deps.config then pcall(function() c = deps.config() end) end
  return c or {}
end

-- ---------------------------------------------------------------------------
-- Backend detection. Probed lazily, then cached — but ONLY after a positive
-- result. A negative is never cached: the shim answers through an entity, and
-- at the moment the first line is spoken there may not be a usable one yet.
-- Caching "no" there would have permanently disabled voice on a slow load.
-- ---------------------------------------------------------------------------
local state = { native = nil, audioware = nil, logged = false }

-- Any GameObject will do — the shim is added to GameObject itself. Prefer the
-- player because it always exists.
local function probeTarget(target)
  if target then return target end
  local p
  pcall(function() p = Game.GetPlayer() end)
  return p
end

function M.hasNative(target)
  if state.native then return true end
  local t = probeTarget(target)
  if not t then return false end
  local ver
  pcall(function() ver = t:JLVO_Version() end)
  if type(ver) == "number" and ver >= 1 then
    state.native = true
    return true
  end
  return false
end

function M.hasAudioware()
  if state.audioware ~= nil then return state.audioware end
  local d
  pcall(function() d = Game.GetAudioSystemExt():Duration(CName.new("jl_fallback")) end)
  state.audioware = (type(d) == "number" and d > 0)
  return state.audioware
end

-- "native" | "audioware" | "grunt" — what a voiced line would actually use now.
function M.backend(target)
  local mode = cfg().mode or "auto"
  if mode == "off" then return "off" end
  if mode ~= "audioware" and M.hasNative(target) then return "native" end
  if mode ~= "native" and M.hasAudioware() then return "audioware" end
  return "grunt"
end

-- Said once, on the first line, so the log names the backend without spamming.
local function logBackendOnce(target)
  if state.logged then return end
  state.logged = true
  local b = M.backend(target)
  if b == "native" then
    log("using the game's OWN voice-over (JackieLivesVO.reds present) — no audio files needed.")
  elseif b == "audioware" then
    log("using the Audioware bank. The native path is unavailable: r6/scripts/JackieLives/"
        .. "JackieLivesVO.reds is missing or redscript isn't installed.")
  elseif b == "off" then
    log("voice disabled by Config.voice.mode.")
  else
    log("no voice backend — Jackie will use vocal efforts + subtitles. Install redscript and "
        .. "make sure r6/scripts/JackieLives/JackieLivesVO.reds shipped with the mod.")
  end
end

-- ---------------------------------------------------------------------------
-- The id in `sfx`. Our content writes "jl_<decimal string id>"; anything else
-- (jl_fallback, test_tone, a wem-stem alias) is not a line id and belongs to
-- the Audioware path. Returned as a STRING — see the warning in the header.
-- ---------------------------------------------------------------------------
function M.lineId(sfx)
  if type(sfx) ~= "string" then return nil end
  return sfx:match("^jl_(%d%d%d%d%d%d+)$")
end

-- ---------------------------------------------------------------------------
-- How long this line lasts, in seconds. Exact where the game told us, reading
-- time otherwise, nil if we have neither and the caller should use its own
-- default.
-- ---------------------------------------------------------------------------
function M.duration(sfx, text)
  local id = M.lineId(sfx)
  if id and DUR and DUR[id] then return DUR[id] end

  -- Audioware, when it's the backend, knows its own clip lengths.
  if sfx and sfx ~= "" and state.audioware then
    local d
    pcall(function() d = Game.GetAudioSystemExt():Duration(CName.new(sfx)) end)
    if type(d) == "number" and d > 0 then return d end
  end

  if text and text ~= "" and deps.readingSecs then
    local secs
    pcall(function() secs = deps.readingSecs(text) end)
    if type(secs) == "number" and secs > 0 then return secs end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Speak one line.
--   sfx    "jl_<id>" (native), or any Audioware event name
--   target the entity that should speak — Jackie. Falls back to the player,
--          which is what the phone-call beats need (he isn't in the world yet).
--   mute   caller says an unvoiced line should be GENUINELY silent (v1.56's
--          muteFallback): no grunt.
-- Returns true if something was actually heard.
-- ---------------------------------------------------------------------------
function M.play(sfx, target, mute)
  local c = cfg()
  if c.mode == "off" then return false end
  logBackendOnce(target)

  local id = M.lineId(sfx)
  if id and c.mode ~= "audioware" then
    local speaker = probeTarget(target)
    if speaker and M.hasNative(speaker) then
      local ok, played = pcall(function()
        local tag  = c.voiceTag or ""
        local rest = c.restoreVoiceTag or ""
        if tag ~= "" then
          return speaker:JLVO_PlayLineAs(id, c.context or -1, CName.new(tag),
                                         CName.new(rest), M.duration(sfx) or 3.0)
        end
        return speaker:JLVO_PlayLine(id, c.context or -1)
      end)
      if ok and played then return true end
      -- A well-formed id the game doesn't know is silent, not an error, so this
      -- only trips on a genuinely malformed id — worth saying out loud.
      log("native playback refused id " .. tostring(id) .. " (ok=" .. tostring(ok) .. ")")
    end
  end

  if sfx and sfx ~= "" and c.mode ~= "native" and M.hasAudioware() then
    local ok = pcall(function() Game.GetAudioSystemExt():Play(CName.new(sfx)) end)
    if ok then return true end
  end

  -- Nothing voiced. A vocal effort keeps him from reading as broken, and unlike
  -- everything above it needs no dependency whatsoever — these are WWise events
  -- that ship with the game and play on his own body.
  if mute then return false end
  local pool = c.gruntPool
  if pool and #pool > 0 and deps.playEvent and target then
    local ev = pool[math.random(1, #pool)]
    local ok = pcall(function() deps.playEvent(target, ev) end)
    if ok then return true end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Drop every cached probe and re-arm the "which backend am I on" log line.
--
-- Called when the player switches backend in the CET window. Without this, two
-- things would go stale in a way that reads as a bug: `logged` means the log
-- never names the NEW backend, and a cached positive `native` means "Audioware
-- only" would still look like it had a native path available. Cheap to call —
-- the probes are one method call each.
-- ---------------------------------------------------------------------------
function M.forget()
  state.native, state.audioware, state.logged = nil, nil, false
end

-- ---------------------------------------------------------------------------
-- One-line health report for the CET window / Diagnostics.
-- ---------------------------------------------------------------------------
function M.status(target)
  local b = M.backend(target)
  local n = 0
  if DUR then for _ in pairs(DUR) do n = n + 1 end end
  return "backend=" .. b
      .. " native=" .. tostring(M.hasNative(target))
      .. " audioware=" .. tostring(M.hasAudioware())
      .. " durations=" .. tostring(n)
end

return M
