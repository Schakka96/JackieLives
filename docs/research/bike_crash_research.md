# Why Jackie crashes his bike — and why "turn the collisions off" isn't the fix

Research for JackieLives, patch 2.x (CET/Lua). Verified against the CDPR script decompile
(`CDPR-Modding-Documentation/Cyberpunk-Scripts`), the RTTI component hierarchy dump, and AMM source.
Implemented as `Config.bikePhysics` + `jlBikeKnockOff` / `jlBikeGodMode` / `jlCruiseRightingTick`.

## Verdict

**The bike's collider CANNOT be disabled from Lua — and that was never the real problem.**

Jackie isn't crashing because his bike collides with things. He's crashing because the engine has a
*dedicated mechanic* that deliberately throws NPC riders off bikes when they're bumped hard enough.
It fires long before any "crash" damage, and it is a single TweakDB float.

## 1. The real cause — `HandleBikeCollisionReaction`

From `scripts/core/components/scriptComponents/vehicleComponent.script` (CONFIRMED, verbatim shape):

```
knockDownModifier = TweakDBInterface.GetFloat( T"AIGeneralSettings.aiBikeKnockOffModifier", 1.0 );
knockOffForce     = vehicleDataPackage.KnockOffForce() * ( (NPCPuppet)driver ? knockDownModifier : 1.0 );

if( ( impactVelocityChange > knockOffForce ) || IsBeingDragged() )
{
    ... ForceRagdollEvent -> UnmountFromVehicle('Bumped')
        -> QueueEvent(KnockOverBikeEvent) -> QueueEvent(AIEvent 'NoDriver');
}
```

Read that carefully:

- The multiplier is applied **only when the driver is an `NPCPuppet`** — i.e. exactly Jackie, never V.
  Vanilla NPC bike riders are *meant* to be easy to knock off; V isn't.
- Any impact whose `impactVelocityChange` exceeds the threshold **force-ragdolls Jackie off the bike**,
  knocks the bike over, and fires `AIEvent 'NoDriver'` — which kills the follow command.
