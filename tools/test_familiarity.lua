-- tools/test_familiarity.lua — unit tests for the v1.65 familiarity system.
--
-- Run from the repo root:   lua tools/test_familiarity.lua
-- Exits non-zero on failure. Needs only a stock Lua 5.x interpreter (no game, no CET).
--
-- This loads the REAL familiarity.lua and the REAL config.lua, so the tests can't drift from the
-- shipped code or the shipped numbers. What it pins down:
--   * the CURVE — the pacing table in config.lua's header is asserted here, so "slow" can't quietly
--     become "fast" through a well-meant tweak (it did exactly that twice in NCLives);
--   * Jackie is SLOWER than NCLives by construction, which is the whole point of the port;
--   * tier gating, including the two rules that are easy to get subtly wrong:
--       - disabled must show EVERYTHING, never nothing;
--       - points floor at 0, so a rude V can cool him off but never make him a stranger;
--   * the CONTENT: every tier has topics, every link resolves, the exit is pinned, and no new line
--     carries an `sfx` (they're unvoiced by design — a bogus id makes Audioware reject the whole bank).

package.path = "mod/JackieLives/?.lua;" .. package.path

local T = dofile("tools/tcheck.lua")
local check = T.check

local Config = require("config")
local Fam    = require("familiarity")

-- In-memory fact store, so the module runs exactly as it does in-game (it only ever talks to
-- factGet/factSet) without needing the quest system.
local facts = {}
Fam.bind{
  log     = function() end,
  factGet = function(n) return facts[n] or 0 end,
  factSet = function(n, v) facts[n] = v end,
  config  = function() return Config.familiarity end,
}

local F = Config.familiarity

-- ---------------------------------------------------------------------------
print("1. the curve")
-- ---------------------------------------------------------------------------
check("familiarity is enabled by default", F.enabled ~= false)
check("four tiers, four names", #F.tiers == 4 and #F.names == 4)
check("tiers ascend from 0", (function()
  if F.tiers[1] ~= 0 then return false end
  for i = 2, #F.tiers do if F.tiers[i] <= F.tiers[i - 1] then return false end end
  return true
end)(), table.concat(F.tiers, ", "))

-- A conversation is worth ONE point. If this ever becomes per-topic, the whole curve collapses to
-- NCLives' pace and the "slow" requirement is silently gone — so it is asserted, not assumed.
check("a conversation is worth exactly 1", F.award.talk == 1,
      "talk = " .. tostring(F.award.talk) .. " — per-topic scoring would collapse the curve")
check("a dinner is worth more than any conversation", F.award.dinner > F.award.talk)
check("a call is the cheapest award", F.award.call <= F.award.talk)

-- The pacing table from config.lua's header, asserted so the documentation can't lie.
local function dinners(tier) return math.ceil(F.tiers[tier + 1] / F.award.dinner) end
local function talks(tier)   return math.ceil(F.tiers[tier + 1] / F.award.talk)   end
check("Close needs ~10 conversations",  talks(1) >= 8  and talks(1) <= 12, "= " .. talks(1))
check("Trusted needs ~7 dinners",       dinners(2) >= 6 and dinners(2) <= 9, "= " .. dinners(2))
check("Family needs ~16 dinners",       dinners(3) >= 14 and dinners(3) <= 18, "= " .. dinners(3))

-- The reason this port exists: Jackie must be a slower burn than the NCLives personas.
-- NCLives ships { 0, 5, 14, 28 } with talk paying 1 per TOPIC (so ~5 per conversation).
local NCLIVES_TOP, NCLIVES_TALK_PER_CONVO = 28, 5
local jackieConvosToTop  = F.tiers[4] / F.award.talk
local nclivesConvosToTop = NCLIVES_TOP / NCLIVES_TALK_PER_CONVO
check("Jackie is a much slower burn than an NCLives persona",
      jackieConvosToTop >= nclivesConvosToTop * 4,
      ("Jackie %.0f conversations to top vs NCLives ~%.0f"):format(jackieConvosToTop, nclivesConvosToTop))

-- ---------------------------------------------------------------------------
print("\n2. tiers and gating")
-- ---------------------------------------------------------------------------
Fam.reset()
check("a fresh save starts at tier 0", Fam.tier() == 0 and Fam.points() == 0)
check("tier 0 is named for a friend, not a job title", F.names[1] == "Choom")
check("the top tier is 'Family'", F.names[4] == "Family")

check("tier 0 allows only ungated + tier-0 content",
      Fam.allows(nil) and Fam.allows(0) and not Fam.allows(1) and not Fam.allows(3))

for _ = 1, F.tiers[2] do Fam.add("talk") end
check("enough conversations reach Close", Fam.tier() == 1, Fam.status())
check("...which unlocks tier 1 but not tier 2", Fam.allows(1) and not Fam.allows(2))

Fam.setTier(3)
check("setTier(3) reaches Family", Fam.tier() == 3 and Fam.allows(3))

-- Floors at zero: V can cool him off, never reset him to a stranger.
Fam.setPoints(2)
Fam.add("choice", -10)
check("points floor at 0 (you can cool him off, not erase him)", Fam.points() == 0 and Fam.tier() == 0)

-- Disabled must reveal everything. If it hid content it would read as the writing having vanished.
F.enabled = false
check("disabled shows EVERY tier, not none", Fam.tier() == 3 and Fam.allows(3))
F.enabled = true
Fam.reset()

check("a malformed gate shows its content rather than eating it", Fam.allows("banana") == true)

-- ---------------------------------------------------------------------------
print("\n3. the conversation tree")
-- ---------------------------------------------------------------------------
local tree = Config.locationDialogue and Config.locationDialogue.everywhere
check("the everywhere tree exists", type(tree) == "table" and type(tree.nodes) == "table")
local hub = tree.nodes.open

check("unvoiced lines don't drop a stray grunt (muteFallback)", tree.muteFallback == true)
check("the hub samples a few topics rather than showing a wall", type(hub.pick) == "table")

local byTier, exits = {}, 0
for _, c in ipairs(hub.choices) do
  local t = c.minFam or 0
  byTier[t] = (byTier[t] or 0) + 1
  if c.pin then exits = exits + 1 end
end
for t = 0, 3 do
  check(("tier %d has topics to offer"):format(t), (byTier[t] or 0) >= 2,
        "only " .. tostring(byTier[t] or 0) .. " — a tier with nothing new is a dead level-up")
end
check("the way out of the hub is PINNED", exits >= 1,
      "a sampled hub with an unpinned exit can strand the player with no way to end the conversation")

-- Every branch must land somewhere real.
local dangling = {}
for key, node in pairs(tree.nodes) do
  for _, c in ipairs(node.choices or {}) do
    if c.to and not tree.nodes[c.to] then dangling[#dangling + 1] = key .. " -> " .. tostring(c.to) end
  end
end
check("every link resolves", #dangling == 0, table.concat(dangling, ", "))

-- The growth mechanic: the same question answered at more length later.
local grew = 0
for _, node in pairs(tree.nodes) do
  local tiers = {}
  for _, e in ipairs(node.jackiePool or {}) do tiers[e.minFam or 0] = true end
  local n = 0; for _ in pairs(tiers) do n = n + 1 end
  if n >= 2 then grew = grew + 1 end
end
check("some questions grow their answer with familiarity", grew >= 3,
      "only " .. grew .. " nodes vary by tier — new topics alone read as a menu growing, not a person opening up")

-- this check used to be "no tier-gated line may claim a voice clip at all", because under
-- Audioware ONE `sfx` naming a wav that wasn't in the bank made it reject the whole bank and Jackie
-- went completely silent. That failure mode died with v1.66 — the native path names the game's own
-- lines, and an id the game doesn't know is one silent line, not a dead mod. So the rule inverts:
-- a tier-gated line MAY be voiced (the v1.69 small talk deliberately is, so his first answer to a
-- new question is his real voice), as long as every id is a line that actually exists. Reality is
-- proven by vo_durations.lua, which is generated from the install — if it's in there, it's real.
local DUR = require("vo_durations")
local unreal = {}
for key, node in pairs(tree.nodes) do
  for _, e in ipairs(node.jackiePool or {}) do
    local id = e.sfx and e.sfx:match("^jl_(%d%d%d%d%d%d+)$")
    if e.sfx and not (id and DUR[id]) then unreal[#unreal + 1] = key .. ": " .. e.sfx end
  end
end
check("every voiced line in the hub is a real line of the game's", #unreal == 0,
      "no such id in the install: " .. table.concat(unreal, ", "))

-- V can say the wrong thing, and it should cost something.
local penalties = 0
for _, node in pairs(tree.nodes) do
  for _, c in ipairs(node.choices or {}) do if c.fam and c.fam < 0 then penalties = penalties + 1 end end
end
check("at least one reply can cost V ground", penalties >= 1)

T.finish()
