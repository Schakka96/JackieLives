-- =============================================================================
-- messages.lua — Jackie TEXTS you (global `Msg`, v1.92 — ported from NCLives v1.91)
--
-- The message TEXT lives in the mod's .archive as a cooked .journal; this file decides only WHEN each
-- authored message fires, and what a reply does. Read ../NCLives/docs/MESSAGES.md first (there is ONE
-- copy of that schema doc, in NCLives, on purpose — two copies drift), then
-- docs/research/messages_port_spec.md for what this port changed — in particular §1, which
-- explains why the text has to be baked into an archive at all (there is no runtime "create a phone
-- message" API; JournalManager only has ChangeEntryState).
--
-- Delivery idiom, from a shipped mod that is known to work (BowieKnife99 bowieknife99.reds:456):
--     ChangeEntryState(path, class, "Inactive", "DoNotNotify")   -- recycle, silently
--     ChangeEntryState(path, class, "Active",   "Notify")        -- deliver, with the phone popup
-- The silent Inactive first is what lets the same line fire again later, so a small pool of check-ins
-- can carry a long playthrough.
--
-- ⚠️ Enum arguments are passed as PLAIN STRINGS ("Active" / "Notify"), not as
-- `gameJournalEntryState.Active`. Both work from CET, but strings sidestep the RTTI-global trap
-- documented in CLAUDE.md (see dialogui.lua) entirely, and that is how Simple Menu and CyberScript
-- have called this for years.
--
-- ⚠️ This module is a GLOBAL, loaded as `Msg = require("messages")` — init.lua is at Lua's 200-local
-- cap and cannot take another top-level `local`. Same reason as Session / Lang / DialogUI / Fam / VO.
--
-- WHAT THIS PORT CHANGED vs NCLives (docs/research/messages_port_spec.md §1d):
--   * ONE persona. NCLives runs a roster (Lucy, Valerie, ...); JackieLives has one character, so the
--     seven roster bindings are gone and `CUR` is a constant. The MECHANISM is kept rather than
--     deleted, because ~40 call sites read `CUR` and `withPersona`.
--   * The unlock gate is INJECTED (`Msg.env.gate`) instead of hard-coded. NCLives keys off Lucy's
--     jacket quest; ours is `Retrieval.isUnlocked()` — Jackie texts once he is actually back.
--   * `Msg.sendStory(id)` is new: the questline (storyboard.lua / arc.lua) fires a `kind: "story"`
--     beat BY NAME. The scheduler never draws one — its words are a plot point, not chit-chat.
-- =============================================================================

local Msg = {}

Msg.version = "1.0"   -- of the SMS system; JackieLives mod version is separate

-- Paths + tiers, GENERATED from content/*_messages.json. Never hand-edit; see docs/MESSAGES.md §3.
local Index = require("messages_index")

-- Engine handles, filled by Msg.bind() from init.lua. Every one is optional: a missing binding
-- degrades this module to a no-op rather than erroring, exactly like NCL.bind.
Msg.env = {}

function Msg.bind(t)
  t = t or {}
  -- ⚠️ BEING ON THIS LIST IS NOT BEING BOUND. bind() copies only the keys it names, so a binding
  -- passed but unlisted is silently dropped — AND a binding listed but never PASSED at the call site
  -- is just as dead. NCLives shipped v1.72 with this whole feature inert because two keys were listed
  -- here and never passed from init.lua, and 83 offline checks went green over it because the test
  -- harness stubs them itself. When you add one, add it in BOTH places, and name it in Msg.diagnose().
  for _, k in ipairs({
    "log",          -- function(msg)
    "Config",       -- the tuning table (Config.messages)
    "gameSeconds",  -- function() -> in-game seconds, or nil
    "clock",        -- function() -> real seconds since mod start (NCS.clock)
    "factGet",      -- function(name) -> number|nil
    "factSet",      -- function(name, value)
    -- ⚠️ NEW IN THIS PORT, AND THE ONE BINDING THAT CAN KILL THE WHOLE FEATURE SILENTLY.
    -- NCLives hard-codes its unlock (Lucy's jacket quest). Ours is a question only init.lua can
    -- answer — `Retrieval.isUnlocked()` — so it is injected, which also lets test_messages.lua drive
    -- it. Unbound it FAILS CLOSED (he never texts), which is the safe direction for a story gate.
    "gate",         -- function() -> bool, or (bool, reasonString): may the chain start yet?
    "famTier",      -- function() -> 0..3          (keyless: Fam.tier())
    "famAdd",       -- function(_key, why, n)      (keyless: Fam.add(why, n))
    "busy",         -- function() -> bool: a conversation / choice box is open
    "inCombat",     -- function() -> bool
    "spawned",      -- function() -> bool: the companion is currently in the world
    "venueKnown",   -- function(venueKey) -> bool: this persona actually uses that venue
  }) do
    if t[k] ~= nil then Msg.env[k] = t[k] end
  end
  return Msg
end

local function log(m)
  if Msg.env.log then pcall(Msg.env.log, "[Msg] " .. tostring(m)) end
end

-- ---------------------------------------------------------------------------
-- Tuning defaults
--
-- ⚠️ THESE LIVE HERE, NOT IN config.lua, and that is deliberate for this port. Every number below is
-- read through `or` fallbacks in NCLives too — but `enabled` is not: it gates Msg.tick outright, so
-- a missing `Config.messages` table would leave the whole feature silently off. Rather than add a
-- block to config.lua (which other work is editing, and which is re-required from disk on every
-- reload), the defaults sit beside the code that uses them and `Config.messages` OVERRIDES them
-- key-by-key. Adding `Config.messages = { ... }` to config.lua later needs no change here.
--
-- The bands come straight from NCLives v1.91 and are the one piece of tuning that was arrived at
-- from a player report, not from taste (see the cadence-ramp comment in `gapHours`): the first few
-- texts land 10-22 in-game hours apart so the chain reads as a conversation starting, everything
-- after at 24-40 so he settles into an unhurried cadence.
Msg.DEFAULTS = {
  enabled                  = true,
  firstMessageHours        = 2.0,    -- after the gate passes, before the very first text
  earlyCount               = 5,      -- how many texts count as "the opening run"
  earlyGapHours            = { 10.0, 22.0 },
  lateGapHours             = { 24.0, 40.0 },
  bubbleSeconds            = 2.5,    -- REAL seconds between the blobs of one text
  replyWindowSeconds       = 1800,   -- real-time half of the reply window
  replyWindowGameHours     = 6.0,    -- ...and the in-game half. Whichever expires first. (§8 trap 2)
  replyPollSeconds         = 2.0,
  gatePollSeconds          = 5.0,
  rendezvousHours          = 6.0,    -- how long he waits at a venue V agreed to
  rendezvousSpawnRadius    = 60.0,   -- metres: how close V must get before he is placed there
  sulkHours                = 24.0,   -- ...and how long he goes quiet after being stood up
  outgoingChainTurns       = 3,      -- turns V's side stays open once V starts a conversation
  outgoingCooldownMinHours = 0.5,
  outgoingCooldownMaxHours = 3.0,
}

-- Config.messages wins key-by-key; anything it does not name falls through to DEFAULTS. Rebuilt on
-- each call rather than cached, because config.lua is re-required from disk on every CET reload and
-- a cached table would pin the player's tuning to whatever was loaded first (the
-- config-reload-wipes-tuning trap the seat and walk tuners both hit).
local function cfg()
  local C = Msg.env.Config
  local t = C and C.messages
  if not t then return Msg.DEFAULTS end
  return setmetatable({}, { __index = function(_, k)
    local v = t[k]
    if v == nil then v = Msg.DEFAULTS[k] end
    return v
  end })
end

-- ---------------------------------------------------------------------------
-- Per-save state
--
-- Everything that must survive a reload is a game FACT, keyed by the companion's roster id — the same
-- discipline NCL.fam uses, and the same reason roster ids may never be renumbered. Facts are Int32,
-- so game-second timestamps fit comfortably.
--
-- Deliberately NOT persisted: the shuffle bag of which check-ins have been used. It resets per
-- session, which at worst repeats one line across a reload. Persisting it would mean a fact per beat.
-- ---------------------------------------------------------------------------
-- ⚠️ THE PREFIX IS NOT COSMETIC. Game facts are SHARED state across every installed mod — they live
-- in the save, not in our Lua state — so `jackielives_msg_` is the only thing keeping this mod's SMS
-- bookkeeping from colliding with NCLives' and NCLucy's, which a player may well have installed
-- alongside it. Never shorten it to `jl_msg_`.
local function factName(prefix, id)
  return "jackielives_msg_" .. prefix .. "_" .. tostring(id or 0)
end

-- WHOSE state machine is running right now.
--
-- NCLives runs a roster and sets this per persona each tick. JackieLives has exactly one character,
-- so this is a CONSTANT — but the mechanism is kept rather than deleted, because roughly forty call
-- sites below read `CUR` (and `withPersona`), and unpicking all of them would be forty chances to
-- introduce a bug in code that is known to work. `id = 1` is Jackie's fact suffix and MAY NEVER
-- CHANGE: every `jackielives_msg_*_1` fact in every existing save is keyed by it.
--
-- Messages are deliberately NOT gated on Jackie being summoned or "active" — he texts because he is
-- back, not because the player has him out. The one thing that DOES silence him is standing in front
-- of V (see `suppressed`).
local CUR = nil

-- ⚠️ EVERY PERSONA'S `id` IS A FACT SUFFIX AND MAY NEVER CHANGE OR BE REUSED. All SMS bookkeeping for
-- a contact lives in `jackielives_msg_<what>_<id>`, so renumbering one silently hands an existing
-- save somebody else's state. Append new rows; never reorder, never reuse a retired number.
--
-- `ticks` is the split that makes the arc's other voices possible without giving them a personality:
--   * TICKING (Jackie). Runs the whole state machine every frame — unlock gate, cadence, shuffle
--     bag, invites, V's outgoing side. He is the only one with a relationship to schedule.
--   * STORY-ONLY (the unknown number, Nix). Never ticked at all. They own a contact and a thread in
--     the phone, and they speak exactly when arc.lua says so, via Msg.sendStory(). Ticking them
--     would be wrong twice over: they have no ambient beats for the scheduler to draw, so it would
--     spin on an empty pool forever — and the whole effect of the unknown number is that two lines
--     land and then NOTHING happens for days. A schedule would destroy the beat it belongs to.
local PERSONAS = {
  { key = "jackie",  cid = "jackie",              id = 1, ticks = true  },
  { key = "unknown", cid = "jackielives_unknown", id = 2, ticks = false },
  { key = "nix",     cid = "jackielives_nix",     id = 3, ticks = false },
}
local JACKIE = PERSONAS[1]

local function fget(prefix)
  if not (CUR and Msg.env.factGet) then return 0 end
  -- ⚠️ COERCE. Every caller compares this with a number (`fget("on") >= 1`), and a non-number here
  -- throws "attempt to compare number with table" once per tick, which floods the log and buries
  -- whatever you were actually reading. The quest-fact system returns an Int32 in game, but a stub
  -- returns a table — which is why NCL.fam has coerced with tonumber since it was written and this
  -- did not. Same defence, same reason: a fact we cannot read is 0, not a crash.
  return tonumber(Msg.env.factGet(factName(prefix, CUR.id))) or 0
end

local function fset(prefix, v)
  if not (CUR and Msg.env.factSet) then return end
  Msg.env.factSet(factName(prefix, CUR.id), math.floor(v or 0))
end

-- Live, per-session scratch, per persona. Rebuilt on load; never persisted.
Msg.rt = { p = {} }

--- The current persona's scratch, created on first touch.
---   bag          [beatId] = true once used this session (the shuffle bag's "already drawn" set)
---   queue        bubbles still to drop into the thread: { paths = {...}, i = 1, nextAt = <clock> }
---   await        { beat = <beat>, until_ = <clock> } — waiting for V to tap a reply
local function rt()
  local key = CUR and CUR.key or "?"
  local t = Msg.rt.p[key]
  if not t then
    t = { bag = {}, queue = nil, await = nil, pollAt = 0, gateAt = 0, contactShown = false }
    Msg.rt.p[key] = t
  end
  return t
end

-- ---------------------------------------------------------------------------
-- Journal plumbing
-- ---------------------------------------------------------------------------
local function jm()
  local m; pcall(function() m = Game.GetJournalManager() end)
  return m
end

-- true only if the entry really exists — i.e. the .archive is installed and merged. Every failure
-- path in this module funnels through here, so a missing archive degrades to "he never texts"
-- instead of a spray of errors.
local function entry(path, class)
  local m = jm(); if not m then return nil end
  local e; pcall(function() e = m:GetEntryByString(path, class) end)
  return e
end

local function setState(path, class, state, notify)
  local m = jm(); if not m then return false end
  local ok, res = pcall(function()
    return m:ChangeEntryState(path, class, state, notify or "Notify")
  end)
  return (ok and res ~= false) or false
end

local function stateOf(path, class)
  local m, e = jm(), entry(path, class)
  if not (m and e) then return nil end
  local s; pcall(function() s = m:GetEntryState(e) end)
  return s
end

-- GetEntryState comes back as either the enum name or its ordinal depending on the CET build.
local function isSucceeded(s)
  return s == "Succeeded" or s == 3
end

-- Make sure the contact and the thread exist in the phone before the first message lands, or the
-- notification has nowhere to open. Immersive NCPD Hotline does the same for its dispatcher.
local function ensureContact(persona)
  if rt().contactShown then return end
  setState(persona.contactPath, "gameJournalContact", "Active", "DoNotNotify")
  setState(persona.convoPath, "gameJournalPhoneConversation", "Active", "DoNotNotify")
  rt().contactShown = true
end

--- Every persona the generator actually produced a pack for, in PERSONAS order (deterministic across
--- sessions, which matters because these drive fact writes). `wantTicks` filters to the ones with a
--- schedule. A contact declared in PERSONAS but absent from the index is skipped rather than
--- erroring — that is what a half-generated content folder looks like, and it must degrade quietly.
local function personas(wantTicks)
  local out = {}
  for _, P in ipairs(PERSONAS) do
    if (wantTicks == nil or P.ticks == wantTicks) then
      local idx = Index.personas and Index.personas[P.cid]
      if idx then
        out[#out + 1] = { idx = idx, cid = P.cid, key = P.key, id = P.id, ticks = P.ticks }
      end
    end
  end
  return out
end

--- The personas that run a schedule. Returns a LIST, unchanged in shape from NCLives, so
--- `tickPersona` / `withPersona` / `Msg.tick` are untouched. Story-only contacts are NOT in here —
--- see the PERSONAS comment for why ticking them would break the beat they exist for.
local function personaList()
  return personas(true)
end

--- Run `fn(p)` with `p` as the current persona, then restore. Used by the public entry points, which
--- are called from buttons rather than from the tick loop.
local function withPersona(p, fn)
  local prev = CUR
  CUR = p
  local ok, res = pcall(fn, p)
  CUR = prev
  if not ok then log("error: " .. tostring(res)); return nil end
  return res
end

--- The persona a menu button should act on. With one character this is simply "him, if he has a
--- pack" — but it is still a function, because every call site treats "no pack installed" as a real
--- and reportable state rather than as a crash.
local function defaultPersona()
  return personaList()[1]
end

--- The persona that owns `beatId`, searched across EVERY contact including the story-only ones.
--- This is the only place the arc's other voices are reachable from, and it is why a beat id must be
--- unique across the whole content folder, not just within one file.
local function personaForBeat(beatId)
  for _, p in ipairs(personas()) do
    for _, b in ipairs(p.idx.beats) do
      if b.id == beatId then return p, b end
    end
  end
end

-- ---------------------------------------------------------------------------
-- The unlock — Jackie is actually back
--
-- NCLives hard-codes Lucy's fiction here (the mq049 jacket, read straight out of the vanilla
-- journal). JackieLives' equivalent is the shipped questline's own gate: `Retrieval.isUnlocked()`,
-- i.e. stage >= REUNITED. He texts once he is a person in V's life again, which is the only point at
-- which a text from him is not a spoiler.
--
-- Three reasons it is INJECTED (`Msg.env.gate`) instead of written in here:
--   1. retrieval.lua owns that state; duplicating the stage check would give us two sources of truth.
--   2. test_messages.lua can drive it, so the gate is actually covered offline.
--   3. It reads no journal entries, so it works with no archive installed — and it is
--      retro-compatible for free: a save that reunited months ago passes on the next load.
--
-- ⚠️ FAILS CLOSED. An unbound `gate` means "not yet", not "sure, go ahead". For a story gate that is
-- the safe direction: the failure mode is "he never texts" (visible, diagnosable via Msg.diagnose),
-- not "he texts a player who has not met him yet" (a spoiler we can never take back).
local function gatePassed()
  if not Msg.env.gate then return false end
  local ok, why
  local called = pcall(function() ok, why = Msg.env.gate() end)
  if not called or not ok then return false end
  return true, why or "reunited with Jackie"
end

--- Called both from inside the tick loop (CUR set) and from menu buttons / tests (CUR nil), so it
--- falls back to the default persona rather than silently reporting "locked" for everyone.
function Msg.unlocked()
  if CUR then return fget("on") >= 1 end
  local t = defaultPersona()
  if not t then return false end
  return withPersona(t, function() return fget("on") >= 1 end) or false
end

-- Native Settings "Start texting now" for anyone who never did the jacket quest.
function Msg.forceStart()
  local target = defaultPersona()
  if not target then return false end
  return withPersona(target, function()
    if Msg.unlocked() then log("force start ignored — already unlocked"); return false end
    Msg.unlock("manual")
    return true
  end) or false
end

function Msg.unlock(why)
  if Msg.unlocked() then return end
  fset("on", 1)
  -- First text lands after a short in-game beat, not instantly: an SMS the same second you pick the
  -- jacket up reads as a script firing, not as a person who saw you take it.
  local g = Msg.env.gameSeconds and Msg.env.gameSeconds()
  local lead = (cfg().firstMessageHours or 2.0) * 3600
  fset("due", (g or 0) + lead)
  log(string.format("unlocked (%s) — first text in ~%.1f in-game hours", tostring(why), lead / 3600))
end

-- ---------------------------------------------------------------------------
-- Choosing what he sends
-- ---------------------------------------------------------------------------

local function tierNow(key)
  if not Msg.env.famTier then return 0 end
  -- Keyless in this mod: Fam.tier() takes no argument. `key` is kept in the signature only so the
  -- forty call sites below did not all have to change.
  local t = Msg.env.famTier(key)
  return type(t) == "number" and t or 0
end

-- One-shot beats (the two openers) are struck off permanently, in a bitmask fact — there are only a
-- handful of them, so this stays a single Int32 no matter how big the check-in pool grows.
local function onceIndex(p, beat)
  local n = 0
  for _, b in ipairs(p.beats) do
    if b.once then
      n = n + 1
      if b.id == beat.id then return n end
    end
  end
  return nil
end

local function onceDone(p, beat)
  local i = onceIndex(p, beat); if not i then return false end
  local mask = fget("once")
  return math.floor(mask / 2 ^ (i - 1)) % 2 == 1
end

local function markOnce(p, beat)
  local i = onceIndex(p, beat); if not i then return end
  local mask = fget("once")
  if math.floor(mask / 2 ^ (i - 1)) % 2 == 0 then fset("once", mask + 2 ^ (i - 1)) end
end

local function eligible(p, key, kinds)
  local tier, out = tierNow(key), {}
  local g = Msg.env.gameSeconds and Msg.env.gameSeconds()
  local since = g and (g - (fget("t0") or 0)) / 3600 or nil
  for _, b in ipairs(p.beats) do
    local want = false
    for _, k in ipairs(kinds) do if b.kind == k then want = true end end
    if want and b.tier <= tier
       and not (b.once and onceDone(p, b))
       and not rt().bag[b.id]
       -- `afterHours`: a beat that must not land until N in-game hours after the chain started.
       and not (b.afterHours and since and since < b.afterHours)
       -- an invite for a venue this persona doesn't actually use would send V somewhere he'll never be
       and not (b.venue and Msg.env.venueKnown and not Msg.env.venueKnown(b.venue)) then
      out[#out + 1] = b
    end
  end
  return out
end

-- Draw from `kinds` without repeating until the pool is exhausted, then refill. Openers jump the
-- queue: while one is pending he has not introduced himself yet, and nothing else makes sense.
local function pick(p, key)
  local openers = eligible(p, key, { "opener" })
  if #openers > 0 then return openers[1] end

  local kinds = { "checkin", "question" }
  -- Invites need tier 2 and no rendezvous already on the books.
  if tierNow(key) >= 2 and fget("rv") == 0 then kinds[#kinds + 1] = "invite" end

  local pool = eligible(p, key, kinds)
  if #pool == 0 then
    -- bag empty: refill and redraw (keeps `once` beats struck off — those are not in the bag)
    rt().bag = {}
    pool = eligible(p, key, kinds)
    if #pool == 0 then return nil end
  end
  local n = 1
  pcall(function() n = math.random(1, #pool) end)
  return pool[n]
end

-- ---------------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------------
local function deliver(path, notify)
  -- recycle first (silently), so a beat drawn again later still notifies
  setState(path, "gameJournalPhoneMessage", "Inactive", "DoNotNotify")
  return setState(path, "gameJournalPhoneMessage", "Active", notify or "Notify")
end

-- Queue a beat's bubbles so they arrive a couple of seconds apart instead of as one wall of text.
local function send(p, key, beat)
  ensureContact(p)
  if not entry(beat.bubbles[1], "gameJournalPhoneMessage") then
    log("archive missing entry " .. tostring(beat.bubbles[1]) .. " — is JackieLives.archive installed?")
    return false
  end
  rt().queue = { paths = beat.bubbles, i = 0, nextAt = 0, beat = beat }
  fset("n", fget("n") + 1)          -- v1.91: drives the early/late cadence ramp in gapHours
  if beat.once then markOnce(p, beat) end
  rt().bag[beat.id] = true
  log(string.format("sending %s (%s, tier %d)", beat.id, beat.kind, beat.tier))
  return true
end

-- Followups are him reply to V's reply — same staggering, no re-arming of the choice group.
local function sendFollowup(paths)
  if not paths or #paths == 0 then return end
  rt().queue = { paths = paths, i = 0, nextAt = 0 }
end

-- ⚠️ v1.91 — ONE CHOICE GROUP ACTIVE AT A TIME, EVER. This is the invariant the whole thread depends
-- on, and until now only HALF the code kept it: `disarmOutgoing` put its group and every entry back
-- to Inactive, and `armReplies` never put anything back at all. So the group behind every beat he
-- had ever sent stayed Active for the rest of the save, piling up on one conversation. The messenger
-- draws whatever is Active, so after the first exchange V was looking at a stack of stale options —
-- and picking one did nothing, because `pollReply` is only ever watching the LATEST beat's paths.
-- Reported 2026-08-22: *"I can only reply to the first message and after that it bugs out and becomes
-- unusable."* That is this, exactly.
-- `rt().armed` is the one group currently offered. Arm anything and the previous one comes down
-- first; answer it and it comes down too.
local function disarmGroup(beat)
  if not (beat and beat.group) then return end
  for _, r in ipairs(beat.replies or {}) do
    setState(r.path, "gameJournalPhoneChoiceEntry", "Inactive", "DoNotNotify")
  end
  setState(beat.group, "gameJournalPhoneChoiceGroup", "Inactive", "DoNotNotify")
  if rt().armed == beat then rt().armed = nil end
  -- ⚠️ AND CLEAR THE OUTGOING LATCH IF THIS WAS IT. `rt().out` is what step 3b tests before it will
  -- offer V a way to start a conversation. Take the group down without clearing the latch and V's
  -- side is dead for the rest of the save: the group is Inactive so nothing can be tapped, and the
  -- latch is set so nothing re-arms. His question simply takes the thread for as long as it is open.
  if rt().out == beat then rt().out = nil end
end

local function armReplies(beat)
  if not beat.group then return end
  if rt().armed and rt().armed ~= beat then disarmGroup(rt().armed) end   -- v1.91: never two at once
  for _, r in ipairs(beat.replies or {}) do
    -- Inactive+Active on each choice, so a reply offered before can be offered again
    setState(r.path, "gameJournalPhoneChoiceEntry", "Inactive", "DoNotNotify")
    setState(r.path, "gameJournalPhoneChoiceEntry", "Active", "DoNotNotify")
  end
  setState(beat.group, "gameJournalPhoneChoiceGroup", "Active", "DoNotNotify")
  rt().armed = beat
  -- ⚠️ v1.91 — TWO CLOCKS, BECAUSE ONE OF THEM CAN BE SKIPPED. `until_` is REAL seconds, and while
  -- `await` is set the tick returns before it ever reaches "is him next text due" — so a pending
  -- question stops him whole schedule for up to half an hour of REAL time. In a game with a Skip
  -- Time button that is the wrong clock to be alone: sleep through a day and a half in four real
  -- seconds and he still owes you a text he cannot send, which reads exactly as "he doesn't text
  -- on his own even after hours of in-game time" (reported 2026-08-22).
  -- `gameUntil` is the same window measured the way the player experiences it. Whichever runs out
  -- first ends the wait — he would not sit staring at him phone for a day and a half either.
  local gnow = Msg.env.gameSeconds and Msg.env.gameSeconds()
  rt().await = { beat = beat,
                 sentG     = gnow,          -- v1.91: the gap is measured from HERE, not from the timeout
                 until_    = (Msg.env.clock and Msg.env.clock() or 0) + (cfg().replyWindowSeconds or 1800),
                 gameUntil = gnow and (gnow + (cfg().replyWindowGameHours or 6.0) * 3600) or nil }
  fset("await", 1)
end

-- ---------------------------------------------------------------------------
-- Rendezvous — he names a place, and is there when V arrives (docs/MESSAGES.md §6)
--
-- This module owns the STATE (which venue, until when). The engine owns the spawn: it asks
-- Msg.pendingVenue() each tick and places him when V gets close. Keeping the split here means the
-- engine hook is a few lines and everything else is testable off-game.
-- ---------------------------------------------------------------------------
local VENUE_IDS = {}   -- venue key -> small int, so it fits in a fact
local VENUE_KEYS = {}
-- ⚠️ THIS ORDER IS PERSISTED. The venue is stored in a fact as its INDEX in this list, so reordering
-- it silently sends every existing save's pending rendezvous to a different bar. Append only.
-- The keys themselves are config.lua's `Config.approach.venues` (all seven), which is what the
-- engine's venue walk/snap/sit machinery already knows how to place him at.
for i, k in ipairs({ "noodle", "misty", "coyote", "afterlife", "ginger", "redwood", "lizzies" }) do
  VENUE_IDS[k], VENUE_KEYS[i] = i, k
end

local function armRendezvous(beat)
  local vid = beat.venue and VENUE_IDS[beat.venue]
  if not vid then log("invite " .. tostring(beat.id) .. " has no known venue"); return end
  local g = Msg.env.gameSeconds and Msg.env.gameSeconds() or 0
  fset("rv", vid)
  fset("rvx", g + (cfg().rendezvousHours or 6.0) * 3600)
  log(string.format("rendezvous armed: %s for the next %.1f in-game hours", beat.venue, cfg().rendezvousHours or 6.0))
end

--- The venue the CURRENT persona has agreed to meet V at, or nil.
local function pendingVenueFor()
  local vid = fget("rv")
  if vid == 0 then return nil end
  return VENUE_KEYS[vid]
end

--- Is ANY persona expecting V somewhere? Returns venue key + roster key, or nil.
--- The engine polls this (nclRendezvousTick) — it must not depend on who is active, because the
--- whole point is that he can arrange to meet V before V has ever made him their companion.
function Msg.pendingVenue()
  for _, p in ipairs(personaList()) do
    local v = withPersona(p, pendingVenueFor)
    if v then return v, p.key end
  end
  return nil
end

--- Engine calls this once he has actually been placed at the venue, so the invite is spent.
--- `key` names whose rendezvous it was; omitted means the active/default persona.
function Msg.rendezvousMet(key)
  local target
  for _, p in ipairs(personaList()) do if p.key == key then target = p end end
  target = target or defaultPersona()
  if not target then return end
  withPersona(target, function()
    if fget("rv") == 0 then return end
    log("rendezvous met — " .. tostring(pendingVenueFor()) .. " (" .. tostring(target.key) .. ")")
    fset("rv", 0)
    fset("rvx", 0)
    -- Give the after-date beats a chance to be the next thing he sends.
    fset("aft", 1)
  end)
end

local function rendezvousExpired(p, key)
  if fget("rv") == 0 then return end
  local g = Msg.env.gameSeconds and Msg.env.gameSeconds()
  if not (g and g >= fget("rvx")) then return end
  fset("rv", 0)
  fset("rvx", 0)
  log("rendezvous expired — V never showed")
  -- He says something about it, ONCE, and the next invite is held back a while. Standing him up
  -- should cost something; it is the only negative event in the whole system.
  local pool = eligible(p, key, { "standup" })
  if #pool > 0 then
    local n = 1; pcall(function() n = math.random(1, #pool) end)
    send(p, key, pool[n])
  end
  if Msg.env.famAdd and key then pcall(Msg.env.famAdd, key, "stood him up", -1) end
  local gs = Msg.env.gameSeconds and Msg.env.gameSeconds() or 0
  fset("due", gs + (cfg().sulkHours or 24.0) * 3600)
end

-- ---------------------------------------------------------------------------
-- V texts HER  (v1.46)
--
-- The phone has no "compose" button we can hook, but it does draw whatever reply group is currently
-- Active on a thread. So an OUTGOING beat is a choice group with no message of his in front of it:
-- leave it armed and the player can open the thread and say something whenever they like.
--
-- It is deliberately NOT always available. Re-arming on a cooldown is what stops it feeling like a
-- vending machine — but that cooldown is much SHORTER than his own gaps, because reaching out to
-- someone should be easier than waiting to be thought of.
-- ---------------------------------------------------------------------------
local function armOutgoing(idx, key)
  local pool = eligible(idx, key, { "outgoing" })
  if #pool == 0 then
    -- Outgoing beats are re-usable, so an empty pool just means the bag needs refilling.
    --
    -- ⚠️ ...but NOT the one V just used. NCLives refills the whole bag and redraws, which on a small
    -- pool can hand V back the exact same three options they answered a second ago — the vending
    -- machine this cooldown exists to avoid, and it reads as the thread not responding rather than
    -- as a choice. Hold the last one back, and only give it up if it is genuinely all there is.
    local last = rt().lastOut
    for _, b in ipairs(idx.beats) do
      if b.kind == "outgoing" and b.id ~= last then rt().bag[b.id] = nil end
    end
    pool = eligible(idx, key, { "outgoing" })
    if #pool == 0 and last then
      rt().bag[last] = nil                      -- it was the only one: better repeated than silent
      pool = eligible(idx, key, { "outgoing" })
    end
    if #pool == 0 then return end
  end
  local n = 1; pcall(function() n = math.random(1, #pool) end)
  local beat = pool[n]
  if not beat.group or not entry(beat.group, "gameJournalPhoneChoiceGroup") then return end
  ensureContact(idx)
  if rt().armed and rt().armed ~= beat then disarmGroup(rt().armed) end   -- v1.91: never two at once
  for _, r in ipairs(beat.replies or {}) do
    setState(r.path, "gameJournalPhoneChoiceEntry", "Inactive", "DoNotNotify")
    setState(r.path, "gameJournalPhoneChoiceEntry", "Active", "DoNotNotify")
  end
  setState(beat.group, "gameJournalPhoneChoiceGroup", "Active", "DoNotNotify")
  rt().out     = beat
  rt().armed   = beat
  rt().lastOut = beat.id                        -- what the bag refill above must not re-offer first
  rt().bag[beat.id] = true
  log(("V can text %s now (%s)"):format(tostring(key), beat.id))
end

local function disarmOutgoing()
  local beat = rt().out
  if not beat then return end
  disarmGroup(beat)          -- v1.91: one helper, so the two sides cannot drift apart again
  rt().out = nil
end

--- Did V just text him? If so, answer and start the cooldown.
local function pollOutgoing(idx, key)
  local beat = rt().out; if not beat then return end
  for _, r in ipairs(beat.replies or {}) do
    if isSucceeded(stateOf(r.path, "gameJournalPhoneChoiceEntry")) then
      log(("V texted %s: %s"):format(tostring(key), r.id))
      disarmOutgoing()
      if r.fam ~= 0 and Msg.env.famAdd and key then
        pcall(Msg.env.famAdd, key, "texted him first", r.fam)
      end
      rt().queue = { paths = r.followup or {}, i = 0, nextAt = 0 }
      -- A CONVERSATION, not a single exchange. Once V has opened one, keep V's side armed for a few
      -- more turns — that is what makes it feel like texting rather than picking from a menu once an
      -- evening. Only when the thread runs out of turns does the cooldown start.
      rt().outChain = (rt().outChain or 0) + 1
      if rt().outChain < (cfg().outgoingChainTurns or 3) then
        rt().rearm = true                      -- armed once his answer has finished landing
      else
        rt().outChain = 0
        local g = Msg.env.gameSeconds and Msg.env.gameSeconds() or 0
        local lo = cfg().outgoingCooldownMinHours or 0.5
        local hi = cfg().outgoingCooldownMaxHours or 3.0
        local j = 0.5; pcall(function() j = math.random() end)
        fset("outdue", g + (lo + (hi - lo) * j) * 3600)
      end
      return
    end
  end
end

-- ---------------------------------------------------------------------------
-- Scheduling
-- ---------------------------------------------------------------------------
-- ⚠️ v1.91 — THE FIRST FEW TEXTS COME FASTER, and it is not a tier thing. Familiarity only moves when
-- V TALKS to them, so a player who has only ever texted stays at tier 0 forever — where the gap used
-- to be 30 in-game hours, i.e. a day and a quarter of play between the first text and the second.
-- That is indistinguishable from broken, and it was being reported as broken.
-- So the ramp is by HOW MANY he has sent, not by how well he knows you: the opening exchanges land
-- close enough together to read as a conversation starting, and once that is established he settles
-- into him real, unhurried cadence. `earlyCount` texts at earlyHours, everything after at lateHours.
-- Antonia, 2026-08-22: *"let's make the first few messages only 10-22 hours, later conversations can
-- be 24-40 hours apart."*
local function gapHours(key)
  local C = cfg()
  local sent = fget("n")
  local lo, hi
  if sent < (C.earlyCount or 5) then
    lo, hi = (C.earlyGapHours or { 10.0, 22.0 })[1], (C.earlyGapHours or { 10.0, 22.0 })[2]
  else
    lo, hi = (C.lateGapHours or { 24.0, 40.0 })[1], (C.lateGapHours or { 24.0, 40.0 })[2]
  end
  -- Uniform across the band rather than a midpoint ±25%: the band IS the jitter, and a flat draw
  -- across it is what stops the gap reading as a timer.
  local j = 0.5
  pcall(function() j = math.random() end)
  return lo + (hi - lo) * j
end

-- ⚠️ v1.91 — `fromG` IS NOT OPTIONAL DECORATION. The gap is the time between him TEXTS, not the time
-- after he stops waiting for an answer. Once every beat had reply options (2026-08-22 content pass)
-- every unanswered text started costing its whole reply window ON TOP of the gap — so a player who
-- reads him messages and never taps anything sees him slow down, which is the opposite of what that
-- pass was for. The no-reply path passes the moment the text was SENT.
local function scheduleNext(key, why, fromG)
  local g = Msg.env.gameSeconds and Msg.env.gameSeconds()
  if not g then return end
  local h = gapHours(key)
  local base = fromG or g
  -- ...but never schedule into the past: if the wait really did outlast the gap, the next text is
  -- due now, not overdue by a day.
  fset("due", math.max(base + h * 3600, g))
  -- NOTE: in-game time only, on purpose. An earlier build added a real-time floor so that sleeping
  -- twice couldn't produce two texts in a minute — but that IS how it works for a real person who
  -- has been getting on with their day while you were asleep (Antonia, 2026-08-01). Skipping time
  -- skips time.
  log(string.format("next text in ~%.1f in-game hours (%s)", h, tostring(why)))
end

-- A text that lands mid-firefight reads as a bug, not as immersion.
local function suppressed()
  if Msg.env.inCombat and Msg.env.inCombat() then return true end
  if Msg.env.busy and Msg.env.busy() then return true end
  -- He doesn't text you while he is standing in front of you. (NCLives has to ask "is the spawned
  -- companion THIS persona?" here; with one character, spawned means him.)
  if Msg.env.spawned and Msg.env.spawned() then return true end
  return false
end

-- ---------------------------------------------------------------------------
-- Replies
-- ---------------------------------------------------------------------------
local function pollReply(p, key)
  local a = rt().await; if not a then return end
  local now = Msg.env.clock and Msg.env.clock() or 0
  for _, r in ipairs(a.beat.replies or {}) do
    if isSucceeded(stateOf(r.path, "gameJournalPhoneChoiceEntry")) then
      log("V replied: " .. r.id)
      -- v1.91: the question has been answered — take its options down. Leaving them Active is what
      -- made the thread unusable (see disarmGroup).
      disarmGroup(a.beat)
      rt().await = nil
      fset("await", 0)
      if r.fam ~= 0 and Msg.env.famAdd and key then
        pcall(Msg.env.famAdd, key, "texted him back", r.fam)
      end
      if r.accept then armRendezvous(a.beat) end
      sendFollowup(r.followup)
      -- A story contact has no cadence to push forward — there is no "next text" from an unknown
      -- number. Writing a due-time for one would be harmless but meaningless; not writing it keeps
      -- its facts to exactly what it uses.
      if CUR == nil or CUR.ticks ~= false then scheduleNext(key, "after a reply") end
      return
    end
  end
  -- V just never answers. Not an error — he moves on, and the thread keeps its choices sitting there.
  local gnow2 = Msg.env.gameSeconds and Msg.env.gameSeconds()
  local timedOut = now >= a.until_
                or (a.gameUntil and gnow2 and gnow2 >= a.gameUntil)      -- v1.91: the skippable clock
  if timedOut then
    log("no reply — moving on")
    -- The options stay ON SCREEN here, deliberately: he has stopped waiting, but V answering late
    -- is still a reasonable thing to let happen. `rt().armed` still points at them, so the NEXT
    -- thing that arms a group takes them down — which is what keeps them from piling up.
    rt().await = nil
    fset("await", 0)
    if CUR == nil or CUR.ticks ~= false then
      scheduleNext(key, "no reply", a.sentG)   -- v1.91: measured from when the text went out
    end
  end
end

-- ---------------------------------------------------------------------------
-- Tick
-- ---------------------------------------------------------------------------
function Msg.onInit()
  -- ⚠️ Drop ALL per-persona scratch, throttles included. The throttles hold CLOCK values and the
  -- clock restarts at 0 on a CET soft-reload — leaving a stale "next poll at 2000" behind means the
  -- unlock gate silently never polls again for the rest of the session. Caught by
  -- tools/test_messages.lua, which reuses the module across stub worlds and reproduces exactly that.
  Msg.rt = { p = {} }
  local sched, story = {}, {}
  for _, p in ipairs(personas(true))  do sched[#sched + 1] = p.key end
  for _, p in ipairs(personas(false)) do story[#story + 1] = p.key end
  log(string.format("ready — scheduled: %s | story-only: %s",
      #sched > 0 and table.concat(sched, ", ") or "NONE",
      #story > 0 and table.concat(story, ", ") or "none"))
end

--- One persona's state machine. `CUR` is already set to `p`.
local function tickPersona(p, dt)
  local key = p.key
  local idx = p.idx
  local now = Msg.env.clock and Msg.env.clock() or 0

  -- 1. bubbles still landing from the last beat, one every couple of seconds
  local q = rt().queue
  if q then
    if now >= (q.nextAt or 0) then
      q.i = q.i + 1
      if q.i > #q.paths then
        rt().queue = nil
        -- mid-conversation: hand the thread straight back to V
        if rt().rearm then
          rt().rearm = nil
          armOutgoing(idx, key)
          return
        end
        if q.beat and q.beat.group then
          armReplies(q.beat)
        elseif q.beat then
          scheduleNext(key, "sent " .. q.beat.id)
        end
      else
        -- Only the FIRST bubble raises the phone popup; the rest slide into the thread quietly, the
        -- way a real multi-part text does.
        deliver(q.paths[q.i], q.i == 1 and "Notify" or "DoNotNotify")
        q.nextAt = now + (cfg().bubbleSeconds or 2.5)
      end
    end
    return                                  -- nothing else while a beat is still arriving
  end

  -- 1b. A STORY-ONLY CONTACT STOPS HERE — but it must get this far, and that is the whole point.
  --
  -- ⚠️ "No schedule" does NOT mean "no tick". These contacts still have to DELIVER: the bubbles of a
  -- beat arc.lua fired are staggered through the queue above, and when V taps "Who is this?" it is
  -- pollReply below that notices and sends the answer. Skipping them entirely (which is what
  -- iterating only the scheduled personas did) left arc.lua's texts queued and never sent — the beat
  -- fired, Msg.sendStory returned true, and nothing ever appeared on the phone.
  --
  -- What they skip is everything that would give them a personality of their own: the unlock gate,
  -- the cadence, the shuffle bag, rendezvous, and V's outgoing side. An unknown Arasaka number does
  -- not check in on you, and there must be no way for it to try.
  if not p.ticks then
    if rt().await and now >= rt().pollAt then
      rt().pollAt = now + (cfg().replyPollSeconds or 2.0)
      pollReply(idx, key)
    end
    return
  end

  -- 2. the unlock gate, polled cheaply until it passes
  if not Msg.unlocked() then
    if now >= rt().gateAt then
      rt().gateAt = now + (cfg().gatePollSeconds or 5.0)
      local ok, why = gatePassed()
      if ok then
        Msg.unlock(why)
        fset("t0", Msg.env.gameSeconds and Msg.env.gameSeconds() or 0)
      end
    end
    return
  end

  -- 3a. did V text HER? (checked before his own schedule — the player acting beats a timer)
  if rt().out then pollOutgoing(idx, key) end

  -- 3b. re-arm V's side once its cooldown has passed, so there is usually something to say
  if not rt().out and not rt().await and Msg.unlocked() then
    local gnow = Msg.env.gameSeconds and Msg.env.gameSeconds()
    if gnow and gnow >= fget("outdue") then armOutgoing(idx, key) end
  end

  -- 3. waiting on a reply
  if rt().await then
    if now >= rt().pollAt then
      rt().pollAt = now + (cfg().replyPollSeconds or 2.0)
      pollReply(idx, key)
    end
    return
  end

  -- 4. a rendezvous that timed out
  rendezvousExpired(idx, key)

  -- 5. is the next text due?
  local g = Msg.env.gameSeconds and Msg.env.gameSeconds()
  if not g then return end
  local due = fget("due")
  if due == 0 then scheduleNext(key, "first schedule"); return end
  if g < due then return end
  if suppressed() then return end          -- due, but a bad moment — try again next tick

  -- after-date beats get first refusal once, right after an evening out
  local beat
  if fget("aft") == 1 then
    local pool = eligible(idx, key, { "afterdate" })
    if #pool > 0 then
      local n = 1; pcall(function() n = math.random(1, #pool) end)
      beat = pool[n]
    end
    fset("aft", 0)
  end
  beat = beat or pick(idx, key)
  if not beat then scheduleNext(key, "nothing eligible"); return end
  if not send(idx, key, beat) then
    -- archive missing: back off hard rather than retrying every frame
    fset("due", g + 24 * 3600)
  end
end

--- EVERY contact ticks — the scheduled one runs its whole state machine, the story-only ones run
--- just enough to finish delivering what arc.lua started (see step 1b). One persona erroring must
--- not stop the others, so each is isolated.
function Msg.tick(dt)
  if not cfg().enabled then return end
  for _, p in ipairs(personas()) do
    withPersona(p, function() tickPersona(p, dt) end)
  end
end

-- ---------------------------------------------------------------------------
-- Debug / Native Settings
-- ---------------------------------------------------------------------------
--- One line per persona with a pack — not just the active one.
function Msg.status()
  local list = personaList()
  if #list == 0 then return "no character has SMS content installed" end
  local rows = {}
  for _, p in ipairs(list) do
    rows[#rows + 1] = withPersona(p, function()
      local g = Msg.env.gameSeconds and Msg.env.gameSeconds() or 0
      local due = fget("due")
      return string.format(
        "%s | unlocked=%s tier=%d | next in %.1f h | rendezvous=%s | awaiting reply=%s",
        p.key, tostring(Msg.unlocked()), tierNow(p.key),
        math.max(0, (due - g)) / 3600, tostring(pendingVenueFor()), tostring(rt().await ~= nil))
    end) or (p.key .. " | error")
  end
  return table.concat(rows, "   //   ")
end

--- Debug: send a specific beat now, or the next scheduled one. Used by the CET tuner button.
--- Every early return LOGS why, because "the button does nothing" is otherwise unfalsifiable.
function Msg.sendNow(beatId)
  local target = defaultPersona()
  if not target then
    log("sendNow: nobody has an SMS pack installed")
    return false
  end
  return withPersona(target, function()
    if not Msg.unlocked() then Msg.unlock("debug send") end
    local beat
    for _, b in ipairs(target.idx.beats) do if b.id == beatId then beat = b end end
    beat = beat or pick(target.idx, target.key)
    if not beat then log("sendNow: nothing eligible to send"); return false end
    return send(target.idx, target.key, beat)
  end) or false
end

--- Fire a STORY beat by name — the questline's entry point (storyboard.lua's `sms` blocks, driven by
--- arc.lua). Unlike Msg.sendNow it NEVER falls back to picking something at random: an arc beat that
--- cannot be delivered must report that, because sending a chit-chat line in place of a plot point
--- would be worse than sending nothing. Returns true only if the beat was actually queued.
---
--- It also bypasses the scheduler entirely (no tier, no bag, no gap) — the story decides when these
--- land, not the cadence — but it still goes through `send`, so it recycles, staggers its bubbles and
--- arms its replies exactly like any other text, and still fails soft with no archive installed.
function Msg.sendStory(beatId)
  -- Searched across ALL contacts, not just Jackie: Part 2's dread arrives from an unknown number and
  -- its netrunner quotes a price, and neither of them is him.
  local target, beat = personaForBeat(beatId)
  if not target then
    log("sendStory: no beat named " .. tostring(beatId) .. " in any contact — is content/*.json in "
        .. "step with storyboard.lua? (tools/audit_messages.py answers exactly that)")
    return false
  end
  return withPersona(target, function()
    if beat.kind ~= "story" then
      log("sendStory: " .. tostring(beatId) .. " is kind '" .. tostring(beat.kind)
          .. "', not 'story' — the scheduler owns that one")
      return false
    end
    log(("sendStory: %s -> contact '%s'"):format(tostring(beatId), tostring(target.cid)))
    -- The arc gets to text even before the ambient chain has unlocked itself: by the time a story
    -- beat fires, the story has already decided V is allowed to hear it.
    if not Msg.unlocked() then Msg.unlock("story beat " .. tostring(beatId)) end
    return send(target.idx, target.key, beat)
  end) or false
end

--- One-click "why isn't this working". Walks the chain in the order it can break and names the FIRST
--- thing that is wrong, instead of leaving the player to guess between a missing archive, a missing
--- ArchiveXL, the wrong companion being active, and a bad path. Returns an array of lines.
---
--- ⚠️ Deliberately checks the JOURNAL, not our own state: `entry()` returning nil for the contact is
--- the single fact that separates "the archive isn't loaded" from every software problem on our side.
function Msg.diagnose()
  local out = {}
  local function say(s) out[#out + 1] = s; log(s) end

  say("---- JackieLives messages: diagnosis ----")

  -- ⚠️ REPORT EVERY BINDING THIS MODULE CANNOT WORK WITHOUT, BY NAME. The NCLives v1.72 failure was
  -- a binding listed in bind()'s allow-list and never passed from init.lua: the feature was inert,
  -- the log was clean, and the offline tests passed because the harness binds them itself. The only
  -- defence that survives that is asking the LIVE module what it actually holds.
  local missing = {}
  for _, k in ipairs({ "log", "Config", "gameSeconds", "clock", "factGet", "factSet",
                       "gate", "famTier", "famAdd", "busy", "inCombat", "spawned", "venueKnown" }) do
    if Msg.env[k] == nil then missing[#missing + 1] = k end
  end
  say(("bindings missing : %s"):format(#missing > 0 and table.concat(missing, ", ") or "none"))
  if #missing > 0 then
    say("  -> init.lua's Msg.bind{...} does not pass these. Being on bind()'s allow-list is NOT")
    say("     being bound; `gate` missing means the chain can never start at all.")
  end

  local names = {}
  for k in pairs(Index.personas) do names[#names + 1] = k end
  table.sort(names)
  say(("packs installed  : %s"):format(#names > 0 and table.concat(names, ", ") or "NONE"))
  -- The arc's other voices own a contact each but no schedule, so they never appear in the sections
  -- below. Naming them here is the difference between "Nix never texted" being a bug report and
  -- being a question about where the questline actually is.
  local story = {}
  for _, p in ipairs(personas(false)) do story[#story + 1] = p.key end
  say(("story-only       : %s   <- no schedule; these speak only when arc.lua says so")
      :format(#story > 0 and table.concat(story, ", ") or "none"))

  local target = defaultPersona()
  if not target then
    say("STOP: there is no authored SMS pack for Jackie.")
    say("  -> mod/JackieLives/messages_index.lua is empty or missing his contact. Re-run")
    say("     `python3 tools/gen_messages.py` on the Mac and ship what it writes.")
    return out
  end
  CUR = target                                   -- everything below reports on THIS persona
  local p, key = target.idx, target.key
  say(("reporting on     : %s   -> contact '%s'"):format(tostring(key), tostring(target.cid)))

  if not jm() then
    say("STOP: no JournalManager. Are you actually in a loaded save (not the main menu)?")
    CUR = nil
    return out
  end

  -- The decisive test. These entries exist ONLY if JackieLives.archive is installed AND ArchiveXL merged
  -- it into the journal, so a nil here is never a bug in this Lua file.
  local contactOk = entry(p.contactPath, "gameJournalContact") ~= nil
  local convoOk   = entry(p.convoPath, "gameJournalPhoneConversation") ~= nil
  local firstMsg  = p.beats[1] and p.beats[1].bubbles[1]
  local msgOk     = firstMsg and entry(firstMsg, "gameJournalPhoneMessage") ~= nil
  say(("journal entries  : contact=%s conversation=%s message=%s")
      :format(tostring(contactOk), tostring(convoOk), tostring(msgOk)))

  if not (contactOk and convoOk and msgOk) then
    say("STOP: the game does not have our journal entries — the archive is not loaded.")
    say("  Check, in this order:")
    say("   1. ArchiveXL is installed (it is a SEPARATE mod from CET).")
    say("   2. <game>\\archive\\pc\\mod\\ contains BOTH JackieLives.archive AND JackieLives.archive.xl.")
    say("   3. You restarted the game after adding them (archives load at startup only).")
    say(("   (looked for: %s)"):format(tostring(p.contactPath)))
    CUR = nil
    return out
  end

  local gok, gwhy = gatePassed()
  say(("story gate       : %s%s   <- Retrieval.isUnlocked(): has V actually got him back?")
      :format(tostring(gok), gwhy and ("  (" .. tostring(gwhy) .. ")") or ""))
  say(("unlocked         : %s"):format(tostring(Msg.unlocked())))
  say(("familiarity tier : %d"):format(tierNow(key)))
  say(("queue / awaiting : %s / %s")
      :format(tostring(rt().queue ~= nil), tostring(rt().await ~= nil)))
  say(("pending meet-up  : %s"):format(tostring(Msg.pendingVenue())))

  -- ---- deep probe -----------------------------------------------------------------------------
  -- Reached when everything WE control looks right but no text shows up. Rather than guess, actually
  -- deliver one and then ask the game what it thinks — including the two questions the messenger UI
  -- itself asks before it will draw a contact (messengerUtils.script:70 and :34):
  --   * JournalContact:IsKnown()  — an Active contact that isn't "known" is skipped entirely
  --   * GetFlattenedMessagesAndChoices() — what the phone actually finds under the contact
  say("---- deep probe: delivering one message and asking the game what it sees ----")

  local m = jm()
  local function put(path, class, state, notify)
    local res
    local okc = pcall(function() res = m:ChangeEntryState(path, class, state, notify) end)
    return okc and res
  end

  say(("contact  Active -> returned %s, reads back %s")
      :format(tostring(put(p.contactPath, "gameJournalContact", "Active", "DoNotNotify")),
              tostring(stateOf(p.contactPath, "gameJournalContact"))))
  say(("convo    Active -> returned %s, reads back %s")
      :format(tostring(put(p.convoPath, "gameJournalPhoneConversation", "Active", "DoNotNotify")),
              tostring(stateOf(p.convoPath, "gameJournalPhoneConversation"))))
  put(firstMsg, "gameJournalPhoneMessage", "Inactive", "DoNotNotify")
  say(("message  Active -> returned %s, reads back %s")
      :format(tostring(put(firstMsg, "gameJournalPhoneMessage", "Active", "Notify")),
              tostring(stateOf(firstMsg, "gameJournalPhoneMessage"))))

  local contact = entry(p.contactPath, "gameJournalContact")
  local known
  pcall(function() known = contact:IsKnown(m) end)
  say(("contact IsKnown  : %s   <- the phone SKIPS a contact that is not known")
      :format(tostring(known)))

  local nMsg, nChoice = "?", "?"
  pcall(function()
    local msgs, choices = m:GetFlattenedMessagesAndChoices(contact)
    nMsg = msgs and #msgs or 0
    nChoice = choices and #choices or 0
  end)
  say(("phone sees       : %s message(s), %s reply option(s) under this contact")
      :format(tostring(nMsg), tostring(nChoice)))

  if known == false then
    say("STOP: the contact is not 'known', so the messenger will never list it.")
  else
    say("Delivered one message — check the phone NOW. If it is still empty, send me these lines.")
  end
  CUR = nil
  return out
end

return Msg
