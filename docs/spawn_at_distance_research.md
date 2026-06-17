# Spawn-at-distance + "don't get stuck" — research & plan

Research for the holocall arrival (v0.28): call Jackie → he spawns ahead of V and walks in.
All API names below are **verified against the decompiled game scripts**
(codeberg.org/adamsmasher/cyberpunk) and AMM's shipping Lua. Stable across the 2.x line; verify
in the CET console on patch 2.3 before relying on any one call.

---

## TL;DR — why the current arrival can land Jackie in a wall

The current flow (`init.lua` `arrivalTick` + `teleportEntity`) is:

1. `ammSpawn(1)` — AMM places him **1 m from the player** (AMM just offsets along the player's
   forward vector and reuses the player's Z; **no navmesh, no collision check** — confirmed in
   AMM `Modules/util.lua` `GetPosition`).
2. ~0.8 s later, `GetTeleportationFacility():Teleport(handle, arrivalPoint(), ...)` to 18 m ahead.

**The teleport facility is NAIVE** — it drops the entity at the *exact* coordinates with **no
navmesh projection and no `doNavTest` flag**. So if "18 m along V's facing" lands inside a
building, a parked car, a fence, or another NPC, that's exactly where he ends up → stuck / T-pose /
possible crash. Antonia's worry is real and is a property of *this specific call*.

