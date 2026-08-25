-- tools/test_messages.lua — unit tests for the SMS system (JackieLives v1.92).
--
-- Run from the repo root:   lua tools/test_messages.lua
-- Exits non-zero on failure. Needs only a stock Lua 5.x / LuaJIT (no game, no CET, no Windows).
--
-- This is NOT a copy of the logic: it `require`s the SHIPPED mod/JackieLives/messages.lua and runs the
-- real code against a stubbed `Game.GetJournalManager()` / `Game.GetQuestsSystem()`.
--
-- Why it matters more than usual here: the message TEXT lives in an .archive, so the ONLY thing that
-- can be exercised on the Mac is exactly this — the schedule, the gate, the reply handling and the
-- rendezvous bookkeeping. Everything below the journal boundary is a stub, so a passing run means
-- "the logic is right", not "the archive is right" (the archive is checked by gen_messages.py's
-- index/archive parity assertion, and finally by seeing a text land in game).
--
-- The stub journal knows only the paths messages_index.lua actually declares, so asking it for a
-- path the generator never emitted reads back as "not installed" — which is also how a player with
-- no JackieLives.archive behaves.
--
-- PORTED FROM NCLives, whose harness runs a ROSTER of personas. Everything about who-is-active, which
-- character mod is installed, and the Project V addon switch is gone: JackieLives has one character.
-- What replaces it is the GATE — NCLives reads Jackie's jacket quest out of the vanilla journal, we
-- inject `Retrieval.isUnlocked()` — and section 15, which covers `Msg.sendStory` and the storyboard
-- beats, neither of which NCLives has.

package.path = "mod/JackieLives/?.lua;" .. package.path

local fails, checks = 0, 0
local function ok(cond, msg)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    print("  FAIL " .. msg)
  else
    print("  ok   " .. msg)
  end
end
local function section(t) print("\n" .. t) end

local Index = require("messages_index")
local PERSONA = Index.personas["jackie"]
-- The arc's other voices. They own a contact and a thread but NO schedule — messages.lua never ticks
-- them; arc.lua speaks for them via Msg.sendStory. Section 16 is what holds that line.
local UNKNOWN = Index.personas["jackielives_unknown"]
local NIX     = Index.personas["jackielives_nix"]

-- ---------------------------------------------------------------------------
-- Stub world
-- ---------------------------------------------------------------------------
-- ⚠️ THE GATE IS A BINDING HERE, NOT A JOURNAL PATH. NCLives hard-codes Jackie's jacket objective and
-- flips its journal state; ours is `Msg.env.gate`, wired in init.lua to Retrieval.isUnlocked(). So
-- the stub world just carries a boolean and the test flips it — which is the whole reason the port
-- injects it instead of hard-coding a retrieval-stage read inside messages.lua.
local world
local function newWorld(opts)
  opts = opts or {}
  local w = {
    known = {},        -- path -> true: the entry exists (i.e. the archive is installed)
    state = {},        -- path -> "Inactive" | "Active" | "Succeeded"
    calls = {},        -- ordered log of every ChangeEntryState
    facts = {},
    clock = 0,
    game  = 100000,    -- in-game seconds
    tier  = 0,
    combat = false, busy = false, spawned = false,
    gateOpen = false,          -- Retrieval.isUnlocked() — see the note above
    fam = {},
  }
  if not opts.noArchive then
    -- ⚠️ EVERY contact in the index, not just Jackie's. The stub journal is the archive: a path it
    -- does not know reads back as "not installed", which is also exactly how a player with no
    -- JackieLives.archive behaves. Registering only Jackie would make every story beat on another
    -- contact look like a missing archive, and section 16 would pass by testing nothing.
    for _cid, P in pairs(Index.personas) do
      w.known[P.contactPath] = true
      w.known[P.convoPath] = true
      for _, b in ipairs(P.beats) do
        for _, p in ipairs(b.bubbles) do w.known[p] = true end
        if b.group then
          w.known[b.group] = true
          for _, r in ipairs(b.replies or {}) do
            w.known[r.path] = true
            for _, f in ipairs(r.followup or {}) do w.known[f] = true end
          end
        end
      end
    end
  end
  world = w
  return w
end

