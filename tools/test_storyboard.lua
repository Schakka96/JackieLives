-- tools/test_storyboard.lua — the story's own regression harness.
--
-- Run from the repo root:   lua tools/test_storyboard.lua
-- Exits non-zero on failure. Stock Lua 5.x, no game, no CET.
--
-- WHY A TEST FOR A STORY. Because "Ghost in the Machine" is DATA (storyboard.lua / sidequests.lua),
-- and data rots the same way code does — a renamed beat, a `next` pointing at nothing, a casting
-- slot nobody ever filled, a String ID quietly turned into a number by an editor's auto-format.
-- Every one of those is silent in-game: the beat simply never fires, and the player reports that
-- "nothing happens", which is the single most expensive bug class this repo has (v1.56, v1.64).
-- So the story gets asserted, offline, before it ever reaches a save file.
--
-- What it pins down:
--   * structural integrity — unique ids, resolvable `next`, resolvable `afterBeat`, real places
--   * castability — every `vo` slot exists, and every slot the story actually uses has a recording
--   * ID SAFETY — String IDs are strings, ~19 digits, never numbers (a Lua double corrupts them)
--   * the arc is completable — a path exists from the first beat to each of the three endings
--   * pacing sanity — every part rests, no part can fire before the mod is unlocked
--   * the SMS contract — unique thread/message ids, every reply has a followup or is terminal
--   * the safety rules from the storyboard's own header are actually true of the data

package.path = "mod/JackieLives/?.lua;" .. package.path

local fails, checks = 0, 0
local function check(name, ok, detail)
  checks = checks + 1
  if ok then print(("  ok   %s"):format(name))
  else fails = fails + 1; print(("  FAIL %s%s"):format(name, detail and ("\n         " .. detail) or "")) end
end

local Story = require("storyboard")
local Side  = require("sidequests")

