-- test_nca.lua — the Night City Allies bridge, against a stub of THEIR objects
-- =============================================================================
--   lua tools/test_nca.lua
--
-- The stub mirrors the real shapes read out of NCA 1.4.3 (see
-- docs/research/nca_integration.md): a mod table with `.app`, an
-- `app.availableInteractions` list, and an `app.ui:choice(title, rows)` that honours a per-row
-- `condition` exactly as Application/ui.lua does.
--
-- ⚠️ WHY THIS TEST EXISTS AT ALL. We reach into `mod.app`, which they never published. The whole
-- integration is one layout change away from breaking, so what is pinned here is the BEHAVIOUR ON
-- FAILURE as much as the happy path: no NCA -> silent no-op; a changed layout -> refuse to attach;
-- their renderer throwing -> end cleanly rather than wedge the player in a menu.
-- =============================================================================

local here = arg and arg[0] and arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/../mod/JackieLives/?.lua;" .. package.path

_G.Game = { FindEntityByID = function() return nil end }   -- no engine: the record path must fail soft

local Allies = require("nca")

local pass, fail = 0, 0
local function check(name, ok, detail)
  if ok then pass = pass + 1; print("  ok   " .. name)
  else fail = fail + 1; print(("  FAIL %s%s"):format(name, detail and ("  -> " .. tostring(detail)) or "")) end
end

