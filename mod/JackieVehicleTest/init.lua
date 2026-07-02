--[[
  JackieVehicleTest — standalone CET harness for VEHICLE ARRIVAL (Jackie on his bike).
  ----------------------------------------------------------------------------
  SEPARATE mod (never edits JackieLives) so experiments can't clash with the working
  arrival code. Console lines are prefixed [JKVeh]. Red errors -> send to Claude.

  GOAL (Antonia's step plan, one button per step, press them IN ORDER):
    0) PROBE        - confirm the vehicle/mount API exists on this patch before anything else.
    1) Spawn bike + Jackie NEAR you (two separate buttons) so we see both entities exist.
    2) Mount Jackie onto the bike as DRIVER (seat_front_left).
    3) Spawn Jackie ALREADY on the bike (1+1+2 combined, near you).
    4) Make the bike DRIVE to a captured coordinate / to you.
    5) Unmount Jackie (get off the bike).
    6) Spawn Jackie on the bike AT DISTANCE and have him drive up to you.
    7) PASSENGER: seat Jackie in V's OWN car (front passenger) + drive around (mirror of driving).
    8) CRUISE: Jackie rides his Arch behind you (AI follow w/ useKinematic, or ghost-trail teleport).

  HOW THE PIECES WORK (verified against decompiled scripts + AMM source, patch 2.x):
    * Spawn      : Game.GetDynamicEntitySystem():CreateEntity(DynamicEntitySpec) - same path
                   AMM uses. recordID takes the TweakDB path string. Handle resolves a few
                   frames later, so we POLL Game.FindEntityByID(id) each onUpdate.
    * Mount      : AIMountCommand + MountEventData, slotName "seat_front_left" (= driver),
                   sent to the NPC via npc:GetAIControllerComponent():SendCommand(cmd).
                   (Exact recipe from AMM Modules/scan.lua Scan:AssignSeats.)
    * Drive      : AIVehicleDriveToPointAutonomousCommand wrapped in AINPCCommandEvent,
                   QueueEvent'd onto the VEHICLE handle (NOT the driver). targetPosition is a
                   Vector3. The base game's preventionSystem drives cars exactly this way.

  ⚠️ REALITY CHECK (important): the vanilla AI is built to drive CARS, not MOTORCYCLES - there
     are no AI motorcyclists in traffic, and no mod has achieved genuine AI bike-riding. So the
     bike may simply refuse to drive (sit still / fall over). That's why there's a BIKE/CAR
     toggle: if the bike won't drive, flip to CAR to PROVE the spawn->mount->drive pipeline
     works, then we decide how to fake the bike (e.g. scripted ride-along) for the real mod.
--]]

-- ── EDITABLE RECORDS ─────────────────────────────────────────────────────────
-- Jackie's Arch - LOCKED to the normal model (no cycling needed). Same record JackieLives uses.
local BIKE_RECORDS = {
  "Vehicle.v_sportbike2_arch_jackie_player",        -- Jackie's Arch (the normal one)
}
-- A CAR known to work for AI driving (fallback to prove the pipeline). If this record is wrong
-- on your build, the spawn will log a failure - tell Claude and we'll swap it.
local CAR_RECORDS = {
  "Vehicle.v_standard2_archer_quartz_player",
  "Vehicle.v_sport1_quadra_turbo_player",
}
local JACKIE_RECORD = "Character.Jackie"   -- same record JackieLives discovered

-- ── RIDE-IN TUNING (the "drive carefully, then get off and walk up" behaviour) ─
local SPEED_STEPS   = { 8, 12, 16, 22 }   -- cruise speeds the speed button cycles through
local DISMOUNT_DIST = 40.0   -- bike->V distance at which Jackie parks the bike + gets off
local SPRINT_TO_WALK = 25.0  -- Jackie->V distance where he downshifts sprint -> walk (last 25 m)
local ARRIVE_DIST   = 3.0    -- Jackie->V distance = arrived (on foot), stop here + become companion
-- stuck failsafe: bike crawling (< STUCK_SPEED) for STUCK_SUSTAIN s, after STUCK_GRACE s grace -> bail
local STUCK_SPEED   = 2.0
local STUCK_GRACE   = 5.0
local STUCK_SUSTAIN = 2.0
-- ─────────────────────────────────────────────────────────────────────────────

