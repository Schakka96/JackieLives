-- tools/test_passenger.lua — the v1.8.8 regression: a queued mount is not a failed mount.
--
-- Run from the repo root:   luajit tools/test_passenger.lua mod/JackieLives/init.lua
-- Exits non-zero on failure. Needs only a stock Lua 5.x interpreter (no game, no CET).
--
-- NOT a copy of the logic: the harness EXTRACTS jlPassengerTick / jlPassengerBusy straight out of
-- init.lua and runs the real bytecode against a stubbed engine, so it cannot drift from the shipped
-- code — rename either function and this errors rather than passing.
--
-- THE BUG IT PINS (reported against v1.91, 2026-08-20: "Jackie cant get inside a vehicle").
-- Native.forceMount ends in `Game.GetMountingFacility():Mount(req)` — a QUEUED request. Nobody is in
-- a seat on the frame it is asked for. v1.90 read `Native.isMountedTo` back on that same frame, got
-- the honest "not aboard", declared the teleport dead and cleared `jlPassenger.veh`. Clearing that
-- releases jlPassengerBusy(), which is the ONLY thing holding followKeepCloseTick / catchUpTick off
-- his body — so they push their own move command at a Jackie the engine was one frame from seating,
-- and he never rides. The stub below models exactly that engine timing: the mount lands LATER.

local SRC = arg[1] or "mod/JackieLives/init.lua"
local srcf = assert(io.open(SRC, "r"), "cannot read " .. SRC .. " — run this from the repo root")
local src = srcf:read("a"); srcf:close()
local function extract(name)
  local s = src:find("\nfunction " .. name .. "%(")
  assert(s, "could not find " .. name .. " — renamed? then fix this harness")
  local e = src:find("\nend\n", s)
  return src:sub(s + 1, e + 4)
end

-- ---------------------------------------------------------------------------
-- the stubbed world
-- ---------------------------------------------------------------------------
local CAR = { name = "car" }
local JPOS = { x = 0, y = 0, z = 0 }
-- jlPassengerTick reads his world position to decide walk-vs-teleport. Without this the pcall
-- around it fails, `jp` stays nil and the distance branch can never be reached — the harness would
-- silently only ever test the near case.
local HANDLE = { GetWorldPosition = function(_) return JPOS end }

-- Real values from config.lua, so the timings under test are the shipped ones.
Config = { follow = { passenger = true,
                      passengerTiming = { walkSeconds = 6.0, walkTries = 2,
                                          farDistance = 18.0, forceVerifySeconds = 1.5 } } }
jlCruise = nil
JL = { clock = 0, puppet = nil, varrival = {}, leaving = {},
       summon = { active = true, companionSet = true, spawn = { handle = HANDLE } } }
jlPassenger = { veh = nil, cmd = nil, sentAt = -999, tries = 0, deadline = nil,
                mounted = false, seat = nil, armed = nil, forced = false }

local VEH_LIVE, JDIST = CAR, 3.0
local MOUNT_LANDS_AT   -- simulated clock time the engine actually seats him; nil = never
local ENGINE_SEATED = false

function log(_) end
function playerPos() return { x = 0, y = 0, z = 0 } end
function dist3() return JDIST end
function jlPlayerVehicleObj() return VEH_LIVE end
function jlIsBikeVeh() return false end
function jlDinnerOwnsBody() return false end
function resolveJackieHandle() return HANDLE end
function jlManualUnseat() end

local forceCalls, walkCalls = 0, 0
Native = {
  freeSeat     = function() return "seat_front_right" end,
  cancelMount  = function() end,
  mount        = function() walkCalls = walkCalls + 1; return { cmd = true } end,
  -- ⚠️ THE WHOLE POINT. Mount() queues; it does not seat. The engine seats him `forceVerifySeconds`
  -- LATER, which is well inside the verify window the fix opens and impossible for v1.90 to see.
  forceMount   = function() forceCalls = forceCalls + 1; MOUNT_LANDS_AT = JL.clock + 0.5; return true end,
  isMountedTo  = function() return ENGINE_SEATED end,
}

