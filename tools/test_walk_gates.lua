-- tools/test_walk_gates.lua — unit tests for the v1.46 walk gates.
--
-- Run from the repo root:   lua tools/test_walk_gates.lua mod/JackieLives/init.lua
-- Exits non-zero on failure. Needs only a stock Lua 5.x interpreter (no game, no CET).
--
-- These are NOT copies of the logic: the harness EXTRACTS jlVWalking / jlVertical / jlAbreastOn
-- straight out of init.lua and runs the real bytecode against stubbed game calls. So the tests
-- cannot silently drift away from the shipped code — if a function is renamed, the test errors.
--
-- What it pins down:
--   * abreast engages only after the walk-band sustain, on flat ground;
--   * stairs/slopes (V's vertical speed) and a Jackie-vs-V height gap both hand him to the trail;
--   * the slopeReleaseSeconds latch stops trail<->abreast flip-flopping on a landing;
--   * sneaking and combat both disable abreast;
--   * THE HANDOFF INVARIANT — across a full stair-climb there is never a frame where nobody
--     drives Jackie (the v1.46 bug) nor one where both ticks do.

-- call them EVERY simulated frame, exactly as onUpdate does in-game.

JL = { clock = 0, abreast = {}, summon = { active = true, companionSet = true, spawn = { handle = {} } },
       dinner = {}, leaving = {}, disableCustomWalk = false }
Config = { abreast = { enabled = true, slopeRate = 0.45, maxZDelta = 1.0, slopeReleaseSeconds = 1.5,
                       walkMinSpeed = 0.6, walkMaxSpeed = 2.0, jogMinSpeed = 2.8, walkSustainSeconds = 2.0 },
           stealth = { enabled = true } }
jlCruise = nil

VPOS, JPOS, SNEAK, COMBAT, TAKEDOWN = { x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 }, false, false, false

function playerPos() return VPOS end
function jlInCombat() return COMBAT end
function jlVSneaking() return SNEAK end
function jlTakedownBusy() return TAKEDOWN end   -- v1.48: a running takedown owns Jackie
function log(_) end
JL.summon.spawn.handle.GetWorldPosition = function(_) return JPOS end

local src = io.open(arg[1], "r"):read("a")
local function extract(name)
  local s = src:find("\nfunction " .. name .. "%(")
  assert(s, "could not find " .. name)
  local e = src:find("\nend\n", s)
  return src:sub(s + 1, e + 4)
end
load(extract("jlVWalking"))()
load(extract("jlVertical"))()
load(extract("jlAbreastOn"))()

local fails = 0
local function check(name, got, want)
  if got ~= want then
    fails = fails + 1
    print(("FAIL %-52s got=%s want=%s"):format(name, tostring(got), tostring(want)))
  else
    print(("ok   %-52s %s"):format(name, tostring(got)))
  end
end

-- One simulated frame. jzOff = Jackie's height relative to V. Drives the real per-frame code path.
local function step(dt, dz, speed2d, jzOff)
  JL.clock = JL.clock + dt
  VPOS = { x = VPOS.x + (speed2d or 0) * dt, y = 0, z = VPOS.z + (dz or 0) }
  JPOS = { x = VPOS.x + 1.0, y = 0, z = VPOS.z + (jzOff or 0) }
  return jlAbreastOn()          -- exactly what onUpdate's two ticks ask, once per frame
end
local function run(n, dt, dz, speed2d, jzOff)
  local last; for _ = 1, n do last = step(dt, dz, speed2d, jzOff) end; return last
end

-- 1. flat ground, steady walk -> abreast engages (after the 2 s sustain)
run(40, 0.1, 0, 1.2)
check("flat + steady walk -> jlVertical false", jlVertical(), false)
check("flat + steady walk -> abreast ON",       jlAbreastOn(), true)

-- 2. climbing stairs (V rising ~1.0 m/s) -> abreast OFF, single file
run(10, 0.1, 0.10, 1.2)
check("climbing -> jlVertical TRUE", jlVertical(), true)
check("climbing -> abreast OFF",     jlAbreastOn(), false)

-- 3. reaching a landing: the trail stays latched for slopeReleaseSeconds (no flip-flop)
step(0.1, 0, 1.2)
check("just levelled out -> still trailing (latch)", jlVertical(), true)
run(12, 0.1, 0, 1.2)                       -- ~1.2 s later: still inside the 1.5 s latch
check("1.2 s after levelling -> still trailing",     jlVertical(), true)
run(8, 0.1, 0, 1.2)                        -- now past 1.5 s
check("1.9 s after levelling -> abreast resumes",    jlVertical(), false)
check("...and abreast is ON again",                  jlAbreastOn(), true)

-- 4. height gap alone (V not climbing, Jackie a step above) trips it
run(3, 0.1, 0, 1.2, 1.4)                   -- Jackie 1.4 m above V (> maxZDelta 1.0)
check("Jackie a floor above V -> trailing", jlVertical(), true)

-- 5. back level, then sneaking disables abreast
run(25, 0.1, 0, 1.2)
check("upright, level again -> abreast ON", jlAbreastOn(), true)
SNEAK = true;  step(0.1, 0, 1.2)
check("V sneaking -> abreast OFF", jlAbreastOn(), false)
SNEAK = false; run(25, 0.1, 0, 1.2)

-- 6. combat disables abreast
COMBAT = true;  step(0.1, 0, 1.2)
check("in combat -> abreast OFF", jlAbreastOn(), false)
COMBAT = false; run(25, 0.1, 0, 1.2)

-- 6b. v1.48: a running takedown owns Jackie — abreast must stand down so it can't cancel the command.
--     (followKeepCloseTick and catchUpTick have their own `if jlTakedownBusy() then return end` guards,
--     so during a takedown NO tick drives him. That is the one intended exception to the handoff invariant.)
TAKEDOWN = true;  step(0.1, 0, 1.2)
check("takedown running -> abreast OFF", jlAbreastOn(), false)
TAKEDOWN = false; run(25, 0.1, 0, 1.2)
check("takedown over -> abreast ON again", jlAbreastOn(), true)

-- 7. a jump (brief big dz) trips the gate, then releases — documented, acceptable
step(0.1, 0.5, 1.2)
check("jump -> trailing", jlVertical(), true)
run(20, 0.1, 0, 1.2)
check("~2 s after jump -> abreast back", jlVertical(), false)

-- 8. THE HANDOFF INVARIANT. followKeepCloseTick yields iff jlAbreastOn(); abreastTick drives iff
--    jlAbreastOn(). Assert across a full stair-climb that there is never a frame with NOBODY driving
--    Jackie (the bug the shared predicate exists to prevent) nor one with BOTH driving him.
local gap, overlap, sawBoth = 0, 0, { [true] = 0, [false] = 0 }
for i = 1, 80 do
  local on = step(0.1, (i > 20 and i < 45) and 0.10 or 0, 1.2)
  local trailDrives, abreastDrives = not on, on
  if not trailDrives and not abreastDrives then gap = gap + 1 end
  if trailDrives and abreastDrives then overlap = overlap + 1 end
  sawBoth[on] = sawBoth[on] + 1
end
check("handoff: frames with NOBODY driving Jackie", gap, 0)
check("handoff: frames with BOTH driving Jackie",   overlap, 0)
check("handoff: climb really did hand over (trail frames > 0)", sawBoth[false] > 0, true)
check("handoff: flat really did hand back (abreast frames > 0)", sawBoth[true] > 0, true)

print(fails == 0 and "\nALL PASS" or ("\n" .. fails .. " FAILURE(S)"))
os.exit(fails == 0 and 0 or 1)