local V = {
  open = true, overlay = false, status = "",
  useCar = false,                 -- false = bike, true = car
  bikeIdx = 1, carIdx = 1,        -- which record in the lists above
  bike   = { id = nil, handle = nil },
  jackie = { id = nil, handle = nil },
  target = nil,                   -- captured Vector4 drive destination (nil -> drive to player)
  driveDist = 80.0,               -- step 6 spawn distance
  maxSpeed = 8.0,                 -- cruise speed for the drive command (cycle button changes it)
  arrival = { phase = nil, at = 0 },  -- tiny state machine for step 6 (spawn -> settle -> mount -> drive)
  -- ride-in machine: drive (slow) -> dismount+stop at DISMOUNT_DIST -> sprint -> walk -> stop near V
  ride = { phase = nil, lastReissue = -999, sprintAt = 0, cmd = nil },
  seatInstant = false,            -- step 7: false = play get-in anim (car stopped); true = teleport into seat
  seatUsed = nil,                 -- which passenger seat we last put Jackie in (for unmount)
  seatedJackie = nil,             -- the Jackie HANDLE we actually seated (so unmount works w/o look-at)
  seatedVeh = nil,                -- the vehicle handle he was seated in (V's car, remembered for unmount)
  ourSeating = true,              -- MASTER toggle for our passenger-seat code. Turn OFF to test whether
                                  --   AMM's own companion behaviour already seats/dismounts him -> if so,
                                  --   our code is redundant and can be deleted.
  -- STEP 8 bike cruise: Jackie's mounted Arch trails behind V.
  cruise = { on = false, mode = "follow", lastReissue = -999, cmd = nil },  -- mode: "follow" | "trail"
  cruiseTrailDist = 8.0,          -- ghost-trail mode: metres his bike stays behind V's vehicle
  clock = 0,
}

local function log(m) print("[JKVeh] " .. tostring(m)) end

-- ── small helpers ────────────────────────────────────────────────────────────
local function currentVehicleRecord()
  if V.useCar then return CAR_RECORDS[V.carIdx] or CAR_RECORDS[1] end
  return BIKE_RECORDS[V.bikeIdx] or BIKE_RECORDS[1]
end

local function player() return Game.GetPlayer() end

local function playerPos()
  local p = player(); if not p then return nil end
  local pos; pcall(function() pos = p:GetWorldPosition() end)
  return pos
end

local function dist3(a, b)
  if not a or not b then return nil end
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- A point `d` m ahead of V (or behind, if d<0 conceptually we pass a negative via caller).
local function pointAhead(d)
  local p = player(); if not p then return nil end
  local pp; pcall(function() pp = p:GetWorldPosition() end)
  if not pp then return nil end
  local fwd; pcall(function() fwd = p:GetWorldForward() end)
  if not fwd then return Vector4.new(pp.x + d, pp.y, pp.z, 1.0) end
  return Vector4.new(pp.x + fwd.x * d, pp.y + fwd.y * d, pp.z + fwd.z * d, 1.0)
end

-- Snap a candidate down onto the human navmesh (so the vehicle lands on ground, not floating).
local function snapToGround(candidate)
  if not candidate then return candidate end
  local nav = Game.GetNavigationSystem(); if not nav then return candidate end
  local origin = Vector4.new(candidate.x, candidate.y, candidate.z + 4.0, 1.0)
  local pt
  pcall(function() pt = nav:GetNearestNavmeshPointBelowOnlyHumanNavmesh(origin, 1.0, 12) end)
  if not pt or (pt.x == 0 and pt.y == 0 and pt.z == 0) then return candidate end
  local dx, dy = pt.x - candidate.x, pt.y - candidate.y
  if (dx * dx + dy * dy) > (8.0 * 8.0) then return candidate end
  return pt
end

-- A navmesh-ish point ~`distance` m BEHIND V at a RANDOM angle in the rear 180° arc (more
-- immersive than always dead-ahead). Sweeps a few headings/distances and snaps each to ground.
-- Ported from JackieLives' navmeshArrivalPoint (rear arc). Returns a Vector4.
local rngSeeded = false
local function rearArrivalPoint(distance)
  local p = player(); if not p then return nil end
  local pp; pcall(function() pp = p:GetWorldPosition() end)
  local fwd; pcall(function() fwd = p:GetWorldForward() end)
  if not pp or not fwd then return nil end
  if not rngSeeded then pcall(function() math.randomseed((os.time and os.time() or 0)) end); rngSeeded = true end
  local baseAng = math.atan2(fwd.y, fwd.x) + math.pi          -- directly behind V
  local jitter  = (math.random() * 180.0) - 90.0             -- random direction within the rear arc
  for _, df in ipairs({ 1.0, 0.8, 0.6 }) do
    local d = distance * df
    for _, deg in ipairs({ 0, 25, -25, 50, -50, 75, -75, 90, -90 }) do
      local rel = math.max(-90.0, math.min(90.0, jitter + deg))
      local a   = baseAng + math.rad(rel)
      local cand = Vector4.new(pp.x + math.cos(a) * d, pp.y + math.sin(a) * d, pp.z, 1.0)
      local snapped = snapToGround(cand)
      if snapped then return snapped end
    end
  end
  return snapToGround(Vector4.new(pp.x + math.cos(baseAng) * distance, pp.y + math.sin(baseAng) * distance, pp.z, 1.0))
end

-- Yaw (degrees) so an entity at `from` faces `to` (used so a distance-spawned bike points at V).
local function yawTowards(from, to)
  if not from or not to then return 0.0 end
  local ang = math.atan2(to.y - from.y, to.x - from.x)   -- radians, game yaw is degrees about Z
  return math.deg(ang) - 90.0                            -- -90: vehicle "forward" is +Y in its local frame
end

local function quatFromYaw(yawDeg)
  local q
  pcall(function() q = EulerAngles.new(0.0, 0.0, yawDeg or 0.0):ToQuat() end)
  return q
end

-- Build a command object, trying the 'handle:' form first then the bare form (CET accepts
-- different prefixes for different command classes across builds).
local function newCmd(name)
  local o
  pcall(function() o = NewObject('handle:' .. name) end)
  if not o then pcall(function() o = NewObject(name) end) end
  return o
end

-- ── spawning (DynamicEntitySystem - the path AMM wraps) ───────────────────────
local function spawnEntity(recordStr, pos, yawDeg, tag)
  local des = Game.GetDynamicEntitySystem()
  if not des then log("DynamicEntitySystem unavailable."); return nil end
  local id
  local ok, err = pcall(function()
    local spec = DynamicEntitySpec.new()
    spec.recordID      = recordStr                 -- string path; CET coerces to TweakDBID
    spec.appearanceName = "default"
    spec.position      = pos
    spec.orientation   = quatFromYaw(yawDeg)
    spec.persistState  = false
    spec.persistSpawn  = false
    spec.alwaysSpawned = false
    spec.spawnInView   = true
    spec.tags          = { CName.new(tag or "JackieVehicleTest") }
    id = des:CreateEntity(spec)
  end)
  if not ok or not id then log("CreateEntity FAILED for '" .. tostring(recordStr) .. "': " .. tostring(err)); return nil end
  log("CreateEntity '" .. tostring(recordStr) .. "' -> id queued (handle resolves shortly).")
  return id
end

local function spawnBike()
  local pos = snapToGround(pointAhead(5.5))
  if not pos then V.status = "No player position."; return end
  local yaw = yawTowards(pos, playerPos())   -- face V so it would drive toward you
  local rec = currentVehicleRecord()
  local id = spawnEntity(rec, pos, yaw, "JKVeh_bike")
  if id then
    V.bike.id, V.bike.handle = id, nil
    V.status = "Spawning " .. (V.useCar and "CAR" or "BIKE") .. " near you..."
  else
    V.status = "Bike spawn failed (see console)."
  end
end

local function spawnJackieNear()
  local pos = snapToGround(pointAhead(2.5))
  if not pos then V.status = "No player position."; return end
  local id = spawnEntity(JACKIE_RECORD, pos, 0.0, "JKVeh_jackie")
  if id then
    V.jackie.id, V.jackie.handle = id, nil
    V.status = "Spawning Jackie near you..."
  else
    V.status = "Jackie spawn failed (see console)."
  end
end

-- Make Jackie treat V as a friend so he doesn't react as a threat once spawned.
local function setFriendly(h)
  pcall(function()
    local p = player()
    if p and h and h.GetAttitudeAgent then
      h:GetAttitudeAgent():SetAttitudeTowards(p:GetAttitudeAgent(), EAIAttitude.AIA_Friendly)
    end
  end)
end

-- ── mount / unmount (AMM Scan:AssignSeats recipe) ─────────────────────────────
local function mountJackie(seat)
  local jh, vh = V.jackie.handle, V.bike.handle
  if not jh then V.status = "No Jackie handle yet (spawn him first)."; return end
  if not vh then V.status = "No vehicle handle yet (spawn the bike first)."; return end
  local ok, err = pcall(function()
    local cmd = newCmd('AIMountCommand')
    local md  = MountEventData.new()
    md.mountParentEntityId = vh:GetEntityID()
    md.isInstant = false
    md.setEntityVisibleWhenMountFinish = true
    md.removePitchRollRotationOnDismount = false
    md.ignoreHLS = false
    md.mountEventOptions = NewObject('handle:gameMountEventOptions')
    md.mountEventOptions.silentUnmount = false
    md.mountEventOptions.entityID = vh:GetEntityID()
    md.mountEventOptions.alive = true
    md.mountEventOptions.occupiedByNeutral = true
    md.slotName = seat or "seat_front_left"
    cmd.mountData = md
    cmd = cmd:Copy()
    jh:GetAIControllerComponent():SendCommand(cmd)
  end)
  V.status = "Mount Jackie -> " .. (ok and "command sent (watch him climb on)." or ("FAILED: " .. tostring(err)))
  log(V.status)
end

local function unmountJackie()
  local jh, vh = V.jackie.handle, V.bike.handle
  if not jh then V.status = "No Jackie handle."; return end
  local ok, err = pcall(function()
    local cmd = newCmd('AIUnmountCommand')
    local md  = MountEventData.new()
    if vh then md.mountParentEntityId = vh:GetEntityID() end
    md.isInstant = false
    md.setEntityVisibleWhenMountFinish = true
    md.mountEventOptions = NewObject('handle:gameMountEventOptions')
    md.mountEventOptions.silentUnmount = false
    if vh then md.mountEventOptions.entityID = vh:GetEntityID() end
    md.mountEventOptions.alive = true
    md.slotName = "seat_front_left"
    cmd.mountData = md
    cmd = cmd:Copy()
    jh:GetAIControllerComponent():SendCommand(cmd)
  end)
  V.status = "Unmount Jackie -> " .. (ok and "command sent (watch him get off)." or ("FAILED: " .. tostring(err)))
  log(V.status)
end

-- ── PASSENGER: seat Jackie in V's OWN car (front passenger) ───────────────────
-- Same AIMountCommand recipe as mountJackie, but the mount parent is V's CURRENT vehicle and
-- the seat is a passenger slot. Verified in docs/research/vehicle_passenger_research.md
-- (AMM Scan:AssignSeats + Util:GetMountedVehicleTarget + VehicleComponent::HasSlot).
local function playerVehicle()
  local qm; pcall(function() qm = player():GetQuickSlotsManager() end)
  local veh; if qm then pcall(function() veh = qm:GetVehicleObject() end) end
  return veh
end

local function hasSeat(veh, cname)
  local ok = false
  pcall(function()
    ok = Game['VehicleComponent::HasSlot;GameInstanceVehicleObjectCName'](veh, CName.new(cname))
  end)
  return ok
end

-- Front passenger preferred, then the back seats (4-seaters only). nil if none exist.
local PASSENGER_SEATS = { "seat_front_right", "seat_back_left", "seat_back_right" }
local function freePassengerSeat(veh)
  for _, c in ipairs(PASSENGER_SEATS) do if hasSeat(veh, c) then return c end end
  return nil
end

-- Jackie handle to seat: prefer the one THIS mod spawned (1b), else the NPC you're looking at
-- (so it also works on an AMM-summoned Jackie).
local function jackieForSeat()
  if V.jackie.handle then return V.jackie.handle end
  local p = player(); if not p then return nil end
  local t
  pcall(function()
    local ts = Game.GetTargetingSystem()
    if ts then t = ts:GetLookAtObject(p, false, false) end
  end)
  return t
end

local function seatJackieInPlayerCar()
  if not V.ourSeating then V.status = "Our seating is OFF (AMM should handle it)."; log(V.status); return end
  local jh  = jackieForSeat()
  local veh = playerVehicle()
  if not jh  then V.status = "No Jackie — spawn him (1b) or look at a summoned Jackie."; log(V.status); return end
  if not veh then V.status = "You're not in a vehicle — get in your car first."; log(V.status); return end
  local seat = freePassengerSeat(veh)
  if not seat then V.status = "No free passenger seat on this vehicle (2-seater full?)."; log(V.status); return end
  setFriendly(jh)
  local ok, err = pcall(function()
    local cmd = newCmd('AIMountCommand')
    local md  = MountEventData.new()
    md.mountParentEntityId = veh:GetEntityID()
    md.isInstant = V.seatInstant                 -- false = get-in anim (stop first); true = teleport
    md.setEntityVisibleWhenMountFinish = true
    md.removePitchRollRotationOnDismount = false
    md.ignoreHLS = false
    md.mountEventOptions = NewObject('handle:gameMountEventOptions')
    md.mountEventOptions.silentUnmount   = false
    md.mountEventOptions.entityID        = veh:GetEntityID()
    md.mountEventOptions.alive           = true
    md.mountEventOptions.occupiedByNeutral = true
    md.slotName = seat
    cmd.mountData = md
    cmd = cmd:Copy()
    jh:GetAIControllerComponent():SendCommand(cmd)
  end)
  V.seatUsed = seat
  if ok then V.seatedJackie, V.seatedVeh = jh, veh end   -- remember for unmount (works from driving cam)
  V.status = "Seat Jackie (" .. seat .. ") -> " .. (ok and "sent (look to your right)." or ("FAILED: " .. tostring(err)))
  log(V.status)
end

local function unmountPassenger()
  if not V.ourSeating then V.status = "Our seating is OFF (AMM should handle it)."; log(V.status); return end
  -- Prefer the handle we actually seated (V's driving camera has no look-at target, so
  -- jackieForSeat() would return nil here — that was the "No Jackie handle" bug).
  local jh  = V.seatedJackie or jackieForSeat()
  local veh = V.seatedVeh or playerVehicle() or V.bike.handle
  if not jh then V.status = "No seated Jackie to dismount."; log(V.status); return end
  local ok, err = pcall(function()
    local cmd = newCmd('AIUnmountCommand')
    local md  = MountEventData.new()
    if veh then md.mountParentEntityId = veh:GetEntityID() end
    md.isInstant = false
    md.setEntityVisibleWhenMountFinish = true
    md.mountEventOptions = NewObject('handle:gameMountEventOptions')
    md.mountEventOptions.silentUnmount = false
    if veh then md.mountEventOptions.entityID = veh:GetEntityID() end
    md.mountEventOptions.alive = true
    md.slotName = V.seatUsed or "seat_front_right"
    cmd.mountData = md
    cmd = cmd:Copy()
    jh:GetAIControllerComponent():SendCommand(cmd)
  end)
  V.status = "Unmount passenger (" .. (V.seatUsed or "seat_front_right") .. ") -> " .. (ok and "sent." or ("FAILED: " .. tostring(err)))
  log(V.status)
  if ok then V.seatedJackie, V.seatedVeh, V.seatUsed = nil, nil, nil end
end

-- ── STEP 8: bike CRUISE — Jackie's mounted Arch trails behind V ───────────────
-- PRIMARY = AI follow with useKinematic=true (AMM's Scan:SetDriverVehicleToFollow recipe): the
-- engine's own "bikes can't be physics-driven" workaround — a kinematic bike follows without wobble.
-- FALLBACK = ghost trail: teleport his bike to a point behind V's vehicle each frame (passes THROUGH
-- traffic, since collision never resolves — a vehicle hitbox CANNOT be disabled from CET on 2.x).
local function bikeFollowV()
  local bh = V.bike.handle
  local p  = player()
  if not (bh and p) then V.status = "No Jackie-bike (spawn Jackie on bike, step 3, first)."; log(V.status); return false end
  pcall(function() bh:TurnVehicleOn(true) end)
  local ok, err = pcall(function()
    local cmd = newCmd('AIVehicleFollowCommand')
    cmd.target = p                          -- V's PLAYER object (tracks his bike), NOT the vehicle
    cmd.distanceMin = 6.0
    cmd.distanceMax = 10.0
    pcall(function() cmd.secureTimeOut = 5.0 end)
    cmd.stopWhenTargetReached = false       -- keep cruising, never "arrive & park"
    cmd.useTraffic  = false                 -- don't lane-lock / wait at lights
    cmd.useKinematic = true                 -- KEY: bypass bike physics -> no wobble / fall
    pcall(function() cmd.needDriver = true end)
    cmd = cmd:Copy()
    V.cruise.cmd = cmd
    local evt = NewObject('handle:AINPCCommandEvent')
    evt.command = cmd
    bh:QueueEvent(evt)                       -- queue to the VEHICLE, not the driver
  end)
  if not ok then log("bikeFollowV FAILED: " .. tostring(err)) end
  return ok
end

-- Ghost-trail fallback: place his bike ~cruiseTrailDist m behind V's vehicle, matching V's heading.
-- Teleport the BIKE (mount parent) — the mounted Jackie rides along (OnTeleport doesn't eject him).
local function trailBehindV()
  local bh   = V.bike.handle
  local vVeh = playerVehicle()
  if not (bh and vVeh) then return end
  local pos, fwd
  pcall(function() pos = vVeh:GetWorldPosition() end)
  pcall(function() fwd = vVeh:GetWorldForward() end)
  if not (pos and fwd) then return end
  local d = V.cruiseTrailDist or 8.0
  local trail = Vector4.new(pos.x - fwd.x * d, pos.y - fwd.y * d, pos.z, 1.0)  -- behind V
  local yaw = math.deg(math.atan2(fwd.y, fwd.x)) - 90.0
  pcall(function() bh:TurnEngineOn(false) end)          -- reduce physics fighting the teleport
  pcall(function() Game.GetTeleportationFacility():Teleport(bh, trail, EulerAngles.new(0, 0, yaw)) end)
end

local function startCruise()
  if not V.bike.handle then V.status = "No Jackie-bike — spawn Jackie on his bike (STEP 3) first."; log(V.status); return end
  V.cruise.on, V.cruise.lastReissue = true, -999
  if V.cruise.mode == "follow" then
    bikeFollowV()
    V.status = "Cruise ON (AI follow + useKinematic). Get on your bike + ride — does his Arch trail you?"
  else
    V.status = "Cruise ON (ghost trail — his bike teleports behind you, through traffic)."
  end
  log(V.status)
end

local function stopCruise()
  V.cruise.on = false
  local bh = V.bike.handle
  if bh then
    pcall(function() if V.cruise.cmd then bh:StopExecutingCommand(V.cruise.cmd, true) end end)
    pcall(function() bh:TurnEngineOn(false) end)
  end
  V.cruise.cmd = nil
  V.status = "Cruise OFF."
  log(V.status)
end

-- Stepped from onUpdate.
local function cruiseTick()
  if not V.cruise.on or not V.bike.handle then return end
  if V.cruise.mode == "follow" then
    if (V.clock - V.cruise.lastReissue) >= 5.0 then    -- re-issue occasionally in case it drops
      V.cruise.lastReissue = V.clock
      bikeFollowV()
    end
  else
    trailBehindV()                                     -- every frame
  end
end

-- ── engine ────────────────────────────────────────────────────────────────────
local function engine(on)
  local vh = V.bike.handle
  if not vh then V.status = "No vehicle handle."; return end
  local any = false
  pcall(function() vh:TurnVehicleOn(on); any = true end)
  pcall(function() vh:TurnEngineOn(on) end)
  V.status = "Engine " .. (on and "ON" or "OFF") .. " -> " .. (any and "sent." or "method missing (see console).")
  log(V.status)
end

-- ── drive (AIVehicleDriveToPointAutonomousCommand -> queued to the VEHICLE) ────
local function makeVec3(v4)
  local v3
  pcall(function() v3 = Vector3.new(v4.x, v4.y, v4.z) end)
  if not v3 then pcall(function() v3 = ToVector3(v4) end) end
  return v3
end

-- quiet = true skips the status/log spam (used by the per-2s re-issue in the ride machine).
local function driveTo(destV4, quiet)
  local vh = V.bike.handle
  if not vh then if not quiet then V.status = "No vehicle handle (spawn the bike first)." end; return end
  if not destV4 then destV4 = playerPos() end
  if not destV4 then if not quiet then V.status = "No destination." end; return end
  pcall(function() vh:TurnVehicleOn(true) end)   -- ensure systems are live before driving
  local speed = V.maxSpeed or 12.0
  local ok, err = pcall(function()
    local cmd = newCmd('AIVehicleDriveToPointAutonomousCommand')
    cmd.targetPosition              = makeVec3(destV4)
    cmd.maxSpeed                    = speed
    cmd.minSpeed                    = math.min(4.0, speed)   -- gentle, not a crawl
    cmd.minimumDistanceToTarget     = 6.0
    cmd.clearTrafficOnPath          = false
    cmd.driveDownTheRoadIndefinitely = false
    pcall(function() cmd.needDriver = true end)
    cmd = cmd:Copy()
    V.ride.cmd = cmd                                          -- keep ref so we can stop the bike later
    local evt = NewObject('handle:AINPCCommandEvent')
    evt.command = cmd
    vh:QueueEvent(evt)
    pcall(function() vh:GetAIComponent():SetInitCmd(cmd) end)   -- base game also registers it
  end)
  if not quiet then
    V.status = "Drive command -> " .. (ok and ("queued (speed %.0f)."):format(speed) or ("FAILED: " .. tostring(err)))
    log(V.status .. "  dest={" .. string.format("%.1f,%.1f,%.1f", destV4.x, destV4.y, destV4.z) .. "}")
  end
end

-- Stop the bike where it is (so it doesn't run V over after Jackie dismounts).
local function stopBike()
  local vh = V.bike.handle; if not vh then return end
  pcall(function() if V.ride.cmd then vh:StopExecutingCommand(V.ride.cmd, true) end end)
  pcall(function() vh:TurnEngineOn(false) end)
  log("Ride: bike stopped.")
end

-- Send the (dismounted) Jackie on foot to a world point. Same AIMoveToCommand pattern as
-- JackieLives' walk-in. movementType: "Walk" | "Run" | "Sprint".
local function moveJackieTo(pos, movementType, desiredDist)
  local jh = V.jackie.handle
  if not jh or not pos then return false end
  local mt
  pcall(function() if moveMovementType and moveMovementType[movementType] ~= nil then mt = moveMovementType[movementType] end end)
  if mt == nil then pcall(function() mt = Enum.new("moveMovementType", movementType) end) end
  return (pcall(function()
    local dest = NewObject('WorldPosition'); dest:SetVector4(dest, pos)
    local spec = NewObject('AIPositionSpec'); spec:SetWorldPosition(spec, dest)
    local cmd = NewObject('handle:AIMoveToCommand')
    cmd.movementTarget               = spec
    cmd.movementType                 = mt or movementType
    cmd.ignoreNavigation             = false
    cmd.desiredDistanceFromTarget    = desiredDist or 1.5
    cmd.finishWhenDestinationReached = true
    jh:GetAIControllerComponent():SendCommand(cmd)
  end))
end

-- ── ride-in: drive carefully -> dismount + stop bike -> sprint -> walk -> stop ─
local function handlePos(h)
  if not h then return nil end
  local p; pcall(function() p = h:GetWorldPosition() end); return p
end

-- Kick off the full arrival behaviour (assumes Jackie is mounted on the bike).
local function startRideIn()
  if not (V.bike.handle and V.jackie.handle) then
    V.status = "Mount Jackie on the bike first (step 2/3) before ride-in."; log(V.status); return
  end
  V.ride.phase, V.ride.lastReissue = "driving", -999
  V.ride.startAt, V.ride.stuckTime, V.ride.lastBikePos, V.ride.lastSpeedT = V.clock, 0, nil, V.clock
  V.status = "Ride-in: driving toward you (parks + dismounts at " .. DISMOUNT_DIST .. " m)..."
  log(V.status)
end

-- Stepped from onUpdate.
local function rideTick()
  local r = V.ride
  if not r.phase then return end
  local pp = playerPos()
  if not pp then return end

  if r.phase == "driving" then
    if not V.bike.handle then r.phase = nil; return end
    local bp = handlePos(V.bike.handle)
    local d  = dist3(pp, bp)
    if (V.clock - r.lastReissue) >= 2.0 then r.lastReissue = V.clock; driveTo(pp, true) end  -- track a moving V
    -- stuck failsafe: crawling for STUCK_SUSTAIN s (after grace) -> bail off + sprint
    local stuck = false
    if bp and (V.clock - (r.startAt or 0)) >= STUCK_GRACE and (V.clock - (r.lastSpeedT or V.clock)) >= 1.0 then
      local dt    = V.clock - (r.lastSpeedT or V.clock)
      local moved = r.lastBikePos and dist3(bp, r.lastBikePos) or 999
      local spd   = (dt > 0) and (moved / dt) or 999
      r.stuckTime = (spd < STUCK_SPEED) and ((r.stuckTime or 0) + dt) or 0
      r.lastBikePos, r.lastSpeedT = bp, V.clock
      if (r.stuckTime or 0) >= STUCK_SUSTAIN then stuck = true end
    end
    if (d and d <= DISMOUNT_DIST) or stuck then
      stopBike()
      unmountJackie()
      r.phase, r.sprintAt, r.lastReissue = "sprinting", V.clock + 1.0, -999  -- let him get off, then run
      V.status = stuck and ("Ride-in: STUCK at %.0f m -> on foot."):format(d or 0)
                       or  ("Ride-in: parked at %.0f m -> sprinting in."):format(d or 0)
      log(V.status)
    end

  elseif r.phase == "sprinting" then
    if V.clock < (r.sprintAt or 0) then return end           -- brief beat to finish the dismount
    local d = dist3(pp, handlePos(V.jackie.handle))
    if (V.clock - r.lastReissue) >= 1.2 then r.lastReissue = V.clock; moveJackieTo(pp, "Sprint", 1.5) end
    if d and d <= SPRINT_TO_WALK then
      r.phase, r.lastReissue = "walking", -999
      V.status = ("Ride-in: %.0f m -> Jackie slows to a walk."):format(d); log(V.status)
    end

  elseif r.phase == "walking" then
    local d = dist3(pp, handlePos(V.jackie.handle))
    if (V.clock - r.lastReissue) >= 1.5 then r.lastReissue = V.clock; moveJackieTo(pp, "Walk", ARRIVE_DIST) end
    if d and d <= ARRIVE_DIST then
      r.phase = nil
      -- stop at 3 m + become a companion (best-effort; AMM may not adopt a DES-spawned NPC -
      -- the real companion handoff lives in JackieLives, this just proves the stop distance).
      local jh = V.jackie.handle
      pcall(function()
        local amm = GetMod("AppearanceMenuMod")
        if amm and amm.Spawn and amm.Spawn.SetNPCAsCompanion and jh then amm.Spawn:SetNPCAsCompanion(jh) end
      end)
      setFriendly(jh)
      V.status = "Ride-in: Jackie arrived on foot (stopped ~3 m, companion attempted)."; log(V.status)
    end
  end
end

-- ── despawn ───────────────────────────────────────────────────────────────────
local function deleteById(id)
  if not id then return end
  pcall(function()
    local des = Game.GetDynamicEntitySystem()
    if des then des:DeleteEntity(id) end
  end)
end

local function despawnAll()
  deleteById(V.jackie.id)
  deleteById(V.bike.id)
  V.jackie.id, V.jackie.handle = nil, nil
  V.bike.id, V.bike.handle = nil, nil
  V.arrival.phase = nil
  V.ride.phase, V.ride.cmd = nil, nil
  V.cruise.on, V.cruise.cmd = false, nil   -- stop cruise so no orphaned ghost-bike (Follower Jackster bug)
  V.status = "Despawned bike + Jackie."
  log(V.status)
end

-- ── capture drive target ──────────────────────────────────────────────────────
local function captureTarget()
  local pp = playerPos()
  if not pp then V.status = "No player position."; return end
  V.target = Vector4.new(pp.x, pp.y, pp.z, 1.0)
  V.status = string.format("Captured drive target { %.1f, %.1f, %.1f } (stand ON a road for driving).", pp.x, pp.y, pp.z)
  log(V.status)
end

-- ── PROBE: confirm every API name exists on this patch BEFORE we rely on it ────
local function probe()
  log("===== JKVeh PROBE =====")
  log("DynamicEntitySystem : " .. tostring(Game.GetDynamicEntitySystem() ~= nil))
  log("MountingFacility    : " .. tostring(Game.GetMountingFacility() ~= nil))
  local function ctor(label, fn)
    local ok = pcall(fn)
    log("  ctor " .. label .. " : " .. (ok and "OK" or "MISSING"))
  end
  ctor("DynamicEntitySpec",  function() return DynamicEntitySpec.new() end)
  ctor("MountEventData",     function() return MountEventData.new() end)
  ctor("AIMountCommand",     function() return newCmd('AIMountCommand') end)
  ctor("AIUnmountCommand",   function() return newCmd('AIUnmountCommand') end)
  ctor("AIVehicleDriveToPointAutonomousCommand", function() return newCmd('AIVehicleDriveToPointAutonomousCommand') end)
  ctor("AIVehicleFollowCommand", function() return newCmd('AIVehicleFollowCommand') end)
  ctor("AINPCCommandEvent",  function() return NewObject('handle:AINPCCommandEvent') end)
  ctor("Vector3",            function() return Vector3.new(0, 0, 0) end)
  -- passenger (step 7) API
  log("QuickSlotsManager   : " .. tostring((function() local q; pcall(function() q = player():GetQuickSlotsManager() end); return q ~= nil end)()))
  log("VehicleComponent::HasSlot : " .. tostring(Game['VehicleComponent::HasSlot;GameInstanceVehicleObjectCName'] ~= nil))
  log("player vehicle now  : " .. tostring(playerVehicle() ~= nil) .. " (get in a car to make this true)")
  V.status = "Probe done - paste the [JKVeh] lines to Claude (OK/MISSING tells us what works)."
  log("===== END PROBE =====")
end

-- ── combined flows ─────────────────────────────────────────────────────────────
-- Step 3: spawn the bike + Jackie near you, then auto-mount once both handles resolve.
local function spawnJackieOnBike()
  spawnBike()
  spawnJackieNear()
  V.arrival.phase = "near_mount"     -- onUpdate mounts him once both handles exist
  V.arrival.at = V.clock + 2.0
  V.status = "Spawning bike + Jackie near you; will auto-mount when both exist..."
end

-- Step 6: spawn the bike (with Jackie) at distance, then drive to V.
local function arrivalAtDistance()
  local pp = playerPos()
  if not pp then V.status = "No player position."; return end
  local pos = rearArrivalPoint(V.driveDist)   -- random angle BEHIND V (immersive)
  if not pos then V.status = "No spawn point."; return end
  local yaw = yawTowards(pos, pp)
  local rec = currentVehicleRecord()
  local bid = spawnEntity(rec, pos, yaw, "JKVeh_bike")
  -- spawn Jackie right next to the bike at distance (snap to ground beside it)
  local jpos = snapToGround(Vector4.new(pos.x + 1.5, pos.y, pos.z, 1.0))
  local jid = spawnEntity(JACKIE_RECORD, jpos, yaw, "JKVeh_jackie")
  if not bid or not jid then V.status = "Distance spawn failed (see console)."; return end
  V.bike.id, V.bike.handle = bid, nil
  V.jackie.id, V.jackie.handle = jid, nil
  V.arrival.phase = "dist_mount"
  V.arrival.at = V.clock + 2.0
  V.status = string.format("Spawned at %.0f m; mount + drive will auto-fire...", V.driveDist)
  log(V.status)
end

-- ── lifecycle ──────────────────────────────────────────────────────────────────
registerForEvent("onInit", function()
  log("Loaded. Press PROBE first. Records: bike='" .. BIKE_RECORDS[1] .. "', jackie='" .. JACKIE_RECORD .. "'.")
end)
registerForEvent("onOverlayOpen",  function() V.overlay = true end)
registerForEvent("onOverlayClose", function() V.overlay = false end)

registerForEvent("onUpdate", function(dt)
  V.clock = V.clock + dt
  -- resolve handles from queued entity ids
  if V.bike.id and not V.bike.handle then
    pcall(function() V.bike.handle = Game.FindEntityByID(V.bike.id) end)
    if V.bike.handle then log("Bike handle resolved.") end
  end
  if V.jackie.id and not V.jackie.handle then
    pcall(function() V.jackie.handle = Game.FindEntityByID(V.jackie.id) end)
    if V.jackie.handle then setFriendly(V.jackie.handle); log("Jackie handle resolved.") end
  end
  -- tiny state machine for the combined flows
  if V.arrival.phase and V.clock >= V.arrival.at then
    if V.arrival.phase == "near_mount" then
      if V.bike.handle and V.jackie.handle then
        pcall(function() engine(true) end)
        mountJackie("seat_front_left")
        V.arrival.phase = nil
      elseif V.clock > V.arrival.at + 8.0 then
        V.arrival.phase = nil; log("near_mount: handles never resolved (timeout).")
      end
    elseif V.arrival.phase == "dist_mount" then
      if V.bike.handle and V.jackie.handle then
        pcall(function() engine(true) end)
        mountJackie("seat_front_left")
        V.arrival.phase = "dist_drive"
        V.arrival.at = V.clock + 2.5     -- give the mount a moment, then drive
      elseif V.clock > V.arrival.at + 8.0 then
        V.arrival.phase = nil; log("dist_mount: handles never resolved (timeout).")
      end
    elseif V.arrival.phase == "dist_drive" then
      startRideIn()                      -- drive in carefully -> dismount -> walk up to you
      V.arrival.phase = nil
    end
  end
  pcall(rideTick)
  pcall(cruiseTick)
end)

registerForEvent("onShutdown", function() pcall(despawnAll) end)

registerForEvent("onDraw", function()
  if not V.overlay or not V.open then return end
  -- CAP the window height so it can't grow taller than the screen (which hid STEP 7/8 below the
  -- bottom edge with no way to scroll). SizeConstraints caps it even if a huge size was already
  -- saved in imgui.ini, forcing an INTERNAL scrollbar. (min 380x240, max 900x680.)
  pcall(function() ImGui.SetNextWindowSizeConstraints(380, 240, 900, 680) end)
  pcall(function() ImGui.SetNextWindowSize(460, 640, ImGuiCond.FirstUseEver) end)
  ImGui.Begin("Jackie Vehicle Test")

  -- live status read-out
  local pp = playerPos()
  local bd = (V.bike.handle and pp) and dist3(pp, (function() local x; pcall(function() x = V.bike.handle:GetWorldPosition() end); return x end)()) or nil
  ImGui.Text("Vehicle: " .. (V.useCar and ("CAR  [" .. (CAR_RECORDS[V.carIdx] or "?") .. "]") or ("BIKE [" .. (BIKE_RECORDS[V.bikeIdx] or "?") .. "]")))
  ImGui.Text("Bike handle: " .. (V.bike.handle and "ok" or (V.bike.id and "spawning..." or "-")) ..
             "   Jackie handle: " .. (V.jackie.handle and "ok" or (V.jackie.id and "spawning..." or "-")))
  if bd then ImGui.Text(string.format("Bike is %.1f m from you.", bd)) end
  ImGui.Text("Drive target: " .. (V.target and "captured" or "your live position") ..
             "   Ride phase: " .. tostring(V.ride.phase or "-"))
  ImGui.Separator()

  ImGui.Text("STEP 0 - verify the API exists on this patch:")
  if ImGui.Button("PROBE vehicle/mount API") then probe() end
  if ImGui.Button("Toggle vehicle: " .. (V.useCar and "CAR" or "BIKE")) then V.useCar = not V.useCar end
  ImGui.SameLine()
  if ImGui.Button("cycle record") then
    if V.useCar then V.carIdx = (V.carIdx % #CAR_RECORDS) + 1 else V.bikeIdx = (V.bikeIdx % #BIKE_RECORDS) + 1 end
  end
  ImGui.Separator()

  ImGui.Text("STEP 1 - spawn both near you (see they exist):")
  if ImGui.Button("1a) Spawn bike near me") then spawnBike() end
  ImGui.SameLine()
  if ImGui.Button("1b) Spawn Jackie near me") then spawnJackieNear() end
  ImGui.Separator()

  ImGui.Text("STEP 2 - put Jackie on the bike as DRIVER:")
  if ImGui.Button("2) Mount Jackie (driver seat)") then mountJackie("seat_front_left") end
  ImGui.Separator()

  ImGui.Text("STEP 3 - spawn Jackie ALREADY on the bike (near you):")
  if ImGui.Button("3) Spawn Jackie on bike") then spawnJackieOnBike() end
  ImGui.Separator()

  ImGui.Text("STEP 4 - make the bike DRIVE (stand on a road!):")
  if ImGui.Button(("Cruise speed: %.0f"):format(V.maxSpeed)) then
    local cur, nxt = V.maxSpeed, nil
    for i, s in ipairs(SPEED_STEPS) do if math.abs(s - cur) < 0.5 then nxt = SPEED_STEPS[(i % #SPEED_STEPS) + 1]; break end end
    V.maxSpeed = nxt or SPEED_STEPS[1]
  end
  ImGui.SameLine(); ImGui.TextWrapped("(lower = safer)")
  if ImGui.Button("Capture this spot as target") then captureTarget() end
  if ImGui.Button("4a) Drive to captured target (no dismount)") then driveTo(V.target) end
  if ImGui.Button("4b) RIDE to me (slow -> dismount @20m -> walk up)") then startRideIn() end
  if ImGui.Button("Engine ON") then engine(true) end
  ImGui.SameLine()
  if ImGui.Button("Engine OFF") then engine(false) end
  ImGui.Separator()

  ImGui.Text("STEP 5 - Jackie gets off the bike:")
  if ImGui.Button("5) Unmount Jackie") then unmountJackie() end
  ImGui.Separator()

  ImGui.Text("STEP 6 - spawn on bike at distance + ride up to you:")
  if ImGui.Button(("Distance: %.0f m"):format(V.driveDist)) then
    local steps, cur, nxt = { 20, 40, 60, 80, 100 }, V.driveDist, nil
    for i, s in ipairs(steps) do if math.abs(s - cur) < 0.5 then nxt = steps[(i % #steps) + 1]; break end end
    V.driveDist = nxt or 80
  end
  ImGui.SameLine()
  if ImGui.Button("6) Spawn at distance + ride in + dismount + walk") then arrivalAtDistance() end
  ImGui.Separator()

  ImGui.Text("STEP 7 - Jackie as PASSENGER in YOUR car:")
  local myVeh = playerVehicle()
  ImGui.Text("  In a vehicle: " .. (myVeh and "yes" or "no - get in your car") ..
             (V.seatUsed and ("   last seat: " .. V.seatUsed) or ""))
  -- MASTER TOGGLE: does AMM already seat/dismount a summoned Jackie on its own? Flip this OFF and
  -- ride around with a summoned Jackie: if he STILL gets in/out, AMM handles it and our code is dead.
  if ImGui.Button(V.ourSeating and "Our seating: ON  (click to test AMM-only)" or "Our seating: OFF (AMM handles it?)") then
    V.ourSeating = not V.ourSeating
    V.status = V.ourSeating and "Our passenger code ON." or "Our passenger code OFF - AMM should seat/dismount him."
    log(V.status)
  end
  V.seatInstant = ImGui.Checkbox("instant seat (teleport - use if seating while moving)", V.seatInstant)
  ImGui.TextWrapped("(unchecked = he plays the get-in animation; stop the car first for that)")
  if ImGui.Button("7a) Seat Jackie as passenger") then seatJackieInPlayerCar() end
  ImGui.SameLine()
  if ImGui.Button("7b) Unmount passenger") then unmountPassenger() end
  ImGui.Separator()

  ImGui.Text("STEP 8 - CRUISE: Jackie rides his Arch behind you:")
  ImGui.TextWrapped("First mount Jackie on his Arch (STEP 3). Then get on YOUR bike and START cruise.")
  if ImGui.Button("Cruise mode: " ..
      (V.cruise.mode == "follow" and "AI FOLLOW (useKinematic)" or "GHOST TRAIL (through traffic)")) then
    V.cruise.mode = (V.cruise.mode == "follow") and "trail" or "follow"
  end
  ImGui.TextWrapped("AI follow = proper AMM bike-follow (kinematic; may snag in heavy traffic). " ..
    "Ghost trail = teleports his bike behind you every frame -> passes THROUGH traffic (can jitter).")
  if V.cruise.mode == "trail" then
    V.cruiseTrailDist = ImGui.SliderFloat("trail distance (m)", V.cruiseTrailDist, 4.0, 15.0)
  end
  if ImGui.Button(V.cruise.on and "STOP cruise" or "START cruise") then
    if V.cruise.on then stopCruise() else startCruise() end
  end
  ImGui.TextWrapped("NOTE: a vehicle's hitbox CANNOT be disabled from CET on 2.x (engine limit). " ..
    "Ghost-trail is the workaround for 'don't let traffic block him'.")
  ImGui.Separator()

  if ImGui.Button("DESPAWN bike + Jackie") then despawnAll() end
  if V.status ~= "" then ImGui.TextWrapped("> " .. V.status) end
  ImGui.End()
end)

-- Hotkeys (bind in CET -> Bindings if you want them off the panel)
registerHotkey("jkv_probe",     "Vehicle: probe API",          function() probe() end)
registerHotkey("jkv_bike",      "Vehicle: spawn bike",         function() spawnBike() end)
registerHotkey("jkv_jackie",    "Vehicle: spawn Jackie",       function() spawnJackieNear() end)
registerHotkey("jkv_mount",     "Vehicle: mount Jackie",       function() mountJackie("seat_front_left") end)
registerHotkey("jkv_onbike",    "Vehicle: spawn Jackie on bike", function() spawnJackieOnBike() end)
registerHotkey("jkv_drive",     "Vehicle: ride to me (full)",  function() startRideIn() end)
registerHotkey("jkv_unmount",   "Vehicle: unmount Jackie",     function() unmountJackie() end)
registerHotkey("jkv_arrive",    "Vehicle: arrive at distance", function() arrivalAtDistance() end)
registerHotkey("jkv_seat",      "Vehicle: seat Jackie passenger", function() seatJackieInPlayerCar() end)
registerHotkey("jkv_unseat",    "Vehicle: unmount passenger",     function() unmountPassenger() end)
registerHotkey("jkv_cruise",    "Vehicle: toggle bike cruise", function() if V.cruise.on then stopCruise() else startCruise() end end)
registerHotkey("jkv_despawn",   "Vehicle: despawn all",        function() despawnAll() end)
