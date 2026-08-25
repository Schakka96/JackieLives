-- tools/test_journalquest.lua — unit tests for journalquest.lua (real quest objectives + shards).
--
-- Run from the repo root:   lua tools/test_journalquest.lua
-- Exits non-zero on failure. Needs only a stock Lua 5.x / LuaJIT (no game, no CET, no Windows).
--
-- This is NOT a copy of the logic: it `require`s the SHIPPED mod/JackieLives/journalquest.lua and
-- the GENERATED mod/JackieLives/journalquest_index.lua, and runs the real code against a stub
-- JournalManager that records every call in order. That ordering is the point — the four facts
-- this feature rests on are all about order and types, and all four fail SILENTLY in game:
--
--   1. YOU TRACK AN OBJECTIVE, NEVER A QUEST. The HUD casts the tracked entry to a quest
--      objective and draws nothing at all if it isn't one. A test that only checked "TrackEntry
--      was called" would pass while the tracker stayed empty.
--   2. PARENTS FIRST. The tracker walks the tree with an active-only filter at every level, so
--      activating an objective before its quest and phase produces an invisible objective and no
--      error. Hence the call-ORDER assertions below.
--   3. ENUMS CROSS AS PLAIN STRINGS. `gameJournalEntryState.Active` is nil inside CET's sandbox,
--      and passing nil is not an error, it is a no-op. So we assert the literal "Active".
--   4. `TrackEntry` IS THE SETTER — there is no SetTrackedEntry. A call to a method that doesn't
--      exist dies inside our own pcall and looks exactly like "the archive isn't installed".
--
-- It also pins the two things that make the feature safe to ship:
--   * NO JOURNAL -> the mod behaves as it did before. Every entry point must return false, must
--     not throw, and must fall through to the on-screen band.
--   * SOURCE PARITY. Every `journal = {...}` and `shard = {...}` block in the real storyboard
--     must resolve in the generated index, and every id must be present in the generated archive
--     source. This is the check that catches "someone edited the story and forgot to regenerate",
--     which in game shows up as one objective that silently never appears.

package.path = "mod/JackieLives/?.lua;" .. package.path

local fails, checks = 0, 0
local function ok(cond, msg)
  checks = checks + 1
  if not cond then fails = fails + 1; print("  FAIL: " .. msg) else print("  ok  : " .. msg) end
end
local function section(s) print("\n" .. s) end

-- ---------------------------------------------------------------- stub journal manager
-- Models only what the real one guarantees: entries exist for known paths, ChangeEntryState
-- returns true, GetEntryState reads back what was set, GetTrackedEntry remembers the handle.
local JM = {}
JM.__index = JM

local calls          -- ordered log of every game call: { "set", path, class, state, notify } etc.
local present        -- path -> class, "what the archive contains"
local states         -- path -> state string
local tracked        -- the entry handed to TrackEntry
local visited        -- path -> bool, for IsEntryVisited
local inventory      -- item id -> true
local noManager      -- when true, Game.GetJournalManager() returns nil

local function reset(withArchive)
  calls, states, tracked, visited, inventory = {}, {}, nil, {}, {}
  present, noManager = {}, false
  if withArchive ~= false then
    local Index = require("journalquest_index")
    for _, qid in ipairs(Index.questOrder) do
      local q = Index.quests[qid]
      present[q.path] = "gameJournalQuest"
      for _, pid in ipairs(q.phaseOrder) do
        local ph = q.phases[pid]
        present[ph.path] = "gameJournalQuestPhase"
        for _, oid in ipairs(ph.objectiveOrder) do
          present[ph.objectives[oid].path] = "gameJournalQuestObjective"
        end
      end
    end
    for _, sid in ipairs(Index.shardOrder) do
      present[Index.shards[sid].path] = "gameJournalOnscreen"
    end
  end
end

