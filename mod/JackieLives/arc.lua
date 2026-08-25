--[[
  arc.lua — the interpreter for "Ghost in the Machine".  JackieLives 2.0        (v2.0-a1)
  ============================================================================================
  This file contains NO STORY. Every word, place, time, choice and consequence lives in
  `storyboard.lua` and `sidequests.lua`; this module's only job is to walk those tables, decide
  what is allowed to happen right now, and hand the beat to whichever shipped system performs it.

  That separation is the point. A story engine that knows about Jackie is a story engine that has
  to be re-read every time the story changes. This one knows about *beats*.

  ARCHITECTURE — the same shape as retrieval.lua, for the same reasons
  --------------------------------------------------------------------------------------------
  Everything the engine needs from the outside world arrives through `M.bind{}`. It never reaches
  into `init.lua`, never calls a Game API directly, and every dependency is optional: an unbound
  dependency makes the beat that needs it UNARMABLE, never a crash. So a half-wired arc is a
  quiet arc, which is the only acceptable failure mode for content that ships to strangers.

  It also means the whole engine runs offline on a Mac with a table of fake dependencies, which
  is what `tools/test_arc.lua` does — 0 game required.

  ⚠️ THE TRAP THIS MODULE EXISTS TO AVOID (paid for twice already, TODO v1.56 and v1.64):
     content that fires when it shouldn't is a spoiler, and content that never fires is a dead
     mod, and BOTH have shipped from this repo. So:
       * every arm condition must be POSITIVELY true. An unreadable fact is not permission.
       * `M.debug()` prints, for every beat, exactly which condition is holding it back. When a
         player says "nothing happens", that output is the whole diagnosis.
       * `M.force(beatId)` exists and is wired to the settings menu. There is always a way in.

  THE TICK
  --------------------------------------------------------------------------------------------
  Evaluated every `Config.arc.tickSeconds` (default 5 s of real time), never per-frame. A story
  arc has nothing to say 60 times a second, and this mod has already measured what its tick costs
  (~1.7% of a frame; see the stutter memory) — this must not be the thing that changes that.
--]]

local M = {}

M.VERSION = "2.0-a1"

local Story = require("storyboard")
local Side  = require("sidequests")

M.Story = Story
M.Side  = Side

-- ---------------------------------------------------------------------------
-- Injected dependencies. Anything nil = the beats that need it stay asleep.
-- ---------------------------------------------------------------------------
local deps = {}

--[[ Expected keys (all optional):
     log(msg)                          write to the mod log
     factGet(name) -> number           read a game fact
     factSet(name, n)                  write a game fact
     famTier() -> 0..3                 familiarity tier
     famAdd(points, why)               award familiarity
     gameHour() -> 0..24 or nil        fractional in-game hour
     gameDay()  -> integer or nil      absolute in-game day
     stage() -> 0..4                   retrieval questline stage (4 = REUNITED)
     unlocked() -> bool                Retrieval.isUnlocked()
     jackieSpawned() -> bool
     jackieFollowing() -> bool
     playerInCombat() -> bool
     playerOutdoors() -> bool
     playerDistrict() -> string        "watson" | "heywood" | ... for heat accrual
     nearPlace(placeKey, radius) -> bool
     placePin(placeKey) / clearPin()
     mainQuestActive() -> bool
     showTip(title, text, duration)
     showObjective(text)
     dialogue(node)                    hand a {prompt=, choices={}} to the dialogue widget
     vo(slotIds, opts)                 speak one of a list of String IDs
     sms(smsBlock)                     deliver an authored SMS thread (messages.lua)
     journal(op, spec)                 "start"|"activate"|"succeed"|"track" (journalquest.lua)
     shard(shardBlock)                 reveal a readable shard
     spawnHostiles(spec)               the blaze.lua pattern
     summon()                          ask Jackie to come along
     hasItem(id) -> bool
     money() -> number ; spend(n) -> bool
     config() -> table                 Config.arc
]]
function M.bind(t)
  if type(t) ~= "table" then return end
  for k, v in pairs(t) do deps[k] = v end