So there are two separate things to fix:
- **(A) Choose a guaranteed-walkable arrival point** (don't blindly go 18 m along forward).
- **(B) Give him the "get-unstuck" power for a few seconds** as a safety net.

Both are real engine features. Recommended: do **both** (cheap, and they cover each other).

---

## (A) Pick a SAFE arrival point — reuse the game's navmesh

Two navmesh systems are reachable; either works. Prefer #1 (purpose-built for "a point N metres
away from a reference").

**1. `Game.GetNavigationSystem()` — `NavigationSystem`** (`core/systems/navigationSystem.swift`)

```
FindNavmeshPointAwayFromReferencePoint(
    pos: Vector4, refPos: Vector4, distance: Float,
    agentSize: NavGenAgentSize, out destination: Vector4,
    opt distanceTolerance: Float, opt angleTolerance: Float) -> Bool
```
Pass `pos` = a point in front of V, `refPos` = V's position, `distance` = ~18. Returns a
guaranteed-walkable `destination`. Returns `false` if it can't find one → then **retry with a
different facing** (left / right / behind) or shrink the distance, instead of spawning blind.

Also useful on the same system:
- `GetNearestNavmeshPointBelowOnlyHumanNavmesh(origin, radius, numSpheres) -> Vector4` — snap Z to
  the floor.
- `IsNavmeshStreamedInLocation(origin, tolerance, ...) -> Bool` — is the navmesh even loaded there?

**2. `Game.GetAINavigationSystem()` — `AINavigationSystem`** (`cyberpunk/ai/aiNavigationSystem.swift`)

```
IsPointOnNavmesh(character, point, tolerance: Vector4, out navmeshPoint) -> Bool
GetNearestNavmeshPointBelow(character, origin, querySphereRadius, numberOfSpheres) -> Vector4
```
The `out navmeshPoint` overload is the cleanest "snap my intended point to the nearest valid
navmesh." This is the exact system the native follower behavior uses (see C).

> `NavGenAgentSize` is an enum — use the human/normal member. **Verify its members in NativeDB
> (nativedb.red4ext.com) before coding** — guessed names won't compile.

**Optional clearance double-check** before placing: `SpatialQueriesHelper.HasSpaceInFront(...)`
(box `Overlap` against `n"Static"` + `n"Vehicle"`), the same helper the base game uses for
spawn-fit. Probably overkill if the navmesh point already validated, but it's there.

> Naming note: many "obvious" names (`IsPointOnNavmesh` on the wrong system, `GetPointOnNavmesh`,
> `GetNavmeshPositionInRadius`) **do not exist** — use the exact ones above.

---

## (B) The "ghost for 3 s" power — it's a real, first-class engine feature

Antonia is right that Jackie "phases" out of stuck spots in quests. The mechanism is plain
collision toggling on the puppet (`cyberpunk/NPC/NPCPuppet.swift`):

```
NPCPuppet.DisableCollision() -> Void   // -> AIComponent.DisableCollider() + trace-obstacle off
NPCPuppet.EnableCollision()  -> Void
```
These are the same methods the engine uses for ragdoll / incapacitation. Callable on the puppet
handle from CET Lua: `handle:DisableCollision()` … `handle:EnableCollision()`.

**Pattern:** right after spawn → `DisableCollision()`; ~3 s later → `EnableCollision()`. With
collision off he can't get wedged in geometry while the follow AI walks him onto the navmesh.

(Note: `SetIndividualTimeDilation(...)` also exists on puppets but is *time-scaling*, not
collision — don't confuse the two.)

---

## (C) Teleport him there + make him self-unstick afterwards

**Better than the naive facility teleport:** send an AI teleport command that validates the target.

```
AITeleportCommand (extends AICommand):
    position: Vector4
    rotation: Float    // yaw degrees
    doNavTest: Bool    // <-- TRUE = validate against navmesh before placing
```
`doNavTest = true` is exactly the "don't drop me inside a wall" flag. Send via the AI controller
(`puppet:GetAIControllerComponent():SendCommand(cmd)` pattern, same as AMM's follow command).

**Companion follow already gives free catch-up teleporting.** When Jackie is made a companion,
AMM assigns `AIFollowerRole`, and the game's native follower behavior tree runs
`FollowerFindTeleportPositionAroundTarget` — it finds a navmesh point behind the player and
teleports the follower when he falls behind / goes off-navmesh. So once he's following, he
self-corrects. Also, the follow command itself has a lever:

```
AIFollowTargetCommand: ... teleport: Bool   // true -> command teleports him to keep up
```

---

## Recommended arrival recipe (smallest viable, for the programming instance)

Replace the "blind 18 m forward + naive facility teleport" with:

1. Compute a forward point ~18 m ahead of V (existing `arrivalPoint()` logic is fine as the
   *candidate*).
2. **Project it to navmesh:** `NavigationSystem:FindNavmeshPointAwayFromReferencePoint(candidate,
   playerPos, 18, agentSize, out dest)`. If `false`, retry candidate at V-facing ±90° / 180° /
   smaller distance. Only proceed with a validated `dest`.
3. `ammSpawn(1)` (companion).
4. On the puppet handle: `DisableCollision()`.
5. Move him to `dest`: either `AITeleportCommand{ position=dest, doNavTest=true }` via the AI
   controller, **or** the existing facility `Teleport` (safe now, because `dest` is already
   navmesh-validated).
6. Companion role (AMM already sets `AIFollowerRole`) → he walks in and self-unsticks via the
   native follower teleport.
7. After 3 s (Cron or the existing `JL.clock` timer): `EnableCollision()`.

Net effect: he spawns on walkable ground, can't wedge during the walk-in, and the follower AI
catches him up if anything still goes wrong. This directly reuses the game's own systems
(navmesh + `AITeleportCommand.doNavTest` + follower role + the engine's own collision toggle)
rather than rolling anything custom.

### Caveats
- Verify `NavGenAgentSize` enum members + the `AITeleportCommand` / nav method names live in the
  CET console on 2.3 (RTTI is stable across 2.x but pinning a patch warrants a check).
- `GetTeleportationFacility():Teleport` has **no** nav flag — only safe once the point is
  pre-validated. This is the single most important distinction in all of this.

## Sources
- Decompiled scripts (authoritative): https://codeberg.org/adamsmasher/cyberpunk
  — `core/systems/navigationSystem.swift`, `core/systems/spatialQueriesSystem.swift`,
  `cyberpunk/ai/aiNavigationSystem.swift`, `cyberpunk/NPC/NPCPuppet.swift`,
  `cyberpunk/ai/Tasks/FollowerTasks.swift`, `orphans.swift` (`AITeleportCommand`,
  `AIFollowTargetCommand`, `TeleportationFacility`).
- AMM source (reference spawn/follow): https://github.com/MaximiliumM/appearancemenumod
  — `Modules/spawn.lua`, `Modules/util.lua`, `init.lua`.
- NativeDB (enum/arg verification): https://nativedb.red4ext.com