load(extract("jlPassengerBusy"))()
load(extract("jlPassengerTick"))()

-- ---------------------------------------------------------------------------
local fails = 0
local function check(name, cond, extra)
  print((cond and "ok   " or "FAIL ") .. name .. (extra and ("   " .. tostring(extra)) or ""))
  if not cond then fails = fails + 1 end
end

-- Run the tick the way onUpdate does: every frame, advancing the same clock the mod reads.
local function frames(seconds)
  for _ = 1, math.floor(seconds / 0.016) do
    JL.clock = JL.clock + 0.016
    if MOUNT_LANDS_AT and JL.clock >= MOUNT_LANDS_AT then ENGINE_SEATED = true end
    jlPassengerTick()
  end
end

print("1. the walk is tried first, and the busy gate is held the whole time")
frames(0.1)
check("a walk command went out", walkCalls == 1, "walkCalls=" .. walkCalls)
check("no teleport yet — the walk gets its window", forceCalls == 0)
check("jlPassengerBusy() holds the follow ticks off him", jlPassengerBusy() == true)

print("\n2. two failed walks escalate to the teleport")
frames(13.0)   -- both 6 s walk windows expire
check("both honest walks were tried", walkCalls == 2, "walkCalls=" .. walkCalls)
check("then exactly one teleport was asked for", forceCalls == 1, "forceCalls=" .. forceCalls)

print("\n3. THE REGRESSION — the queued mount is not judged on the frame it was asked for")
check("the busy gate is STILL held while the request is in flight", jlPassengerBusy() == true,
      "v1.90 cleared jlPassenger.veh here, handing him straight back to followKeepCloseTick")
frames(1.0)    -- the engine seats him 0.5 s in, inside the 1.5 s verify window
check("the tick notices he made it", jlPassenger.mounted == true)
check("...and keeps the gate held for the journey", jlPassengerBusy() == true)
check("no second teleport was fired at an already-seated Jackie", forceCalls == 1,
      "forceCalls=" .. forceCalls)

print("\n4. a mount that truly never lands still gives up, and releases him")
JL.clock, ENGINE_SEATED, MOUNT_LANDS_AT = 0, false, nil
walkCalls, forceCalls = 0, 0
jlPassenger = { veh = nil, cmd = nil, sentAt = -999, tries = 0, deadline = nil,
                mounted = false, seat = nil, armed = nil, forced = false }
Native.forceMount = function() forceCalls = forceCalls + 1; return true end   -- never seats him
frames(13.0)
check("escalated to the teleport", forceCalls == 1, "forceCalls=" .. forceCalls)
check("still held during the verify window", jlPassengerBusy() == true)
-- Watch for the release rather than sampling the end state: the moment the ladder gives up, the
-- 2 s send throttle has long expired, so the very next tick legitimately starts a FRESH ladder
-- (V may have stopped at a light; a companion who gives up forever would be worse). What must not
-- happen is the gate staying latched on a mount that never landed.
local released = false
for _ = 1, 125 do
  JL.clock = JL.clock + 0.016
  jlPassengerTick()
  if not jlPassengerBusy() then released = true break end
end
check("verify window expired -> he is released to follow on foot", released)
check("...and is not left flagged as aboard", jlPassenger.mounted == false)

print("\n5. V far away when they get in -> straight to the teleport, same verify rule")
JL.clock, ENGINE_SEATED, MOUNT_LANDS_AT = 0, false, nil
walkCalls, forceCalls = 0, 0
JDIST = 40.0
jlPassenger = { veh = nil, cmd = nil, sentAt = -999, tries = 0, deadline = nil,
                mounted = false, seat = nil, armed = nil, forced = false }