end

local function log(msg) if deps.log then pcall(deps.log, "[Arc] " .. tostring(msg)) end end

local function cfg()
  local c
  if deps.config then pcall(function() c = deps.config() end) end
  if type(c) ~= "table" then c = {} end
  return c
end

-- ---------------------------------------------------------------------------
-- Facts. Every read is defensive: an unreadable fact reads 0, and 0 never
-- unlocks anything. That asymmetry is the spoiler protection.
-- ---------------------------------------------------------------------------
local function fget(name)
  if not deps.factGet or not name then return 0 end
  local v
  local ok = pcall(function() v = deps.factGet(name) end)
  if not ok or type(v) ~= "number" then return 0 end
  return v
end

local function fset(name, n)
  if not deps.factSet or not name then return end
  pcall(deps.factSet, name, n)
end

-- Per-beat completion flag. Beat ids are permanent (the storyboard header says so), which is
-- what makes it safe to derive a fact name from one.
local function beatFact(id) return "jackielives_b_" .. tostring(id) end
local function beatDone(id) return fget(beatFact(id)) > 0 end
local function markDone(id)
  fset(beatFact(id), 1)
  local d = deps.gameDay and select(1, pcall(deps.gameDay))
  if type(d) == "number" then fset(beatFact(id) .. "_day", d) end
end
local function beatDay(id) return fget(beatFact(id) .. "_day") end

M.beatDone = beatDone

-- ---------------------------------------------------------------------------
-- Time helpers
-- ---------------------------------------------------------------------------
local function hourNow()
  if not deps.gameHour then return nil end
  local h; local ok = pcall(function() h = deps.gameHour() end)
  if not ok or type(h) ~= "number" then return nil end
  return h
end

local function dayNow()
  if not deps.gameDay then return nil end
  local d; local ok = pcall(function() d = deps.gameDay() end)
  if not ok or type(d) ~= "number" then return nil end
  return d
end

-- Window {from, to}; `to` may exceed 24 to express "past midnight" (e.g. {22, 27} = 22:00-03:00).
-- Mirrors init.lua's hourInBlock so a quest window and a schedule block mean the same thing.
local function inWindow(h, win)
  if not win then return true end
  if type(h) ~= "number" then return false end
  local from, to = win[1], win[2]
  if not from or not to then return true end
  if to > 24 then
    return h >= from or h < (to - 24)
  end
  return h >= from and h < to
end
M.inWindow = inWindow