- **This code path contains no god-mode check.** Invulnerability does **not** stop it. (The *damage*
  paths in the same file do call `HasGodMode(...)`; this one doesn't.)

That last point matters: the obvious fix (god-mode the bike) provably cannot work on its own.

### Symptom match
Our arrival state machine already had a failsafe for this without knowing what it was —
`init.lua`'s "Jackie NOT on the bike (%.1f m from it) -> ditch bike, he comes on foot". That is
precisely what a knock-off looks like from the outside: he's suddenly several metres from a bike that's
still rolling. The "stuck failsafe" catches the aftermath, not the cause.

## 2. Why collision-off is impossible (confirms `bike_cruise_research.md` §3)

- The only scriptable collision toggle is `PhysicalMeshComponent.ToggleCollision(enabled: Bool)`
  (`scripts/core/components/physicalMeshComponent.script`).
- Hierarchy (CONFIRMED, RTTI dump):
  - `entPhysicalMeshComponent` ← `entMeshComponent` ← `entIVisualComponent` ← `entIPlacedComponent`
  - `vehicleChassisComponent` ← **`entIPlacedComponent`** (direct)
  - `entColliderComponent`    ← **`entIPlacedComponent`** (direct)

  The chassis and the real colliders sit on a *different branch* from the mesh component, so
  `ToggleCollision` is not reachable on them. Neither collider class exposes any disable.
- No `SetCollision` / `EnableCollision` / `SetIsCollisionEnabled` / `SetKinematic` /
  `physicsCollisionMask` exists anywhere in the script dump.
- `entIComponent.Toggle(Bool)` exists (AMM uses it to hide *mesh* components). Calling it on a chassis
  or collider is **untested and likely drops the bike through the world**. Not attempted.

So: no mod disables vehicle collision, because none can.

## 3. `useKinematic` / `useTraffic` are NOT the bug

AMM's own bike follower (`Modules/scan.lua` → `Scan:SetDriverVehicleToFollow`) ships the **exact**
config we already use: `useKinematic = true`, `useTraffic = false`, `needDriver = true`,
`stopWhenTargetReached = false`, `:Copy()` before queueing to the vehicle. Our command setup is the
community-blessed default and was not the cause. Do not "fix" it blindly.

- `useTraffic = true` would route him along road lanes instead of beelining — plausible crash reducer,
  but it needs valid nav lanes and stops him hugging V. AMM deliberately keeps it `false`. **Untested.**
- Whether `useKinematic = true` suppresses collision *response* is **UNVERIFIED**. It clearly reduces
  wobble/topple (that's why AMM uses it) but does not make the bike a ghost.
- The arrival ride-in (`driveBikeTo`, `AIVehicleDriveToPointAutonomousCommand`) does **not** set
  `useKinematic`, and sets `clearTrafficOnPath = false`. Both are inherited/real fields and are valid
  knobs — but arrival is confirmed-good in-game today, so they're left alone rather than risk a
  regression. Revisit only if arrivals still topple after the knock-off fix.

## 4. What we shipped (v1.41)

Ranked by how directly it attacks the confirmed cause.

1. **Raise the knock-off threshold** — `jlBikeKnockOff(true/false)`.
   ```lua
   TweakDB:SetFlat("AIGeneralSettings.aiBikeKnockOffModifier", 1000.0)
   ```
   This is the fix. It multiplies the force needed to throw an NPC off a bike.
   - The flat is **global** (it governs every NPC bike rider in the city), so it's **ref-counted**:
     raised when Jackie's Arch spawns (arrival *or* cruise), restored to the **captured original** when
     the last one despawns — never hard-coded back to `1.0`, so a co-installed mod that tuned it isn't
     clobbered. Also force-restored in `onShutdown`.
   - Reads the flat first and no-ops with a log line if it can't (renamed record on a future patch)
     rather than writing blind.
   - Magnitude is **UNVERIFIED** — tune `Config.bikePhysics.knockOffModifier` in-game.

2. **God-mode the Arch** — `jlBikeGodMode(veh)`, `AddGodMode(id, gameGodModeType.Invulnerable, ...)`.
   Stops a hard hit *destroying* the bike (a destroyed bike strands him). Confirmed API; AMM does the
   same for spawned entities. Explicitly does **not** stop knock-off.

3. **Flip / thrown recovery** — `jlCruiseRightingTick()`. `IsBeingDragged()` bypasses the threshold
   entirely, so a safety net is still needed. Once a second, if `bh:IsFlippedOver()` (fallback:
   `GetWorldUp().z < 0.4`, the engine's own `ComputeIsVehicleUpsideDown` test) **or** Jackie is no
   longer mounted: teleport the bike upright behind V, `PhysicsWakeUp()`, re-mount him, re-issue the
   follow. Rate-limited (4 s) so a bike wedged in a wall can't teleport-thrash.

## Confirmed API reference

```
// vehicles.script  (VehicleObject)
public import const final function IsFlippedOver() : Bool;
public import const final function IsInAir() : Bool;
public import final function GetLinearVelocity() : Vector4;
public import final function PhysicsWakeUp();
public function ComputeIsVehicleUpsideDown() : Bool { return Vector4.Dot(GetWorldUp(), Vector4.UP()) < 0.0; }

// godModeSystem.script
public import function AddGodMode( entID : EntityID, gmType : gameGodModeType, sourceInfo : CName ) : Bool;
// enum gameGodModeType { Invulnerable, Immortal, Mortal }

// physicalMeshComponent.script  — the ONLY collision toggle, and NOT on a vehicle chassis
public import function ToggleCollision( enabled : Bool );

// aiCommand.script
class AIVehicleFollowCommand extends AIVehicleCommand {
  target : weak<GameObject>; secureTimeOut : Float; distanceMin : Float; distanceMax : Float;
  stopWhenTargetReached : Bool; useTraffic : Bool;
  trafficTryNeighborsForStart : Bool; trafficTryNeighborsForEnd : Bool;
}
// base AIVehicleCommand: useKinematic : Bool; needDriver : Bool;
```

`AIVehicleOnSpotCommand` does **not exist** in 2.x. For following a moving player,
`AIVehicleFollowCommand` is the correct class; the siblings (`AIVehicleToNodeCommand`,
`AIVehicleRacingCommand`, `AIVehicleOnSplineCommand`, …) all need a node/spline/destination.

## Still to verify in-game (Windows)

1. That `AIGeneralSettings.aiBikeKnockOffModifier` is readable **and writable** under exactly that ID on
   the installed patch. The CET console will say so: `print(TweakDB:GetFlat("AIGeneralSettings.aiBikeKnockOffModifier"))`
   — expect `1.0`. Our code logs `"knock-off modifier unreadable -> SKIPPED"` if not.
2. Whether `1000.0` is the right magnitude, or whether it makes him feel unnaturally glued.
3. Whether the righting tick ever fires once (1) is in place — if it fires constantly, something else
   is wrong.
4. Side-effect check: while Jackie is riding, *other* NPC bikers are also un-knock-off-able. Ref-counting
   keeps the window as small as possible, but it is not zero. Watch for weirdness in traffic during a cruise.

## Sources

- `vehicleComponent.script`, `physicalMeshComponent.script`, `component.script`, `godModeSystem.script`,
  `statsData.script`, `vehicles.script`, `aiCommand.script` —
  https://github.com/CDPR-Modding-Documentation/Cyberpunk-Scripts
- Component hierarchy —
  https://github.com/CDPR-Modding-Documentation/Cyberpunk-Modding-Docs/blob/main/for-mod-creators-theory/files-and-what-they-do/components/comprehensive-components-list.md
- AMM (`Modules/scan.lua`, `util.lua`, `spawn.lua`) — https://github.com/MaximiliumM/appearancemenumod
- CET teleport reference — https://wiki.redmodding.org/cyber-engine-tweaks/console/console/how-do-i
