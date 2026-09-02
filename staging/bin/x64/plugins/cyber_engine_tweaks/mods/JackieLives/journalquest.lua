--[[
  journalquest.lua — REAL tracked quest objectives + readable shards          (v1.0)
  ============================================================================================
  Self-contained module, same shape as retrieval.lua: init.lua couples to it through
  `JQuest = require("journalquest")` and one `JQuest.bind{...}` call, and everything it needs
  from init.lua is OPTIONAL and injected. Nothing here reaches back into init.lua.

  WHAT THIS IS FOR
  ----------------
  Until now the mod's "objectives" were a text band drawn on screen by us. This module puts them
  in the GAME's top-right quest tracker — the real one, with the chime, the strikethrough when
  you finish a step, and an entry in the journal you can re-open later. Same for shards: a note
  Jackie leaves you lands in V's Shards tab and can be re-read for the rest of the save, instead
  of scrolling past once.

  HOW IT WORKS, IN ONE PARAGRAPH
  ------------------------------
  A quest is not code. It is DATA baked into the game's journal, and a mod can add its own
  branches to that data with ArchiveXL. `tools/gen_journal_quests.py` reads the story out of
  storyboard.lua/sidequests.lua and writes two things from the same run: the baked journal (built
  into the archive on Windows) and `journalquest_index.lua` (the paths, read by this file). At
  runtime all we do is tell the game "this entry is now Active / Succeeded" and "track that one".
  We never invent an entry — the archive already contains every one of them.

  THE FOUR FACTS THAT MAKE IT WORK  (each cost a session to establish — see
  docs/research/journal_quests_and_shards_spec.md for the citations)
  --------------------------------------------------------------------------------------------
  1. YOU TRACK AN OBJECTIVE, NEVER A QUEST. The HUD reads the tracked entry and casts it to a
     quest OBJECTIVE; hand it a quest and it silently draws nothing.
  2. QUEST, PHASE AND OBJECTIVE MUST ALL BE ACTIVE. The tracker walks the tree with an
     "active only" filter at every level, so a child of an inactive parent is invisible. Always
     activate parents first — that ordering is load-bearing, not tidiness.
  3. THE SETTER IS `TrackEntry`. There is no `SetTrackedEntry`; a plausible-looking name that
     does not exist fails silently under pcall and looks exactly like "the archive is missing".
  4. ENUMS CROSS INTO LUA AS PLAIN STRINGS — "Active", "Notify". `gameJournalEntryState.Active`
     is nil inside CET's sandbox, and nil is not an error here, it is a no-op.

  DEGRADATION — THE WHOLE POINT
  -----------------------------
  If the archive isn't installed (or ArchiveXL is missing, or the build is stale), every journal
  call here fails harmlessly and we fall back to the on-screen text band the mod uses today. A
  player without the archive gets exactly the mod they have now — never a broken one. Nothing in
  this file may ever be allowed to throw: every game call is wrapped.

  ⚠️ Never call any of this from the main menu. `Game.GetJournalManager()` is nil until a save is
  loaded, and `available()` is how you ask.
--]]

local M = {}

M.VERSION = "1.0"

-- The generated path table. Loaded defensively: a missing/broken index must degrade to "no
-- journal", not stop the mod from loading.
local Index = { quests = {}, questOrder = {}, shards = {}, shardOrder = {} }
do
  local ok, res = pcall(function() return require("journalquest_index") end)
  if ok and type(res) == "table" and res.quests then Index = res end
end
M.index = Index

-- Injected by init.lua via M.bind{}. ALL optional; every one has a safe default.
local deps = {
  log            = nil,   -- log(msg)
  showObjective  = nil,   -- showObjective(text, secs)  -> the on-screen band (fallback)
  showShard      = nil,   -- showShard(title, body)     -> the shard reader fallback
}

-- Runtime state. Deliberately NOT persisted: the journal itself is save state, and re-arming on
-- load is idempotent (re-activating an Active entry is a no-op).
local state = {
  current  = nil,     -- { quest=, phase=, objective= } — what we last pushed to the tracker
  started  = {},      -- questId -> true, so we only send the "quest updated" chime once
  warned   = false,   -- log the "no journal" verdict once per session, not once per beat
}

local function log(msg)
  if deps.log then pcall(function() deps.log("[JQuest] " .. tostring(msg)) end) end
end

-- ---------------------------------------------------------------------------
-- The three game calls, each wrapped so nothing here can ever throw
-- ---------------------------------------------------------------------------