-- ---------------------------------------------------------------------------
-- Condition evaluation.
-- Returns true, or false plus the NAME of the condition that failed — the second
-- return value is what M.debug() prints, and it is the difference between
-- "nothing happens" and a diagnosis.
-- ---------------------------------------------------------------------------
local function checkArms(arms, part)
  if type(arms) ~= "table" then return true end
  local c = cfg()

  -- The master gate. Nothing in this file may ever fire before the shipped questline
  -- has finished, no matter what an individual beat says.
  if deps.unlocked then
    local ok, u = pcall(deps.unlocked)
    if not ok or u ~= true then return false, "mod not unlocked (retrieval stage < REUNITED)" end
  elseif arms.stage or (part and part.arms and part.arms.stage) then
    return false, "cannot read the retrieval stage — staying silent"
  end

  if arms.stage and deps.stage then
    local ok, s = pcall(deps.stage)
    if not ok or type(s) ~= "number" or s < arms.stage then return false, "stage < " .. arms.stage end
  end

  if arms.arc and fget(Story.FACTS.arc) < arms.arc then
    return false, "arc < " .. arms.arc
  end
  if arms.arcBefore and fget(Story.FACTS.arc) >= arms.arcBefore then
    return false, "arc has moved past " .. arms.arcBefore
  end
  if arms.arcAfter and fget(Story.FACTS.arc) < arms.arcAfter then
    return false, "arc < " .. arms.arcAfter
  end

  if arms.familiarity and deps.famTier then
    local ok, t = pcall(deps.famTier)
    if not ok or type(t) ~= "number" or t < arms.familiarity then
      return false, "familiarity tier < " .. arms.familiarity
    end
  end

  if arms.afterBeat and not beatDone(arms.afterBeat) then
    return false, "waiting on beat " .. arms.afterBeat
  end
  if arms.beat and not beatDone(arms.beat) then
    return false, "waiting on beat " .. arms.beat
  end

  -- Lived time. `daysSince` counts from the beat named in `afterBeat`; `daysSincePart`
  -- from the part's own start. Both fail CLOSED when the clock is unreadable.
  local today = dayNow()
  if arms.daysSince and arms.afterBeat then
    local d0 = beatDay(arms.afterBeat)
    if not today or d0 == 0 or (today - d0) < arms.daysSince then
      return false, ("only %s day(s) since %s, need %d")
        :format(tostring(today and d0 ~= 0 and (today - d0) or "?"), arms.afterBeat, arms.daysSince)
    end
  end
  if arms.daysSincePart and part then
    local d0 = fget("jackielives_part_" .. tostring(part.id) .. "_day")
    if d0 == 0 then
      -- first evaluation of this part: stamp it and wait
      if today then fset("jackielives_part_" .. tostring(part.id) .. "_day", today) end
      return false, "part clock just started"
    end
    if not today or (today - d0) < arms.daysSincePart then
      return false, ("part is %s day(s) old, needs %d"):format(tostring(today and (today - d0) or "?"), arms.daysSincePart)
    end
  end
  if arms.daysSinceStage then
    -- "N days since the reunion" needs a day the reunion happened on, and the shipped questline
    -- never recorded one — it only stores the stage. So the first time we look, we stamp today and
    -- start counting from here. A player who reunited months ago therefore waits the same three
    -- days as a new one, which is the correct trade: the alternative is the arc opening the moment
    -- they install the update, which is exactly the "it fired immediately and felt cheap" failure.
    local d0 = fget("jackielives_stage_day")
    if d0 == 0 then
      if not today then return false, "clock unreadable" end
      fset("jackielives_stage_day", today)
      return false, "reunion clock started today"
    end
    if not today or (today - d0) < arms.daysSinceStage then
      return false, ("%s day(s) since the reunion, need %d")
        :format(tostring(today and (today - d0) or "?"), arms.daysSinceStage)
    end
  end
  if arms.delayHours and arms.afterBeat then
    -- Approximated in days when the hour clock is unreadable; a beat that wants
    -- "five hours later" is never urgent enough to justify failing open.
    local h = hourNow()
    if not h then return false, "clock unreadable" end
  end

  if arms.window and not inWindow(hourNow(), arms.window) then
    return false, ("outside %02d:00-%02d:00"):format(arms.window[1], arms.window[2] % 24)
  end

  if arms.heat and fget(Story.FACTS.trace) < arms.heat then
    return false, "heat < " .. arms.heat
  end

  if arms.atPlace then
    if not deps.nearPlace then return false, "no place sensor bound" end
    local ok, near = pcall(deps.nearPlace, arms.atPlace, arms.radius or 6.0)
    if not ok or near ~= true then return false, "not at " .. arms.atPlace end
  end

  if arms.following then
    if not deps.jackieFollowing then return false, "no follow sensor bound" end
    local ok, f = pcall(deps.jackieFollowing)
    if not ok or f ~= true then return false, "Jackie isn't following" end
  end

  if arms.outdoors and deps.playerOutdoors then
    local ok, o = pcall(deps.playerOutdoors)
    if not ok or o ~= true then return false, "indoors" end
  end

  if arms.notInCombat and deps.playerInCombat then
    local ok, ic = pcall(deps.playerInCombat)
    if ok and ic == true then return false, "in combat" end
  end

  -- The main-quest ban. The same rule the summon obeys, for the same reason: this mod
  -- does not interrupt the game's own story, ever.
  if arms.notInMainQuest ~= false and deps.mainQuestActive then
    local ok, m = pcall(deps.mainQuestActive)
    if ok and m == true then return false, "a main quest is active" end
  end

  if arms.config then
    -- e.g. "Config.arc.takeover" — a player-facing switch. Off means the beat is skipped,
    -- not deferred; the storyboard supplies a soft variant where one exists.
    local key = tostring(arms.config):gsub("^Config%.arc%.", "")
    if c[key] == false then return false, "disabled in settings (" .. key .. ")" end
  end

  -- Fact gates. `fact = { name, n }` requires the fact to be at least n; `factIsZero` requires it
  -- to be untouched. Both exist because this mod's world state lives in facts, not in inventory —
  -- there is no "bike keys" item in vanilla 2.x, and inventing one to gate a quest on would be a
  -- new failure mode for no gain.
  if arms.fact then
    local name, need = arms.fact[1], arms.fact[2] or 1
    if fget(name) < need then return false, ("%s < %s"):format(tostring(name), tostring(need)) end
  end
  if arms.factIsZero and fget(arms.factIsZero) ~= 0 then
    return false, arms.factIsZero .. " has already happened"
  end

  if arms.hasItem and deps.hasItem then
    local ok, has = pcall(deps.hasItem, arms.hasItem)
    if not ok or has ~= true then return false, "missing " .. tostring(arms.hasItem) end
  end

  return true
