# Vehicle arrival (Jackie on his bike) — research & test plan

Goal: Jackie arrives by vehicle — spawn him on a bike at distance, have him ride up to V, then
get off. Built as a **standalone test mod** `mod/JackieVehicleTest/` (never touches JackieLives)
with one button per step, pressed in order. API names below are verified against the decompiled
game scripts (codeberg.org/adamsmasher/cyberpunk @ 2.31), NativeDB, and AMM's shipping Lua.
Verify in the CET console on patch 2.3 before relying on any one call.

---

## TL;DR — the three mechanisms

1. **Spawn** — `Game.GetDynamicEntitySystem():CreateEntity(DynamicEntitySpec)`. `spec.recordID`
   takes the TweakDB **path string** directly (AMM assigns a string too). The entity HANDLE
   resolves a few frames later, so poll `Game.FindEntityByID(id)` each `onUpdate`.
2. **Mount (driver)** — `AIMountCommand` + `MountEventData`, `slotName = "seat_front_left"`
   (= driver), sent to the NPC via `npc:GetAIControllerComponent():SendCommand(cmd)`. Exact
   recipe lifted from AMM `Modules/scan.lua` → `Scan:AssignSeats`. `cmd:Copy()` before sending.
3. **Drive** — `AIVehicleDriveToPointAutonomousCommand` wrapped in `AINPCCommandEvent`, then
   **`vehicleHandle:QueueEvent(evt)`**. The command goes to the **VEHICLE, not the driver** — the
   driver's `AIControllerComponent` only accepts on-foot commands. The base game's
   `preventionSystem` drives cars exactly this way.

---

## ⚠️ The big caveat: vanilla AI does NOT drive motorcycles

This is the single most important feasibility fact, and it directly affects the plan:

- There are **no AI motorcyclists in traffic**, and **no mod has achieved genuine AI bike-riding**.
  CDPR's quest director (Paweł Sasko) publicly called free-roam vehicle AI a limitation they
  "didn't manage to make." The "Follower Jackster" mod **faked** Jackie-on-a-bike as a pinned
  ride-along (and hit orphaned-bike cleanup bugs).
- Jackie's **prologue bike intro is a binary `.scene`/`.quest`** — not in the script repo, can't be
  extracted or replayed from CET. It's a hand-authored cutscene, not a reusable system.

**Implication for the test mod:** the bike may simply refuse to drive (sit still / topple). That's
expected, not a bug in our code. The mod therefore has a **BIKE ⇄ CAR toggle**:
- Test the bike first (Antonia wants the bike).
- If it won't drive, flip to CAR — if a car drives the spawn→mount→drive pipeline is PROVEN, and the
  problem is isolated to motorcycle AI. Then the real mod's bike arrival must be **faked**: spawn the
  bike already near V (or just out of sight) and play a short scripted ride-in / dismount, rather than
  a genuine 80 m autonomous ride. We confirm which path with the buttons before writing any of it.

---

## Verified command reference (patch 2.x)

### Drive command — `AIVehicleDriveToPointAutonomousCommand` (extends `AIVehicleCommand`)
```
targetPosition               : Vector3   // NOTE: Vector3, not Vector4
maxSpeed                     : Float
minSpeed                     : Float
clearTrafficOnPath           : Bool
minimumDistanceToTarget      : Float
forcedStartSpeed             : Float
driveDownTheRoadIndefinitely : Bool
// inherited: useKinematic: Bool ; needDriver: Bool
```
Dispatch (to the vehicle):
```lua
local cmd = NewObject('handle:AIVehicleDriveToPointAutonomousCommand')
cmd.targetPosition           = Vector3.new(dest.x, dest.y, dest.z)
cmd.maxSpeed                 = 18.0
cmd.minSpeed                 = 6.0
cmd.minimumDistanceToTarget  = 6.0
cmd.clearTrafficOnPath       = false
cmd.driveDownTheRoadIndefinitely = false
cmd.needDriver               = true
cmd = cmd:Copy()
local evt = NewObject('handle:AINPCCommandEvent'); evt.command = cmd
vehicle:QueueEvent(evt)
pcall(function() vehicle:GetAIComponent():SetInitCmd(cmd) end)   -- base game also does this
```