local function jm()
  local m
  pcall(function() m = Game.GetJournalManager() end)
  return m
end

-- state:  "Inactive" | "Active" | "Succeeded" | "Failed"      (plain strings — see fact 4)
-- notify: "Notify" (chime + banner) | "DoNotNotify"
function M.set(path, class, st, notify)
  if not path then return false end
  local m = jm(); if not m then return false end
  local ok, res = pcall(function()
    return m:ChangeEntryState(path, class, st, notify or "DoNotNotify")
  end)
  return (ok and res) and true or false
end

function M.entry(path, class)
  if not path then return nil end
  local m = jm(); if not m then return nil end
  local e
  pcall(function() e = m:GetEntryByString(path, class) end)
  return e
end

-- Reads a state back for the log/probe. GetEntryState answers with the enum NAME on some CET
-- builds and its ORDINAL on others, so normalise — messages.lua in NCLives does the same.
local STATE_NAMES = { [0] = "Undefined", [1] = "Inactive", [2] = "Active",
                      [3] = "Succeeded", [4] = "Failed" }

function M.state(path, class)
  local m = jm(); if not m then return "no-journal-manager" end
  local e = M.entry(path, class); if not e then return "no-entry" end
  local s
  pcall(function() s = m:GetEntryState(e) end)
  if type(s) == "number" then return STATE_NAMES[s] or tostring(s) end
  return tostring(s)
end

-- ---------------------------------------------------------------------------
-- Lookups into the generated index
-- ---------------------------------------------------------------------------

-- Accepts a storyboard `journal = { quest=, phase=, objective=, text= }` block verbatim, so a
-- caller never has to know how a path is spelled.
local function resolve(j)
  if type(j) ~= "table" then return nil end
  local q = Index.quests[j.quest or ""]
  if not q then return nil end
  local ph = q.phases[j.phase or ""]
  if not ph then return nil, q end
  local o = ph.objectives[j.objective or ""]
  if not o then return nil, q, ph end
  return o, q, ph
end

function M.quest(id)   return Index.quests[id or ""] end
function M.shardInfo(id)
  if type(id) == "table" then id = id.id end
  return Index.shards[id or ""]
end

-- ---------------------------------------------------------------------------
-- Is the baked journal actually there?
-- ---------------------------------------------------------------------------
-- Asks the game for one entry we know we ship. A nil answer means the archive isn't installed,
-- ArchiveXL is missing, or the build is stale — all the same thing from here: use the fallback.
function M.available()
  if not jm() then return false end
  for _, qid in ipairs(Index.questOrder or {}) do
    if M.entry(Index.quests[qid].path, "gameJournalQuest") then return true end
  end
  for _, sid in ipairs(Index.shardOrder or {}) do
    if M.entry(Index.shards[sid].path, "gameJournalOnscreen") then return true end
  end
  if not state.warned then
    state.warned = true
    log("no journal entries found — archive not installed or stale. Falling back to the "
     .. "on-screen band; the mod behaves exactly as it did before this feature.")
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Quests
-- ---------------------------------------------------------------------------

-- Activate the quest and one of its phases. Parents FIRST, always (fact 2).
function M.startQuest(questId, phaseId)
  local q = Index.quests[questId or ""]
  if not q then return false end
  local first = not state.started[questId]
  -- "Notify" on the quest gives the player the real "new quest" banner, once.
  local ok = M.set(q.path, "gameJournalQuest", "Active", first and "Notify" or "DoNotNotify")
  if ok then state.started[questId] = true end
  local ph = q.phases[phaseId or (q.phaseOrder or {})[1] or ""]
  if ph then M.set(ph.path, "gameJournalQuestPhase", "Active", "DoNotNotify") end
  return ok
end

-- Put an objective in the top-right tracker. THE normal call: hand it the storyboard's own
-- `journal` block and it does the whole chain — quest, phase, objective, then track.
-- Returns true if the real tracker took it; false means the caller should show the band.
function M.objective(j, notify)
  local o, q, ph = resolve(j)
  if not o then
    if q then log("no objective for " .. tostring(j and j.quest) .. "/"
                  .. tostring(j and j.phase) .. "/" .. tostring(j and j.objective)
                  .. " — regenerate: python3 tools/gen_journal_quests.py") end
    return M.fallback(j)
  end
  if not M.available() then return M.fallback(j) end

  M.startQuest(q.id, ph.id)
  local ok = M.set(o.path, "gameJournalQuestObjective", "Active", notify or "Notify")
  if ok then
    state.current = { quest = q.id, phase = ph.id, objective = o.id }
    M.track(j)
  else
    log("could not activate " .. o.path)
    return M.fallback(j)
  end
  return true