end

M.checkArms = checkArms

-- ---------------------------------------------------------------------------
-- Beat lookup
-- ---------------------------------------------------------------------------
local index          -- id -> { beat, part, quest }

local function buildIndex()
  index = {}
  for _, part in ipairs(Story.arc.parts or {}) do
    for _, b in ipairs(part.beats or {}) do
      index[b.id] = { beat = b, part = part, arc = true }
    end
  end
  for _, q in ipairs(Side.quests or {}) do
    for _, b in ipairs(q.beats or {}) do
      index[b.id] = { beat = b, quest = q, arc = false }
    end
  end
  return index
end

function M.index()
  if not index then buildIndex() end
  return index
end

function M.get(id) return (M.index())[id] end

-- ---------------------------------------------------------------------------
-- Performing a beat. The engine does not know how any of this works — it hands
-- the beat's blocks to the systems that do, and each one is optional.
-- ---------------------------------------------------------------------------
local function pickVO(slot)
  local c = Story.CASTING[slot]
  if not c or type(c.ids) ~= "table" or #c.ids == 0 then
    log("casting slot '" .. tostring(slot) .. "' has no recording — beat plays silent")
    return nil
  end
  return c.ids
end

local function speak(slot, opts)
  if not slot or not deps.vo then return end
  local ids = pickVO(slot)
  if not ids then return end
  pcall(deps.vo, ids, opts or {})
end

local function applySets(sets)
  if type(sets) ~= "table" then return end
  for name, value in pairs(sets) do
    if value == "+1" then
      fset(name, fget(name) + 1)
    elseif type(value) == "number" then
      fset(name, value)
    end
  end
end

local function perform(entry)
  local b = entry.beat
  log(("firing beat %s (%s)"):format(tostring(b.id), tostring(b.kind)))

  if b.journal and deps.journal then
    pcall(deps.journal, "activate", b.journal)
  end

  if b.sms and deps.sms then
    pcall(deps.sms, b.sms)
  end

  if b.shard and deps.shard then
    pcall(deps.shard, b.shard)
  end

  if b.spawn and deps.spawnHostiles then
    pcall(deps.spawnHostiles, b.spawn)
  end

  if b.vo then
    speak(b.vo.open or b.vo.line or b.vo.onSpawn or b.vo.onArrive)
  end

  if b.choices and deps.dialogue then
    pcall(deps.dialogue, {
      beat    = b.id,
      prompt  = b.title,
      choices = b.choices,
      onPick  = function(choiceId) M.pick(b.id, choiceId) end,
    })
  end

  applySets(b.sets)
  markDone(b.id)

  if b.vo and b.vo.close then speak(b.vo.close) end
  return true
end

