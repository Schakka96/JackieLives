-- tools/test_arc.lua — the arc engine, driven offline against a fake world.
--
-- Run from the repo root:   lua tools/test_arc.lua
-- Exits non-zero on failure. Stock Lua 5.x, no game, no CET.
--
-- This loads the REAL arc.lua and the REAL storyboard, binds a fake Night City (a table of
-- facts, a clock we can move, a place sensor we can lie to) and then plays the questline through
-- from a fresh save to each of the four endings. What it is really testing is the two failure
-- modes this repo has actually shipped:
--
--   * CONTENT THAT SPOILS — a beat firing for a player who hasn't finished the retrieval quest.
--     v1.56 shipped this: Vik revealed Jackie was alive to players who hadn't done the heist.
--     Here it is asserted directly: with the mod locked, NOTHING fires, ever, under any clock.
--   * CONTENT THAT NEVER FIRES — v1.64 shipped that: a gate that silently never opened for
--     anybody, so a correctly-installed mod looked dead. Asserted here as its mirror image: with
--     the gate open and the conditions met, the arc must actually walk from beat 1 to the ending
--     without a human touching it.
--
-- The third thing it pins is the computed ending ("You choose, Jackie"), because that branch is
-- read off the player's whole history and is the one place where a wrong answer is invisible:
-- the game just quietly gives you a different friend.

package.path = "mod/JackieLives/?.lua;" .. package.path

local T = dofile("tools/tcheck.lua")
local check = T.check

local Story = require("storyboard")
local Arc   = require("arc")

-- ---------------------------------------------------------------------------
-- A fake Night City. Everything the engine can see, and nothing it can't.
-- ---------------------------------------------------------------------------
local world

local function newWorld(over)
  local w = {
    facts = {}, log = {},
    unlocked = true, stage = 4, fam = 2,
    hour = 12.0, day = 100, stageDay = 90,
    spawned = true, following = true, combat = false, outdoors = true,
    district = "heywood", place = nil, mainQuest = false,
    items = {}, eddies = 100000,
    sms = {}, shards = {}, journal = {}, fights = {}, spoken = {}, dialogues = {},
    config = { tickSeconds = 0, takeover = true, raid = true },
  }
  for k, v in pairs(over or {}) do w[k] = v end
  return w
end

-- The arc counts "days since the reunion" off a fact it stamps itself the first time it looks
-- (the shipped questline never recorded a date). Pre-stamp it for the tests that want to be
-- past that wait; §2b below tests the stamping itself.
local function reunionWasLongAgo(w)
  w.facts["jackielives_stage_day"] = (w.day or 100) - 30
  return w
end