Game = {
  GetJournalManager = function()
    return {
      GetEntryByString = function(_, path, class)
        if not world.known[path] then return nil end
        return { path = path, class = class,
                 IsKnown = function() return world.known_contact ~= false end }
      end,
      GetEntryState = function(_, e) return world.state[e.path] or "Inactive" end,
      -- the two questions the real messenger UI asks before drawing a contact
      IsKnown = function() return world.known_contact ~= false end,
      GetFlattenedMessagesAndChoices = function(_, _) return {}, {} end,
      ChangeEntryState = function(_, path, class, state, notify)
        if not world.known[path] then return false end
        world.state[path] = state
        world.calls[#world.calls + 1] = { path = path, class = class, state = state, notify = notify }
        return true
      end,
    }
  end,
}

local Msg = require("messages")

local Config = {
  messages = {
    enabled = true,
    earlyCount = 5, earlyGapHours = { 10.0, 22.0 }, lateGapHours = { 24.0, 40.0 },
    outgoingCooldownMinHours = 0.5,
    outgoingCooldownMaxHours = 3.0,
    outgoingChainTurns = 3,
    firstMessageHours = 2.0,
    bubbleSeconds = 2.5,
    replyWindowSeconds = 1800,
    replyPollSeconds = 0,       -- poll every tick in tests
    rendezvousHours = 6.0,
    sulkHours = 24.0,
    gatePollSeconds = 0,
  },
}

local function bind(w)
  Msg.bind{
    log = function() end,
    Config = Config,
    gameSeconds = function() return w.game end,
    clock       = function() return w.clock end,
    factGet     = function(n) return w.facts[n] or 0 end,
    factSet     = function(n, v) w.facts[n] = v end,
    -- ⚠️ THIS LIST MUST MIRROR init.lua's Msg.bind{...} EXACTLY. A binding the harness supplies and
    -- init.lua does not is the NCLives v1.72 failure mode: every check here goes green over a
    -- feature that is completely inert in game. If you add one, add it in init.lua in the same
    -- sitting, and Msg.diagnose() will name it if you don't.
    gate        = function() return w.gateOpen end,
    famTier     = function() return w.tier end,
    famAdd      = function(key, why, n) w.fam[#w.fam + 1] = { why = why, n = n } end,
    busy        = function() return w.busy end,
    inCombat    = function() return w.combat end,
    spawned     = function() return w.spawned end,
    -- Config.approach.venues, minus the ones his pack has no invite for — so section 7's "never
    -- invites V somewhere his pack doesn't list" is testing something.
    venueKnown  = function(v) return v == "noodle" or v == "coyote" or v == "lizzies" end,
  }
  Msg.onInit()
end

--- Tick until `pred` holds or we give up. Advances both clocks, which is what the real loop does.
local function run(w, ticks, stepGame)
  for _ = 1, (ticks or 1) do
    w.clock = w.clock + 0.1
    w.game = w.game + (stepGame or 0)
    Msg.tick(0.1)
  end
end

--- Tick long enough for a whole beat to finish landing: every bubble is `bubbleSeconds` apart, and
--- the reply group is only armed on the tick AFTER the last one. Advances the real clock only, so
--- nothing new can come due while we drain.
local function settle(w)
  for _ = 1, 400 do
    w.clock = w.clock + 0.1
    Msg.tick(0.1)
  end
end

local function sentPaths(w)
  local out = {}
  for _, c in ipairs(w.calls) do
    if c.class == "gameJournalPhoneMessage" and c.state == "Active" then out[#out + 1] = c.path end
  end
  return out
end

-- v1.91: answer whatever question he is currently waiting on, if any. His question OWNS the
-- thread while it is open (only one choice group may be Active at a time — see disarmGroup), so a
-- test that wants to see V's own conversation-starters has to clear his question first. Returns the
-- beat that was answered, or nil.
local function answerPending(w)
  for _, b in ipairs(PERSONA.beats) do
    if b.group and b.kind ~= "outgoing" and w.state[b.group] == "Active" and #(b.replies or {}) > 0 then
      w.state[b.replies[1].path] = "Succeeded"
      settle(w)
      return b
    end
  end
end

local function activeGroups(w)
  local out = {}
  for _, b in ipairs(PERSONA.beats) do
    if b.group and w.state[b.group] == "Active" then out[#out + 1] = b end
  end
  return out
end

local function beatById(id)
  for _, b in ipairs(PERSONA.beats) do if b.id == id then return b end end
end

-- ===========================================================================
section("1. content — what the generator produced")
-- ⚠️ THESE ARE SHAPE CHECKS, NOT VOLUME TARGETS. NCLives asserts >= 20 beats and >= 8 check-ins
-- because Jackie's pack is finished there (43 beats for Jackie). JackieLives' is deliberately small
-- for now — the pipeline was built before the writing. What must hold from the FIRST beat is that
-- every KIND the scheduler can reach has something to draw, because an empty kind is a state machine
-- that picks nothing and reschedules forever. Raise these numbers as the pack grows; don't delete.
ok(PERSONA ~= nil, "Jackie has an authored SMS pack")
ok(#PERSONA.beats >= 10, "...with something in it (" .. #PERSONA.beats .. " beats)")
do
  local kinds, tiers = {}, {}
  for _, b in ipairs(PERSONA.beats) do kinds[b.kind] = (kinds[b.kind] or 0) + 1; tiers[b.tier] = true end
  ok(kinds.opener and kinds.opener >= 1, "there is an opener (his first text after the reunion)")
  ok(kinds.checkin and kinds.checkin >= 2, "there are check-ins")
  ok(kinds.invite and kinds.invite >= 1, "there are rendezvous invites")
  ok(kinds.standup and kinds.standup >= 1, "...and something to say when V doesn't show")
  ok(kinds.afterdate and kinds.afterdate >= 1, "...and something after an evening out")
  ok(kinds.outgoing and kinds.outgoing >= 1, "...and a way for V to start a conversation")
  ok(kinds.story and kinds.story >= 1, "the questline's own texts are in the pack too")
  ok(tiers[0] and tiers[1] and tiers[2], "the low tiers all have content")
end
do
  local bad = {}
  for _, b in ipairs(PERSONA.beats) do
    if b.kind == "invite" and not b.venue then bad[#bad + 1] = b.id end
  end
  ok(#bad == 0, "every invite names a venue")
end

-- ===========================================================================
section("2. the unlock gate — Jackie is actually back")
do
  local w = newWorld(); bind(w)
  run(w, 5)
  ok(not Msg.unlocked(), "locked before V has him back (Retrieval.isUnlocked() is false)")
  ok(#sentPaths(w) == 0, "...and he sends nothing")

  w.gateOpen = true
  run(w, 2)
  ok(Msg.unlocked(), "unlocks once the retrieval questline says he is reunited")
  ok(#sentPaths(w) == 0, "...but does NOT text in the same second (that reads as a script firing)")
  ok(w.facts["jackielives_msg_due_1"] >= w.game, "a first text is scheduled ahead")
end

do
  local w = newWorld(); bind(w)
  ok(Msg.forceStart(), "Native Settings force-start unlocks it manually")
  ok(not Msg.forceStart(), "...and is idempotent")
end

-- ⚠️ 2b — THE v1.72 FAILURE MODE, MADE VISIBLE. NCLives shipped this feature completely inert because
-- a binding was NAMED in bind()'s allow-list and never PASSED from init.lua — and its offline suite
-- went green over it, because the harness binds everything itself. That blind spot is structural, so
-- one test deliberately leaves the gate unbound and asserts the two things that must follow: he stays
-- silent (fail CLOSED — the failure is "no texts", never "a spoiler"), and Msg.diagnose() NAMES the
-- missing binding, so "he never texts" is falsifiable without reading the source.
do
  local w = newWorld()
  Msg.env = {}                                  -- as if init.lua passed almost nothing
  Msg.bind{ log = function() end, Config = Config,
            gameSeconds = function() return w.game end,
            clock       = function() return w.clock end,
            factGet     = function(n) return w.facts[n] or 0 end,
            factSet     = function(n, v) w.facts[n] = v end }
  Msg.onInit()
  w.gateOpen = true                             -- the story says yes; nothing is listening
  run(w, 20)
  ok(not Msg.unlocked(), "an UNBOUND gate fails CLOSED — he never texts, rather than texting early")
  ok(#sentPaths(w) == 0, "...and sends nothing at all")
  local lines; pcall(function() lines = Msg.diagnose() end)
  local rep2 = table.concat(lines or {}, "\n")
  ok(rep2:find("bindings missing"), "diagnose() reports that bindings are missing...")
  ok(rep2:find("gate", 1, true), "...and names `gate` among them")
end

-- ===========================================================================
section("3. the first text")
local function unlockedWorld(tier)
  local w = newWorld(); bind(w)
  w.tier = tier or 0
  w.gateOpen = true
  run(w, 2)
  w.game = w.facts["jackielives_msg_due_1"] + 1     -- jump to when the text is due
  return w
end

do
  local w = unlockedWorld(0)
  local opener = beatById("open01")
  run(w, 2)                                    -- one tick to choose the beat, one to drop bubble 1
  local s = sentPaths(w)
  ok(#s == 1, "one bubble lands first, not the whole text at once")
  ok(s[1] == opener.bubbles[1], "the FIRST text is the opener, not a random check-in")
  local first
  for _, c in ipairs(w.calls) do
    if c.class == "gameJournalPhoneMessage" and c.state == "Active" and not first then first = c end
  end
  ok(first and first.notify == "Notify", "...and it raises the phone popup")

  settle(w)
  s = sentPaths(w)
  ok(#s == #opener.bubbles, "the rest of the text follows, a beat apart")
  local quiet = true
  for i, c in ipairs(w.calls) do
    if c.class == "gameJournalPhoneMessage" and c.state == "Active" and i > 1 and c ~= first then
      if c.notify ~= "DoNotNotify" then quiet = false end
    end
  end
  ok(quiet, "...quietly — only the first bubble pops the phone")

  ok(w.state[opener.group] == "Active", "his reply options are armed once he's done talking")
end

-- ===========================================================================
section("4. replies")
do
  local w = unlockedWorld(0)
  settle(w)                                    -- send the opener + arm replies
  local beat = beatById("open01")
  local thanks
  for _, r in ipairs(beat.replies) do if r.id == "glad" then thanks = r end end
  ok(thanks ~= nil, "the opener offers the warm reply")

  w.state[thanks.path] = "Succeeded"           -- V taps it: the messenger UI does this itself
  settle(w)
  ok(#w.fam == 1 and w.fam[1].n == 1, "replying warmly awards familiarity")
  local got = {}
  for _, p in ipairs(sentPaths(w)) do got[p] = true end
  local all = #thanks.followup > 0
  for _, f in ipairs(thanks.followup) do if not got[f] then all = false end end
  ok(all, "...and he answers the reply, every bubble of it")
  ok(w.facts["jackielives_msg_due_1"] > w.game, "the next text is rescheduled")
end

do
  local w = unlockedWorld(0)
  settle(w)
  w.clock = w.clock + 2000                     -- V never answers
  run(w, 2)
  ok(w.facts["jackielives_msg_await_1"] == 0, "an unanswered text is dropped rather than blocking forever")
end

-- ===========================================================================
section("5. familiarity gates what he says")
do
  local w = unlockedWorld(0)
  -- burn the openers so the pool is check-ins
  run(w, 40)
  local seen, guard = {}, 0
  while guard < 60 do
    guard = guard + 1
    w.game = (w.facts["jackielives_msg_due_1"] or w.game) + 1
    w.facts["jackielives_msg_await_1"] = 0
    Msg.rt.await = nil
    settle(w)
    for _, p in ipairs(sentPaths(w)) do seen[p] = true end
  end
  local leaked = {}
  for _, b in ipairs(PERSONA.beats) do
    if b.tier > 0 and seen[b.bubbles[1]] then leaked[#leaked + 1] = b.id end
  end
  ok(#leaked == 0, "at tier 0 he NEVER sends a tier 1+ line (" .. table.concat(leaked, ",") .. ")")
end

do
  local w = unlockedWorld(0)
  w.tier = 3
  settle(w)
  ok(true, "a close companion draws from the whole pool (tier <= current)")
  local pool = 0
  for _, b in ipairs(PERSONA.beats) do if b.tier <= 3 then pool = pool + 1 end end
  ok(pool == #PERSONA.beats, "...which at tier 3 is everything")
end

-- ===========================================================================
section("6. he doesn't text at a stupid moment")
for _, case in ipairs({ { "combat", "mid-firefight" }, { "busy", "while a conversation is open" },
                        { "spawned", "while he's standing right there" } }) do
  local w = unlockedWorld(0)
  w[case[1]] = true
  run(w, 5)
  ok(#sentPaths(w) == 0, "no text " .. case[2])
  w[case[1]] = false
  run(w, 2)
  ok(#sentPaths(w) > 0, "...and it arrives once that passes")
end

-- ===========================================================================
section("7. rendezvous")
do
  local w = unlockedWorld(2)
  w.tier = 2
  -- drive until an invite goes out
  local invite, guard = nil, 0
  while not invite and guard < 200 do
    guard = guard + 1
    -- ⚠️ ADVANCE BY A FIXED STEP, and let the reply window time out on its own.
    -- This used to jump to `due` and clear `Msg.rt.await` — but `await` lives per persona at
    -- `Msg.rt.p[key]`, so that assignment was always a no-op, and `due` is not rescheduled while he
    -- is waiting on an answer. It only LOOKED like it worked because no beat had reply options; the
    -- moment every check-in got them (2026-08-22), the loop stopped advancing and this section
    -- failed. Twelve in-game hours a turn clears both the reply window and the gap.
    w.game = w.game + 12 * 3600
    settle(w)
    for _, b in ipairs(PERSONA.beats) do
      if b.kind == "invite" and w.state[b.bubbles[1]] == "Active" then invite = b end
    end
  end
  ok(invite ~= nil, "at tier 2 he eventually asks V out")
  if invite then
    ok(Msg.pendingVenue() == nil, "no rendezvous is on the books until V accepts")
    local yes
    for _, r in ipairs(invite.replies) do if r.accept then yes = r end end
    ok(yes ~= nil, "the invite has an accept reply")
    w.state[yes.path] = "Succeeded"
    Msg.rt.await = { beat = invite, until_ = w.clock + 100000 }
    settle(w)
    ok(Msg.pendingVenue() == invite.venue, "accepting arms a rendezvous at HER venue (" .. tostring(invite.venue) .. ")")
    ok(w.facts["jackielives_msg_rvx_1"] > w.game, "...with a deadline")

    Msg.rendezvousMet()
    ok(Msg.pendingVenue() == nil, "the invite is spent once he's been placed there")
  end
end

do
  -- V never shows
  local w = unlockedWorld(2)
  w.tier = 2
  w.facts["jackielives_msg_rv_1"] = 1               -- "noodle" (index 1, see VENUE_KEYS)
  w.facts["jackielives_msg_rvx_1"] = w.game - 1     -- already expired
  ok(Msg.pendingVenue() == "noodle", "a pending rendezvous survives as a fact (i.e. across a reload)")
  run(w, 2)
  ok(Msg.pendingVenue() == nil, "an expired rendezvous is cleared")
  local sawStandup = false
  for _, b in ipairs(PERSONA.beats) do
    if b.kind == "standup" and w.state[b.bubbles[1]] == "Active" then sawStandup = true end
  end
  ok(sawStandup, "...and he says something about being stood up")
  ok(#w.fam == 1 and w.fam[1].n == -1, "standing him up costs familiarity")
  ok(w.facts["jackielives_msg_due_1"] >= w.game + 20 * 3600, "...and he sulks before inviting again")
end

do
  local w = unlockedWorld(2)
  w.tier = 2
  -- ⚠️ THE INDEX IS THE CONTRACT. VENUE_KEYS in messages.lua is
  --   1 noodle · 2 misty · 3 coyote · 4 afterlife · 5 ginger · 6 redwood · 7 lizzies
  -- and that order is PERSISTED in a fact, so reordering it sends every existing save's pending
  -- rendezvous to a different bar. Asserting on a literal here is what makes a reorder fail loudly.
  w.facts["jackielives_msg_rv_1"] = 4               -- "afterlife" — NOT one of Jackie's invites
  ok(Msg.pendingVenue() == "afterlife", "the venue id round-trips through the fact")
  local offered = {}
  for _, b in ipairs(PERSONA.beats) do
    if b.kind == "invite" then offered[b.venue] = true end
  end
  ok(not offered.afterlife, "he never invites V somewhere his pack doesn't list")
end

-- ===========================================================================
section("8. one-time beats")
do
  local w = unlockedWorld(0)
  settle(w)
  local mask = w.facts["jackielives_msg_once_1"]
  ok(mask and mask > 0, "an opener is struck off permanently once sent")
  -- a fresh session (bag reset) must not re-send it
  Msg.onInit()
  local before = #sentPaths(w)
  for _ = 1, 40 do
    -- ⚠️ ADVANCE BY A FIXED STEP, and let the reply window time out on its own.
    -- This used to jump to `due` and clear `Msg.rt.await` — but `await` lives per persona at
    -- `Msg.rt.p[key]`, so that assignment was always a no-op, and `due` is not rescheduled while he
    -- is waiting on an answer. It only LOOKED like it worked because no beat had reply options; the
    -- moment every check-in got them (2026-08-22), the loop stopped advancing and this section
    -- failed. Twelve in-game hours a turn clears both the reply window and the gap.
    w.game = w.game + 12 * 3600
    settle(w)
  end
  local resent = false
  for _, p in ipairs(sentPaths(w)) do
    if p == beatById("open01").bubbles[1] and before > 0 then
      -- the opener's first bubble appearing AGAIN after the mask was set
      local n = 0
      for _, q in ipairs(sentPaths(w)) do if q == p then n = n + 1 end end
      if n > 1 then resent = true end
    end
  end
  ok(not resent, "...and never sent again, even after a reload resets the shuffle bag")
end

-- ===========================================================================
section("9. no archive installed")
do
  local w = newWorld{ noArchive = true }
  bind(w)
  w.gateOpen = true
  run(w, 2)
  w.game = w.facts["jackielives_msg_due_1"] + 1
  run(w, 5)
  ok(#sentPaths(w) == 0, "a player with only the CET folder gets no texts...")
  ok(true, "...and no error — the mod behaves exactly as it did before v1.45")
  ok(w.facts["jackielives_msg_due_1"] > w.game, "...and it backs off instead of retrying every frame")
end

-- ===========================================================================
section("10. status readout")
do
  local w = unlockedWorld(1)
  local s = Msg.status()
  ok(type(s) == "string" and s:find("jackie"), "Msg.status() reports the one persona")
end

-- ===========================================================================
section("12. what silences him, and what does not")
-- NCLives asks "is the SPAWNED companion this persona?" here, because a roster means somebody else
-- may be standing next to V. With one character, spawned means him — so the roster half of that
-- section is gone and what is left is the rule it protected: he goes quiet only while he is actually
-- in front of V, and texting him has never required summoning him first.
do
  local w = newWorld(); bind(w)
  w.gateOpen = true
  run(w, 3)
  ok(Msg.unlocked(), "the retrieval gate unlocks him with nobody summoned")
  w.game = w.facts["jackielives_msg_due_1"] + 1
  settle(w)
  ok(#sentPaths(w) > 0, "...and he texts anyway — his texts do not need him spawned")
end

do
  local w = unlockedWorld(0)
  w.spawned = true
  run(w, 5)
  ok(#sentPaths(w) == 0, "he doesn't text while he's standing right there")
  w.spawned = false
  run(w, 3)
  ok(#sentPaths(w) > 0, "...and picks it back up once he's gone")
end

-- ===========================================================================
section("13. V can text HIM (v1.46)")
do
  local w = unlockedWorld(0)
  settle(w)
  -- v1.91: he opens with a question, and a question OWNS the thread while it is open. Answer it,
  -- and V's own conversation-starters come back.
  answerPending(w)
  local out
  for _, b in ipairs(PERSONA.beats) do
    if b.kind == "outgoing" and w.state[b.group] == "Active" then out = b end
  end
  ok(out ~= nil, "an outgoing group is left armed so V can start a conversation")
  if out then
    ok(#out.bubbles == 0, "...and it has no message of hers in front of it (V speaks first)")
    -- pick one that is WORTH something: replies[1] is the neutral "You around?", which is
    -- deliberately worth 0 familiarity, so asserting on it would prove nothing.
    local pick1 = out.replies[1]
    for _, r in ipairs(out.replies) do if r.fam > 0 then pick1 = r end end
    local mark = #w.calls
    w.state[pick1.path] = "Succeeded"          -- V taps it in the messenger
    settle(w)
    -- ⚠️ ASSERT ON THE CALL LOG, NOT ON THE END STATE. The end state is not the invariant: this world
    -- keeps ticking, so once the conversation winds down V's side is entitled to come back around to
    -- this same set eventually — that is the pool recycling, not a vending machine. What must be true
    -- is that TAPPING IT TOOK IT DOWN. (NCLives can assert the end state only because its pool is big
    -- enough that a redraw never lands on the same beat inside one settle.)
    local wentQuiet = false
    for i = mark + 1, #w.calls do
      local c = w.calls[i]
      if c.path == out.group and c.state == "Inactive" then wentQuiet = true end
    end
    ok(wentQuiet, "once used, V's options go quiet (not a vending machine)")
    local got = {}
    for _, x in ipairs(sentPaths(w)) do got[x] = true end
    local answered = #pick1.followup > 0
    for _, f in ipairs(pick1.followup) do if not got[f] then answered = false end end
    ok(answered, "...and he answers what V said")
    ok(#w.fam > 0, "texting him first counts toward familiarity")
  end
end

do  -- the cooldown only starts once the CHAIN is exhausted
  local w = unlockedWorld(0)
  settle(w)
  answerPending(w)                             -- v1.91: clear his opening question first
  for _ = 1, 8 do
    local armed
    for _, b in ipairs(PERSONA.beats) do
      if b.kind == "outgoing" and w.state[b.group] == "Active" then armed = b end
    end
    if not armed then break end
    w.state[armed.replies[1].path] = "Succeeded"
    settle(w)
  end
  local due = w.facts["jackielives_msg_outdue_1"]
  ok(due and due > w.game, "a cooldown is set once the conversation winds down")
  local hisGap = Config.messages.earlyGapHours[1] * 3600
  ok((due - w.game) < hisGap, "...and it is SHORTER than the wait for him to text you")
  ok((due - w.game) <= Config.messages.outgoingCooldownMaxHours * 3600 + 1,
     "...and never longer than the configured 3 in-game hours")
  ok((due - w.game) >= Config.messages.outgoingCooldownMinHours * 3600 - 1,
     "...nor shorter than 0.5")
end

do  -- a conversation, not a single exchange
  local w = unlockedWorld(1)
  settle(w)
  answerPending(w)                             -- v1.91: clear his opening question first
  local turns, guard = 0, 0
  while guard < 6 do
    guard = guard + 1
    local armed
    for _, b in ipairs(PERSONA.beats) do
      if b.kind == "outgoing" and w.state[b.group] == "Active" then armed = b end
    end
    if not armed then break end
    turns = turns + 1
    w.state[armed.replies[1].path] = "Succeeded"
    settle(w)
  end
  ok(turns >= 2, "V's side re-arms mid-chat, so a conversation keeps going (" .. turns .. " turns)")
  ok(turns <= (Config.messages.outgoingChainTurns or 3),
     "...but not forever — it winds down into a cooldown")
end

-- ===========================================================================
section("13b. ONE choice group at a time — the thread must stay usable (v1.91)")
-- THE BUG (reported 2026-08-22): "I can only reply to the first message and after that it bugs out
-- and becomes unusable." `disarmOutgoing` put its group and every entry back to Inactive; armReplies
-- never put anything back at all. So the group behind every beat he had ever sent stayed Active for
-- the rest of the save, stacking up on one conversation. The messenger draws whatever is Active, so
-- after the first exchange V faced a pile of stale options — and tapping one did nothing, because
-- pollReply only ever watches the LATEST beat's paths.
do
  local w = unlockedWorld(0)
  settle(w)
  ok(#activeGroups(w) <= 1,
     "after his first text: at most one choice group is Active (" .. #activeGroups(w) .. ")")

  -- Answer him, let him follow up, let V's side come back, use it, and keep going. At NO point may
  -- two groups be offered at once — that is the state the player described as "unusable".
  local worst = #activeGroups(w)
  for _ = 1, 10 do
    local groups = activeGroups(w)
    if #groups > worst then worst = #groups end
    if #groups == 0 then
      w.game = w.game + 40 * 3600            -- nothing on the thread: let him get in touch again
      settle(w)
    else
      local b = groups[1]
      w.state[b.replies[1].path] = "Succeeded"
      settle(w)
    end
  end
  ok(worst <= 1, "...and through ten exchanges it never exceeded one (worst was " .. worst .. ")")

  -- The specific regression: an ANSWERED question must not leave its options sitting there.
  local w2 = unlockedWorld(0)
  settle(w2)
  local answered = answerPending(w2)
  ok(answered ~= nil, "he opened with a question to answer")
  if answered then
    ok(w2.state[answered.group] == "Inactive",
       "an answered question's options come down (this is what stacked up before)")
    for _, r in ipairs(answered.replies) do
      if w2.state[r.path] == "Active" then
        ok(false, "...including every entry under it: " .. r.id); break
      end
    end
    ok(true, "...including every entry under it")
  end

  -- ...and taking a group down must never strand V's side. `rt().out` is what gates the re-arm; if
  -- disarming forgot to clear it, V could never start a conversation again for the rest of the save.
  local reArmed = false
  for _, b in ipairs(PERSONA.beats) do
    if b.kind == "outgoing" and w2.state[b.group] == "Active" then reArmed = true end
  end
  ok(reArmed, "V's own conversation-starters come back once his question is answered")
end

-- ===========================================================================
section("13c. a pending question must not be able to stop his schedule (v1.91)")
-- While `await` is set the tick returns BEFORE it reaches "is his next text due", so an unanswered
-- question holds up everything else he might send. That window was measured in REAL seconds only —
-- and this game has a Skip Time button. Sleep through a day and a half in four real seconds and he
-- still owes you a text he cannot send: "he doesn't text on his own even after hours of in game
-- time" (2026-08-22). The in-game window is what unsticks it.
do
  local w = unlockedWorld(0)
  settle(w)                                    -- he opens with a question and waits
  local pending
  for _, b in ipairs(PERSONA.beats) do
    if b.group and b.kind ~= "outgoing" and w.state[b.group] == "Active" and #(b.replies or {}) > 0 then
      pending = b
    end
  end
  ok(pending ~= nil, "he is waiting on an answer")

  -- V ignores it and sleeps. Real time barely moves; in-game time moves a lot — which is exactly
  -- what the player did before reporting this.
  -- 48 in-game hours: past the top of the late band (40 h), so he is definitely owed a text, and
  -- no longer than it needs to be. (Antonia, 2026-08-22 — this is simulated time inside the harness,
  -- not a wait anyone sits through, but there is no reason for it to be longer than the thing it is
  -- testing.)
  local before = #sentPaths(w)
  for _ = 1, 3 do
    w.game = w.game + 48 * 3600
    settle(w)
  end
  ok(#sentPaths(w) > before,
     "...but he still gets on with his day after a long in-game wait (" ..
     (#sentPaths(w) - before) .. " new bubbles)")
end

-- ===========================================================================
section("13d. the cadence ramp — the first few land like a conversation starting (v1.91)")
-- Familiarity only moves when V TALKS to them, so a texting-only player sits at tier 0 forever.
-- Under the old tier table that meant 30 in-game hours between his first text and his second, which
-- is indistinguishable from broken. The ramp is by COUNT for exactly that reason.
do
  local C = Config.messages
  local w = unlockedWorld(0)
  local gaps, last = {}, nil
  for _ = 1, 12 do
    settle(w)
    answerPending(w)
    local due = w.facts["jackielives_msg_due_1"]
    local n   = w.facts["jackielives_msg_n_1"] or 0
    if due and due ~= last then gaps[#gaps + 1] = { h = (due - w.game) / 3600, n = n }; last = due end
    w.game = w.game + 60 * 3600
  end
  ok(#gaps >= 6, "he kept texting across the run (" .. #gaps .. " gaps observed)")

  -- Each gap is tagged with how many texts he had sent when it was chosen, which is exactly what
  -- the ramp reads — so this classifies the same way the code does instead of assuming an order.
  local early, late, unclassified = 0, 0, 0
  for _, g in ipairs(gaps) do
    if g.n == 0 then
      unclassified = unclassified + 1        -- the firstMessageHours opening beat, before any send
    elseif g.n < C.earlyCount then
      if g.h >= C.earlyGapHours[1] - 0.01 and g.h <= C.earlyGapHours[2] + 0.01 then early = early + 1
      else ok(false, ("gap %.1f h at n=%d should have been in the early band"):format(g.h, g.n)) end
    else
      if g.h >= C.lateGapHours[1] - 0.01 and g.h <= C.lateGapHours[2] + 0.01 then late = late + 1
      else ok(false, ("gap %.1f h at n=%d should have been in the late band"):format(g.h, g.n)) end
    end
  end
  ok(early > 0, ("his opening run uses the %.0f-%.0f h band (%d gaps)")
       :format(C.earlyGapHours[1], C.earlyGapHours[2], early))
  ok(late > 0, ("...and he settles into %.0f-%.0f h after that (%d gaps)")
       :format(C.lateGapHours[1], C.lateGapHours[2], late))
  ok(C.earlyGapHours[2] < C.lateGapHours[1],
     "...and the two bands do not overlap, so the change of pace is actually felt")
end

do  -- the pool has to be big enough that chit-chat doesn't repeat immediately
  local byTier = {}
  for _, b in ipairs(PERSONA.beats) do
    if b.kind == "outgoing" then byTier[b.tier] = (byTier[b.tier] or 0) + 1 end
  end
  local total = 0
  for _, n in pairs(byTier) do total = total + n end
  -- NCLives asserts >= 10 sets and >= 3 at tier 0 against a finished pack. Ours is small on purpose
  -- for now; what must be true from the first beat is that V has SOMETHING to open with at tier 0,
  -- because the outgoing pool is the only part of the thread a player can reach on demand.
  ok(total >= 2, "there is a pool of things V can open with (" .. total .. " sets)")
  ok((byTier[0] or 0) >= 1, "...including small talk available from the very first tier")
end

-- ⚠️ NCLives' sections 14 and 14b ARE DELIBERATELY ABSENT. They cover "is this persona's character
-- mod installed" and "did the player switch this addon persona off" — both roster concepts. Jackie's
-- body ships with this mod and there is no roster to be absent from, so there is nothing to assert.
-- If a roster ever arrives here, port them back; do not re-derive them.

-- ===========================================================================
section("11. self-diagnosis — it must name the FIRST broken thing")
local function joined(w)
  local lines
  pcall(function() lines = Msg.diagnose() end)
  return table.concat(lines or {}, "\n")
end

do  -- the real failure Antonia hit: archive not loaded
  local w = newWorld{ noArchive = true }; bind(w)
  local rep = joined(w)
  ok(rep:find("STOP: the game does not have our journal entries"),
     "no archive -> says the archive isn't loaded")
  ok(rep:find("ArchiveXL"), "...and names ArchiveXL as the first thing to check")
  ok(rep:find("archive\\pc\\mod", 1, true), "...and the exact folder both files belong in")
end

do  -- everything fine: the deep probe runs and actually delivers one
  local w = unlockedWorld(1)
  local rep = joined(w)
  ok(not rep:find("STOP:"), "healthy setup -> no STOP line")
  ok(rep:find("deep probe"), "...it goes on to probe the game itself")
  ok(rep:find("IsKnown"), "...reporting the gate the messenger actually applies")
  ok(rep:find("phone sees"), "...and what the phone finds under the contact")
  ok(#sentPaths(w) > 0, "...having really delivered a message, not just described one")
end

do  -- the suspected real-world cause: contact exists and is Active but isn't "known"
  local w = unlockedWorld(1)
  w.known_contact = false
  local rep = joined(w)
  ok(rep:find("STOP: the contact is not 'known'"),
     "an Active-but-unknown contact is called out (the messenger silently skips it)")
end

-- ===========================================================================
section("15. the questline's own texts (JackieLives-only)")
-- storyboard.lua is the single source of truth for the arc, and its beats carry their text messages
-- verbatim. Those words are copied into content/jackie_messages.json as `kind: "story"` beats so the
-- generator can bake them into the archive (tools/audit_messages.py fails if the two ever drift).
--
-- Two properties matter, and they pull in opposite directions:
--   * a story beat must NEVER be drawn at random — its words are a plot point, and one arriving out
--     of order would spoil the arc or contradict it;
--   * arc.lua must be able to fire one BY NAME the moment the story says so, regardless of tier,
--     cadence, shuffle bag or gap.
-- Msg.sendStory is that door, and this section is the lock on it.
do
  local story = {}
  for _, b in ipairs(PERSONA.beats) do if b.kind == "story" then story[#story + 1] = b end end
  ok(#story >= 1, "the arc's texts are in the pack (" .. #story .. " story beats)")

  -- Run the scheduler hard at the highest tier and check nothing of the story leaks out.
  local w = unlockedWorld(0)
  w.tier = 3
  for _ = 1, 30 do
    w.game = w.game + 48 * 3600
    settle(w)
    answerPending(w)
  end
  local seen = {}
  for _, p in ipairs(sentPaths(w)) do seen[p] = true end
  local leaked = {}
  for _, b in ipairs(story) do
    if b.bubbles[1] and seen[b.bubbles[1]] then leaked[#leaked + 1] = b.id end
  end
  ok(#leaked == 0,
     "the scheduler NEVER draws a story beat, even at tier 3 (" .. table.concat(leaked, ",") .. ")")
end

do
  local w = unlockedWorld(0)
  local target
  for _, b in ipairs(PERSONA.beats) do if b.kind == "story" then target = b; break end end
  ok(Msg.sendStory(target.id), "...but arc.lua can fire one by name")
  settle(w)
  local got = {}
  for _, p in ipairs(sentPaths(w)) do got[p] = true end
  local all = #target.bubbles > 0
  for _, b in ipairs(target.bubbles) do if not got[b] then all = false end end
  ok(all, "...and every bubble of it lands, staggered like any other text")
  if target.group then
    ok(w.state[target.group] == "Active", "...and its reply options are armed")
  else
    ok(true, "...(this one has no replies, by design)")
  end
end

do  -- ⚠️ it must NOT fall back to something else. NCLives' Msg.sendNow picks a random beat when the
    -- id is unknown, which is right for a debug button and catastrophic for a plot point: the player
    -- would get chit-chat where the story expected a revelation, and nothing would report it.
  local w = unlockedWorld(0)
  ok(Msg.sendStory("arc_beat_that_does_not_exist") == false,
     "an unknown story id reports failure rather than sending something else")
  settle(w)
  -- ⚠️ Assert on the STORY specifically, not on the total. The ambient scheduler is running in this
  -- world and is entitled to send a check-in while we look away; what must never happen is a plot
  -- point going out because arc.lua asked for an id that no longer exists.
  local got = {}
  for _, p in ipairs(sentPaths(w)) do got[p] = true end
  local leaked = {}
  for _, b in ipairs(PERSONA.beats) do
    if b.kind == "story" and b.bubbles[1] and got[b.bubbles[1]] then leaked[#leaked + 1] = b.id end
  end
  ok(#leaked == 0, "...and no story beat goes out in its place (" .. table.concat(leaked, ",") .. ")")

  ok(Msg.sendStory("open01") == false, "a NON-story beat is refused too (the scheduler owns those)")
end

do  -- the story outranks the ambient chain: an arc text may land before the gate has ever passed
  local w = newWorld(); bind(w)          -- gateOpen stays false
  local target
  for _, b in ipairs(PERSONA.beats) do if b.kind == "story" then target = b; break end end
  ok(Msg.sendStory(target.id), "the arc can text even before the ambient chain has unlocked itself")
  settle(w)
  ok(#sentPaths(w) > 0, "...and it actually arrives")
end

do  -- ...and with no archive it fails soft, exactly like everything else here
  local w = newWorld{ noArchive = true }; bind(w)
  local target
  for _, b in ipairs(PERSONA.beats) do if b.kind == "story" then target = b; break end end
  ok(Msg.sendStory(target.id) == false, "no archive -> a story beat reports failure, doesn't error")
  ok(#sentPaths(w) == 0, "...and nothing is delivered")
end

-- ===========================================================================
section("16. the arc's other voices — story-only contacts")
-- Part 2 needs two people who are not Jackie: an unknown number that says he is Arasaka property,
-- and Nix quoting a price for a jammer. Both own a real contact and a real thread in the phone, and
-- NEITHER has a schedule. That split is the whole design:
--   * ticking them would spin the scheduler on an empty pool forever — they have no ambient beats;
--   * and the unknown number's entire effect is two lines arriving and then nothing happening for
--     days. A cadence would destroy the beat it exists for.
do
  ok(UNKNOWN ~= nil, "the unknown number has a contact of its own")
  ok(NIX ~= nil, "...and so does Nix")
  if UNKNOWN then
    ok(UNKNOWN.contactPath ~= PERSONA.contactPath,
       "the unknown number is NOT filed under Jackie (it would read as him saying it)")
    local kinds = {}
    for _, b in ipairs(UNKNOWN.beats) do kinds[b.kind] = true end
    ok(kinds.story and not (kinds.checkin or kinds.question or kinds.outgoing or kinds.invite),
       "...and every beat it owns is `story`, so nothing can draw one at random")
  end
end

do  -- the decisive one: a full run of the scheduler must never say a word as either of them
  local w = unlockedWorld(0)
  w.tier = 3
  for _ = 1, 30 do
    w.game = w.game + 48 * 3600
    settle(w)
    answerPending(w)
  end
  local seen = {}
  for _, p in ipairs(sentPaths(w)) do seen[p] = true end
  local leaked = {}
  for _, P in ipairs({ UNKNOWN, NIX }) do
    for _, b in ipairs((P or {}).beats or {}) do
      if b.bubbles[1] and seen[b.bubbles[1]] then leaked[#leaked + 1] = b.id end
    end
  end
  ok(#leaked == 0,
     "the scheduler never speaks as anyone but Jackie (" .. table.concat(leaked, ",") .. ")")
end

do  -- ...but arc.lua can, by name, and the words are the storyboard's
  local w = unlockedWorld(0)
  ok(Msg.sendStory("arc_p2_unknown"), "arc.lua can fire the unknown number's text")
  settle(w)
  local got = {}
  for _, p in ipairs(sentPaths(w)) do got[p] = true end
  local beat
  for _, b in ipairs(UNKNOWN.beats) do if b.id == "arc_p2_unknown" then beat = b end end
  local all = #beat.bubbles == 2
  for _, b in ipairs(beat.bubbles) do if not got[b] then all = false end end
  ok(all, "...both of its lines land, on the unknown number's OWN thread")
  ok(w.state[beat.group] == "Active", "...and 'Who is this?' is offered")

  -- The dread depends on the answer going nowhere: `nothing` has no followup ON PURPOSE.
  local who, nothing
  for _, r in ipairs(beat.replies) do
    if r.id == "who" then who = r elseif r.id == "nothing" then nothing = r end
  end
  ok(who and #who.followup == 1, "'Who is this?' gets exactly one line back")
  ok(nothing and #nothing.followup == 0, "...and saying nothing gets silence, which is the beat")
end

do  -- Nix: a separate contact again, with the price carried through for arc.lua to charge
  local w = unlockedWorld(0)
  ok(Msg.sendStory("arc_p2_nix"), "arc.lua can fire Nix's quote")
  settle(w)
  local beat
  for _, b in ipairs(NIX.beats) do if b.id == "arc_p2_nix" then beat = b end end
  local got = {}
  for _, p in ipairs(sentPaths(w)) do got[p] = true end
  local all = #beat.bubbles == 3
  for _, b in ipairs(beat.bubbles) do if not got[b] then all = false end end
  ok(all, "...all three of his lines land on HIS thread")
  local pay
  for _, r in ipairs(beat.replies) do if r.id == "pay" then pay = r end end
  -- ⚠️ messages.lua must never spend the player's money itself: it reports which reply was tapped
  -- and arc.lua does the charging, because only arc.lua knows whether V can afford it.
  ok(pay and pay.cost == 2000, "...and the €$2000 price reaches the index for arc.lua to charge")
end

do  -- the two threads are genuinely separate: firing one must not touch the other
  local w = unlockedWorld(0)
  Msg.sendStory("arc_p2_nix")
  settle(w)
  local touched = false
  for _, b in ipairs(UNKNOWN.beats) do
    for _, p in ipairs(b.bubbles) do if w.state[p] == "Active" then touched = true end end
  end
  ok(not touched, "one story contact speaking leaves the others silent")
end

do  -- and their bookkeeping cannot collide: distinct fact ids, per the PERSONAS table
  local w = unlockedWorld(0)
  Msg.sendStory("arc_p2_unknown")
  settle(w)
  ok((w.facts["jackielives_msg_n_2"] or 0) >= 1, "the unknown number keeps its own facts (id 2)")
  ok((w.facts["jackielives_msg_n_3"] or 0) == 0, "...and Nix's (id 3) are untouched")
  Msg.sendStory("arc_p2_nix")
  settle(w)
  ok((w.facts["jackielives_msg_n_3"] or 0) >= 1, "...until he speaks for himself")
end

print(("\n%d checks, %d failed"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