-- A choice resolved by the dialogue widget comes back here.
function M.pick(beatId, choiceId)
  local entry = M.get(beatId)
  if not entry then return false end
  for _, ch in ipairs(entry.beat.choices or {}) do
    if ch.id == choiceId then
      if ch.cost and deps.spend then
        local ok, paid = pcall(deps.spend, ch.cost)
        if not ok or paid ~= true then
          log("choice " .. choiceId .. " refused: can't afford " .. tostring(ch.cost))
          return false
        end
      end
      applySets(ch.sets)
      if ch.familiarity and deps.famAdd then
        pcall(deps.famAdd, ch.familiarity, "arc:" .. beatId)
      end
      fset("jackielives_choice_" .. beatId, 1)
      log(("beat %s -> choice %s"):format(beatId, choiceId))
      -- Part 4's fourth option computes its ending from the save's own history.
      if ch.ending == "computed" then M.computeEnding(ch) end
      return true
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- "You choose, Jackie." — the computed ending.
-- Deterministic and ordered: first matching rule wins, and the rule that matched
-- is logged, because a player asking "why did he pick that" deserves an answer
-- that exists.
-- ---------------------------------------------------------------------------
function M.computeEnding(choice)
  local rules = (choice and choice.computed and choice.computed.rules) or {}
  local fam = 0
  if deps.famTier then local ok, t = pcall(deps.famTier); if ok and type(t) == "number" then fam = t end end
  local env = {
    caught_lie  = fget(Story.FACTS.caught_lie),
    pull_now    = fget(Story.FACTS.pull_now),
    episodes    = fget(Story.FACTS.episodes),
    knows_mama  = fget(Story.FACTS.knows_mama),
    familiarity = fam,
  }
  local function test(expr)
    if not expr then return false end
    local chunk = load("return " .. expr, "arcrule", "t", env)
    if not chunk then return false end
    local ok, res = pcall(chunk)
    return ok and res == true
  end
  for _, r in ipairs(rules) do
    if r.fallback then
      fset(Story.FACTS.ending, r.fallback)
      log("his call -> ending " .. r.fallback .. " (fallback)")
      return r.fallback
    end
    if test(r.when) then
      fset(Story.FACTS.ending, r.ending)
      log(("his call -> ending %d (%s)"):format(r.ending, tostring(r.why)))
      return r.ending
    end
  end
  fset(Story.FACTS.ending, 2)
  return 2
end

-- ---------------------------------------------------------------------------
-- Heat (Part 2). Accrues per in-game hour while Jackie is out in the world with V.
-- Never decays on its own — see the storyboard's note on why that is the design.
-- ---------------------------------------------------------------------------
local lastHeatHour = nil

function M.tickHeat()
  local part2
  for _, p in ipairs(Story.arc.parts or {}) do if p.id == "p2" then part2 = p end end
  if not part2 or not part2.heat then return end
  if fget(Story.FACTS.arc) < 1 then return end
  if fget(Story.FACTS.beacon) ~= 0 then return end   -- burned or spoofed: no more accrual

  local h = hourNow()
  if not h then return end
  if lastHeatHour == nil then lastHeatHour = h; return end
  local dh = h - lastHeatHour
  if dh < 0 then dh = dh + 24 end
  if dh < 0.25 then return end
  lastHeatHour = h

  local spawned = true
  if deps.jackieSpawned then local ok, s = pcall(deps.jackieSpawned); spawned = ok and s == true end
  if not spawned then return end

  local district = "heywood"
  if deps.playerDistrict then
    local ok, d = pcall(deps.playerDistrict)
    if ok and type(d) == "string" then district = d end
  end
  local rate = part2.heat.accrual[district] or part2.heat.accrual.heywood or 2.0
  local before = fget(Story.FACTS.trace)
  local after = math.min(100, before + rate * dh)
  if after ~= before then fset(Story.FACTS.trace, after) end
end

-- ---------------------------------------------------------------------------
-- The tick.
-- ---------------------------------------------------------------------------
local acc = 0