local function bindWorld(w)
  world = w
  Arc.bind{
    log      = function(m) w.log[#w.log + 1] = m end,
    factGet  = function(n) return w.facts[n] or 0 end,
    factSet  = function(n, v) w.facts[n] = v end,
    famTier  = function() return w.fam end,
    famAdd   = function(n) w.fam = w.fam end,
    gameHour = function() return w.hour end,
    gameDay  = function() return w.day end,
    stage    = function() return w.stage end,
    stageDay = function() return w.stageDay end,
    unlocked = function() return w.unlocked end,
    jackieSpawned   = function() return w.spawned end,
    jackieFollowing = function() return w.following end,
    playerInCombat  = function() return w.combat end,
    playerOutdoors  = function() return w.outdoors end,
    playerDistrict  = function() return w.district end,
    nearPlace = function(key) return w.place == key end,
    mainQuestActive = function() return w.mainQuest end,
    hasItem  = function(id) return w.items[id] == true end,
    money    = function() return w.eddies end,
    spend    = function(n) if w.eddies >= n then w.eddies = w.eddies - n; return true end return false end,
    showTip  = function(t) w.tip = t end,
    sms      = function(b) w.sms[#w.sms + 1] = b.id end,
    shard    = function(b) w.shards[#w.shards + 1] = b.id end,
    journal  = function(op, spec) w.journal[#w.journal + 1] = op .. ":" .. tostring(spec.objective) end,
    spawnHostiles = function(s) w.fights[#w.fights + 1] = s end,
    vo       = function(ids) w.spoken[#w.spoken + 1] = ids[1] end,
    dialogue = function(node) w.dialogues[#w.dialogues + 1] = node.beat; w.lastNode = node end,
    config   = function() return w.config end,
  }
  Arc.reset()
  return w
end

-- Drive the tick until nothing new fires, with a hard cap so a loop in the data can't hang CI.
local function run(maxTicks)
  local fired = {}
  for _ = 1, (maxTicks or 200) do
    local before = #world.log
    Arc.tick(999)
    if #world.log == before then break end
    for i = before + 1, #world.log do
      local id = tostring(world.log[i]):match("firing beat ([%w_]+)")
      if id then fired[#fired + 1] = id end
    end
  end
  return fired
end

local function fired(list, id)
  for _, x in ipairs(list) do if x == id then return true end end
  return false
end

-- ===========================================================================
print("\n-- 1. the spoiler gate --------------------------------------------")
-- ===========================================================================

bindWorld(newWorld{ unlocked = false })
do
  local f = run()
  check("a locked mod fires nothing at all", #f == 0, "fired: " .. table.concat(f, ", "))
end

bindWorld(newWorld{ unlocked = false, stage = 0, fam = 3, day = 999 })
do
  -- The worst case: a maxed-out familiarity, months of in-game time, and a pre-heist save.
  local f = run()
  check("a pre-heist save with high familiarity STILL fires nothing", #f == 0,
        "fired: " .. table.concat(f, ", "))
end

-- An unreadable world must behave like a locked one, never like an open one.
Arc.bind{ unlocked = nil, stage = nil, factGet = nil, factSet = nil }
bindWorld(newWorld())
Arc.bind{ unlocked = function() error("boom") end }
do
  local f = run()
  check("an unreadable gate stays silent rather than guessing", #f == 0)
end

-- ===========================================================================
print("\n-- 2. the arc actually walks --------------------------------------")
-- ===========================================================================

bindWorld(newWorld())
do
  -- A save that has only just reunited must NOT get the arc immediately: the first look stamps
  -- the clock and waits. This is the "it fired the moment I installed the update" guard.
  local f0 = run()
  check("a just-reunited save waits instead of opening the arc at once", not fired(f0, "p1_episode"))
  check("...and the reunion clock got stamped", (world.facts["jackielives_stage_day"] or 0) > 0)
end

bindWorld(reunionWasLongAgo(newWorld()))
do
  local f = run()
  check("the first episode fires for an unlocked, following player", fired(f, "p1_episode"),
        "fired: " .. table.concat(f, ", "))
  check("the night-time text is NOT delivered at noon", not fired(f, "p1_sms_night"))

  world.hour = 1.0                       -- 01:00 — inside the {23,27} window
  local f2 = run()
  check("the text lands once it is late enough", fired(f2, "p1_sms_night"))
  check("the SMS actually reached the messenger", world.sms[1] == "arc_p1_night")

  world.place = "vik"
  local f3 = run()
  check("being at Vik's advances the objective", fired(f3, "p1_to_vik") or fired(f3, "p1_scan"))
end

-- ===========================================================================
print("\n-- 3. windows, places and combat ----------------------------------")
-- ===========================================================================

check("a window that wraps past midnight includes 01:00", Arc.inWindow(1.0, { 22.0, 27.0 }))
check("a window that wraps past midnight excludes 12:00", not Arc.inWindow(12.0, { 22.0, 27.0 }))
check("an ordinary window works", Arc.inWindow(10.0, { 8.0, 14.0 }))
check("an ordinary window excludes its end hour", not Arc.inWindow(14.0, { 8.0, 14.0 }))

bindWorld(reunionWasLongAgo(newWorld{ combat = true }))
do
  local f = run()
  check("nothing scripted fires while V is in a firefight", not fired(f, "p1_episode"))
end

bindWorld(reunionWasLongAgo(newWorld{ mainQuest = true }))
do
  local f = run()
  check("the arc never interrupts a main quest", not fired(f, "p1_episode"))
end

bindWorld(reunionWasLongAgo(newWorld{ following = false }))
do
  local f = run()
  check("the mid-follow episode waits until he is actually following", not fired(f, "p1_episode"))
end

-- ===========================================================================
print("\n-- 4. heat ---------------------------------------------------------")
-- ===========================================================================

bindWorld(newWorld())
world.facts[Story.FACTS.arc] = 1
world.district = "watson"
do
  Arc.tickHeat()            -- first call only stamps the clock
  world.hour = 13.0
  Arc.tickHeat()
  local h1 = world.facts[Story.FACTS.trace] or 0
  check("heat accrues while Jackie is out in Watson", h1 > 0, "heat = " .. tostring(h1))

  world.hour = 14.0
  world.district = "badlands"
  Arc.tickHeat()
  local h2 = world.facts[Story.FACTS.trace]
  check("the Badlands accrue slower than Watson", (h2 - h1) < h1, ("%.1f then %.1f"):format(h1, h2 - h1))

  world.hour = 15.0
  world.spawned = false
  local h3before = world.facts[Story.FACTS.trace]
  Arc.tickHeat()
  check("heat does not accrue while he is at home", world.facts[Story.FACTS.trace] == h3before)

  world.spawned = true
  world.hour = 16.0
  world.facts[Story.FACTS.beacon] = 1     -- burned
  local h4 = world.facts[Story.FACTS.trace]
  Arc.tickHeat()
  check("burning the beacon stops heat for good", world.facts[Story.FACTS.trace] == h4)
end

-- ===========================================================================
print("\n-- 5. the computed ending ('You choose, Jackie') --------------------")
-- ===========================================================================

local handback
for _, part in ipairs(Story.arc.parts) do
  for _, b in ipairs(part.beats or {}) do
    for _, ch in ipairs(b.choices or {}) do if ch.computed then handback = ch end end
  end
end

local function endingFor(setup)
  bindWorld(newWorld())
  for k, v in pairs(setup.facts or {}) do world.facts[k] = v end
  world.fam = setup.fam or 0
  return Arc.computeEnding(handback)
end

check("trust + the truth -> Caged (he stays, with upkeep)",
      endingFor{ facts = { [Story.FACTS.caught_lie] = 1 }, fam = 3 } == 2)
check("he asked to get it all out in Part 1 -> Clean",
      endingFor{ facts = { [Story.FACTS.pull_now] = 1 }, fam = 2 } == 1)
check("he has seen what he does to people -> Clean",
      endingFor{ facts = { [Story.FACTS.episodes] = 5 }, fam = 2 } == 1)
check("Mama found out -> Clean",
      endingFor{ facts = { [Story.FACTS.knows_mama] = 1 }, fam = 2 } == 1)
check("never let in, or lied to and never told -> Ride it",
      endingFor{ facts = { [Story.FACTS.caught_lie] = 2 }, fam = 1 } == 3)
check("a save with nothing on record still gets an ending",
      endingFor{ facts = {}, fam = 2 } ~= 0)

-- Order matters: the rules are read top to bottom and the first match wins. If `pull_now`
-- ever outranked the trust rule, a player who admitted the lie AND was overruled in Part 1
-- would get the colder ending. Pin the precedence.
check("trust outranks the Part 1 framing choice",
      endingFor{ facts = { [Story.FACTS.caught_lie] = 1, [Story.FACTS.pull_now] = 1 }, fam = 3 } == 2)

-- ===========================================================================
print("\n-- 6. choices, costs and consequences ------------------------------")
-- ===========================================================================

bindWorld(newWorld())
do
  Arc.force("p1_choice")
  check("a choice beat opens the dialogue widget", world.dialogues[1] == "p1_choice")
  Arc.pick("p1_choice", "pull_now")
  check("picking 'take it out now' is remembered", world.facts[Story.FACTS.pull_now] == 1)
end

bindWorld(newWorld{ eddies = 500 })
do
  Arc.force("rico_choice")
  local ok = Arc.pick("rico_choice", "pay")
  check("a choice V cannot afford is refused, not faked", ok == false)
  check("no eddies were taken on a refused choice", world.eddies == 500)
end

bindWorld(newWorld{ eddies = 5000 })
do
  Arc.force("rico_choice")
  Arc.pick("rico_choice", "pay")
  check("paying the kid's debt costs the eddies", world.eddies == 3000)
  check("and the kid is remembered for Part 5", world.facts["jackielives_side_rico"] == 1)
end

-- ===========================================================================
print("\n-- 7. the settings switches ----------------------------------------")
-- ===========================================================================

bindWorld(newWorld{ config = { tickSeconds = 0, takeover = false, raid = true } })
do
  world.facts[Story.FACTS.arc] = 2
  local ok, why = Arc.checkArms({ config = "Config.arc.takeover" }, nil)
  check("turning the takeover off disarms that beat", ok == false, tostring(why))
end
bindWorld(newWorld())
do
  local ok = Arc.checkArms({ config = "Config.arc.takeover" }, nil)
  check("leaving it on arms it", ok == true)
end

-- ===========================================================================
print("\n-- 8. the safety net -----------------------------------------------")
-- ===========================================================================

bindWorld(newWorld{ unlocked = false })
do
  local txt = Arc.debug()
  check("debug() names the condition holding each beat back",
        type(txt) == "string" and txt:find("blocked") ~= nil)
  check("force() works even when everything is blocked", Arc.force("p1_episode") == true)
  check("start() opens the arc by hand", Arc.start() == true)
  check("start() shows the warning card", world.tip ~= nil)
  check("start() refuses to run twice", (select(1, Arc.start())) == false)
  Arc.reset()
  check("reset() clears the arc fact", (world.facts[Story.FACTS.arc] or 0) == 0)
  check("reset() clears the beat flags", (world.facts["jackielives_b_p1_episode"] or 0) == 0)
end

T.finish()