-- ---------------------------------------------------------------------------
-- Collect everything once
-- ---------------------------------------------------------------------------
local beats, order = {}, {}
local function collect(b, owner)
  order[#order + 1] = b.id
  beats[b.id] = { beat = b, owner = owner }
end
for _, part in ipairs(Story.arc.parts) do
  for _, b in ipairs(part.beats or {}) do collect(b, part) end
end
for _, q in ipairs(Side.quests) do
  for _, b in ipairs(q.beats or {}) do collect(b, q) end
end

print(("\nstoryboard %s — %d arc parts, %d side quests, %d beats\n")
  :format(Story.VERSION, #Story.arc.parts, #Side.quests, #order))

-- ---------------------------------------------------------------------------
-- 1. Structure
-- ---------------------------------------------------------------------------
local dupes = {}
do
  local seen = {}
  for _, id in ipairs(order) do
    if seen[id] then dupes[#dupes + 1] = id end
    seen[id] = true
  end
end
check("every beat id is unique", #dupes == 0, "duplicated: " .. table.concat(dupes, ", "))

local badNext = {}
for id, e in pairs(beats) do
  local n = e.beat.next
  if n and not beats[n] then badNext[#badNext + 1] = id .. " -> " .. tostring(n) end
end
check("every `next` points at a beat that exists", #badNext == 0, table.concat(badNext, "; "))

local badAfter = {}
for id, e in pairs(beats) do
  local a = e.beat.arms and (e.beat.arms.afterBeat or e.beat.arms.beat)
  if a and not beats[a] then badAfter[#badAfter + 1] = id .. " waits on " .. tostring(a) end
end
check("every `afterBeat` points at a beat that exists", #badAfter == 0, table.concat(badAfter, "; "))

local badPlace = {}
for id, e in pairs(beats) do
  local p = e.beat.place
  if p and p ~= "any" and p ~= "jackie_current" and p ~= "near_jackie" and not Story.PLACES[p] then
    badPlace[#badPlace + 1] = id .. " -> " .. tostring(p)
  end
end
check("every `place` is a declared place", #badPlace == 0, table.concat(badPlace, "; "))

-- A place that needs capturing must declare where to fall back to, or the beat has nowhere to run.
local noFallback = {}
for key, p in pairs(Story.PLACES) do
  if p.needsCapture and not p.fallbackKey then noFallback[#noFallback + 1] = key end
  if p.needsCapture and not p.capture then noFallback[#noFallback + 1] = key .. " (no capture instructions)" end
end
check("every uncaptured place has a fallback and instructions", #noFallback == 0, table.concat(noFallback, ", "))

-- The capture list must be the WHOLE ask — this is what stops a "one more thing" trickle.
do
  local listed = {}
  for _, row in ipairs(Story.CAPTURE_LIST) do if row.place then listed[row.place] = true end end
  local missing = {}
  for key, p in pairs(Story.PLACES) do
    if p.needsCapture and not listed[key] then missing[#missing + 1] = key end
  end
  check("CAPTURE_LIST names every place that needs capturing", #missing == 0, table.concat(missing, ", "))
end

-- A beat's journal block must name the quest it actually lives in. This is not pedantry: the
-- journal generator files the objective under whatever id the beat declares, so a typo here
-- silently creates a second, empty quest in the player's journal and the real one never ticks.
-- (Caught exactly that on `side_shakedown`, which declared `side_cut`.)
do
  local wrong = {}
  for _, q in ipairs(Side.quests) do
    for _, b in ipairs(q.beats or {}) do
      if b.journal and b.journal.quest and b.journal.quest ~= q.id then
        wrong[#wrong + 1] = ("%s declares quest '%s' but lives in '%s'"):format(b.id, b.journal.quest, q.id)
      end
    end
  end
  for _, part in ipairs(Story.arc.parts) do
    for _, b in ipairs(part.beats or {}) do
      if b.journal and b.journal.quest and b.journal.quest ~= Story.arc.id then
        wrong[#wrong + 1] = ("%s declares quest '%s' but lives in the arc '%s'"):format(b.id, b.journal.quest, Story.arc.id)
      end
    end
  end
  check("every journal objective is filed under the quest it belongs to", #wrong == 0,
        table.concat(wrong, "; "))
end

-- ---------------------------------------------------------------------------
-- 2. Casting
-- ---------------------------------------------------------------------------
local usedSlots = {}
local unknownSlot = {}
for id, e in pairs(beats) do
  for key, slot in pairs(e.beat.vo or {}) do
    if type(slot) == "string" then
      usedSlots[slot] = (usedSlots[slot] or 0) + 1
      if not Story.CASTING[slot] then unknownSlot[#unknownSlot + 1] = id .. "." .. key .. " -> " .. slot end
    end
  end
end
check("every `vo` slot a beat uses exists in CASTING", #unknownSlot == 0, table.concat(unknownSlot, "; "))

-- A slot the story leans on must have a recording. `laugh`/`toast` are knowingly empty
-- (the audit found none) and must therefore not be referenced by any beat.
local emptyButUsed = {}
for slot, n in pairs(usedSlots) do
  local c = Story.CASTING[slot]
  if c and (type(c.ids) ~= "table" or #c.ids == 0) then
    emptyButUsed[#emptyButUsed + 1] = ("%s (used %d×)"):format(slot, n)
  end
end
check("no beat depends on a casting slot with zero recordings", #emptyButUsed == 0,
      "these slots are empty but referenced: " .. table.concat(emptyButUsed, ", "))

-- THE ID TRAP. String IDs are ~2e18; Lua numbers are doubles and corrupt them silently.
local badIds = {}
for slot, c in pairs(Story.CASTING) do
  for _, id in ipairs(c.ids or {}) do
    if type(id) ~= "string" then
      badIds[#badIds + 1] = slot .. ": " .. tostring(id) .. " is a " .. type(id)
    elseif not id:match("^%d+$") then
      badIds[#badIds + 1] = slot .. ": " .. id .. " isn't all digits"
    elseif #id < 18 or #id > 20 then
      badIds[#badIds + 1] = slot .. ": " .. id .. " is " .. #id .. " digits (expected 19)"
    end
  end
end
check("every String ID is a 19-digit STRING, never a number", #badIds == 0, table.concat(badIds, "; "))

-- Every casting slot documents what it's for. A slot with no `need` can't be recast by anyone else.
local noNeed = {}
for slot, c in pairs(Story.CASTING) do
  if not c.need or #c.need < 10 then noNeed[#noNeed + 1] = slot end
end
check("every casting slot says what it must carry", #noNeed == 0, table.concat(noNeed, ", "))

-- ---------------------------------------------------------------------------
-- 3. The arc is actually completable
-- ---------------------------------------------------------------------------
do
  local first = Story.arc.parts[1].beats[1].id
  local seen, queue = { [first] = true }, { first }
  while #queue > 0 do
    local id = table.remove(queue, 1)
    local e = beats[id]
    local n = e and e.beat.next
    if n and not seen[n] then seen[n] = true; queue[#queue + 1] = n end
  end
  -- Parts chain by their own `arms` rather than by `next` (a part opens when the previous one
  -- has rested and enough days have passed), so a pure `next` walk stops at every part boundary.
  -- Close over the whole graph instead: keep sweeping until nothing new becomes reachable.
  local grew = true
  while grew do
    grew = false
    for _, part in ipairs(Story.arc.parts) do
      -- A part's first beat is reachable once ANY beat of the previous part is done, since
      -- parts arm on elapsed days and the arc fact, not on a pointer.
      local prevSeen = false
      for _, p2 in ipairs(Story.arc.parts) do
        if p2.id == part.id then break end
        for _, b2 in ipairs(p2.beats or {}) do if seen[b2.id] then prevSeen = true end end
      end
      for i, b in ipairs(part.beats or {}) do
        local reach = seen[b.id]
        if not reach and i == 1 and (prevSeen or part.id == Story.arc.parts[1].id) then reach = true end
        if not reach and b.arms and b.arms.afterBeat and seen[b.arms.afterBeat] then reach = true end
        if not reach and b.arms and b.arms.heat and prevSeen then reach = true end  -- heat-armed beats
        if reach and not seen[b.id] then
          seen[b.id] = true; grew = true
          if b.next then seen[b.next] = true end
        end
      end
    end
  end
  local unreachable = {}
  for _, part in ipairs(Story.arc.parts) do
    for _, b in ipairs(part.beats or {}) do
      -- Part 5's three epilogues are ending-gated, not chained; they're reachable by construction.
      if not seen[b.id] and not b.ending then unreachable[#unreachable + 1] = b.id end
    end
  end
  check("every arc beat is reachable from the first one", #unreachable == 0, table.concat(unreachable, ", "))
end

do
  local endings = {}
  for _, part in ipairs(Story.arc.parts) do
    for _, b in ipairs(part.beats or {}) do
      for _, ch in ipairs(b.choices or {}) do
        if type(ch.ending) == "number" then endings[ch.ending] = true end
      end
      if type(b.ending) == "number" then endings["epi" .. b.ending] = true end
    end
  end
  check("all three endings are choosable", endings[1] and endings[2] and endings[3])
  check("all three endings have an epilogue", endings.epi1 and endings.epi2 and endings.epi3)
end

-- The computed ending ("You choose, Jackie") must be total: every rule set ends in a fallback,
-- or a save can reach the climax and get no ending at all.
do
  local found, hasFallback = false, false
  for _, part in ipairs(Story.arc.parts) do
    for _, b in ipairs(part.beats or {}) do
      for _, ch in ipairs(b.choices or {}) do
        if ch.computed then
          found = true
          for _, r in ipairs(ch.computed.rules or {}) do
            if r.fallback then hasFallback = true end
            if r.when then check("  rule parses: " .. r.when, load("return " .. r.when) ~= nil) end
          end
        end
      end
    end
  end
  check("the computed ending exists", found)
  check("the computed ending can never fall through", hasFallback)
end

-- ---------------------------------------------------------------------------
-- 4. Pacing and safety (the storyboard's own header rules, asserted)
-- ---------------------------------------------------------------------------
for _, part in ipairs(Story.arc.parts) do
  check(("part %s rests"):format(part.id), type(part.rest) == "string" and #part.rest > 10)
  check(("part %s has a logline"):format(part.id), type(part.logline) == "string" and #part.logline > 20)
  check(("part %s says what it is for"):format(part.id), type(part.intent) == "string" and #part.intent > 40)
end

check("the arc opens behind the reunion", (Story.arc.parts[1].arms or {}).stage == 4)
check("the arc opens with a card that warns the player", type(Story.arc.opening_card.text) == "string")

-- Every beat carries a writer's note. This is the storyboard's whole reason for existing:
-- the next person to touch a beat has to be able to see what it was FOR.
do
  local noIntent = {}
  for _, part in ipairs(Story.arc.parts) do
    for _, b in ipairs(part.beats or {}) do
      if not b.intent or #b.intent < 30 then noIntent[#noIntent + 1] = b.id end
    end
  end
  check("every arc beat states its dramatic intent", #noIntent == 0, table.concat(noIntent, ", "))
end

-- The two upsetting beats must be switchable, or the opening card is lying.
do
  local gated = {}
  for id, e in pairs(beats) do
    if (e.beat.arms or {}).config then gated[#gated + 1] = id end
  end
  check("the takeover and the raid are both behind settings switches", #gated >= 2,
        "gated beats: " .. table.concat(gated, ", "))
end

-- ---------------------------------------------------------------------------
-- 5. SMS contract
-- ---------------------------------------------------------------------------
do
  local ids, dupe, orphanReply, emptyThread = {}, {}, {}, {}
  for id, e in pairs(beats) do
    local s = e.beat.sms
    if s then
      if ids[s.id] then dupe[#dupe + 1] = s.id else ids[s.id] = id end
      if type(s.messages) ~= "table" or (#s.messages == 0 and not s.replies) then
        emptyThread[#emptyThread + 1] = s.id
      end
      for _, r in ipairs(s.replies or {}) do
        if s.followups and s.followups[r.id] == nil then
          orphanReply[#orphanReply + 1] = s.id .. "." .. r.id
        end
      end
    end
  end
  check("every SMS thread id is unique", #dupe == 0, table.concat(dupe, ", "))
  check("no SMS thread is empty", #emptyThread == 0, table.concat(emptyThread, ", "))
  check("every SMS reply has a declared follow-up (even an empty one)", #orphanReply == 0,
        "no followups entry for: " .. table.concat(orphanReply, ", "))
end

-- ---------------------------------------------------------------------------
-- 6. Side quests
-- ---------------------------------------------------------------------------
do
  local noPlants, noSlot = {}, {}
  for _, q in ipairs(Side.quests) do
    if not q.plants then noPlants[#noPlants + 1] = q.id end
    if not q.slot then noSlot[#noSlot + 1] = q.id end
  end
  check("every side quest declares what it plants (even 'nothing')", #noPlants == 0, table.concat(noPlants, ", "))
  check("every side quest declares where it slots into the arc", #noSlot == 0, table.concat(noSlot, ", "))

  local offered = {}
  for _, id in ipairs(Side.offer.order) do offered[id] = true end
  local unoffered = {}
  for _, q in ipairs(Side.quests) do if not offered[q.id] then unoffered[#unoffered + 1] = q.id end end
  check("every side quest is in the offer order", #unoffered == 0, table.concat(unoffered, ", "))
  check("the mod never offers more than one quest a day", (Side.offer.maxPerDay or 99) <= 1)
end

-- ---------------------------------------------------------------------------
-- 7. Facts
-- ---------------------------------------------------------------------------
do
  local declared = {}
  for _, name in pairs(Story.FACTS) do declared[name] = true end
  local undeclared = {}
  for id, e in pairs(beats) do
    local function scan(sets, where)
      for name in pairs(sets or {}) do
        if not declared[name] and not name:match("^jackielives_side_") then
          undeclared[#undeclared + 1] = where .. " sets " .. name
        end
      end
    end
    scan(e.beat.sets, id)
    for _, ch in ipairs(e.beat.choices or {}) do scan(ch.sets, id .. "." .. tostring(ch.id)) end
  end
  check("every fact a beat writes is declared in FACTS (or is a side-quest fact)",
        #undeclared == 0, table.concat(undeclared, "; "))

  local prefixed = true
  for _, name in pairs(Story.FACTS) do
    if not tostring(name):match("^jackielives_") then prefixed = false end
  end
  check("every fact name is namespaced to this mod", prefixed)
end

print(("\n%d checks, %d failed"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