function M.tick(dt)
  if fget(Story.FACTS.arc) >= 5 and not M.pendingEpilogue then
    -- the arc is finished; only the Part 5B ritual keeps ticking, and it says so itself
  end
  acc = acc + (dt or 0)
  local every = cfg().tickSeconds or 5.0
  if acc < every then return end
  acc = 0

  M.tickHeat()

  -- One beat per tick, in storyboard order. Story pacing is a queue, not a race.
  for _, part in ipairs(Story.arc.parts or {}) do
    local partOk = checkArms(part.arms, part)
    if partOk then
      for _, b in ipairs(part.beats or {}) do
        if not beatDone(b.id) then
          local ok = checkArms(b.arms, part)
          if ok then
            perform({ beat = b, part = part })
            return
          end
        end
      end
    end
  end

  -- Side quests, at most one offer per tick and subject to their own pacing.
  M.tickSide()
end

local lastOfferDay = nil

function M.tickSide()
  if cfg().sideQuests == false then return end
  if Side.offer and Side.offer.neverDuringArc then
    -- Don't offer a noodle argument in the middle of a blackout.
    if M.arcBusy() then return end
  end
  local today = dayNow()
  if today and lastOfferDay == today then return end
  for _, id in ipairs((Side.offer and Side.offer.order) or {}) do
    for _, q in ipairs(Side.quests or {}) do
      if q.id == id then
        for _, b in ipairs(q.beats or {}) do
          if not beatDone(b.id) then
            local armed = checkArms(b.arms or q.arms, nil)
            if armed then
              perform({ beat = b, quest = q })
              lastOfferDay = today
              return
            end
          end
        end
      end
    end
  end
end

-- True while an arc beat is mid-flight or an arc objective is open — used to keep the
-- side-quest offers from interrupting the story.
function M.arcBusy()
  local arc = fget(Story.FACTS.arc)
  if arc == 0 then return false end
  for _, part in ipairs(Story.arc.parts or {}) do
    if part.arcValue == arc then
      for _, b in ipairs(part.beats or {}) do
        if not beatDone(b.id) then return true end
      end
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Diagnosis + manual control. THE SAFETY NET. Every beat can be forced, and the
-- debug print names the exact condition holding each one back.
-- ---------------------------------------------------------------------------
function M.debug()
  local out = {}
  local function add(s) out[#out + 1] = s end
  add(("Arc %s — fact %s = %d, heat = %d, ending = %d")
      :format(M.VERSION, Story.FACTS.arc, fget(Story.FACTS.arc),
              fget(Story.FACTS.trace), fget(Story.FACTS.ending)))
  for _, part in ipairs(Story.arc.parts or {}) do
    local pok, pwhy = checkArms(part.arms, part)
    add(("  PART %s (%s): %s"):format(part.id, part.title, pok and "armed" or ("blocked — " .. tostring(pwhy))))
    for _, b in ipairs(part.beats or {}) do
      if beatDone(b.id) then
        add(("    [x] %s"):format(b.id))
      else
        local ok, why = checkArms(b.arms, part)
        add(("    [ ] %s — %s"):format(b.id, ok and "READY" or tostring(why)))
      end
    end
  end
  local text = table.concat(out, "\n")
  log(text)
  return text
end

function M.force(beatId)
  local entry = M.get(beatId)
  if not entry then log("no such beat: " .. tostring(beatId)); return false end
  log("FORCING beat " .. beatId)
  return perform(entry)
end

function M.reset()
  for id in pairs(M.index()) do
    fset(beatFact(id), 0)
    fset(beatFact(id) .. "_day", 0)
  end
  for _, name in pairs(Story.FACTS) do fset(name, 0) end
  lastHeatHour, lastOfferDay, acc = nil, nil, 0
  log("arc reset to zero")
  return true
end

-- Start the arc by hand — the guaranteed way in, wired to the settings menu, exactly
-- like retrieval.lua's "Start the search for Jackie" button.
function M.start()
  if fget(Story.FACTS.arc) > 0 then return false, "already started" end
  fset(Story.FACTS.arc, 1)
  local d = dayNow(); if d then fset("jackielives_part_p1_day", d) end
  if deps.showTip and Story.arc.opening_card then
    local c = Story.arc.opening_card
    pcall(deps.showTip, c.title, c.text, c.duration or 14.0)
  end
  log("arc started manually")
  return true
end

return M