-- ---------------------------------------------------------------------------
-- A stub of their side, with their real semantics.
-- ---------------------------------------------------------------------------
local function fakeNCA()
  local ui = { opened = {} }
  function ui:choice(title, rows)
    self.opened[#self.opened + 1] = { title = title, rows = rows }
    self.last = { title = title, rows = rows }
  end
  local app = { availableInteractions = {}, ui = ui }
  -- their own rows, so we can prove ours is ADDED rather than substituted
  app.availableInteractions[1] = { label = "Follow",     condition = function() return true end, callback = function() end }
  app.availableInteractions[2] = { label = "Send away",  condition = function() return true end, callback = function() end }
  return { app = app, version = "1.4.3" }, app, ui
end

local function fakeNPC(name)
  return { GetName = function() return name end, GetEntityID = function() return nil end }
end

-- our side
local spoken, playerSaid, famAwards, ended = {}, {}, {}, 0
CLOCK = 0
local TREE = {
  start = "open",
  nodes = {
    open = { silent = true, choices = {
      { text = "How've you been?",        to = "how" },
      { text = "Tell me about the moon.", to = "moon", minFam = 2 },
      { text = "Rare thing.",             to = "how",  chance = 0.0 },   -- never rolls
      { text = "Once only.",              to = "how",  once = "k1" },
      { text = "Nothing.",                             },                -- no `to` -> ends
    } },
    how  = { companion = { text = "Working." }, choices = { { text = "Fair.", fam = 1 } } },
    -- a sampled hub: 8 topics, `pick` a range, and an exit pinned via `last`
    hub  = { silent = true, pick = { 2, 3 }, choices = {
      { text = "t1", to = "how" }, { text = "t2", to = "how" }, { text = "t3", to = "how" },
      { text = "t4", to = "how" }, { text = "t5", to = "how" }, { text = "t6", to = "how" },
      { text = "t7", to = "how" }, { text = "t8", to = "how" },
      { text = "Nothing.", last = true },
    } },
    moon = { companion = { text = "It's clean up there." }, choices = { { text = "Yeah." } } },
  },
}

local famTier = 0
Allies.bind{
  log          = function() end,
  speak        = function(t) spoken[#spoken + 1] = t; return 1.0 end,
  sayPlayer    = function(t) playerSaid[#playerSaid + 1] = t end,
  pickLine     = function(pool) return pool and pool[1] end,
  var          = function(e) return e end,
  talkTree     = function() return TREE end,
  personaName  = function() return "Jackie" end,
  activeKey    = function() return "jackie" end,
  recordIsOurs = function(r) return tostring(r):find("Jackie", 1, true) ~= nil end,
  famAllows    = function(minFam) return (minFam or 0) <= famTier end,
  famAdd       = function(a) famAwards[#famAwards + 1] = a end,
  endHook      = function() ended = ended + 1 end,
  now          = function() return CLOCK end,
  hubRefresh   = function() return 10.0, 30.0 end,
}

-- ---------------------------------------------------------------------------
print("1. absent NCA is a no-op, not an error")
_G.GetMod = function() return nil end
local okTick = pcall(function() for i = 1, 3 do Allies.tick(i * 10) end end)
check("ticking with no NCA installed never throws", okTick)
check("...and nothing is attached", Allies.present() == false)

-- ---------------------------------------------------------------------------
print("\n2. attach")
local mod, app, ui = fakeNCA()
_G.GetMod = function(n) return n == "NightCityAllies" and mod or nil end
Allies.tick(1000)
check("attached once NCA appears", Allies.present() == true)
check("our row was ADDED — their own rows survive", #app.availableInteractions == 3,
      #app.availableInteractions)
check("...and theirs are unchanged", app.availableInteractions[2].label == "Follow"
      and app.availableInteractions[3].label == "Send away")
local ours = app.availableInteractions[1]
-- ⚠️ FIRST, deliberately. Their UI paginates at 12 rows and puts the rest behind a "More ..." button
-- that their own AlreadyRead styling greys out. Appended, our row fell off page one on a fully-kitted
-- squad member and was simply not reachable in game (2026-08-15).
check("...ours is FIRST, so it can never fall off page one", ours.label == "Talk")

-- ⚠️ THE REGRESSION THAT WOULD SHIP TWO TALK ROWS: CET hot-reload re-runs onInit.
Allies.tick(2000); Allies.tick(3000)
check("attaching is idempotent (a hot reload must not add a second row)",
      #app.availableInteractions == 3, #app.availableInteractions)

-- ---------------------------------------------------------------------------
print("\n3. the row appears on OUR character and on nobody else")
check("shows on our persona (matched by display name)", ours.condition(fakeNPC("Jackie")) == true)
check("hidden on somebody else's ally",                 ours.condition(fakeNPC("Judy")) == false)
check("hidden on a random merc",                        ours.condition(fakeNPC("Merc")) == false)
check("a broken npc object answers NO rather than throwing",
      ours.condition({ GetName = function() error("boom") end }) == false)
check("nil is not our character", ours.condition(nil) == false)

-- ---------------------------------------------------------------------------
print("\n4. the conversation runs through THEIR renderer")
ours.callback(fakeNPC("Jackie"), ui)
check("their ui:choice was called", ui.last ~= nil)
check("...titled with her name", ui.last and ui.last.title == "Jackie", ui.last and ui.last.title)
-- tier 0: the moon topic is gated, the 0%-chance row never rolls, so 3 of 5 remain
local labels = {}
for _, r in ipairs(ui.last.rows) do labels[#labels + 1] = r.label end
check("familiarity gating is honoured (the tier-2 topic is absent at tier 0)",
      table.concat(labels, "|"):find("moon") == nil, table.concat(labels, "|"))
check("a 0%-chance row never appears", table.concat(labels, "|"):find("Rare") == nil)
check("the ungated topics are all offered", #ui.last.rows == 3, #ui.last.rows)

famTier = 3
ours.callback(fakeNPC("Jackie"), ui)
labels = {}
for _, r in ipairs(ui.last.rows) do labels[#labels + 1] = r.label end
check("...and at tier 3 the gated topic arrives", table.concat(labels, "|"):find("moon") ~= nil,
      table.concat(labels, "|"))

-- ---------------------------------------------------------------------------
print("\n5. picking a row advances our tree")
local before = #ui.opened
for _, r in ipairs(ui.last.rows) do if r.label == "How've you been?" then r.callback() end end
check("V's line was shown as a subtitle", playerSaid[#playerSaid] == "How've you been?")
check("her reply was spoken", spoken[#spoken] == "Working.", spoken[#spoken])
check("...and the next node opened a new menu through them", #ui.opened == before + 1)
check("the silent root spoke nothing on the way in",
      spoken[1] == "Working.", tostring(spoken[1]))

for _, r in ipairs(ui.last.rows) do if r.label == "Fair." then r.callback() end end
check("a choice carrying `fam` awards it", famAwards[#famAwards] == 1, tostring(famAwards[#famAwards]))
check("a choice with no `to` ends the conversation", Allies.talking() == false)
check("...and the end hook fired", ended >= 1)

-- ---------------------------------------------------------------------------
print("\n6. `once` is struck off for the rest of the conversation")
famTier = 0
ours.callback(fakeNPC("Jackie"), ui)
local function labelSet()
  local t = {}
  for _, r in ipairs(ui.last.rows) do t[r.label] = r end
  return t
end
local set = labelSet()
check("the one-time row is offered first time", set["Once only."] ~= nil)
set["Once only."].callback()                    -- take it; lands on `how`
for _, r in ipairs(ui.last.rows) do if r.label == "Fair." then r.callback() end end   -- ends
ours.callback(fakeNPC("Jackie"), ui)              -- a NEW conversation
check("...and a NEW conversation offers it again (the ledger is per conversation)",
      labelSet()["Once only."] ~= nil)

-- ---------------------------------------------------------------------------
print("\n6b. the `pick` sampler — the thing that makes her feel different each time")
-- ⚠️ This was shipped unhonoured in the first draft, on the theory that `pick` only existed because
-- our own box is a fixed-height list and their renderer paginates. Wrong: sampling is CONTENT. A hub
-- that always shows all thirty topics reads as a menu, and the character stops being surprising.
TREE.nodes.open.choices = { { text = "Catch up", to = "hub" } }
local function openHub()
  ours.callback(fakeNPC("Jackie"), ui)
  for _, r in ipairs(ui.last.rows) do if r.label == "Catch up" then r.callback() end end
  local t = {}
  for _, r in ipairs(ui.last.rows) do t[#t + 1] = r.label end
  return t
end

CLOCK = 100
local first = openHub()
check("a sampled hub offers a SUBSET, not the wall", #first < 9, #first)
check("...between 2 and 3 topics plus the pinned exit", #first >= 3 and #first <= 4, #first)
check("...and the pinned exit is always among them",
      table.concat(first, "|"):find("Nothing.", 1, true) ~= nil, table.concat(first, "|"))

-- THE STICKY DRAW: reopening must not re-roll, or a player walks the whole pool in one sitting
CLOCK = 101
local again = openHub()
check("reopening inside the cooldown keeps the SAME topics",
      table.concat(again, "|") == table.concat(first, "|"),
      table.concat(first, "|") .. "  vs  " .. table.concat(again, "|"))

-- ...and after the cooldown it may move on
CLOCK = 100000
local rolls = {}
for _ = 1, 12 do CLOCK = CLOCK + 1000; rolls[#rolls + 1] = table.concat(openHub(), "|") end
local distinct = {}
for _, r in ipairs(rolls) do distinct[r] = true end
local n = 0; for _ in pairs(distinct) do n = n + 1 end
check("...but a later visit draws afresh (the hub is not frozen forever)", n > 1, n .. " distinct draws")

-- a node with no `pick` must still show everything
TREE.nodes.hub.pick = nil
local all = openHub()
check("a hub with no `pick` still offers every eligible topic", #all == 9, #all)
TREE.nodes.hub.pick = { 2, 3 }

print("\n6c. their loader REPLACES the interaction table — we must survive it")
-- ⚠️ THE BUG THAT SHIPPED. App:LoadModules() does
--     self.availableInteractions = self.moduleLoader:LoadInteractions()
-- so it hands back a BRAND NEW table rather than refilling the old one, and it runs at their init and
-- again around a session start. Our row went in fine, we reported "attached", and then the whole
-- table was thrown away with our row in it. In game: "the conversation hub was not added to the NCA
-- list" — with no error anywhere, because nothing failed. It was simply discarded.
local reload = function()          -- exactly what their LoadModules does to us
  app.availableInteractions = {
    { label = "Follow",    condition = function() return true end, callback = function() end },
    { label = "Send away", condition = function() return true end, callback = function() end },
  }
end

reload()
local function ourRowIn()
  for _, e in ipairs(app.availableInteractions) do if e.label == "Talk" then return e end end
  return nil
end
check("their reload wipes our row (this is the real behaviour, not a straw man)", ourRowIn() == nil)

Allies.tick(500000)                -- the next heartbeat after the reload
local back = ourRowIn()
check("...and the next tick puts it back", back ~= nil)
check("...still at the front", app.availableInteractions[1].label == "Talk",
      app.availableInteractions[1].label)
check("...exactly once, not twice", #app.availableInteractions == 3, #app.availableInteractions)
check("...and the restored row still works on our persona", back and back.condition(fakeNPC("Jackie")) == true)

-- and it must not keep appending on every later tick
Allies.tick(500000 + 60); Allies.tick(500000 + 120)
check("a settled list is left alone", #app.availableInteractions == 3, #app.availableInteractions)

-- ⚠️ THE PAGE-ONE GUARANTEE, against a menu big enough to paginate. Their MAX_CHOICES_PER_PAGE is 12.
for i = 1, 20 do
  table.insert(app.availableInteractions, { label = "cmd" .. i, condition = function() return true end,
                                            callback = function() end })
end
Allies.tick(600000)
local idx
for i, e in ipairs(app.availableInteractions) do if e.label == "Talk" then idx = i end end
check("with a 20+ row menu, Talk is still within the first page (<= 12)", idx ~= nil and idx <= 12, idx)
-- put the list back as we found it, or the detach check below counts our 20 filler rows
for i = #app.availableInteractions, 1, -1 do
  if tostring(app.availableInteractions[i].label):find("^cmd%d") then table.remove(app.availableInteractions, i) end
end

-- status(): the line the Diagnostics hotkey prints
local st = Allies.status()
check("status() reports the row as present", tostring(st):find("ourRowPresent=true", 1, true) ~= nil, st)
check("status() reports how many times they rebuilt the list",
      tostring(st):find("reasserts=1", 1, true) ~= nil, st)

print("\n7. failure modes — the part that actually matters")
-- their renderer throws
local badUi = { choice = function() error("their UI changed") end }
local okThrow = pcall(function() ours.callback(fakeNPC("Jackie"), badUi) end)
check("their ui:choice throwing does not take us down", okThrow)
check("...and we end the conversation rather than wedging", Allies.talking() == false)

-- detach removes OUR row and only ours
Allies.detach()
check("detach removed our row", #app.availableInteractions == 2, #app.availableInteractions)
check("...and left theirs alone",
      app.availableInteractions[1].label == "Follow" and app.availableInteractions[2].label == "Send away")
check("...and reports detached", Allies.present() == false)

-- a layout change on their side: no availableInteractions at all
local mod2 = { app = { ui = {} } }
check("a changed NCA layout refuses to attach instead of erroring", Allies.attach(mod2) == false)
check("...and we stay detached", Allies.present() == false)

-- ⚠️ the retry must STOP. A player without NCA must not pay a GetMod call forever.
_G.GetMod = function() return nil end
local calls = 0
_G.GetMod = function() calls = calls + 1; return nil end
for i = 1, 200 do Allies.tick(10000 + i * 100) end
check("the search gives up rather than polling forever", calls <= Allies.maxTries, calls)

print(("\n%d checks, %d failed"):format(pass + fail, fail))
os.exit(fail == 0 and 0 or 1)
