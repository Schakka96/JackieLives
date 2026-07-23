-- ===========================================================================
-- Jackie Lives — LOCALIZATION (v1.60)
-- ===========================================================================
-- Translates every player-facing string the mod writes to the screen.
--
-- HOW IT WORKS — the English string IS the key.
-- There is no key table to maintain and config.lua was NOT restructured. A
-- translation file is just a flat map of the English line to its translation:
--
--     -- lang_ja.lua
--     return { ["Talk to me, choomba."] = "話してよ、チョンバ。" }
--
-- A string with no entry falls straight back to English, so a half-finished
-- translation can never break the mod or blank a subtitle. That also means
-- EDITING an English line in config.lua silently un-translates that one line
-- (the key no longer matches) — run tools/lang_extract.py after text edits and
-- it reports every key that drifted.
--
-- WHERE IT IS APPLIED — four chokepoints in init.lua, nothing else:
--   showSubtitle()        the native bottom subtitle band  (all spoken lines)
--   showOnscreenMsg()     the native blue banner           (all notices)
--   drawChoiceRows()      V's dialogue choices             (ImGui picker)
--   buildJackieHub() / Blaze.showPrompt()   the native [F] prompt label
-- Because every line in config.lua / blaze.lua / retrieval.lua reaches the
-- screen through one of those, none of those files needed touching.
--
-- 200-LOCAL CAP: init.lua holds this as the GLOBAL `Lang` (like Retrieval /
-- Blaze / Session). Nothing here adds a top-level local to init.lua's chunk.
--
-- ⚠️ FONTS: the native subtitle band, the native banner and the shards all use
-- the GAME's fonts, which ship full glyph coverage for every language below.
-- The dialogue-choice picker is drawn in ImGui with CET's own font, which is
-- Latin-only by default — see docs/localization.md for the one-line CET config
-- players need for Japanese / Russian / Chinese.
-- ===========================================================================

local Lang = {}

-- The shipping set. `code` is our file suffix (lang_<code>.lua) AND the value
-- persisted to jl_settings.txt. `game` is the code the game's own language
-- setting reports, used by autodetect.
Lang.LANGUAGES = {
  { code = "en",    label = "English",              game = { "en-us" } },
  { code = "ja",    label = "Japanese / 日本語",     game = { "ja-jp" } },
  { code = "es",    label = "Spanish / Espanol",    game = { "es-mx", "es-es" } },
  { code = "de",    label = "German / Deutsch",     game = { "de-de" } },
  { code = "fr",    label = "French / Francais",    game = { "fr-fr" } },
  { code = "it",    label = "Italian / Italiano",   game = { "it-it" } },
  { code = "pl",    label = "Polish / Polski",      game = { "pl-pl" } },
  { code = "ptbr",  label = "Portuguese (BR)",      game = { "pt-br" } },
  { code = "ru",    label = "Russian / Русский",    game = { "ru-ru" } },
  { code = "zhcn",  label = "Chinese (Simplified)", game = { "zh-cn" } },
}

Lang.code = "en"     -- active language code
Lang.map  = nil      -- active translation table; nil == English (no lookup)
Lang.auto = true     -- follow the game's language, vs. an explicit player pick
Lang.hits, Lang.miss = 0, 0   -- diagnostics for the CET window

local function say(msg)
  if _G.log then _G.log("[lang] " .. tostring(msg)) end
end

-- ---------------------------------------------------------------------------
-- t(s) — the whole public surface. Returns the translation, or `s` unchanged.
-- Non-strings (nil, numbers) pass through untouched so call sites stay dumb.
-- ---------------------------------------------------------------------------
function Lang.t(s)
  if type(s) ~= "string" or s == "" then return s end
  local m = Lang.map
  if not m then return s end
  local hit = m[s]
  if hit ~= nil and hit ~= "" then
    Lang.hits = Lang.hits + 1
    return hit
  end
  Lang.miss = Lang.miss + 1
  return s
end

function Lang.labelFor(code)
  for _, L in ipairs(Lang.LANGUAGES) do
    if L.code == code then return L.label end
  end
  return code
end

-- ---------------------------------------------------------------------------
-- AUTODETECT — read the game's own language setting.
--
-- VERIFIED: '/language' + 'VoiceOver' is the exact pair the base game reads in
--   singleplayerMenu.script:1040
--     GetSystemRequestsHandler().GetUserSettings().GetVar('/language','VoiceOver')
--   ...which returns a ConfigVarListName whose GetValue() is a CName like 'ru-ru'.
--
-- 'OnScreen' is the TEXT (subtitle/UI) language and is what we actually want —
-- a player can run Japanese text over English voice. It is NOT referenced
-- anywhere in the decompiled scripts, so treat it as UNVERIFIED: we try it
-- first, fall back to the verified VoiceOver var, and fall back again to
-- English. Any failure here is silent and harmless — the player can always
-- override in the CET window.
-- ---------------------------------------------------------------------------
local function readGameLangVar(group)
  local out
  pcall(function()
    local us = GetSystemRequestsHandler():GetUserSettings()
    if not us then return end
    local var = us:GetVar("/language", group)
    if not var then return end
    local v = var:GetValue()
    if v then out = tostring(v):lower() end
  end)
  return out
end

function Lang.detect()
  local raw = readGameLangVar("OnScreen") or readGameLangVar("VoiceOver")
  if not raw then say("autodetect: game language unreadable -> English"); return "en" end
  for _, L in ipairs(Lang.LANGUAGES) do
    for _, g in ipairs(L.game) do
      if raw == g then say("autodetect: game reports '" .. raw .. "' -> " .. L.code); return L.code end
    end
  end
  -- Unshipped language (Korean, Czech, Turkish...): stay English rather than
  -- half-matching on the leading two letters and picking the wrong dialect.
  say("autodetect: game reports '" .. raw .. "', no JackieLives translation -> English")
  return "en"
end

-- ---------------------------------------------------------------------------
-- LOAD — pull in lang_<code>.lua. A missing or broken file degrades to English
-- with a log line; it must never stop the mod loading.
-- ---------------------------------------------------------------------------
function Lang.load(code)
  code = tostring(code or "en")
  if code == "en" then
    Lang.code, Lang.map = "en", nil
    Lang.hits, Lang.miss = 0, 0
    say("active language: English (source strings)")
    return true
  end
  local ok, tbl = pcall(require, "lang_" .. code)
  if not ok or type(tbl) ~= "table" then
    say("could not load lang_" .. code .. ".lua (" .. tostring(tbl) .. ") -> falling back to English")
    Lang.code, Lang.map = "en", nil
    return false
  end
  local n = 0
  for _ in pairs(tbl) do n = n + 1 end
  Lang.code, Lang.map = code, tbl
  Lang.hits, Lang.miss = 0, 0
  say("active language: " .. Lang.labelFor(code) .. " (" .. n .. " strings)")
  return true
end

-- Called from onInit AFTER jlLoadSettings, so an explicit player pick wins over
-- autodetect. `saved` is the persisted code, or nil when the player never chose.
function Lang.init(saved)
  if saved and saved ~= "" and saved ~= "auto" then
    Lang.auto = false
    Lang.load(saved)
  else
    Lang.auto = true
    Lang.load(Lang.detect())
  end
end

return Lang