### Exists / does NOT exist
| Class | Verdict |
|---|---|
| `AIVehicleDriveToPointAutonomousCommand` | **EXISTS** — drive to a raw coordinate |
| `AIVehicleToNodeCommand` | EXISTS — drives to a `NodeRef` via traffic lanes (AMM's tested path) |
| `AIVehicleFollowCommand` | EXISTS — `target: wref<GameObject>`, `distanceMin/Max`, `stopWhenTargetReached`, `useTraffic` |
| `AIVehicleJoinTrafficCommand` | EXISTS — no fields |
| `AIVehicleDriveToPointCombatCommand` | **DOES NOT EXIST** |
| `AIVehicleToLocationCommand` | **DOES NOT EXIST** |
| `AIVehicleStopCommand` | **DOES NOT EXIST** — stop via `vehicle:StopExecutingCommand(cmd, true)` |

### Mount — `AIMountCommand` + `MountEventData` (AMM recipe)
`slotName = "seat_front_left"` is the driver seat. Send to the NPC's AIControllerComponent.
Unmount = the same with `AIUnmountCommand`.

### Engine
`vehicle:TurnVehicleOn(true)` (AMM's `ToggleEngine` idiom) and/or `vehicle:TurnEngineOn(true)`.
`ToggleVehicleSystems` is `protected` (not callable from Lua); `PutVehicleOnGround` /
`TurnOnVehicleSystems` do NOT exist.

### Jackie's Arch records (verified — it's `sportbike2`, not `sport2`/`nazare`/`apollo`)
- `Vehicle.v_sportbike2_arch_jackie_player` — Jackie's Arch
- `Vehicle.v_sportbike2_arch_jackie_tuned_player` — tuned variant
- `Vehicle.v_sportbike2_arch_player` — standard Nazaré

---

## Gotchas (verified)
- **Must mount a driver first.** The AI drive task bails on `if !VehicleComponent.IsDriver(...)`.
  No "DriverCombat role" is needed (that's the mounted-weapon system) — what matters is being in
  `seat_front_left`.
- **Replicate `needDriver` + `SetInitCmd`.** A hand-mounted (CET) driver may not be registered with
  the vehicle's `AIVehicleAgent` otherwise. **This is the most likely failure point — test it.**
- **Road/lane-bound.** AI driving follows driving lanes. Spawn the vehicle on a drivable road and
  pick a `targetPosition` on the road network, inside the streamed bubble.

---

## Test order (buttons in JackieVehicleTest)
0. **PROBE** — confirms every ctor above exists on this patch (OK/MISSING). Run first.
1. **Spawn bike / Spawn Jackie** near V (prove both entities exist).
2. **Mount Jackie** (driver seat) — does he climb on?
3. **Spawn Jackie on bike** (1+1+2 combined, auto-mount).
4. **Drive to captured spot / to me** (stand on a road!). Does the vehicle MOVE? (bike likely won't.)
5. **Unmount** — does he get off cleanly?
6. **Spawn at distance + drive to me** — the full arrival. Distance toggle 20/40/60/80/100 m.

If step 4 fails on the bike but works on the car (toggle), the pipeline is proven and the bike must
be faked. That decision waits on the in-game result — don't pre-build either way.

## Sources
- Decompiled scripts: codeberg.org/adamsmasher/cyberpunk @ 2.31 — `orphans.swift`,
  `core/systems/preventionSystem.swift`, `core/systems/autoDriveSystem.swift`,
  `core/components/aiComponent.swift`, `cyberpunk/ai/Tasks/aiVehicle.swift`, `vehicleComponent.swift`.
- AMM source: `MaximiliumM/appearancemenumod` — `Modules/scan.lua` (mount), `Modules/spawn.lua` (vehicle spawn).
- NativeDB (RTTI verification): nativedb.red4ext.com.
- Motorcycle-AI limits: Nexus 13894 (Roaming Motorcycles), 24399 (Follower Jackster); TheGamer Sasko interview.
