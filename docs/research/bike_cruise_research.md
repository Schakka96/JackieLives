# Jackie bike-cruise (rides his Arch alongside V) — verified research

Research for JackieLives, patch 2.x (CET/Lua + AMM). Goal: after Jackie is mounted on his Arch
(driver, `seat_front_left`), his bike **trails behind V** while V rides. Implemented as STEP 8 in
`mod/JackieVehicleTest/init.lua`. API verified against AMM source, decompiled scripts, NativeDB.

## Verdict / recommendation

**Primary path = AI follow with `useKinematic = true`** (AMM's shipping bike-follow recipe). This is
the engine's own workaround for "bikes can't be full-physics-driven" — a kinematic bike follows a
target without wobble/topple. **Fallback = kinematic ghost-trail** (per-frame teleport the bike behind
V). **Disabling a vehicle's collision/hitbox from Lua is NOT possible on 2.x** — the ghost-trail is
the practical "pass through traffic" answer.

> ⚠️ This **corrects `vehicle_arrival_research.md`**: "no mod has achieved genuine AI bike-riding" is
> too strong. `Bike` is a first-class `gamedataVehicleType`; AMM's follow code special-cases bikes and
> drives them via `useKinematic`; "Roaming Motorcycles" (Nexus 13894) makes traffic AI ride bikes. The
> real blocker was only *full-physics* AI driving, which `useKinematic` bypasses. Try AI-follow first.

## 1. `AIVehicleFollowCommand` + `useKinematic` (primary)

Fields (verbatim from `scripts/core/ai/aiCommand.script`, `AIVehicleFollowCommand extends AIVehicleCommand`):

```
target                       : weak<GameObject>   // V's PLAYER object, NOT the vehicle
secureTimeOut                : Float
distanceMin / distanceMax    : Float
stopWhenTargetReached        : Bool
useTraffic                   : Bool
trafficTryNeighborsForStart / ...End : Bool
// inherited from AIVehicleCommand:
useKinematic                 : Bool   // KEY: spline/path solver, bypass rigidbody -> bike won't fall
needDriver                   : Bool
```

- **`target` = `Game.GetPlayer()`** (V is mounted, so the player object tracks his bike). Confirmed by
  AMM (`cmd.target = AMM.player`) and game `aiVehicle.swift`.
- **Dispatch:** build `handle:AIVehicleFollowCommand`, `:Copy()`, wrap in `handle:AINPCCommandEvent`,
  `QueueEvent` onto the **VEHICLE** handle (Jackie's bike, the mount parent). **No `SetInitCmd`.**

```lua
local function bikeFollowV(bikeHandle)
  local p = Game.GetPlayer()
  if not (bikeHandle and p) then return false end
  pcall(function() bikeHandle:TurnVehicleOn(true) end)
  return (pcall(function()
    local cmd = NewObject("handle:AIVehicleFollowCommand")
    cmd.target = p                       -- V's PLAYER object (tracks his bike), NOT the vehicle
    cmd.distanceMin = 6.0
    cmd.distanceMax = 10.0
    cmd.stopWhenTargetReached = false    -- keep cruising, never park
    cmd.useTraffic  = false              -- don't lane-lock / wait at lights
    cmd.useKinematic = true              -- bypass bike physics -> no wobble/fall
    cmd.needDriver  = true
    cmd = cmd:Copy()
    local evt = NewObject("handle:AINPCCommandEvent"); evt.command = cmd
    bikeHandle:QueueEvent(evt)           -- queue to the VEHICLE, not the driver
  end))
end
```

## 2. AMM's bike-follow to copy

`Modules/scan.lua` → **`Scan:SetDriverVehicleToFollow(driver)`** (~L913). It special-cases
`vehicleClass == "vehicleBikeBaseObject"` (a lone bike gets a tighter follow distance) and issues the
exact command above. Proof AMM's follow is intended to and does move bikes. Requires the mount pipeline
first (`Scan:AssignSeats` → `seat_front_left`), which our `mountJackie()` already replicates.

## 3. Disable collision / hitbox — NOT possible from Lua on 2.x

- The only runtime collision toggle, `entPhysicalMeshComponent.ToggleCollision(Bool)`, lives on a
  visual mesh sub-component. A vehicle's real collider is `entColliderComponent`, which has **no**
  scriptable disable. `useKinematic` bodies still collide. No verified Lua makes a vehicle phase
  through traffic.
- A mounted rider's collision is subsumed by the vehicle bounds, so he needs no separate toggle.
- **Do instead:** `useKinematic = true` + `useTraffic = false` (routes along the road, pushes/clips
  rather than crashing), or the ghost-trail below. True hitbox-off needs an archive edit (strip the
  chassis `.phys`), which breaks normal drivability — not worth it.

## 4. Kinematic ghost-trail (fallback)

Works mechanically; jitter-prone (physics keeps integrating gravity between teleports). Use only if
AI-follow won't move the bike in-game.

- **Teleport the VEHICLE (mount parent), never the NPC** — `VehicleObject.OnTeleport()` only cancels
  auto-drive; it does **not** eject occupants, so the mounted Jackie rides along.
- Mover: `Game.GetTeleportationFacility():Teleport(gameObject, Vector4, EulerAngles)`.

```lua
local TRAIL_DIST = 8.0
local function trailBehindV(bikeHandle)
  local vVeh = playerVehicle(); if not (vVeh and bikeHandle) then return end
  local p, f = vVeh:GetWorldPosition(), vVeh:GetWorldForward()
  local trail = Vector4.new(p.x - f.x*TRAIL_DIST, p.y - f.y*TRAIL_DIST, p.z, 1.0)  -- behind V
  local yaw = math.deg(math.atan2(f.y, f.x)) - 90.0
  pcall(function() bikeHandle:TurnEngineOn(false) end)   -- reduce physics fighting the teleport
  pcall(function() Game.GetTeleportationFacility():Teleport(bikeHandle, trail, EulerAngles.new(0,0,yaw)) end)
end
```

Tuning if it jitters: snap `trail.z` to V's z each frame; keep the engine off.

## 5. Cleanup gotcha (Follower Jackster, Nexus 24399)

**Despawn Jackie's bike when Jackie despawns** — Follower Jackster's shipped bug was a save-breaking
orphaned ghost bike from not deleting the ride-along. Our `despawnAll()` deletes `V.bike.id` and now
also clears the cruise state.

## Sources
- `scripts/core/ai/aiCommand.script` (fields), `aiVehicle.swift` (dispatch/target) —
  github.com/CDPR-Modding-Documentation/Cyberpunk-Scripts.
- AMM `Modules/scan.lua` `Scan:SetDriverVehicleToFollow`, `Modules/util.lua` (`Teleport`) —
  github.com/MaximiliumM/appearancemenumod.
- Collision: NativeDB `entPhysicalMeshComponent` (has `ToggleCollision`) vs `entColliderComponent`
  (none); patch-2.31 photo-mode NPC-collision note.
- Bike-AI feasibility: Nexus 13894 (Roaming Motorcycles), 24399 (Follower Jackster); Let There Be
  Flight (github.com/jackhumbert/let_there_be_flight, uses PhysX force — not pure Lua).