local manager = {
  ChangeEntryState = function(_, path, class, state, notify)
    calls[#calls + 1] = { "set", path, class, state, notify }
    if present[path] ~= class then return false end
    states[path] = state
    return true
  end,
  GetEntryByString = function(_, path, class)
    calls[#calls + 1] = { "get", path, class }
    if present[path] ~= class then return nil end
    return { path = path, class = class,
             GetId = function(self) return (self.path:match("([^/]+)$")) end }
  end,
  GetEntryState = function(_, e) return states[e.path] or "Inactive" end,
  TrackEntry = function(_, e) calls[#calls + 1] = { "track", e.path, e.class }; tracked = e end,
  GetTrackedEntry = function(_) return tracked end,
  UntrackEntry = function(_) calls[#calls + 1] = { "untrack" }; tracked = nil end,
  IsEntryVisited = function(_, e) return visited[e.path] == true end,
}

-- ---------------------------------------------------------------- stub CET / game API
Game = {
  GetJournalManager = function() return (not noManager) and manager or nil end,
  GetPlayer = function() return { player = true } end,
  GetTransactionSystem = function()
    return {
      HasItem = function(_, _, id) return inventory[id] == true end,
      GiveItem = function(_, _, id) calls[#calls + 1] = { "give", id }; inventory[id] = true end,
    }
  end,
}
TweakDBID = { new = function(s) return s end }
ItemID = { FromTDBID = function(t) return t end }

-- ---------------------------------------------------------------- helpers over the call log
local function kinds(kind)
  local out = {}
  for _, c in ipairs(calls) do if c[1] == kind then out[#out + 1] = c end end
  return out
end

local function indexOfSet(path)
  for i, c in ipairs(calls) do if c[1] == "set" and c[2] == path then return i end end
  return nil
end

local band = {}   -- what the fallback on-screen band was asked to show
local logged = {}

reset(true)
local JQ = require("journalquest")
JQ.bind{
  log = function(m) logged[#logged + 1] = m end,
  showObjective = function(text, secs) band[#band + 1] = { text = text, secs = secs } end,
}

local Index = require("journalquest_index")
local GHOST = { quest = "ghost", phase = "p1", objective = "take_jackie_to_vik",
                text = "Take Jackie to Vik" }

-- =============================================================================================
section("1. the generated index is well formed")

ok(#Index.questOrder > 0, "index has at least one quest")
ok(#Index.shardOrder > 0, "index has at least one shard")
local pathsOk, uniq = true, {}
for _, qid in ipairs(Index.questOrder) do
  local q = Index.quests[qid]
  if not q.path:match("^quests/[a-z_]+/" .. qid .. "$") then pathsOk = false end
  if uniq[q.path] then pathsOk = false end
  uniq[q.path] = true
  for _, pid in ipairs(q.phaseOrder) do
    local ph = q.phases[pid]
    if ph.path ~= q.path .. "/" .. pid then pathsOk = false end
    for _, oid in ipairs(ph.objectiveOrder) do
      local o = ph.objectives[oid]
      -- The uniquePath is the id chain with no leading slash — this is what the game parses.
      if o.path ~= ph.path .. "/" .. oid then pathsOk = false end
      if uniq[o.path] then pathsOk = false end
      uniq[o.path] = true
    end
  end
end
ok(pathsOk, "every path is its parent's path + '/' + its own id, and unique")

local shardPathsOk = true
for _, sid in ipairs(Index.shardOrder) do
  local s = Index.shards[sid]
  -- Shards are onscreens, not quests: a different shelf entirely.
  if s.path ~= "onscreens/emails/quests/minor_quest/jl_shards/shards/" .. sid then
    shardPathsOk = false
  end
  if not s.item:match("^Items%.") then shardPathsOk = false end
end
ok(shardPathsOk, "every shard sits under onscreens/…/jl_shards/shards and names an Items.* record")

-- =============================================================================================
section("2. pushing an objective — parents first, objective tracked (facts 1 and 2)")

reset(true)
local pushed = JQ.objective(GHOST)
ok(pushed == true, "objective() reports the real tracker took it")

local q, ph, o = Index.quests.ghost, Index.quests.ghost.phases.p1, nil
o = ph.objectives.take_jackie_to_vik
local iq, ip, io_ = indexOfSet(q.path), indexOfSet(ph.path), indexOfSet(o.path)
ok(iq and ip and io_, "quest, phase and objective were all activated")
ok(iq < ip and ip < io_, "...in that ORDER — a child of an inactive parent is invisible")
ok(states[q.path] == "Active" and states[ph.path] == "Active" and states[o.path] == "Active",
   "all three end up Active (the tracker filters on active at every level)")

local tr = kinds("track")
ok(#tr == 1, "TrackEntry was called exactly once")
ok(tr[1] and tr[1][3] == "gameJournalQuestObjective",
   "we track the OBJECTIVE, never the quest (the HUD casts it and gives up otherwise)")
ok(tracked and tracked.path == o.path, "the tracked handle is our objective")

-- =============================================================================================
section("3. enum arguments cross as plain strings (fact 3)")

local stringy = true
for _, c in ipairs(kinds("set")) do
  if type(c[4]) ~= "string" or type(c[5]) ~= "string" then stringy = false end
  if c[4] ~= "Active" and c[4] ~= "Succeeded" and c[4] ~= "Failed" and c[4] ~= "Inactive" then
    stringy = false
  end
  if c[5] ~= "Notify" and c[5] ~= "DoNotNotify" then stringy = false end
end
ok(stringy, "every state/notify argument is a literal string from the known set")

local notified = 0
for _, c in ipairs(kinds("set")) do if c[5] == "Notify" then notified = notified + 1 end end
ok(notified == 2, "exactly two chimes: the new quest and the new objective (not the phase)")

reset(true)
JQ.objective(GHOST, "DoNotNotify")
local quiet = true
for _, c in ipairs(kinds("set")) do if c[5] == "Notify" and c[2] ~= q.path then quiet = false end end
ok(quiet, "a DoNotNotify push does not chime the objective (used by the re-arm on load)")

-- =============================================================================================
section("4. succeeding, failing and finishing")

reset(true)
JQ.objective(GHOST)
JQ.succeed(GHOST)
ok(states[o.path] == "Succeeded", "succeed() strikes the objective through")

reset(true)
JQ.objective(GHOST)
JQ.fail(GHOST)
ok(states[o.path] == "Failed", "fail() marks it failed")

reset(true)
JQ.objective(GHOST)
JQ.finishQuest("ghost", GHOST)
ok(states[o.path] == "Succeeded", "finishQuest closes the last objective")
ok(states[q.path] == "Succeeded", "...and the quest")
local allPhases = true
for _, pid in ipairs(q.phaseOrder) do
  if states[q.phases[pid].path] ~= "Succeeded" then allPhases = false end
end
ok(allPhases, "...and every phase, so no phase is left Active with a live line in the tracker")
-- Order again: a parent that succeeds while a child is still Active leaves the line on screen.
local lastObj, questDone = 0, 0
for i, c in ipairs(calls) do
  if c[1] == "set" and c[3] == "gameJournalQuestObjective" then lastObj = i end
  if c[1] == "set" and c[2] == q.path and c[4] == "Succeeded" then questDone = i end
end
ok(lastObj > 0 and questDone > lastObj, "the quest is closed AFTER its children, never before")

-- =============================================================================================
section("5. no journal (no archive installed) — the mod must behave exactly as before")

reset(false)          -- archive present = false: GetEntryByString answers nil for everything
band = {}
local res = JQ.objective(GHOST)
ok(res == false, "objective() reports it did NOT reach the tracker")
ok(#band == 1 and band[1].text == "Take Jackie to Vik",
   "...and the on-screen band shows the storyboard's own wording instead")

noManager = true
band = {}
res = JQ.objective(GHOST)
ok(res == false and #band == 1, "with no JournalManager at all (main menu) it still degrades")
ok(JQ.state("anything", "gameJournalQuest") == "no-journal-manager",
   "state() says so rather than throwing")
ok(select(1, pcall(JQ.probe)) == true, "probe() survives having no journal manager")
noManager = false

reset(true)
band = {}
ok(JQ.objective{ quest = "no_such_quest", phase = "x", objective = "y", text = "Do a thing" }
   == false, "an unknown quest is refused, not invented")
ok(#band == 1 and band[1].text == "Do a thing", "...and still degrades to the band")
ok(JQ.shard("no_such_shard") == false, "an unknown shard is refused")
ok(select(1, pcall(JQ.objective, nil)) == true, "a nil journal block does not throw")
ok(select(1, pcall(JQ.shard, nil)) == true, "a nil shard block does not throw")

-- =============================================================================================
section("6. shards")

reset(true)
local sid = Index.shardOrder[1]
local s = Index.shards[sid]
ok(JQ.shard{ id = sid } == true, "shard() unlocks a known shard")
ok(states[s.path] == "Active", "...by flipping the onscreen entry Active — all ReadAction does")
local given = kinds("give")
ok(#given == 1 and given[1][2] == s.item, "...and puts the matching item in V's inventory")

JQ.shard{ id = sid }
ok(#kinds("give") == 1, "giving it twice does not duplicate the item")

-- ⚠️ The trap: an entry goes Active when the shard is PICKED UP. Reading state instead of asking
-- IsEntryVisited would call it read for a player who pocketed it and read nothing.
ok(JQ.isShardRead(sid) == false, "an Active-but-unvisited shard does NOT count as read")
visited[s.path] = true
ok(JQ.isShardRead(sid) == true, "IsEntryVisited is what says it was read")

-- =============================================================================================
section("7. source parity — the storyboard, the index and the archive agree")

-- Load the REAL story files and walk every beat, exactly as the generator does.
local sb = require("storyboard")
local sq = require("sidequests")

local missingJ, missingS, wrongText, nBeats, nShards = {}, {}, {}, 0, 0
local function visit(beats)
  for _, b in ipairs(beats or {}) do
    if b.journal then
      nBeats = nBeats + 1
      local qq = Index.quests[b.journal.quest]
      local pp = qq and qq.phases[b.journal.phase]
      local oo = pp and pp.objectives[b.journal.objective]
      if not oo then
        missingJ[#missingJ + 1] = ("%s (%s/%s/%s)"):format(b.id, b.journal.quest,
                                    b.journal.phase, b.journal.objective)
      elseif oo.text ~= (b.journal.text or "") then
        wrongText[#wrongText + 1] = b.id
      end
    end
    if b.shard then
      nShards = nShards + 1
      local ss = Index.shards[b.shard.id]
      if not ss then missingS[#missingS + 1] = b.shard.id
      else
        local body = b.shard.body
        if type(body) == "table" then body = table.concat(body, "\n") end
        if ss.body ~= body or ss.title ~= b.shard.title then
          wrongText[#wrongText + 1] = "shard " .. b.shard.id
        end
      end
    end
  end
end
for _, part in ipairs(sb.arc.parts or {}) do visit(part.beats) end
for _, quest in ipairs(sq.quests or {}) do visit(quest.beats) end

ok(nBeats > 0 and nShards > 0, ("the storyboard declares %d objectives and %d shards")
   :format(nBeats, nShards))
ok(#missingJ == 0, "every journal block resolves in the index: " .. table.concat(missingJ, ", "))
ok(#missingS == 0, "every shard resolves in the index: " .. table.concat(missingS, ", "))
ok(#wrongText == 0,
   "the index carries the storyboard's wording VERBATIM (stale? re-run "
   .. "tools/gen_journal_quests.py): " .. table.concat(wrongText, ", "))

-- The archive source is written by the same generator run, so a mismatch here means somebody
-- hand-edited one side. Cheap text check: every id must appear as an "id" in the CR2W-JSON.
local f = io.open("archive/source/mod/jackielives/journal/jackielives_quests.journal.json", "r")
ok(f ~= nil, "the generated archive source exists")
if f then
  local json = f:read("*a"); f:close()
  local absent = {}
  local function need(id)
    if not json:find('"id": "' .. id .. '"', 1, true) then absent[#absent + 1] = id end
  end
  for _, qid in ipairs(Index.questOrder) do
    need(qid)
    for _, pid in ipairs(Index.quests[qid].phaseOrder) do
      need(pid)
      for _, oid in ipairs(Index.quests[qid].phases[pid].objectiveOrder) do need(oid) end
    end
  end
  for _, x in ipairs(Index.shardOrder) do need(x) end
  ok(#absent == 0, "every id in the index is a node in the archive source: "
     .. table.concat(absent, ", "))
  -- LocKeys must be namespaced. An FNV-1a64 hash of a bare English phrase can collide with a
  -- base-game localization entry, which crashes the game — BowieKnife99 shipped that once.
  local bare = json:match('"value": "([^"]*)"')
  ok(bare ~= nil and bare:match("^jl_"), "localization keys are namespaced with jl_ (" ..
     tostring(bare) .. ")")
  -- A quest with no `type` presents as a MAIN quest in the HUD.
  local typed = true
  for _ in json:gmatch('"%$type": "gameJournalQuest"') do
    typed = typed and json:find('"type": "', 1, true) ~= nil
  end
  ok(typed, "quests declare a type (omit it and the HUD styles them as MAIN quests)")
end

-- =============================================================================================
section("8. probe + reset")

reset(true)
local verdict = JQ.probe()
ok(type(verdict) == "string" and verdict:find("tracked=true", 1, true) ~= nil,
   "probe() reports a tracked entry when the archive is present")
ok(verdict:find("trackedIsOurs=true", 1, true) ~= nil,
   "...and confirms the tracked entry is OURS, not whatever quest the player had running")
ok(JQ.probeReset() ~= false, "probeReset() puts the test quest back to Inactive")
local firstQ = Index.quests[Index.questOrder[1]]
ok(states[firstQ.path] == "Inactive", "...so a real save isn't left carrying it")

-- =============================================================================================
print(("\n%d checks, %d failed"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