Native.forceMount = function() forceCalls = forceCalls + 1; MOUNT_LANDS_AT = JL.clock + 0.5; return true end
frames(0.1)
check("no pointless walk from 40 m", walkCalls == 0, "walkCalls=" .. walkCalls)
check("placed directly", forceCalls == 1)
check("the gate is held, not released on the asking frame", jlPassengerBusy() == true,
      "v1.90 cleared jlPassenger.veh here too")
frames(1.0)
check("and he is aboard", jlPassenger.mounted == true)

print("\n6. THE IN-OUT LOOP — a flickering vehicle read must not tear the mount down")
-- Reported 2026-08-22: "Jackie will literally keep rolling in the car then rolling out the vehicle...
-- like she's keep enter the vehicle and get out vehicle while with V."
-- nclPlayerVehicleObj() is GetQuickSlotsManager():GetVehicleObject(), and it answers nil for the odd
-- frame while V is still driving. One such frame used to run the whole teardown: cancel the mount,
-- release the busy gate — so the follow ticks pull them out of a moving car — and the next frame the
-- read comes back and the ladder puts them in again.
JL.clock, ENGINE_SEATED, MOUNT_LANDS_AT = 0, false, nil
walkCalls, forceCalls = 0, 0
JDIST = 3.0
jlPassenger = { veh = nil, cmd = nil, sentAt = -999, tries = 0, deadline = nil,
                 mounted = false, seat = nil, armed = nil, forced = false, lostAt = nil, gaveUp = nil }
Native.mount = function() walkCalls = walkCalls + 1; MOUNT_LANDS_AT = JL.clock + 0.4; return { cmd = true } end
frames(1.0)
check("aboard on the first walk", jlPassenger.mounted == true)
check("...and the busy gate is held", jlPassengerBusy() == true)

-- Now drop the vehicle read for a handful of frames, exactly as the engine does.
VEH_LIVE = nil
for _ = 1, 20 do JL.clock = JL.clock + 0.016; jlPassengerTick() end
VEH_LIVE = CAR
frames(0.5)
check("a flickering vehicle read does NOT throw them out", jlPassengerBusy() == true,
      "the teardown fired on a transient nil — this is the in-out loop")
check("...and no second mount was issued", walkCalls == 1, ("walkCalls=%d"):format(walkCalls))

-- ...but V really getting out still releases them, just not on the first frame.
VEH_LIVE = nil
frames(3.0)
check("V really leaving the car does still release them", jlPassengerBusy() == false)

print("\n7. a ladder that fails does not restart on the same car")
-- Whatever the cause of a failure, restarting the ladder every 2 s is what turns one disappointment
-- into a companion strobing through the passenger door for the whole drive.
JL.clock, ENGINE_SEATED, MOUNT_LANDS_AT = 0, false, nil
walkCalls, forceCalls = 0, 0
VEH_LIVE = CAR
jlPassenger = { veh = nil, cmd = nil, sentAt = -999, tries = 0, deadline = nil,
                 mounted = false, seat = nil, armed = nil, forced = false, lostAt = nil, gaveUp = nil }
Native.mount      = function() walkCalls = walkCalls + 1; return { cmd = true } end   -- never lands
Native.forceMount = function() forceCalls = forceCalls + 1; return true end           -- never lands
frames(60.0)
check("the walk was tried its configured number of times", walkCalls == 2, ("walkCalls=%d"):format(walkCalls))
check("...the teleport exactly once", forceCalls == 1, ("forceCalls=%d"):format(forceCalls))
check("...and then it stays given up for this car", jlPassengerBusy() == false)

-- A NEW car is a clean slate, though — giving up once must not mean giving up forever.
local CAR2 = { name = "car2" }
VEH_LIVE = CAR2
Native.mount = function() walkCalls = walkCalls + 1; MOUNT_LANDS_AT = JL.clock + 0.4; return { cmd = true } end
frames(3.0)
check("a different car gets a fresh ladder", jlPassenger.mounted == true,
      "giving up on one car must not disable the feature for the rest of the save")

print("")
if fails > 0 then print(fails .. " FAILED"); os.exit(1) end
print("ALL PASS")