end

-- Track the OBJECTIVE (fact 1). Separate from `objective` so a caller can re-point the tracker
-- at an already-active step without re-chiming it.
function M.track(j)
  local o = resolve(j); if not o then return false end
  local m = jm(); if not m then return false end
  local e = M.entry(o.path, "gameJournalQuestObjective")
  if not e then return false end
  local ok = pcall(function() m:TrackEntry(e) end)
  return ok
end

function M.untrack()
  local m = jm(); if not m then return false end
  return pcall(function() m:UntrackEntry() end)
end

-- Tick it off: strikethrough + chime, then it fades out of the tracker.
function M.succeed(j)
  local o = resolve(j); if not o then return false end
  if state.current and state.current.objective == o.id then state.current = nil end
  return M.set(o.path, "gameJournalQuestObjective", "Succeeded", "Notify")
end

function M.fail(j)
  local o = resolve(j); if not o then return false end
  if state.current and state.current.objective == o.id then state.current = nil end
  return M.set(o.path, "gameJournalQuestObjective", "Failed", "Notify")
end

-- Close a quest out: last objective, then its phase, then the quest. Order matters here too —
-- succeeding a parent while a child is still Active leaves a live line in the tracker.
function M.finishQuest(questId, lastJournalBlock)
  local q = Index.quests[questId or ""]
  if not q then return false end
  if lastJournalBlock then M.succeed(lastJournalBlock) end
  for _, pid in ipairs(q.phaseOrder or {}) do
    M.set(q.phases[pid].path, "gameJournalQuestPhase", "Succeeded", "DoNotNotify")
  end
  state.current = nil
  return M.set(q.path, "gameJournalQuest", "Succeeded", "Notify")
end

-- Re-apply after a save load. Journal states are save state, so this is belt-and-braces — but a
-- re-activation is a no-op, so running it on every onInit costs nothing and rescues a save that
-- was made between the quest starting and the archive being installed.
function M.rearm(j)
  j = j or state.current
  if not j then return false end
  return M.objective(j, "DoNotNotify")
end

-- The degradation path: our own on-screen band, exactly as before this module existed.
function M.fallback(j)
  local text = j and j.text
  if not text then
    local o = resolve(j)
    text = o and o.text
  end
  if text and deps.showObjective then
    pcall(function() deps.showObjective(text, 8.0) end)
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Shards
-- ---------------------------------------------------------------------------

-- Make a shard readable. Two halves, and only the first is essential:
--   1. flip the journal entry Active — this is literally all the game's own ReadAction does, and
--      it is what puts the note in V's Shards list;
--   2. put the physical item in the inventory too, so it looks like something V picked up.
-- Takes the storyboard's `shard = { id=, title=, body= }` block verbatim, or just an id.
function M.shard(s)
  local info = M.shardInfo(s)
  if not info then
    log("unknown shard " .. tostring(type(s) == "table" and s.id or s)
     .. " — regenerate: python3 tools/gen_journal_quests.py")
    return M.shardFallback(s)
  end
  if not M.available() then return M.shardFallback(s) end

  local ok = M.set(info.path, "gameJournalOnscreen", "Active", "Notify")
  if not ok then
    log("could not unlock shard " .. info.path)
    return M.shardFallback(s)
  end
  M.giveShardItem(info.id)
  return true
end

-- The inventory item. Optional: the shard is already readable without it. Needs the TweakXL YAML
-- deployed to r6\tweaks\JackieLives\, which is a loose file and may simply not be there.
function M.giveShardItem(id)
  local info = M.shardInfo(id); if not info then return false end
  local ts, p
  pcall(function() ts, p = Game.GetTransactionSystem(), Game.GetPlayer() end)
  if not (ts and p) then return false end
  local ok = pcall(function()
    local iid = ItemID.FromTDBID(TweakDBID.new(info.item))
    if ts:HasItem(p, iid) then return end
    ts:GiveItem(p, iid, 1)
  end)
  return ok
end

-- Has the player actually READ it?
-- ⚠️ Ask IsEntryVisited, never the state. An entry goes Active the moment the shard is PICKED UP,
-- so a state check calls it read for a player who pocketed it and read nothing.
function M.isShardRead(id)
  local info = M.shardInfo(id); if not info then return false end
  local m = jm(); if not m then return false end
  local e = M.entry(info.path, "gameJournalOnscreen"); if not e then return false end
  local v = false
  pcall(function() v = m:IsEntryVisited(e) end)
  return v and true or false
end

function M.shardFallback(s)
  local info = M.shardInfo(s)
  local title = (type(s) == "table" and s.title) or (info and info.title)
  local body  = (type(s) == "table" and s.body) or (info and info.body)
  if type(body) == "table" then body = table.concat(body, "\n") end
  if deps.showShard and (title or body) then
    pcall(function() deps.showShard(title, body) end)
  elseif deps.showObjective and title then
    pcall(function() deps.showObjective(title, 8.0) end)
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Probe — one button, one verdict line in jackie_debug.log
-- ---------------------------------------------------------------------------
-- See docs/research/journal_probe.md for how to run it and how to read the answer. It is written
-- to be safe on a real save: it activates the FIRST objective of the FIRST quest and nothing else.
function M.probe()
  local out = {}
  local function add(s) out[#out + 1] = s end

  if not jm() then
    local v = "JQuest probe: no journal manager (load a save first)"
    log(v); return v
  end

  local qid = (Index.questOrder or {})[1]
  local q = qid and Index.quests[qid]
  if not q then local v = "JQuest probe: index empty — run tools/gen_journal_quests.py"; log(v); return v end
  local pid = (q.phaseOrder or {})[1]
  local ph = pid and q.phases[pid]
  local oid = ph and (ph.objectiveOrder or {})[1]
  local o = oid and ph.objectives[oid]
  if not o then local v = "JQuest probe: quest " .. qid .. " has no objectives"; log(v); return v end

  add("archive=" .. tostring(M.available()))
  add("before: quest=" .. M.state(q.path, "gameJournalQuest")
      .. " phase=" .. M.state(ph.path, "gameJournalQuestPhase")
      .. " obj=" .. M.state(o.path, "gameJournalQuestObjective"))

  local j = { quest = qid, phase = pid, objective = oid, text = o.text }
  local pushed = M.objective(j, "Notify")

  local tracked, isObj = nil, false
  local m = jm()
  pcall(function() tracked = m:GetTrackedEntry() end)
  if tracked then
    pcall(function() isObj = (tracked:GetId() == oid) end)
  end

  add("after:  quest=" .. M.state(q.path, "gameJournalQuest")
      .. " phase=" .. M.state(ph.path, "gameJournalQuestPhase")
      .. " obj=" .. M.state(o.path, "gameJournalQuestObjective")
      .. " tracked=" .. tostring(tracked ~= nil)
      .. " trackedIsOurs=" .. tostring(isObj)
      .. " pushed=" .. tostring(pushed))

  local sid = (Index.shardOrder or {})[1]
  if sid then
    add("shard " .. sid .. "=" .. M.state(Index.shards[sid].path, "gameJournalOnscreen"))
  end

  local verdict = "JQuest probe [" .. qid .. "/" .. pid .. "/" .. oid .. "] "
               .. table.concat(out, " | ")
  log(verdict)
  return verdict
end

-- Undo what the probe did, so a real save isn't left carrying a test quest.
function M.probeReset()
  local qid = (Index.questOrder or {})[1]
  local q = qid and Index.quests[qid]
  if not q then return false end
  M.untrack()
  for _, pid in ipairs(q.phaseOrder or {}) do
    local ph = q.phases[pid]
    for _, oid in ipairs(ph.objectiveOrder or {}) do
      M.set(ph.objectives[oid].path, "gameJournalQuestObjective", "Inactive", "DoNotNotify")
    end
    M.set(ph.path, "gameJournalQuestPhase", "Inactive", "DoNotNotify")
  end
  state.current, state.started[qid] = nil, nil
  return M.set(q.path, "gameJournalQuest", "Inactive", "DoNotNotify")
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
-- Inject init.lua's helpers. ALL optional — an unbound helper just means that fallback is silent.
--   log(msg)                  the mod logger
--   showObjective(text, secs) the on-screen objective band (init.lua's showOnscreenMsg)
--   showShard(title, body)    a shard reader, if the mod ever grows one
function M.bind(opts)
  opts = opts or {}
  for _, k in ipairs({ "log", "showObjective", "showShard" }) do
    if opts[k] ~= nil then deps[k] = opts[k] end
  end
end

return M
